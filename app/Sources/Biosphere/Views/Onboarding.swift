import SwiftUI

/// First-run setup: welcome → Claude → iPad → permissions → done. Re-runnable from Settings.
struct OnboardingView: View {
    @Environment(AppModel.self) var model
    @Binding var isPresented: Bool
    @State private var step = 0
    private let steps = ["Welcome", "Claude", "iPad", "Permissions", "Done"]

    var body: some View {
        VStack(spacing: 0) {
            progress.padding(.top, 22).padding(.bottom, 6)
            Group {
                switch step {
                case 0: welcome
                case 1: claudeStep
                case 2: IPadSetup(compact: false)
                case 3: PermissionsList(compact: false)
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(step)
            footer
        }
        .frame(width: 680, height: 600)
        .background(.white)
        .task { await model.permissions.refresh() }
    }

    var progress: some View {
        HStack(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 6) {
                    Circle().fill(i <= step ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Palette.empty)).frame(width: 9, height: 9)
                    Text(s).font(.system(size: 11.5, weight: i == step ? .bold : .medium))
                        .foregroundStyle(i == step ? Palette.text : Palette.faint)
                }
                if i < steps.count - 1 { Rectangle().fill(i < step ? Palette.violet : Palette.stroke).frame(width: 22, height: 1.5) }
            }
        }
    }

    var footer: some View {
        HStack {
            if step > 0 && step < steps.count - 1 {
                Button("Back") { withAnimation(.snappy) { step -= 1 } }.buttonStyle(GhostButtonStyle())
            }
            Spacer()
            if step == 1 && !model.claude.loggedIn {
                Button("Skip for now") { next() }.buttonStyle(.plain).foregroundStyle(Palette.dim).padding(.trailing, 8)
            }
            if step == 2 && model.settings.sendMethod == .airdrop && model.settings.ipadName.isEmpty {
                Button("Skip for now") { next() }.buttonStyle(.plain).foregroundStyle(Palette.dim).padding(.trailing, 8)
            }
            Button(step == 0 ? "Let's set up" : step == steps.count - 1 ? "Start revising" : "Continue") { next() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(step == 1 && !model.claude.loggedIn)
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
        .background(Palette.bg2)
    }

    func next() {
        if step == steps.count - 1 {
            model.settings.onboarded = true
            model.settings.save()
            isPresented = false
        } else {
            withAnimation(.snappy) { step += 1 }
        }
    }

    // MARK: steps

    var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            HankAvatar(size: 110, mood: .happy)
            Text("Hey, I'm Hank!").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
            Text("Your study tutor. Here's how Biosphere works:")
                .font(.system(size: 14)).foregroundStyle(Palette.dim)
            HStack(alignment: .top, spacing: 14) {
                howItWorks("square.grid.2x2.fill", "Pick a topic", "and how long you've got")
                howItWorks("ipad.and.arrow.forward", "Do it on your iPad", "real past-paper questions")
                howItWorks("checkmark.seal.fill", "I mark it", "and show you where the marks are")
            }
            .padding(.top, 6)
            Text("Setup takes about two minutes.").font(.system(size: 12)).foregroundStyle(Palette.faint)
            Spacer()
        }
    }

    func howItWorks(_ icon: String, _ title: String, _ sub: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 50, height: 50).background(Palette.gradient, in: RoundedRectangle(cornerRadius: 14))
            Text(title).font(.system(size: 13.5, weight: .bold)).foregroundStyle(Palette.text)
            Text(sub).font(.system(size: 11.5)).foregroundStyle(Palette.dim).multilineTextAlignment(.center)
        }
        .frame(width: 160)
    }

    var claudeStep: some View {
        VStack(spacing: 16) {
            Spacer()
            stepHeader("person.crop.circle.badge.checkmark", "Sign in to Claude",
                       "I run on your own Claude account, so marking and chat use your plan. You only do this once.")
            if model.claude.loggedIn {
                Label("Signed in\(model.claude.email.map { " as \($0)" } ?? "")", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.green)
                    .padding(14).frame(maxWidth: 420).background(Palette.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            } else {
                ClaudeSetupCard().frame(maxWidth: 460)
            }
            Spacer()
        }
    }

    var done: some View {
        VStack(spacing: 16) {
            Spacer()
            HankAvatar(size: 100, mood: .happy)
            Text("You're all set!").font(.system(size: 28, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
            VStack(alignment: .leading, spacing: 10) {
                tip("square.grid.2x2.fill", "Start on **Topics**: pick a subtopic, choose your time, and your paper's ready.")
                tip("ipad.and.arrow.forward", "**Send to iPad** goes straight to \(model.settings.ipadName.isEmpty ? "your iPad" : model.settings.ipadName).")
                tip("bubble.left.and.text.bubble.right.fill", "Stuck? **⌘E** opens me on any screen.")
                tip("camera.viewfinder", "**⇧⌘S** sends a screenshot of anything to your iPad.")
            }
            .frame(maxWidth: 440)
            Spacer()
        }
    }

    func tip(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Palette.purple).frame(width: 20)
            Text(text).font(.system(size: 13.5)).foregroundStyle(Palette.text)
        }
    }
}

