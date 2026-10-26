import XCTest
import PDFKit
@testable import Biosphere

/// Maths is revised by execution strategy: drills use the parts that need a move, mixes use whole questions.
final class MathsStrategyTests: XCTestCase {
    private var directory: URL!
    private var bank: Bank!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("biosphere-maths-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("papers"), withIntermediateDirectories: true)
        let move = { (id: String, name: String) in
            Subtopic(id: id, name: name, hlOnly: false, level: "Using derivatives", notesUrl: "", ref: "SL 5.8",
                     cues: ["greatest volume", "minimum cost"], steps: ["Differentiate.", "Set it equal to zero."],
                     formula: nil, trap: "Stopping at x.")
        }
        let syllabus = Syllabus(subject: "Maths AA SL", slug: "maths-test", syllabus: "AA", notesSite: "",
                                themes: [Theme(id: "M5", name: "Calculus", notesUrl: "",
                                               subtopics: [move("M5.2.5", "Find and classify stationary points"),
                                                           move("M5.2.7", "Optimisation in context")])],
                                strategies: true)
        let questions = [
            question("Q8", primary: "M5.2.5", parts: [("(a)", "M5.2.5", 6), ("(b)", "M5.2.7", 4)], marks: 10),
            question("Q8-b", primary: "M5.2.7", parts: [("(a)", "M5.2.5", 6), ("(b)", "M5.2.7", 4)], marks: 10, parent: "Q8"),
            question("short-uses-it", primary: "M5.2.5", parts: [("(a)", "M5.2.5", 2), ("(b)", "M5.2.7", 3)], marks: 5),
            question("short-barely", primary: "M5.2.5", parts: [("(a)", "M5.2.5", 5), ("(b)", "M5.2.7", 1)], marks: 6),
            question("short-optimise", primary: "M5.2.7", parts: [("", "M5.2.7", 6)], marks: 6),
        ]
        try JSON.save(syllabus, to: directory.appendingPathComponent("syllabus.json"))
        try JSON.save(questions, to: directory.appendingPathComponent("questions.json"))
        try onePagePDF(to: directory.appendingPathComponent("papers/AA-test.pdf"))
        bank = try Bank(slug: "maths-test", directory: directory)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    func testPickAndMixDrillsTheTickedStrategiesWithinOneArea() {
        let scope = SubtopicMix(topic: "M5.2", picked: ["M5.2.5", "M5.2.7"]).scope!
        XCTAssertFalse(scope.spansTopics)
        XCTAssertFalse(scope.isExamStyle)
        XCTAssertEqual(RevisionScope.topicId("M5.2.7"), "M5.2")
        XCTAssertEqual(RevisionScope.topicId("A1.2"), "A1")
        XCTAssertFalse(scope.title(in: bank.syllabus).contains("M5"))
        XCTAssertFalse(bank.pool(for: scope).isEmpty)
    }

    func testDrillTakesDrillItemsAndShortQuestionsThatSpendRealMarksOnTheMove() {
        let drill = Set(bank.pool(for: .subtopic("M5.2.7")).map(\.id))
        XCTAssertEqual(drill, ["Q8-b", "short-uses-it", "short-optimise"])   // not the whole Q8, not a 1-mark part
    }

    func testExamStyleUsesWholeQuestionsOnly() {
        let exam = bank.pool(for: .theme("M5"))
        XCTAssertFalse(exam.contains { $0.parent != nil })
        XCTAssertTrue(exam.contains { $0.id == "Q8" })
    }

    func testAPaperNeverHoldsAQuestionAndItsDrillItem() {
        let family = [bank.question("Q8")!, bank.question("Q8-b")!]
        let picked = Selector.pick(from: family, seen: [:], options: .init(targetMinutes: 60))
        XCTAssertEqual(picked.count, 1)
        let modes = StudyMode.allCases.map { Selector.pick(from: family, reviews: [:], mode: $0, options: .init(targetMinutes: 60)) }
        XCTAssertTrue(modes.allSatisfy { Set($0.map(\.family)).count == $0.count })
    }

    func testScopeTitlesUseStrategyNamesNotIds() {
        let syl = bank.syllabus
        XCTAssertEqual(RevisionScope.subtopic("M5.2.7").title(in: syl), "Optimisation in context")
        XCTAssertEqual(RevisionScope.topic("M5.2").title(in: syl), "Calculus · Using derivatives")
        XCTAssertEqual(syl.topics(in: syl.themes[0]).map(\.id), ["M5.2"])
    }

    func testBiologyTopicsAndPoolsAreUnchanged() throws {
        let bio = try JSON.load(Syllabus.self, from: Workspace.resources.appendingPathComponent("bank/biology-sl/syllabus.json"))
        XCTAssertFalse(bio.isStrategyBank)
        for theme in bio.themes {
            for topic in bio.topics(in: theme) {
                XCTAssertEqual(topic.id.count, 2)
                XCTAssertTrue(topic.subtopics.allSatisfy { String($0.id.prefix(2)) == topic.id })
            }
        }
        XCTAssertEqual(RevisionScope.topic("A1").title(in: bio).prefix(3), "A1 ")
    }

    func testShippedMathsSyllabusHasARecipeForEveryStrategy() throws {
        let url = Workspace.resources.appendingPathComponent("bank/maths-aa-sl/syllabus.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Maths bank not built") }
        let syl = try JSON.load(Syllabus.self, from: url)
        XCTAssertTrue(syl.isStrategyBank)
        XCTAssertGreaterThan(syl.slSubtopics.count, 60)
        for s in syl.slSubtopics {
            XCTAssertFalse(s.cues?.isEmpty ?? true, s.id)
            XCTAssertFalse(s.steps?.isEmpty ?? true, s.id)
        }
    }

