import XCTest
@testable import Biosphere

final class BusinessMixedPracticeTests: XCTestCase {
    private func bank() throws -> BusinessBank {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try JSON.load(BusinessBank.self, from: app.appendingPathComponent("Resources/bank/business-hl/sets.json"))
    }

    func testScopeBuildersUseBankTopicIds() throws {
        let bank = try bank()
        let everything = BusinessPracticeScope.everything(bank: bank)
        XCTAssertEqual(Set(everything.topicIds), Set(bank.topics.map(\.id)))
        let unit = BusinessPracticeScope.unit("3", bank: bank)
        XCTAssertTrue(unit.topicIds.contains("3.6"))
        XCTAssertTrue(unit.topicIds.allSatisfy { bank.topic($0)?.unit == "3" })
        XCTAssertEqual(BusinessPracticeScope.topic("4.2", bank: bank).topicIds, ["4.2"])
        XCTAssertEqual(BusinessPracticeScope.chosen(["4.2", "1.5", "4.2"], bank: bank).topicIds, ["1.5", "4.2"])
    }

    func testMixedPaperConsolidatesByCaseAndFitsBudget() throws {
        let bank = try bank()
        let topics = ["1.5", "4.5"]
        let plan = BusinessPracticePlanner.plan(bank: bank, topics: topics, minutes: 45,
                                                format: .both, mode: .smart, history: [:], everyQuestion: false)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertEqual(Set(plan.map(\.setId)).count, plan.count)
        XCTAssertTrue(plan.allSatisfy { !$0.labels.isEmpty })
        let selected = BusinessPracticePlanner.selectedSets(bank: bank, components: plan)
        XCTAssertEqual(selected.map(\.id), plan.map(\.setId))
        XCTAssertTrue(selected.allSatisfy { $0.currentSyllabus && ($0.paper == "1" || $0.paper == "2") })
        let estimate = BusinessPracticePlanner.estimatedMinutes(bank: bank, components: plan)
        XCTAssertTrue(estimate <= 45 || plan.count == 1, "only an indivisible first question may exceed the budget")
    }

    func testFreshAndMistakesApplyPartHistoryAndCurrentContentFilters() throws {
        let bank = try bank()
        let topic = "4.5"
        let candidate = try XCTUnwrap(bank.sets.first(where: { $0.currentSyllabus })?.parts.first(where: { $0.topicIds.contains(topic) }))
        let targetSet = try XCTUnwrap(bank.sets.first(where: { $0.parts.contains(candidate) }))
        let history = [targetSet.id: [candidate.label: 0.2]]

        let mistakes = BusinessPracticePlanner.plan(bank: bank, topics: [topic], minutes: 120,
                                                    format: .both, mode: .mistakes, history: history, everyQuestion: true)
        XCTAssertTrue(mistakes.contains { $0.setId == targetSet.id && $0.labels.contains(candidate.label) })
        let fresh = BusinessPracticePlanner.plan(bank: bank, topics: [topic], minutes: 120,
                                                 format: .both, mode: .fresh, history: history, everyQuestion: true)
        XCTAssertFalse(fresh.contains { $0.setId == targetSet.id && $0.labels.contains(candidate.label) })
        XCTAssertTrue(BusinessPracticePlanner.plan(bank: bank, topics: [topic], minutes: 45,
                                                   format: .both, mode: .due, history: history, everyQuestion: false).isEmpty)
    }

    func testPrerequisiteClosureAndQuestionFormats() throws {
        let bank = try bank()
        let topic = "toolkit.critical-path"
        let plan = BusinessPracticePlanner.plan(bank: bank, topics: [topic], minutes: 120,
                                                format: .both, mode: .fresh, history: [:], everyQuestion: true)
        let component = try XCTUnwrap(plan.first { $0.setId == "2025N-P2-TZ1-Q3" })
        XCTAssertTrue(component.labels.contains("c"))
        XCTAssertTrue(component.labels.contains("b(i)"))

        let short = BusinessPracticePlanner.plan(bank: bank, topics: [topic], minutes: 120,
                                                 format: .short, mode: .fresh, history: [:], everyQuestion: true)
        let essays = BusinessPracticePlanner.plan(bank: bank, topics: [topic], minutes: 120,
                                                  format: .essays, mode: .fresh, history: [:], everyQuestion: true)
        let shortSets = BusinessPracticePlanner.selectedSets(bank: bank, components: short)
        let essaySets = BusinessPracticePlanner.selectedSets(bank: bank, components: essays)
        XCTAssertTrue(shortSets.flatMap(\.parts).allSatisfy { !$0.extended })
        XCTAssertTrue(essaySets.flatMap(\.parts).allSatisfy { $0.extended })
    }

