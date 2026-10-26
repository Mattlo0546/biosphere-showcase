import XCTest
import PDFKit
@testable import Biosphere

/// Economics runs on the Business engine; these check the bank and that the subject is routed everywhere.
final class EconomicsTests: XCTestCase {
    private func bank() throws -> BusinessBank {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        var bank = try JSON.load(BusinessBank.self, from: app.appendingPathComponent("Resources/bank/economics-hl/sets.json"))
        bank.topics = try JSON.load([BusinessTopic].self, from: app.appendingPathComponent("Resources/bank/economics-hl/topics.json"))
        return bank
    }

    func testBankIsWellFormedAndNeverCollidesWithBusiness() throws {
        let bank = try bank()
        XCTAssertEqual(bank.caseSubject, .economics)
        XCTAssertGreaterThan(bank.sets.filter(\.currentSyllabus).count, 60)
        XCTAssertEqual(Set(bank.sets.map(\.id)).count, bank.sets.count)
        let topics = Set(bank.topics.map(\.id))
        XCTAssertEqual(Set(bank.topics.compactMap(\.unit)), ["1", "2", "3", "4"])
        for set in bank.sets {
            XCTAssertTrue(set.id.hasPrefix("ECO-"), set.id)
            XCTAssertEqual(set.subject, .economics)
            XCTAssertFalse(set.parts.isEmpty, set.id)
            XCTAssertEqual(Set(set.parts.map(\.label)).count, set.parts.count, "duplicate labels in \(set.id)")
            XCTAssertEqual(set.marks, set.parts.reduce(0) { $0 + $1.marks }, set.id)
            XCTAssertTrue(set.parts.allSatisfy { $0.choice == nil }, "Economics sets are single questions: \(set.id)")
            XCTAssertTrue(set.parts.flatMap(\.topicIds).allSatisfy(topics.contains), set.id)
        }
        // The current papers' totals: P1 essay 25, P2 data response 40, P3 policy question 30.
        let current = bank.sets.filter(\.currentSyllabus)
        XCTAssertTrue(current.filter { $0.paper == "1" }.allSatisfy { $0.marks == 25 })
        XCTAssertTrue(current.filter { $0.paper == "2" }.allSatisfy { $0.marks == 40 })
        XCTAssertGreaterThan(current.filter { $0.paper == "3" && $0.marks == 30 }.count, 10)
        let withScheme = bank.sets.flatMap(\.parts).filter { !$0.markscheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        XCTAssertGreaterThan(Double(withScheme.count) / Double(bank.sets.flatMap(\.parts).count), 0.95)
        for id in EconomicsGuide.startHere { XCTAssertNotNil(bank.set(id), id) }
    }

    func testSubjectComesFromTheSetIdAndTheSession() {
        XCTAssertEqual(CaseSubject(setId: "ECO-2025M-P2-TZ1-Q1"), .economics)
        XCTAssertEqual(CaseSubject(setId: "2025M-P2-TZ1-Q5"), .business)
        var s = StudySession(id: "BS-ECON1", title: "Kenya", subtitle: "", kind: .custom, scope: [], questionIds: [],
                             totalMarks: 40, minutes: 105, createdAt: Date(), status: .ready)
        XCTAssertNil(s.caseSubject)
        s.subject = "economics-hl"; s.businessSetId = "ECO-2025M-P2-TZ1-Q1"
        XCTAssertEqual(s.caseSubject, .economics)
        // Business sessions saved before Economics existed have no subject, or "business-hl".
        var old = s; old.subject = nil; old.businessSetId = "2025M-P2-TZ1-Q5"
        XCTAssertEqual(old.caseSubject, .business)
        old.subject = "business-hl"
        XCTAssertEqual(old.caseSubject, .business)
    }

    func testEconomicsPaperThreeSplitsButBusinessPaperThreeStaysWhole() throws {
        let p3 = try XCTUnwrap(try bank().sets.first { $0.paper == "3" && $0.currentSyllabus && $0.parts.count > 2 })
        let first = try XCTUnwrap(p3.selecting(labels: [p3.parts[0].label]))
        XCTAssertEqual(first.parts.map(\.label), [p3.parts[0].label])
        XCTAssertLessThan(first.marks, p3.marks)
        XCTAssertFalse(CaseSubject.economics.keepsWhole(paper: "3"))
        XCTAssertTrue(CaseSubject.business.keepsWhole(paper: "3"))
    }

    func testTopicPracticePlansAcrossEconomicsPapersWithinTheBudget() throws {
        let bank = try bank()
        let scope = BusinessPracticeScope.topic("4.5", bank: bank)
        XCTAssertEqual(scope.subject, .economics)
        XCTAssertTrue(scope.id.hasPrefix("economics."))
        let plan = BusinessPracticePlanner.plan(bank: bank, topics: scope.topicIds, minutes: 45, format: .short, mode: .smart,
                                                history: [:], everyQuestion: false, papers: ["2", "3"])
        XCTAssertFalse(plan.isEmpty)
        let sets = BusinessPracticePlanner.selectedSets(bank: bank, components: plan)
        XCTAssertEqual(sets.count, plan.count)
        XCTAssertTrue(sets.allSatisfy { $0.subject == .economics && $0.parts.allSatisfy { !$0.extended } })
        XCTAssertTrue(sets.flatMap(\.parts).contains { $0.topicIds.contains("4.5") })
        XCTAssertLessThanOrEqual(BusinessPracticePlanner.estimatedMinutes(bank: bank, components: plan), 45)
        let sources = BusinessMixedPaper.sources(sets)
        XCTAssertTrue(sources.allSatisfy { $0.caseFile.hasPrefix("bank/economics-hl/cases/ECO-") })
    }

    func testMarkerGetsTheEconomicsSkillPackAndReaderWording() {
        let key = BusinessKey(sessionId: "BS-ECON1", id: "ECO-2025M-P1-TZ1-Q3", session: "2025 May", paper: "1",
                              company: "Essay · Exchange rates", marks: 25, writesInPaper: false, answerPages: [3],
                              parts: [], subject: "economics-hl")
        XCTAssertEqual(key.caseSubject, .economics)
        XCTAssertEqual(key.caseSubject.markingSkill, "mark-economics")
        XCTAssertEqual(key.caseSubject.markingPack, "bank/economics-hl/marking-pack.md")
        XCTAssertTrue(HandwritingReader.businessRules(.economics).contains("handwritten Economics exam answers"))
        // Keys written before Economics existed decode as Business.
        let legacy = Data(#"{"session_id":"BS-1","id":"2025M-P2-TZ1-Q5","session":"2025 May","paper":"2","company":"X","marks":10,"writes_in_paper":true,"answer_pages":[2],"parts":[]}"#.utf8)
        XCTAssertEqual(try JSON.decoder.decode(BusinessKey.self, from: legacy).caseSubject, .business)
    }

    func testMarkschemeCropsPointIntoTheirPapersMarkscheme() throws {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bank = try bank()
        let current = bank.sets.filter(\.currentSyllabus).flatMap(\.parts)
        XCTAssertGreaterThan(Double(current.filter { !($0.msRegions ?? []).isEmpty }.count) / Double(current.count), 0.95)
        let folder = app.appendingPathComponent("Resources/bank/economics-hl/markschemes")
        let shipped = FileManager.default.fileExists(atPath: folder.path)
        for set in bank.sets {
            let paper = set.id.replacingOccurrences(of: #"-Q\d+$"#, with: "", options: .regularExpression)
            let pages = shipped ? PDFDocument(url: folder.appendingPathComponent("\(paper).pdf"))?.pageCount : nil
            for part in set.parts {
                for r in part.msRegions ?? [] {
                    XCTAssertTrue(0 <= r.x0 && r.x0 < r.x1 && r.x1 <= 1 && 0 <= r.y0 && r.y0 < r.y1 && r.y1 <= 1, "\(set.id) \(part.label)")
                    if shipped { XCTAssertLessThan(r.page, try XCTUnwrap(pages, paper), "\(set.id) \(part.label)") }
                }
            }
        }
        XCTAssertNil(CaseSubject.markschemeURL(setId: "2025M-P2-TZ1-Q5"), "Business has no markscheme crops")
    }

    @MainActor
    func testHankIsNotSentTheCrops() throws {
        let set = try XCTUnwrap(try bank().set("ECO-2025M-P2-TZ1-Q1"))
        XCTAssertTrue(set.parts.contains { !($0.msRegions ?? []).isEmpty })
        let model = AppModel(previewEconomics: try bank())
        var s = StudySession(id: "BS-ECON2", title: set.title, subtitle: "", kind: .custom, scope: [], questionIds: [],
                             totalMarks: set.marks, minutes: set.minutes, createdAt: Date(), status: .ready)
        s.subject = "economics-hl"; s.businessSetId = set.id
        XCTAssertTrue(model.businessKey(s, set).parts.allSatisfy { $0.msRegions == nil })
    }

    func testGuideMatchesTheQuestion() throws {
        let bank = try bank()
        let essay = try XCTUnwrap(bank.sets.first { $0.paper == "1" && $0.currentSyllabus })
        let titles = CaseSubject.economics.guideSections(for: essay).map(\.title)
        XCTAssertTrue(titles.contains { $0.contains("15-marker") })
        XCTAssertTrue(titles.contains { $0.contains("explain, don't evaluate") })
        let policy = try XCTUnwrap(bank.sets.first { $0.paper == "3" && $0.currentSyllabus })
        XCTAssertTrue(CaseSubject.economics.guideSections(for: policy).map(\.title).contains { $0.contains("policy") })
    }
}
