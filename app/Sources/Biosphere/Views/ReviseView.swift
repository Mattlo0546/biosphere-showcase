import SwiftUI

struct ReviseView: View {
    @Environment(AppModel.self) var model
    @State private var collapsed: Set<String> = []
    @AppStorage("subject") private var subject = "biology"

    var body: some View {
        if subject == "business" {
            BusinessView()
        } else if subject == "economics" {
            EconomicsView()
        } else if let bank = model.bank {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SubjectSwitch()
                    header(bank)
                    ForEach(bank.syllabus.themes) { theme in
                        ThemeCard(theme: theme, expanded: !collapsed.contains(theme.id)) {
                            if collapsed.contains(theme.id) { collapsed.remove(theme.id) } else { collapsed.insert(theme.id) }
                        }
                    }
                }
                .padding(.horizontal, 32).padding(.top, 56).padding(.bottom, 40)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                if model.mix != nil { MixBar().transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .animation(.snappy, value: model.mix != nil)
        }
    }

    func header(_ bank: Bank) -> some View {
        let subs = bank.syllabus.slSubtopics
        let stats = subs.map { model.progress.stats(for: $0.id).mastery }
        let green = stats.filter { $0 == .green }.count
        return VStack(alignment: .leading, spacing: 14) {
            Text("What are we revising?").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
            HStack(alignment: .top, spacing: 12) {
                HankAvatar(size: 36)
                Text(HankLines.greeting(green: green, total: subs.count, noun: bank.syllabus.isStrategyBank ? "strategy" : "subtopic",
                                        nouns: bank.syllabus.isStrategyBank ? "strategies" : "subtopics"))
                    .font(.system(size: 13.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 3) {
                ForEach(Array(subs.enumerated()), id: \.offset) { i, s in
                    MasterySquare(mastery: stats[i], size: bank.syllabus.isStrategyBank ? 9 : 16)
                        .help(bank.syllabus.isStrategyBank ? s.name : "\(s.id) \(s.name)")
                }
            }
            if bank.syllabus.isStrategyBank { StrategyIntro() }
            PaperPackBanner()
            reviewQueue
            if bank.syllabus.isStrategyBank, let mock = MathsMock.load() { mockCard(mock) }
            HStack(spacing: 16) {
                ReviseButton(title: "Mix everything — weakest first", style: .primary) { model.timeRequest = .everything }
                Button {
                    collapsed = []
                    model.mix = SubtopicMix()
                } label: { Label("Build my own paper", systemImage: "checklist") }
                .buttonStyle(GhostButtonStyle(compact: true))
                .help(bank.syllabus.isStrategyBank ? "Tick strategies from any topic and get one paper that mixes them all"
                                                   : "Tick subtopics from any topic and get one paper with all of them")
                .disabled(model.mix != nil)
                legend(.red, stats.filter { $0 == .red }.count)
                legend(.orange, stats.filter { $0 == .orange }.count)
                legend(.green, green)
                legend(.notStarted, stats.filter { $0 == .notStarted }.count)
            }
        }
    }

    /// Spaced-repetition queue across the whole syllabus.
    @ViewBuilder var reviewQueue: some View {
        let c = model.reviewCounts(.everything)
        if c.due > 0 || c.mistakes > 0 {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.due > 0 ? "\(c.due) question\(c.due == 1 ? "" : "s") due for review" : "Review queue is clear")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                    Text("\(c.mistakes) mistake\(c.mistakes == 1 ? "" : "s") to redo · spaced repetition brings them back right before you'd forget")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.dim)
                }
                Spacer()
                if c.due > 0 {
                    Button { model.timeRequestMode = .due; model.timeRequest = .everything } label: {
                        Label("Review due · ~\(Int(c.dueMinutes.rounded())) min", systemImage: "clock.arrow.circlepath")
                    }.buttonStyle(PrimaryButtonStyle(compact: true))
                }
                if c.mistakes > 0 {
                    Button { model.timeRequestMode = .mistakes; model.timeRequest = .everything } label: {
                        Label("Redo mistakes", systemImage: "arrow.uturn.backward.circle")
                    }.buttonStyle(GhostButtonStyle(compact: true))
                }
            }
            .padding(14)
            .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.stroke))
        }
    }

    /// Maths: the hand-picked exam-style paper, one click to a timed session.
    func mockCard(_ mock: MathsMock) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "timer").font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(mock.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                Text(mock.subtitle).font(.system(size: 11.5)).foregroundStyle(Palette.dim)
            }
            Spacer()
            Button { model.buildMathsMock() } label: { Label("Build my mock · \(mock.minutes) min", systemImage: "doc.text") }
                .buttonStyle(GhostButtonStyle(compact: true))
                .help("A full exam-style paper of whole past-paper questions, timed like the real thing")
        }
        .padding(14)
        .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.stroke))
    }

    func legend(_ m: Mastery, _ n: Int) -> some View {
        HStack(spacing: 6) {
            MasterySquare(mastery: m, size: 10)
            Text("\(m.label) · \(n)").font(.system(size: 11.5)).foregroundStyle(Palette.dim)
        }
    }
}

