import SwiftUI
import AppKit

/// The window's content runs under a transparent title bar, so the top strip has to hand double-clicks
/// and drags back to the window itself (zoom/fill, minimise or nothing — per System Settings › Desktop & Dock).
struct TitleBarArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitleBarNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TitleBarNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
                    ?? (UserDefaults.standard.bool(forKey: "AppleMiniaturizeOnDoubleClick") ? "Minimize" : "Maximize")
                switch action {
                case "Minimize": window.miniaturize(nil)
                case "None": break
                default: window.zoom(nil)        // "Maximize" / "Fill"
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}
