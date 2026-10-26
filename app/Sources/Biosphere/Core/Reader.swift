import Foundation

// MARK: - What the reader returns

/// One Biology question as the reader saw it: her words, verbatim, and nothing else.
struct ReadQuestion: Codable, Hashable {
    var n: Int
    var answered: Bool
    var mcqChoice: String         // the letter she chose, "" if none; "B or C" when ambiguous
    var parts: [ReadPart]
    var starred: Bool             // a hand-drawn * or star: she was unsure
    var drawing: Bool             // she drew something the marker should see
    var legibility: String        // clear | partly | unclear
    var note: String
    var sheets: [String]?         // app-filled: reading/qNN-k.png files the reader looked at
}

struct ReadPart: Codable, Hashable {
    var label: String
    var text: String
    var lines: [String]? = nil    // Maths: ids of her handwritten lines for this part (see BiologyReading.anchors)
}

/// sessions/<id>/transcript.json for a Biology paper.
struct BiologyReading: Codable {
    var questions: [ReadQuestion]
    var model: String
    var inkSeparated: Bool        // false: the returned PDF didn't line up, so the reader saw whole crops
    var anchors: [String: EssayAnchor]? = nil   // Maths, app-filled: line id → exact rectangle on her page

    /// Where she wrote one part (one rectangle per page), so results can show her own handwriting.
    func handwriting(question n: Int, part label: String) -> [EssayAnchor] {
        let key = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
        guard let anchors, let part = question(n)?.parts.first(where: { key($0.label) == key(label) }) else { return [] }
        let boxes = (part.lines ?? []).compactMap { anchors[$0] }
        return Dictionary(grouping: boxes, by: \.page).keys.sorted().compactMap { page in
            let b = boxes.filter { $0.page == page }
            guard let y0 = b.map(\.y).min(), let y1 = b.map({ $0.y + $0.height }).max() else { return nil }
            // Full answer width, so every part's crop is drawn at the same scale.
            let x0 = min(b.map(\.x).min() ?? 0.05, 0.05), x1 = max(b.map { $0.x + $0.width }.max() ?? 0.95, 0.95)
            // Pad, but stop halfway to her lines for other parts so none of them peeks in.
            let others = anchors.values.filter { $0.page == page && !b.contains($0) }
            let above = others.map { $0.y + $0.height }.filter { $0 <= y0 }.max().map { ($0 + y0) / 2 } ?? 0
            let below = others.map(\.y).filter { $0 >= y1 }.min().map { ($0 + y1) / 2 } ?? 1
            let top = max(above, y0 - 0.008), bottom = min(below, y1 + 0.008)
            return EssayAnchor(page: page, x: x0, y: top, width: x1 - x0, height: bottom - top)
        }
    }

    func question(_ n: Int) -> ReadQuestion? { questions.first { $0.n == n } }
}

/// One handwritten Business line. Ids (L1, L2…) are printed beside the line on the reading sheet.
struct ReadLine: Codable, Hashable { var id: String; var part: String; var text: String }

/// sessions/<id>/transcript.json for a Business paper.
struct BusinessReading: Codable {
    var lines: [ReadLine]
    var starredParts: [String]
    var drawingParts: [String]
    var unclearParts: [String]
    var note: String
    var model: String?
    var inkSeparated: Bool?
    var anchors: [String: EssayAnchor]?   // app-filled: line id → exact rectangle on her page
    var pageSheets: [String: String]?     // app-filled: page number → reading/page-NN.png

    /// The reader sometimes writes "(a)(i)" or "a (i)" for the paper's "a(i)": compare without brackets and spaces.
    func lines(for part: String) -> [ReadLine] { lines.filter { Self.same($0.part, part) } }
    static func same(_ a: String, _ b: String) -> Bool { key(a) == key(b) }
    private static func key(_ s: String) -> String { s.lowercased().filter { !"() ".contains($0) } }
}

// MARK: - The reader

/// Turns her returned PDF into text with a small, cheap model, so the marking model never has to
/// look at page images. The app finds her ink (see `Ink`), the reader only transcribes it.
enum HandwritingReader {
    /// Questions per reader call. Calls run in parallel, so long papers aren't slower.
    static let batchSize = 8

