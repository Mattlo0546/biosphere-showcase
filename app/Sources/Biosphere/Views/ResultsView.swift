import SwiftUI

struct ResultsView: View {
    enum QuestionFilter: Hashable { case all, review, starred, fix }
    @Environment(AppModel.self) var model
    var session: StudySession
    var result: MarkingResult
    var back: () -> Void
    @State private var filter: QuestionFilter = .review
    @State private var focus: Set<Int> = []
    @State private var focusTitle = ""
    @AppStorage("results.imageWidth") private var imageWidth: Double = 1.0
    @State private var reading: BiologyReading?
    var bank: Bank? { model.bank(for: session) }
    var strategies: Bool { bank?.syllabus.isStrategyBank == true }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button { model.resultsVisible = false; back() } label: { Label("Paper & actions", systemImage: "chevron.left") }.buttonStyle(GhostButtonStyle(compact: true))
                    Spacer()
                }
                header
                fixesSection
                HStack(alignment: .top, spacing: 16) {
                    bySubtopic
                    wins
                }
                questionsHeader
                ForEach(shownQuestions) { q in
                    QuestionResultCard(session: session, result: q, imageScale: imageWidth, reading: reading)
                }
            }
            .padding(.horizontal, 30).padding(.top, 52).padding(.bottom, 40)
            .frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .onAppear {
            model.resultsVisible = true
            if result.reviewQuestions.isEmpty { filter = .all }
            // Maths transcripts know which of her lines answer each part (older ones don't: they show text).
            reading = try? JSON.load(BiologyReading.self, from: Workspace.sessionDir(session.id).appendingPathComponent("transcript.json"))
        }
        .onDisappear { model.resultsVisible = false }
    }

    var shownQuestions: [QuestionResult] {
        switch filter {
        case .review: result.reviewQuestions
        case .starred: result.uncertainQuestions
        case .fix: result.questions.filter { focus.contains($0.number) }
        case .all: result.questions
        }
    }

    static func color(_ pct: Double) -> Color { pct >= 0.75 ? Palette.green : pct >= 0.5 ? Palette.orange : Palette.red }

    // MARK: header — ring, one-line headline, stat pills

    var header: some View {
        let pct = Double(result.awarded) / Double(max(result.available, 1))
        let color = Self.color(pct)
        let qs = result.questions.compactMap { r in bank?.question(r.questionId).map { (r, $0) } }
        let mcq = qs.filter { $0.1.isMCQ }, written = qs.filter { !$0.1.isMCQ }
        return Card(padding: 20) {
            HStack(alignment: .center, spacing: 24) {
                ZStack {
                    Circle().stroke(Palette.empty, lineWidth: 11)
                    Circle().trim(from: 0, to: pct).stroke(color, style: StrokeStyle(lineWidth: 11, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Text("\(result.awarded)").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                        Text("of \(result.available)").font(.system(size: 12)).foregroundStyle(Palette.dim)
                    }
                }
                .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 10) {
                    Text(session.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.violet)
                    HStack(alignment: .center, spacing: 10) {
                        HankAvatar(size: 32)
                        Text(result.headline).font(.system(size: 19, weight: .bold)).foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        pill("\(Int((pct * 100).rounded()))%", "score", color)
                        if !mcq.isEmpty { pill("\(mcq.reduce(0) { $0 + $1.0.awarded })/\(mcq.count)", "multiple choice", Palette.purple) }
                        if !written.isEmpty { pill("\(written.reduce(0) { $0 + $1.0.awarded })/\(written.reduce(0) { $0 + $1.0.available })", "written", Palette.purple) }
                        if let t = session.timeSpentSeconds { pill("\(t / 60) min", "of \(session.minutes) suggested", Palette.dim) }
                    }
                    if !result.uncertainQuestions.isEmpty {
                        Button { withAnimation(.snappy) { filter = .review } } label: {
                            Label("\(result.uncertainQuestions.count) starred as unsure · included in your review", systemImage: "star.fill")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    func pill(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Palette.dim)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Palette.bg2, in: Capsule())
    }

    // MARK: fix cards

    var fixes: [Fix] {
        if let f = result.fixes, !f.isEmpty { return Array(f.prefix(3)) }
        // Older results: build simple cards from the questions that lost the most marks.
        return result.questions.filter { $0.awarded < $0.available && !$0.whyLost.isEmpty }
            .sorted { ($0.available - $0.awarded) > ($1.available - $1.awarded) }
            .prefix(3)
            .map { Fix(title: $0.concept.isEmpty ? "Question \($0.number)" : $0.concept, detail: $0.tip.isEmpty ? $0.whyLost : $0.tip,
                       wrong: nil, right: nil, subtopic: $0.subtopic, questions: [$0.number]) }
    }

    @ViewBuilder var fixesSection: some View {
        if !fixes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars").foregroundStyle(Palette.purple)
                    Text("Fix these to win back marks").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text)
                }
                // One column per fix (max 3), so the cards always span the full width.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 220), spacing: 12, alignment: .top),
                                         count: max(1, min(3, fixes.count))), spacing: 12) {
                    ForEach(Array(fixes.enumerated()), id: \.offset) { i, f in fixCard(i + 1, f) }
                }
            }
        }
    }

    func fixCard(_ n: Int, _ f: Fix) -> some View {
        let qs = f.questions ?? []
        let selected = filter == .fix && focus == Set(qs)
        return Button {
            withAnimation(.snappy) {
                if selected { filter = .review } else { focus = Set(qs); focusTitle = f.title; filter = .fix }
            }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text("\(n)").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(Palette.gradient, in: Circle())
                    Text(f.title).font(.system(size: 14.5, weight: .bold)).foregroundStyle(Palette.text)
                        .multilineTextAlignment(.leading)
                }
                Text(f.detail).font(.system(size: 12.5)).foregroundStyle(Palette.dim)
                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                if let w = f.wrong, !w.isEmpty, let r = f.right, !r.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.red).padding(.top, 3)
                            Text(w).font(.system(size: 12.5)).foregroundStyle(Palette.text).strikethrough(color: Palette.red.opacity(0.6))
                                .multilineTextAlignment(.leading)
                        }
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.green).padding(.top, 3)
                            Text(r).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text).multilineTextAlignment(.leading)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 10))
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if let s = f.subtopic, !s.isEmpty { Chip(text: s, color: Palette.purple) }
                    ForEach(qs, id: \.self) { q in Chip(text: "Q\(q)", color: Palette.dim) }
                    Spacer()
                    if !qs.isEmpty {
                        Text(selected ? "Showing ✓" : "Show").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.purple)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Palette.purple : Palette.stroke, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: marks by subtopic + wins

    var bySubtopic: some View {
        var rows: [(id: String, got: Int, of: Int)] = []
        for q in result.questions {
            let id = bank?.question(q.questionId)?.primary ?? q.subtopic
            if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].got += q.awarded; rows[i].of += q.available }
            else { rows.append((id, q.awarded, q.available)) }
        }
        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(strategies ? "Marks by strategy" : "Marks by subtopic").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                ForEach(rows, id: \.id) { r in
                    let pct = Double(r.got) / Double(max(r.of, 1))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if !strategies { Text(r.id).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Palette.lilac) }
                            Text(bank?.syllabus.subtopic(r.id)?.name ?? "").font(.system(size: 12)).foregroundStyle(Palette.text).lineLimit(1)
                            Spacer()
                            Text("\(r.got)/\(r.of)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Self.color(pct))
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.empty)
                                Capsule().fill(Self.color(pct)).frame(width: max(6, g.size.width * pct))
                            }
                        }.frame(height: 7)
                    }
                }
                if !result.focusNext.isEmpty {
                    HStack(spacing: 6) {
                        Text("Revise next:").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.dim)
                        ForEach(result.focusNext.prefix(3), id: \.self) { f in
                            let id = String(f.prefix(while: { $0 != ":" && $0 != " " }))
                            if let sub = bank?.syllabus.subtopic(id) {
                                Button { model.revise(.subtopic(sub.id), like: session) } label: { Chip(text: "\(strategies ? sub.name : sub.id) ↗", color: Palette.orange) }
                                    .buttonStyle(.plain).help("Make a paper on \(sub.name)")
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    var wins: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("What went well").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                ForEach(result.strengths.prefix(3), id: \.self) { s in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green)
                        Text(s).font(.system(size: 12.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !result.summary.isEmpty {
                    Text(result.summary).font(.system(size: 12)).foregroundStyle(Palette.dim).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: question list header (filter + image size)

    var questionsHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(filter == .fix ? "Questions for: \(focusTitle)" : filter == .review ? "Questions to review" : "Question by question")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(Palette.text).lineLimit(1)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "photo").font(.system(size: 11)).foregroundStyle(Palette.faint)
                    Slider(value: $imageWidth, in: 0.6...1.6).frame(width: 110).tint(Palette.purple)
                    Image(systemName: "photo").font(.system(size: 15)).foregroundStyle(Palette.faint)
                }
                .help("Make the question and handwriting images bigger or smaller")
            }
            Picker("Questions", selection: $filter) {
                Text("All").tag(QuestionFilter.all)
                Text("To review (\(result.reviewQuestions.count))").tag(QuestionFilter.review)
                if !result.uncertainQuestions.isEmpty { Text("Starred").tag(QuestionFilter.starred) }
                if filter == .fix { Text("This fix").tag(QuestionFilter.fix) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 400, alignment: .leading)
            if filter == .review {
                Text("Questions that lost marks and answers you starred as unsure, including correct ones.")
                    .font(.system(size: 12)).foregroundStyle(Palette.dim)
            }
        }
    }
}

struct QuestionResultCard: View {
    @Environment(AppModel.self) var model
    var session: StudySession
    var result: QuestionResult
    var imageScale: Double = 1
    var reading: BiologyReading? = nil
    @State var open = false
    @State private var showWorking = false
    @State private var showFullMarkscheme = false
    @State private var zoom: ZoomTarget?
    var bank: Bank? { model.bank(for: session) }

    var body: some View {
        let q = bank?.question(result.questionId)
        let sub = bank?.syllabus.subtopic(q?.primary ?? result.subtopic)
        let full = result.awarded >= result.available
        let color = full ? Palette.green : (result.awarded == 0 ? Palette.red : Palette.orange)
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("Q\(result.number)").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .frame(width: 42, height: 32).background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(q?.title.isEmpty == false ? q!.title : result.concept).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Palette.text)
                        Text("\(sub.map { bank?.syllabus.isStrategyBank == true ? $0.name : "\($0.id) \($0.name)" } ?? result.subtopic) · \(q?.sourceLabel ?? "")")
                            .font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                    }
                    Spacer()
                    if result.isUncertain {
                        Label("Unsure", systemImage: "star.fill")
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.orange)
                            .help("You starred this question for review")
                    }
                    Text("\(result.awarded)/\(result.available)").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(color)
                    Image(systemName: "chevron.down").rotationEffect(.degrees(open ? 0 : -90)).foregroundStyle(Palette.dim)
                }
                .padding(14)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { open.toggle() } }

                if !open && !result.whyLost.isEmpty {
                    Text(result.whyLost).font(.system(size: 12.5)).foregroundStyle(Palette.dim).lineLimit(2)
                        .padding(.horizontal, 14).padding(.bottom, 14)
                }

                if open { detail(q: q, sub: sub) }
            }
        }
    }

    /// Maths: which move each part needed and the words that gave it away, so she learns to spot it.
    func moves(_ q: Question, _ syl: Syllabus) -> some View {
        let parts = q.parts.filter { $0.subtopic != nil }
        return VStack(alignment: .leading, spacing: 6) {
            label("The move")
            ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                if let m = syl.subtopic(p.subtopic!) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !p.label.isEmpty { Text(p.label).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Palette.lilac) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
                            if let cue = p.cue { Text("Spotted by: “\(cue)”").font(.system(size: 11.5)).foregroundStyle(Palette.dim) }
                        }
                        Spacer()
                        Button("Drill it") { model.revise(.subtopic(m.id), like: session) }
                            .buttonStyle(GhostButtonStyle(compact: true)).help("Make a paper of \(m.name) questions")
                    }
                }
            }
        }
        .padding(12)
        .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder func detail(q: Question?, sub: Subtopic?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            let isMCQ = q?.isMCQ == true
            let side = !isMCQ && imageScale <= 1.05
            let layout = side ? AnyLayout(HStackLayout(alignment: .top, spacing: 14)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            layout {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { label("The question"); Spacer(); zoomHint }
                    if let q, let bank = bank {
                        VStack(spacing: 2) {
                            ForEach(Array(q.regions.prefix(3).enumerated()), id: \.offset) { _, r in
                                PDFCropImage(url: bank.paperURL(q.paperId), page: r.page,
                                             rectFromTop: CGRect(x: r.x0, y: r.y0, width: r.x1 - r.x0, height: r.y1 - r.y0), width: 1400)
                            }
                        }
                        .background(.white).clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.stroke))
                        .frame(maxWidth: side ? .infinity : 900 * imageScale)
                        .onTapGesture { zoom = ZoomTarget(url: bank.paperURL(q.paperId), page: q.regions.first?.page ?? 0, title: "Q\(result.number) · the question") }
                        .help("Click to open full size and zoom")
                    }
                }
                if !isMCQ {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { label("What you wrote"); Spacer(); zoomHint }
                        submittedAnswerImage(side: side)
                    }
                }
            }
            .frame(maxHeight: side ? 520 * imageScale : nil)

            let msURL = q.flatMap { bank?.markschemeURL($0.paperId) }
            VStack(spacing: 8) {
                ForEach(Array(result.parts.enumerated()), id: \.offset) { _, p in
                    partRow(p, markscheme: msURL.flatMap { url in q?.part(labelled: p.label)?.msRegions.map { (url, $0) } })
                }
            }
            if let q, let msURL, let whole = q.msRegions, !whole.isEmpty { fullMarkscheme(q, msURL, whole) }

            if let q, let syl = bank?.syllabus, syl.isStrategyBank { moves(q, syl) }

            if isMCQ, !(session.placements[result.questionId] ?? []).isEmpty {
                DisclosureGroup(isExpanded: $showWorking) {
                    submittedAnswerImage(side: false, title: "your working")
                        .padding(.top, 6)
                } label: {
                    Label("View your working", systemImage: "pencil.and.outline")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.purple)
                }
                .tint(Palette.purple)
            }

            if result.isUncertain {
                note("You starred this question", result.awarded >= result.available
                     ? "You got this right, but marked it as unsure. Revisit the explanation to feel confident next time."
                     : "You marked this as unsure. Review the answer and explanation below with Hank.", "star.fill", Palette.orange)
            }
            if !result.whyLost.isEmpty { note("Why you lost marks", result.whyLost, "exclamationmark.bubble.fill", Palette.orange) }
            note("The bigger picture", result.bigPicture, "globe.europe.africa.fill", Palette.violet)
            if !result.tip.isEmpty { note("Next time", result.tip, "lightbulb.fill", Palette.green) }

            HStack(spacing: 10) {
                if let sub, let url = URL(string: sub.notesUrl) {
                    Link(destination: url) { Label("Read \(sub.id) \(sub.name) on Biology for Life", systemImage: "book.fill") }
                        .buttonStyle(GhostButtonStyle(compact: true))
                }
                Button {
                    let uncertainty = result.isUncertain ? " I starred it because I was unsure; help me understand the answer and feel confident about it." : ""
                    model.openHank(suggestionTitle: "Explain Q\(result.number) from this paper",
                                   prompt: "Can you go through question \(result.number) with me? I got \(result.awarded)/\(result.available). Explain the answer and what earns the marks.\(uncertainty)")
                } label: { Label("Ask Hank about this", systemImage: "bubble.left.fill") }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 16)
        .sheet(item: $zoom) { z in ZoomSheet(target: z) }
    }

    func submittedAnswerImage(side: Bool, title: String = "your answer") -> some View {
        let placements = session.placements[result.questionId] ?? []
        let completed = model.completedURL(session)
        return VStack(spacing: 2) {
            ForEach(Array(placements.prefix(3).enumerated()), id: \.offset) { _, p in
                PDFCropImage(url: completed, page: p.page,
                             rectFromTop: CGRect(x: p.x0, y: p.y0, width: p.x1 - p.x0, height: p.y1 - p.y0), width: 1400)
            }
        }
        .background(.white).clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.stroke))
        .frame(maxWidth: side ? .infinity : 900 * imageScale)
        .onTapGesture { zoom = ZoomTarget(url: completed, page: placements.first?.page ?? 0, title: "Q\(result.number) · \(title)") }
        .help("Click to open full size and zoom")
    }

    /// Maths: the original markscheme for the whole question, for parts the pipeline couldn't crop on their own.
    @ViewBuilder func fullMarkscheme(_ q: Question, _ url: URL, _ regions: [Region]) -> some View {
        let cropped = result.parts.filter { q.part(labelled: $0.label)?.msRegions?.isEmpty == false }.count
        if cropped == 0 {
            VStack(alignment: .leading, spacing: 6) {
                HStack { label("The markscheme"); Spacer(); zoomHint }
                markschemeImage(url, regions, title: "Q\(result.number) · markscheme").frame(maxWidth: 900 * imageScale)
            }
        } else if cropped < result.parts.count {
            DisclosureGroup(isExpanded: $showFullMarkscheme) {
                markschemeImage(url, regions, title: "Q\(result.number) · markscheme").frame(maxWidth: 900 * imageScale).padding(.top, 6)
            } label: {
                Label("See the whole markscheme", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.purple)
            }
            .tint(Palette.purple)
        }
    }

    /// Her own handwriting for one part, cut from the PDF she sent back.
    func handwritingImage(_ ink: [EssayAnchor], title: String) -> some View {
        let completed = model.completedURL(session)
        return VStack(spacing: 2) {
            ForEach(Array(ink.prefix(3).enumerated()), id: \.offset) { _, a in
                PDFCropImage(url: completed, page: a.page - 1, rectFromTop: CGRect(x: a.x, y: a.y, width: a.width, height: a.height), width: 1400)
            }
        }
        .background(.white).clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.stroke))
        .onTapGesture { zoom = ZoomTarget(url: completed, page: (ink.first?.page ?? 1) - 1, title: title) }
        .help("Click to open your working full size and zoom")
    }

    /// A crop of the official markscheme, so she sees exactly where the examiner gives each mark.
    func markschemeImage(_ url: URL, _ regions: [Region], title: String) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(regions.prefix(3).enumerated()), id: \.offset) { _, r in
                PDFCropImage(url: url, page: r.page, rectFromTop: CGRect(x: r.x0, y: r.y0, width: r.x1 - r.x0, height: r.y1 - r.y0), width: 1400)
            }
        }
        .background(.white).clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.stroke))
        .onTapGesture { zoom = ZoomTarget(url: url, page: regions.first?.page ?? 0, title: title) }
        .help("Click to open the markscheme full size and zoom")
    }

    func partRow(_ p: PartResult, markscheme: (url: URL, regions: [Region])? = nil) -> some View {
        let full = p.awarded >= p.available
        return HStack(alignment: .top, spacing: 12) {
            Text(p.label.isEmpty ? "—" : p.label).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Palette.lilac).frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text("You").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Palette.faint).textCase(.uppercase)
                let ink = reading?.handwriting(question: result.number, part: p.label) ?? []
                if ink.isEmpty {
                    Text(p.studentAnswer).font(.system(size: 12.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                } else {
                    handwritingImage(ink, title: "Q\(result.number)\(p.label) · your working")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text("Markscheme").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Palette.faint).textCase(.uppercase)
                Text(p.correctAnswer).font(.system(size: 12.5)).foregroundStyle(Palette.green.opacity(0.95)).fixedSize(horizontal: false, vertical: true)
                if !p.feedback.isEmpty {
                    Text(p.feedback).font(.system(size: 11.5).italic()).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
                }
                if let ms = markscheme, !ms.regions.isEmpty {
                    markschemeImage(ms.url, ms.regions, title: "Q\(result.number)\(p.label) · markscheme").padding(.top, 4)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text("\(p.awarded)/\(p.available)").font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(full ? Palette.green : (p.awarded == 0 ? Palette.red : Palette.orange)).frame(width: 40, alignment: .trailing)
        }
        .padding(12)
        .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 10))
    }

    var zoomHint: some View {
        Image(systemName: "plus.magnifyingglass").font(.system(size: 11)).foregroundStyle(Palette.faint)
    }

    func label(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.faint).textCase(.uppercase)
    }

    func note(_ title: String, _ body: String, _ icon: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(color)
                Text(body).font(.system(size: 13)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
