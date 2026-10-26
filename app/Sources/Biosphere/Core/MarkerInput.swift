import Foundation
import PDFKit

/// What the marking model (her chosen model, often Opus) receives: one message of text — the skill,
/// the markschemes and the reader's transcription — plus an image only where the reader asked for a
/// second look. No tools, no page images, no turns spent opening files.
enum MarkerInput {
    /// A skill's instructions from the app (the same text the workspace copy gets), frontmatter removed.
    static func skill(_ name: String) -> String {
        let candidates = [Workspace.resources.appendingPathComponent("skills/\(name)/SKILL.md"),
                          Workspace.root.appendingPathComponent(".claude/skills/\(name)/SKILL.md")]
        guard let text = candidates.lazy.compactMap({ try? String(contentsOf: $0, encoding: .utf8) }).first else { return "" }
        guard text.hasPrefix("---"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else { return text }
        return String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compact snake_case JSON (the same shape the skills describe).
    static func json<T: Encodable>(_ value: T) -> String {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }

    /// The text layer of an original case PDF (cases ship with real text, so no images are needed).
    static func pdfText(_ url: URL) -> String {
        guard let doc = PDFDocument(url: url) else { return "" }
        return (0..<doc.pageCount).compactMap { i in
            doc.page(at: i)?.string.map { "--- page \(i + 1) ---\n" + $0.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression) }
        }.joined(separator: "\n")
    }

    static let readingNote = """
    You don't see her paper. The app found her handwriting and a reader transcribed it verbatim (her spelling \
    and wording) — treat each transcription as exactly what she wrote. [?] is a word the reader couldn't read; \
    [brackets] describe something she drew or crossed out. Where an image is attached, the reader asked for a \
    second look (a drawing, unclear writing or an ambiguous choice): use the image for that answer.
    """
}

// MARK: - Biology

extension Marking {
    /// Multiple-choice marks the app settles itself: one clear letter compared with the key, or a blank.
    static func decidedMCQ(key: [AnswerKeyEntry], reading: BiologyReading) -> [Int: Int] {
        var out: [Int: Int] = [:]
        for entry in key where entry.type == "mcq" {
            guard let q = reading.question(entry.n), let answer = entry.answer?.trimmingCharacters(in: .whitespaces).uppercased(),
                  !answer.isEmpty else { continue }
            let choice = q.mcqChoice.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !q.answered && choice.isEmpty { out[entry.n] = 0; continue }
            guard q.legibility != "unclear", choice.count == 1, "ABCDEFGH".contains(choice) else { continue }
            out[entry.n] = choice == answer ? entry.marks : 0
        }
        return out
    }

    /// Questions whose crop the marker should see: drawings, unclear writing, or a choice the app couldn't settle.
    static func needsLook(key: [AnswerKeyEntry], reading: BiologyReading, decided: [Int: Int]) -> Set<Int> {
        Set(key.compactMap { entry in
            guard let q = reading.question(entry.n), !(q.sheets ?? []).isEmpty else { return nil }
            let mcqOpen = entry.type == "mcq" && decided[entry.n] == nil
            return (q.drawing || q.legibility == "unclear" || mcqOpen) ? entry.n : nil
        })
    }

