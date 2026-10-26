import SwiftUI

/// The same time → question mix → PDF flow as Biology, for Business or Economics (`scope.subject`).
struct BusinessTimeSheet: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) var dismiss
    var scope: BusinessPracticeScope
    @State private var minutes: Double = 30
    @State private var mode: StudyMode = .smart
    @State private var format: BusinessQuestionFormat = .both
    @State private var everyQuestion = false
    @State private var timed = true
    /// Which papers to mix, e.g. "12" or "23"; remembered per subject for next time.
    @AppStorage private var mixPapers: String

    init(scope: BusinessPracticeScope) {
        self.scope = scope
        _mixPapers = AppStorage(wrappedValue: "12", "\(scope.subject.pageKey).mixPapers")
    }
    var caseWord: String { scope.subject == .business ? "case" : "question" }

    var papers: Set<String> {
        let chosen = Set(mixPapers.map(String.init)).intersection(["1", "2", "3"])
        return chosen.isEmpty ? BusinessPracticePlanner.defaultPapers : chosen
    }

    var components: [BusinessPaperComponent] {
        guard let bank = model.caseBank(scope.subject) else { return [] }
        return BusinessPracticePlanner.plan(bank: bank, topics: scope.topicIds, minutes: Int(minutes), format: format,
                                             mode: mode, history: model.businessPracticeHistory(scope.subject), everyQuestion: everyQuestion,
                                             papers: papers)
    }

    /// Turns one paper on or off, always keeping at least one.
    func toggle(_ paper: String) {
        var next = papers
        if next.contains(paper) { next.remove(paper) } else { next.insert(paper) }
        guard !next.isEmpty else { return }
        withAnimation(.snappy) { mixPapers = next.sorted().joined() }
    }

    var paperPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PAPERS TO MIX").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Palette.purple)
            HStack(spacing: 8) {
                ForEach(scope.subject.paperBlurbs, id: \.0) { paper, blurb in
                    let on = papers.contains(paper)
                    Button { toggle(paper) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Paper \(paper)").font(.system(size: 12, weight: .semibold))
                                Text(blurb).font(.system(size: 10.5)).opacity(0.8)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(on ? .white : Palette.lilac)
                        .background(on ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Palette.bg2), in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .help(on && papers.count == 1 ? "Keep at least one paper" : on ? "Leave Paper \(paper) out" : "Add Paper \(paper) questions")
                }
            }
            if papers.contains("3") && scope.subject == .business {
                Text(format == .short
                     ? "Paper 3 comes whole with its 17-mark plan, so it's left out of short-answer papers."
                     : "Paper 3 always comes whole (about 80 min), because its plan pulls the whole case together.")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.dim)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scope.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.purple)
                    Text("How long have you got?").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    Text("One paper with questions from your selected subtopics.").font(.system(size: 12.5)).foregroundStyle(Palette.dim)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").padding(6) }.buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                ForEach([StudyMode.smart, .fresh, .mistakes]) { choice in
                    Button { mode = choice } label: {
                        Label(choice.title, systemImage: choice.icon).font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(10)
                            .foregroundStyle(mode == choice ? .white : Palette.lilac)
                            .background(mode == choice ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Palette.bg2), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }
            Text(mode == .smart ? "Weak answers first, then new questions, balanced across your selected subtopics." : mode.blurb).font(.system(size: 11.5)).foregroundStyle(Palette.dim)
            Picker("Questions", selection: $format) {
                Text("Both").tag(BusinessQuestionFormat.both)
                Text("Short answers").tag(BusinessQuestionFormat.short)
                Text("Essays").tag(BusinessQuestionFormat.essays)
            }.pickerStyle(.segmented)
            paperPicker
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(everyQuestion ? "All" : "\(Int(minutes))").font(.system(size: 60, weight: .heavy, design: .rounded)).foregroundStyle(Palette.text)
                    Text(everyQuestion ? "questions" : "minutes").font(.system(size: 18, weight: .medium)).foregroundStyle(Palette.dim)
                }
                Slider(value: $minutes, in: 5...120, step: 5).tint(Palette.purple).disabled(everyQuestion)
                HStack(spacing: 8) {
                    ForEach([10, 15, 20, 30, 45, 60, 90], id: \.self) { preset in
                        Button("\(preset) min") { minutes = Double(preset); everyQuestion = false }
                            .buttonStyle(GhostButtonStyle(compact: true))
                            .overlay(Capsule().strokeBorder(Int(minutes) == preset && !everyQuestion ? Palette.purple : .clear, lineWidth: 1.5))
                    }
                }
            }.padding(18).background(Palette.bg2, in: RoundedRectangle(cornerRadius: 16))
            Toggle("Every question in this selection", isOn: $everyQuestion).toggleStyle(.switch).tint(Palette.purple)
            Toggle("Time me", isOn: $timed).toggleStyle(.switch).tint(Palette.purple)
            if let bank = model.caseBank(scope.subject) {
                let selection = components
                let sets = BusinessPracticePlanner.selectedSets(bank: bank, components: selection)
                let count = sets.reduce(0) { $0 + $1.parts.count }
                let suggested = BusinessPracticePlanner.estimatedMinutes(bank: bank, components: selection)
                let included = Set(sets.map(\.paper))
                Text(sets.isEmpty ? "No questions match this mode yet. Try Smart review, another question type or another paper." :
                     "\(count) parts · \(sets.reduce(0) { $0 + $1.marks }) marks · \(BusinessPracticePlanner.papersTitle(included)) · \(sets.count) \(caseWord)\(sets.count == 1 ? "" : "s") · about \(suggested) min, including reading.")
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(sets.isEmpty ? Palette.orange : Palette.purple)
                if scope.subject == .business, !sets.isEmpty, !everyQuestion, format != .short, papers.contains("3"), !included.contains("3") {
                    let alone = BusinessPracticePlanner.plan(bank: bank, topics: scope.topicIds, minutes: 1, format: format, mode: mode,
                                                             history: model.businessPracticeHistory(scope.subject), everyQuestion: false, papers: ["3"])
                    let need = BusinessPracticePlanner.estimatedMinutes(bank: bank, components: alone)
                    Text(alone.isEmpty ? "No Paper 3 matches this mode yet, so this mix leaves it out."
                         : "A whole Paper 3 needs about \(need) min, so it didn't fit. Choose \(Int(ceil(Double(need) / 5)) * 5) min or more to include one.")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.dim)
                }
                if !sets.isEmpty, !everyQuestion, suggested > Int(minutes) {
                    Text("The shortest complete question needs about \(suggested) minutes. Your timer will use that time.")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.dim)
                }
                Text("Each \(caseWord) stays with its \(scope.subject == .business ? "tables" : "texts, tables") and exact markscheme. Earlier parts needed for a calculation are included too.")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                HStack {
                    Spacer()
                    Button {
                        if model.buildBusinessPractice(scope, minutes: Int(minutes), format: format, mode: mode, everyQuestion: everyQuestion, timed: timed, papers: papers) != nil { dismiss() }
                    } label: {
                        Label(everyQuestion ? "Make the full set" : "Make my \(Int(minutes))-minute paper", systemImage: "doc.badge.plus")
                    }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction).disabled(sets.isEmpty)
                }
            }
        }.padding(26).frame(width: 640).background(.white)
    }
}
