import Foundation
import Observation

/// Her real Claude plan usage, read from the `rate_limit_event` that every `claude -p` stream emits
/// (utilization per limit window + reset time). Updated by every chat, marking and planning call.
@MainActor
@Observable
final class ClaudeUsage {
    static let shared = ClaudeUsage()

    struct Window: Codable, Hashable, Identifiable {
        var key: String
        var utilization: Double      // 0...1
        var resetsAt: Date?
        var id: String { key }

        var name: String {
            switch key {
            case "five_hour": "5-hour limit"
            case "seven_day": "Weekly limit"
            case "seven_day_opus": "Weekly limit (Opus)"
            case "seven_day_sonnet": "Weekly limit (Sonnet)"
            default: key.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
    }

    private struct Saved: Codable { var windows: [Window]; var status: String?; var updatedAt: Date? }

    var windows: [Window] = []
    var status: String?          // "allowed", "allowed_warning", "rejected"
    var updatedAt: Date?
    var refreshing = false

    /// The window closest to running out — that's the one the circle shows.
    var primary: Window? { windows.max { $0.utilization < $1.utilization } }
    var isStale: Bool { updatedAt.map { Date().timeIntervalSince($0) > 15 * 60 } ?? true }

    private static var file: URL { Workspace.root.appendingPathComponent("usage.json") }

    init() {
        if let s = try? JSON.load(Saved.self, from: Self.file) {
            windows = s.windows; status = s.status; updatedAt = s.updatedAt
            // Drop windows whose reset time has passed — they've refilled.
            windows = windows.map { w in
                var w = w
                if let r = w.resetsAt, r < Date() { w.utilization = 0; w.resetsAt = nil }
                return w
            }
        }
    }

    /// Call with every stream-json line from the CLI; cheap no-op for anything that isn't a rate-limit event.
    nonisolated static func ingest(_ line: Data) {
        guard line.range(of: Data("rate_limit_event".utf8)) != nil,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "rate_limit_event",
              let info = obj["rate_limit_info"] as? [String: Any] else { return }
        var found: [Window] = []
        if let unified = info["unifiedWindows"] as? [String: Any] {
            for (k, v) in unified {
                guard let w = v as? [String: Any] else { continue }
                found.append(Window(key: k, utilization: (w["utilization"] as? Double) ?? 0,
                                    resetsAt: (w["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }))
            }
        } else if let k = info["rateLimitType"] as? String {
            found.append(Window(key: k, utilization: (info["utilization"] as? Double) ?? 0,
                                resetsAt: (info["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) }))
        }
        let status = info["status"] as? String
        Task { @MainActor in shared.update(found, status: status) }
    }

    private func update(_ found: [Window], status: String?) {
        var byKey = Dictionary(uniqueKeysWithValues: windows.map { ($0.key, $0) })
        for w in found { byKey[w.key] = w }
        windows = byKey.values.sorted { $0.key < $1.key }
        self.status = status
        updatedAt = Date()
        try? JSON.save(Saved(windows: windows, status: status, updatedAt: updatedAt), to: Self.file)
    }

    /// A tiny Haiku call (run outside the workspace so it doesn't load Hank's files) just to read the meter.
    func refresh() async {
        guard !refreshing, let exe = ClaudeCLI.locate() else { return }
        refreshing = true
        defer { refreshing = false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = ["-p", "Reply with just: ok", "--model", "haiku", "--output-format", "stream-json", "--verbose", "--strict-mcp-config"]
        p.environment = ClaudeCLI.environment
        p.currentDirectoryURL = Workspace.root
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let out = Pipe()
        p.standardOutput = out
        let buffer = LineBuffer()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let once = Once()
            @Sendable func done() {
                guard once.claim() else { return }
                out.fileHandleForReading.readabilityHandler = nil
                if p.isRunning { p.terminate() }
                cont.resume()
            }
            out.fileHandleForReading.readabilityHandler = { h in
                let chunk = h.availableData
                if chunk.isEmpty { done(); return }
                for line in buffer.append(chunk) {
                    ClaudeUsage.ingest(line)
                    // The CLI can linger after answering; stop once we have what we came for.
                    if line.range(of: Data("\"type\":\"result\"".utf8)) != nil { done() }
                }
            }
            p.terminationHandler = { _ in done() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 60) { done() }
            if (try? p.run()) == nil { done() }
        }
    }
}

/// Lets exactly one caller through (for resuming a continuation from several callbacks).
final class Once: @unchecked Sendable {
    private var used = false
    private let lock = NSLock()
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
}
