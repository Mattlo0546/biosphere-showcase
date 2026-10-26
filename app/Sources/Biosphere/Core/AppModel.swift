import AppKit
import Observation
import UserNotifications

@MainActor
@Observable
final class AppModel {
    var biology: Bank?
    var maths: Bank?                       // nil until the Maths bank ships
    var business: BusinessBank?
    var economics: BusinessBank?           // same engine as Business (see CaseSubject)
    var businessPracticeRequest: BusinessPracticeScope?
    var businessAnnotating: Set<String> = []
    var businessAnnotationErrors: [String: String] = [:]
    var businessRequest: BusinessSet?      // drives the Business "timed or not?" sheet
    var loadError: String?
    var progress = ProgressStore.load()
    var sessions: [StudySession] = []
    var settings = AppSettings.load()
    var claude = ClaudeCLI.Status(installed: false, loggedIn: false, email: nil, path: nil)
    var checkedClaude = false
    var toast: String?
    var markingLog: [String: [String]] = [:]     // session id -> progress lines
    var planning = false
    var selection: SidebarItem? = .revise
    var openSession: String?
    var timeRequest: RevisionScope?        // drives the "how long have you got?" sheet
    var timeRequestMode: StudyMode = .smart
    var mix: SubtopicMix?                  // Topics page is in pick-and-mix mode
    let timer = StudyTimer()
    let exam = ExamCoach()
    let chat = HankChat()
    let permissions = Permissions()
    let updater = Updater()
    let biologyPack = PaperPack(slug: Subject.biology.slug)
    let mathsPack = PaperPack(slug: Subject.maths.slug)
    var resultsVisible = false

    /// The question bank on screen: Biology or Maths, whichever she last picked on the Topics page
    /// (Business has its own bank). The Topics page, time sheet and Tracker all read this one.
    var bank: Bank? { Subject.current == .maths ? maths : biology }
    var pack: PaperPack { Subject.current == .maths ? mathsPack : biologyPack }

    /// The bank a session's questions come from.
    func bank(for s: StudySession) -> Bank? { s.isMaths ? maths : biology }
    func pack(for bank: Bank) -> PaperPack { bank.slug == mathsPack.slug ? mathsPack : biologyPack }

    /// Opens "How long have you got?" in the subject a session belongs to (results can be from either bank).
    func revise(_ scope: RevisionScope, like s: StudySession) {
        if !s.isCasePaper { UserDefaults.standard.set((s.isMaths ? Subject.maths : .biology).rawValue, forKey: "subject") }
        timeRequest = scope
    }

    func writeSummaries() {
        for b in [biology, maths].compactMap({ $0 }) { progress.writeSummary(bank: b) }
    }

    enum SidebarItem: Hashable { case exam, revise, sessions, tracker, settings }

    private var poller: Timer?
    private var knownInbox: Set<String> = []

