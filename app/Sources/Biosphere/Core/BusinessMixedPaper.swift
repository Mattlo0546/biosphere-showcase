import AppKit
import PDFKit

/// Stable question identifiers prevent part (a) in one case being marked against another case.
enum BusinessMixedPaper {
    static func label(caseNumber: Int, original: String) -> String { "\(caseNumber).\(original)" }

    static func numbered(_ set: BusinessSet, caseNumber: Int) -> BusinessSet {
        var copy = set
        copy.company = "\(set.subject == .business ? "Case" : "Question") \(caseNumber) · \(set.title)"
        copy.parts = set.parts.map { part in
            var part = part
            part.label = label(caseNumber: caseNumber, original: part.label)
            part.prerequisites = part.prerequisites?.map { label(caseNumber: caseNumber, original: $0) }
            return part
        }
        copy.selectedLabels = copy.parts.map(\.label)
        return copy
    }

    static func combined(session: StudySession, sets: [BusinessSet]) -> BusinessSet {
        let parts = sets.enumerated().flatMap { index, set in
            numbered(set, caseNumber: index + 1).parts.map { part in
                var part = part
                part.prompt = "\(set.subject == .business ? "Case" : "Question") \(index + 1) · \(set.title): " + part.prompt
                return part
            }
        }
        return BusinessSet(id: session.id, session: "Topical practice", paper: "mixed", tz: "TZ0", number: "",
                           company: session.title, currentSyllabus: true, marks: parts.reduce(0) { $0 + $1.marks },
                           minutes: session.minutes, writesInPaper: false, casePages: sets.reduce(0) { $0 + $1.casePages },
                           topics: Array(Set(parts.flatMap(\.topicIds))).sorted(), parts: parts,
                           hasExtended: parts.contains { $0.extended }, selectedLabels: parts.map(\.label))
    }

    static func sources(_ sets: [BusinessSet]) -> [BusinessKeySource] {
        sets.enumerated().map { index, set in
            BusinessKeySource(number: index + 1, setId: set.id, company: set.title, source: set.sourceLabel,
                              caseFile: set.subject.caseFile(set.id), markbands: set.markbands,
                              labels: Dictionary(uniqueKeysWithValues: set.parts.map { (label(caseNumber: index + 1, original: $0.label), $0.label) }))
        }
    }

    static func compose(session: StudySession, sets: [BusinessSet], to url: URL,
                        caseURL: (String) -> URL = BusinessBank.caseURL) throws -> BusinessComposer.Output {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("business-paper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let cover = temporary.appendingPathComponent("cover.pdf")
        try makeCover(session: session, sets: sets, to: cover)
        guard let document = PDFDocument(url: cover) else { throw PDFComposer.ComposeError.cannotCreate }
        var answerPages: [Int] = []
        for (index, set) in sets.enumerated() {
            let componentURL = temporary.appendingPathComponent("case-\(index).pdf")
            let out = try BusinessComposer.compose(session: session, set: numbered(set, caseNumber: index + 1), to: componentURL,
                                                    includeGuide: false, forceAnswerPages: true,
                                                    pageOffset: document.pageCount, caseURL: caseURL(set.id))
            guard let component = PDFDocument(url: componentURL) else { throw PDFComposer.ComposeError.cannotCreate }
            for i in 0..<component.pageCount {
                if let page = component.page(at: i) { document.insert(page, at: document.pageCount) }
            }
            answerPages.append(contentsOf: out.answerPages)
        }
        guard document.write(to: url) else { throw PDFComposer.ComposeError.cannotCreate }
        return .init(pageCount: document.pageCount, answerPages: answerPages)
    }

    private static func makeCover(session: StudySession, sets: [BusinessSet], to url: URL) throws {
        typealias P = PDFComposer
        var box = CGRect(origin: .zero, size: P.page)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw PDFComposer.ComposeError.cannotCreate }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = nil }
        var page = 1
        var y = P.top
        func begin() { context.beginPDFPage(nil); y = P.top; P.drawFooter(ctx: context, session: session, pageNumber: page) }
        func text(_ value: String, size: CGFloat = 11, weight: NSFont.Weight = .regular, color: NSColor = BusinessComposer.grey) {
            let height = BusinessComposer.measure(value, width: P.contentWidth, size: size, weight: weight)
            if y + height > P.page.height - P.bottom { context.endPDFPage(); page += 1; begin() }
            BusinessComposer.draw(value, x: P.side, top: y, width: P.contentWidth, size: size, weight: weight, color: color)
            y += height + 12
        }
        begin()
        let subject = session.caseSubject ?? sets.first?.subject ?? .business
        let word = subject == .business ? "case" : "question"
        text("BIOSPHERE · \(subject.name.uppercased()) · \(session.id)", size: 10, weight: .bold, color: P.purple)
        text(session.title, size: 24, weight: .bold, color: BusinessComposer.ink)
        text("\(session.totalMarks) marks · about \(session.minutes) minutes · \(sets.count) \(word)\(sets.count == 1 ? "" : "s")", size: 13)
        text("Read each original \(word), then write on the lined answer pages immediately after it. Answer ONLY the questions repeated on those answer pages. Other questions and boxes in the original \(word) are included for context.", weight: .medium, color: BusinessComposer.ink)
        text("Your question numbers start with the \(word) number: 2.b means \(word) 2, original part (b). All listed questions are required, including any earlier calculation needed by a later part.")
        text("IN THIS PAPER", size: 10, weight: .bold, color: P.purple)
        for (index, set) in sets.enumerated() {
            text("\(word.capitalized) \(index + 1) · \(set.title)\n\(set.sourceLabel)\n" + set.parts.map { "\(label(caseNumber: index + 1, original: $0.label)) [\($0.marks)]" }.joined(separator: " · "), size: 11, weight: .medium)
        }
        text("FOR EVERY ANSWER", size: 10, weight: .bold, color: P.purple)
        text(subject == .business
             ? "Explain: point → why → evidence from this case. Calculate: show your working and units. Evaluate: weigh both sides, explain their impact on this business, then justify your judgement."
             : "Define: the precise definition. Calculate: show your working, units, 2 decimal places. Diagrams: fully labelled, and explained in your words. Discuss / evaluate: theory, the text and data, a diagram, both sides, then a judgement.")
        context.endPDFPage(); context.closePDF()
    }
}
