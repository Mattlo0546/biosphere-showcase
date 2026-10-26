import AppKit
import PDFKit

/// What Claude gets for marking: the questions, their markschemes and where each one sits in the PDF.
struct AnswerKeyEntry: Codable {
    var n: Int
    var questionId: String
    var type: String
    var marks: Int
    var pages: [Int]                 // 1-based pages of the session PDF this question is on
    var subtopic: String
    var subtopicName: String
    var concepts: [String]
    var answer: String?              // MCQ letter
    var parts: [Part]
    var source: String
}

enum Marking {
    static func answerKey(for session: StudySession, bank: Bank) -> [AnswerKeyEntry] {
        session.questionIds.enumerated().compactMap { i, id in
            guard let q = bank.question(id) else { return nil }
            let pages = Array(Set((session.placements[id] ?? []).map { $0.page + 1 })).sorted()
            return AnswerKeyEntry(n: i + 1, questionId: id, type: q.type, marks: q.marks, pages: pages, subtopic: q.primary,
                                  subtopicName: bank.syllabus.subtopic(q.primary)?.name ?? q.primary,
                                  concepts: q.concepts, answer: q.answer,
                                  // Markscheme crop coordinates are for the results screen, not for Hank.
                                  parts: q.parts.map { var p = $0; p.msRegions = nil; return p }, source: q.sourceLabel)
        }
    }

    /// Renders each page of her completed PDF (with handwriting/annotations) to PNG for Claude to read.
    static func renderPages(of pdf: URL, into dir: URL, width: CGFloat = 1400) throws -> Int {
        guard let doc = PDFDocument(url: pdf) else { throw ClaudeCLI.CLIError.failed("Couldn't open the completed PDF.") }
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let png = renderPNG(page, width: width)
            try png?.write(to: dir.appendingPathComponent(String(format: "page-%02d.png", i + 1)))
        }
        return doc.pageCount
    }

    static func renderPNG(_ page: PDFPage, width: CGFloat, crop: CGRect? = nil) -> Data? {
        guard let image = render(page, width: width, crop: crop) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    /// Renders a page (or a crop of it, in page coordinates measured from the bottom-left) including annotations.
    static func render(_ page: PDFPage, width: CGFloat, crop: CGRect? = nil) -> CGImage? {
        let bounds = page.bounds(for: .cropBox)
        let area = crop ?? bounds
        let scale = width / area.width
        let w = Int(area.width * scale), h = Int(area.height * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -(area.minX - bounds.minX), y: -(area.minY - bounds.minY))
        page.draw(with: .cropBox, to: ctx)
        return ctx.makeImage()
    }

    static let schema: String = {
        let part: [String: Any] = ["type": "object", "required": ["label", "awarded", "available", "student_answer", "correct_answer", "feedback"],
                                   "properties": ["label": ["type": "string"], "awarded": ["type": "integer"], "available": ["type": "integer"],
                                                  "student_answer": ["type": "string"], "correct_answer": ["type": "string"], "feedback": ["type": "string"]]]
        let q: [String: Any] = ["type": "object",
                                "required": ["question_id", "number", "awarded", "available", "subtopic", "concept", "parts", "why_lost", "big_picture", "tip", "uncertain"],
                                "properties": ["question_id": ["type": "string"], "number": ["type": "integer"], "awarded": ["type": "integer"],
                                               "available": ["type": "integer"], "subtopic": ["type": "string"], "concept": ["type": "string"],
                                               "parts": ["type": "array", "items": part], "why_lost": ["type": "string"],
                                               "big_picture": ["type": "string"], "tip": ["type": "string"], "uncertain": ["type": "boolean"]]]
        let fix: [String: Any] = ["type": "object", "required": ["title", "detail", "wrong", "right", "subtopic", "questions"],
                                  "properties": ["title": ["type": "string"], "detail": ["type": "string"], "wrong": ["type": "string"],
                                                 "right": ["type": "string"], "subtopic": ["type": "string"],
                                                 "questions": ["type": "array", "items": ["type": "integer"]]]]
        let root: [String: Any] = ["type": "object",
                                   "required": ["session_id", "awarded", "available", "headline", "summary", "strengths", "focus_next", "fixes", "questions"],
                                   "properties": ["session_id": ["type": "string"], "awarded": ["type": "integer"], "available": ["type": "integer"],
                                                  "headline": ["type": "string"], "summary": ["type": "string"],
                                                  "strengths": ["type": "array", "items": ["type": "string"]],
                                                  "focus_next": ["type": "array", "items": ["type": "string"]],
                                                  "fixes": ["type": "array", "items": fix],
                                                  "questions": ["type": "array", "items": q]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: root), as: UTF8.self)
    }()

    /// Finds a Biosphere session id in a file name or in the PDF's own text (the footer carries it).
    static func sessionId(in url: URL) -> String? {
        let pattern = try! NSRegularExpression(pattern: "BS-[A-HJ-NP-Z2-9]{6}")
        func find(_ s: String) -> String? {
            pattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)).flatMap { Range($0.range, in: s).map { String(s[$0]) } }
        }
        if let id = find(url.lastPathComponent) { return id }
        guard let doc = PDFDocument(url: url) else { return nil }
        if let t = doc.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, let id = find(t) { return id }
        for i in 0..<min(doc.pageCount, 3) { if let s = doc.page(at: i)?.string, let id = find(s) { return id } }
        return nil
    }
}

/// Plans a session with Claude using the build-session skill.
struct SessionPlan: Codable {
    var title: String
    var rationale: String
    var questionIds: [String]

    /// Check Hank's plan against the exact pool allowed by her topic and question-format choices.
    func validatedQuestions(from pool: [Question]) throws -> [Question] {
        let allowed = Dictionary(uniqueKeysWithValues: pool.map { ($0.id, $0) })
        var seen: Set<String> = []
        return try questionIds.compactMap { id in
            guard let question = allowed[id] else {
                throw ClaudeCLI.CLIError.failed("Hank picked a question outside your chosen topic or question type. Try again.")
            }
            return seen.insert(id).inserted ? question : nil
        }
    }

    static let schema: String = {
        let root: [String: Any] = ["type": "object", "required": ["title", "rationale", "question_ids"],
                                   "properties": ["title": ["type": "string"], "rationale": ["type": "string"],
                                                  "question_ids": ["type": "array", "items": ["type": "string"]]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: root), as: UTF8.self)
    }()
}