struct ThemeCard: View {
    @Environment(AppModel.self) var model
    var theme: Theme
    var expanded: Bool
    var toggle: () -> Void

    var body: some View {
        let bank = model.bank!
        let strategies = bank.syllabus.isStrategyBank
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Text(strategies ? String(theme.id.dropFirst()) : theme.id)
                        .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Palette.gradient, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(theme.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.text)
                        Text("\(theme.subtopics.filter { !$0.hlOnly }.count) \(strategies ? "strategies" : "SL subtopics")").font(.system(size: 12)).foregroundStyle(Palette.dim)
                    }
                    Spacer()
                    if let mix = model.mix {
                        if mix.topic == nil { MixSelectAll(ids: theme.subtopics.filter { !$0.hlOnly }.map(\.id)) }
                    } else {
                        ReviseButton(title: strategies ? "Exam-style mix" : "Mix whole theme", style: .ghost) { model.timeRequest = .theme(theme.id) }
                            .help(strategies ? "Whole past-paper questions from this topic, mixed" : "Questions from every subtopic in this theme")
                    }
                    Button(action: toggle) {
                        Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 0 : -90))
                            .foregroundStyle(Palette.dim).frame(width: 28, height: 28)
                    }.buttonStyle(.plain)
                }
                .padding(18)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle)

                if expanded {
                    ForEach(bank.syllabus.topics(in: theme)) { topic in
                        Divider().overlay(Palette.stroke.opacity(0.5))
                        TopicSection(topic: topic)
                    }
                }
            }
        }
    }
}

struct TopicSection: View {
    @Environment(AppModel.self) var model
    var topic: Topic

    var strategies: Bool { model.bank?.syllabus.isStrategyBank == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(strategies ? topic.name : "\(topic.id) · \(topic.name)").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.violet)
                    .textCase(.uppercase).tracking(0.6)
                Spacer()
                if let mix = model.mix {
                    if mix.allows(topic.subtopics[0].id) && topic.subtopics.count > 1 { MixSelectAll(ids: topic.subtopics.map(\.id)) }
                } else {
                    actions
                }
            }
            ForEach(topic.subtopics) { s in
                if strategies { StrategyRow(strategy: s) } else { SubtopicRow(subtopic: s) }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    @ViewBuilder var actions: some View {
                let c = model.reviewCounts(.topic(topic.id))
                if c.mistakes > 0 {
                    Button { model.timeRequestMode = .mistakes; model.timeRequest = .topic(topic.id) } label: {
                        Label("Redo \(c.mistakes) mistake\(c.mistakes == 1 ? "" : "s")", systemImage: "arrow.uturn.backward.circle")
                    }.buttonStyle(GhostButtonStyle(compact: true))
                }
                if topic.subtopics.count > 1 {
                    Button { model.mix = SubtopicMix(topic: topic.id) } label: { Label("Pick & mix", systemImage: "checklist") }
                        .buttonStyle(GhostButtonStyle(compact: true))
                        .help(strategies ? "Choose which of these strategies to mix into one paper" : "Choose which subtopics in \(topic.id) to mix into one paper")
                    ReviseButton(title: strategies ? "Mix these moves" : "Revise whole topic", style: .ghost) { model.timeRequest = .topic(topic.id) }
                }
    }
}

struct SubtopicRow: View {
    @Environment(AppModel.self) var model
    var subtopic: Subtopic
    @State private var hover = false

