import XCTest
@testable import Biosphere

final class RevisionTests: XCTestCase {
    private var directory: URL!
    private var bank: Bank!
    private let scope: Set<String> = ["B2.1"]
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("biosphere-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let syllabus = Syllabus(subject: "Biology", slug: "test", syllabus: "2025", notesSite: "", themes: [])
        var questions = ["mcq", "structured", "extended"].flatMap { type in
            (1...3).map { question("\(type)-\($0)", type: type) }
        }
        var oldSyllabus = question("old", type: "mcq")
        oldSyllabus.inSyllabus = false
        var otherTopic = question("other-topic", type: "structured")
        otherTopic.primary = "C1.1"
        questions += [oldSyllabus, otherTopic]
        try JSON.save(syllabus, to: directory.appendingPathComponent("syllabus.json"))
        try JSON.save(questions, to: directory.appendingPathComponent("questions.json"))
        bank = try Bank(slug: "test", directory: directory)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    func testQuestionFormatPoolsIncludeWrittenResponsesAndExcludeOtherTopics() {
        XCTAssertEqual(bank.pool(for: scope).count, 9)
        XCTAssertEqual(Set(bank.pool(for: scope, format: .multipleChoice).map(\.type)), ["mcq"])
        XCTAssertEqual(Set(bank.pool(for: scope, format: .structuredWriting).map(\.type)), ["structured", "extended"])
        XCTAssertTrue(bank.pool(for: ["missing"], format: .multipleChoice).isEmpty)
        XCTAssertFalse(bank.pool(for: scope).contains { $0.id == "old" || $0.id == "other-topic" })
    }

    func testAllRevisionModesRespectQuestionFormat() {
        var reviews: [String: ReviewState] = [:]
        for type in ["mcq", "structured", "extended"] {
            reviews["\(type)-1"] = ReviewState(questionId: "\(type)-1", subtopic: "B2.1", due: now, lastPercent: 0)
            reviews["\(type)-2"] = ReviewState(questionId: "\(type)-2", subtopic: "B2.1", due: now, lastPercent: 1)
        }
        for format in QuestionFormat.allCases {
            let pool = bank.pool(for: scope, format: format)
            for mode in StudyMode.allCases {
                let picked = Selector.pick(from: pool, reviews: reviews, mode: mode,
                                           options: .init(targetMinutes: 30), now: now)
                XCTAssertFalse(picked.isEmpty, "\(format): \(mode)")
                XCTAssertTrue(picked.allSatisfy(format.includes), "\(format): \(mode)")
                if mode == .fresh { XCTAssertTrue(picked.allSatisfy { reviews[$0.id] == nil }) }
                if mode == .mistakes { XCTAssertTrue(picked.allSatisfy { reviews[$0.id]?.isMistake == true }) }
                if mode == .due { XCTAssertTrue(picked.allSatisfy { reviews[$0.id]?.isDue(now) == true }) }
            }
        }
    }

    func testFullSetsContainEveryQuestionOfTheChosenFormat() {
        for format in QuestionFormat.allCases {
            let pool = bank.pool(for: scope, format: format)
            let picked = Selector.pick(from: pool, seen: ["mcq-1": 1], options: .init(targetMinutes: 100_000))
            XCTAssertEqual(Set(picked.map(\.id)), Set(pool.map(\.id)))
        }
    }

    func testHankCannotOverrideTopicOrQuestionFormatAndDuplicatesAreRemoved() throws {
        let pool = bank.pool(for: scope, format: .multipleChoice)
        for excluded in ["structured-1", "extended-1", "other-topic", "old", "unknown"] {
            let plan = SessionPlan(title: "Practice", rationale: "", questionIds: ["mcq-1", excluded])
            XCTAssertThrowsError(try plan.validatedQuestions(from: pool), excluded)
        }
        let valid = SessionPlan(title: "Practice", rationale: "", questionIds: ["mcq-2", "mcq-1", "mcq-2"])
        XCTAssertEqual(try valid.validatedQuestions(from: pool).map(\.id), ["mcq-2", "mcq-1"])
        XCTAssertTrue(try SessionPlan(title: "Empty", rationale: "", questionIds: []).validatedQuestions(from: pool).isEmpty)
    }

    func testReviewIncludesStarredCorrectAnswersAndLostMarksWithoutDoubleCounting() throws {
        let questions = [
            answer(1, awarded: 1, uncertain: false),
            answer(2, awarded: 1, uncertain: true),
            answer(3, awarded: 0, uncertain: false),
            answer(4, awarded: 0, uncertain: true)
        ]
        let result = MarkingResult(sessionId: "BS-ABC234", awarded: 2, available: 4, headline: "", summary: "",
                                   strengths: [], focusNext: [], questions: questions)
        let saved = try JSON.encoder.encode(result)
        let restored = try JSON.decoder.decode(MarkingResult.self, from: saved)
        XCTAssertEqual(restored.reviewQuestions.map(\.number), [2, 3, 4])
        XCTAssertEqual(restored.uncertainQuestions.map(\.number), [2, 4])
        XCTAssertEqual(restored.awarded, 2)
        XCTAssertEqual(restored.questions[1].awarded, 1)
        XCTAssertTrue(restored.questions[1].whyLost.isEmpty)
    }

    func testLegacyResultsWithoutUncertaintyStillLoad() throws {
        let result = MarkingResult(sessionId: "BS-ABC234", awarded: 1, available: 2, headline: "", summary: "",
                                   strengths: [], focusNext: [], questions: [answer(1, awarded: 1), answer(2, awarded: 0)])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSON.encoder.encode(result)) as? [String: Any])
        var questions = try XCTUnwrap(object["questions"] as? [[String: Any]])
        for i in questions.indices { questions[i].removeValue(forKey: "uncertain") }
        object["questions"] = questions
        let restored = try JSON.decoder.decode(MarkingResult.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(restored.uncertainQuestions.isEmpty)
        XCTAssertEqual(restored.reviewQuestions.map(\.number), [2])
    }

    func testMarkingSchemaRequiresBooleanUncertaintyOnEveryQuestion() throws {
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(Marking.schema.utf8)) as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let questions = try XCTUnwrap(properties["questions"] as? [String: Any])
        let item = try XCTUnwrap(questions["items"] as? [String: Any])
        XCTAssertTrue(try XCTUnwrap(item["required"] as? [String]).contains("uncertain"))
        let questionProperties = try XCTUnwrap(item["properties"] as? [String: Any])
        let uncertainty = try XCTUnwrap(questionProperties["uncertain"] as? [String: Any])
        XCTAssertEqual(uncertainty["type"] as? String, "boolean")
    }

    private func question(_ id: String, type: String) -> Question {
        Question(id: id, paperId: "test", session: "2025 May", paper: type == "mcq" ? "1A" : "2", tz: "TZ1",
                 number: "1", type: type, inSyllabus: true, primary: "B2.1", subtopics: ["B2.1"], title: "Test",
                 concepts: [], skills: [], difficulty: 1, marks: type == "mcq" ? 1 : 2, minutes: type == "mcq" ? 1.5 : 2.5,
                 parts: [], regions: [], needsSpace: type != "mcq")
    }

    private func answer(_ number: Int, awarded: Int, uncertain: Bool? = nil) -> QuestionResult {
        QuestionResult(questionId: "test-\(number)", number: number, awarded: awarded, available: 1, subtopic: "B2.1",
                       concept: "Test", parts: [], whyLost: awarded == 1 ? "" : "Incorrect answer", bigPicture: "", tip: "",
                       uncertain: uncertain)
    }
}
