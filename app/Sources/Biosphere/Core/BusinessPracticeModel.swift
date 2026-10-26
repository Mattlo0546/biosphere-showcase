import Foundation

extension AppModel {
    /// Latest marked result for each original case/part, shared by mixed and individual sessions.
    func businessPracticeHistory(_ subject: CaseSubject = .business) -> [String: [String: Double]] {
        var history: [String: [String: Double]] = [:]
        for session in sessions.filter({ $0.caseSubject == subject && $0.status == .marked }).sorted(by: { ($0.markedAt ?? $0.createdAt) > ($1.markedAt ?? $1.createdAt) }) {
            guard let result = businessResults(session) else { continue }
            if let components = session.businessComponents {
                for (index, component) in components.enumerated() {
                    for label in component.labels {
                        let paperLabel = BusinessMixedPaper.label(caseNumber: index + 1, original: label)
                        if history[component.setId]?[label] == nil, let part = result.parts.first(where: { $0.label == paperLabel }) {
                            history[component.setId, default: [:]][label] = Double(part.awarded) / Double(max(part.available, 1))
                        }
                    }
                }
            } else if let id = session.businessSetId {
                for part in result.parts where history[id]?[part.label] == nil {
                    history[id, default: [:]][part.label] = Double(part.awarded) / Double(max(part.available, 1))
                }
            }
        }
        return history
    }

    @discardableResult
    func buildBusinessPractice(_ scope: BusinessPracticeScope, minutes: Int, format: BusinessQuestionFormat,
                               mode: StudyMode, everyQuestion: Bool, timed: Bool,
                               papers: Set<String> = BusinessPracticePlanner.defaultPapers) -> StudySession? {
        guard let bank = caseBank(scope.subject) else { return nil }
        let components = BusinessPracticePlanner.plan(bank: bank, topics: scope.topicIds, minutes: minutes,
                                                       format: format, mode: mode, history: businessPracticeHistory(scope.subject),
                                                       everyQuestion: everyQuestion, papers: papers)
        let sets = BusinessPracticePlanner.selectedSets(bank: bank, components: components)
        guard !sets.isEmpty, sets.count == components.count else { say("There are no questions for this selection yet."); return nil }
        let suggested = BusinessPracticePlanner.estimatedMinutes(bank: bank, components: components)
        var session = StudySession(id: StudySession.newID(), title: scope.title,
                                   subtitle: "\(scope.subject.name) · mixed \(BusinessPracticePlanner.papersTitle(Set(sets.map(\.paper)))) · \(sets.count) case\(sets.count == 1 ? "" : "s")",
                                   kind: .custom, scope: scope.topicIds, questionIds: [],
                                   totalMarks: sets.reduce(0) { $0 + $1.marks }, minutes: max(minutes, suggested),
                                   createdAt: Date(), status: .ready)
        if everyQuestion { session.minutes = suggested }
        session.subject = scope.subject.slug
        session.businessComponents = components
        if scope.topicIds.count == 1 { session.businessTopicId = scope.topicIds[0] }
        let directory = Workspace.sessionDir(session.id)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let output = try BusinessMixedPaper.compose(session: session, sets: sets, to: pdfURL(session))
            session.pageCount = output.pageCount
            session.answerPages = output.answerPages
            let combined = BusinessMixedPaper.combined(session: session, sets: sets)
            try JSON.save(businessKey(session, combined), to: directory.appendingPathComponent("business.json"))
            save(session)
            openSession = session.id
            if timed { timer.prepare(session) }
            return session
        } catch { say("Couldn't build the PDF: \(error.localizedDescription)"); return nil }
    }

    func annotatedBusinessURL(_ session: StudySession) -> URL {
        Workspace.sessionDir(session.id).appendingPathComponent("marked.pdf")
    }

    /// Backfill paper locations for older essay feedback without regrading the student's work. The cheap
    /// reader numbers and transcribes her lines; a text-only call matches each sentence to its lines.
    func addBusinessAnnotations(_ session: StudySession) async {
        guard !businessAnnotating.contains(session.id), let result = businessResults(session), !result.essays.isEmpty,
              let set = businessSet(for: session) else { return }
        businessAnnotating.insert(session.id)
        businessAnnotationErrors[session.id] = nil
        defer { businessAnnotating.remove(session.id) }
        let directory = Workspace.sessionDir(session.id)
        do {
            let completed = completedURL(session)
            let key = businessKey(session, set)
            let saved = try? JSON.load(BusinessReading.self, from: directory.appendingPathComponent("transcript.json"))
            let reading: BusinessReading
            if let saved, !(saved.anchors ?? [:]).isEmpty { reading = saved } else {
                reading = try await HandwritingReader.readBusiness(key: key, completed: completed, original: pdfURL(session),
                                                                   dir: directory, model: settings.readerModel)
                try JSON.save(reading, to: directory.appendingPathComponent("transcript.json"))
            }
            guard !(reading.anchors ?? [:]).isEmpty else {
                throw ClaudeCLI.CLIError.failed("Your returned paper doesn't line up with the one Biosphere made, so comments can't be placed.")
            }
            let sentences = result.essays.map { essay in
                "Part \(essay.label):\n" + essay.sentences.enumerated().map { "[\($0)] \($1.text)" }.joined(separator: "\n")
            }.joined(separator: "\n\n")
            let lines = reading.lines.map { "\($0.id) (\($0.part)): \($0.text)" }.joined(separator: "\n")
            let matched = try await ClaudeCLI.ask(content: [.text("""
                Match each sentence of a marked essay to the handwritten lines it was written on. Return one entry for EVERY \
                sentence, with its part and zero-based index, and the ids of its lines in order. Lines may be transcribed \
                slightly differently from the sentences. Use [] if a sentence isn't on any line. Don't guess.

                Sentences:
                \(sentences)

                Lines:
                \(lines)
                """)], schema: BusinessAnnotations.matchSchema, model: settings.readerModel, effort: "low",
                cwd: HandwritingReader.neutralFolder, as: BusinessAnnotations.Matches.self)
            let anchors = reading.anchors ?? [:]
            let located = matched.sentences.compactMap { m -> BusinessAnnotations.LocatedSentence? in
                guard let essay = result.essays.first(where: { $0.label == m.part }), essay.sentences.indices.contains(m.index) else { return nil }
                let sentence = essay.sentences[m.index]
                let judgement = sentence.judgement ?? (sentence.label == "none" ? "improve" : "strength")
                return .init(part: m.part, index: m.index, judgement: judgement, note: sentence.note, anchors: m.lines.compactMap { anchors[$0] })
            }
            let pages = key.answerPages.isEmpty ? Array(Set(anchors.values.map(\.page))) : key.answerPages
            let updated = try BusinessAnnotations.apply(.init(sentences: located), to: result, answerPages: pages)
            try BusinessAnnotations.write(result: updated, source: completed, to: annotatedBusinessURL(session))
            try JSON.save(updated, to: directory.appendingPathComponent("business_results.json"))
            say("Your essay comments are ready on your paper.")
        } catch { businessAnnotationErrors[session.id] = error.localizedDescription }
    }
}
