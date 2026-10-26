import Foundation

/// Marking in two steps, so her plan isn't spent on page images:
///   1. Read: the app finds her ink, a small model (`settings.readerModel`, Haiku by default) transcribes it.
///   2. Mark: her chosen model (`settings.markingModel`) marks the transcription against the markscheme
///      in one turn, seeing an image only where the reader asked for a second look.
extension AppModel {
    func readAndMark(_ s: StudySession, bank: Bank) async throws -> MarkingResult {
        let dir = Workspace.sessionDir(s.id)
        let key = Marking.answerKey(for: s, bank: bank)
        let id = s.id
        let log: @Sendable (String) -> Void = { line in Task { @MainActor in self.markingLog[id, default: []].append(line) } }

        let maths = bank.syllabus.isStrategyBank
        let reading = try await HandwritingReader.readBiology(key: key, placements: s.placements, completed: completedURL(s),
                                                              original: pdfURL(s), dir: dir, model: settings.readerModel,
                                                              rules: maths ? HandwritingReader.mathsRules : HandwritingReader.biologyRules,
                                                              numberLines: maths, log: log)
        try JSON.save(reading, to: dir.appendingPathComponent("transcript.json"))
        let decided = Marking.decidedMCQ(key: key, reading: reading)
        let look = Marking.needsLook(key: key, reading: reading, decided: decided)
        log("Read \(reading.questions.filter(\.answered).count) answers. Hank is marking them…")

        let content = Marking.markerContent(session: s, key: key, reading: reading, decided: decided, look: look,
                                            progress: progressNotes(for: key, bank: bank), readingDir: dir.appendingPathComponent("reading"),
                                            skill: maths ? "mark-maths" : "mark-session")
        let result = try await ClaudeCLI.ask(content: content, schema: Marking.schema, model: settings.markingModel,
                                             effort: settings.effort, as: MarkingResult.self, onEvent: log)
        return Marking.reconcile(result, key: key, reading: reading, decided: decided, looked: look)
    }

    func readAndMark(_ s: StudySession, key: BusinessKey) async throws -> BusinessResult {
        let dir = Workspace.sessionDir(s.id)
        let id = s.id
        let log: @Sendable (String) -> Void = { line in Task { @MainActor in self.markingLog[id, default: []].append(line) } }

        let reading = try await HandwritingReader.readBusiness(key: key, completed: completedURL(s), original: pdfURL(s),
                                                               dir: dir, model: settings.readerModel, log: log)
        try JSON.save(reading, to: dir.appendingPathComponent("transcript.json"))
        log("Read \(reading.lines.count) lines. Hank is marking them…")

        let content = BusinessMarking.markerContent(session: s, key: key, reading: reading, history: businessHistoryNotes(key.caseSubject),
                                                    readingDir: dir.appendingPathComponent("reading"))
        let result = try await ClaudeCLI.ask(content: content, schema: BusinessMarking.schema, model: settings.markingModel,
                                             effort: settings.effort, as: BusinessResult.self, onEvent: log)
        return BusinessMarking.placeSentences(result, reading: reading)
    }

    /// One line per subtopic on this paper (every part's strategy, for Maths), instead of the whole progress summary.
    func progressNotes(for key: [AnswerKeyEntry], bank: Bank) -> String {
        Array(Set(key.flatMap { [$0.subtopic] + $0.parts.compactMap(\.subtopic) })).sorted().map { id in
            let st = progress.stats(for: id)
            let pct = st.percent.map { "\(Int($0 * 100))% recently" } ?? "no marks yet"
            return "\(id) \(bank.syllabus.subtopic(id)?.name ?? ""): \(st.mastery.label.lowercased()) (\(pct), \(st.sessions) session\(st.sessions == 1 ? "" : "s"))"
        }.joined(separator: "\n")
    }

    /// Her last few marked sessions in that subject, so Hank can spot habits.
    func businessHistoryNotes(_ subject: CaseSubject = .business) -> String {
        guard let entries = try? JSON.load([BusinessHistoryEntry].self, from: Workspace.root.appendingPathComponent(subject.historyFile)),
              !entries.isEmpty else { return "" }
        return MarkerInput.json(Array(entries.suffix(8)))
    }
}
