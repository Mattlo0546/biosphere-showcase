import AppKit
import Observation
import Security

/// Checks GitHub Releases for a newer Biosphere and installs it in place.
/// Stable releases are tagged `vX.Y.Z`; pre-releases (betas) only show up when beta updates are on.
@MainActor
@Observable
final class Updater {
    struct Available: Equatable { var version: String; var notes: String; var assetID: Int; var size: Int; var beta: Bool }

    var available: Available?
    var checking = false
    var installing = false
    var progress: Double?
    var message: String?
    var lastChecked: Date?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func check(beta: Bool, quiet: Bool = true) async {
        if Workspace.isDevBuild { if !quiet { message = "Dev builds don't self-update; run scripts/dev.sh." }; return }
        guard GitHub.hasToken, !checking, !installing else {
            if !quiet && !GitHub.hasToken { message = GitHub.Failure.noToken.localizedDescription }
            return
        }
        checking = true
        defer { checking = false; lastChecked = Date() }
        do {
            let current = GitHub.version(Self.currentVersion)
            let candidates = try await GitHub.releases()
                .filter { !$0.draft && $0.tagName.hasPrefix("v") && (beta || !$0.prerelease) }
                .filter { GitHub.isNewer(GitHub.version($0.tagName), than: current) }
                .sorted { GitHub.isNewer(GitHub.version($0.tagName), than: GitHub.version($1.tagName)) }
            if let r = candidates.first, let asset = r.assets.first(where: { $0.name == "Biosphere.zip" }) {
                available = Available(version: String(r.tagName.dropFirst()), notes: r.body ?? "", assetID: asset.id,
                                      size: asset.size, beta: r.prerelease)
                message = nil
            } else {
                available = nil
                if !quiet { message = "You're up to date (\(Self.currentVersion))." }
            }
        } catch {
            if !quiet { message = error.localizedDescription }
        }
    }

    func install() async {
        guard let a = available, !installing else { return }
        let appURL = Bundle.main.bundleURL
        if appURL.path.contains("/AppTranslocation/") {
            message = "Move Biosphere into your Applications folder first, then try again."
            return
        }
        installing = true
        progress = 0
        message = "Downloading \(a.version)…"
        do {
            let zip = try await GitHub.download(GitHub.Asset(id: a.assetID, name: "Biosphere.zip", size: a.size)) { p in
                Task { @MainActor in self.progress = p }
            }
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("BiosphereUpdate-\(UUID().uuidString)")
            try GitHub.unzip(zip, to: staging)
            guard let newApp = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else { throw CocoaError(.fileNoSuchFile) }
            guard Self.signedBySameDeveloper(newApp) else {
                throw NSError(domain: "Biosphere", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "The download wasn't signed by the same developer, so it wasn't installed."])
            }
            message = "Installing — Biosphere will reopen in a moment…"
            try Self.swapAndRelaunch(old: appURL, new: newApp)
            NSApp.terminate(nil)
        } catch {
            installing = false
            progress = nil
            message = "Update failed: \(error.localizedDescription)"
        }
    }

    /// The new app must satisfy this app's own code-signing requirement (same identifier, same key).
    /// Older ad-hoc-signed builds have no stable identity, so for those we only check the new app is validly signed.
    nonisolated static func signedBySameDeveloper(_ newApp: URL) -> Bool {
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(newApp as CFURL, [], &newCode) == errSecSuccess, let newCode else { return false }
        var selfCode: SecCode?
        var requirement: SecRequirement?
        if SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
           SecCodeCopyDesignatedRequirement(selfCode as! SecStaticCode, [], &requirement) == errSecSuccess,
           let requirement {
            var text: CFString?
            SecRequirementCopyString(requirement, [], &text)
            if let t = text as String?, t.contains("certificate") {
                return SecStaticCodeCheckValidity(newCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
            }
        }
        return SecStaticCodeCheckValidity(newCode, [], nil) == errSecSuccess
    }

    /// A tiny helper script waits for us to quit, swaps the bundles, and reopens the app.
    static func swapAndRelaunch(old: URL, new: URL) throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("biosphere-update.sh")
        let pid = ProcessInfo.processInfo.processIdentifier
        let sh = """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        OLD='\(old.path)'
        rm -rf "$OLD.previous"
        mv "$OLD" "$OLD.previous" && mv '\(new.path)' "$OLD" && rm -rf "$OLD.previous"
        xattr -dr com.apple.quarantine "$OLD" 2>/dev/null
        open "$OLD"
        """
        try sh.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path]
        try p.run()
    }
}
