import Foundation

/// The folder Biosphere and Claude share: ~/Biosphere
///
///   CLAUDE.md, .claude/skills/   Hank's persona and skills
///   bank/                        copy of the question bank shipped inside the app (refreshed when the app updates)
///   sessions/<id>/               session.json, questions.pdf, answer_key.json, completed.pdf, pages/, results.json
///   requests/                    session requests written by Claude's build-session skill
///   progress.json                every marked attempt
///   progress_summary.json        per-subtopic status, regenerated for Claude to read
///   screenshots/
enum Workspace {
    /// "Biosphere Dev" (scripts/dev.sh) and Xcode previews use their own data folder and never self-update.
    static let isDevBuild: Bool = Bundle.main.bundleIdentifier == "app.biosphere.dev"
        || ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    static let root: URL = {
        if let h = ProcessInfo.processInfo.environment["BIOSPHERE_HOME"], !h.isEmpty {
            return URL(fileURLWithPath: NSString(string: h).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(isDevBuild ? "Biosphere-Dev" : "Biosphere")
    }()
    static var sessions: URL { root.appendingPathComponent("sessions") }
    static var requests: URL { root.appendingPathComponent("requests") }
    static var screenshots: URL { root.appendingPathComponent("screenshots") }
    static var bank: URL { root.appendingPathComponent("bank") }
    static var progressFile: URL { root.appendingPathComponent("progress.json") }
    static var summaryFile: URL { root.appendingPathComponent("progress_summary.json") }
    /// Biology keeps progress_summary.json (older skills read it); other subjects get their own digest.
    static func summaryFile(for slug: String) -> URL {
        slug == Subject.biology.slug ? summaryFile : root.appendingPathComponent("progress_summary_\(slug).json")
    }
    static var settingsFile: URL { root.appendingPathComponent("settings.json") }

    static let iCloudRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Biosphere")

    /// Resources live in the app bundle; when running from `swift run` fall back to the repo.
    static var resources: URL {
        // Dev mode reads prompts, skills and the bank straight from the repo, so edits show up on ⌘R.
        if let r = ProcessInfo.processInfo.environment["BIOSPHERE_RESOURCES"], !r.isEmpty {
            return URL(fileURLWithPath: r)
        }
        if let r = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: r.appendingPathComponent("bank").path) {
            return r
        }
        // Sources/Biosphere/Core/Workspace.swift -> repo root
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return repo.appendingPathComponent("app/Resources")
    }

    static func prepare() throws {
        let fm = FileManager.default
        for dir in [root, sessions, requests, screenshots, root.appendingPathComponent(".claude")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // The bank's small files (syllabus, questions, index, pack manifest) are copied from the app on every
        // launch so app updates bring new labels; the big paper PDFs are a separate download (PaperPack) and are
        // never deleted here. A real copy, not a link into the bundle, so Claude reading it never triggers
        // folder-permission prompts. (APFS clones make the copies instant.)
        if (try? fm.destinationOfSymbolicLink(atPath: bank.path)) != nil { try? fm.removeItem(at: bank) }
        let source = resources.appendingPathComponent("bank")
        for subject in (try? fm.contentsOfDirectory(atPath: source.path)) ?? [] where !subject.hasPrefix(".") {
            let from = source.appendingPathComponent(subject), to = bank.appendingPathComponent(subject)
            try fm.createDirectory(at: to.appendingPathComponent("papers"), withIntermediateDirectories: true)
            for file in (try? fm.contentsOfDirectory(atPath: from.path)) ?? [] where file != "papers" {
                try? fm.removeItem(at: to.appendingPathComponent(file))
                try fm.copyItem(at: from.appendingPathComponent(file), to: to.appendingPathComponent(file))
            }
            // Builds that still bundle the PDFs (developer builds): bring them along too.
            let bundled = from.appendingPathComponent("papers")
            for pdf in (try? fm.contentsOfDirectory(atPath: bundled.path)) ?? [] where pdf.hasSuffix(".pdf") {
                let dest = to.appendingPathComponent("papers/\(pdf)")
                if !fm.fileExists(atPath: dest.path) { try? fm.copyItem(at: bundled.appendingPathComponent(pdf), to: dest) }
            }
        }
        try? fm.removeItem(at: root.appendingPathComponent(".bank-version"))
        // Hank's persona + skills: refreshed from the template on every launch.
        let template = resources.appendingPathComponent("template")
        if let items = try? fm.contentsOfDirectory(at: template, includingPropertiesForKeys: nil) {
            for item in items {
                let dest = root.appendingPathComponent(item.lastPathComponent)
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: item, to: dest)
            }
        }
        let skills = resources.appendingPathComponent("skills")
        let skillsDest = root.appendingPathComponent(".claude/skills")
        if fm.fileExists(atPath: skills.path) {
            try? fm.removeItem(at: skillsDest)
            try fm.copyItem(at: skills, to: skillsDest)
        }
    }

    static func sessionDir(_ id: String) -> URL { sessions.appendingPathComponent(id) }

    /// Changes whenever the shipped bank changes (app update).
    static func bankStamp(_ dir: URL) -> String {
        let fm = FileManager.default
        let subjects = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return subjects.sorted().map { slug -> String in
            let q = dir.appendingPathComponent("\(slug)/questions.json")
            let a = try? fm.attributesOfItem(atPath: q.path)
            let size = (a?[.size] as? NSNumber)?.intValue ?? 0
            let date = (a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(slug):\(size):\(Int(date))"
        }.joined(separator: ",")
    }
}

enum JSON {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

struct AppSettings: Codable {
    enum SendMethod: String, Codable, CaseIterable { case airdrop, icloud }
    var sendMethod: SendMethod = .airdrop
    var markingModel: String = "sonnet"
    var readerModel: String = "haiku"        // reads her handwriting before Hank marks it
    var effort: String = "medium"
    var ipadName: String = ""
    var watchDownloads: Bool = true
    var minutesPerMark: Double = 1.25
    var minutesPerMCQ: Double = 1.5
    var onboarded: Bool = false
    var betaUpdates: Bool = false

    init() {}

    // Tolerant decoding so new settings never wipe out old ones.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        sendMethod = (try? c.decode(SendMethod.self, forKey: .sendMethod)) ?? d.sendMethod
        markingModel = (try? c.decode(String.self, forKey: .markingModel)) ?? d.markingModel
        readerModel = (try? c.decode(String.self, forKey: .readerModel)) ?? d.readerModel
        effort = (try? c.decode(String.self, forKey: .effort)) ?? d.effort
        ipadName = (try? c.decode(String.self, forKey: .ipadName)) ?? d.ipadName
        watchDownloads = (try? c.decode(Bool.self, forKey: .watchDownloads)) ?? d.watchDownloads
        minutesPerMark = (try? c.decode(Double.self, forKey: .minutesPerMark)) ?? d.minutesPerMark
        minutesPerMCQ = (try? c.decode(Double.self, forKey: .minutesPerMCQ)) ?? d.minutesPerMCQ
        onboarded = (try? c.decode(Bool.self, forKey: .onboarded)) ?? d.onboarded
        betaUpdates = (try? c.decode(Bool.self, forKey: .betaUpdates)) ?? d.betaUpdates
    }

    static func load() -> AppSettings {
        (try? JSON.load(AppSettings.self, from: Workspace.settingsFile)) ?? AppSettings()
    }
    func save() { try? JSON.save(self, to: Workspace.settingsFile) }
}
