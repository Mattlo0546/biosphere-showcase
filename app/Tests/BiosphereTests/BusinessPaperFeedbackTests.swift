import XCTest
import PDFKit
@testable import Biosphere

final class BusinessPaperFeedbackTests: XCTestCase {
    let output = URL(fileURLWithPath: "/tmp/biosphere-business-qa")
    private var app: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private func session() -> StudySession {
        StudySession(id: "BS-QATEST", title: "Finance and marketing", subtitle: "Business HL", kind: .custom,
                     scope: ["3.1", "4.1"], questionIds: [], totalMarks: 4, minutes: 30, createdAt: Date(), status: .ready)
    }
    private func result(_ anchors: [EssayAnchor]? = nil) -> BusinessResult {
        .init(sessionId: "BS-QATEST", awarded: 6, available: 10, headline: "Use the case to support your decision", summary: "",
              strengths: [], fixes: [], parts: [.init(label: "1.d", awarded: 6, available: 10, studentAnswer: "", correctAnswer: "", feedback: "", whyLost: "", tip: "")],
              essays: [.init(label: "1.d", band: "5–6", strands: [], capsHit: [], pointsHit: [], pointsMissed: [],
                             sentences: [.init(text: "Lower prices may increase sales, which improves cash flow.", label: "analysis",
                                               note: "Good chain of reasoning: sales lead to cash flow.", judgement: "strength", anchors: anchors)],
                             rewrite: .init(original: "", improved: "", why: ""), nextTime: "Use evidence from the case.")], transcriptionNote: "")
    }
    func testMixedPaperKeepsDuplicateOriginalLabelsDistinctAndPersistsSources() throws {
        let bank = try JSON.load(BusinessBank.self, from: app.appendingPathComponent("Resources/bank/business-hl/sets.json"))
        let first = try XCTUnwrap(bank.set("2025M-P2-TZ1-Q1"))
        let second = try XCTUnwrap(bank.set("2025M-P2-TZ1-Q5"))
        let sets = try [first, second].map { try XCTUnwrap($0.selecting(labels: [$0.parts[0].label])) }
        var saved = session()
        saved.businessComponents = sets.map { .init(setId: $0.id, labels: $0.parts.map(\.label)) }
        let combined = BusinessMixedPaper.combined(session: saved, sets: sets)
        XCTAssertEqual(Set(combined.parts.map(\.label)).count, 2)
        XCTAssertEqual(combined.parts[0].markscheme, sets[0].parts[0].markscheme)
        XCTAssertEqual(combined.parts[1].markscheme, sets[1].parts[0].markscheme)
        XCTAssertEqual(combined.marks, sets.reduce(0) { $0 + $1.marks })
        XCTAssertEqual(try JSON.decoder.decode(StudySession.self, from: JSON.encoder.encode(saved)).businessComponents, saved.businessComponents)
        XCTAssertEqual(BusinessMixedPaper.sources(sets)[1].labels[combined.parts[1].label], sets[1].parts[0].label)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let url = output.appendingPathComponent("mixed-paper.pdf")
        let built = try BusinessMixedPaper.compose(session: saved, sets: sets, to: url) { id in
            self.app.appendingPathComponent("Resources/bank/business-hl/cases/\(id).pdf")
        }
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(built.pageCount, document.pageCount)
        XCTAssertFalse(built.answerPages.isEmpty)
        XCTAssertTrue(built.answerPages.allSatisfy { $0 > 1 && $0 <= built.pageCount })
        let answerText = built.answerPages.compactMap { document.page(at: $0 - 1)?.string }.joined(separator: "\n")
        XCTAssertTrue(answerText.contains(combined.parts[0].label))
        XCTAssertTrue(answerText.contains(combined.parts[1].label))
    }
    func testCommentsUsePageCoordinatesAndLeaveOriginalPaperUntouched() throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let source = output.appendingPathComponent("submitted-paper.pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = try XCTUnwrap(CGContext(source as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        PDFComposer.drawText("Lower prices may increase sales,", rect: CGRect(x: 60, y: 658, width: 460, height: 20), size: 15)
        PDFComposer.drawText("which improves cash flow.", rect: CGRect(x: 60, y: 626, width: 460, height: 20), size: 15)
        NSGraphicsContext.current = nil
        context.endPDFPage(); context.closePDF()
        let before = try Data(contentsOf: source)
        let anchors = [EssayAnchor(page: 1, x: 0.098, y: 0.193, width: 0.40, height: 0.023),
                       EssayAnchor(page: 1, x: 0.098, y: 0.231, width: 0.31, height: 0.023)]
        let marked = output.appendingPathComponent("marked-paper.pdf")
        XCTAssertEqual(try BusinessAnnotations.write(result: result(anchors), source: source, to: marked), 2)
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertEqual(PDFDocument(url: source)?.page(at: 0)?.annotations.count, 0)
        let page = try XCTUnwrap(PDFDocument(url: marked)?.page(at: 0))
        let comments = page.annotations.filter { BusinessAnnotations.commentNumber($0) == 1 }
        XCTAssertEqual(comments.count, 3) // PDFKit also writes a popup for the sticky note
        XCTAssertEqual(comments.filter { $0.type == "Highlight" }.count, 2)
        let rect = BusinessAnnotations.rect(anchors[0], bounds: box)
        XCTAssertEqual(rect.maxY, box.height * (1 - anchors[0].y), accuracy: 0.001)
    }
    func testLocationUpdatesCannotChangeGradesAndRejectUnknownSentences() throws {
        let original = result()
        let location = BusinessAnnotations.LocatedSentence(part: "1.d", index: 0, judgement: "improve", note: "Use a number from the case.",
                                                           anchors: [.init(page: 4, x: 0.2, y: 0.3, width: 0.5, height: 0.02)])
        let updated = try BusinessAnnotations.apply(.init(sentences: [location]), to: original, answerPages: [4])
        XCTAssertEqual(updated.parts, original.parts)
        XCTAssertEqual(updated.awarded, original.awarded)
        XCTAssertEqual(updated.essays[0].band, original.essays[0].band)
        XCTAssertEqual(updated.essays[0].sentences[0].text, original.essays[0].sentences[0].text)
        XCTAssertEqual(updated.essays[0].sentences[0].anchors?.first?.page, 4)
        XCTAssertThrowsError(try BusinessAnnotations.apply(.init(sentences: [location]), to: original, answerPages: [3]))
        XCTAssertThrowsError(try BusinessAnnotations.apply(.init(sentences: [location, location]), to: original, answerPages: [4]))
        XCTAssertThrowsError(try BusinessAnnotations.apply(.init(sentences: []), to: original, answerPages: [4]))
        XCTAssertFalse(EssayAnchor(page: 1, x: 0.9, y: 0, width: 0.2, height: 0.1).isValid)
        XCTAssertFalse(EssayAnchor(page: 1, x: 0, y: 0, width: .nan, height: 0.1).isValid)
    }
    func testOlderFeedbackStillDecodesWithoutLocations() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSON.encoder.encode(result())) as? [String: Any])
        var essays = try XCTUnwrap(json["essays"] as? [[String: Any]])
        var sentences = try XCTUnwrap(essays[0]["sentences"] as? [[String: Any]])
        sentences[0].removeValue(forKey: "judgement"); sentences[0].removeValue(forKey: "anchors")
        essays[0]["sentences"] = sentences; json["essays"] = essays
        let decoded = try JSON.decoder.decode(BusinessResult.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.essays[0].sentences[0].anchors)
        XCTAssertNil(decoded.essays[0].sentences[0].judgement)
    }
}
