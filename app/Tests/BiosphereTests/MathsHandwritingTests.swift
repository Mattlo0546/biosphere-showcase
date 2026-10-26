import XCTest
@testable import Biosphere

/// Maths results show her own handwriting per part: the reader tags her numbered lines with the part they
/// answer, and the app keeps each line's rectangle. None of that reaches the marking model.
final class MathsHandwritingTests: XCTestCase {
    private func anchor(_ page: Int, _ y: Double, x: Double = 0.1, width: Double = 0.5) -> EssayAnchor {
        EssayAnchor(page: page, x: x, y: y, width: width, height: 0.02)
    }

    private func reading() -> BiologyReading {
        let parts = [ReadPart(label: "(a)", text: "q = 5", lines: ["L1"]),
                     ReadPart(label: "(b)(i)", text: "33 - 30 = 3", lines: ["L2", "L3", "L4"]),
                     ReadPart(label: "(c)", text: "", lines: [])]
        let q = ReadQuestion(n: 2, answered: true, mcqChoice: "", parts: parts, starred: false, drawing: false,
                             legibility: "clear", note: "", sheets: ["q02-1.png"])
        return BiologyReading(questions: [q], model: "haiku", inkSeparated: true,
                              anchors: ["L1": anchor(1, 0.30), "L2": anchor(1, 0.40), "L3": anchor(1, 0.45, x: 0.2, width: 0.75),
                                        "L4": anchor(2, 0.10)])
    }

    func testEachPartBecomesOneFullWidthCropPerPage() throws {
        let r = reading()
        let a = r.handwriting(question: 2, part: "(a)")
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(a[0].page, 1)
        XCTAssertEqual(a[0].y, 0.292, accuracy: 0.0001)
        XCTAssertEqual(a[0].x, 0.05, accuracy: 0.0001)
        XCTAssertEqual(a[0].x + a[0].width, 0.95, accuracy: 0.0001)

        let b = r.handwriting(question: 2, part: "b(i)")       // Hank's label spelling may differ
        XCTAssertEqual(b.map(\.page), [1, 2])
        XCTAssertEqual(b[0].y, 0.392, accuracy: 0.0001)
        XCTAssertEqual(b[0].y + b[0].height, 0.478, accuracy: 0.0001)
        XCTAssertTrue(b.allSatisfy(\.isValid))

        XCTAssertTrue(r.handwriting(question: 2, part: "(c)").isEmpty)    // nothing written: show the text instead
        XCTAssertTrue(r.handwriting(question: 9, part: "(a)").isEmpty)

        // Lines written close together: each crop stops halfway, so the next part's line doesn't peek in.
        var tight = r
        tight.anchors?["L2"] = anchor(1, 0.325)
        let a2 = tight.handwriting(question: 2, part: "(a)")[0], b2 = tight.handwriting(question: 2, part: "(b)(i)")[0]
        XCTAssertEqual(a2.y + a2.height, 0.3225, accuracy: 0.0001)
        XCTAssertEqual(b2.y, 0.3225, accuracy: 0.0001)
    }

    func testOlderTranscriptsWithoutLineIdsStillDecodeAndShowText() throws {
        let json = #"{"questions":[{"n":1,"answered":true,"mcq_choice":"","parts":[{"label":"(a)","text":"x = 2"}],"starred":false,"drawing":false,"legibility":"clear","note":""}],"model":"haiku","ink_separated":true}"#
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transcript-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let r = try JSON.load(BiologyReading.self, from: url)
        XCTAssertNil(r.anchors)
        XCTAssertTrue(r.handwriting(question: 1, part: "(a)").isEmpty)
    }

    func testMarkerSeesNeitherLineIdsNorMarkschemeCrops() throws {
        let crop = [Region(page: 6, x0: 0.035, x1: 0.965, y0: 0.13, y1: 0.2)]
        var part = Part(label: "(a)", marks: 1, subtopic: "M4.1.1", prompt: "Write down q.", markscheme: ["A1: q = 5"],
                        guidance: nil, concept: nil)
        part.msRegions = crop
        let q = Question(id: "AA-Q2", paperId: "AA-P", session: "2019 November", paper: "1", tz: "TZ0", number: "2", type: "structured",
                         inSyllabus: true, primary: "M4.1.1", subtopics: ["M4.1.1"], title: "", concepts: [], skills: [],
                         difficulty: 1, marks: 1, minutes: 1, answer: nil, parts: [part], regions: [], needsSpace: true, msRegions: crop)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("maths-hw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("papers"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let syllabus = Syllabus(subject: "Maths AA SL", slug: "maths-hw", syllabus: "AA", notesSite: "", themes: [], strategies: true)
        try JSON.save(syllabus, to: dir.appendingPathComponent("syllabus.json"))
        try JSON.save([q], to: dir.appendingPathComponent("questions.json"))
        let bank = try Bank(slug: "maths-hw", directory: dir)
        let session = StudySession(id: "BS-TESTHW", title: "Venn", subtitle: "", kind: .subtopic, scope: [], questionIds: ["AA-Q2"],
                                   totalMarks: 1, minutes: 5, createdAt: Date(), status: .marking)
        let key = Marking.answerKey(for: session, bank: bank)
        XCTAssertNil(key[0].parts[0].msRegions)

        var r = reading()
        r.questions[0].n = 1
        let content = Marking.markerContent(session: session, key: key, reading: r, decided: [:], look: [], progress: "",
                                            readingDir: dir, skill: "mark-maths")
        let text = content.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined(separator: "\n")
        XCTAssertTrue(text.contains("33 - 30 = 3"))
        XCTAssertFalse(text.contains("\"L2\""))
        XCTAssertFalse(text.contains("ms_regions"))
    }

    func testMathsReaderSchemaAsksForLineIdsAndBiologyDoesnt() {
        XCTAssertTrue(HandwritingReader.mathsSchema.contains("\"lines\""))
        XCTAssertFalse(HandwritingReader.biologySchema.contains("\"lines\""))
        XCTAssertTrue(HandwritingReader.mathsRules.contains("L1, L2"))
    }
}
