import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) var model
    @State private var showSetup = false

    static let models: [(id: String, name: String, blurb: String, icon: String)] = [
        ("sonnet", "Sonnet", "Fast and smart. Best for everyday marking and chat.", "hare.fill"),
        ("opus", "Opus", "More careful marking and deeper explanations. Slower.", "graduationcap.fill"),
        ("fable", "Fable", "The most capable. Uses your plan limits fastest.", "sparkles"),
        ("haiku", "Haiku", "Quickest replies. Fine for quick questions.", "bolt.fill"),
    ]
    static let readers: [(id: String, name: String, blurb: String, icon: String)] = [
        ("haiku", "Haiku", "Reads your answers for a tiny slice of your plan. Recommended.", "bolt.fill"),
        ("sonnet", "Sonnet", "Slower, more careful with very messy handwriting.", "hare.fill"),
    ]
    static let efforts: [(id: String, name: String, blurb: String)] = [
        ("low", "Low", "Fastest replies, least thinking."),
        ("medium", "Medium", "A good balance. Recommended."),
        ("high", "High", "Thinks harder. Best for careful marking."),
        ("xhigh", "Extra high", "Very thorough; noticeably slower."),
        ("max", "Max", "Maximum thinking; slowest and uses the most of your plan."),
    ]

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)

                SettingsSection(icon: "bubble.left.and.text.bubble.right.fill", color: Palette.purple, title: "Hank",
                                subtitle: "Your tutor runs on your own Claude account.") {
                    account
                    Divider().overlay(Palette.stroke)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                            ForEach(Self.models, id: \.id) { m in
                                choiceCard(selected: model.settings.markingModel == m.id, icon: m.icon, title: m.name, blurb: m.blurb) {
                                    model.settings.markingModel = m.id
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Effort").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                            Spacer()
                            Text(Self.efforts.first { $0.id == model.settings.effort }?.blurb ?? "")
                                .font(.system(size: 11.5)).foregroundStyle(Palette.dim)
                        }
                        HStack(spacing: 0) {
                            ForEach(Array(Self.efforts.enumerated()), id: \.offset) { i, e in
                                let on = model.settings.effort == e.id
                                Button { model.settings.effort = e.id } label: {
                                    VStack(spacing: 4) {
                                        HStack(spacing: 2) {
                                            ForEach(0..<(i + 1), id: \.self) { _ in
                                                Capsule().fill(on ? Color.white : Palette.violet.opacity(0.6)).frame(width: 3, height: 10)
                                            }
                                        }
                                        Text(e.name).font(.system(size: 11.5, weight: .semibold))
                                    }
                                    .foregroundStyle(on ? .white : Palette.lilac)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(on ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 10))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(3)
                        .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 12))
                        Text("Applies to chat, marking and planning. Higher effort is more thorough but slower and uses more of your plan.")
                            .font(.system(size: 11)).foregroundStyle(Palette.faint)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reading your handwriting").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                        HStack(spacing: 10) {
                            ForEach(Self.readers, id: \.id) { r in
                                choiceCard(selected: model.settings.readerModel == r.id, icon: r.icon, title: r.name, blurb: r.blurb) {
                                    model.settings.readerModel = r.id
                                }
                            }
                        }
                        Text("A small model types up what you wrote, then Hank marks it with the model above. Hank only looks at your page himself for drawings or writing the reader couldn't make out.")
                            .font(.system(size: 11)).foregroundStyle(Palette.faint).fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsSection(icon: "ipad.and.arrow.forward", color: Color(red: 0.25, green: 0.55, blue: 0.95), title: "iPad",
                                subtitle: model.settings.sendMethod == .airdrop
                                    ? (model.settings.ipadName.isEmpty ? "Not set up yet: you'll pick your iPad in AirDrop each time." : "Send to iPad goes straight to \(model.settings.ipadName).")
                                    : "Papers go through iCloud Drive.") {
                    IPadSetup(compact: true)
                }

                SettingsSection(icon: "lock.shield.fill", color: Palette.green, title: "Permissions",
                                subtitle: "What Biosphere is allowed to do on this Mac.") {
                    PermissionsList(compact: true)
                    Toggle(isOn: $model.settings.watchDownloads) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Watch Downloads for returned papers").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                            Text("Only while a paper is out being answered.").font(.system(size: 11)).foregroundStyle(Palette.faint)
                        }
                    }.toggleStyle(.switch).tint(Palette.purple)
                }

                SettingsSection(icon: "timer", color: Palette.orange, title: "Timing",
                                subtitle: "How long questions should take. Used to fit papers to your time.") {
                    stepperRow("Multiple choice", value: $model.settings.minutesPerMCQ, unit: "min per question", range: 0.5...3, step: 0.25)
                    stepperRow("Written questions", value: $model.settings.minutesPerMark, unit: "min per mark", range: 0.5...3, step: 0.25)
                    Text("IB timing is about 1.5 min per multiple-choice question and 1.25 min per mark.")
                        .font(.system(size: 11)).foregroundStyle(Palette.faint)
                }

                SettingsSection(icon: "arrow.triangle.2.circlepath", color: Color(red: 0.55, green: 0.36, blue: 0.96), title: "Updates",
                                subtitle: "You're on version \(Updater.currentVersion). Biosphere checks for updates by itself.") {
                    HStack(spacing: 10) {
                        if let a = model.updater.available {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Version \(a.version)\(a.beta ? " (beta)" : "") is ready").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.text)
                                if !a.notes.isEmpty {
                                    Text(a.notes).font(.system(size: 11.5)).foregroundStyle(Palette.dim).lineLimit(3)
                                }
                            }
                            Spacer()
                            Button { Task { await model.updater.install() } } label: {
                                if model.updater.installing { HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Installing…") } }
                                else { Label("Install & restart", systemImage: "arrow.down.app") }
                            }
                            .buttonStyle(PrimaryButtonStyle(compact: true))
                            .disabled(model.updater.installing)
                        } else {
                            Text(model.updater.message ?? (model.updater.lastChecked.map { "Last checked \($0.formatted(.relative(presentation: .named)))." } ?? "Not checked yet."))
                                .font(.system(size: 12.5)).foregroundStyle(Palette.dim)
                            Spacer()
                            Button {
                                Task { await model.updater.check(beta: model.settings.betaUpdates, quiet: false) }
                            } label: {
                                if model.updater.checking { HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…") } }
                                else { Label("Check now", systemImage: "arrow.clockwise") }
                            }
                            .buttonStyle(GhostButtonStyle(compact: true))
                        }
                    }
                    if model.updater.installing, let p = model.updater.progress {
                        ProgressView(value: p).tint(Palette.purple)
                    }
                    Toggle(isOn: $model.settings.betaUpdates) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Beta updates").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                            Text("Get test versions before everyone else. Leave off unless you're testing.").font(.system(size: 11)).foregroundStyle(Palette.faint)
                        }
                    }
                    .toggleStyle(.switch).tint(Palette.purple)
                    .onChange(of: model.settings.betaUpdates) {
                        model.settings.save()
                        Task { await model.updater.check(beta: model.settings.betaUpdates) }
                    }
                }

                SettingsSection(icon: "folder.fill", color: Palette.dim, title: "Files & setup",
                                subtitle: "Everything lives in ~/Biosphere: your papers, marks and progress.") {
                    HStack(spacing: 10) {
                        Button { NSWorkspace.shared.open(Workspace.root) } label: { Label("Open in Finder", systemImage: "folder") }
                            .buttonStyle(GhostButtonStyle(compact: true))
                        Button { showSetup = true } label: { Label("Run setup again", systemImage: "wand.and.stars") }
                            .buttonStyle(GhostButtonStyle(compact: true))
                        Spacer()
                        Text("\(model.bank?.questions.count ?? 0) questions · \(model.bank?.questions.filter(\.inSyllabus).count ?? 0) on the current syllabus")
                            .font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                    }
                }
            }
            .padding(.horizontal, 32).padding(.top, 56).padding(.bottom, 40)
            .frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showSetup) { OnboardingView(isPresented: $showSetup).environment(model) }
        .onChange(of: model.settings.markingModel) { model.settings.save() }
        .onChange(of: model.settings.effort) { model.settings.save() }
        .onChange(of: model.settings.readerModel) { model.settings.save() }
        .onChange(of: model.settings.watchDownloads) { model.settings.save() }
        .onChange(of: model.settings.minutesPerMCQ) { model.settings.save() }
        .onChange(of: model.settings.minutesPerMark) { model.settings.save() }
        .task { await model.permissions.refresh() }
    }

    var account: some View {
        HStack(spacing: 12) {
            HankAvatar(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                if !model.claude.installed {
                    Text("Claude Code isn't installed").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.text)
                } else if model.claude.loggedIn {
                    Text("Signed in").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.text)
                    if let e = model.claude.email { Text(e).font(.system(size: 12)).foregroundStyle(Palette.dim) }
                } else {
                    Text("Not signed in").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.text)
                }
            }
            Spacer()
            if model.claude.loggedIn {
                UsageRing(size: 34, showLabel: true)
            } else {
                Button(model.claude.installed ? "Sign in" : "Set up") { model.openHank() }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
    }

    func choiceCard(selected: Bool, icon: String, title: String, blurb: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon).foregroundStyle(selected ? .white : Palette.purple)
                    Text(title).font(.system(size: 13.5, weight: .bold)).foregroundStyle(selected ? .white : Palette.text)
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white) }
                }
                Text(blurb).font(.system(size: 11.5)).foregroundStyle(selected ? .white.opacity(0.9) : Palette.dim)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
            .background(selected ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Palette.bg2), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? .clear : Palette.stroke))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    func stepperRow(_ title: String, value: Binding<Double>, unit: String, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
            Spacer()
            Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(0...2)))) \(unit)").font(.system(size: 12.5, design: .rounded)).foregroundStyle(Palette.dim)
            Stepper("", value: value, in: range, step: step).labelsHidden()
        }
    }
}

struct SettingsSection<Content: View>: View {
    var icon: String
    var color: Color
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34).background(color.gradient, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.dim)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.stroke))
        .shadow(color: Palette.purple.opacity(0.05), radius: 10, y: 3)
    }
}
