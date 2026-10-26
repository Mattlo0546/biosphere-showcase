import SwiftUI

/// Economics HL: real past-paper questions, built and marked by the Business engine (see `CaseSubject`).
/// Pick a topic → mix its parts, or pick a whole question → timed or not → iPad → Hank marks it.
struct EconomicsView: View {
    @Environment(AppModel.self) var model
    @AppStorage("economics.older") private var showOlder = false
    @AppStorage("economics.topic") private var topic = "all"
    @State private var showHow = false
    @State private var fullPapers = false
    @State private var selectedTopics: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SubjectSwitch()
                if let bank = model.economics {
                    header
                    howItsMarked
                    Picker("Practice", selection: $fullPapers) {
                        Text("By topic").tag(false)
                        Text("Whole questions").tag(true)
                    }.pickerStyle(.segmented).frame(maxWidth: 400)
                    if !fullPapers && topic == "all" {
                        topicIndex(bank)
                    } else {
                        if fullPapers {
                            startHere(bank)
                        } else if let selected = bank.topic(topic) {
                            HStack {
                                Button { topic = "all" } label: { Label("All topics", systemImage: "chevron.left") }
                                    .buttonStyle(GhostButtonStyle(compact: true))
                                Text(selected.displayName).font(.system(size: 20, weight: .bold)).foregroundStyle(Palette.text)
                            }
                            Text(selected.blurb).font(.system(size: 12.5)).foregroundStyle(Palette.dim)
                            if count(selected.id, in: bank) > 0 {
                                Button { model.businessPracticeRequest = .topic(selected.id, bank: bank) } label: {
                                    Label("Revise this topic · mix its questions", systemImage: "shuffle")
                                }.buttonStyle(PrimaryButtonStyle())
                                Text("Answer the selected parts only. Each practice PDF keeps the original texts, tables and figures.")
                                    .font(.system(size: 12.5)).foregroundStyle(Palette.dim)
                            } else {
                                Text("There are no questions on this topic in the current papers yet. Turn on older questions below, or ask Hank to teach it.")
                                    .font(.system(size: 12.5)).foregroundStyle(Palette.dim)
                            }
                        }
                        section(bank, "Paper 2 · data response",
                                fullPapers ? "Texts and data, short parts with diagrams, then a 15-marker. 40 marks, 1 h 45." : "Focused parts with their original texts, data and markscheme.",
                                bank.sets.filter { $0.paper == "2" && $0.currentSyllabus })
                        section(bank, "Paper 1 · essays",
                                fullPapers ? "Explain (a) [10], then discuss with real-world examples (b) [15]. 25 marks, 1 h 15." : "The (a) explains, the (b) evaluates with real-world examples.",
                                bank.sets.filter { $0.paper == "1" && $0.currentSyllabus })
                        section(bank, "Paper 3 · policy questions",
                                fullPapers ? "Calculations, diagrams and a 10-mark policy recommendation. 30 marks, about 50 min." : "Calculations and diagrams from the policy paper, with its data.",
                                bank.sets.filter { $0.paper == "3" && $0.currentSyllabus })
                        Toggle(isOn: $showOlder.animation()) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Show older questions (2016–2021)").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                                Text("The previous syllabus: same essays, 20-mark data responses and quantitative Paper 3s, each with its own markscheme.")
                                    .font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                            }
                        }
                        .toggleStyle(.switch).tint(Palette.purple)
                        if showOlder {
                            ForEach(["1", "2", "3"], id: \.self) { paper in
                                section(bank, "Older Paper \(paper) questions", "Write on the lined pages at the end of the PDF.",
                                        bank.sets.filter { !$0.currentSyllabus && $0.paper == paper })
                            }
                        }
                    }
                } else {
                    Text("The Economics questions didn't load. Restart Biosphere; if it keeps happening, tell Matt.")
                        .foregroundStyle(Palette.red)
                }
            }
            .padding(.horizontal, 32).padding(.top, 56).padding(.bottom, 40)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if !fullPapers, !selectedTopics.isEmpty, let bank = model.economics {
                HStack(spacing: 12) {
                    Text("\(selectedTopics.count) topics selected").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    Button("Clear") { selectedTopics = [] }.buttonStyle(GhostButtonStyle(compact: true))
                    Spacer()
                    Button { model.businessPracticeRequest = .chosen(Array(selectedTopics).sorted(), bank: bank) } label: {
                        Label("Mix selected topics", systemImage: "shuffle")
                    }.buttonStyle(PrimaryButtonStyle())
                }.padding(16).background(Palette.bg2)
            }
        }
        .onAppear {
            if topic != "all" && model.economics?.topic(topic) == nil { topic = "all" }
        }
    }

    /// Current-syllabus parts on a topic (what "Revise" can draw from).
    func count(_ topic: String, in bank: BusinessBank) -> Int {
        bank.sets.filter(\.currentSyllabus).reduce(0) { $0 + $1.parts(in: topic).count }
    }

    var header: some View {
        let marked = model.sessions.filter { $0.caseSubject == .economics && $0.status == .marked }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Economics questions").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
            HStack(alignment: .top, spacing: 12) {
                HankAvatar(size: 36)
                Text(marked.isEmpty
                     ? "Real past-paper questions with their texts and data. Do one on your iPad, send it back, and I'll mark every part, diagrams included, and show you where the marks went."
                     : "\(marked.count) marked so far. Pick a topic below to go back over the parts you lost marks on.")
                    .font(.system(size: 13.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder func startHere(_ bank: BusinessBank) -> some View {
        if let s = EconomicsGuide.startHere.compactMap({ bank.set($0) }).first(where: { model.attempts(at: $0).isEmpty }) {
            HStack(spacing: 14) {
                Image(systemName: "flag.checkered").font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start here").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.purple).textCase(.uppercase).tracking(0.6)
                    Text("\(s.title) · \(s.kindLabel)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                    Text("\(s.sourceLabel) · \(s.marks) marks · about \(s.minutes) min").font(.system(size: 11.5)).foregroundStyle(Palette.dim)
                }
                Spacer()
                Button { model.businessRequest = s } label: { Label("Do it", systemImage: "pencil.and.outline") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)
            .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.violet.opacity(0.5)))
        }
    }

    var howItsMarked: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.snappy) { showHow.toggle() } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "lightbulb.fill").foregroundStyle(Palette.orange)
                        Text("How the marks work, and why").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                        Spacer()
                        Image(systemName: "chevron.down").rotationEffect(.degrees(showHow ? 0 : -90)).foregroundStyle(Palette.dim)
                    }
                    .padding(16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if showHow {
                    VStack(alignment: .leading, spacing: 14) {
                        group("What each command word wants") {
                            ForEach(EconomicsGuide.commandRules, id: \.0) { w, r in
                                (Text(w).bold() + Text(" — " + r.replacingOccurrences(of: "**", with: ""))).font(.system(size: 12.5)).foregroundStyle(Palette.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        steps("Diagrams: where the marks are", EconomicsGuide.diagramSteps)
                        steps("The 15-marker: four steps, and why", EconomicsGuide.fifteenMarkerSteps)
                        steps("Paper 1 (a): explain, don't evaluate", EconomicsGuide.essayTenSteps)
                        steps("Paper 3: the policy recommendation", EconomicsGuide.policySteps)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
            }
        }
    }

    func steps(_ title: String, _ lines: [String]) -> some View {
        group(title) {
            ForEach(lines, id: \.self) { s in
                Text(s.replacingOccurrences(of: "**", with: "")).font(.system(size: 12.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.violet).textCase(.uppercase)
            content()
        }
    }

    func topicIndex(_ bank: BusinessBank) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { model.businessPracticeRequest = .everything(bank: bank) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "shuffle").font(.system(size: 20, weight: .semibold))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mix everything — weakest first").font(.system(size: 15, weight: .bold))
                        Text("Choose your time and get one paper across the syllabus.").font(.system(size: 12))
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                }.foregroundStyle(Palette.purple).padding(18)
                    .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain)
            Text("Choose a topic, mix a whole unit, or tick topics to combine them.")
                .font(.system(size: 13)).foregroundStyle(Palette.dim)
            ForEach(["1", "2", "3", "4"], id: \.self) { unit in
                let topics = bank.topics.filter { $0.unit == unit }
                if let first = topics.first {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Unit \(unit) · " + (first.unitName ?? "")).font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.purple)
                                Spacer()
                                if topics.contains(where: { count($0.id, in: bank) > 0 }) {
                                    Button { model.businessPracticeRequest = .unit(unit, bank: bank) } label: {
                                        Label("Mix whole unit", systemImage: "shuffle")
                                    }.buttonStyle(GhostButtonStyle(compact: true))
                                }
                            }
                            ForEach(topics) { t in topicRow(t, bank: bank) }
                        }
                    }
                }
            }
        }
    }

    func topicRow(_ t: BusinessTopic, bank: BusinessBank) -> some View {
        let n = count(t.id, in: bank)
        return HStack(spacing: 10) {
            Toggle("Select \(t.displayName)", isOn: Binding(get: { selectedTopics.contains(t.id) }, set: { on in
                if on { selectedTopics.insert(t.id) } else { selectedTopics.remove(t.id) }
            })).labelsHidden().toggleStyle(.checkbox).disabled(n == 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.displayName).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Palette.text)
                Text((n == 0 ? "No past-paper questions yet" : "\(n) question\(n == 1 ? "" : "s")") + (t.hlOnly == true ? " · HL" : ""))
                    .font(.system(size: 11.5)).foregroundStyle(Palette.faint)
            }
            Spacer()
            Button { topic = t.id } label: { Image(systemName: "list.bullet") }
                .buttonStyle(GhostButtonStyle(compact: true)).help("Choose one past-paper question on this topic")
            Button { model.businessPracticeRequest = .topic(t.id, bank: bank) } label: { Text("Revise") }
                .buttonStyle(PrimaryButtonStyle(compact: true)).disabled(n == 0)
        }
    }

    @ViewBuilder func section(_ bank: BusinessBank, _ title: String, _ blurb: String, _ all: [BusinessSet]) -> some View {
        let list = fullPapers ? all : all.compactMap { $0.selecting(topic: topic) }
        if !list.isEmpty {
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.text)
                        Text("\(blurb) · \(list.count) to choose from").font(.system(size: 12)).foregroundStyle(Palette.dim)
                    }
                    .padding(18)
                    ForEach(list) { s in
                        Divider().overlay(Palette.stroke.opacity(0.5))
                        BusinessSetRow(set: s, topic: fullPapers ? nil : topic)
                    }
                }
            }
        }
    }
}
