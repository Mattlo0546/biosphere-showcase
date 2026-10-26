import SwiftUI

/// Hank as a chat panel docked on the right of the window, available from every screen.
struct HankPanel: View {
    @Environment(AppModel.self) var model
    @AppStorage("subject") private var subject = "biology"
    var width: Double = 390
    @State private var draft = ""
    @FocusState private var focused: Bool
    // Hank's expression: a transient reaction (surprised / happy / blush) wins over the steady state.
    @State private var reaction: HankMood?
    @State private var reactionToken = UUID()
    @State private var typing = false
    @State private var typingToken = UUID()
    @State private var pokes = 0

    var body: some View {
        let chat = model.chat
        VStack(spacing: 0) {
            header
            Divider().overlay(Palette.stroke)
            if !model.claude.installed || !model.claude.loggedIn {
                ClaudeSetupCard().padding(16)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if chat.messages.isEmpty { welcome }
                            ForEach(chat.messages) { m in
                                Bubble(message: m, typing: chat.busy && m.id == chat.messages.last?.id)
                                    .id(m.id)
                            }
                            if let a = chat.activity, chat.busy {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini)
                                    Text(a).font(.system(size: 11)).foregroundStyle(Palette.faint)
                                }
                                .padding(.leading, 38).id("activity")
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: chat.messages.last?.text) { _, _ in
                        if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                    .onChange(of: chat.messages.count) { _, _ in
                        withAnimation { if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                    }
                }
                if let suggestion = chat.questionSuggestion {
                    Button { send(suggestion.prompt, context: suggestion.context) } label: {
                        Label(suggestion.title, systemImage: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(GhostButtonStyle(compact: true))
                    .disabled(chat.busy)
                    .padding(.horizontal, 12).padding(.bottom, 8)
                }
                composer
            }
        }
        .frame(width: width)
        .background(Palette.bg2)
        .onAppear { focused = true }
        .onChange(of: model.chat.busy) { was, now in
            if was && !now && model.chat.messages.last?.failed != true { react(.happy, for: 2.4) }
        }
        .onChange(of: draft) { _, v in
            guard !v.isEmpty else { typing = false; return }
            typing = true
            let t = UUID(); typingToken = t
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { if typingToken == t { typing = false } }
        }
    }

    // MARK: Hank's mood

    var mood: HankMood {
        if let reaction { return reaction }
        if model.chat.busy {
            return (model.chat.messages.last?.text.isEmpty ?? true) ? .thinking : .talking
        }
        if typing && focused { return .listening }
        return .idle
    }

    /// While she types, his eyes follow the caret across the line (−1 left … 1 right).
    var gaze: CGFloat? {
        guard mood == .listening else { return nil }
        let charsPerLine = max(20, Int((width - 90) / 7.2))
        let lastLine = draft.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? draft
        let col = lastLine.count % charsPerLine
        return CGFloat(col) / CGFloat(charsPerLine) * 1.8 - 0.9
    }

    var moodLine: String {
        switch mood {
        case .idle: subject == "maths" ? "your Maths tutor" : "your \(CaseSubject.allCases.first { $0.pageKey == subject }?.shortName ?? "Biology") tutor"
        case .listening: "listening…"
        case .surprised: "ooh, a question!"
        case .thinking: model.chat.activity.map { $0.lowercased() } ?? "thinking…"
        case .talking: "explaining…"
        case .happy: "there you go!"
        case .blush: ["hey, that tickles!", "stop it, I'm blushing", "ok ok, I'm awake!", "careful, these glasses aren't cheap"][pokes % 4]
        }
    }

    func react(_ m: HankMood, for seconds: Double) {
        let t = UUID(); reactionToken = t
        withAnimation(.spring(duration: 0.35)) { reaction = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if reactionToken == t { withAnimation(.spring(duration: 0.4)) { reaction = nil } }
        }
    }

    func poke() {
        pokes += 1
        react(.blush, for: 1.8)
    }

    /// Hank, live: animated with the current mood, and pokeable.
    func liveHank(_ size: CGFloat) -> some View {
        HankAvatar(size: size, mood: mood, gaze: gaze)
            .contentShape(Circle())
            .onTapGesture { poke() }
            .help("Poke Hank")
    }

    var header: some View {
        HStack(spacing: 10) {
            liveHank(52).padding(4)
            VStack(alignment: .leading, spacing: 1) {
                Text("Hank").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                Text(moodLine).font(.system(size: 11)).foregroundStyle(mood == .blush ? Palette.red.opacity(0.8) : Palette.faint)
                    .lineLimit(1).contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: moodLine)
            }
            Spacer()
            UsageRing(size: 26).help("How much of your Claude plan Hank has used")
            if model.chat.canResumePreviousChat {
                Button { model.chat.resumePreviousChat(); draft = ""; focused = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .buttonStyle(.plain).foregroundStyle(Palette.dim).help("Resume previous chat")
                    .disabled(model.chat.busy)
            }
            Button { model.chat.newChat(); draft = ""; focused = true } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.plain).foregroundStyle(Palette.dim).help("New chat")
                .disabled(model.chat.busy)
            Button { model.chat.isOpen = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Palette.dim).help("Close (⌘E)")
        }
        .padding(.horizontal, 16).padding(.top, 40).padding(.bottom, 12)
    }

