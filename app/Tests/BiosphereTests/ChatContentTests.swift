import XCTest
import WebKit
import SwiftUI
@testable import Biosphere

final class ChatContentTests: XCTestCase {
    func testMarkdownBeforeAndAfterSVGStaysInOrder() throws {
        let source = try dnaSource()
        let blocks = ChatBlock.parse("**DNA has complementary bases.**\n\n```svg\n\(source)\n```\n\n> **Exam tip:** A pairs with T.\n\n### Quick check\nWhich base pairs with C?")
        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(blocks[0], .paragraph("**DNA has complementary bases.**"))
        guard case .diagram(let diagram) = blocks[1] else { return XCTFail("SVG should be a drawing, not text") }
        XCTAssertEqual(diagram.title, "DNA base pairing")
        XCTAssertEqual(diagram.aspectRatio, 320.0 / 420.0, accuracy: 0.001)
        XCTAssertEqual(blocks[2], .callout("**Exam tip:** A pairs with T."))
        XCTAssertEqual(blocks[3], .heading("Quick check"))
        XCTAssertEqual(blocks[4], .paragraph("Which base pairs with C?"))
    }

    func testIncompleteSVGWaitsWhileStreamingAndDoesNotExposeSource() {
        let text = "Here is the diagram.\n```svg\n<svg viewBox=\"0 0 320 360\">\n<text>DNA"
        XCTAssertEqual(ChatBlock.parse(text, isStreaming: true), [.paragraph("Here is the diagram."), .pendingDiagram])
        XCTAssertEqual(ChatBlock.parse(text), [.paragraph("Here is the diagram."), .unavailableDiagram])
    }

    func testCodeFencesDoNotBecomeHeadingsOrBullets() {
        XCTAssertEqual(ChatBlock.parse("```text\n# Not a heading\n- Not a bullet\n```"), [.code("# Not a heading\n- Not a bullet")])
        XCTAssertEqual(ChatBlock.parse("1. First\n- Next\n> A note\n> More"), [.bullet("1.", "First"), .bullet("•", "Next"), .callout("A note\nMore")])
    }

    func testSVGRejectsActiveContentAndExternalResources() {
        let dangerous = [
            "<script>alert(1)</script>", "<foreignObject><div>HTML</div></foreignObject>",
            "<image href=\"https://example.com/tracker\"/>", "<a href=\"file:///etc/passwd\"><text>Open</text></a>",
            "<path d=\"M0 0\" onclick=\"alert(1)\"/>", "<rect fill=\"url(https://example.com/a)\"/>",
            "<style>text{fill:red}</style>", "<animate attributeName=\"x\"/>", "<text style=\"background:url(file:///etc/passwd)\">DNA</text>"
        ]
        for content in dangerous {
            XCTAssertNil(SVGDiagram("<svg viewBox=\"0 0 320 360\">\(content)</svg>"), content)
        }
        XCTAssertNil(SVGDiagram("<!DOCTYPE svg [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><svg viewBox=\"0 0 320 360\"><text>&secret;</text></svg>"))
        XCTAssertNil(SVGDiagram("<svg viewBox=\"0 0 0 360\"/>"))
        XCTAssertNil(SVGDiagram("<svg viewBox=\"0 0 320 nan\"/>"))
        XCTAssertNil(SVGDiagram("<svg viewBox=\"0 0 320 360\"><text>unfinished"))
    }

    func testSVGPreservesLabelsAndInternalMarkersAndUsesHostDimensions() throws {
        let diagram = try XCTUnwrap(SVGDiagram(try dnaSource()))
        XCTAssertTrue(diagram.markup.contains("marker-end=\"url(#arrow)\""))
        XCTAssertTrue(diagram.markup.contains("5′"))
        XCTAssertTrue(diagram.html.contains("script-src 'none'"))
        let escaped = try XCTUnwrap(SVGDiagram("<svg width=\"1000\" height=\"1000\" viewBox=\"0 0 320 360\"><title>A &amp; T</title><text>&lt;script&gt;</text></svg>"))
        XCTAssertEqual(escaped.title, "A & T")
        XCTAssertTrue(escaped.markup.contains("&lt;script&gt;"))
        XCTAssertFalse(escaped.markup.contains("width=\"1000\""))
        XCTAssertFalse(escaped.markup.contains("height=\"1000\""))
    }

