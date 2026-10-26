import XCTest
@testable import Biosphere

/// The shipped 1-hour Maths mock: real whole questions, shaped like an AA SL paper.
final class MathsMockTests: XCTestCase {
    func load() throws -> (MathsMock, [Question]) {
        let mock = try XCTUnwrap(MathsMock.load(), "exam/maths-aa-sl-mock.json should decode")
        let bank = try Bank(slug: "maths-aa-sl", directory: Workspace.resources.appendingPathComponent("bank/maths-aa-sl"))
        return (mock, try XCTUnwrap(mock.questions(in: bank), "every mock question should be in the bank"))
    }

    func testWholeRecentQuestionsThatFitTheHour() throws {
        let (mock, qs) = try load()
        XCTAssertEqual(mock.minutes, 60)
        for q in qs {
            XCTAssertNil(q.parent, "\(q.id) should be a whole question, not a drill item")
            XCTAssertTrue(q.inSyllabus, q.id)
            XCTAssertTrue(["2024", "2025", "2026"].contains(String(q.session.prefix(4))), q.id)
        }
        XCTAssertEqual(Set(qs.map { $0.session.prefix(4) }), ["2024", "2025", "2026"], "mixes all three years")
        let marks = qs.reduce(0) { $0 + $1.marks }
        XCTAssertTrue((50...60).contains(marks), "IB pace is ~80 marks in 90 min; got \(marks) marks")
        XCTAssertEqual(Set(qs.map(\.id)).count, qs.count)
    }

    func testCalculusHeavyWithEveryTopicAndNoProbability() throws {
        let (_, qs) = try load()
        let parts = qs.flatMap(\.parts)
        var byTheme: [String: Int] = [:]
        for p in parts { byTheme[String((p.subtopic ?? "").prefix(2)), default: 0] += p.marks }
        let total = parts.reduce(0) { $0 + $1.marks }
        XCTAssertGreaterThan(Double(byTheme["M5"] ?? 0), Double(total) / 2, "calculus should be most of the marks: \(byTheme)")
        for theme in ["M1", "M2", "M3", "M4"] { XCTAssertGreaterThan(byTheme[theme] ?? 0, 0, "needs some \(theme)") }
        // Statistics only up to correlation and regression (M4.1, M4.2): no probability yet.
        for p in parts where p.subtopic?.hasPrefix("M4") == true {
            XCTAssertTrue(p.subtopic!.hasPrefix("M4.1") || p.subtopic!.hasPrefix("M4.2"), "\(p.subtopic!) is past regression")
        }
        // Like a real paper: number and algebra opens it, the long (Section B) questions close it.
        XCTAssertEqual(qs.first?.primary.prefix(2), "M1")
        let firstLong = try XCTUnwrap(qs.firstIndex { $0.type == "extended" })
        XCTAssertTrue(qs[firstLong...].allSatisfy { $0.type == "extended" }, "short questions first, then the long ones")
    }
}
