import XCTest
@testable import Biosphere

/// The exam pack is hand-written JSON, so these guard against the easy mistakes: a typo'd section id,
/// a plan that doesn't add up to the time she has, or a worked example that disagrees with itself.
final class ExamPackTests: XCTestCase {
    func pack() throws -> ExamPack {
        try JSON.load(ExamPack.self, from: Workspace.resources.appendingPathComponent("exam/business-hl.json"))
    }

    func testPlanFillsExactlyTwoHours() throws {
        XCTAssertEqual(try pack().totalMinutes, 120)
    }

    func testEveryBlockPointsAtRealSections() throws {
        let p = try pack()
        XCTAssertEqual(Set(p.blocks.map(\.id)).count, p.blocks.count, "block ids must be unique")
        for b in p.blocks {
            XCTAssertFalse(b.steps.isEmpty, "\(b.id) needs steps")
            for s in b.sections { XCTAssertNotNil(p.section(s), "\(b.id) points at missing section \(s)") }
        }
        // Everything she asked for is covered by some block.
        let covered = Set(p.blocks.flatMap(\.sections))
        for s in ["papers", "essay", "toolkit", "finance", "marketing", "operations", "formulas"] { XCTAssertTrue(covered.contains(s), s) }
    }

    func testItemsHaveWhatTheirTypeNeeds() throws {
        for s in try pack().sections {
            for card in s.cards {
                for item in card.items {
                    let at = "\(s.id) / \(card.title)"
                    switch item.type {
                    case .bullets, .steps: XCTAssertFalse(item.items?.isEmpty ?? true, at)
                    case .formulas: XCTAssertFalse(item.formulas?.isEmpty ?? true, at)
                    case .table:
                        let width = item.headers?.count ?? 0
                        XCTAssertFalse(item.rows?.isEmpty ?? true, at)
                        for row in item.rows ?? [] { XCTAssertEqual(row.count, width, "ragged table row in \(at)") }
                    case .ladder: XCTAssertFalse(item.lines?.isEmpty ?? true, at)
                    case .grid:
                        XCTAssertEqual(item.cells?.count, (item.columns?.count ?? 0) * (item.rowLabels?.count ?? 0), at)
                    case .letters: XCTAssertFalse(item.letters?.isEmpty ?? true, at)
                    case .tree: XCTAssertNotNil(item.tree, at)
                    case .tip, .text: XCTAssertFalse(item.text?.isEmpty ?? true, at)
                    case .flash: XCTAssertFalse(item.cards?.isEmpty ?? true, at)
                    case .prompts: XCTAssertFalse(item.prompts?.isEmpty ?? true, at)
                    case .myFixes: break
                    }
                }
            }
        }
    }

    func testPracticePromptsAreRealBankQuestions() throws {
        guard let bank = try? BusinessBank.load() else { throw XCTSkip("Business bank not available") }
        let prompts = try pack().sections.flatMap(\.cards).flatMap(\.items).flatMap { $0.prompts ?? [] }
        XCTAssertFalse(prompts.isEmpty)
        for p in prompts {
            let set = try XCTUnwrap(p.set.flatMap(bank.set), "unknown set \(p.set ?? "nil")")
            XCTAssertTrue(set.parts.contains { $0.prompt.contains(p.text.prefix(40)) }, "prompt not in \(set.id): \(p.text)")
        }
    }

    func testDecisionTreeExampleWorksOut() throws {
        let tree = try XCTUnwrap(try pack().sections.flatMap(\.cards).flatMap(\.items).compactMap(\.tree).first)
        for o in tree.options {
            XCTAssertEqual(o.outcomes.reduce(0) { $0 + $1.probability }, 1, accuracy: 0.0001, "\(o.name) probabilities must add to 1")
        }
        XCTAssertEqual(tree.options.map { DecisionTree.number($0.expectedValue) }, ["3.7", "5.95", "1.85"])
        XCTAssertEqual(tree.options.map { DecisionTree.number($0.netGain) }, ["1.2", "1.45", "0.35"])
        XCTAssertEqual(tree.best?.name, "Option 2: new company")
        XCTAssertEqual(DecisionTree.number(-1), "-1")
    }

    func testBlockFollowsTheClock() throws {
        let p = try pack()
        XCTAssertEqual(p.block(at: 0)?.id, p.blocks[0].id)
        XCTAssertEqual(p.block(at: p.blocks[0].minutes * 60 - 1)?.id, p.blocks[0].id)
        XCTAssertEqual(p.block(at: p.blocks[0].minutes * 60)?.id, p.blocks[1].id)
        XCTAssertEqual(p.block(at: 120 * 60 + 300)?.id, p.blocks.last?.id, "running over stays on the last block")
        XCTAssertEqual(p.start(of: p.blocks[2]), p.blocks[0].minutes + p.blocks[1].minutes)
    }

    @MainActor
    func testCoachStartsATwoHourTimerAndTicksBlocks() throws {
        let coach = ExamCoach()
        let p = try XCTUnwrap(coach.pack)
        let timer = StudyTimer()
        coach.start(timer) { _ in }
        defer { timer.stop() }
        XCTAssertTrue(coach.isOn(timer))
        XCTAssertEqual(timer.total, 120 * 60)
        XCTAssertEqual(coach.selected, p.blocks[0].id)
        let saved = UserDefaults.standard.stringArray(forKey: "exam.done")
        defer { UserDefaults.standard.set(saved, forKey: "exam.done") }
        coach.finish(p.blocks[0])
        XCTAssertTrue(coach.done.contains(p.blocks[0].id))
        XCTAssertEqual(coach.selected, p.blocks[1].id)
        coach.startOver(timer)
        XCTAssertFalse(coach.isOn(timer))
        XCTAssertTrue(coach.done.isEmpty)
    }
}
