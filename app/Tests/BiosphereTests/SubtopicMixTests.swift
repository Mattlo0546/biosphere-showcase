import XCTest
@testable import Biosphere

final class SubtopicMixTests: XCTestCase {
    private func sub(_ id: String, hl: Bool = false) -> Subtopic {
        Subtopic(id: id, name: "Name " + id, hlOnly: hl, level: "Level " + id.prefix(2), notesUrl: "")
    }

    private lazy var syllabus = Syllabus(subject: "Biology", slug: "test", syllabus: "2025", notesSite: "", themes: [
        Theme(id: "A", name: "Unity", notesUrl: "", subtopics: [sub("A1.1"), sub("A1.2"), sub("A1.3", hl: true), sub("A2.1")]),
        Theme(id: "B", name: "Form", notesUrl: "", subtopics: [sub("B1.1"), sub("B1.2")]),
    ])

    func testCustomScopeKeepsOnlyHerSLPicks() {
        let scope = RevisionScope.custom(["A1.1", "A1.3", "B1.2", "Z9.9"])
        XCTAssertEqual(scope.subtopicIds(in: syllabus), ["A1.1", "B1.2"])
        XCTAssertTrue(scope.isMixed)
        XCTAssertTrue(scope.spansTopics)
        XCTAssertEqual(scope.kind, .timed)
        XCTAssertEqual(scope.id, RevisionScope.custom(["B1.2", "Z9.9", "A1.3", "A1.1"]).id)
    }

    func testMixWithinOneTopicIsTitledByTheTopic() {
        let scope = RevisionScope.custom(["A1.1", "A1.2"])
        XCTAssertFalse(scope.spansTopics)
        XCTAssertEqual(scope.kind, .topic)
        XCTAssertTrue(scope.title(in: syllabus).hasPrefix("A1 Unity"))
        XCTAssertTrue(scope.title(in: syllabus).hasSuffix("your mix"))
        XCTAssertEqual(RevisionScope.custom(["A1.1", "B1.1", "B1.2"]).title(in: syllabus), "Your mix · 3 subtopics")
    }

    func testSinglePickBecomesSubtopicPractice() {
        XCTAssertNil(RevisionScope.mix([]))
        XCTAssertEqual(RevisionScope.mix(["A1.1"]), .subtopic("A1.1"))
        XCTAssertEqual(RevisionScope.mix(["A1.1", "A2.1"]), .custom(["A1.1", "A2.1"]))
    }

    func testTopicMixOnlyAcceptsItsOwnSubtopics() {
        var mix = SubtopicMix(topic: "A1")
        mix.toggle("A1.1"); mix.toggle("A2.1"); mix.toggle("A1.2"); mix.toggle("A1.2")
        XCTAssertEqual(mix.picked, ["A1.1"])
        XCTAssertFalse(mix.allows("A10.1"))

        var everywhere = SubtopicMix()
        everywhere.toggle("A1.1"); everywhere.toggle("B1.2")
        XCTAssertEqual(everywhere.scope, .custom(["A1.1", "B1.2"]))
    }
}