    func testSessionsWithoutASubjectAreStillBiology() throws {
        let json = #"{"id":"BS-OLD123","title":"Membranes","subtitle":"","kind":"subtopic","scope":["B2.1"],"question_ids":[],"total_marks":0,"minutes":30,"created_at":"2026-01-01T00:00:00Z","status":"marked","placements":{},"page_count":2}"#
        let s = try JSON.decoder.decode(StudySession.self, from: Data(json.utf8))
        XCTAssertFalse(s.isMaths)
        XCTAssertFalse(s.isCasePaper)
    }

    func testSingleStrategyPaperStartsWithTheMoveAndHidesStrategiesInHeaders() throws {
        let session = StudySession(id: "BS-MATHS1", title: "Optimisation in context", subtitle: "", kind: .subtopic,
                                   scope: ["M5.2.7"], questionIds: ["short-optimise"], totalMarks: 6, minutes: 7,
                                   createdAt: Date(), status: .ready)
        let url = directory.appendingPathComponent("out.pdf")
        let out = try PDFComposer.compose(session: session, questions: [bank.question("short-optimise")!], bank: bank,
                                          syllabus: bank.syllabus, to: url)
        XCTAssertFalse(out.placements["short-optimise"]?.isEmpty ?? true)
        let text = PDFDocument(url: url)?.string ?? ""
        XCTAssertTrue(text.contains("THE MOVE"))
        XCTAssertTrue(text.contains("greatest volume"))
        XCTAssertTrue(text.contains("Set it equal to zero."))
        XCTAssertTrue(text.contains("Working"))
        XCTAssertFalse(text.contains("M5.2.7"))
    }

    func testMixedPaperShowsAToolboxWithoutSayingWhichQuestionNeedsWhich() throws {
        let session = StudySession(id: "BS-MATHS2", title: "Using derivatives", subtitle: "", kind: .topic,
                                   scope: ["M5.2.5", "M5.2.7"], questionIds: ["short-optimise"], totalMarks: 6, minutes: 7,
                                   createdAt: Date(), status: .ready)
        let url = directory.appendingPathComponent("mixed.pdf")
        _ = try PDFComposer.compose(session: session, questions: [bank.question("short-optimise")!], bank: bank,
                                    syllabus: bank.syllabus, to: url)
        let text = PDFDocument(url: url)?.string ?? ""
        XCTAssertTrue(text.contains("TOOLBOX"))
        XCTAssertTrue(text.contains("Find and classify stationary points"))
        XCTAssertFalse(text.contains("THE MOVE"))
    }

    // MARK: helpers

    private func question(_ id: String, primary: String, parts: [(String, String, Int)], marks: Int, parent: String? = nil) -> Question {
        Question(id: id, paperId: "AA-test", session: "2025 May", paper: "1", tz: "TZ1", number: "1",
                 type: marks >= 9 ? "extended" : "structured", inSyllabus: true, primary: primary,
                 subtopics: Array(Set(parts.map(\.1))), title: "Test", concepts: [], skills: [], difficulty: 2,
                 marks: marks, minutes: Double(marks) * 1.1,
                 parts: parts.map { Part(label: $0.0, marks: $0.2, subtopic: $0.1, prompt: "…", markscheme: ["M1: …"],
                                         guidance: nil, concept: nil, cue: "greatest volume") },
                 regions: [Region(page: 0, x0: 0.05, x1: 0.95, y0: 0.1, y1: 0.3)], needsSpace: true, parent: parent)
    }

    private func onePagePDF(to url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        let ctx = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        ctx.beginPDFPage(nil)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 60, y: 600, width: 300, height: 20))
        ctx.endPDFPage(); ctx.closePDF()
    }
}