    static func markerContent(session: StudySession, key: [AnswerKeyEntry], reading: BiologyReading, decided: [Int: Int],
                              look: Set<Int>, progress: String, readingDir: URL, skill: String = "mark-session") -> [ClaudeCLI.Content] {
        struct Answer: Encodable { var n: Int; var answered: Bool; var mcqChoice: String; var parts: [ReadPart]; var drawing: Bool; var legibility: String; var note: String }
        // Line ids only place her handwriting on the results screen; the marker doesn't need them.
        let answers = reading.questions.map { Answer(n: $0.n, answered: $0.answered, mcqChoice: $0.mcqChoice,
                                                      parts: $0.parts.map { ReadPart(label: $0.label, text: $0.text) },
                                                      drawing: $0.drawing, legibility: $0.legibility, note: $0.note) }
        var content: [ClaudeCLI.Content] = [
            .text("""
            Mark Biosphere session \(session.id) ("\(session.title)"). Follow the marking instructions below exactly.

            \(MarkerInput.readingNote)
            Multiple-choice marks under "Already marked" are final: write their feedback, don't re-mark them. \
            The app records stars from the reader, so set uncertain from the transcription's starred list.
            """),
            .text("## Marking instructions\n\n" + MarkerInput.skill(skill)),
            .text("## Questions and markschemes (answer key)\n\n" + MarkerInput.json(key)),
            .text("## Her answers, transcribed\n\n" + MarkerInput.json(answers)),
            .text("## Starred as unsure\n\n" + {
                let starred = reading.questions.filter(\.starred).map { "Q\($0.n)" }
                return starred.isEmpty ? "None." : starred.joined(separator: ", ")
            }()),
        ]
        if !decided.isEmpty {
            let lines = key.compactMap { e -> String? in
                guard let got = decided[e.n] else { return nil }
                let choice = reading.question(e.n)?.mcqChoice ?? ""
                return "Q\(e.n): chose \(choice.isEmpty ? "nothing" : choice), answer \(e.answer ?? "?") → \(got)/\(e.marks)"
            }
            content.append(.text("## Already marked (multiple choice)\n\n" + lines.joined(separator: "\n")))
        }
        for n in look.sorted() {
            for file in reading.question(n)?.sheets ?? [] {
                guard let png = try? Data(contentsOf: readingDir.appendingPathComponent(file)) else { continue }
                content.append(.text("Question \(n), as she wrote it (her ink dark, the printed question faint):"))
                content.append(.png(png))
            }
        }
        if !progress.isEmpty { content.append(.text("## Her progress on these subtopics\n\n" + progress)) }
        content.append(.text("Include one entry per question in the answer key. " + ClaudeCLI.submitInstruction))
        return content
    }

