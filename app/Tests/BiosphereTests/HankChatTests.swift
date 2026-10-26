import XCTest
@testable import Biosphere

final class HankChatTests: XCTestCase {
    @MainActor
    func testOpeningAnExistingChatStartsFreshWithoutSendingAndCanResumeIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hank-chat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("chat.json")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let oldMessages = [ChatMessage(role: .user, text: "Explain my old question", date: date),
                           ChatMessage(role: .tutor, text: "Old explanation", date: date)]
        // The previous version saved these two fields only.
        let saved: [String: Any] = ["messages": try JSONSerialization.jsonObject(with: JSON.encoder.encode(oldMessages)),
                                    "claude_session": "old-session"]
        try JSONSerialization.data(withJSONObject: saved).write(to: file)
        let chat = HankChat(file: file)
        XCTAssertEqual(chat.messages, oldMessages)
        let suggestion = ChatSuggestion(title: "Explain Q3", prompt: "Explain question 3", context: "the original paper")
        chat.open(suggestion: suggestion)
        XCTAssertTrue(chat.isOpen)
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertFalse(chat.busy)
        XCTAssertNil(chat.activity)
        XCTAssertEqual(chat.questionSuggestion, suggestion)
        XCTAssertTrue(chat.canResumePreviousChat)
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertNil(stored["claude_session"], "A fresh question must not resume the old Claude conversation")
        let reloaded = HankChat(file: file)
        XCTAssertTrue(reloaded.canResumePreviousChat)
        reloaded.resumePreviousChat()
        XCTAssertEqual(reloaded.messages, oldMessages)
        XCTAssertFalse(reloaded.busy)
        XCTAssertNil(reloaded.questionSuggestion)
    }

    @MainActor
    func testOpeningAnAlreadyVisibleChatDoesNotEraseAnActiveConversation() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("hank-chat-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let chat = HankChat(file: file)
        chat.isOpen = true
        chat.messages = [ChatMessage(role: .user, text: "What is DNA?")]
        chat.open()
        XCTAssertEqual(chat.messages.first?.text, "What is DNA?")
        XCTAssertFalse(chat.busy)
        chat.toggle()
        XCTAssertFalse(chat.isOpen)
        chat.toggle()
        XCTAssertTrue(chat.isOpen)
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertTrue(chat.canResumePreviousChat)
    }
}
