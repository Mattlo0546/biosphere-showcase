import SwiftUI
import UniformTypeIdentifiers

struct SessionsView: View {
    @Environment(AppModel.self) var model
    @AppStorage("width.sessionList") private var listWidth: Double = 300
    @AppStorage("sessions.sort") private var sort = "date"          // date | subject | topic
    @AppStorage("sessions.ascending") private var ascending = false

    /// Sessions in groups: one unnamed group when sorting by date, otherwise one per subject or topic.
    var groups: [(name: String, sessions: [StudySession])] {
        let byDate = model.sessions.sorted { ascending ? $0.createdAt < $1.createdAt : $0.createdAt > $1.createdAt }
        guard sort != "date" else { return [("", byDate)] }
        let key: (StudySession) -> String = sort == "subject" ? model.subjectName : { "\(model.subjectName($0)) · \(model.topicName($0))" }
        let names = Array(Set(byDate.map(key))).sorted { ascending ? $0 < $1 : $0 > $1 }
        // Inside a group, newest first: that's usually the one she wants to go back to.
        return names.map { n in (n, model.sessions.filter { key($0) == n }.sorted { $0.createdAt > $1.createdAt }) }
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            if listWidth > 0 { list.frame(width: listWidth) }
            // Drag left past ~160pt to hide the list entirely; drag back (or use the button) to bring it back.
            ResizeHandle(width: $listWidth, growsRight: true, defaultWidth: 300) { raw in
                raw < 160 ? 0 : PanelWidth.clamp(raw, 220, 480)
            }
            Group {
                if let id = model.openSession ?? model.sessions.first?.id, let s = model.session(id) {
                    SessionDetailView(session: s, listHidden: listWidth == 0) {
                        withAnimation(.snappy) { listWidth = listWidth == 0 ? 300 : 0 }
                    }
                    .id(s.id)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    var list: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("My sessions").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    .padding(.horizontal, 16).padding(.top, 52).padding(.bottom, 8)
                HStack(spacing: 6) {
                    Picker("", selection: $sort) {
                        Text("Date").tag("date")
                        Text("Subject").tag("subject")
                        Text("Topic").tag("topic")
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .onChange(of: sort) { _, s in ascending = s != "date" }   // dates newest first, names A → Z
                    Button { withAnimation(.snappy) { ascending.toggle() } } label: {
                        Image(systemName: ascending ? "arrow.up" : "arrow.down").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.lilac).frame(width: 26, height: 22)
                            .background(Palette.cardHi, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(sort == "date" ? (ascending ? "Oldest first" : "Newest first") : (ascending ? "A → Z" : "Z → A"))
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
                if model.sessions.isEmpty {
                    VStack(spacing: 10) {
                        HankAvatar(size: 44)
                        Text(HankLines.empty[0]).multilineTextAlignment(.center).font(.system(size: 13)).foregroundStyle(Palette.dim)
                        Button("Pick a topic") { model.selection = .revise }.buttonStyle(PrimaryButtonStyle(compact: true))
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(groups, id: \.name) { g in
                                if !g.name.isEmpty {
                                    Text(g.name).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.violet)
                                        .textCase(.uppercase).tracking(0.4).lineLimit(1)
                                        .padding(.horizontal, 6).padding(.top, 10)
                                }
                                ForEach(g.sessions) { s in
                                    SessionRow(session: s, selected: model.openSession == s.id)
                                        .onTapGesture { model.openSession = s.id }
                                        .contextMenu {
                                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.pdfURL(s)]) }
                                            Button("Delete session", role: .destructive) { model.delete(s) }
                                        }
                                }
                            }
                        }.padding(.horizontal, 10).padding(.bottom, 20)
                    }
                }
            }
            .background(Palette.bg2.opacity(0.6))
    }
}

struct StatusChip: View {
    var status: SessionStatus
    var body: some View {
        switch status {
        case .ready: Chip(text: "Ready", color: Palette.lilac)
        case .sent: Chip(text: "On iPad", color: Palette.violet)
        case .completed: Chip(text: "Received", color: Palette.orange)
        case .marking: Chip(text: "Marking…", color: Palette.orange)
        case .marked: Chip(text: "Marked", color: Palette.green)
        case .failed: Chip(text: "Needs attention", color: Palette.red)
        }
    }
}

