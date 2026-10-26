import Foundation
import Observation

struct ChatMessage: Codable, Identifiable, Hashable {
    enum Role: String, Codable { case user, tutor = "eeyore" }   // raw value kept so saved chats still load
    var id = UUID()
    var role: Role
    var text: String
    var date = Date()
    var failed = false
}

struct ChatSuggestion: Equatable {
    var title: String
    var prompt: String
    var context: String?
}

/// The side-panel chat with Hank. Each message runs her `claude` CLI headlessly in ~/Biosphere
/// (so CLAUDE.md + skills apply) and resumes the same Claude session, streaming the reply.
@MainActor
@Observable
final class HankChat {
    var messages: [ChatMessage] = []
    var isOpen = false
    var busy = false
    var activity: String?
    var questionSuggestion: ChatSuggestion?
    private var previousChat: Conversation?
    private var claudeSession: String?
    private var process: Process?
    private var toolSinceText = false   // text before a tool call is narration ("let me check…"); the answer comes after
    private var generation = UUID()     // ignore callbacks from a stopped or replaced CLI run

    private struct Conversation: Codable { var messages: [ChatMessage]; var claudeSession: String? }
    private struct Saved: Codable { var messages: [ChatMessage]; var claudeSession: String?; var previousChat: Conversation? }
    private let file: URL
    var canResumePreviousChat: Bool { previousChat?.messages.isEmpty == false }

    static let chatPrompt = """
    You are chatting with her in Biosphere's side panel — a narrow chat window, not a terminal. She is busy and easily
    overwhelmed, so every answer must be skimmable in 10 seconds. Teach like the Amoeba Sisters and Hank Green explain,
    and lay it out like a Save My Exams revision note.

    FORMAT — follow this shape for explanations (drop sections that don't apply; small talk gets one short line):
    **<The answer in one bold sentence.>**

    ### How it works
    1. <step — one short line, cause → effect>
    2. <step>
    3. <step>   (max 4 steps; no paragraphs)

    🧠 <ONE vivid everyday analogy or real-life hook, one line.>

    > **Exam tip:** <the exact words that score marks, key terms in bold; name the command term if relevant>

    ### Quick check
    <one short question for her to try — don't give the answer yet>

    RULES
    - Under ~120 words unless she asks for more detail. No sentence over ~20 words. No paragraph over 2 lines.
    - Bold only the 3–5 key terms she must remember. No tables or long headings. The only code blocks to use are SVG diagrams (see below).
    - When going through a question she got wrong: lead with what she wrote → what scores (one line each), then the
      fix. Use "### What you wrote" / "### What scores" instead of "How it works".
    - Plain words first, then the IB term in bold. Bust the misconception directly if there is one ("Not X — it's Y").
    - Don't show file paths, ids or JSON; say "your last session" or "question 3".
    - Answer the question she actually sends. Never start explaining her paper just because she opened the panel.
      Lines starting with [Biosphere context: …] describe her screen; they are background, not a request to explain it.
      Use that context only when her message refers to it. A new biology question gets a fresh answer on that subject.
    - Maths: her real problem is spotting which method a worded question wants. Lead with the move in bold ("This is
      **optimisation**") and quote the words that give it away, then the recipe as the numbered steps. Write maths in
      plain text (x², √x, (a)/(b), f′(x)) and show each line of working; the analogy can be about the move itself.
    - When she wants a practice paper, use the build-session skill and write the request file; then tell her (one
      line) it's waiting in My sessions.

    DIAGRAMS — the chat renders fenced SVG code as an actual drawing, not visible source code.
    - If she asks to see or draw something, or a spatial diagram would clarify the answer, include one complete
      SVG inside a ```svg fenced block. Never draw with ASCII, spaced text, emoji grids, or Markdown tables.
    - Use <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 360"> (adjust the height to fit), a <title>
      and <desc>, and simple paths, lines, circles, rectangles, polygons and text. Keep all labels inside the viewBox.
      Use short labels at least 20 SVG units tall, clear leader lines, generous spacing, and a white background.
      Match the app: dark text #1e1433, purple #7c3aed; use other contrasting colours only to distinguish structures.
    - SVG must be self-contained: no scripts, event handlers, style tags, animation, foreignObject, images, links,
      external fonts or resources. Use presentation attributes such as fill, stroke and font-size. Internal defs,
      markers and gradients are supported. No HTML, JavaScript, Mermaid or other code blocks.
    - Show the biologically important structure, not decoration. For DNA, label the sugar–phosphate backbones,
      complementary A–T and C–G base pairs, hydrogen bonds, and opposite 5′/3′ strand directions when relevant.
      A labelled ladder schematic is clearer than a decorative helix for showing base pairing.
    - Keep prose brief; the SVG source does not count towards the prose word limit. Explain the drawing in one line.
    """

