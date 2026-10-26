import XCTest
import SwiftUI
@testable import Biosphere

final class BusinessPracticeTests: XCTestCase {
    private func bank() throws -> BusinessBank {
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try JSON.load(BusinessBank.self, from: app.appendingPathComponent("Resources/bank/business-hl/sets.json"))
    }

    func testFocusedSessionKeepsCaseAndOnlySelectedMarkschemes() throws {
        let original = try XCTUnwrap(try bank().set("2025M-P2-TZ1-Q5"))
        let part = try XCTUnwrap(original.parts.first)
        let focused = try XCTUnwrap(original.selecting(labels: [part.label]))
        XCTAssertEqual(focused.id, original.id)
        XCTAssertEqual(focused.parts.map(\.label), [part.label])
        XCTAssertEqual(focused.parts.first?.markscheme, part.markscheme)
        XCTAssertEqual(focused.marks, part.marks)
        XCTAssertEqual(focused.selectedLabels, [part.label])
        XCTAssertLessThan(focused.minutes, original.minutes)
        XCTAssertNil(original.selectedLabels)
        XCTAssertNil(original.selecting(labels: ["missing"]))
    }

    func testTopicPracticeMakesBothChosenEssayOptionsExplicitTasks() throws {
        let original = try XCTUnwrap(try bank().set("2025M-P1-TZ1"))
        let options = original.parts.filter { $0.choice != nil }
        XCTAssertEqual(options.count, 2)
        let focused = try XCTUnwrap(original.selecting(labels: options.map(\.label)))
        XCTAssertEqual(focused.marks, options.reduce(0) { $0 + $1.marks })
        XCTAssertTrue(focused.parts.allSatisfy { $0.choice == nil })
        XCTAssertTrue(original.parts.contains { $0.choice != nil })
    }

    func testPaperThreeRemainsWhole() throws {
        let original = try XCTUnwrap(try bank().sets.first { $0.paper == "3" })
        XCTAssertEqual(original.selecting(labels: [original.parts[0].label]), original)
        XCTAssertEqual(original.marks, 25)
    }

    func testSelectedLabelsSurviveSavingAndOlderSessionsStillDecode() throws {
        var session = StudySession(id: "BS-TEST", title: "Topic practice", subtitle: "", kind: .custom,
                                   scope: [], questionIds: [], totalMarks: 2, minutes: 5,
                                   createdAt: Date(), status: .ready)
        session.businessSetId = "2025M-P1-TZ1"
        session.businessPartLabels = ["1"]
        session.businessTopicId = "1.2"
        let saved = try JSON.encoder.encode(session)
        XCTAssertEqual(try JSON.decoder.decode(StudySession.self, from: saved).businessPartLabels, ["1"])
        XCTAssertEqual(try JSON.decoder.decode(StudySession.self, from: saved).businessTopicId, "1.2")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        legacy.removeValue(forKey: "business_part_labels")
        legacy.removeValue(forKey: "business_topic_id")
        XCTAssertNil(try JSON.decoder.decode(StudySession.self, from: JSONSerialization.data(withJSONObject: legacy)).businessPartLabels)
    }

    func testTopicPracticeIncludesCalculationsNeededByLaterParts() throws {
        let original = try XCTUnwrap(try bank().set("2025N-P2-TZ1-Q3"))
        let focused = try XCTUnwrap(original.selecting(topic: "toolkit.critical-path"))
        XCTAssertTrue(focused.parts.contains { $0.label == "b(i)" })
        XCTAssertTrue(focused.parts.contains { $0.label == "c" })
        XCTAssertEqual(focused.selectedTopicId, "toolkit.critical-path")
        XCTAssertEqual(focused.marks, focused.parts.reduce(0) { $0 + $1.marks })
        XCTAssertEqual(focused.markbands, original.markbands)
    }

