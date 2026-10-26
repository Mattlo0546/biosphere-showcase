import Foundation

/// Developer conveniences: reload content without restarting, and seed the dev data folder.
extension AppModel {
    /// ⌘R: re-copies Hank's persona + skills and the question bank, then reloads them. Hank reads his
    /// files fresh on every message, so prompt/skill edits apply to the very next chat.
    func reloadContent() {
        do {
            try Workspace.prepare()
            biology = try Bank(slug: Subject.biology.slug)
            maths = try? Bank(slug: Subject.maths.slug)
            progress = ProgressStore.load()
            reloadSessions()
            writeSummaries()
            biologyPack.refresh(); mathsPack.refresh()
            exam.reload()
            say("Reloaded Hank's prompts, skills and the question bank.")
        } catch {
            say("Reload failed: \(error.localizedDescription)")
        }
    }

    /// First run of Biosphere Dev: copy your real sessions/progress so there's something to look at.
    static func seedDevDataIfNeeded() {
        guard Workspace.isDevBuild else { return }
        let fm = FileManager.default
        let real = fm.homeDirectoryForCurrentUser.appendingPathComponent("Biosphere")
        guard !fm.fileExists(atPath: Workspace.root.path), fm.fileExists(atPath: real.path) else { return }
        try? fm.createDirectory(at: Workspace.root, withIntermediateDirectories: true)
        for item in ["sessions", "progress.json", "settings.json", "chat.json", "usage.json"] {
            let from = real.appendingPathComponent(item)
            if fm.fileExists(atPath: from.path) { try? fm.copyItem(at: from, to: Workspace.root.appendingPathComponent(item)) }
        }
    }
}
