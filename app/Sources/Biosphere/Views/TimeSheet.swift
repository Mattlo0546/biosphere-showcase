import SwiftUI

/// Step 2 of revising: she's picked what to revise — now, how long has she got?
struct TimeSheet: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) var dismiss
    var scope: RevisionScope
    @State private var minutes: Double = 30
    @State private var hankPicks = false
    @State private var everyQuestion = false
    @State private var focus = ""
    @State private var mode: StudyMode = .smart
    @State private var timed = true
    @AppStorage("revision.questionFormat") private var format: QuestionFormat = .both

    let presets: [Double] = [10, 15, 20, 30, 45, 60, 90]

    var body: some View {
        let syl = model.bank!.syllabus
        let strategies = syl.isStrategyBank
        let format = strategies ? QuestionFormat.both : format     // Maths has no multiple choice
        let available = model.bank!.pool(for: scope, format: format)
        let counts = model.reviewCounts(scope, format: format)
        let modeIsEmpty = switch mode {
        case .smart: available.isEmpty
        case .fresh: counts.unseen == 0
        case .mistakes: counts.mistakes == 0
        case .due: counts.due == 0
        }
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scope.title(in: syl)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.purple)
                    Text("How long have you got?").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    Text("\(available.count) past-paper questions to choose from" + (scope.spansTopics ? " · 90 minutes is one full Biology paper" : ""))
                        .font(.system(size: 12.5)).foregroundStyle(Palette.dim)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Palette.faint).padding(6) }.buttonStyle(.plain)
            }

            if strategies {
                Text(scope.subtitle(in: syl) + (scope.isExamStyle ? "." : ". Long questions are cut down to the parts that use these moves (plus any part they build on)."))
                    .font(.system(size: 11.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
            } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Question type").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                Picker("Question type", selection: $format) {
                    ForEach(QuestionFormat.allCases) { f in Text(f.title).tag(f) }
                }
                .pickerStyle(.segmented)
                Text(available.isEmpty ? "No questions of this type available for this topic." : format.blurb)
                    .font(.system(size: 11.5)).foregroundStyle(available.isEmpty ? Palette.orange : Palette.dim)
            }
            }

            modePicker(counts)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(everyQuestion ? "All" : "\(Int(minutes))").font(.system(size: 60, weight: .heavy, design: .rounded))
                        .foregroundStyle(everyQuestion ? Palette.faint : Palette.text).contentTransition(.numericText())
                    Text(everyQuestion ? "questions" : "minutes").font(.system(size: 18, weight: .medium)).foregroundStyle(Palette.dim)
                }
                Slider(value: $minutes.animation(), in: 5...120, step: 5).tint(Palette.purple).disabled(everyQuestion)
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { p in
                        Button("\(Int(p)) min") { withAnimation { minutes = p; everyQuestion = false } }
                            .buttonStyle(GhostButtonStyle(compact: true))
                            .overlay(Capsule().strokeBorder(minutes == p && !everyQuestion ? Palette.purple : .clear, lineWidth: 1.5))
                    }
                }
            }
            .padding(18)
            .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 10) {
                if case .subtopic = scope {
                    Toggle(isOn: $everyQuestion.animation()) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(strategies ? "Every question that uses this strategy" : "Every question of this type on this subtopic").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                            Text("One big PDF with all \(available.count) — no time limit.").font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                        }
                    }
                    .disabled(hankPicks)
                }
                Toggle(isOn: $hankPicks.animation()) {
                    HStack(spacing: 8) {
                        HankAvatar(size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Let Hank pick the questions").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                            Text(model.claude.loggedIn ? "Claude reads your tracker and past mistakes and chooses on purpose (~1 min)."
                                                       : "Sign in to Claude in Settings to use this.")
                                .font(.system(size: 11.5)).foregroundStyle(model.claude.loggedIn ? Palette.faint : Palette.orange)
                        }
                    }
                }
                .disabled(!model.claude.loggedIn || everyQuestion)
                if hankPicks {
                    TextField("Anything specific? e.g. \"data-based questions\" or \"the bits I keep getting wrong\"", text: $focus)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.stroke))
                }
            }
            .toggleStyle(.switch).tint(Palette.purple)

            Toggle(isOn: $timed) {
                Text("Time me").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
            }
            .toggleStyle(.switch).tint(Palette.purple)

            Label("Unsure of an answer? Add a * or star beside it and Hank will include it in your review.", systemImage: "star")
                .font(.system(size: 11.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(!timed ? "No timer: the minutes only decide how many questions you get." :
                     everyQuestion ? "The timer counts up from the suggested time." : "Your timer will be set to \(Int(minutes)) minutes.")
                    .font(.system(size: 12)).foregroundStyle(Palette.faint)
                Spacer()
                Button {
                    model.mix = nil
                    let m = Int(minutes)
                    let chosenFormat = format
                    if hankPicks {
                        dismiss()
                        let modeNote = mode == .smart ? "" : " Mode: \(mode.title) — \(mode.blurb)"
                        Task { await model.planWithHank(scope, minutes: m, focus: focus + modeNote, format: chosenFormat, timed: timed) }
                    } else {
                        model.build(scope, minutes: m, everyQuestion: everyQuestion, mode: mode, format: chosenFormat, timed: timed)
                        dismiss()
                    }
                } label: {
                    Label(everyQuestion ? "Make the full set" : "Make my \(Int(minutes))-minute paper", systemImage: hankPicks ? "sparkles" : "doc.badge.plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(available.isEmpty || (!everyQuestion && modeIsEmpty))
            }
        }
        .padding(26)
        .frame(width: 600)
        .background(.white)
        .onAppear {
            mode = model.timeRequestMode; model.timeRequestMode = .smart
            if scope.spansTopics { minutes = 90 }   // her own mix across topics = a full paper
        }
        .onChange(of: format) {
            let c = model.reviewCounts(scope, format: format)
            if (mode == .fresh && c.unseen == 0) || (mode == .mistakes && c.mistakes == 0) || (mode == .due && c.due == 0) {
                mode = .smart
            }
        }
    }

    func modePicker(_ c: (mistakes: Int, due: Int, unseen: Int, mistakeMinutes: Double, dueMinutes: Double)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(StudyMode.allCases) { m in
                    let count: Int? = switch m { case .smart: nil; case .fresh: c.unseen; case .mistakes: c.mistakes; case .due: c.due }
                    let disabled = (count ?? 1) == 0
                    Button { withAnimation(.snappy) { mode = m; if m != .smart && m != .fresh { everyQuestion = false } } } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Image(systemName: m.icon).font(.system(size: 12, weight: .semibold))
                                Text(m.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            }
                            Text(count.map { "\($0) question\($0 == 1 ? "" : "s")" } ?? "recommended")
                                .font(.system(size: 10.5)).opacity(0.8)
                        }
                        .foregroundStyle(mode == m ? .white : (disabled ? Palette.faint : Palette.lilac))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(mode == m ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Palette.bg2), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                }
            }
            Text(mode.blurb + (mode == .mistakes && c.mistakes > 0 ? " About \(Int(c.mistakeMinutes.rounded())) min in total." :
                               mode == .due && c.due > 0 ? " About \(Int(c.dueMinutes.rounded())) min in total." : ""))
                .font(.system(size: 11.5)).foregroundStyle(Palette.dim)
        }
    }
}
