import SwiftUI
import WebKit

struct ChatDiagramView: View {
    var diagram: SVGDiagram
    @State private var enlarged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { enlarged = true } label: {
                DiagramWebView(diagram: diagram)
                    .aspectRatio(diagram.aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Enlarge \(diagram.title)")
            Button { enlarged = true } label: { Label("Enlarge diagram", systemImage: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(GhostButtonStyle(compact: true))
        }
        .sheet(isPresented: $enlarged) {
            VStack(spacing: 12) {
                HStack {
                    Text(diagram.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.text)
                    Spacer()
                    Button("Done") { enlarged = false }.buttonStyle(GhostButtonStyle(compact: true))
                        .keyboardShortcut(.cancelAction)
                }
                DiagramWebView(diagram: diagram).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(22).frame(width: 700, height: 600).background(.white)
        }
    }
}

/// SVG is rendered as a static drawing in an isolated web view with scripts and networking blocked.
struct DiagramWebView: NSViewRepresentable {
    var diagram: SVGDiagram

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: Self.configuration())
        view.navigationDelegate = context.coordinator
        return view
    }

    static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return configuration
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.markup != diagram.markup else { return }
        context.coordinator.markup = diagram.markup
        view.loadHTMLString(diagram.html, baseURL: nil)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WKWebView, context: Context) -> CGSize? {
        let width = proposal.width ?? 260
        return CGSize(width: width, height: proposal.height ?? width / diagram.aspectRatio)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var markup: String?
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
        }
    }
}
