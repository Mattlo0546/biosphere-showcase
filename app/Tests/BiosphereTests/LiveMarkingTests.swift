import XCTest
@testable import Biosphere

/// Runs the real two-step marking (reader → marker) on a marked dev session, using the claude CLI and your plan.
/// Writes into BIOSPHERE_LIVE_OUT; the session folder itself is only read.
///
///   cd app && BIOSPHERE_HOME=~/Biosphere-Dev BIOSPHERE_LIVE_MARKING=BS-XXXXXX BIOSPHERE_LIVE_OUT=/tmp/live \
///     swift test --filter LiveMarkingTests
///
/// Skipped unless BIOSPHERE_LIVE_MARKING is set. Outputs: transcript.json, reading/*.png, marker-input.jsonl
/// (replay it with `claude -p --input-format stream-json …` to inspect token usage) and the result JSON.
final class LiveMarkingTests: XCTestCase {
    @MainActor
    func testReadAndMarkADevSession() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let id = env["BIOSPHERE_LIVE_MARKING"], !id.isEmpty else { throw XCTSkip("Set BIOSPHERE_LIVE_MARKING to a session id.") }
        let out = URL(fileURLWithPath: env["BIOSPHERE_LIVE_OUT"] ?? "/tmp/biosphere-live")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let dir = Workspace.sessionDir(id)
        let s = try JSON.load(StudySession.self, from: dir.appendingPathComponent("session.json"))
        let settings = AppSettings.load()
        let completed = dir.appendingPathComponent("completed.pdf")
        let original = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("Biosphere ") && $0.pathExtension == "pdf" })
        let log: @Sendable (String) -> Void = { print("·", $0) }

        if s.isCasePaper {
            let key = try JSON.load(BusinessKey.self, from: dir.appendingPathComponent("business.json"))
            let reading = try await HandwritingReader.readBusiness(key: key, completed: completed, original: original, dir: out,
                                                                   model: settings.readerModel, log: log)
            try JSON.save(reading, to: out.appendingPathComponent("transcript.json"))
            let content = BusinessMarking.markerContent(session: s, key: key, reading: reading, history: "", readingDir: out.appendingPathComponent("reading"))
            try ClaudeCLI.userMessage(content).write(to: out.appendingPathComponent("marker-input.jsonl"))
            let raw = try await ClaudeCLI.ask(content: content, schema: BusinessMarking.schema, model: settings.markingModel,
                                              effort: settings.effort, as: BusinessResult.self, onEvent: log)
            let result = BusinessMarking.placeSentences(raw, reading: reading)
            try JSON.save(result, to: out.appendingPathComponent("business_results.json"))
            XCTAssertNoThrow(try BusinessMarking.validate(result, key: key))
            print("Business \(result.awarded)/\(result.available) — \(result.headline)")
        } else {
            let bank = try Bank(slug: "biology-sl")
            let key = Marking.answerKey(for: s, bank: bank)
            let reading = try await HandwritingReader.readBiology(key: key, placements: s.placements, completed: completed, original: original,
                                                                  dir: out, model: settings.readerModel, log: log)
            try JSON.save(reading, to: out.appendingPathComponent("transcript.json"))
            let decided = Marking.decidedMCQ(key: key, reading: reading)
            let look = Marking.needsLook(key: key, reading: reading, decided: decided)
            let content = Marking.markerContent(session: s, key: key, reading: reading, decided: decided, look: look,
                                                progress: "", readingDir: out.appendingPathComponent("reading"))
            try ClaudeCLI.userMessage(content).write(to: out.appendingPathComponent("marker-input.jsonl"))
            let raw = try await ClaudeCLI.ask(content: content, schema: Marking.schema, model: settings.markingModel,
                                              effort: settings.effort, as: MarkingResult.self, onEvent: log)
            let result = Marking.reconcile(raw, key: key, reading: reading, decided: decided, looked: look)
            try JSON.save(result, to: out.appendingPathComponent("results.json"))
            XCTAssertEqual(result.questions.count, key.count)
            print("Biology \(result.awarded)/\(result.available) — \(result.headline) · looked at \(look.sorted())")
        }
    }
}
