import SwiftUI

/// Biology SL | Business HL | Economics HL | Maths AA SL, at the top of the Topics page.
struct SubjectSwitch: View {
    @Environment(AppModel.self) var model
    @AppStorage("subject") private var subject = "biology"
    var body: some View {
        HStack(spacing: 4) {
            option("biology", "Biology SL", "leaf.fill")
            ForEach(CaseSubject.allCases) { option($0.pageKey, $0.name, $0.icon) }
            if model.maths != nil { option(Subject.maths.rawValue, Subject.maths.title, Subject.maths.icon) }
        }
        .padding(4)
        .background(Palette.bg2, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.stroke))
    }

    func option(_ id: String, _ title: String, _ icon: String) -> some View {
        let on = subject == id
        return Button { withAnimation(.snappy) { subject = id } } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12.5, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? .white : Palette.dim)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(on ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Color.clear), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Business HL: real past-paper questions. Pick a topic → a question → timed or not → do it on the iPad → Hank marks it.
struct BusinessView: View {
    @Environment(AppModel.self) var model
    @AppStorage("business.older") private var showOlder = false
    @AppStorage("business.topic") private var topic = "all"
    @State private var showHow = false
    @State private var fullPapers = false
    @State private var selectedTopics: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SubjectSwitch()
                if let bank = model.business {
                    header
                    howItsMarked
                    Picker("Practice", selection: $fullPapers) {
                        Text("By topic").tag(false)
                        Text("Full cases & papers").tag(true)
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
                            Button { model.businessPracticeRequest = .topic(selected.id, bank: bank) } label: {
                                Label("Revise this topic · mix its questions", systemImage: "shuffle")
                            }.buttonStyle(PrimaryButtonStyle())
                            BusinessReadingLinks(topics: [selected])
                            Text("Answer the selected parts only. Each practice PDF keeps the original case, tables and references.")
                                .font(.system(size: 12.5)).foregroundStyle(Palette.dim)
                            if !bank.sets.contains(where: { $0.currentSyllabus && $0.paper != "3" && !$0.parts(in: topic).isEmpty }) {
                                Text("There are no focused questions for this topic in the current papers yet. Use the reading links or turn on older questions below for more practice.")
                                    .font(.system(size: 12.5)).foregroundStyle(Palette.dim)
                            }
                        }
                        section(bank, fullPapers ? "Paper 2 · one case, all its parts" : "Paper 2 · topic questions",
                                fullPapers ? "Complete case questions, including their short answers and 10-markers." : "Focused parts with their original case and markscheme.",
                                bank.sets.filter { $0.paper == "2" && $0.currentSyllabus })
                        section(bank, fullPapers ? "Paper 1 · the whole case study paper" : "Paper 1 · topic questions with the shared case",
                                fullPapers ? "30 marks, 90 minutes. Short questions on the case, then one 10-marker from a choice of two." : "The shared case stays intact. Practise the selected short questions or extended responses.",
                                bank.sets.filter { $0.paper == "1" })
                        if fullPapers {
                            section(bank, "Paper 3 · social enterprise", "25 marks, 75 minutes. Ends with the 17-mark plan of action.",
                                    bank.sets.filter { $0.paper == "3" })
                        } else {
                            Button { fullPapers = true } label: { Label("Practise a complete Paper 3", systemImage: "doc.text") }
                                .buttonStyle(GhostButtonStyle(compact: true))
                        }
                        Toggle(isOn: $showOlder.animation()) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Show older Paper 2 questions (2016–2023)").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                                Text("Extra practice from the previous syllabus, using each question's original markscheme.")
                                    .font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                            }
                        }
                        .toggleStyle(.switch).tint(Palette.purple)
                        if showOlder {
                            section(bank, "Older Paper 2 questions", "Write on the lined pages at the end of the PDF.",
                                    bank.sets.filter { !$0.currentSyllabus })
                        }
                    }
                } else {
                    Text("The Business questions didn't load. Restart Biosphere; if it keeps happening, tell Matt.")
                        .foregroundStyle(Palette.red)
                }
            }
            .padding(.horizontal, 32).padding(.top, 56).padding(.bottom, 40)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if !fullPapers, !selectedTopics.isEmpty, let bank = model.business {
                HStack(spacing: 12) {
                    Text("\(selectedTopics.count) subtopics selected").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    Button("Clear") { selectedTopics = [] }.buttonStyle(GhostButtonStyle(compact: true))
                    Spacer()
                    Button { model.businessPracticeRequest = .chosen(Array(selectedTopics).sorted(), bank: bank) } label: {
                        Label("Mix selected subtopics", systemImage: "shuffle")
                    }.buttonStyle(PrimaryButtonStyle())
                }.padding(16).background(Palette.bg2)
            }
        }
        .onAppear {
            if topic != "all" && model.business?.topic(topic) == nil { topic = "all" }
        }
    }

    var header: some View {
        let marked = model.sessions.filter { $0.caseSubject == .business && $0.status == .marked }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Business questions").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
            HStack(alignment: .top, spacing: 12) {
                HankAvatar(size: 36)
                Text(marked.isEmpty
                     ? "Real past-paper questions, with the case. Do one on your iPad, send it back, and I'll mark every part against the markscheme and show you why marks were lost."
                     : "\(marked.count) marked so far. Pick a topic below to go back over the parts you lost marks on.")
                    .font(.system(size: 13.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder func startHere(_ bank: BusinessBank) -> some View {
        if let s = BusinessBank.startHere.compactMap({ bank.set($0) }).first(where: { model.attempts(at: $0).isEmpty }) {
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
                            ForEach(BusinessComposer.commandRules, id: \.0) { w, r in
                                (Text(w).bold() + Text(" — " + r.replacingOccurrences(of: "**", with: ""))).font(.system(size: 12.5)).foregroundStyle(Palette.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        group("The 10-marker: five steps, and why") {
                            ForEach(BusinessComposer.tenMarkerSteps, id: \.self) { s in
                                Text(s.replacingOccurrences(of: "**", with: "")).font(.system(size: 12.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        group("SWOT and STEEPLE") {
                            Text(BusinessComposer.swotWhy.replacingOccurrences(of: "**", with: "")).font(.system(size: 12.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
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
            Text("Choose a topic, mix a whole unit, or tick subtopics to combine them.")
                .font(.system(size: 13)).foregroundStyle(Palette.dim)
            ForEach(["1", "2", "3", "4", "5", "toolkit"], id: \.self) { unit in
                let topics = bank.topics.filter { $0.unit == unit }
                if let first = topics.first {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text((unit == "toolkit" ? "" : "Unit \(unit) · ") + (first.unitName ?? ""))
                                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.purple)
                                Spacer()
                                Button { model.businessPracticeRequest = .unit(unit, bank: bank) } label: {
                                    Label(unit == "toolkit" ? "Mix the toolkit" : "Mix whole unit", systemImage: "shuffle")
                                }.buttonStyle(GhostButtonStyle(compact: true))
                            }
                            ForEach(topics) { t in
                                let count = bank.sets.filter { $0.currentSyllabus && $0.paper != "3" }
                                    .reduce(0) { $0 + $1.parts(in: t.id).count }
                                HStack(spacing: 10) {
                                    Toggle("Select \(t.displayName)", isOn: Binding(get: { selectedTopics.contains(t.id) }, set: { on in
                                        if on { selectedTopics.insert(t.id) } else { selectedTopics.remove(t.id) }
                                    })).labelsHidden().toggleStyle(.checkbox).disabled(count == 0)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.displayName).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Palette.text)
                                        Text((count == 0 ? "No past-paper questions yet · read the notes"
                                              : "\(count) question\(count == 1 ? "" : "s")") + (t.hlOnly == true ? " · HL" : ""))
                                            .font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                                    }
                                    Spacer()
                                    Button { topic = t.id } label: { Image(systemName: "book") }
                                        .buttonStyle(GhostButtonStyle(compact: true)).help("Reading links and individual cases")
                                    if count == 0 {
                                        Button { topic = t.id } label: { Text("Read notes") }
                                            .buttonStyle(GhostButtonStyle(compact: true))
                                    } else {
                                        Button { model.businessPracticeRequest = .topic(t.id, bank: bank) } label: { Text("Revise") }
                                            .buttonStyle(PrimaryButtonStyle(compact: true))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func chip(_ id: String, _ name: String) -> some View {
        let on = topic == id
        return Button { withAnimation(.snappy) { topic = id } } label: {
            Text(name).font(.system(size: 12.5, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? .white : Palette.lilac)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(on ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Palette.cardHi), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : Palette.stroke))
        }
        .buttonStyle(.plain)
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

struct BusinessSetRow: View {
    @Environment(AppModel.self) var model
    var set: BusinessSet
    var topic: String?
    @State private var hover = false

    var body: some View {
        let last = model.attempts(at: set).first
        let focus = topic.map { set.parts(in: $0) } ?? []
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(set.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(set.sourceLabel).font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                    if set.subject == .business, set.hasExtended && set.paper == "2" { Chip(text: "10-marker", color: Palette.purple) }
                    if set.subject == .economics, let essay = set.parts.filter(\.extended).map(\.marks).max() {
                        Chip(text: "\(essay)-marker", color: Palette.purple)
                    }
                }
                Text(focus.isEmpty
                     ? set.parts.map { "\($0.display) \($0.command.isEmpty ? "" : $0.command.lowercased())" }.joined(separator: " · ")
                     : "On this topic: " + focus.map { "\($0.display) \($0.prompt)" }.joined(separator: "  ·  "))
                    .font(.system(size: 12)).foregroundStyle(Palette.dim).lineLimit(2)
            }
            Spacer(minLength: 8)
            if let last, let score = last.score {
                Chip(text: "\(score)/\(last.totalMarks)", color: ResultsView.color(Double(score) / Double(max(last.totalMarks, 1))))
            }
            Text("\(set.marks) marks · \(set.minutes) min").font(.system(size: 11.5)).foregroundStyle(Palette.faint)
            Button { model.businessRequest = set } label: { Label(last == nil ? "Do it" : "Again", systemImage: "pencil.and.outline") }
                .buttonStyle(PrimaryButtonStyle(compact: true))
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(hover ? Palette.cardHi.opacity(0.6) : .clear)
        .onHover { hover = $0 }
    }
}

/// Step 2: she's picked the question. Timed or not?
struct BusinessSheet: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) var dismiss
    var set: BusinessSet
    @State private var timed = true
    /// Economics questions come with texts and data (or nothing, for an essay), not a business case.
    var caseWord: String { self.set.subject == .business ? "case" : self.set.paper == "1" ? "question" : "original texts and data" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(set.sourceLabel) · \(set.kindLabel)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.purple)
                    Text(set.title).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Palette.faint).padding(6) }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT'S IN IT · \(set.marks) MARKS").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Palette.purple)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(set.parts) { p in
                            HStack(alignment: .top, spacing: 8) {
                                Text(p.display).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2).background(Palette.purple, in: RoundedRectangle(cornerRadius: 5))
                                Text(p.prompt).font(.system(size: 12.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                Text("[\(p.marks)]").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.purple)
                            }
                        }
                    }
                    .padding(.bottom, 8)   // so the last question's final line never sits under the scroll edge
                }
                .frame(maxHeight: 360)   // tall enough for a whole Paper 1 list; the rest scrolls
                Text(set.writesInPaper
                     ? "The PDF starts with a one-page guide, then the \(caseWord). You write in the paper's own answer boxes, like the real exam."
                     : "The PDF starts with a one-page guide, then the \(caseWord), then answer pages with each question printed above its lines.")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
                if set.subject == .business && set.paper == "1" && set.selectedLabels == nil {
                    Text("Section B: answer one of the two 10-markers.").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.dim)
                }
                if set.selectedLabels != nil {
                    Text("Answer only the parts listed above. The other original questions stay visible as part of the \(caseWord).")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.purple)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 14))

            Toggle(isOn: $timed) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Time me (\(set.minutes) min, exam pace)").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                    Text(timed ? "The timer loads ready; it only starts when you press Start." : "No timer. Take as long as you need to learn it properly.")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                }
            }
            .toggleStyle(.switch).tint(Palette.purple)

            HStack {
                Spacer()
                Button {
                    model.createBusinessSession(set, timed: timed)
                    dismiss()
                } label: { Label("Make my paper", systemImage: "doc.badge.plus") }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 620)
        .background(.white)
    }
}