struct SessionRow: View {
    @Environment(AppModel.self) var model
    var session: StudySession
    var selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                Spacer()
                if let score = session.score {
                    let pct = Double(score) / Double(max(session.totalMarks, 1))
                    Text("\(score)/\(session.totalMarks)").font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(pct >= 0.75 ? Palette.green : pct >= 0.5 ? Palette.orange : Palette.red)
                }
            }
            HStack(spacing: 8) {
                StatusChip(status: session.status)
                Text(session.isCasePaper ? "\(session.caseSubject?.shortName ?? "Business") · \(session.totalMarks) marks" : "Biology · \(session.questionIds.count) Qs · \(session.minutes) min").font(.system(size: 11)).foregroundStyle(Palette.faint)
                Spacer()
                Text(session.createdAt, format: .dateTime.day().month(.abbreviated)).font(.system(size: 11)).foregroundStyle(Palette.faint)
            }
        }
        .padding(12)
        .background(selected ? Palette.cardHi : Palette.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Palette.violet : .clear, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

struct SessionDetailView: View {
    @Environment(AppModel.self) var model
    var session: StudySession
    var listHidden = false
    var toggleList: () -> Void = {}
    @AppStorage("width.sessionActions") private var actionsWidth: Double = 330
    @StateObject private var pdfZoom = PDFZoom()
    @State private var showResults = true
    @State private var showCompleted = false
    @State private var dropping = false
    @State private var droppingOnZone = false
    @State private var lineIndex = 0

    var body: some View {
        if session.isCasePaper, session.status == .marked, showResults, let r = model.businessResults(session) {
            BusinessResultsView(session: session, result: r, back: { showResults = false })
        } else if !session.isCasePaper, session.status == .marked, showResults, let r = model.results(session) {
            ResultsView(session: session, result: r, back: { showResults = false })
        } else {
            HStack(spacing: 0) {
                pdfPane.frame(minWidth: 260)
                ResizeHandle(width: $actionsWidth, growsRight: false, defaultWidth: 330) { raw in
                    PanelWidth.clamp(raw, 260, 560)
                }
                actions.frame(width: actionsWidth)
            }
        }
    }

    var pdfPane: some View {
        let completed = model.completedURL(session)
        let hasCompleted = FileManager.default.fileExists(atPath: completed.path)
        return VStack(spacing: 0) {
            HStack {
                Button(action: toggleList) {
                    Image(systemName: "sidebar.left").foregroundStyle(listHidden ? Palette.purple : Palette.dim)
                }
                .buttonStyle(.plain).help(listHidden ? "Show sessions list" : "Hide sessions list")
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 34).padding(.bottom, hasCompleted ? 0 : 6)
            if hasCompleted {
                Picker("", selection: $showCompleted) {
                    Text("Questions").tag(false)
                    Text("Your answers").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 260).padding(.top, 4).padding(.bottom, 8)
            }
            PDFKitView(url: showCompleted && hasCompleted ? completed : model.pdfURL(session), zoom: pdfZoom)
                .overlay(alignment: .bottomTrailing) { PDFZoomBar(zoom: pdfZoom).padding(14) }

        }
        .background(Palette.bg2)
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.violet, style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .background(Color.white.opacity(0.85))
                    .overlay(Text("Drop your finished PDF to mark it").font(.title3.bold()).foregroundStyle(Palette.purple))
                    .padding(20)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping, perform: dropPDF)
    }

    var actions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    StatusChip(status: session.status)
                    Text(session.title).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    Text(session.subtitle).font(.system(size: 12.5)).foregroundStyle(Palette.dim)
                    HStack(spacing: 14) {
                        if !session.isCasePaper { stat("\(session.questionIds.count)", "questions") }
                        stat("\(session.totalMarks)", "marks")
                        stat("\(session.minutes)", "minutes")
                        stat("\(session.pageCount)", "pages")
                    }.padding(.top, 6)
                }
                step(1, "Send it to your iPad") {
                    Button { model.send(session) } label: { Label("Send to iPad", systemImage: "ipad.and.arrow.forward") }
                        .buttonStyle(PrimaryButtonStyle())
                    Text(model.settings.sendMethod == .icloud ? "Copies to iCloud Drive › Biosphere › To do."
                         : model.settings.ipadName.isEmpty ? "Opens AirDrop — tap your iPad." : "Goes straight to \(model.settings.ipadName).")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                }

                step(2, "Do it (timer optional)") {
                    if model.timer.sessionId == session.id {
                        Text(StudyTimer.format(model.timer.remaining)).font(.system(size: 40, weight: .heavy, design: .rounded)).monospacedDigit()
                            .foregroundStyle(model.timer.remaining < 0 ? Palette.red : Palette.text)
                        if model.timer.isFresh {
                            Button { model.timer.resume() } label: { Label("Start timer", systemImage: "play.fill") }
                                .buttonStyle(PrimaryButtonStyle())
                        } else {
                            HStack {
                                Button(model.timer.running ? "Pause" : "Resume") { model.timer.running ? model.timer.pause() : model.timer.resume() }
                                Button("+5 min") { model.timer.add(minutes: 5) }
                                Button("Stop") { model.timer.stop() }
                            }.buttonStyle(GhostButtonStyle(compact: true))
                        }
                    } else {
                        Button { model.timer.start(session) } label: { Label("Start \(session.minutes)-minute timer", systemImage: "timer") }
                            .buttonStyle(GhostButtonStyle())
                    }
                }

                step(3, "Send it back to your Mac") {
                    Text("AirDrop the finished PDF back (or save it to iCloud Drive › Biosphere › Done). I'll notice it and start marking.")
                        .font(.system(size: 12)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
                    dropZone
                }

                step(4, "Hank marks it") { markingSection }
            }
            .padding(.horizontal, 20).padding(.top, 76).padding(.bottom, 30)
        }
        .background(Palette.bg)
    }

    @ViewBuilder var markingSection: some View {
        switch session.status {
        case .marking:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Marking…").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text) }
                Text(HankLines.marking[lineIndex % HankLines.marking.count]).font(.system(size: 12).italic()).foregroundStyle(Palette.lilac)
                    .onReceive(Timer.publish(every: 6, on: .main, in: .common).autoconnect()) { _ in lineIndex += 1 }
                ForEach(Array((model.markingLog[session.id] ?? []).suffix(5).enumerated()), id: \.offset) { _, l in
                    Text("· " + l).font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
            }
        case .marked:
            Button { showResults = true } label: { Label("See results", systemImage: "checkmark.seal.fill") }.buttonStyle(PrimaryButtonStyle())
            Button("Mark again") { Task { await model.mark(session) } }.buttonStyle(GhostButtonStyle(compact: true))
        case .completed, .failed:
            if let e = session.error { Text(e).font(.system(size: 11.5)).foregroundStyle(Palette.red).fixedSize(horizontal: false, vertical: true) }
            Button { Task { await model.mark(session) } } label: { Label("Mark it now", systemImage: "checkmark.seal") }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.claude.loggedIn)
        default:
            Text("Waiting for your answers.").font(.system(size: 12)).foregroundStyle(Palette.faint)
        }
    }

    func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
            Text(l).font(.system(size: 10.5)).foregroundStyle(Palette.faint)
        }
    }

    func step<C: View>(_ n: Int, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Palette.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Drag the finished PDF here from Finder, AirDrop's Downloads, or the iCloud Done folder — or click to browse.
    var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: droppingOnZone ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 24)).foregroundStyle(Palette.purple)
            Text(droppingOnZone ? "Let go to send it to Hank" : "Drag your finished PDF here")
                .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
            Button { pickFile() } label: { Label("or choose PDF…", systemImage: "tray.and.arrow.down") }
                .buttonStyle(GhostButtonStyle(compact: true))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(droppingOnZone ? Palette.cardHi : Palette.bg2, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(droppingOnZone ? Palette.violet : Palette.stroke, style: StrokeStyle(lineWidth: droppingOnZone ? 2 : 1.5, dash: [7])))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { pickFile() }
        .onDrop(of: [.fileURL], isTargeted: $droppingOnZone, perform: dropPDF)
        .animation(.easeOut(duration: 0.15), value: droppingOnZone)
    }

    /// Accepts the first dropped PDF and hands it to Hank; anything else is refused so Finder shows the no-drop cursor.
    func dropPDF(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                if url.pathExtension.lowercased() == "pdf" { model.importCompleted(url, into: session) }
                else { model.say("That's not a PDF — drop the finished paper you exported from the iPad.") }
            }
        }
        return true
    }

    func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        if panel.runModal() == .OK, let url = panel.url { model.importCompleted(url, into: session) }
    }
}
