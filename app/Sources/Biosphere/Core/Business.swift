import AppKit
import CoreGraphics
import PDFKit

// MARK: - Business question bank

struct BusinessTopic: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var blurb: String
    var unit: String?
    var unitName: String?
    var hlOnly: Bool?
    var notesPage: Int?
    var notesY: Double?
    var notesHeading: String?
    var revisionDojoUrl: String?

    var displayName: String { id.hasPrefix("toolkit.") ? name : "\(id) · \(name)" }
}

struct BusinessPart: Codable, Hashable, Identifiable {
    var label: String            // "a", "b(i)", "3(a)", "7"
    var marks: Int
    var prompt: String
    var markscheme: String       // that part's markscheme section (with its N.B. caps)
    var topic: String
    var extended: Bool           // 10 / 17-markers: marked on bands, with essay feedback
    var command: String
    var choice: String?          // P1 Section B: answer one of the parts in this group
    var topics: [String]?
    var inSyllabus: Bool?
    var prerequisites: [String]?
    var msRegions: [Region]?     // Economics: crops of the official markscheme (pages of `CaseSubject.markschemeURL`)
    var id: String { label }
    var topicIds: [String] { topics ?? [topic] }
    var isCurrentContent: Bool { inSyllabus != false }
    var display: String { Self.display(label) }
    /// "b(i)" → "(b)(i)", "a" → "(a)"; numbered questions ("7", "3(a)") stay as they are.
    static func display(_ label: String) -> String {
        guard let first = label.first, first.isLetter else { return label }
        return "(\(first))" + label.dropFirst()
    }
}

/// A business question only makes sense with its case, so the unit is a set: one Paper 2 question
/// (stimulus + parts) or a whole Paper 1 / Paper 3.
struct BusinessSet: Codable, Identifiable, Hashable {
    var id: String               // 2025M-P2-TZ1-Q5, 2025M-P1-TZ1
    var session: String
    var paper: String
    var tz: String
    var number: String
    var company: String
    var currentSyllabus: Bool
    var marks: Int
    var minutes: Int
    var writesInPaper: Bool      // the paper has its own answer boxes (P2 since ~2020)
    var casePages: Int
    var topics: [String]
    var parts: [BusinessPart]
    var hasExtended: Bool
    var selectedLabels: [String]?
    var selectedTopicId: String?
    var markbands: String?

    var sourceLabel: String { "\(session) · Paper \(paper)\(tz == "TZ0" ? "" : " " + tz)\(number.isEmpty ? "" : " · Q\(number)")" }
    var title: String { company.isEmpty ? "Paper \(paper)" : company }
    var subject: CaseSubject { CaseSubject(setId: id) }
    var kindLabel: String {
        if selectedLabels != nil { return "Topic practice · Paper \(paper)" }
        if subject == .economics {
            return switch paper {
            case "1": "Paper 1 essay · explain (a), then evaluate (b)"
            case "3": "Paper 3 policy question"
            default: "Paper 2 data response"
            }
        }
        return switch paper {
        case "1": "Whole Paper 1 · case study"
        case "3": "Whole Paper 3 · social enterprise"
        default: hasExtended ? "Paper 2 question with a 10-marker" : "Paper 2 short question"
        }
    }
    func parts(in topic: String) -> [BusinessPart] {
        parts.filter { $0.isCurrentContent && $0.topicIds.contains(topic) }
    }

    /// Keep the original case, tables and part labels while practising only chosen parts.
    /// Business Paper 3 stays whole because its plan integrates several business functions.
    func selecting(labels: [String]) -> BusinessSet? {
        guard !subject.keepsWhole(paper: paper) else { return self }
        let wanted = Set(labels)
        let chosen = parts.filter { wanted.contains($0.label) }
        guard !chosen.isEmpty, chosen.count == wanted.count else { return nil }
        var copy = self
        copy.parts = chosen.map { p in var p = p; p.choice = nil; return p }
        copy.selectedLabels = chosen.map(\.label)
        copy.marks = chosen.reduce(0) { $0 + $1.marks }
        let pace = Double(minutes) / Double(max(marks, 1))
        copy.minutes = max(5, Int(ceil(Double(copy.marks) * pace)))
        copy.hasExtended = chosen.contains { $0.extended }
        copy.topics = Array(Set(chosen.flatMap(\.topicIds))).sorted()
        return copy
    }