    /// Runs outside ~/Biosphere so Hank's persona and skills don't load into a transcription job.
    static var neutralFolder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("biosphere-reader") }

    static let biologyRules = """
    You are reading a student's handwritten exam answers for a teacher who will mark them. You only \
    transcribe: never judge, correct, complete or improve anything.

    Each image shows the answer area of ONE question. Her handwriting is dark. The printed question is faint \
    grey and is only there so you can see where she wrote: do not transcribe printed text.

    - Write exactly what she wrote: her spelling, wording, abbreviations, numbers and units.
    - Split her writing by the part labels listed for that question. A single unlabelled part uses label "".
    - Crossed-out writing: leave it out, unless it's all she wrote; then write [crossed out: …].
    - A word you can't read: write [?]. legibility is "partly" for a few such words, "unclear" if you can't follow the answer.
    - Drawings, graphs, diagrams, tables, arrows or labels she added: set drawing to true and describe them in \
    [brackets], including every label she wrote.
    - Multiple choice: mcq_choice is the one letter she chose (in the Answer box, or circled/ticked among the \
    options; a crossed-out letter doesn't count). If two letters still look chosen, write e.g. "B or C" and set \
    legibility "unclear". "" if she chose nothing.
    - starred: true only for an asterisk (*) or star she drew by hand beside the question, an answer or a part.
    - answered: false if there is no handwriting for the question.
    - note: only a real reading problem (e.g. "ink very faint"); otherwise "".
    Return one entry per question listed, with the same n.
    """

    /// Maths: the same job, but her working is the answer (method marks), so every line of it matters.
    static let mathsRules = """
    You are reading a student's handwritten maths working for a teacher who will mark it. You only transcribe: \
    never judge, correct, complete, simplify or finish anything, even an obvious slip.

    Each image shows the working area of ONE question. Her handwriting is dark. The printed question is faint grey \
    and is only there so you can see where she wrote: do not transcribe printed text.

    - Transcribe her working line by line, top to bottom, in plain-text maths, one line of hers per line of text \
    (separate lines with a newline): x^2, sqrt(x), (a)/(b) for fractions, pi, theta, ln, e^(2x), f'(x), d/dx, ∫, ≤, ≥, ≠.
    - Keep her exact numbers, signs, rounding and units. Mark her final answer if she boxed or underlined it: [boxed] 3.25.
    - Split her working by the part labels listed for that question, using the labels she wrote (or where it sits). \
    A single unlabelled part uses label "".
    - Crossed-out working: leave it out, unless it's all she wrote; then write [crossed out: …].
    - Something you can't read: [?]. legibility is "partly" for a few such symbols, "unclear" if you can't follow the working.
    - Sketches, graphs, tables or diagrams she drew: set drawing to true and describe them in [brackets], including \
    every intercept, asymptote, coordinate and label she wrote.
    - mcq_choice is always "".
    - starred: true only for an asterisk (*) or star she drew by hand beside the question or a part.
    - answered: false if there is no handwriting for the question.
    - note: only a real reading problem (e.g. "ink very faint"); otherwise "".
    - lines: when her handwritten lines have ids (L1, L2…) in the left margin, list for each part the ids of every \
    line of her working for that part, in order. Without ids, lines is [].
    Return one entry per question listed, with the same n.
    """

    static func businessRules(_ subject: CaseSubject) -> String { businessRules.replacingOccurrences(of: "Business Management", with: subject.readerName) }

    static let businessRules = """
    You are reading a student's handwritten Business Management exam answers for a teacher who will mark them. \
    You only transcribe: never judge, correct, complete or improve anything.

    Each image is one page. Her handwriting is dark. The printed paper is faint grey and is only there so you can \
    see where she wrote (part labels, answer boxes): do not transcribe printed text. Each handwritten line has an \
    id (L1, L2…) in the left margin.

    - Return one entry per id, in order: her exact words on that line (spelling, numbers, units), and the part label \
    it answers (use the labels listed below; "" if it belongs to no part, e.g. a doodle).
    - Crossed-out writing: leave it out of the line's text; if the whole line is crossed out, text is "[crossed out]".
    - A word you can't read: [?]. Add the part to unclear_parts if you can't follow its answer.
    - Tables, diagrams, charts, calculations laid out in columns: transcribe what you can, describe the rest in \
    [brackets], and add the part to drawing_parts.
    - starred_parts: parts with an asterisk (*) or star she drew by hand.
    - note: only a real reading problem the teacher should know about (e.g. "page 5 very faint"); otherwise "". \
    Images are cropped to where she wrote, so a page ending below her last line is normal.
    """

    static let biologySchema = readerSchema(lines: false)
    static let mathsSchema = readerSchema(lines: true)

    static func readerSchema(lines: Bool) -> String {
        var partProps: [String: Any] = ["label": ["type": "string"], "text": ["type": "string"]]
        if lines { partProps["lines"] = ["type": "array", "items": ["type": "string"]] }
        let part: [String: Any] = ["type": "object", "required": lines ? ["label", "text", "lines"] : ["label", "text"],
                                   "properties": partProps]
        let q: [String: Any] = ["type": "object",
                                "required": ["n", "answered", "mcq_choice", "parts", "starred", "drawing", "legibility", "note"],
                                "properties": ["n": ["type": "integer"], "answered": ["type": "boolean"], "mcq_choice": ["type": "string"],
                                               "parts": ["type": "array", "items": part], "starred": ["type": "boolean"],
                                               "drawing": ["type": "boolean"],
                                               "legibility": ["type": "string", "enum": ["clear", "partly", "unclear"]],
                                               "note": ["type": "string"]]]
        let root: [String: Any] = ["type": "object", "required": ["questions"],
                                   "properties": ["questions": ["type": "array", "items": q]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: root), as: UTF8.self)
    }

    static let businessSchema: String = {
        let strings: [String: Any] = ["type": "array", "items": ["type": "string"]]
        let line: [String: Any] = ["type": "object", "required": ["id", "part", "text"],
                                   "properties": ["id": ["type": "string"], "part": ["type": "string"], "text": ["type": "string"]]]
        let root: [String: Any] = ["type": "object",
                                   "required": ["lines", "starred_parts", "drawing_parts", "unclear_parts", "note"],
                                   "properties": ["lines": ["type": "array", "items": line], "starred_parts": strings,
                                                  "drawing_parts": strings, "unclear_parts": strings, "note": ["type": "string"]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: root), as: UTF8.self)
    }()

    private struct BiologyBatch: Codable { var questions: [ReadQuestion] }
    private struct BusinessBatch: Codable {
        var lines: [ReadLine]; var starredParts: [String]; var drawingParts: [String]; var unclearParts: [String]; var note: String
    }

    // MARK: Biology

    /// Crops every question's answer area (only where she wrote, when the PDFs line up), saves the sheets
    /// to `reading/`, and asks the reader to transcribe them.
    static func readBiology(key: [AnswerKeyEntry], placements: [String: [Placement]], completed: URL, original: URL?,
                            dir: URL, model: String, rules: String = biologyRules, numberLines: Bool = false,
                            log: @escaping @Sendable (String) -> Void = { _ in }) async throws -> BiologyReading {
        let readingDir = dir.appendingPathComponent("reading")
        try? FileManager.default.removeItem(at: readingDir)
        try FileManager.default.createDirectory(at: readingDir, withIntermediateDirectories: true)

        let pagesNeeded = Set(key.flatMap(\.pages))
        let pages = try await Task.detached { try Ink.pages(original: original, completed: completed, only: pagesNeeded) }.value
        let separated = !pages.isEmpty && pages.allSatisfy(\.canSeparateInk)
        let byNumber = Dictionary(uniqueKeysWithValues: pages.map { ($0.number, $0) })

        // Build the sheets locally: questions with no ink at all never reach a model.
        var sheets: [Int: [String]] = [:]
        // Maths: number her lines (as Business does) so the reader can say which lines answer which part.
        let numbered = numberLines && separated
        var anchors: [String: EssayAnchor] = [:]
        var next = 1
        for entry in key {
            var files: [String] = []
            for p in placements[entry.questionId] ?? [] {
                guard let page = byNumber[p.page + 1] else { continue }
                let rows = Ink.rows(p, in: page), cols = Ink.columns(p, in: page)
                if separated && !page.hasInk(rows: rows, columns: cols) { continue }
                var tags: [(line: InkLine, id: String)] = []
                if numbered {
                    for line in Ink.lines(on: page, rows: rows) where line.right > cols.lowerBound && line.left < cols.upperBound {
                        tags.append((line, "L\(next)")); anchors["L\(next)"] = line.anchor; next += 1
                    }
                }
                guard let png = Ink.sheet(page, rows: rows, columns: cols, tags: tags) else { continue }
                let name = String(format: "q%02d-%d.png", entry.n, files.count + 1)
                try png.write(to: readingDir.appendingPathComponent(name))
                files.append(name)
            }
            sheets[entry.n] = files
        }

        let toRead = key.filter { !(sheets[$0.n] ?? []).isEmpty }
        log("Reading \(toRead.count) answer\(toRead.count == 1 ? "" : "s")…")
        let batches = stride(from: 0, to: toRead.count, by: batchSize).map { Array(toRead[$0..<min($0 + batchSize, toRead.count)]) }
        let read: [ReadQuestion] = try await withThrowingTaskGroup(of: [ReadQuestion].self) { group in
            for batch in batches {
                var content: [ClaudeCLI.Content] = [.text(rules)]
                for entry in batch {
                    let parts = entry.parts.map { "\($0.label.isEmpty ? "(single part)" : $0.label) [\($0.marks)]" }.joined(separator: ", ")
                    content.append(.text("Question \(entry.n) · \(entry.type == "mcq" ? "multiple choice" : "written") · parts: \(parts)"))
                    for (i, file) in (sheets[entry.n] ?? []).enumerated() {
                        if let png = try? Data(contentsOf: readingDir.appendingPathComponent(file)) {
                            if (sheets[entry.n]?.count ?? 0) > 1 { content.append(.text("Question \(entry.n), area \(i + 1):")) }
                            content.append(.png(png))
                        }
                    }
                }
                content.append(.text("Transcribe questions \(batch.map { String($0.n) }.joined(separator: ", ")). " + ClaudeCLI.submitInstruction))
                group.addTask {
                    try await ClaudeCLI.ask(content: content, schema: numberLines ? mathsSchema : biologySchema, model: model, effort: "low",
                                            cwd: neutralFolder, as: BiologyBatch.self).questions
                }
            }
            var all: [ReadQuestion] = []
            for try await qs in group { all += qs }
            return all
        }

        // Every question gets an entry, even blank ones and any the reader skipped.
        let questions = key.map { entry -> ReadQuestion in
            let files = sheets[entry.n] ?? []
            if var q = read.first(where: { $0.n == entry.n }) {
                q.sheets = files
                return q
            }
            return ReadQuestion(n: entry.n, answered: false, mcqChoice: "", parts: [], starred: false, drawing: false,
                                legibility: files.isEmpty ? "clear" : "unclear",
                                note: files.isEmpty ? "No handwriting found." : "The reader skipped this question.", sheets: files)
        }
        return BiologyReading(questions: questions, model: model, inkSeparated: separated, anchors: numbered ? anchors : nil)
    }

    // MARK: Business

    /// Numbers every handwritten line on her answer pages (exact rectangles from the ink), saves one sheet
    /// per page and asks the reader for the text of each line and the part it answers.
    static func readBusiness(key: BusinessKey, completed: URL, original: URL?, dir: URL, model: String,
                             log: @escaping @Sendable (String) -> Void = { _ in }) async throws -> BusinessReading {
        let readingDir = dir.appendingPathComponent("reading")
        try? FileManager.default.removeItem(at: readingDir)
        try FileManager.default.createDirectory(at: readingDir, withIntermediateDirectories: true)

        let wanted = key.answerPages.isEmpty ? nil : Set(key.answerPages)
        let pages = try await Task.detached { try Ink.pages(original: original, completed: completed, only: wanted) }.value
        let separated = !pages.isEmpty && pages.allSatisfy(\.canSeparateInk)

        var anchors: [String: EssayAnchor] = [:]
        var pageSheets: [String: String] = [:]
        var sheetsInOrder: [(page: Int, ids: [String], file: String)] = []
        var next = 1
        for page in pages {
            let lines = Ink.lines(on: page)
            if separated && lines.isEmpty { continue }          // nothing written on this page
            let tags = lines.map { line -> (line: InkLine, id: String) in
                defer { next += 1 }
                return (line, "L\(next)")
            }
            for t in tags { anchors[t.id] = t.line.anchor }
            let top = max(0, (lines.first?.top ?? 0) - 150), bottom = min(page.height, (lines.last?.bottom ?? page.height) + 40)
            guard let png = Ink.sheet(page, rows: separated ? top..<bottom : 0..<page.height, tags: tags) else { continue }
            let name = String(format: "page-%02d.png", page.number)
            try png.write(to: readingDir.appendingPathComponent(name))
            pageSheets[String(page.number)] = name
            sheetsInOrder.append((page.number, tags.map(\.id), name))
        }

        guard !sheetsInOrder.isEmpty else {
            return BusinessReading(lines: [], starredParts: [], drawingParts: [], unclearParts: [], note: "No handwriting found.",
                                   model: model, inkSeparated: separated, anchors: [:], pageSheets: [:])
        }
        log("Reading \(sheetsInOrder.count) page\(sheetsInOrder.count == 1 ? "" : "s") of your answers…")

        let partsText = key.parts.map { p in
            "\(p.label) [\(p.marks)]\(p.extended ? " (long answer)" : "")\(p.choice.map { " (choice group \($0): she answers one)" } ?? "")"
        }.joined(separator: ", ")
        let batches = stride(from: 0, to: sheetsInOrder.count, by: 6).map { Array(sheetsInOrder[$0..<min($0 + 6, sheetsInOrder.count)]) }
        let results: [(Int, BusinessBatch)] = try await withThrowingTaskGroup(of: (Int, BusinessBatch).self) { group in
            for (index, batch) in batches.enumerated() {
                var content: [ClaudeCLI.Content] = [.text(businessRules(key.caseSubject)), .text("Parts on this paper: \(partsText)")]
                for sheet in batch {
                    content.append(.text(separated ? "Page \(sheet.page) · lines \(sheet.ids.first ?? "")–\(sheet.ids.last ?? ""):" :
                                            "Page \(sheet.page) (lines aren't numbered: number them yourself from L\(index * 1000 + 1) in reading order):"))
                    if let png = try? Data(contentsOf: readingDir.appendingPathComponent(sheet.file)) { content.append(.png(png)) }
                }
                content.append(.text(ClaudeCLI.submitInstruction))
                group.addTask {
                    (index, try await ClaudeCLI.ask(content: content, schema: businessSchema, model: model, effort: "low",
                                                    cwd: neutralFolder, as: BusinessBatch.self))
                }
            }
            var all: [(Int, BusinessBatch)] = []
            for try await r in group { all.append(r) }
            return all.sorted { $0.0 < $1.0 }
        }
        let batchesRead = results.map(\.1)
        func merged(_ path: KeyPath<BusinessBatch, [String]>) -> [String] {
            var seen = Set<String>(); return batchesRead.flatMap { $0[keyPath: path] }.filter { seen.insert($0).inserted }
        }
        // Keep only lines we numbered (when we numbered them), in page order.
        var lines = batchesRead.flatMap(\.lines)
        if separated {
            let order = Dictionary(uniqueKeysWithValues: sheetsInOrder.flatMap(\.ids).enumerated().map { ($1, $0) })
            var seen = Set<String>()
            lines = lines.filter { order[$0.id] != nil && seen.insert($0.id).inserted }.sorted { order[$0.id]! < order[$1.id]! }
        }
        return BusinessReading(lines: lines, starredParts: merged(\.starredParts), drawingParts: merged(\.drawingParts),
                               unclearParts: merged(\.unclearParts),
                               note: batchesRead.map(\.note).filter { !$0.isEmpty }.joined(separator: " "),
                               model: model, inkSeparated: separated, anchors: separated ? anchors : [:], pageSheets: pageSheets)
    }
}
