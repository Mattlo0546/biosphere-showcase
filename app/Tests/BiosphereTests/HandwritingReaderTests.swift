import XCTest
import PDFKit
@testable import Biosphere

/// The cheap-reader pipeline: finding her ink locally, settling what the app can settle, and making sure
/// the marking model gets text (and line ids) instead of page images.
final class HandwritingReaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("biosphere-reader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    /// A printed page, optionally with "handwriting" (wavy strokes) on given lines (points from the top).
    private func paper(_ name: String, pages: Int = 1, handwriting: [CGFloat] = [], shade: Bool = false) throws -> URL {
        let url = directory.appendingPathComponent(name)
        var box = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        for _ in 0..<pages {
            ctx.beginPDFPage(nil)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            PDFComposer.drawText("Question 1  ·  Explain why cash flow matters. [4]", rect: CGRect(x: 40, y: 760, width: 500, height: 20), size: 13)
            PDFComposer.drawText("Biosphere · BS-TESTAA", rect: CGRect(x: 40, y: 14, width: 300, height: 12), size: 8)
            NSGraphicsContext.current = nil
            if shade { ctx.setFillColor(gray: 0.5, alpha: 1); ctx.fill(box) }
            ctx.setStrokeColor(red: 0.1, green: 0.1, blue: 0.6, alpha: 1)
            ctx.setLineWidth(1.6)
            for top in handwriting {
                let y = box.height - top
                ctx.move(to: CGPoint(x: 60, y: y))
                for x in stride(from: 60.0, through: 420.0, by: 6) { ctx.addLine(to: CGPoint(x: x, y: y + (Int(x) % 12 == 0 ? 7 : -1))) }
                ctx.strokePath()
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    // MARK: ink

    func testInkIsOnlyHerWritingAndEachLineGetsItsOwnRectangle() throws {
        let original = try paper("sent.pdf")
        let completed = try paper("back.pdf", handwriting: [200, 240, 400])
        let page = try XCTUnwrap(Ink.pages(original: original, completed: completed).first)
        XCTAssertTrue(page.canSeparateInk)
        // The printed question has no ink; her lines do.
        let header = 0..<Int(0.12 * Double(page.height))
        XCTAssertFalse(page.hasInk(rows: header))
        let lines = Ink.lines(on: page)
        XCTAssertEqual(lines.count, 3)
        for (line, top) in zip(lines, [200.0, 240.0, 400.0]) {
            let anchor = line.anchor
            XCTAssertTrue(anchor.isValid)
            XCTAssertEqual(anchor.y + anchor.height / 2, top / 841.89, accuracy: 0.015)
            XCTAssertEqual(anchor.x, 60 / 595.28, accuracy: 0.02)
            XCTAssertEqual(anchor.x + anchor.width, 420 / 595.28, accuracy: 0.02)
        }
        let tags = lines.enumerated().map { (line: $1, id: "L\($0 + 1)") }
        let png = try XCTUnwrap(Ink.sheet(page, rows: 0..<page.height, tags: tags))
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(image.pixelsWide, page.width + 76)   // the gutter carries the line ids
    }

    func testPapersThatDontLineUpFallBackToThePlainPage() throws {
        let original = try paper("sent.pdf")
        let twoPages = try paper("back-2.pdf", pages: 2, handwriting: [200])
        XCTAssertFalse(try Ink.pages(original: original, completed: twoPages).contains(where: \.canSeparateInk))
        let rescanned = try paper("back-grey.pdf", handwriting: [200], shade: true)
        let page = try XCTUnwrap(Ink.pages(original: original, completed: rescanned).first)
        XCTAssertFalse(page.canSeparateInk)
        XCTAssertTrue(Ink.lines(on: page).isEmpty)
        XCTAssertNotNil(Ink.sheet(page, rows: 0..<100))
    }

    // MARK: Biology marking

    private func key() -> [AnswerKeyEntry] {
        func entry(_ n: Int, _ type: String, _ marks: Int, answer: String? = nil) -> AnswerKeyEntry {
            AnswerKeyEntry(n: n, questionId: "2024M-P1-TZ1-Q\(n)", type: type, marks: marks, pages: [1], subtopic: "B2.1",
                           subtopicName: "Membranes", concepts: [], answer: answer,
                           parts: [Part(label: "", marks: marks, subtopic: "B2.1", prompt: "…", markscheme: ["…"], guidance: nil, concept: nil)],
                           source: "2024 May · Paper 1")
        }
        return [entry(1, "mcq", 1, answer: "B"), entry(2, "mcq", 1, answer: "C"), entry(3, "mcq", 1, answer: "A"),
                entry(4, "mcq", 1, answer: "D"), entry(5, "structured", 4)]
    }

    private func reading() -> BiologyReading {
        func q(_ n: Int, _ choice: String, answered: Bool = true, legibility: String = "clear", starred: Bool = false,
               drawing: Bool = false, text: String = "") -> ReadQuestion {
            ReadQuestion(n: n, answered: answered, mcqChoice: choice, parts: text.isEmpty ? [] : [ReadPart(label: "", text: text)],
                         starred: starred, drawing: drawing, legibility: legibility, note: "", sheets: answered ? ["q0\(n)-1.png"] : [])
        }
        return BiologyReading(questions: [q(1, "B"), q(2, "A", starred: true), q(3, "B or C", legibility: "unclear"),
                                          q(4, "", answered: false),
                                          q(5, "", drawing: true, text: "water moves to high solute [drawing: arrow across membrane]")],
                              model: "haiku", inkSeparated: true)
    }

    func testAppSettlesClearMultipleChoiceAndAsksForALookOnlyWhereNeeded() {
        let decided = Marking.decidedMCQ(key: key(), reading: reading())
        XCTAssertEqual(decided, [1: 1, 2: 0, 4: 0])          // Q3 is ambiguous: Hank decides with the image
        XCTAssertEqual(Marking.needsLook(key: key(), reading: reading(), decided: decided), [3, 5])
    }

    func testMarkerGetsTextAndOnlyTheFlaggedCrops() throws {
        let readingDir = directory.appendingPathComponent("reading")
        try FileManager.default.createDirectory(at: readingDir, withIntermediateDirectories: true)
        for n in 1...5 { try Data([0x89, 0x50, UInt8(n)]).write(to: readingDir.appendingPathComponent("q0\(n)-1.png")) }
        let session = StudySession(id: "BS-TESTAA", title: "Membranes", subtitle: "", kind: .subtopic, scope: ["B2.1"],
                                   questionIds: [], totalMarks: 8, minutes: 10, createdAt: Date(), status: .marking)
        let r = reading(), decided = Marking.decidedMCQ(key: key(), reading: r)
        let content = Marking.markerContent(session: session, key: key(), reading: r, decided: decided,
                                            look: Marking.needsLook(key: key(), reading: r, decided: decided),
                                            progress: "B2.1 Membranes: one more go", readingDir: readingDir)
        let images = content.compactMap { if case .png(let d) = $0 { return d } else { return nil } }
        XCTAssertEqual(images, [Data([0x89, 0x50, 3]), Data([0x89, 0x50, 5])])
        let text = content.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined(separator: "\n")
        XCTAssertTrue(text.contains("water moves to high solute"))
        XCTAssertTrue(text.contains("Q1: chose B, answer B → 1/1"))
        XCTAssertTrue(text.contains("Q2"))                     // starred
        XCTAssertFalse(text.contains("pages/page-"))           // no page images to open
    }

    func testAppFactsOverrideTheMarker() {
        func q(_ n: Int, _ got: Int, _ of: Int, uncertain: Bool) -> QuestionResult {
            QuestionResult(questionId: "wrong-id", number: n, awarded: got, available: of, subtopic: "B2.1", concept: "",
                           parts: [PartResult(label: "", awarded: got, available: of, studentAnswer: "", correctAnswer: "", feedback: "")],
                           whyLost: got < of ? "Chose the wrong option." : "", bigPicture: "", tip: "", uncertain: uncertain)
        }
        let marker = MarkingResult(sessionId: "BS-TESTAA", awarded: 99, available: 99, headline: "", summary: "", strengths: [],
                                   focusNext: [], fixes: [], questions: [q(1, 0, 1, uncertain: true), q(2, 1, 1, uncertain: false),
                                                                         q(3, 1, 1, uncertain: true), q(4, 1, 1, uncertain: false),
                                                                         q(5, 9, 4, uncertain: false), q(9, 1, 1, uncertain: false)])
        let r = reading(), decided = Marking.decidedMCQ(key: key(), reading: r)
        let fixed = Marking.reconcile(marker, key: key(), reading: r, decided: decided, looked: [3, 5])
        XCTAssertEqual(fixed.questions.map(\.number), [1, 2, 3, 4, 5])          // nothing outside the key
        XCTAssertEqual(fixed.questions.map(\.awarded), [1, 0, 1, 0, 4])          // settled MCQs win; capped at marks
        XCTAssertEqual(fixed.questions.map(\.isUncertain), [false, true, true, false, false])
        XCTAssertEqual(fixed.questions[0].questionId, "2024M-P1-TZ1-Q1")
        XCTAssertEqual(fixed.questions[0].whyLost, "")
        XCTAssertEqual(fixed.questions[1].parts[0].studentAnswer, "A")
        XCTAssertEqual(fixed.awarded, 6)
        XCTAssertEqual(fixed.available, 8)
    }

    // MARK: Business

    func testEssaySentencesBecomeExactHighlightsFromLineIds() throws {
        let reading = BusinessReading(lines: [ReadLine(id: "L1", part: "d", text: "Lower prices may increase sales,"),
                                              ReadLine(id: "L2", part: "d", text: "which improves cash flow.")],
                                      starredParts: [], drawingParts: [], unclearParts: [], note: "", model: "haiku", inkSeparated: true,
                                      anchors: ["L1": EssayAnchor(page: 4, x: 0.1, y: 0.2, width: 0.6, height: 0.03),
                                                "L2": EssayAnchor(page: 4, x: 0.1, y: 0.24, width: 0.4, height: 0.03)],
                                      pageSheets: ["4": "page-04.png"])
        var sentence = EssaySentence(text: "Lower prices may increase sales, which improves cash flow.", label: "analysis",
                                     note: "Good chain.", judgement: "strength", anchors: nil)
        sentence.lines = ["L1", "L2", "L99"]
        let result = BusinessResult(sessionId: "BS-TESTAA", awarded: 6, available: 10, headline: "", summary: "", strengths: [], fixes: [],
                                    parts: [.init(label: "d", awarded: 6, available: 10, studentAnswer: "", correctAnswer: "", feedback: "", whyLost: "", tip: "")],
                                    essays: [.init(label: "d", band: "5–6", strands: [], capsHit: [], pointsHit: [], pointsMissed: [],
                                                   sentences: [sentence], rewrite: .init(original: "", improved: "", why: ""), nextTime: "")],
                                    transcriptionNote: "")
        let placed = BusinessMarking.placeSentences(result, reading: reading)
        XCTAssertEqual(placed.essays[0].sentences[0].anchors?.map(\.y), [0.2, 0.24])   // unknown L99 dropped
        let key = BusinessKey(sessionId: "BS-TESTAA", id: "set", session: "2025 May", paper: "2", company: "Co", marks: 10,
                              writesInPaper: false, answerPages: [4],
                              parts: [BusinessPart(label: "d", marks: 10, prompt: "Recommend…", markscheme: "Bands…", topic: "3.7",
                                                   extended: true, command: "Recommend")])
        XCTAssertNoThrow(try BusinessMarking.validate(placed, key: key))
        // The marker's schema asks for line ids, not coordinates.
        XCTAssertTrue(BusinessMarking.schema.contains("\"lines\""))
        XCTAssertFalse(BusinessMarking.schema.contains("\"anchors\""))
    }

    // MARK: plumbing

    func testSingleTurnRequestCarriesImagesInline() throws {
        let line = ClaudeCLI.userMessage([.text("Question 1:"), .png(Data([1, 2, 3]))])
        XCTAssertEqual(line.last, 0x0A)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        let content = try XCTUnwrap((obj["message"] as? [String: Any])?["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["text"] as? String, "Question 1:")
        let source = try XCTUnwrap(content[1]["source"] as? [String: Any])
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertEqual(source["data"] as? String, Data([1, 2, 3]).base64EncodedString())
    }

    func testOlderSettingsGetTheCheapReader() throws {
        let old = Data(#"{"marking_model":"opus","effort":"high"}"#.utf8)
        let settings = try JSON.decoder.decode(AppSettings.self, from: old)
        XCTAssertEqual(settings.markingModel, "opus")
        XCTAssertEqual(settings.readerModel, "haiku")
    }
}