    init(file: URL = Workspace.root.appendingPathComponent("chat.json")) {
        self.file = file
        if let s = try? JSON.load(Saved.self, from: file) {
            messages = s.messages
            claudeSession = s.claudeSession
            previousChat = s.previousChat
        }
    }

    private func persist() {
        try? JSON.save(Saved(messages: messages, claudeSession: claudeSession, previousChat: previousChat), to: file)
    }

    /// Opening the panel never submits a prompt. Completed chats remain available via "Previous chat".
    func open(suggestion: ChatSuggestion? = nil) {
        if !isOpen && !busy { newChat() }
        questionSuggestion = suggestion
        isOpen = true
    }

    func toggle() {
        if isOpen { isOpen = false } else { open() }
    }

    func resumePreviousChat() {
        guard !busy, let previousChat else { return }
        let current = Conversation(messages: messages, claudeSession: claudeSession)
        messages = previousChat.messages
        claudeSession = previousChat.claudeSession
        self.previousChat = current.messages.isEmpty ? nil : current
        questionSuggestion = nil
        persist()
    }

    func newChat() {
        stop()
        if !messages.isEmpty { previousChat = Conversation(messages: messages, claudeSession: claudeSession) }
        messages = []
        claudeSession = nil
        questionSuggestion = nil
        persist()
    }

    func stop() {
        generation = UUID()
        process?.terminate()
        process = nil
        busy = false
        activity = nil
    }

    func send(_ text: String, context: String?, model: String?, effort: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !busy else { return }
        isOpen = true
        messages.append(ChatMessage(role: .user, text: trimmed))
        messages.append(ChatMessage(role: .tutor, text: ""))
        busy = true
        activity = "Thinking…"
        toolSinceText = false
        questionSuggestion = nil
        let token = UUID(); generation = token
        persist()

        guard let exe = ClaudeCLI.locate() else {
            finish(error: "I can't find Claude Code on this Mac. Open Settings to install it.")
            return
        }
        let prompt = (context.map { "[Biosphere context: \($0)]\n\n" } ?? "") + trimmed
        var args = ["-p", prompt, "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--strict-mcp-config",
                    "--append-system-prompt", Self.chatPrompt,
                    "--permission-mode", "acceptEdits",
                    "--allowedTools", "Read", "Glob", "Grep", "Write", "Edit", "Skill", "Bash(ls:*)", "WebFetch"]
        if let model, !model.isEmpty { args += ["--model", model] }
        if let effort, !effort.isEmpty { args += ["--effort", effort] }
        if let claudeSession { args += ["--resume", claudeSession] }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = ClaudeCLI.environment
        p.currentDirectoryURL = Workspace.root
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let buffer = LineBuffer()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard !chunk.isEmpty else { return }
            for line in buffer.append(chunk) {
                ClaudeUsage.ingest(line)
                guard let ev = Event(line) else { continue }
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.handle(ev)
                }
            }
        }
        p.terminationHandler = { [weak self] proc in
            out.fileHandleForReading.readabilityHandler = nil
            let rest = out.fileHandleForReading.readDataToEndOfFile()
            let lines = buffer.append(rest) + buffer.flush()
            lines.forEach(ClaudeUsage.ingest)
            let events = lines.compactMap(Event.init)
            let errText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                events.forEach { self.handle($0) }
                if self.busy {   // no result event arrived
                    self.finish(error: proc.terminationReason == .uncaughtSignal ? nil
                                : "Something went wrong talking to Claude. \(errText.prefix(300))")
                }
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            finish(error: "Couldn't start Claude: \(error.localizedDescription)")
        }
    }

    private func handle(_ ev: Event) {
        guard busy else { return }
        switch ev {
        case .text(let t):
            if let i = messages.indices.last {
                if toolSinceText { messages[i].text = ""; toolSinceText = false }
                messages[i].text += t
            }
            activity = nil
        case .tool(let desc):
            activity = desc
            toolSinceText = true
        case .result(let session, let isError, let text):
            if let session { claudeSession = session }
            if let i = messages.indices.last, messages[i].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages[i].text = text ?? ""
            }
            let lingering = process
            if isError { finish(error: text ?? "Claude reported an error.") } else { finish(error: nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if lingering?.isRunning == true { lingering?.terminate() } }
        }
    }

    private func finish(error: String?) {
        if let error, let i = messages.indices.last {
            messages[i].text = messages[i].text.isEmpty ? error : messages[i].text + "\n\n" + error
            messages[i].failed = true
        }
        if let i = messages.indices.last, messages[i].text.isEmpty, error == nil {
            messages[i].text = "…"
        }
        busy = false
        activity = nil
        process = nil
        persist()
    }

    // MARK: stream parsing

    enum Event {
        case text(String)
        case tool(String)
        case result(session: String?, isError: Bool, text: String?)

        init?(_ line: Data) {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
            switch obj["type"] as? String {
            case "stream_event":
                guard let e = obj["event"] as? [String: Any], e["type"] as? String == "content_block_delta",
                      let d = e["delta"] as? [String: Any], d["type"] as? String == "text_delta",
                      let t = d["text"] as? String else { return nil }
                self = .text(t)
            case "assistant":
                guard let desc = ClaudeCLI.describe(line) else { return nil }
                self = .tool(desc.replacingOccurrences(of: "Reading your", with: "Looking at your"))
            case "result":
                self = .result(session: obj["session_id"] as? String, isError: (obj["is_error"] as? Bool) ?? false,
                               text: obj["result"] as? String)
            default:
                return nil
            }
        }
    }
}