    var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    liveHank(92).padding(10)
                    Text("psst, you can poke me").font(.system(size: 10.5)).foregroundStyle(Palette.faint)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            Bubble(message: ChatMessage(role: .tutor, text: "Hey! What would you like to ask? Start with any biology question — I can explain concepts, draw labelled diagrams, or help with your paper."), typing: false)
            if model.chat.canResumePreviousChat {
                Button("Resume previous chat") { model.chat.resumePreviousChat(); focused = true }
                    .buttonStyle(GhostButtonStyle(compact: true)).padding(.leading, 38)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(suggestions, id: \.self) { s in
                    Button { send(s) } label: {
                        Text(s).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.lilac)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.stroke))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.leading, 38)
        }
    }

    var suggestions: [String] {
        var s = ["Show me a labelled DNA diagram", "What should I revise next?",
                 "Make me a 30-minute paper on my weakest topic"]
        if let id = model.openSession, model.session(id)?.status == .marked { s.insert("Go through this paper with me", at: 0) }
        s.append("Teach me membrane transport like a story")
        return s
    }

    var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask Hank…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit { send(draft) }
                .onChange(of: draft) { _, v in if v.hasSuffix("\n") && !v.hasSuffix("\n\n") { send(v) } }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(focused ? Palette.violet : Palette.stroke, lineWidth: focused ? 1.5 : 1))
            if model.chat.busy {
                Button { model.chat.stop() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Palette.dim, in: Circle())
                }.buttonStyle(.plain).help("Stop")
            } else {
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Palette.gradient, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
        }
        .padding(12)
        .background(Palette.bg2)
    }

    func send(_ text: String, context: String? = nil) {
        guard !model.chat.busy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        typing = false
        react(.surprised, for: 0.9)
        model.askHank(text, context: context)
        draft = ""
    }
}

struct Bubble: View {
    var message: ChatMessage
    var typing: Bool

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 13.5)).foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(Palette.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                HankAvatar(size: 28, animated: false)
                Group {
                    if message.text.isEmpty && typing {
                        TypingDots()
                    } else {
                        RichText(text: message.text, isStreaming: typing)
                    }
                }
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(message.failed ? Palette.red.opacity(0.5) : Palette.stroke))
                Spacer(minLength: 20)
            }
        }
    }
}