func stepHeader(_ icon: String, _ title: String, _ sub: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: icon).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 58, height: 58).background(Palette.gradient, in: RoundedRectangle(cornerRadius: 16))
        Text(title).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
        Text(sub).font(.system(size: 13.5)).foregroundStyle(Palette.dim).multilineTextAlignment(.center).frame(maxWidth: 460)
    }
}

/// Choosing how papers get to the iPad, finding the iPad, and allowing auto-tap. Used in setup and Settings.
struct IPadSetup: View {
    @Environment(AppModel.self) var model
    var compact: Bool
    @State private var scanning = false
    @State private var found: [String] = []
    @State private var scanned = false
    @State private var testing = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: compact ? .leading : .center, spacing: 16) {
            if !compact {
                stepHeader("ipad.and.arrow.forward", "Your iPad",
                           "Tell me which iPad to send papers to, and \"Send to iPad\" will go straight there.")
            }
            HStack(spacing: 0) {
                ForEach([(AppSettings.SendMethod.airdrop, "AirDrop (recommended)", "dot.radiowaves.left.and.right"),
                         (AppSettings.SendMethod.icloud, "iCloud Drive", "icloud")], id: \.0) { method, label, icon in
                    let on = model.settings.sendMethod == method
                    Button { withAnimation(.snappy) { model.settings.sendMethod = method } } label: {
                        Label(label, systemImage: icon)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(on ? .white : Palette.lilac)
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background(on ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.clear), in: Capsule())
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Palette.bg2, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.stroke))
            .frame(maxWidth: 380)

            if model.settings.sendMethod == .icloud {
                Text("Papers are saved to **iCloud Drive › Biosphere › To do**. On the iPad, open the Files app. Save finished papers into **Biosphere › Done** and they come back to Hank automatically.")
                    .font(.system(size: 12.5)).foregroundStyle(Palette.dim).frame(maxWidth: 460, alignment: compact ? .leading : .center)
                    .multilineTextAlignment(compact ? .leading : .center)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    row(1, "Let Biosphere tap AirDrop for you",
                        done: model.permissions.accessibility == .granted,
                        detail: model.permissions.accessibility == .granted ? "Allowed ✓" : "macOS asks once. Turn on Biosphere under Privacy & Security › Accessibility.") {
                        if model.permissions.accessibility != .granted {
                            Button("Allow") { model.permissions.requestAccessibility() }.buttonStyle(PrimaryButtonStyle(compact: true))
                        }
                    }
                    row(2, "Choose your iPad", done: !model.settings.ipadName.isEmpty,
                        detail: "Unlock your iPad and keep it nearby, then scan. Or type its name (Settings › General › About › Name).") {
                        Button {
                            Task {
                                scanning = true
                                found = await AirDropAuto.discoverDevices()
                                scanned = true
                                scanning = false
                                if found.count == 1 { model.settings.ipadName = found[0]; model.settings.save() }
                            }
                        } label: {
                            if scanning { HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Looking…") } }
                            else { Label("Find my iPad", systemImage: "dot.radiowaves.left.and.right") }
                        }
                        .buttonStyle(GhostButtonStyle(compact: true))
                        .disabled(scanning || model.permissions.accessibility != .granted)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        if !found.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(found, id: \.self) { name in
                                    let on = AirDropAuto.matches(name, model.settings.ipadName) && !model.settings.ipadName.isEmpty
                                    Button { model.settings.ipadName = name; model.settings.save() } label: {
                                        Label(name, systemImage: on ? "checkmark.circle.fill" : "ipad")
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(on ? .white : Palette.lilac)
                                            .padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(on ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Palette.bg2), in: Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        } else if scanned {
                            Text("I couldn't see any devices. Check the iPad is unlocked, with Wi-Fi, Bluetooth and AirDrop on (Control Centre › AirDrop › Contacts Only or Everyone).")
                                .font(.system(size: 11.5)).foregroundStyle(Palette.orange).fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "ipad").foregroundStyle(Palette.faint)
                            TextField("iPad name, e.g. Emma's iPad", text: $model.settings.ipadName)
                                .textFieldStyle(.plain)
                                .onSubmit { model.settings.save() }
                        }
                        .padding(10)
                        .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.stroke))
                        .frame(maxWidth: 360)
                    }
                    .padding(.leading, 36)
                    row(3, "Send a test page", done: false, detail: "Checks everything works end to end.") {
                        Button {
                            Task { testing = true; await model.sendFile(WelcomePage.make()); testing = false }
                        } label: { Label("Send test", systemImage: "paperplane.fill") }
                            .buttonStyle(GhostButtonStyle(compact: true))
                            .disabled(testing)
                    }
                }
                .frame(maxWidth: 520)
            }
        }
        .onChange(of: model.settings.sendMethod) { model.settings.save() }
        .onChange(of: model.settings.ipadName) { model.settings.save() }
        .task {
            // Notice when she flips the Accessibility switch in System Settings.
            while !Task.isCancelled {
                await model.permissions.refresh()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func row<A: View>(_ n: Int, _ title: String, done: Bool, detail: String, @ViewBuilder action: () -> A) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? AnyShapeStyle(Palette.green) : AnyShapeStyle(Palette.gradient)).frame(width: 24, height: 24)
                if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white) }
                else { Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            action()
        }
    }
}

