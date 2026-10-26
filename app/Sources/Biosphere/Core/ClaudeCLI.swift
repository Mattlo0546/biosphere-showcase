import Foundation

/// Talks to her locally installed Claude Code CLI. Biosphere never handles credentials: signing in
/// happens inside `claude` itself.
enum ClaudeCLI {
    struct Status { var installed: Bool; var loggedIn: Bool; var email: String?; var path: String? }

    static let searchPaths = ["~/.local/bin/claude", "~/.claude/local/claude", "/opt/homebrew/bin/claude",
                              "/usr/local/bin/claude", "~/.npm-global/bin/claude", "~/.bun/bin/claude"]
        .map { NSString(string: $0).expandingTildeInPath }

    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        // If Biosphere itself was launched from inside another Claude Code session, don't let that
        // session's internal wiring (host sockets, SDK auth hand-off, entrypoint…) leak into her CLI.
        let keep: Set<String> = ["CLAUDE_CONFIG_DIR", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]
        for k in env.keys where !keep.contains(k) &&
            (k.hasPrefix("CLAUDE") || k.hasPrefix("ANTHROPIC_") || k == "BAGGAGE" || k == "DISABLE_AUTOUPDATER" || k == "DISABLE_MICROCOMPACT") {
            env.removeValue(forKey: k)
        }
        let extra = ["~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
            .map { NSString(string: $0).expandingTildeInPath }
        env["PATH"] = (extra + (env["PATH"].map { [$0] } ?? [])).joined(separator: ":")
        env["TERM"] = env["TERM"] ?? "xterm-256color"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env
    }