    func selecting(topic: String) -> BusinessSet? {
        var labels = Set(parts(in: topic).map(\.label))
        guard !labels.isEmpty else { return nil }
        var previousCount = -1
        while previousCount != labels.count {
            previousCount = labels.count
            for part in parts where labels.contains(part.label) {
                labels.formUnion(part.prerequisites ?? [])
            }
        }
        guard var selected = selecting(labels: parts.filter { labels.contains($0.label) }.map(\.label)) else { return nil }
        selected.selectedTopicId = topic
        return selected
    }
}

struct BusinessBank: Codable {
    var subject: String
    var slug: String
    var topics: [BusinessTopic]
    var sets: [BusinessSet]

    static func load(_ subject: CaseSubject = .business) throws -> BusinessBank {
        var bank = try JSON.load(BusinessBank.self, from: Workspace.bank.appendingPathComponent("\(subject.slug)/sets.json"))
        if let topics = try? JSON.load([BusinessTopic].self, from: Workspace.bank.appendingPathComponent("\(subject.slug)/topics.json")) {
            bank.topics = topics
        }
        return bank
    }
    var caseSubject: CaseSubject { CaseSubject(rawValue: slug) ?? .business }
    func set(_ id: String) -> BusinessSet? { sets.first { $0.id == id } }
    func topic(_ id: String) -> BusinessTopic? { topics.first { $0.id == id } }
    static func caseURL(_ id: String) -> URL { Workspace.root.appendingPathComponent(CaseSubject(setId: id).caseFile(id)) }
    static var notesURL: URL { Workspace.bank.appendingPathComponent("business-hl/notes.pdf") }

    /// A gentle first go: one Paper 2 question with a 10-marker (about 40 min), then the bigger papers.
    static let startHere = ["2025M-P2-TZ1-Q5", "2025M-P2-TZ1-Q1", "2025M-P1-TZ1", "2025N-P2-TZ1-Q5", "2025N-P3-TZ0"]
}

// MARK: - What Hank gets, and what comes back

/// Written to sessions/<id>/business.json for the mark-business skill.
struct BusinessKey: Codable {
    var sessionId: String
    var id: String
    var session: String
    var paper: String
    var company: String
    var marks: Int
    var writesInPaper: Bool
    var answerPages: [Int]       // 1-based pages of her PDF that hold her answers
    var parts: [BusinessPart]
    var currentSyllabus: Bool?
    var selectedLabels: [String]?
    var caseFile: String?
    var markbands: String?
    var sources: [BusinessKeySource]?
    var subject: String?         // "economics-hl"; nil = Business (keys written before Economics)

    var caseSubject: CaseSubject { subject.flatMap(CaseSubject.init(rawValue:)) ?? .business }
}

struct BusinessKeySource: Codable {
    var number: Int
    var setId: String
    var company: String
    var source: String
    var caseFile: String
    var markbands: String?
    var labels: [String: String] // paper label -> original label
}

struct BusinessPartResult: Codable, Hashable {
    var label: String
    var awarded: Int
    var available: Int
    var studentAnswer: String
    var correctAnswer: String
    var feedback: String
    var whyLost: String
    var tip: String
}

struct EssayStrand: Codable, Hashable { var name: String; var level: String; var comment: String }
struct EssaySentence: Codable, Hashable {
    var text: String
    var label: String
    var note: String
    var judgement: String? // strength / improve; independent of the assessment strand
    var anchors: [EssayAnchor]? // optional for results saved before paper annotations
    var lines: [String]?        // reader line ids (L1, L2…) the marker matched this sentence to
}