    /// The app's facts win over the model's: settled MCQ marks, ids and totals from the key, stars from the reader.
    static func reconcile(_ result: MarkingResult, key: [AnswerKeyEntry], reading: BiologyReading,
                          decided: [Int: Int], looked: Set<Int>) -> MarkingResult {
        var r = result
        r.questions = r.questions.filter { q in key.contains { $0.n == q.number } }
        for i in r.questions.indices {
            let n = r.questions[i].number
            guard let entry = key.first(where: { $0.n == n }) else { continue }
            r.questions[i].questionId = entry.questionId
            r.questions[i].available = entry.marks
            if let got = decided[n] {
                r.questions[i].awarded = got
                let choice = reading.question(n)?.mcqChoice ?? ""
                if r.questions[i].parts.count == 1 {
                    r.questions[i].parts[0].awarded = got
                    r.questions[i].parts[0].available = entry.marks
                    r.questions[i].parts[0].studentAnswer = choice.isEmpty ? "(blank)" : choice
                }
                if got == entry.marks { r.questions[i].whyLost = "" }
            }
            r.questions[i].awarded = min(max(0, r.questions[i].awarded), entry.marks)
            if let q = reading.question(n) {
                r.questions[i].uncertain = q.starred || (looked.contains(n) && r.questions[i].isUncertain)
            }
        }
        r.questions.sort { $0.number < $1.number }
        r.awarded = r.questions.reduce(0) { $0 + $1.awarded }
        r.available = key.reduce(0) { $0 + $1.marks }
        return r
    }
}

// MARK: - Business

extension BusinessMarking {
    static func markerContent(session: StudySession, key: BusinessKey, reading: BusinessReading,
                              history: String, readingDir: URL) -> [ClaudeCLI.Content] {
        let bank = Workspace.root
        let subject = key.caseSubject
        let cases: [(String, String)] = (key.sources?.map { ("Case \($0.number): \($0.company) (\($0.source))", $0.caseFile) })
            ?? key.caseFile.map { [("\(key.company) (\(key.session) · Paper \(key.paper))", $0)] } ?? []
        var content: [ClaudeCLI.Content] = [
            .text("""
            Mark Biosphere \(subject.shortName) session \(session.id) ("\(session.title)"). Follow the marking instructions below exactly.

            \(MarkerInput.readingNote)
            Her answer is given line by line with ids (L1, L2…). For every essay sentence, put the ids of the lines \
            it's written on in `lines`, in order (a sentence can share a line with the next one). The app uses them to \
            highlight her paper. Use [] only if a sentence isn't in the transcription.
            """),
            .text("## Marking instructions\n\n" + MarkerInput.skill(subject.markingSkill)),
            .text("## Marking pack\n\n" + ((try? String(contentsOf: bank.appendingPathComponent(subject.markingPack), encoding: .utf8)) ?? "")),
            .text("## This paper (session key)\n\n" + MarkerInput.json(key)),
        ]
        for (title, file) in cases {
            let text = MarkerInput.pdfText(bank.appendingPathComponent(file))
            if !text.isEmpty { content.append(.text("## Original \(subject == .business ? "case" : "question and texts"): \(title)\n\n" + text)) }
        }
        var answers: [String] = []
        for part in key.parts {
            let lines = reading.lines(for: part.label)
            answers.append("### \(part.label) [\(part.marks)]\(part.extended ? " · long answer" : "")\n" +
                           (lines.isEmpty ? "(blank)" : lines.map { "\($0.id): \($0.text)" }.joined(separator: "\n")))
        }
        let loose = reading.lines.filter { l in !key.parts.contains { BusinessReading.same($0.label, l.part) } && !l.text.isEmpty }
        if !loose.isEmpty { answers.append("### Not matched to a part\n" + loose.map { "\($0.id): \($0.text)" }.joined(separator: "\n")) }
        content.append(.text("## Her answers, transcribed\n\n" + answers.joined(separator: "\n\n")))
        let notes = [reading.starredParts.isEmpty ? nil : "Starred as unsure: " + reading.starredParts.joined(separator: ", "),
                     reading.note.isEmpty ? nil : "Reader's note: " + reading.note].compactMap { $0 }
        if !notes.isEmpty { content.append(.text(notes.joined(separator: "\n"))) }

        // A second look only where the reader couldn't do the answer justice in text.
        let look = Set(reading.drawingParts + reading.unclearParts)
        let pagesToShow = Set(reading.lines.filter { look.contains($0.part) }.compactMap { reading.anchors?[$0.id]?.page })
        for page in pagesToShow.sorted() {
            guard let file = reading.pageSheets?[String(page)],
                  let png = try? Data(contentsOf: readingDir.appendingPathComponent(file)) else { continue }
            content.append(.text("Page \(page) as she wrote it, for parts \(look.sorted().joined(separator: ", ")) (line ids in the margin):"))
            content.append(.png(png))
        }
        if !history.isEmpty { content.append(.text("## Her earlier \(subject.shortName) sessions\n\n" + history)) }
        content.append(.text(ClaudeCLI.submitInstruction))
        return content
    }

    /// Essay sentences come back with line ids; the app turns them into exact highlights.
    static func placeSentences(_ result: BusinessResult, reading: BusinessReading) -> BusinessResult {
        var r = result
        let anchors = reading.anchors ?? [:]
        for e in r.essays.indices {
            for s in r.essays[e].sentences.indices {
                let ids = r.essays[e].sentences[s].lines ?? []
                r.essays[e].sentences[s].anchors = ids.compactMap { anchors[$0] }
            }
        }
        if r.transcriptionNote.isEmpty { r.transcriptionNote = reading.note }
        return r
    }
}
