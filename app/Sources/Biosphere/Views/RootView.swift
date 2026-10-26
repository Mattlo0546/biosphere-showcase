import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) var model
    @State private var showOnboarding = false
    @AppStorage("width.sidebar") private var sidebarWidth: Double = 220
    @AppStorage("width.chat") private var chatWidth: Double = 390

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            Sidebar(selection: $model.selection, compact: sidebarWidth < 120)
                .frame(width: sidebarWidth)
            // Drag below ~130pt and the sidebar tucks into icons only.
            ResizeHandle(width: $sidebarWidth, growsRight: true, defaultWidth: 220) { raw in
                raw < 130 ? 68 : PanelWidth.clamp(raw, 170, 340)
            }
            ZStack(alignment: .top) {
                Palette.bg.ignoresSafeArea()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                TopBar()
            }
            .frame(minWidth: 420)
            if model.chat.isOpen {
                ResizeHandle(width: $chatWidth, growsRight: false, defaultWidth: 390) { raw in
                    PanelWidth.clamp(raw, 300, 720)
                }
                HankPanel(width: chatWidth).transition(.move(edge: .trailing))
            }
        }
        .background(Palette.bg)
        .overlay(alignment: .top) {
            // Double-click to fill the screen / drag to move, like a normal title bar.
            TitleBarArea().frame(height: 28).frame(maxWidth: .infinity)
        }
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                HStack(spacing: 10) {
                    HankAvatar(size: 26)
                    Text(t).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.white, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.stroke))
                .shadow(color: Palette.purple.opacity(0.18), radius: 16, y: 4)
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: model.toast)
        .animation(.snappy(duration: 0.25), value: model.chat.isOpen)
        .onAppear {
            if !model.settings.onboarded { showOnboarding = true }
            // The exam update opens straight onto the plan the first time.
            else if model.exam.pack != nil && !UserDefaults.standard.bool(forKey: "exam.opened") { model.selection = .exam }
        }
        .sheet(isPresented: $showOnboarding) { OnboardingView(isPresented: $showOnboarding).environment(model) }
        .sheet(item: $model.timeRequest) { scope in TimeSheet(scope: scope).environment(model) }
        .sheet(item: $model.businessPracticeRequest) { scope in BusinessTimeSheet(scope: scope).environment(model) }
        .sheet(item: $model.businessRequest) { set in BusinessSheet(set: set).environment(model) }
        .overlay {
            if model.planning {
                VStack(spacing: 12) {
                    HankAvatar(size: 54)
                    ProgressView().controlSize(.small)
                    Text("Hank is choosing your questions…").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("Looking at your tracker to find your best next questions.").font(.system(size: 12).italic()).foregroundStyle(Palette.dim)
                }
                .padding(28).background(.white, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: Palette.purple.opacity(0.2), radius: 30)
            }
        }
        .onChange(of: model.openSession) { _, id in if id != nil { model.selection = .sessions } }
    }

    @ViewBuilder var content: some View {
        if let err = model.loadError {
            Text(err).foregroundStyle(Palette.red).padding()
        } else {
            switch model.selection ?? .revise {
            case .exam: ExamPrepView()
            case .revise: ReviseView()
            case .sessions: SessionsView()
            case .tracker: TrackerView()
            case .settings: SettingsView()
            }
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) var model
    @Binding var selection: AppModel.SidebarItem?
    var compact = false

    var body: some View {
        if compact { compactBody } else { fullBody }
    }

    /// Icons only, when the sidebar has been dragged narrow.
    var compactBody: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Palette.gradient).frame(width: 34, height: 34)
                Image(systemName: "leaf.fill").foregroundStyle(.white).font(.system(size: 15, weight: .bold))
            }
            .padding(.top, 38).padding(.bottom, 18)
            if model.exam.pack != nil { icon(.exam, "Exam prep", "graduationcap.fill") }
            icon(.revise, "Topics", "square.grid.2x2.fill")
            icon(.sessions, "My sessions", "doc.richtext.fill")
            icon(.tracker, "Tracker", "chart.bar.xaxis")
            Button { model.chat.toggle() } label: {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 15)).foregroundStyle(model.chat.isOpen ? .white : Palette.dim)
                    .frame(width: 40, height: 36)
                    .background(model.chat.isOpen ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).help("Ask Hank (⌘E)")
            Spacer()
            icon(.settings, "Settings", "gearshape.fill")
            Button { model.openHank() } label: {
                ZStack(alignment: .bottomTrailing) {
                    HankAvatar(size: 34)
                    if model.claude.loggedIn { UsageRing(size: 18) .background(Circle().fill(.white)).offset(x: 6, y: 6) }
                }
            }.buttonStyle(.plain).padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bg2)
    }

    func icon(_ tag: AppModel.SidebarItem, _ title: String, _ name: String) -> some View {
        let on = selection == tag
        return Button { selection = tag } label: {
            Image(systemName: name).font(.system(size: 15)).foregroundStyle(on ? .white : Palette.dim)
                .frame(width: 40, height: 36)
                .background(on ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    var fullBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Palette.gradient).frame(width: 34, height: 34)
                    Image(systemName: "leaf.fill").foregroundStyle(.white).font(.system(size: 15, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Biosphere").font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    Text(model.bank?.syllabus.subject ?? "").font(.system(size: 11)).foregroundStyle(Palette.dim)
                }
            }
            .padding(.top, 38).padding(.bottom, 22).padding(.horizontal, 6)

            if model.exam.pack != nil {
                item(.exam, "Exam prep", "graduationcap.fill", badge: UserDefaults.standard.bool(forKey: "exam.opened") ? nil : "NEW")
            }
            item(.revise, "Topics", "square.grid.2x2.fill")
            item(.sessions, "My sessions", "doc.richtext.fill", badge: model.sessions.filter { $0.status == .marking }.isEmpty ? nil : "…")
            item(.tracker, "Tracker", "chart.bar.xaxis")
            Button { model.chat.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill").frame(width: 20)
                    Text("Ask Hank")
                    Spacer()
                    Text("⌘E").font(.system(size: 10.5, weight: .medium)).foregroundStyle(model.chat.isOpen ? .white.opacity(0.8) : Palette.faint)
                }
                .font(.system(size: 13.5, weight: model.chat.isOpen ? .semibold : .regular))
                .foregroundStyle(model.chat.isOpen ? .white : Palette.dim)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(model.chat.isOpen ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            if let a = model.updater.available {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.app.fill").foregroundStyle(Palette.purple)
                        Text("Update ready").font(.system(size: 12.5, weight: .bold)).foregroundStyle(Palette.text)
                        Spacer()
                        Text("v\(a.version)\(a.beta ? " β" : "")").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.dim)
                    }
                    if model.updater.installing {
                        ProgressView(value: model.updater.progress ?? 0).tint(Palette.purple)
                        Text(model.updater.message ?? "").font(.system(size: 10.5)).foregroundStyle(Palette.faint)
                    } else {
                        Button { Task { await model.updater.install() } } label: {
                            Text("Install & restart").frame(maxWidth: .infinity)
                        }.buttonStyle(PrimaryButtonStyle(compact: true))
                        if let m = model.updater.message { Text(m).font(.system(size: 10.5)).foregroundStyle(Palette.red) }
                    }
                }
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.violet.opacity(0.6)))
                .padding(.bottom, 6)
            }
            item(.settings, "Settings", "gearshape.fill")
            HStack(spacing: 8) {
                HankAvatar(size: 28, mood: model.chat.busy ? .thinking : .idle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hank").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(model.claude.loggedIn ? "Your tutor · online" : (model.checkedClaude ? "Not signed in" : "Checking…"))
                        .font(.system(size: 10)).foregroundStyle(model.claude.loggedIn ? Palette.green : Palette.orange)
                }
                Spacer(minLength: 0)
                if model.claude.loggedIn { UsageRing(size: 24) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.stroke))
            .contentShape(Rectangle())
            .onTapGesture { model.openHank() }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(Palette.bg2)
    }

    func item(_ tag: AppModel.SidebarItem, _ title: String, _ icon: String, badge: String? = nil) -> some View {
        let on = selection == tag
        return Button { selection = tag } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 20)
                Text(title)
                Spacer()
                if let badge { Text(badge).font(.system(size: 11, weight: .bold)) }
            }
            .font(.system(size: 13.5, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? .white : Palette.dim)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(on ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Timer chip + screenshot button, always visible top-right.
struct TopBar: View {
    @Environment(AppModel.self) var model
    var body: some View {
        HStack(spacing: 10) {
            Spacer()
            if model.timer.isActive {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                    Text(StudyTimer.format(model.timer.remaining)).monospacedDigit().font(.system(size: 14, weight: .bold))
                    Button { model.timer.running ? model.timer.pause() : model.timer.resume() } label: {
                        Image(systemName: model.timer.running ? "pause.fill" : "play.fill")
                    }.buttonStyle(.plain)
                    Button { model.timer.stop() } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .foregroundStyle(model.timer.remaining < 0 ? Palette.red : (model.timer.remaining < 300 ? Palette.orange : Palette.text))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Palette.cardHi, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.stroke))
                .help(model.timer.title)
            }
            if !model.chat.isOpen {
                Button { model.openHank() } label: {
                    HStack(spacing: 6) { HankAvatar(size: 18); Text("Ask Hank") }
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .help("Chat with your tutor (⌘E)")
            }
            Button { model.screenshot() } label: {
                Label("Screenshot → iPad", systemImage: "camera.viewfinder")
            }
            .buttonStyle(GhostButtonStyle(compact: true))
            .help("Drag over anything on screen and it goes straight to your iPad (⇧⌘S)")
        }
        .padding(.top, 32).padding(.trailing, 18)
    }
}
