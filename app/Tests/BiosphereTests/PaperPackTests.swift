import XCTest
@testable import Biosphere

/// After an app update the pack is created before the new pack.json is copied in; it must not stay "ready"
/// on the old papers (that printed "Couldn't build the PDF … error 0" for the new May 2026 Maths questions).
@MainActor
final class PaperPackTests: XCTestCase {
    let slug = "maths-aa-sl"
    let bank = FileManager.default.temporaryDirectory.appendingPathComponent("pack-test-\(UUID().uuidString)")
    var dir: URL { bank.appendingPathComponent(slug) }
    override func tearDown() { try? FileManager.default.removeItem(at: bank) }

    func testAnUpdatedManifestWithMorePapersIsNotReady() throws {
        let papers = dir.appendingPathComponent("papers")
        try FileManager.default.createDirectory(at: papers, withIntermediateDirectories: true)
        for i in 0..<2 { try Data("%PDF".utf8).write(to: papers.appendingPathComponent("p\(i).pdf")) }
        try JSON.save(PaperPack.Manifest(tag: "old", asset: "a.zip", count: 2), to: dir.appendingPathComponent("pack.json"))
        let pack = PaperPack(slug: slug, bank: bank)
        XCTAssertTrue(pack.isReady)

        // Workspace.prepare() copies the new version's manifest in after the pack was made.
        try JSON.save(PaperPack.Manifest(tag: "new", asset: "a.zip", count: 3), to: dir.appendingPathComponent("pack.json"))
        pack.refresh()
        XCTAssertFalse(pack.isReady, "the new manifest needs a paper that isn't downloaded")
        XCTAssertEqual(pack.manifest?.tag, "new")
    }
}