/// Notifications + Downloads (+ Accessibility in Settings), with live status.
struct PermissionsList: View {
    @Environment(AppModel.self) var model
    var compact: Bool

    var body: some View {
        VStack(alignment: compact ? .leading : .center, spacing: 16) {
            if !compact {
                stepHeader("lock.shield.fill", "A couple of permissions",
                           "So I can tell you when marking's done, and spot papers you AirDrop back.")
            }
            VStack(spacing: 10) {
                permission("bell.badge.fill", "Notifications", "\"Your paper's marked: 31/40\"", model.permissions.notifications) {
                    Task { await model.permissions.requestNotifications() }
                }
                permission("arrow.down.circle.fill", "Downloads folder", "Papers you AirDrop back land here. I only look for Biosphere papers.", model.permissions.downloads) {
                    Task { await model.permissions.requestDownloads() }
                }
                if compact {
                    permission("hand.tap.fill", "Accessibility", "Lets \"Send to iPad\" tap your iPad in AirDrop automatically.", model.permissions.accessibility) {
                        model.permissions.requestAccessibility()
                    }
                }
            }
            .frame(maxWidth: 520)
        }
        .task { await model.permissions.refresh() }
    }

    func permission(_ icon: String, _ title: String, _ detail: String, _ status: Permissions.Status, request: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.purple)
                .frame(width: 34, height: 34).background(Palette.cardHi, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.text)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            switch status {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.green)
            case .denied:
                Button("Open Settings") { request() }.buttonStyle(GhostButtonStyle(compact: true))
            case .unknown:
                Button("Allow") { request() }.buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.stroke))
    }
}