    @MainActor
    func testDiagramWebViewDisablesScriptsAndPersistentStorage() async {
        let configuration = DiagramWebView.configuration()
        XCTAssertFalse(configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
    }

    @MainActor
    func testDNADiagramRendersAtNarrowAndEnlargedWidths() async throws {
        _ = NSApplication.shared
        let diagram = try XCTUnwrap(SVGDiagram(try dnaSource()))
        for width in [200.0, 276.0, 700.0] {
            let rect = CGRect(x: 0, y: 0, width: width, height: width / diagram.aspectRatio)
            let view = WKWebView(frame: rect, configuration: DiagramWebView.configuration())
            let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.setFrameOrigin(NSPoint(x: -10_000, y: 0))
            window.contentView = view
            window.orderBack(nil)
            defer { window.close() }
            let loaded = expectation(description: "SVG loaded at \(width) points")
            let probe = DiagramNavigationProbe(coordinator: DiagramWebView.Coordinator(), loaded: loaded)
            view.navigationDelegate = probe
            view.loadHTMLString(diagram.html, baseURL: nil)
            await fulfillment(of: [loaded], timeout: 20)
            let snapshot = WKSnapshotConfiguration()
            snapshot.rect = rect
            snapshot.afterScreenUpdates = true
            let image: NSImage = try await withCheckedThrowingContinuation { continuation in
                view.takeSnapshot(with: snapshot) { image, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let image { continuation.resume(returning: image) }
                    else { continuation.resume(throwing: NSError(domain: "BiosphereTests", code: 1)) }
                }
            }
            let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            var nonWhite = 0
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
                    if let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                       min(colour.redComponent, colour.greenComponent, colour.blueComponent) < 0.8 { nonWhite += 1 }
                }
            }
            XCTAssertGreaterThan(nonWhite, 100, "The diagram must render visibly, not as a blank web view")
            if let output = ProcessInfo.processInfo.environment["BIOSPHERE_DIAGRAM_PREVIEW_DIRECTORY"] {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("dna-\(Int(width)).png"))
            }
        }
    }

    @MainActor
    func testInlineDiagramFitsTheActualChatBubble() async throws {
        _ = NSApplication.shared
        let diagram = try XCTUnwrap(SVGDiagram(try dnaSource()))
        let message = ChatMessage(role: .tutor, text: "**DNA has complementary base pairs.**\n```svg\n\(diagram.markup)\n```\nA pairs with T; C pairs with G.")
        let host = NSHostingView(rootView: Bubble(message: message, typing: false).frame(width: 300, alignment: .leading))
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: 0, width: 300, height: 700),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        var webView: WKWebView?
        for _ in 0..<60 {
            host.layoutSubtreeIfNeeded()
            webView = findWebView(in: host)
            if let webView, webView.estimatedProgress == 1, webView.bounds.width > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let drawing = try XCTUnwrap(webView)
        XCTAssertGreaterThan(drawing.bounds.width, 150)
        XCTAssertLessThan(drawing.bounds.width, 250)
        XCTAssertEqual(drawing.bounds.height, drawing.bounds.width / diagram.aspectRatio, accuracy: 2,
                       "The native chat must allocate the drawing's full height")
    }

    @MainActor
    private func findWebView(in view: NSView) -> WKWebView? {
        if let view = view as? WKWebView { return view }
        return view.subviews.lazy.compactMap { self.findWebView(in: $0) }.first
    }

    private func dnaSource() throws -> String {
        try String(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "dna", withExtension: "svg")), encoding: .utf8)
    }
}

@MainActor
private final class DiagramNavigationProbe: NSObject, WKNavigationDelegate {
    let coordinator: DiagramWebView.Coordinator
    let loaded: XCTestExpectation
    init(coordinator: DiagramWebView.Coordinator, loaded: XCTestExpectation) {
        self.coordinator = coordinator
        self.loaded = loaded
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        coordinator.webView(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
}
