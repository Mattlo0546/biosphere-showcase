import Foundation

/// Read-only access to the private GitHub repo's releases (app updates + the past-paper pack).
/// The token is a fine-grained, read-only key baked into the build (never in git).
enum GitHub {
    static let repo = "Mattlo0546/biosphere"

    struct Asset: Decodable { var id: Int; var name: String; var size: Int }
    struct Release: Decodable {
        var tagName: String
        var name: String?
        var body: String?
        var prerelease: Bool
        var draft: Bool
        var publishedAt: Date?
        var assets: [Asset]
    }

    enum Failure: LocalizedError {
        case noToken, http(Int), notFound(String)
        var errorDescription: String? {
            switch self {
            case .noToken: "This copy of Biosphere can't check for updates (no update key was built in)."
            case .http(401), .http(403): "The update key was refused. It may have expired; ask for a new build."
            case .http(let c): "GitHub returned an error (\(c))."
            case .notFound(let s): "Couldn't find \(s) on GitHub."
            }
        }
    }

    /// The update key, lightly obfuscated in the bundle so it isn't sitting there in plain text.
    static let token: String? = {
        // Developer testing only: a key passed in the environment (never set on her Mac).
        if let env = ProcessInfo.processInfo.environment["BIOSPHERE_UPDATE_TOKEN"], !env.isEmpty { return env }
        guard let url = Bundle.main.url(forResource: "update", withExtension: "key"),
              let b64 = try? String(contentsOf: url, encoding: .utf8),
              let data = Data(base64Encoded: b64.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let key = Array("biosphere-updates".utf8)
        let plain = data.enumerated().map { $0.element ^ key[$0.offset % key.count] }
        let s = String(decoding: plain, as: UTF8.self)
        return s.isEmpty ? nil : s
    }()

    static var hasToken: Bool { token != nil }

    static func request(_ path: String, accept: String = "application/vnd.github+json") throws -> URLRequest {
        guard let token else { throw Failure.noToken }
        var r = URLRequest(url: URL(string: "https://api.github.com\(path)")!)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue(accept, forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("Biosphere", forHTTPHeaderField: "User-Agent")
        r.timeoutInterval = 30
        return r
    }

    static func releases() async throws -> [Release] {
        let (data, resp) = try await URLSession.shared.data(for: try request("/repos/\(repo)/releases?per_page=50"))
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw Failure.http(h.statusCode) }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return try d.decode([Release].self, from: data)
    }

    static func release(tag: String) async throws -> Release {
        let (data, resp) = try await URLSession.shared.data(for: try request("/repos/\(repo)/releases/tags/\(tag)"))
        if let h = resp as? HTTPURLResponse, h.statusCode == 404 { throw Failure.notFound(tag) }
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw Failure.http(h.statusCode) }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return try d.decode(Release.self, from: data)
    }

    /// Downloads a release asset to a temporary file, reporting progress 0…1.
    static func download(_ asset: Asset, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let req = try request("/repos/\(repo)/releases/assets/\(asset.id)", accept: "application/octet-stream")
        let delegate = DownloadDelegate(expected: asset.size, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (tmp, resp) = try await session.download(for: req)
        if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw Failure.http(h.statusCode) }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(asset.name)")
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// GitHub redirects asset downloads to its file storage, which must NOT receive our token.
    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate, @unchecked Sendable {
        let expected: Int
        let progress: @Sendable (Double) -> Void
        init(expected: Int, progress: @escaping @Sendable (Double) -> Void) { self.expected = expected; self.progress = progress }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            var r = request
            if r.url?.host != "api.github.com" { r.setValue(nil, forHTTPHeaderField: "Authorization") }
            completionHandler(r)
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let total = totalBytesExpectedToWrite > 0 ? Double(totalBytesExpectedToWrite) : Double(max(expected, 1))
            progress(min(1, Double(totalBytesWritten) / total))
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }

    /// "v0.7.1" → [0, 7, 1]
    static func version(_ s: String) -> [Int] {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
    static func isNewer(_ a: [Int], than b: [Int]) -> Bool {
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func unzip(_ zip: URL, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { throw CocoaError(.fileReadCorruptFile) }
    }
}
