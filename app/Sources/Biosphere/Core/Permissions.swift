import AppKit
import Observation
import UserNotifications

/// The three macOS permissions Biosphere uses, with friendly status + one-click requests.
@MainActor
@Observable
final class Permissions {
    enum Status { case unknown, granted, denied }

    var notifications: Status = .unknown
    var downloads: Status = .unknown
    var accessibility: Status = .unknown

    private let askedDownloadsKey = "permissions.askedDownloads"

    func refresh() async {
        accessibility = AXIsProcessTrusted() ? .granted : .unknown   // can't tell 'never asked' from 'denied'
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }   // tests/tools: no notification centre
        let n = await UNUserNotificationCenter.current().notificationSettings()
        notifications = switch n.authorizationStatus {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        default: .unknown
        }
        // Only probe Downloads once she has been asked, so a status check never pops a prompt.
        if UserDefaults.standard.bool(forKey: askedDownloadsKey) {
            downloads = await Self.canReadDownloads() ? .granted : .denied
        }
    }

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
        if notifications == .denied { Self.open("x-apple.systempreferences:com.apple.Notifications-Settings.extension") }
    }

    /// Reading Downloads triggers macOS's one-time "allow access" prompt.
    func requestDownloads() async {
        UserDefaults.standard.set(true, forKey: askedDownloadsKey)
        downloads = await Self.canReadDownloads() ? .granted : .denied
        if downloads == .denied { Self.open("x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") }
    }

    func requestAccessibility() {
        AirDropAuto.requestPermission()
        if !AXIsProcessTrusted() { AirDropAuto.openAccessibilitySettings() }
    }

    nonisolated static func canReadDownloads() async -> Bool {
        await Task.detached {
            let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            return (try? FileManager.default.contentsOfDirectory(atPath: d.path)) != nil
        }.value
    }

    static func open(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }
}

/// A one-page "Hi from Biosphere" PDF for testing the AirDrop setup.
enum WelcomePage {
    static func make() -> URL {
        let url = Workspace.root.appendingPathComponent("Biosphere test page.pdf")
        var box = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return url }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ctx.beginPDFPage(nil)
        PDFComposer.drawText("Biosphere", rect: CGRect(x: 60, y: 700, width: 480, height: 40), size: 32, weight: .heavy, color: PDFComposer.purple)
        PDFComposer.drawText("It works! 🎉", rect: CGRect(x: 60, y: 640, width: 480, height: 40), size: 26, weight: .bold)
        PDFComposer.drawText("This page came straight from your Mac. From now on, \"Send to iPad\" lands your practice papers here in one click. Write on them, then AirDrop them back and Hank will mark them.",
                             rect: CGRect(x: 60, y: 540, width: 470, height: 90), size: 14, color: NSColor(white: 0.3, alpha: 1))
        ctx.endPDFPage()
        ctx.closePDF()
        NSGraphicsContext.current = nil
        return url
    }
}