/// Light markdown: paragraphs, "- " / "1. " lists, headings as bold, inline **bold** / *italic* / `code` / links.
struct RichText: View {
    var text: String
    var isStreaming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b {
                case .paragraph(let s):
                    inline(s)
                case .bullet(let marker, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.purple)
                        inline(s)
                    }
                case .heading(let s):
                    Text(s.uppercased()).font(.system(size: 10.5, weight: .heavy)).tracking(0.6).foregroundStyle(Palette.purple)
                        .padding(.top, 4)
                case .callout(let s):
                    HStack(alignment: .top, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(Palette.purple).frame(width: 3)
                        inline(s)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                case .diagram(let diagram):
                    ChatDiagramView(diagram: diagram)
                case .pendingDiagram:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Drawing the diagram…").font(.system(size: 12)).foregroundStyle(Palette.dim)
                    }.padding(.vertical, 8)
                case .unavailableDiagram:
                    Text("The diagram couldn't be displayed. Ask Hank to redraw it.")
                        .font(.system(size: 12)).foregroundStyle(Palette.dim)
                case .code(let source):
                    Text(source).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
    }

    var blocks: [ChatBlock] { ChatBlock.parse(text, isStreaming: isStreaming) }

    func inline(_ raw: String) -> Text {
        // Bare URLs become short links: "biologyforlife.com/cellspecialization" → [Biology for Life ↗](…)
        let url = "(https?://[^\\s)]*[^\\s).,;:!?])"
        let s = raw
            .replacingOccurrences(of: "(?<![(<\\[])" + url.replacingOccurrences(of: "https?://", with: "https?://(?:www\\.)?biologyforlife\\.com"),
                                  with: "[Biology for Life ↗]($1)", options: .regularExpression)
            .replacingOccurrences(of: "(?<![(<\\[])" + url, with: "[open link ↗]($1)", options: .regularExpression)
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let a = (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
        return Text(a).font(.system(size: 13.5)).foregroundColor(Palette.text)
    }
}

struct TypingDots: View {
    @State private var phase = 0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(Palette.violet).frame(width: 6, height: 6).opacity(phase == i ? 1 : 0.3)
            }
        }
        .padding(.vertical, 4)
        .onReceive(Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()) { _ in phase = (phase + 1) % 3 }
    }
}

/// Install / sign in to Claude Code from inside the app — no terminal.
private func signInStep(_ n: Int, _ text: LocalizedStringKey) -> some View {
    HStack(alignment: .top, spacing: 8) {
        Text("\(n)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            .frame(width: 18, height: 18).background(Palette.gradient, in: Circle())
        Text(text).font(.system(size: 12.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
    }
}

struct ClaudeSetupCard: View {
    @Environment(AppModel.self) var model
    @State private var setup = ClaudeSetup()
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HankAvatar(size: 36)
                Text(model.claude.installed ? "Sign in and we're ready to go. I run on your own Claude account."
                                            : "First, a quick install of Claude Code. Takes about a minute.")
                    .font(.system(size: 13)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
            }
            if setup.running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.claude.installed ? "Finish signing in in your browser…" : "Installing…")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.dim)
                }
                if let url = setup.url {
                    Button("Open the sign-in page") { NSWorkspace.shared.open(url) }.buttonStyle(GhostButtonStyle(compact: true))
                }
                if setup.needsInput {
                    VStack(alignment: .leading, spacing: 8) {
                        signInStep(1, "Sign in on the page that opened in your browser.")
                        signInStep(2, "Claude then shows a long code. Click **Copy Code**.")
                        signInStep(3, "Paste it here and press **Done**.")
                        HStack {
                            TextField("Paste the code here", text: $code).textFieldStyle(.roundedBorder)
                                .onSubmit { if !code.isEmpty { setup.submit(code); code = "" } }
                            Button("Done") { setup.submit(code); code = "" }
                                .buttonStyle(PrimaryButtonStyle(compact: true))
                                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(10)
                    .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 10))
                }
                Button("Cancel") { setup.cancel() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.faint)
            } else if model.claude.installed {
                Button { setup.login() } label: { Label("Sign in with Claude", systemImage: "person.crop.circle.badge.checkmark") }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button { setup.install() } label: { Label("Install Claude Code", systemImage: "arrow.down.circle") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            if !setup.output.isEmpty && !setup.running && !model.claude.loggedIn {
                Text(setup.output.suffix(400)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Palette.faint)
                    .lineLimit(6)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.stroke))
        .onChange(of: setup.done) { _, d in if d { Task { await model.refreshClaude() } } }
        .task {   // keep checking while this card is visible (e.g. she signs in in the browser)
            while !model.claude.loggedIn && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await model.refreshClaude()
            }
        }
    }
}