    init(previewBusiness: BusinessBank? = nil, previewEconomics: BusinessBank? = nil) {
        if previewBusiness != nil || previewEconomics != nil {
            business = previewBusiness
            economics = previewEconomics
            return
        }
        do {
            try Workspace.prepare()
            biology = try Bank(slug: Subject.biology.slug)
            maths = try? Bank(slug: Subject.maths.slug)
            biologyPack.refresh(); mathsPack.refresh()   // the packs were made before prepare() updated pack.json
        } catch {
            loadError = "Couldn't load the question bank: \(error.localizedDescription)"
        }
        business = try? BusinessBank.load()
        economics = try? BusinessBank.load(.economics)
        reloadSessions()
        writeSummaries()
        // Start watching for returned papers only after the window is up, and list folders off the
        // main thread: reading Downloads can block on macOS's permission prompt.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            let (dl, ic) = self.inboxScope
            let existing = await Task.detached { Self.inboxFiles(downloads: dl, icloud: ic).map(\.path) }.value
            self.knownInbox = Set(existing)
            self.watchedScope = "\(dl)-\(ic)"
            self.poller = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.poll() }
            }
        }
        Task { await refreshClaude() }
        Task { await biologyPack.ensure() }
        Task { if maths != nil { await mathsPack.ensure() } }
        // Check for updates shortly after launch, then every 6 hours while open.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            while let self, !Task.isCancelled {
                await self.updater.check(beta: self.settings.betaUpdates)
                try? await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
            }
        }
    }

    func refreshClaude() async {
        claude = await ClaudeCLI.status()
        checkedClaude = true
    }

    func say(_ s: String) {
        toast = s
        Task { try? await Task.sleep(nanoseconds: 4_500_000_000); if toast == s { toast = nil } }
    }

    // MARK: sessions on disk

    func reloadSessions() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: Workspace.sessions, includingPropertiesForKeys: nil)) ?? []
        sessions = dirs.compactMap { try? JSON.load(StudySession.self, from: $0.appendingPathComponent("session.json")) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ s: StudySession) {
        try? JSON.save(s, to: Workspace.sessionDir(s.id).appendingPathComponent("session.json"))
        if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } else { sessions.insert(s, at: 0) }
    }

    func session(_ id: String) -> StudySession? { sessions.first { $0.id == id } }

    func pdfURL(_ s: StudySession) -> URL {
        let safe = s.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "")
        return Workspace.sessionDir(s.id).appendingPathComponent("Biosphere \(s.id) – \(safe).pdf")
    }
    func completedURL(_ s: StudySession) -> URL { Workspace.sessionDir(s.id).appendingPathComponent("completed.pdf") }
    func results(_ s: StudySession) -> MarkingResult? {
        try? JSON.load(MarkingResult.self, from: Workspace.sessionDir(s.id).appendingPathComponent("results.json"))
    }


    func delete(_ s: StudySession) {
        try? FileManager.default.removeItem(at: Workspace.sessionDir(s.id))
        sessions.removeAll { $0.id == s.id }
        progress.attempts.removeAll { $0.sessionId == s.id }
        progress.save()
        writeSummaries()
    }

    // MARK: building sessions

    func minutes(for q: Question) -> Double { q.isMCQ ? settings.minutesPerMCQ : Double(q.marks) * settings.minutesPerMark }

    @discardableResult
    func createSession(kind: SessionKind, title: String, subtitle: String, scope: [String], questions: [Question],
                       rationale: String? = nil, minutes chosen: Int? = nil, timed: Bool = true, from source: Bank? = nil) -> StudySession? {
        guard let bank = source ?? bank, !questions.isEmpty else { say("No questions available for that yet."); return nil }
        let pack = pack(for: bank)
        guard pack.isReady else {
            if case .downloading(let p) = pack.state { say("The past papers are still downloading (\(Int(p * 100))%). Try again in a moment.") }
            else { say("The past papers aren't downloaded yet. Check the banner on Topics."); Task { await pack.ensure() } }
            return nil
        }
        var s = StudySession(id: StudySession.newID(), title: title, subtitle: subtitle, kind: kind, scope: scope,
                             questionIds: questions.map(\.id), totalMarks: questions.reduce(0) { $0 + $1.marks },
                             minutes: chosen ?? max(5, Int(questions.reduce(0) { $0 + minutes(for: $1) }.rounded())),
                             createdAt: Date(), status: .ready, rationale: rationale)
        if bank.syllabus.isStrategyBank { s.subject = bank.slug }
        let dir = Workspace.sessionDir(s.id)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let out = try PDFComposer.compose(session: s, questions: questions, bank: bank, syllabus: bank.syllabus, to: pdfURL(s))
            s.placements = out.placements
            s.pageCount = out.pageCount
            try JSON.save(Marking.answerKey(for: s, bank: bank), to: dir.appendingPathComponent("answer_key.json"))
            save(s)
            openSession = s.id
            if timed { timer.prepare(s) }
            return s
        } catch PDFComposer.ComposeError.missingPaper {
            // A bank update can name papers the installed pack doesn't have yet: fetch them, don't show the raw error.
            try? FileManager.default.removeItem(at: dir)
            say("Some of the newest past papers aren't downloaded yet. Fetching them now, so try again in a minute.")
            Task { await pack.ensure() }
            return nil
        } catch {
            say("Couldn't build the PDF: \(error.localizedDescription)")
            return nil
        }
    }

    /// Topic first, then time: builds a paper for `scope` that fits `minutes` and loads the timer.
    /// How many questions in a scope are mistakes / due / not yet seen (for the mode picker and badges).
    func reviewCounts(_ scope: RevisionScope, format: QuestionFormat = .both) -> (mistakes: Int, due: Int, unseen: Int, mistakeMinutes: Double, dueMinutes: Double) {
        guard let bank else { return (0, 0, 0, 0, 0) }
        let pool = bank.pool(for: scope, format: format)
        let rev = progress.reviews
        let now = Date()
        let mistakes = pool.filter { rev[$0.id]?.isMistake == true }
        let due = pool.filter { rev[$0.id]?.isDue(now) == true }
        return (mistakes.count, due.count, pool.filter { rev[$0.id] == nil }.count,
                mistakes.reduce(0) { $0 + $1.minutes }, due.reduce(0) { $0 + $1.minutes })
    }

    func build(_ scope: RevisionScope, minutes: Int, everyQuestion: Bool = false, mode: StudyMode = .smart,
               format: QuestionFormat = .both, timed: Bool = true) {
        guard let bank else { return }
        let ids = scope.subtopicIds(in: bank.syllabus)
        let pool = bank.pool(for: scope, format: format)
        var weights: [String: Double] = [:]
        for id in ids {
            switch progress.stats(for: id).mastery {
            case .red: weights[id] = 3
            case .orange: weights[id] = 2
            case .notStarted: weights[id] = 1.5
            case .green: weights[id] = 0.3
            }
        }
        let target = everyQuestion ? 100_000 : Double(minutes)
        let options = Selector.Options(targetMinutes: target, interleave: ids.count > 1, weights: scope.isMixed ? weights : [:])
        let qs = everyQuestion
            ? Selector.pick(from: pool, seen: progress.seen, options: options)
            : Selector.pick(from: pool, reviews: progress.reviews, mode: mode, options: options)
        guard !qs.isEmpty else {
            say(mode == .mistakes ? "No mistakes to redo here. Nice!" : mode == .due ? "Nothing due for review here yet." : "No questions left for that.")
            return
        }
        let base = scope == .everything ? "" : scope.title(in: bank.syllabus)
        let title: String
        switch (everyQuestion, mode) {
        case (true, _): title = base + " — full set"
        case (_, .mistakes): title = base.isEmpty ? "Redo my mistakes" : "Redo mistakes: " + base
        case (_, .due): title = base.isEmpty ? "Spaced review" : "Review: " + base
        default: title = base.isEmpty ? scope.title(in: bank.syllabus) : base
        }
        // Review papers can be shorter than the time chosen if there aren't enough questions.
        let fitted = Int(qs.reduce(0) { $0 + self.minutes(for: $1) }.rounded())
        let finalMinutes = everyQuestion ? nil : (mode == .mistakes || mode == .due ? max(5, min(minutes, fitted)) : minutes)
        let subtitle: String
        switch (everyQuestion, mode) {
        case (true, _): subtitle = "Every past-paper question on this \(bank.syllabus.isStrategyBank ? "strategy" : "subtopic")"
        case (_, .mistakes): subtitle = "\(qs.count) question\(qs.count == 1 ? "" : "s") you lost marks on, worst first"
        case (_, .due): subtitle = "\(qs.count) question\(qs.count == 1 ? "" : "s") due on your review schedule"
        case (_, .fresh): subtitle = "\(minutes)-minute session · new questions only"
        default: subtitle = "\(minutes)-minute session · \(scope.subtitle(in: bank.syllabus))"
        }
        createSession(kind: scope.kind, title: title, subtitle: subtitle + " · " + format.title,
                      scope: Array(ids).sorted(), questions: qs, minutes: finalMinutes, timed: timed)
    }

    /// Same, but Claude (via the build-session skill) chooses the questions.
    func planWithHank(_ scope: RevisionScope, minutes: Int, focus: String, format: QuestionFormat = .both, timed: Bool = true) async {
        guard let bank else { return }
        planning = true
        defer { planning = false }
        progress.writeSummary(bank: bank)
        let ids = scope.subtopicIds(in: bank.syllabus).sorted()
        let scopeText = scope.isMixed && scope != .everything ? "Only use subtopics: \(ids.joined(separator: ", "))." :
            (scope == .everything ? "Any SL subtopic." : "Only use subtopics: \(ids.joined(separator: ", ")).")
        let subjectText = bank.syllabus.isStrategyBank
            ? "Subject: \(bank.syllabus.subject). The bank is bank/\(bank.slug)/ (its subtopics are execution strategies; progress in progress_summary_\(bank.slug).json). "
              + (scope.isExamStyle ? "Use whole questions only (no ids with a part suffix like -c)." : "Prefer drill items (ids ending in a part suffix like -c) for long questions.")
            : ""
        let prompt = """
        Plan a Biosphere revision session of \(minutes) minutes on \(scope.title(in: bank.syllabus)). \(scopeText) \(subjectText)
        \(focus.isEmpty ? "" : "Her request: \(focus)")
        Required question format: \(format.title). \(format.planningInstruction) This takes priority over any conflicting focus request.
        Follow .claude/skills/build-session/SKILL.md, but do NOT write a request file — return the plan as JSON instead.
        """
        do {
            let plan = try await ClaudeCLI.ask(prompt, schema: SessionPlan.schema, model: settings.markingModel, effort: settings.effort, as: SessionPlan.self)
            let qs = try plan.validatedQuestions(from: bank.pool(for: scope, format: format))
            guard !qs.isEmpty else { say("Hank couldn't find suitable questions. Try a different focus."); return }
            createSession(kind: .custom, title: plan.title, subtitle: "Planned by Hank · \(minutes) minutes · \(format.title)",
                          scope: Array(Set(qs.map(\.primary))).sorted(), questions: qs, rationale: plan.rationale, minutes: minutes, timed: timed)
        } catch {
            say("Hank couldn't plan that: \(error.localizedDescription)")
        }
    }

    // MARK: Hank chat

    func openHank(suggestionTitle: String? = nil, prompt: String? = nil) {
        let suggestion = prompt.map { ChatSuggestion(title: suggestionTitle ?? "Explain this question", prompt: $0, context: screenContext()) }
        chat.open(suggestion: suggestion)
    }

    func askHank(_ text: String, context: String? = nil) {
        chat.send(text, context: context ?? screenContext(), model: settings.markingModel, effort: settings.effort)
    }

    /// One line telling Hank what's on her screen.
    func screenContext() -> String {
        var parts: [String] = []
        switch selection ?? .revise {
        case .revise:
            let page = UserDefaults.standard.string(forKey: "subject")
            parts.append(page == Subject.maths.rawValue ? "she is on the Maths strategies page (Maths AA SL, revised by execution strategy)"
                         : CaseSubject.allCases.first { $0.pageKey == page }.map { "she is on the \($0.shortName) questions page" }
                         ?? "she is on the Topics page")
        case .tracker: parts.append("she is looking at her Tracker")
        case .exam:
            let block = exam.pack?.blocks.first { $0.id == exam.selected }
            parts.append("she is on the Exam prep page (her 2-hour Business HL revision plan before her exam)"
                         + (block.map { ", on the \"\($0.title)\" block" } ?? ""))
        case .settings: parts.append("she is in Settings")
        case .sessions:
            if let id = openSession ?? sessions.first?.id, let s = session(id) {
                var d = s.isCasePaper
                    ? "she has \(s.caseSubject?.shortName ?? "Business") session \(s.id) open (\"\(s.title)\", set \(s.businessSetId ?? "mixed topical paper"), status \(s.status.rawValue)"
                    : "she has session \(s.id) open (\"\(s.title)\", \(s.questionIds.count) questions, status \(s.status.rawValue)"
                if let score = s.score { d += ", scored \(score)/\(s.totalMarks)" }
                d += resultsVisible ? ", viewing the marked results)" : ")"
                parts.append(d + "; its files are in sessions/\(s.id)/")
            } else { parts.append("she is on My sessions") }
        }
        if timer.isActive && timer.running { parts.append("a timer is running (\(StudyTimer.format(timer.remaining)) left)") }
        return parts.joined(separator: "; ")
    }

    // MARK: sending + receiving

    var sendingTo: String?      // shown while AirDrop is in flight

    func send(_ s: StudySession) {
        var s = s
        if s.status == .ready { s.status = .sent }
        save(s)
        Task { await sendFile(pdfURL(s)) }
    }

    func screenshot() {
        Task {
            guard let file = await Sharing.captureScreenshot() else { say("Screenshot cancelled."); return }
            await sendFile(file)
        }
    }

    /// One click: AirDrop straight to her saved iPad (or iCloud Drive if that's her choice).
    func sendFile(_ url: URL) async {
        if settings.sendMethod == .icloud { say(Sharing.copyToICloud(url)); return }
        let device = settings.ipadName
        sendingTo = device.isEmpty ? "your iPad" : device
        let outcome = await AirDropAuto.send(url, to: device) { [weak self] ok in
            Task { @MainActor in
                self?.sendingTo = nil
                self?.say(ok ? "Sent to \(device.isEmpty ? "your iPad" : device) ✓" : "AirDrop didn't go through. Try again with your iPad unlocked.")
            }
        }
        switch outcome {
        case .sending(let name): say("Sending to \(name)…")
        case .manual(let msg): sendingTo = nil; say(msg)
        }
    }

    /// Only look in Downloads while a paper is out being answered, and in iCloud Drive only if she sends
    /// that way — so macOS doesn't ask for folder access before it's actually needed.
    var inboxScope: (downloads: Bool, icloud: Bool) {
        let waiting = sessions.contains { $0.status == .sent || $0.status == .ready }
        return (settings.watchDownloads && waiting, settings.sendMethod == .icloud && waiting)
    }

    nonisolated static func inboxFiles(downloads: Bool, icloud: Bool) -> [URL] {
        var dirs: [URL] = []
        if icloud { dirs.append(Workspace.iCloudRoot.appendingPathComponent("Done")) }
        if downloads { dirs.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")) }
        return dirs.flatMap { d in
            ((try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "pdf" }
        }
    }

    private var polling = false
    private var watchedScope = ""

    private func poll() async {
        guard !polling else { return }
        polling = true
        defer { polling = false }
        // PDFs coming back from the iPad (AirDrop lands in Downloads).
        let (dl, ic) = inboxScope
        let files = await Task.detached { Self.inboxFiles(downloads: dl, icloud: ic) }.value
        if watchedScope != "\(dl)-\(ic)" {
            // Just started watching a folder: whatever is already there isn't a returned paper.
            watchedScope = "\(dl)-\(ic)"
            knownInbox.formUnion(files.map(\.path))
        }
        for url in files where !knownInbox.contains(url.path) {
            knownInbox.insert(url.path)
            guard let id = Marking.sessionId(in: url), let s = session(id), s.status != .marked, s.status != .marking else { continue }
            importCompleted(url, into: s)
        }
        // Session requests written by Claude's build-session skill in the Hank terminal.
        let reqs = (try? FileManager.default.contentsOfDirectory(at: Workspace.requests, includingPropertiesForKeys: nil)) ?? []
        for r in reqs where r.pathExtension == "json" {
            handleRequest(r)
        }
    }

    struct Request: Codable { var title: String; var minutes: Int?; var questionIds: [String]; var rationale: String? }

    private func handleRequest(_ url: URL) {
        let done = Workspace.requests.appendingPathComponent("done")
        try? FileManager.default.createDirectory(at: done, withIntermediateDirectories: true)
        defer { try? FileManager.default.moveItem(at: url, to: done.appendingPathComponent(url.lastPathComponent)) }
        guard let req = try? JSON.load(Request.self, from: url),
              let bank = [biology, maths].compactMap({ $0 }).first(where: { b in req.questionIds.contains { b.question($0) != nil } })
        else { return }
        let qs = req.questionIds.compactMap { bank.question($0) }
        if let s = createSession(kind: .custom, title: req.title, subtitle: "Planned by Hank\(req.minutes.map { " · \($0) minutes" } ?? "")",
                                 scope: Array(Set(qs.map(\.primary))).sorted(), questions: qs, rationale: req.rationale,
                                 minutes: req.minutes, from: bank) {
            selection = .sessions
            notify("New session ready", "\(s.title) — \(s.questionIds.count) questions")
        }
    }

    func importCompleted(_ url: URL, into s: StudySession) {
        var s = s
        do {
            let dest = completedURL(s)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            s.status = .completed
            s.completedAt = Date()
            if timer.sessionId == s.id { s.timeSpentSeconds = timer.elapsed; timer.stop() }
            save(s)
            notify("Got your paper back", "Hank is marking \(s.title)…")
            Task { await mark(s) }
        } catch {
            say("Couldn't import that PDF: \(error.localizedDescription)")
        }
    }

    // MARK: marking

    func mark(_ session: StudySession) async {
        if session.isCasePaper { await markBusiness(session); return }
        guard let bank = bank(for: session) else { return }
        var s = session
        s.status = .marking; s.error = nil
        save(s)
        markingLog[s.id] = ["Opening your paper…"]
        let dir = Workspace.sessionDir(s.id)
        do {
            let completed = completedURL(s)
            let pages = try await Task.detached { try Marking.renderPages(of: completed, into: dir.appendingPathComponent("pages")) }.value
            try JSON.save(Marking.answerKey(for: s, bank: bank), to: dir.appendingPathComponent("answer_key.json"))
            progress.writeSummary(bank: bank)
            markingLog[s.id, default: []].append("\(pages) pages scanned. Reading your handwriting…")
            let result = try await readAndMark(s, bank: bank)
            try JSON.save(result, to: dir.appendingPathComponent("results.json"))
            progress.record(result, session: s, bank: bank)
            progress.writeSummary(bank: bank)
            s.status = .marked
            s.score = result.awarded
            s.markedAt = Date()
            save(s)
            notify("Marked: \(result.awarded)/\(result.available)", result.headline)
        } catch {
            s.status = .failed
            s.error = error.localizedDescription
            save(s)
            markingLog[s.id, default: []].append("Something went wrong: \(error.localizedDescription)")
        }
    }

    // MARK: Business and Economics (one engine; the set's id says which subject)

    func caseBank(_ subject: CaseSubject?) -> BusinessBank? { subject == .economics ? economics : business }

    @discardableResult
    func createBusinessSession(_ set: BusinessSet, timed: Bool) -> StudySession? {
        guard !set.parts.isEmpty, set.parts.allSatisfy({ !$0.markscheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            say("This question needs its original markscheme repaired before you can practise it.")
            return nil
        }
        let subject = set.subject
        var s = StudySession(id: StudySession.newID(), title: set.title,
                             subtitle: "\(subject.name) · \(set.sourceLabel)",
                             kind: .custom, scope: set.topics, questionIds: [], totalMarks: set.marks, minutes: set.minutes,
                             createdAt: Date(), status: .ready)
        s.subject = subject.slug; s.businessSetId = set.id
        s.businessPartLabels = set.selectedLabels
        s.businessTopicId = set.selectedTopicId
        if let topic = set.selectedTopicId.flatMap({ caseBank(subject)?.topic($0) }) {
            s.subtitle = "\(subject.name) · \(topic.displayName) · \(set.sourceLabel)"
        }
        let dir = Workspace.sessionDir(s.id)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let out = try BusinessComposer.compose(session: s, set: set, to: pdfURL(s))
            s.pageCount = out.pageCount
            s.answerPages = out.answerPages
            try JSON.save(businessKey(s, set), to: dir.appendingPathComponent("business.json"))
            save(s)
            openSession = s.id
            if timed { timer.prepare(s) }
            return s
        } catch {
            say("Couldn't build the PDF: \(error.localizedDescription)")
            return nil
        }
    }

    func businessKey(_ s: StudySession, _ b: BusinessSet) -> BusinessKey {
        let subject = s.caseSubject ?? b.subject
        return BusinessKey(sessionId: s.id, id: b.id, session: b.session, paper: b.paper, company: b.company, marks: b.marks,
                    writesInPaper: b.writesInPaper, answerPages: s.answerPages ?? [],
                    parts: b.parts.map { var p = $0; p.msRegions = nil; return p },   // crops are for her screen, not Hank
                    currentSyllabus: b.currentSyllabus, selectedLabels: b.selectedLabels,
                    caseFile: s.businessComponents == nil ? subject.caseFile(b.id) : nil, markbands: b.markbands,
                    sources: s.businessComponents.flatMap { components in
                        guard let bank = caseBank(subject) else { return nil }
                        return BusinessMixedPaper.sources(BusinessPracticePlanner.selectedSets(bank: bank, components: components))
                    },
                    subject: subject == .business ? nil : subject.slug)
    }

    func businessSet(for session: StudySession) -> BusinessSet? {
        let bank = caseBank(session.caseSubject)
        if let components = session.businessComponents, let bank {
            let sets = BusinessPracticePlanner.selectedSets(bank: bank, components: components)
            guard sets.count == components.count else { return nil }
            return BusinessMixedPaper.combined(session: session, sets: sets)
        }
        guard let set = bank?.set(session.businessSetId ?? "") else { return nil }
        if let labels = session.businessPartLabels {
            guard var focused = set.selecting(labels: labels) else { return nil }
            focused.selectedTopicId = session.businessTopicId
            return focused
        }
        return set
    }

    func businessResults(_ s: StudySession) -> BusinessResult? {
        try? JSON.load(BusinessResult.self, from: Workspace.sessionDir(s.id).appendingPathComponent("business_results.json"))
    }

    /// Her marked attempts at one set, newest first.
    func attempts(at set: BusinessSet) -> [StudySession] {
        sessions.filter { $0.businessSetId == set.id && $0.status == .marked &&
            $0.businessPartLabels == set.selectedLabels }
    }

    func markBusiness(_ session: StudySession) async {
        var s = session
        guard let set = businessSet(for: s) else {
            s.status = .failed; s.error = "This question isn't in the bank any more."; save(s); return
        }
        s.status = .marking; s.error = nil
        save(s)
        markingLog[s.id] = ["Opening your paper…"]
        let dir = Workspace.sessionDir(s.id)
        do {
            let completed = completedURL(s)
            let total = try await Task.detached { try Marking.renderPages(of: completed, into: dir.appendingPathComponent("pages")) }.value
            // Only the pages with her answers go to Hank (not the guide page or, on P1/P3, the case).
            let wanted = (s.answerPages ?? []).filter { $0 <= total }
            let pages = wanted.isEmpty ? Array(1...max(total, 1)) : wanted
            s.answerPages = pages
            for i in 1...max(total, 1) where !pages.contains(i) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(String(format: "pages/page-%02d.png", i)))
            }
            try JSON.save(businessKey(s, set), to: dir.appendingPathComponent("business.json"))
            writeBusinessHistory(s.caseSubject ?? .business)
            markingLog[s.id, default: []].append("\(pages.count) page\(pages.count == 1 ? "" : "s") scanned. Reading your handwriting…")
            let result = try await readAndMark(s, key: businessKey(s, set))
            try BusinessMarking.validate(result, key: businessKey(s, set))
            try JSON.save(result, to: dir.appendingPathComponent("business_results.json"))
            if result.essays.flatMap(\.sentences).contains(where: { !($0.anchors ?? []).isEmpty }) {
                try BusinessAnnotations.write(result: result, source: completed, to: annotatedBusinessURL(s))
            }
            s.status = .marked
            s.score = result.awarded
            s.totalMarks = result.available
            s.markedAt = Date()
            save(s)
            writeBusinessHistory(s.caseSubject ?? .business)
            notify("Marked: \(result.awarded)/\(result.available)", result.headline)
        } catch {
            s.status = .failed
            s.error = error.localizedDescription
            save(s)
            markingLog[s.id, default: []].append("Something went wrong: \(error.localizedDescription)")
        }
    }

    /// Rebuilt from every marked session of that subject so Hank can spot habits (e.g. "explains without using the case").
    func writeBusinessHistory(_ subject: CaseSubject = .business) {
        let entries: [BusinessHistoryEntry] = sessions.filter { $0.caseSubject == subject && $0.status == .marked }.compactMap { s in
            guard let r = businessResults(s), let set = businessSet(for: s) else { return nil }
            var lost: [String: Int] = [:]
            for p in r.parts {
                let topic = set.parts.first { $0.label == p.label }?.topic ?? "other"
                lost[topic, default: 0] += p.available - p.awarded
            }
            return BusinessHistoryEntry(sessionId: s.id, setId: set.id, date: s.markedAt ?? s.createdAt, company: set.company,
                                        awarded: r.awarded, available: r.available, lostByTopic: lost,
                                        capsHit: r.essays.flatMap(\.capsHit), fixes: r.fixes.map(\.title))
        }.sorted { $0.date < $1.date }
        try? JSON.save(entries, to: Workspace.root.appendingPathComponent(subject.historyFile))
    }

    // MARK: sorting My sessions

    func subjectName(_ s: StudySession) -> String { s.caseSubject?.name ?? (s.isMaths ? "Maths AA SL" : "Biology SL") }

    /// What the session was about, for sorting and grouping My sessions.
    func topicName(_ s: StudySession) -> String {
        if let subject = s.caseSubject {
            let bank = caseBank(subject)
            if let id = s.businessTopicId, let topic = bank?.topic(id) { return topic.displayName }
            if s.businessComponents != nil { return s.title }
            let set = businessSet(for: s)
            return set?.topics.first.flatMap { bank?.topic($0)?.name } ?? subject.shortName
        }
        guard let syl = bank(for: s)?.syllabus, !s.scope.isEmpty else { return "Mixed" }
        if s.scope.count == 1, let sub = syl.subtopic(s.scope[0]) { return syl.isStrategyBank ? sub.name : "\(sub.id) \(sub.name)" }
        let topics = Set(s.scope.map(Syllabus.topicId))
        if topics.count == 1, let t = topics.first {
            let name = syl.allSubtopics.first { $0.id.hasPrefix(t + ".") }?.level ?? ""
            return syl.isStrategyBank ? name : "\(t) " + name
        }
        return "Mixed"
    }

    func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        say("\(title) — \(body)")
    }
}