/// Coordinates in the full rendered page, normalized from its top-left corner.
struct EssayAnchor: Codable, Hashable {
    var page: Int
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && page > 0 && x >= 0 && y >= 0 &&
        width > 0 && height > 0 && x + width <= 1.0001 && y + height <= 1.0001
    }
}
struct EssayRewrite: Codable, Hashable { var original: String; var improved: String; var why: String }

struct EssayFeedback: Codable, Hashable {
    var label: String
    var band: String
    var strands: [EssayStrand]
    var capsHit: [String]
    var pointsHit: [String]
    var pointsMissed: [String]
    var sentences: [EssaySentence]
    var rewrite: EssayRewrite
    var nextTime: String
}

struct BusinessResult: Codable, Hashable {
    var sessionId: String
    var awarded: Int
    var available: Int
    var headline: String
    var summary: String
    var strengths: [String]
    var fixes: [Fix]
    var parts: [BusinessPartResult]
    var essays: [EssayFeedback]
    var transcriptionNote: String
}

/// One line per marked set in ~/Biosphere/business_history.json, so Hank can spot habits.
struct BusinessHistoryEntry: Codable {
    var sessionId: String
    var setId: String
    var date: Date
    var company: String
    var awarded: Int
    var available: Int
    var lostByTopic: [String: Int]
    var capsHit: [String]
    var fixes: [String]
}

enum BusinessMarking {
    enum ValidationError: LocalizedError {
        case invalidResult
        var errorDescription: String? { "Hank's marks didn't match the selected question parts. Please try marking again." }
    }

    /// Prevent a partial topic session from being graded against the unselected full paper.
    static func validate(_ result: BusinessResult, key: BusinessKey) throws {
        guard Set(key.parts.map(\.label)).count == key.parts.count else { throw ValidationError.invalidResult }
        let expected = Dictionary(uniqueKeysWithValues: key.parts.map { ($0.label, $0) })
        let received = result.parts.map(\.label)
        guard result.sessionId == key.sessionId, Set(received).count == received.count,
              result.available == key.marks,
              result.awarded == result.parts.reduce(0, { $0 + $1.awarded }),
              result.available == result.parts.reduce(0, { $0 + $1.available }) else {
            throw ValidationError.invalidResult
        }
        for part in result.parts {
            guard let source = expected[part.label], part.available == source.marks,
                  (0...part.available).contains(part.awarded) else { throw ValidationError.invalidResult }
        }
        let mandatory = key.parts.filter { $0.choice == nil }.map(\.label)
        guard Set(mandatory).isSubset(of: Set(received)) else { throw ValidationError.invalidResult }
        for group in Set(key.parts.compactMap(\.choice)) {
            guard key.parts.filter({ $0.choice == group && received.contains($0.label) }).count == 1 else {
                throw ValidationError.invalidResult
            }
        }
        let essayLabels = result.essays.map(\.label)
        guard Set(essayLabels).count == essayLabels.count,
              Set(essayLabels) == Set(received.filter { expected[$0]?.extended == true }) else {
            throw ValidationError.invalidResult
        }
        for sentence in result.essays.flatMap(\.sentences) {
            guard sentence.judgement == nil || ["strength", "improve"].contains(sentence.judgement!),
                  (sentence.anchors ?? []).allSatisfy({ $0.isValid && key.answerPages.contains($0.page) }) else {
                throw ValidationError.invalidResult
            }
        }
    }

