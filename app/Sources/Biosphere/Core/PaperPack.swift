import Foundation
import Observation

/// The past-paper PDFs live outside the app (they're big and change rarely). They're published as a
/// GitHub release (`papers-<subject>-<hash>`) and downloaded once into ~/Biosphere/bank/<subject>/papers.
@MainActor
@Observable
final class PaperPack {
    struct Manifest: Codable { var tag: String; var asset: String; var count: Int }
    enum State: Equatable { case checking, ready, missing, downloading(Double), installing, failed(String) }

    let slug: String
    let bank: URL                       // Workspace.bank; tests pass a scratch folder
    var state: State = .checking
    private(set) var manifest: Manifest?

    var isReady: Bool { state == .ready }
    var papersDir: URL { bank.appendingPathComponent("\(slug)/papers") }
    private var stampFile: URL { papersDir.appendingPathComponent(".pack") }

    init(slug: String, bank: URL = Workspace.bank) {
        self.slug = slug
        self.bank = bank
        manifest = try? JSON.load(Manifest.self, from: bank.appendingPathComponent("\(slug)/pack.json"))
        refresh()
    }

    var pdfCount: Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: papersDir.path)) ?? []).filter { $0.hasSuffix(".pdf") }.count
    }

    /// Re-reads the manifest every time: `AppModel` creates its packs before `Workspace.prepare()` copies an
    /// updated bank in, so the one read in `init` can be the previous version's (and call old papers "ready").
    func refresh() {
        if let fresh = try? JSON.load(Manifest.self, from: bank.appendingPathComponent("\(slug)/pack.json")) {
            manifest = fresh
        }
        guard let m = manifest else { state = pdfCount > 0 ? .ready : .missing; return }
        let stamp = try? String(contentsOf: stampFile, encoding: .utf8)
        if pdfCount >= m.count && (stamp == m.tag || stamp == nil) {
            try? m.tag.write(to: stampFile, atomically: true, encoding: .utf8)
            state = .ready
        } else {
            state = .missing
        }
    }

    /// Makes sure the papers are present: dev checkout first (instant), otherwise download from GitHub.
    func ensure() async {
        refresh()
        guard !isReady, let m = manifest else { return }
        if case .downloading = state { return }
        if copyFromDevCheckout(m) { refresh(); if isReady { return } }
        guard GitHub.hasToken else {
            state = .failed("This build can't download the past papers (no update key). Ask for a new build.")
            return
        }
        state = .downloading(0)
        do {
            let release = try await GitHub.release(tag: m.tag)
            guard let asset = release.assets.first(where: { $0.name == m.asset }) else { throw GitHub.Failure.notFound(m.asset) }
            let zip = try await GitHub.download(asset) { p in Task { @MainActor in self.state = .downloading(p) } }
            state = .installing
            let dest = bank.appendingPathComponent(slug)
            try await Task.detached { try GitHub.unzip(zip, to: dest); try? FileManager.default.removeItem(at: zip) }.value
            try? m.tag.write(to: stampFile, atomically: true, encoding: .utf8)
            refresh()
            if !isReady { state = .failed("The download finished but some papers are missing. Try again.") }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// On the developer's Mac the papers already sit in the repo: clone them instead of downloading.
    private func copyFromDevCheckout(_ m: Manifest) -> Bool {
        if ProcessInfo.processInfo.environment["BIOSPHERE_NO_DEV_PAPERS"] != nil { return false }   // test the real download
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/bank/\(slug)/papers")
        // Worktrees don't have the (git-ignored) PDFs, so also try the real install's downloaded copy.
        let installed = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Biosphere/bank/\(slug)/papers")
        let candidates = [repo, installed].filter { $0.standardizedFileURL != papersDir.standardizedFileURL }
        guard let source = candidates.first(where: {
            ((try? FileManager.default.contentsOfDirectory(atPath: $0.path)) ?? []).filter { $0.hasSuffix(".pdf") }.count >= m.count
        }), let files = try? FileManager.default.contentsOfDirectory(atPath: source.path) else { return false }
        let repo_ = source
        let fm = FileManager.default
        try? fm.createDirectory(at: papersDir, withIntermediateDirectories: true)
        for f in files where f.hasSuffix(".pdf") {
            let dest = papersDir.appendingPathComponent(f)
            if !fm.fileExists(atPath: dest.path) { try? fm.copyItem(at: repo_.appendingPathComponent(f), to: dest) }
        }
        try? m.tag.write(to: stampFile, atomically: true, encoding: .utf8)
        return true
    }
}
