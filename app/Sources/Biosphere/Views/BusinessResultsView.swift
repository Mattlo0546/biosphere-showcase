import SwiftUI

/// Results for a Business or Economics set: every part marked against its markscheme (like Biology), and for the
/// 10/17-markers the band, what capped it, her sentences labelled by what they earn, and a rewrite.
struct BusinessResultsView: View {
    @Environment(AppModel.self) var model
    var session: StudySession
    var result: BusinessResult
    var back: () -> Void
    @State private var onlyLost = false
    @State private var reading: BusinessReading?   // transcript.json: where each of her lines is on the page

    var set: BusinessSet? { model.businessSet(for: session) }
    var pct: Double { Double(result.awarded) / Double(max(result.available, 1)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button { model.resultsVisible = false; back() } label: { Label("Paper & actions", systemImage: "chevron.left") }
                        .buttonStyle(GhostButtonStyle(compact: true))
                    Spacer()
                }
                header
                if !result.essays.isEmpty { BusinessMarkedPaperView(session: session, result: result) }
                fixesSection
                partsHeader
                ForEach(shownParts, id: \.label) { r in partCard(r) }
                ForEach(result.essays, id: \.label) { e in EssayFeedbackView(session: session, essay: e, prompt: prompt(e.label)) }
                if !result.transcriptionNote.isEmpty {
                    Text(result.transcriptionNote).font(.system(size: 11)).foregroundStyle(Palette.faint)
                }
            }
            .padding(.horizontal, 30).padding(.top, 52).padding(.bottom, 40)
            .frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
        .onAppear { model.resultsVisible = true }
        .task(id: session.id) {
            reading = try? JSON.load(BusinessReading.self, from: Workspace.sessionDir(session.id).appendingPathComponent("transcript.json"))
        }
        .onDisappear { model.resultsVisible = false }
    }

    func prompt(_ label: String) -> String { set?.parts.first { $0.label == label }?.prompt ?? "" }
    func topicName(_ label: String) -> String {
        guard let t = set?.parts.first(where: { $0.label == label })?.topic else { return "" }
        return model.caseBank(session.caseSubject)?.topic(t)?.name ?? ""
    }
    /// Economics: the official markscheme crops for a part, from the paper it came from (a mixed paper's
    /// "2.c" is original question 2's part c).
    func markscheme(_ label: String) -> (url: URL, regions: [Region])? {
        guard let regions = set?.parts.first(where: { $0.label == label })?.msRegions, !regions.isEmpty else { return nil }
        let setId: String?
        if let components = session.businessComponents {
            let n = Int(label.split(separator: ".").first ?? "") ?? 0
            setId = components.indices.contains(n - 1) ? components[n - 1].setId : nil
        } else { setId = session.businessSetId }
        guard let setId, let url = CaseSubject.markschemeURL(setId: setId) else { return nil }
        return (url, regions)
    }
    var shownParts: [BusinessPartResult] { onlyLost ? result.parts.filter { $0.awarded < $0.available } : result.parts }

    var header: some View {
        let color = ResultsView.color(pct)
        return Card(padding: 20) {
            HStack(alignment: .center, spacing: 24) {
                ZStack {
                    Circle().stroke(Palette.empty, lineWidth: 11)
                    Circle().trim(from: 0, to: pct).stroke(color, style: StrokeStyle(lineWidth: 11, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack(spacing: -2) {
                        Text("\(result.awarded)").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                        Text("of \(result.available)").font(.system(size: 12)).foregroundStyle(Palette.dim)
                    }
                }
                .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 10) {
                    Text(session.businessComponents == nil ? "\(session.title) · \(set?.sourceLabel ?? "")" : "\(session.title) · mixed topical paper").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.violet)
                    HStack(alignment: .center, spacing: 10) {
                        HankAvatar(size: 32)
                        Text(result.headline).font(.system(size: 19, weight: .bold)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(result.summary).font(.system(size: 13)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
                    if !result.strengths.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(result.strengths.prefix(3), id: \.self) { s in Chip(text: s, color: Palette.green) }
                        }
                    }
                    Text("Long answers are Hank's estimate against the IB markband; your teacher's mark is the real one.")
                        .font(.system(size: 10.5)).foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder var fixesSection: some View {
        if !result.fixes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars").foregroundStyle(Palette.purple)
                    Text("Fix these to win back marks").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(Array(result.fixes.prefix(3).enumerated()), id: \.offset) { i, f in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("\(i + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 20, height: 20).background(Palette.gradient, in: Circle())
                                Text(f.title).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                            }
                            MathText(f.detail, color: Palette.dim).fixedSize(horizontal: false, vertical: true)
                            if let w = f.wrong, !w.isEmpty {
                                MathText("You: \(w)", size: 12, color: Palette.red).fixedSize(horizontal: false, vertical: true)
                            }
                            if let r = f.right, !r.isEmpty {
                                MathText("Scores: \(r)", size: 12, color: Palette.green).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.stroke))
                    }
                }
            }
        }
    }

    var partsHeader: some View {
        HStack {
            Text("Question by question").font(.system(size: 16, weight: .bold)).foregroundStyle(Palette.text)
            Spacer()
            Toggle("Only where I lost marks", isOn: $onlyLost.animation()).toggleStyle(.switch).tint(Palette.purple)
                .font(.system(size: 12))
        }
    }

    func partCard(_ r: BusinessPartResult) -> some View {
        let full = r.awarded >= r.available
        let color = ResultsView.color(Double(r.awarded) / Double(max(r.available, 1)))
        let isEssay = result.essays.contains { $0.label == r.label }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Text(BusinessPart.display(r.label)).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Palette.purple, in: RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prompt(r.label)).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                        Text(topicName(r.label)).font(.system(size: 11)).foregroundStyle(Palette.faint)
                    }
                    Spacer()
                    Text("\(r.awarded)/\(r.available)").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(color)
                }
                if isEssay {
                    Text("Full essay feedback is below.").font(.system(size: 12).italic()).foregroundStyle(Palette.lilac)
                    if let ms = markscheme(r.label) {
                        // Essay markschemes run to pages: tucked away until she wants them.
                        DisclosureGroup {
                            MarkschemeCrops(url: ms.url, regions: ms.regions, title: "(\(r.label)) · official markscheme").padding(.top, 6)
                        } label: {
                            Text("Show the official markscheme").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.purple)
                        }
                        .tint(Palette.purple)
                    }
                } else if session.caseSubject == .economics {
                    // Her own handwriting (cropped from the paper she sent back), Hank's version typeset, and the
                    // IB's markscheme beside them.
                    let mine = reading?.handwritingCrops(for: r.label) ?? []
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 10) {
                            if mine.isEmpty {
                                box("You wrote", r.studentAnswer, Palette.bg2, Palette.dim)
                            } else {
                                PaperCrops(heading: "You wrote", tint: Palette.dim, background: Palette.bg2, url: model.completedURL(session),
                                           crops: mine, zoomTitle: "(\(r.label)) · your answer")
                            }
                            box("What scores", r.correctAnswer, Palette.cardHi, Palette.purple)
                        }
                        if let ms = markscheme(r.label) {
                            MarkschemeCrops(url: ms.url, regions: ms.regions, title: "(\(r.label)) · official markscheme")
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        box("You wrote", r.studentAnswer, Palette.bg2, Palette.dim)
                        box("What scores", r.correctAnswer, Palette.cardHi, Palette.purple)
                    }
                }
                if !isEssay {
                    MathText(r.feedback).fixedSize(horizontal: false, vertical: true)
                    if !full && !r.whyLost.isEmpty {
                        Label { MathText(r.whyLost).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.circle.fill") }
                            .labelStyle(TintedIcon(color: Palette.orange))
                    }
                    if !r.tip.isEmpty {
                        Label { MathText(r.tip).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "lightbulb.fill") }
                            .labelStyle(TintedIcon(color: Palette.purple))
                    }
                }
                Button { model.askHank("Explain part (\(r.label)) of my \(session.caseSubject?.shortName ?? "Business") session \(session.id): why did I get \(r.awarded)/\(r.available), and how would I get full marks?") } label: {
                    Label("Ask Hank about this", systemImage: "bubble.left.and.text.bubble.right")
                }.buttonStyle(GhostButtonStyle(compact: true))
                if let part = set?.parts.first(where: { $0.label == r.label }), session.caseSubject == .business, let bank = model.business {
                    Divider().overlay(Palette.stroke.opacity(0.5))
                    Text("Further reading").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.purple)
                    BusinessReadingLinks(topics: part.topicIds.compactMap { bank.topic($0) })
                }
            }
        }
    }

    func box(_ title: String, _ text: String, _ bg: Color, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10.5, weight: .bold)).foregroundStyle(tint).textCase(.uppercase)
            MathText(text.isEmpty ? "(blank)" : text).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(bg, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// The long-answer feedback: band by strand, caps, labelled sentences and her weakest paragraph moved up a band.
struct EssayFeedbackView: View {
    @Environment(AppModel.self) var model
    var session: StudySession
    var essay: EssayFeedback
    var prompt: String

    static let labels: [(id: String, name: String, color: Color)] = [
        ("knowledge", "Knowledge", Color(red: 0.55, green: 0.55, blue: 0.62)),
        ("application", "Application (uses the case)", Color(red: 0.16, green: 0.52, blue: 0.86)),
        ("analysis", "Analysis (so… which means…)", Color(red: 0.49, green: 0.23, blue: 0.93)),
        ("evaluation", "Evaluation (weighs, judges, limits)", Color(red: 0.13, green: 0.66, blue: 0.40)),
        ("none", "Not earning marks", Color(red: 0.90, green: 0.26, blue: 0.32)),
    ]
    static func color(_ label: String) -> Color { labels.first { $0.id == label }?.color ?? Palette.faint }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(BusinessPart.display(essay.label)).font(.system(size: 18, weight: .heavy)).foregroundStyle(Palette.purple)
                Text("Essay feedback · band \(essay.band)").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.text)
                Spacer()
                Button { model.askHank("I want to redraft my weakest paragraph of part (\(essay.label)) in \(session.caseSubject?.shortName ?? "Business") session \(session.id). Give me one thing to change, then I'll write it and you check it.") } label: {
                    Label("Redraft with Hank", systemImage: "arrow.triangle.2.circlepath")
                }.buttonStyle(PrimaryButtonStyle(compact: true))
            }
            if !prompt.isEmpty { Text(prompt).font(.system(size: 13)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true) }
            if !essay.capsHit.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("What capped this answer", systemImage: "lock.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                        .labelStyle(TintedIcon(color: Palette.red))
                    ForEach(essay.capsHit, id: \.self) { c in Text("· " + c).font(.system(size: 12.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true) }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.red.opacity(0.25)))
            }
            HStack(alignment: .top, spacing: 16) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Band by strand").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                        ForEach(essay.strands, id: \.name) { s in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { Text(s.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text); Spacer(); Chip(text: s.level, color: Palette.purple) }
                                Text(s.comment).font(.system(size: 12)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Against the markscheme").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                        ForEach(essay.pointsHit, id: \.self) { p in
                            Label(p, systemImage: "checkmark.circle.fill").font(.system(size: 12.5)).foregroundStyle(Palette.text).labelStyle(TintedIcon(color: Palette.green))
                        }
                        ForEach(essay.pointsMissed, id: \.self) { p in
                            Label(p, systemImage: "plus.circle.fill").font(.system(size: 12.5)).foregroundStyle(Palette.text).labelStyle(TintedIcon(color: Palette.orange))
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your answer, sentence by sentence").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                    Text("Each sentence is coloured by what it earns. Purple and green are where the top marks are.")
                        .font(.system(size: 12)).foregroundStyle(Palette.dim)
                    HStack(spacing: 12) {
                        ForEach(Self.labels, id: \.id) { l in
                            let n = essay.sentences.filter { $0.label == l.id }.count
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 3).fill(l.color).frame(width: 10, height: 10)
                                Text("\(l.name) · \(n)").font(.system(size: 11)).foregroundStyle(Palette.dim)
                            }
                        }
                    }
                    ForEach(Array(essay.sentences.enumerated()), id: \.offset) { _, s in
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(Self.color(s.label)).frame(width: 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.text).font(.system(size: 13.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                                if !s.note.isEmpty { Text(s.note).font(.system(size: 11.5).italic()).foregroundStyle(Self.color(s.label)) }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .background(Self.color(s.label).opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Your weakest paragraph, one band up", systemImage: "arrow.up.forward.circle.fill").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.text).labelStyle(TintedIcon(color: Palette.purple))
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("You wrote").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Palette.dim).textCase(.uppercase)
                            Text(essay.rewrite.original).font(.system(size: 13)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .topLeading).background(Palette.bg2, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("One band up").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Palette.purple).textCase(.uppercase)
                            Text(essay.rewrite.improved).font(.system(size: 13)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .topLeading).background(Palette.cardHi, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.violet.opacity(0.5)))
                    }
                    Text(essay.rewrite.why).font(.system(size: 12.5).italic()).foregroundStyle(Palette.lilac).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                HankAvatar(size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next time").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Palette.purple).textCase(.uppercase)
                    Text(essay.nextTime).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(14).background(Palette.bg2, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct TintedIcon: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.foregroundStyle(color)
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}