    static let schema: String = {
        func str() -> [String: Any] { ["type": "string"] }
        func int() -> [String: Any] { ["type": "integer"] }
        func arr(_ items: [String: Any]) -> [String: Any] { ["type": "array", "items": items] }
        func obj(_ props: [String: Any]) -> [String: Any] { ["type": "object", "required": Array(props.keys), "properties": props] }
        let essay = obj([
            "label": str(), "band": str(),
            "strands": arr(obj(["name": str(), "level": str(), "comment": str()])),
            "caps_hit": arr(str()), "points_hit": arr(str()), "points_missed": arr(str()),
            "sentences": arr(obj(["text": str(), "label": ["type": "string", "enum": ["knowledge", "application", "analysis", "evaluation", "none"]], "note": str(),
                "judgement": ["type": "string", "enum": ["strength", "improve"]], "lines": arr(str())])),
            "rewrite": obj(["original": str(), "improved": str(), "why": str()]),
            "next_time": str(),
        ])
        let root = obj([
            "session_id": str(), "awarded": int(), "available": int(), "headline": str(), "summary": str(),
            "strengths": arr(str()),
            "fixes": arr(obj(["title": str(), "detail": str(), "wrong": str(), "right": str(), "subtopic": str(), "questions": arr(int())])),
            "parts": arr(obj(["label": str(), "awarded": int(), "available": int(), "student_answer": str(), "correct_answer": str(),
                              "feedback": str(), "why_lost": str(), "tip": str()])),
            "essays": arr(essay),
            "transcription_note": str(),
        ])
        return String(decoding: try! JSONSerialization.data(withJSONObject: root), as: UTF8.self)
    }()
}

// MARK: - The PDF: guide → case → answer space

enum BusinessComposer {
    typealias P = PDFComposer
    struct Output { var pageCount: Int; var answerPages: [Int] }

    static let ink = NSColor(calibratedRed: 0.12, green: 0.08, blue: 0.2, alpha: 1)
    static let grey = NSColor(white: 0.3, alpha: 1)