    static func locate() -> String? {
        if let p = searchPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return p }
        // Fall back to her login shell's PATH.
        let r = try? runSync("/bin/zsh", ["-lc", "command -v claude"])
        let path = r?.out.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    static func status() async -> Status {
        await Task.detached {
            guard let path = locate() else { return Status(installed: false, loggedIn: false, email: nil, path: nil) }
            guard let r = try? runSync(path, ["auth", "status"]),
                  let data = r.out.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return Status(installed: true, loggedIn: false, email: nil, path: path)
            }
            return Status(installed: true, loggedIn: (obj["loggedIn"] as? Bool) ?? false,
                          email: obj["email"] as? String, path: path)
        }.value
    }

    struct RunResult { var out: String; var err: String; var code: Int32 }

    static func runSync(_ exe: String, _ args: [String], cwd: URL? = nil) throws -> RunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = environment
        if let cwd { p.currentDirectoryURL = cwd }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        p.standardInput = FileHandle.nullDevice
        try p.run()
        // Read before waiting so large outputs can't deadlock the pipe.
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return RunResult(out: String(decoding: o, as: UTF8.self), err: String(decoding: e, as: UTF8.self), code: p.terminationStatus)
    }

    enum CLIError: LocalizedError {
        case notInstalled, failed(String), noOutput
        var errorDescription: String? {
            switch self {
            case .notInstalled: "Claude Code isn't installed."
            case .failed(let s): s
            case .noOutput: "Claude didn't return a result."
            }
        }
    }

    /// Runs `claude -p` headlessly in the workspace and returns `structured_output` decoded as T.
    /// `onEvent` receives short progress strings (files Claude is reading, etc).
    /// Every call passes `--strict-mcp-config`: her claude.ai connectors (Gmail, Drive…) would otherwise add
    /// tens of thousands of tokens of tool definitions to each request, and Hank never needs them.
    static func ask<T: Decodable>(_ prompt: String, schema: String, model: String?, effort: String? = nil, as: T.Type,
                                  onEvent: @escaping @Sendable (String) -> Void = { _ in }) async throws -> T {
        var args = ["-p", prompt, "--output-format", "stream-json", "--verbose", "--json-schema", schema,
                    "--permission-mode", "acceptEdits", "--allowedTools", "Read", "Glob", "Grep", "Bash(ls:*)", "--strict-mcp-config"]
        if let model, !model.isEmpty { args += ["--model", model] }
        if let effort, !effort.isEmpty { args += ["--effort", effort] }
        return try decode(try await run(args, stdin: nil, cwd: Workspace.root, onEvent: onEvent), as: T.self)
    }

    /// Ends single-turn requests: without it, models sometimes write the whole JSON as text and then again.
    static let submitInstruction = "When you're done, submit the result once with the StructuredOutput tool. Don't write it out as text."

    /// What goes into a single-turn request: text and images, in order.
    enum Content: Equatable { case text(String), png(Data) }

    /// One turn, no tools: everything the model needs (text and images) goes in on stdin, so it never
    /// spends turns opening files and nothing is re-sent turn after turn. `cwd` decides which CLAUDE.md
    /// loads: the workspace for Hank's voice, a neutral folder for the handwriting reader.
    static func ask<T: Decodable>(content: [Content], schema: String, model: String?, effort: String? = nil,
                                  cwd: URL = Workspace.root, as: T.Type,
                                  onEvent: @escaping @Sendable (String) -> Void = { _ in }) async throws -> T {
        var args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                    "--json-schema", schema, "--tools", "", "--disable-slash-commands", "--no-session-persistence", "--strict-mcp-config"]
        if let model, !model.isEmpty { args += ["--model", model] }
        if let effort, !effort.isEmpty { args += ["--effort", effort] }
        try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
        return try decode(try await run(args, stdin: userMessage(content), cwd: cwd, onEvent: onEvent), as: T.self)
    }

    /// A stream-json user message with text and base64 PNG blocks (the Messages API content shape).
    static func userMessage(_ content: [Content]) -> Data {
        let blocks: [[String: Any]] = content.map {
            switch $0 {
            case .text(let s): ["type": "text", "text": s]
            case .png(let d): ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": d.base64EncodedString()]]
            }
        }
        let line: [String: Any] = ["type": "user", "message": ["role": "user", "content": blocks]]
        return (try! JSONSerialization.data(withJSONObject: line)) + Data([0x0A])
    }

    private static func decode<T: Decodable>(_ data: Data, as: T.Type) throws -> T {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CLIError.noOutput }
        if (obj["is_error"] as? Bool) == true {
            throw CLIError.failed((obj["result"] as? String) ?? "Claude reported an error.")
        }
        let payload: Any
        if let s = obj["structured_output"], !(s is NSNull) { payload = s }
        else if let text = obj["result"] as? String, let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
                let o = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) { payload = o }
        else { throw CLIError.noOutput }
        let json = try JSONSerialization.data(withJSONObject: payload)
        return try JSON.decoder.decode(T.self, from: json)
    }

    /// Runs the CLI and returns its final `result` stream-json line.
    private static func run(_ args: [String], stdin: Data?, cwd: URL,
                            onEvent: @escaping @Sendable (String) -> Void) async throws -> Data {
        guard let exe = locate() else { throw CLIError.notInstalled }
        return try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
            p.environment = environment
            p.currentDirectoryURL = cwd
            let input = stdin.map { _ in Pipe() }
            p.standardInput = input ?? FileHandle.nullDevice
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            let lock = NSLock()
            let st = StreamState()
            let once = Once()
            @Sendable func finish(_ line: Data?) {
                guard once.claim() else { return }
                if let line { cont.resume(returning: line) }
                else {
                    let e = String(decoding: err.fileHandleForReading.availableData, as: UTF8.self)
                    cont.resume(throwing: CLIError.failed("Claude stopped without an answer. \(e.prefix(400))"))
                }
                // The CLI sometimes lingers after its result; don't leave it running.
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if p.isRunning { p.terminate() } }
            }
            out.fileHandleForReading.readabilityHandler = { h in
                let chunk = h.availableData
                guard !chunk.isEmpty else { return }
                lock.lock(); st.buffer.append(chunk)
                while let nl = st.buffer.firstIndex(of: 0x0A) {
                    let line = st.buffer.subdata(in: st.buffer.startIndex..<nl)
                    st.buffer.removeSubrange(st.buffer.startIndex...nl)
                    ClaudeUsage.ingest(line)
                    if let ev = describe(line) { onEvent(ev) }
                    if line.range(of: Data("\"type\":\"result\"".utf8)) != nil { st.resultLine = line }
                }
                let result = st.resultLine
                lock.unlock()
                if let result { finish(result) }
            }
            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                let rest = out.fileHandleForReading.readDataToEndOfFile()
                lock.lock()
                st.buffer.append(rest)
                for line in st.buffer.split(separator: 0x0A) { ClaudeUsage.ingest(Data(line)) }
                for line in st.buffer.split(separator: 0x0A) where line.range(of: Data("\"type\":\"result\"".utf8)) != nil {
                    st.resultLine = Data(line)
                }
                let final = st.resultLine
                lock.unlock()
                finish(final)
            }
            do {
                try p.run()
                if let input, let stdin {
                    // Images can be megabytes: write off the caller's thread, then close so the CLI starts.
                    DispatchQueue.global().async {
                        try? input.fileHandleForWriting.write(contentsOf: stdin)
                        try? input.fileHandleForWriting.close()
                    }
                }
            } catch { if once.claim() { cont.resume(throwing: error) } }
        }
    }

    /// Turns a stream-json line into a short human description, if it's interesting.
    static func describe(_ line: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let content = msg["content"] as? [[String: Any]] else { return nil }
        for c in content {
            if c["type"] as? String == "tool_use", let input = c["input"] as? [String: Any] {
                if let path = input["file_path"] as? String {
                    let name = URL(fileURLWithPath: path).lastPathComponent
                    if name.hasPrefix("page-") { return "Reading your \(name.replacingOccurrences(of: "page-", with: "page ").replacingOccurrences(of: ".png", with: ""))" }
                    return "Looking at \(name)"
                }
                return "Thinking…"
            }
        }
        return nil
    }
}

private final class StreamState: @unchecked Sendable {
    var buffer = Data()
    var resultLine: Data?
}
