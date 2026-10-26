import SwiftUI

@main
struct BiosphereApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // The main window is owned by AppDelegate so it always opens (SwiftUI's window restoration
        // sometimes skipped it after a force-quit). Scenes here are just the menu-bar timer + commands.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Show Biosphere") { delegate.showMainWindow() }
                        .keyboardShortcut("1", modifiers: [.command])
                }
                CommandGroup(after: .newItem) {
                    Button("Screenshot to iPad") { delegate.model.screenshot() }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                    Button("Ask Hank") { delegate.model.chat.toggle() }
                        .keyboardShortcut("e", modifiers: [.command])
                    Divider()
                    Button("Reload content (prompts, skills, questions)") { delegate.model.reloadContent() }
                        .keyboardShortcut("r", modifiers: [.command])
                }
            }

        MenuBarExtra(isInserted: .constant(delegate.model.timer.isActive)) {
            TimerMenu().environment(delegate.model)
        } label: {
            Text("⏱ " + StudyTimer.format(delegate.model.timer.remaining))
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model: AppModel = { AppModel.seedDevDataIfNeeded(); return AppModel() }()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        showMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Zooming (double-clicking the title bar) should fill the screen. Without this, SwiftUI's
    /// flexible content makes AppKit think the current size is already the "zoomed" size.
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        window.screen?.visibleFrame ?? newFrame
    }

    func showMainWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let root = RootView()
            .environment(model)
            .frame(minWidth: 1100, minHeight: 720)
            .preferredColorScheme(.light)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1380, height: 880),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = Workspace.isDevBuild ? "Biosphere Dev" : "Biosphere"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.backgroundColor = .white
        let host = NSHostingView(rootView: root)
        host.sizingOptions = [.minSize]      // only enforce the minimum; let zoom / full screen size the window freely
        w.contentView = host
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.setFrameAutosaveName("BiosphereMain")
        if !w.setFrameUsingName("BiosphereMain") { w.center() }
        // Make sure it lands on a screen that exists (e.g. after unplugging a monitor).
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(w.frame) }) { w.center() }
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

struct TimerMenu: View {
    @Environment(AppModel.self) var model
    var body: some View {
        Text(model.timer.title)
        Button(model.timer.running ? "Pause" : "Resume") { model.timer.running ? model.timer.pause() : model.timer.resume() }
        Button("+5 minutes") { model.timer.add(minutes: 5) }
        Button("Stop timer") { model.timer.stop() }
    }
}