    static func compose(session: StudySession, set: BusinessSet, to url: URL, includeGuide: Bool = true, forceAnswerPages: Bool = false, pageOffset: Int = 0, caseURL: URL? = nil) throws -> Output {
        var box = CGRect(origin: .zero, size: P.page)
        let info: [CFString: Any] = [kCGPDFContextTitle: "Biosphere \(session.id) – \(session.title)", kCGPDFContextCreator: "Biosphere"]
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { throw PDFComposer.ComposeError.cannotCreate }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        defer { NSGraphicsContext.current = nil }
        guard let caseDoc = CGPDFDocument((caseURL ?? BusinessBank.caseURL(set.id)) as CFURL) else { throw PDFComposer.ComposeError.missingPaper(set.id) }

        var pageNumber = pageOffset
        var y: CGFloat = 0
        let bottom = P.page.height - P.bottom
        func begin() { ctx.beginPDFPage(nil); pageNumber += 1; y = P.top; P.drawFooter(ctx: ctx, session: session, pageNumber: pageNumber) }
        func end() { ctx.endPDFPage() }
        /// Wrapped text that moves to a new page when it doesn't fit.
        func para(_ s: String, size: CGFloat = 10.5, weight: NSFont.Weight = .regular, color: NSColor = grey, indent: CGFloat = 0, gap: CGFloat = 6) {
            let w = P.contentWidth - indent
            let h = measure(s, width: w, size: size, weight: weight)
            if y + h > bottom { end(); begin() }
            draw(s, x: P.side + indent, top: y, width: w, size: size, weight: weight, color: color)
            y += h + gap
        }
        func heading(_ s: String) {
            if y + 40 > bottom { end(); begin() }
            y += 6
            P.drawText(s.uppercased(), rect: P.rectFromTop(x: P.side, top: y, width: P.contentWidth, height: 13), size: 9, weight: .bold, color: P.purple)
            y += 18
        }

        // 1. The guide: what to do, and why it earns marks.
        let subject = session.caseSubject ?? set.subject
        if includeGuide {
        begin()
        y = drawBanner(ctx: ctx, session: session, set: set, subject: subject)
        if set.selectedLabels != nil {
            para("Topic practice: answer ONLY these parts: " + set.parts.map { "\($0.display) [\($0.marks)]" }.joined(separator: " · ") + ". The complete original case is included so you have every table and reference you need.",
                 size: 11.5, weight: .medium, color: ink, gap: 6)
        }
        let reading = subject == .business ? "case" : set.paper == "1" ? "question" : "texts and data"
        para(set.writesInPaper
             ? (set.selectedLabels == nil
                ? "Read the \(reading), then answer every part in the box under it, like the real Paper \(set.paper). The \(reading) starts on the next page."
                : "Read the \(reading), then answer the selected parts in their original answer boxes. Leave the other boxes blank. The \(reading) starts on the next page.")
             : "Read the \(reading) first (it starts on the next page). Your answer pages are at the end: each question is printed again with lines under it, so you write right below the question.",
             size: 11.5, weight: .medium, color: ink, gap: 4)
        para(subject == .business && set.paper == "1" && set.selectedLabels == nil ? "Section B: answer ONE of the two 10-markers, like in the exam." : "", size: 10.5, color: ink, gap: 2)
        para("The timer is optional. Use it when you want exam practice; leave it off when you're learning.", size: 10, color: grey, gap: 4)

        heading("What each command word wants, and why")
        for (word, rule) in subject.commandRules {
            let colW: CGFloat = 132
            let h = max(measure("**\(word)**", width: colW - 8, size: 10), measure(rule, width: P.contentWidth - colW, size: 10))
            if y + h > bottom { end(); begin() }
            draw("**\(word)**", x: P.side + 4, top: y, width: colW - 8, size: 10, color: ink)
            draw(rule, x: P.side + colW, top: y, width: P.contentWidth - colW, size: 10, color: grey)
            y += h + 6
        }
        for section in subject.guideSections(for: set) {
            heading(section.title)
            for s in section.lines { para(s, size: 10, indent: 4, gap: 5) }
        }
        end()
        }

        // 2. The case, original pages scaled into the margins.
        var casePageNumbers: [Int] = []
        for i in 1...max(caseDoc.numberOfPages, 1) {
            guard let pg = caseDoc.page(at: i) else { continue }
            begin()
            casePageNumbers.append(pageNumber)
            let src = pg.getBoxRect(.cropBox)
            if forceAnswerPages {
                P.drawText(set.title + " · original case", rect: P.rectFromTop(x: P.side, top: 14, width: P.contentWidth, height: 18), size: 10, weight: .bold, color: ink)
            }
            let area = CGRect(x: 16, y: 34, width: P.page.width - 32, height: P.page.height - 34 - (forceAnswerPages ? 40 : 14))
            let scale = min(area.width / src.width, area.height / src.height)
            let dest = CGRect(x: area.midX - src.width * scale / 2, y: area.maxY - src.height * scale, width: src.width * scale, height: src.height * scale)
            P.drawCrop(ctx: ctx, page: pg, src: src, dest: dest)
            end()
        }
        if set.writesInPaper && !forceAnswerPages {
            ctx.closePDF()
            return Output(pageCount: pageNumber - pageOffset, answerPages: casePageNumbers)
        }

        // 3. Answer pages: each question printed again with its lines right under it.
        var answerPages: [Int] = []
        begin(); answerPages.append(pageNumber)
        if forceAnswerPages { para(set.title + " · answer the parts below", size: 13, weight: .bold, color: ink, gap: 12) }
        func lines(_ n: Int) {
            var left = n
            ctx.setLineWidth(0.6)
            while left > 0 {
                if y + 24 > bottom { end(); begin(); answerPages.append(pageNumber) }
                ctx.setStrokeColor(NSColor(calibratedWhite: 0.80, alpha: 1).cgColor)
                ctx.move(to: CGPoint(x: P.side + 6, y: P.page.height - y - 20))
                ctx.addLine(to: CGPoint(x: P.page.width - P.side - 6, y: P.page.height - y - 20))
                ctx.strokePath()
                y += 24; left -= 1
            }
            y += 10
        }
        var choiceShown = false
        for part in set.parts {
            if let group = part.choice {
                if choiceShown { continue }
                choiceShown = true
                let options = set.parts.filter { $0.choice == group }
                if y + 140 > bottom { end(); begin(); answerPages.append(pageNumber) }
                P.drawText("SECTION B · ANSWER ONE OF THESE (write its number at the start)", rect: P.rectFromTop(x: P.side, top: y, width: P.contentWidth, height: 13),
                           size: 9, weight: .bold, color: P.purple)
                y += 18
                for o in options { y = drawPartHeader(ctx: ctx, part: o, top: y) + 4 }
                lines(64)
                continue
            }
            let needed = 30 + measure(part.prompt, width: P.contentWidth - 120, size: 10.5, weight: .medium) + 24 * 3
            if y + needed > bottom { end(); begin(); answerPages.append(pageNumber) }
            y = drawPartHeader(ctx: ctx, part: part, top: y) + 2
            lines(linesFor(part))
        }
        end()
        ctx.closePDF()
        return Output(pageCount: pageNumber - pageOffset, answerPages: answerPages)
    }

