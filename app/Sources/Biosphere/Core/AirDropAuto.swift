import AppKit
import ApplicationServices

/// "Send to iPad" in one click. macOS has no public API to AirDrop to a specific device, but the
/// AirDrop picker is a window inside our own process whose device tiles are accessibility buttons
/// named after each device. With Accessibility permission we open the picker and press her iPad's
/// tile ourselves; without it (or if the iPad isn't nearby) the picker simply stays open for her.
@MainActor
enum AirDropAuto {
    enum Outcome { case sending(String), manual(String) }

    static var canTap: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt (first time) that leads to Privacy & Security › Accessibility.
    static func requestPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private static var delegate: Delegate?

    /// Opens AirDrop with the file and, if possible, taps `device` automatically.
    static func send(_ url: URL, to device: String, onDone: @escaping (Bool) -> Void = { _ in }) async -> Outcome {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: [url]) else {
            return .manual("AirDrop isn't available on this Mac — turn on Wi-Fi and Bluetooth.")
        }
        let d = Delegate(onDone: onDone)
        delegate = d
        service.delegate = d
        service.perform(withItems: [url])
        let name = device.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .manual("AirDrop is open — tap your iPad. (Add its name in Settings to skip this.)") }
        guard canTap else { return .manual("AirDrop is open — tap your iPad. (Allow Biosphere in Accessibility to make this automatic.)") }
        // The iPad tile can take a few seconds to appear while AirDrop discovers nearby devices.
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if let button = deviceButtons().first(where: { matches($0.name, name) }) {
                AXUIElementPerformAction(button.element, kAXPressAction as CFString)
                return .sending(button.name)
            }
        }
        return .manual("Couldn't see \(name) nearby — make sure it's unlocked with AirDrop on, then tap it in the AirDrop window.")
    }

    /// Opens AirDrop briefly to list the devices it can see, then closes it again.
    static func discoverDevices() async -> [String] {
        guard canTap, let service = NSSharingService(named: .sendViaAirDrop) else { return [] }
        let probe = FileManager.default.temporaryDirectory.appendingPathComponent("Biosphere — finding your iPad.txt")
        try? "Biosphere is looking for your iPad. You can ignore this.".write(to: probe, atomically: true, encoding: .utf8)
        service.perform(withItems: [probe])
        var names: [String] = []
        for i in 0..<28 {   // up to ~7s; stop early once the list settles
            try? await Task.sleep(nanoseconds: 250_000_000)
            let now = deviceButtons().map(\.name)
            if !now.isEmpty && now == names && i > 10 { break }
            names = now
        }
        cancelPicker()
        return names
    }

    static func cancelPicker() {
        for w in airDropWindows() {
            if let cancel = descendants(of: w).first(where: { role($0) == kAXButtonRole && title($0) == "Cancel" }) {
                AXUIElementPerformAction(cancel, kAXPressAction as CFString)
            }
        }
    }

    /// "Mattpad Air" matches "Mattpad Air (2)"; case and curly quotes don't matter.
    static func matches(_ tile: String, _ wanted: String) -> Bool {
        func norm(_ s: String) -> String {
            s.lowercased().replacingOccurrences(of: "’", with: "'")
                .replacingOccurrences(of: "\\s*\\(\\d+\\)$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
        }
        let a = norm(tile), b = norm(wanted)
        return a == b || a.hasPrefix(b) || b.hasPrefix(a)
    }

    // MARK: accessibility helpers (our own process only)

    private struct Tile { var name: String; var element: AXUIElement }

    private static func deviceButtons() -> [Tile] {
        airDropWindows().flatMap { w in
            descendants(of: w).compactMap { e -> Tile? in
                guard role(e) == kAXButtonRole, let t = title(e), !t.isEmpty, t != "Cancel" else { return nil }
                return Tile(name: t, element: e)
            }
        }
    }

    private static func airDropWindows() -> [AXUIElement] {
        let app = AXUIElementCreateApplication(getpid())
        return ((attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []).filter { title($0) == "AirDrop" }
    }

    private static func descendants(of e: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        guard depth < 12 else { return [] }
        let kids = (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
        return kids + kids.flatMap { descendants(of: $0, depth: depth + 1) }
    }

    private static func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
    }
    private static func role(_ e: AXUIElement) -> String? { attr(e, kAXRoleAttribute) as? String }
    private static func title(_ e: AXUIElement) -> String? {
        (attr(e, kAXTitleAttribute) as? String) ?? (attr(e, kAXDescriptionAttribute) as? String)
    }

    private final class Delegate: NSObject, NSSharingServiceDelegate {
        let onDone: (Bool) -> Void
        init(onDone: @escaping (Bool) -> Void) { self.onDone = onDone }
        func sharingService(_ s: NSSharingService, didShareItems items: [Any]) { onDone(true) }
        func sharingService(_ s: NSSharingService, didFailToShareItems items: [Any], error: Error) {
            if (error as NSError).code != NSUserCancelledError { onDone(false) }
        }
    }
}