    func testBankHasReadingTopicsOriginalSchemesAndValidDependencies() throws {
        var bank = try bank()
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        bank.topics = try JSON.load([BusinessTopic].self, from: app.appendingPathComponent("Resources/bank/business-hl/topics.json"))
        XCTAssertEqual(bank.topics.count, 52)
        let ids = Set(bank.topics.map(\.id))
        for set in bank.sets {
            let labels = Set(set.parts.map(\.label))
            XCTAssertEqual(labels.count, set.parts.count, set.id)
            XCTAssertEqual(Set(set.topics), Set(set.parts.flatMap(\.topicIds)), set.id)
            if !set.currentSyllabus { XCTAssertFalse((set.markbands ?? "").isEmpty, set.id) }
            for part in set.parts {
                XCTAssertFalse(part.markscheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(set.id) \(part.label)")
                XCTAssertTrue(ids.contains(part.topic), "\(set.id) \(part.label)")
                XCTAssertTrue(Set(part.topicIds).isSubset(of: ids), "\(set.id) \(part.label)")
                XCTAssertTrue(Set(part.prerequisites ?? []).isSubset(of: labels), "\(set.id) \(part.label)")
                if set.currentSyllabus { XCTAssertTrue(part.isCurrentContent, "\(set.id) \(part.label)") }
            }
        }
    }

    func testFullPaperOneRequiresExactlyOneEssayOption() throws {
        let original = try XCTUnwrap(try bank().set("2025M-P1-TZ1"))
        let key = BusinessKey(sessionId: "BS-TEST", id: original.id, session: original.session,
                              paper: original.paper, company: original.company, marks: original.marks,
                              writesInPaper: false, answerPages: [1], parts: original.parts)
        let parts = original.parts.filter { $0.choice == nil } + [try XCTUnwrap(original.parts.first { $0.choice != nil })]
        let entries = parts.map { BusinessPartResult(label: $0.label, awarded: 0, available: $0.marks,
                                                     studentAnswer: "", correctAnswer: "", feedback: "", whyLost: "", tip: "") }
        let essays = parts.filter(\.extended).map { EssayFeedback(label: $0.label, band: "0", strands: [], capsHit: [],
                                                                 pointsHit: [], pointsMissed: [], sentences: [],
                                                                 rewrite: EssayRewrite(original: "", improved: "", why: ""), nextTime: "") }
        var result = BusinessResult(sessionId: key.sessionId, awarded: 0, available: original.marks,
                                    headline: "", summary: "", strengths: [], fixes: [], parts: entries,
                                    essays: essays, transcriptionNote: "")
        XCTAssertNoThrow(try BusinessMarking.validate(result, key: key))
        result.essays = []
        XCTAssertThrowsError(try BusinessMarking.validate(result, key: key))
        result.parts.removeLast()
        result.available = result.parts.reduce(0) { $0 + $1.available }
        XCTAssertThrowsError(try BusinessMarking.validate(result, key: key))
    }

    @MainActor func testReopenedSessionUsesSavedSubset() throws {
        var bank = try bank()
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        bank.topics = try JSON.load([BusinessTopic].self, from: app.appendingPathComponent("Resources/bank/business-hl/topics.json"))
        let model = AppModel(previewBusiness: bank)
        let original = try XCTUnwrap(bank.set("2025M-P1-TZ1"))
        var session = StudySession(id: "BS-TEST", title: "Topic practice", subtitle: "", kind: .custom,
                                   scope: [], questionIds: [], totalMarks: 2, minutes: 5,
                                   createdAt: Date(), status: .ready)
        session.businessSetId = original.id
        session.businessPartLabels = ["1"]
        session.businessTopicId = "1.2"
        XCTAssertEqual(model.businessSet(for: session)?.parts.map(\.label), ["1"])
        XCTAssertEqual(model.businessSet(for: session)?.marks, original.parts[0].marks)
        XCTAssertEqual(model.businessSet(for: session)?.selectedTopicId, "1.2")
        XCTAssertEqual(model.topicName(session), try XCTUnwrap(bank.topic("1.2")).displayName)
        let renderer = ImageRenderer(content: BusinessView().topicIndex(bank).environment(model)
            .padding(24).frame(width: 1080).background(.white).preferredColorScheme(.light))
        if let image = renderer.cgImage,
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/tmp/biosphere-business-topic-preview.png"))
        }
    }

    func testMarkerRejectsFullPaperTotalsForFocusedPractice() throws {
        let original = try XCTUnwrap(try bank().set("2025M-P1-TZ1"))
        let focused = try XCTUnwrap(original.selecting(labels: ["1"]))
        let key = BusinessKey(sessionId: "BS-TEST", id: focused.id, session: focused.session,
                              paper: focused.paper, company: focused.company, marks: focused.marks,
                              writesInPaper: false, answerPages: [1], parts: focused.parts,
                              currentSyllabus: true, selectedLabels: focused.selectedLabels)
        let part = BusinessPartResult(label: "1", awarded: 1, available: focused.marks,
                                      studentAnswer: "", correctAnswer: "", feedback: "", whyLost: "", tip: "")
        var result = BusinessResult(sessionId: key.sessionId, awarded: 1, available: focused.marks,
                                    headline: "", summary: "", strengths: [], fixes: [], parts: [part],
                                    essays: [], transcriptionNote: "")
        XCTAssertNoThrow(try BusinessMarking.validate(result, key: key))
        result.available = original.marks
        XCTAssertThrowsError(try BusinessMarking.validate(result, key: key))
        result.available = focused.marks
        result.parts.append(part)
        XCTAssertThrowsError(try BusinessMarking.validate(result, key: key))
    }
}