    static func linesFor(_ p: BusinessPart) -> Int {
        switch p.marks {
        case ..<2: 3
        case 2: 5
        case 3...4: 8
        case 5...6: 12
        case 7...9: 18
        case 10...12: 64
        default: 100
        }
    }

    // MARK: guide text (every rule comes from the markbands and 2024–25 markschemes)

    static let commandRules: [(String, String)] = [
        ("State / Identify  [1–2]", "Just name it. **Why:** the markscheme says no description or application is needed, so more writing only costs you time."),
        ("Define  [2]", "The precise textbook definition. **Why:** a vague idea gets only 1 of the 2 marks. You don't need the case."),
        ("Describe  [2–4]", "Say what it is, then connect it to the company. **Why:** each point's second mark is for linking it to the case."),
        ("Explain  [2–6]", "Point → why → use the case. **Why:** 1 mark is for the idea; the other mark is only given if you apply it to this company. This is where most marks go missing."),
        ("Calculate  [1–4]", "Show your working and the units. **Why:** the method marks are for the working, so a bare answer often gets just 1 mark."),
        ("Comment / Analyse", "Say what the result means for this business. **Why:** repeating the number scores little; the meaning is what scores."),
        ("Discuss / Evaluate / Recommend  [10]", "Weigh both sides and decide. **Why:** see the five steps below."),
    ]

    static let tenMarkerSteps = [
        "**1. Define the key term and restate the decision.** Why: the first thing the markband checks is whether you understood what the question demands.",
        "**2. Two arguments for, two against.** Why: a one-sided answer is capped at 4/10, and 7+ needs \"some balance\".",
        "**3. In every argument: point → theory → evidence from the case (numbers, line references) → \"so… which means…\" for the business.** Why: just naming the company counts as superficial (3–4 band). The \"so… which means\" link is what examiners call analysis.",
        "**4. Work out one number from the table if there is one.** Why: some markschemes cap you at 6 if you ignore the table or figure the question names.",
        "**5. Limitations, then a judgement.** Why: 9–10 needs you to explain what the case doesn't tell you, and a \"should they?\" question with no clear decision is capped at 7–8.",
    ]

    static let paper3Steps = [
        "**A · Use of resources (4):** use at least four resources inside your plan. Why: the mark counts how many resources support your plan, not how many you mention.",
        "**B · Tools and theories (4):** apply tools that drive your decisions (Gantt chart, Ansoff, finance, motivation…). Why: a tool only scores when it does work for the plan.",
        "**C · Evaluation (6):** judge the impact on HR, marketing, finance and operations, and the trade-offs between them. Why: it's the biggest criterion, and a descriptive plan stays in the bottom band.",
        "**D · Sequencing (3):** what happens first, next, and why. Why: a clear order earns its own 3 marks, even if the rest is weaker.",
    ]

    static let swotWhy = "SWOT and STEEPLE are tools for **listing** a situation, but a 10-marker asks you to **weigh a decision**. Boxes filled with facts copied from the case show no reasoning, so they earn nothing, and they eat the time you need for the \"so… which means\" and the judgement. On Paper 3, examiners are told a plan built around a copied SWOT or STEEPLE is inappropriate and must lose marks. **Use a tool only when it changes your answer:** Ansoff to judge how risky a growth option is, force field to weigh the forces for and against a change, a decision tree or payback when there are numbers. **If the question names a tool, you must use it.**"

    // MARK: drawing helpers