/// Countdown timer for a session.
@MainActor
@Observable
final class StudyTimer {
    var sessionId: String?
    var title = ""
    var total = 0
    var remaining = 0
    var running = false
    var elapsed: Int { total - remaining }
    private var ticker: Timer?

    var isActive: Bool { sessionId != nil }
    var isFresh: Bool { !running && remaining == total }

    /// Loads the session's time without starting — she presses Start when she sits down.
    func prepare(_ s: StudySession) {
        if running && sessionId != s.id { return }   // don't clobber a timer that's already ticking
        pause()
        sessionId = s.id; title = s.title
        total = s.minutes * 60; remaining = total
    }

    func start(_ s: StudySession) {
        if sessionId != s.id || total == 0 { prepare(s) }
        resume()
    }

    func resume() {
        running = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() { running = false; ticker?.invalidate() }

    func stop() { pause(); sessionId = nil; remaining = 0; total = 0 }

    func add(minutes: Int) { remaining += minutes * 60; total += minutes * 60 }

    private func tick() {
        guard running else { return }
        remaining -= 1
        if remaining == 0 {
            NSSound(named: "Glass")?.play()
            let c = UNMutableNotificationContent()
            c.title = "Time's up"; c.sound = .default
            c.body = sessionId == ExamCoach.timerId ? "That's your two hours. Rest up, you've got this." : "\(title) — pens down. Send it back when you're ready."
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }

    static func format(_ seconds: Int) -> String {
        let s = abs(seconds)
        return (seconds < 0 ? "+" : "") + String(format: "%d:%02d", s / 60, s % 60)
    }
}
