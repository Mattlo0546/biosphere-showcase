import XCTest
@testable import Biosphere

/// Maths results show the original markscheme crop beside each part she answered.
final class MarkschemeCropTests: XCTestCase {
    func testShippedMathsBankHasMarkschemeCropsForMostParts() throws {
        let url = Workspace.resources.appendingPathComponent("bank/maths-aa-sl/questions.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Maths bank not built") }
        let questions = try JSON.load([Question].self, from: url)
        let parts = questions.flatMap(\.parts)
        let cropped = parts.filter { !($0.msRegions ?? []).isEmpty }
        XCTAssertGreaterThan(Double(cropped.count) / Double(parts.count), 0.9)
        XCTAssertTrue(questions.allSatisfy { !($0.msRegions ?? []).isEmpty })
        for r in cropped.flatMap({ $0.msRegions! }) {
            XCTAssertTrue(r.y0 >= 0 && r.y0 < r.y1 && r.y1 <= 1, "\(r)")
        }
    }

    func testBiologyQuestionsStillDecodeWithoutMarkschemeCrops() throws {
        let json = #"[{"id":"q","paper_id":"p","session":"2019 May","paper":"2","tz":"TZ1","number":"1","type":"structured","in_syllabus":true,"primary":"A1.1","subtopics":["A1.1"],"title":"","concepts":[],"skills":[],"difficulty":1,"marks":2,"minutes":2.5,"parts":[{"label":"(a)","marks":2,"prompt":"","markscheme":["water"]}],"regions":[],"needs_space":false}]"#
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ms-\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let q = try XCTUnwrap(JSON.load([Question].self, from: url).first)
        XCTAssertNil(q.msRegions)
        XCTAssertNil(q.parts[0].msRegions)
    }

    func testMarkedPartLabelsMatchBankPartsLoosely() {
        let part = { (label: String) in Part(label: label, marks: 1, subtopic: nil, prompt: "", markscheme: [], guidance: nil, concept: nil) }
        let q = Question(id: "q", paperId: "p", session: "2019 May", paper: "1", tz: "TZ1", number: "4", type: "structured",
                         inSyllabus: true, primary: "M1", subtopics: [], title: "", concepts: [], skills: [], difficulty: 1,
                         marks: 3, minutes: 3, answer: nil, parts: [part("(a)"), part("(b)(i)"), part("(b)(ii)")],
                         regions: [], needsSpace: true)
        XCTAssertEqual(q.part(labelled: "(b)(i)")?.label, "(b)(i)")
        XCTAssertEqual(q.part(labelled: "b(ii)")?.label, "(b)(ii)")
        XCTAssertEqual(q.part(labelled: "A")?.label, "(a)")
        XCTAssertNil(q.part(labelled: "(c)"))
    }
}