    /// Text with **bold** segments (drawn darker, so key words stand out).
    static func rich(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping; p.lineSpacing = size * 0.2
        let out = NSMutableAttributedString()
        for (i, chunk) in s.components(separatedBy: "**").enumerated() where !chunk.isEmpty {
            let bold = i % 2 == 1
            out.append(NSAttributedString(string: chunk, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: bold ? .bold : weight),
                .foregroundColor: bold ? (color == grey ? ink : color) : color, .paragraphStyle: p]))
        }
        return out
    }

    static func measure(_ s: String, width: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        guard !s.isEmpty else { return 0 }
        return ceil(rich(s, size: size, weight: weight, color: grey)
            .boundingRect(with: CGSize(width: width, height: 4000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    static func draw(_ s: String, x: CGFloat, top: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .black) {
        guard !s.isEmpty else { return }
        let h = measure(s, width: width, size: size, weight: weight) + size   // a little slack so the last line never clips
        rich(s, size: size, weight: weight, color: color)
            .draw(with: CGRect(x: x, y: P.page.height - top - h, width: width, height: h), options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    static func drawBanner(ctx: CGContext, session: StudySession, set: BusinessSet, subject: CaseSubject) -> CGFloat {
        let band = P.rectFromTop(x: 0, top: 0, width: P.page.width, height: 104)
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [NSColor(calibratedRed: 0.36, green: 0.16, blue: 0.70, alpha: 1).cgColor,
                                       NSColor(calibratedRed: 0.62, green: 0.36, blue: 0.93, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
        ctx.saveGState(); ctx.clip(to: band)
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: band.midY), end: CGPoint(x: P.page.width, y: band.midY), options: [])
        ctx.restoreGState()
        P.drawText("BIOSPHERE  ·  \(subject.name.uppercased())  ·  \(session.id)", rect: P.rectFromTop(x: P.side, top: 16, width: 420, height: 14),
                   size: 9, weight: .semibold, color: NSColor(white: 1, alpha: 0.75))
        P.drawText(set.title, rect: P.rectFromTop(x: P.side, top: 32, width: P.contentWidth, height: 28), size: 21, weight: .bold, color: .white)
        P.drawText("\(set.sourceLabel)  ·  \(set.marks) marks  ·  about \(set.minutes) min", rect: P.rectFromTop(x: P.side, top: 62, width: P.contentWidth, height: 16),
                   size: 11, color: NSColor(white: 1, alpha: 0.92))
        P.drawText("HOW TO GET THE MARKS", rect: P.rectFromTop(x: P.side, top: 82, width: P.contentWidth, height: 14),
                   size: 9, weight: .bold, color: NSColor(white: 1, alpha: 0.8))
        return 118
    }

    /// Label pill, the question, and its marks. Returns the bottom.
    static func drawPartHeader(ctx: CGContext, part: BusinessPart, top: CGFloat) -> CGFloat {
        let textW = P.contentWidth - 120
        let h = max(18, measure(part.prompt, width: textW, size: 10.5, weight: .medium))
        let r = P.rectFromTop(x: P.side, top: top, width: P.contentWidth, height: h + 12)
        ctx.setFillColor(P.lilac.cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath()
        let pill = P.rectFromTop(x: P.side + 6, top: top + 6, width: 52, height: 18)
        ctx.setFillColor(P.purple.cgColor)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 5, cornerHeight: 5, transform: nil)); ctx.fillPath()
        P.drawText(part.display, rect: pill.insetBy(dx: 2, dy: 3).offsetBy(dx: 0, dy: -1), size: 9.5, weight: .bold, color: .white, align: .center)
        draw(part.prompt, x: P.side + 66, top: top + 6, width: textW, size: 10.5, weight: .medium, color: ink)
        P.drawText("[\(part.marks)]", rect: P.rectFromTop(x: P.page.width - P.side - 50, top: top + 7, width: 44, height: 14),
                   size: 9.5, weight: .bold, color: P.purple, align: .right)
        return top + h + 12
    }
}