/// Splits a byte stream into newline-terminated lines (thread-safe).
final class LineBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) -> [Data] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        var lines: [Data] = []
        while let nl = data.firstIndex(of: 0x0A) {
            lines.append(data.subdata(in: data.startIndex..<nl))
            data.removeSubrange(data.startIndex...nl)
        }
        return lines
    }

    func flush() -> [Data] {
        lock.lock(); defer { lock.unlock() }
        let rest = data; data = Data()
        return rest.isEmpty ? [] : [rest]
    }
}

/// Signs in / installs Claude Code without a terminal: runs the CLI, opens the login page, and
/// relays any prompt (e.g. "paste the code") to a text field.
@MainActor
@Observable
final class ClaudeSetup {
    var running = false
    var output = ""
    var needsInput = false
    var done = false
    var url: URL?        // the sign-in page, if the CLI printed one
    private var process: Process?
    private var input: Pipe?

    func login() {
        guard let exe = ClaudeCLI.locate() else { return }
        run(exe, ["auth", "login", "--claudeai"])
    }

    func install() {
        run("/bin/bash", ["-c", "curl -fsSL https://claude.ai/install.sh | bash"])
    }

    func submit(_ code: String) {
        input?.fileHandleForWriting.write(Data((code.trimmingCharacters(in: .whitespacesAndNewlines) + "\n").utf8))
        needsInput = false
    }

    private func run(_ exe: String, _ args: [String]) {
        guard !running else { return }
        output = ""; done = false; url = nil; needsInput = false
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var env = ClaudeCLI.environment
        env["BROWSER"] = env["BROWSER"] ?? "open"
        p.environment = env
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = out; p.standardInput = inp
        input = inp
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            guard !s.isEmpty else { return }
            Task { @MainActor in self?.received(s) }
        }
        p.terminationHandler = { [weak self] _ in
            out.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in self?.running = false; self?.done = true; self?.needsInput = false }
        }
        do { try p.run(); process = p; running = true } catch { output = error.localizedDescription }
    }

    private func received(_ s: String) {
        // Strip terminal colour codes.
        let clean = s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        output += clean
        if url == nil, let r = output.range(of: "https://[^\\s]+", options: .regularExpression) {
            url = URL(string: String(output[r]))   // the CLI usually opens it itself; we offer a button too
        }
        if clean.range(of: "(paste|enter).{0,30}code|code:", options: [.regularExpression, .caseInsensitive]) != nil {
            needsInput = true
        }
    }

    func cancel() { process?.terminate() }
}
