import AppKit

/// Getting files onto the iPad: AirDrop (opens the AirDrop picker with the file ready — she just
/// taps her iPad) or iCloud Drive (copied into iCloud Drive/Biosphere, appears in the iPad's Files app).
enum Sharing {
    @MainActor
    static func sendToIPad(_ url: URL, method: AppSettings.SendMethod) -> String {
        switch method {
        case .airdrop:
            guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: [url]) else {
                return copyToICloud(url) + " (AirDrop isn't available, so I used iCloud Drive)"
            }
            service.perform(withItems: [url])
            return "AirDrop is open — pick your iPad."
        case .icloud:
            return copyToICloud(url)
        }
    }

    static func copyToICloud(_ url: URL, folder: String = "To do") -> String {
        let dir = Workspace.iCloudRoot.appendingPathComponent(folder)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            return "Saved to iCloud Drive › Biosphere › \(folder). Open the Files app on your iPad."
        } catch {
            return "Couldn't copy to iCloud Drive: \(error.localizedDescription)"
        }
    }

    /// Interactive screenshot (drag to select, or press space for a window). Returns the PNG.
    @MainActor
    static func captureScreenshot() async -> URL? {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        let file = Workspace.screenshots.appendingPathComponent("Biosphere screenshot \(stamp).png")
        NSApp.hide(nil)
        try? await Task.sleep(nanoseconds: 350_000_000)
        let ok = await Task.detached { () -> Bool in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-i", "-o", file.path]
            try? p.run(); p.waitUntilExit()
            return p.terminationStatus == 0
        }.value
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard ok, FileManager.default.fileExists(atPath: file.path) else { return nil }
        try? await Task.sleep(nanoseconds: 300_000_000)
        return file
    }
}