    var body: some View {
        let st = model.progress.stats(for: subtopic.id)
        let count = model.bank?.count(for: subtopic.id) ?? 0
        let mixing = model.mix != nil
        let pickable = model.mix?.allows(subtopic.id) == true && count > 0
        let picked = model.mix?.picked.contains(subtopic.id) == true
        HStack(spacing: 12) {
            if mixing {
                Image(systemName: picked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(picked ? Palette.purple : Palette.faint)
            }
            MasterySquare(mastery: st.mastery, size: 16).help(st.mastery.label)
            Text(subtopic.id).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.lilac).frame(width: 40, alignment: .leading)
            Text(subtopic.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.text)
            if let p = st.percent {
                Chip(text: "\(Int(p * 100))%", color: Palette.color(st.mastery))
            }
            let rc = model.reviewCounts(.subtopic(subtopic.id))
            if rc.due > 0 && !mixing {
                Button { model.timeRequestMode = .due; model.timeRequest = .subtopic(subtopic.id) } label: {
                    Chip(text: "\(rc.due) due", color: Palette.purple)
                }.buttonStyle(.plain).help("Due for spaced review")
            }
            if rc.mistakes > 0 && !mixing {
                Button { model.timeRequestMode = .mistakes; model.timeRequest = .subtopic(subtopic.id) } label: {
                    Chip(text: "\(rc.mistakes) to fix", color: Palette.orange)
                }.buttonStyle(.plain).help("Redo the questions you lost marks on")
            }
            Spacer()
            Text("\(count - rc.unseen)/\(count) done").font(.system(size: 11.5)).foregroundStyle(Palette.faint)
            if let url = URL(string: subtopic.notesUrl) {
                Link(destination: url) { Image(systemName: "book.closed.fill") }
                    .foregroundStyle(Palette.dim).help("Read the notes on Biology for Life")
            }
            if !mixing {
                ReviseButton(title: "Revise", style: .primary) { model.timeRequest = .subtopic(subtopic.id) }
                    .disabled(count == 0)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(picked ? Palette.cardHi : hover ? Palette.cardHi.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { if pickable { withAnimation(.snappy(duration: 0.15)) { model.mix?.toggle(subtopic.id) } } }
        .opacity(mixing && !pickable ? 0.4 : 1)
        .onHover { hover = $0 }
    }
}

/// Opens the "how long have you got?" sheet for a subtopic, topic or theme.
struct ReviseButton: View {
    enum Style { case primary, ghost }
    var title: String
    var style: Style
    var action: () -> Void

    var body: some View {
        switch style {
        case .primary: Button(action: action) { Label(title, systemImage: "doc.badge.plus") }.buttonStyle(PrimaryButtonStyle(compact: true))
        case .ghost: Button(action: action) { Label(title, systemImage: "square.stack.3d.up") }.buttonStyle(GhostButtonStyle(compact: true))
        }
    }
}

/// Shown until the past papers are downloaded (first launch on her Mac).
struct PaperPackBanner: View {
    @Environment(AppModel.self) var model
    var body: some View {
        let pack = model.pack
        switch pack.state {
        case .ready, .checking:
            EmptyView()
        case .downloading(let p):
            banner("arrow.down.circle.fill", "Downloading the past papers… \(Int(p * 100))%",
                   "One-time download (~240 MB). You can look around while it finishes.") {
                ProgressView(value: p).tint(Palette.purple).frame(width: 140)
            }
        case .installing:
            banner("shippingbox.fill", "Unpacking the past papers…", "Almost there.") { ProgressView().controlSize(.small) }
        case .missing:
            banner("arrow.down.circle", "The past papers need downloading", "One-time download (~240 MB).") {
                Button("Download") { Task { await pack.ensure() } }.buttonStyle(PrimaryButtonStyle(compact: true))
            }
        case .failed(let why):
            banner("exclamationmark.triangle.fill", "Couldn't download the past papers", why) {
                Button("Try again") { Task { await pack.ensure() } }.buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
    }

    func banner<A: View>(_ icon: String, _ title: String, _ sub: String, @ViewBuilder action: () -> A) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                Text(sub).font(.system(size: 11.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            action()
        }
        .padding(14)
        .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.violet.opacity(0.5)))
    }
}