    func testBudgetCoversBothRequestedTopicsAndRestoreKeepsComponentOrder() throws {
        let bank = try bank()
        let topicIds = ["1.5", "4.5"]
        let plan = BusinessPracticePlanner.plan(bank: bank, topics: topicIds, minutes: 120,
                                                format: .both, mode: .fresh, history: [:], everyQuestion: false)
        let selected = BusinessPracticePlanner.selectedSets(bank: bank, components: plan)
        let covered = Set(selected.flatMap(\.parts).flatMap(\.topicIds))
        XCTAssertTrue(Set(topicIds).isSubset(of: covered))

        let reversed = Array(plan.reversed())
        XCTAssertEqual(BusinessPracticePlanner.selectedSets(bank: bank, components: reversed).map(\.id),
                       reversed.map(\.setId))
        let first = try XCTUnwrap(plan.first)
        XCTAssertTrue(BusinessPracticePlanner.selectedSets(bank: bank, components: [first, first]).isEmpty)
        XCTAssertTrue(BusinessPracticePlanner.selectedSets(bank: bank, components: [BusinessPaperComponent(setId: "missing", labels: ["a"])]).isEmpty)
        XCTAssertTrue(BusinessPracticePlanner.selectedSets(bank: bank, components: [BusinessPaperComponent(setId: first.setId, labels: [])]).isEmpty)
    }

    func testEstimatedTimeUsesOriginalSetPaceAndOneCaseReadingAllowance() throws {
        let bank = try bank()
        let set = try XCTUnwrap(bank.sets.first { $0.currentSyllabus && $0.paper == "2" })
        let part = try XCTUnwrap(set.parts.first)
        let component = BusinessPaperComponent(setId: set.id, labels: [part.label, part.label])
        let expected = Int(ceil(Double(part.marks) * Double(set.minutes) / Double(set.marks) + 4))
        XCTAssertEqual(BusinessPracticePlanner.estimatedMinutes(bank: bank, components: [component]), expected)
        XCTAssertEqual(component.labels, [part.label])
    }

    func testChosenPapersLimitTheMixAndPaperThreeStaysWhole() throws {
        let bank = try bank()
        let everything = BusinessPracticeScope.everything(bank: bank).topicIds
        func papers(_ plan: [BusinessPaperComponent]) -> Set<String> { Set(plan.compactMap { bank.set($0.setId)?.paper }) }

        let twoAndThree = BusinessPracticePlanner.plan(bank: bank, topics: everything, minutes: 120, format: .both,
                                                       mode: .smart, history: [:], everyQuestion: false, papers: ["2", "3"])
        XCTAssertFalse(twoAndThree.isEmpty)
        XCTAssertTrue(papers(twoAndThree).isSubset(of: ["2", "3"]))
        let allThree = BusinessPracticePlanner.plan(bank: bank, topics: everything, minutes: 120, format: .both,
                                                    mode: .fresh, history: [:], everyQuestion: true, papers: ["1", "2", "3"])
        XCTAssertEqual(papers(allThree), ["1", "2", "3"])
        for component in allThree where bank.set(component.setId)?.paper == "3" {
            XCTAssertEqual(component.labels, bank.set(component.setId)?.parts.map(\.label), "Paper 3 is never split")
        }
        XCTAssertEqual(BusinessPracticePlanner.selectedSets(bank: bank, components: allThree).count, allThree.count)

        // With time for it, every paper she ticked appears, and the whole Paper 3 is fitted first.
        let timedThree = BusinessPracticePlanner.plan(bank: bank, topics: everything, minutes: 120, format: .both,
                                                      mode: .smart, history: [:], everyQuestion: false, papers: ["1", "2", "3"])
        XCTAssertEqual(papers(timedThree), ["1", "2", "3"])
        XCTAssertLessThanOrEqual(BusinessPracticePlanner.estimatedMinutes(bank: bank, components: timedThree), 120)
        let defaultMix = BusinessPracticePlanner.plan(bank: bank, topics: everything, minutes: 45, format: .both,
                                                      mode: .smart, history: [:], everyQuestion: false)
        XCTAssertEqual(papers(defaultMix), ["1", "2"])

        // Only Paper 3 and a short budget: the whole paper still comes, and the timer uses its real length.
        let onlyThree = BusinessPracticePlanner.plan(bank: bank, topics: everything, minutes: 30, format: .both,
                                                     mode: .smart, history: [:], everyQuestion: false, papers: ["3"])
        let p3 = try XCTUnwrap(onlyThree.first)
        XCTAssertEqual(onlyThree.count, 1)
        let set = try XCTUnwrap(bank.set(p3.setId))
        XCTAssertEqual(p3.labels, set.parts.map(\.label))
        XCTAssertEqual(BusinessPracticePlanner.estimatedMinutes(bank: bank, components: onlyThree), set.minutes + 8)
        XCTAssertTrue(BusinessPracticePlanner.plan(bank: bank, topics: everything, minutes: 120, format: .short,
                                                   mode: .smart, history: [:], everyQuestion: true, papers: ["3"]).isEmpty)

        // A Paper 3 she has already done counts as seen, even if only one part was marked.
        let fresh = BusinessPracticePlanner.plan(bank: bank, topics: everything, minutes: 120, format: .both, mode: .fresh,
                                                 history: [set.id: ["1": 0.5]], everyQuestion: true, papers: ["3"])
        XCTAssertFalse(fresh.contains { $0.setId == set.id })
        XCTAssertEqual(BusinessPracticePlanner.papersTitle(["3", "1"]), "Papers 1 + 3")
        XCTAssertEqual(BusinessPracticePlanner.papersTitle(["2"]), "Paper 2")
    }
}
