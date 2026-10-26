import SwiftUI

/// Maths is revised by execution strategy: one row per "move" (Find a max or min, Inverse normal…), holding
/// every past-paper part that needs it, however it's worded. The row shows the giveaway wording up front and
/// keeps the recipe one click away, so she learns to spot the move before she practises it.
struct StrategyRow: View {
    @Environment(AppModel.self) var model
    var strategy: Subtopic
    @State private var hover = false
    @State private var open = false

    var body: some View {
        let st = model.progress.stats(for: strategy.id)
        let count = model.bank?.count(for: strategy.id) ?? 0
        let rc = model.reviewCounts(.subtopic(strategy.id))
        let mixing = model.mix != nil
        let pickable = model.mix?.allows(strategy.id) == true && count > 0
        let picked = model.mix?.picked.contains(strategy.id) == true
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if mixing {
                    Image(systemName: picked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(picked ? Palette.purple : Palette.faint)
                }
                MasterySquare(mastery: st.mastery, size: 16).help(st.mastery.label)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(strategy.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.text)
                        if let p = st.percent { Chip(text: "\(Int(p * 100))%", color: Palette.color(st.mastery)) }
                        if rc.due > 0 && !mixing {
                            Button { model.timeRequestMode = .due; model.timeRequest = .subtopic(strategy.id) } label: {
                                Chip(text: "\(rc.due) due", color: Palette.purple)
                            }.buttonStyle(.plain).help("Due for spaced review")
                        }
                        if rc.mistakes > 0 && !mixing {
                            Button { model.timeRequestMode = .mistakes; model.timeRequest = .subtopic(strategy.id) } label: {
                                Chip(text: "\(rc.mistakes) to fix", color: Palette.orange)
                            }.buttonStyle(.plain).help("Redo the questions you lost marks on")
                        }
                    }
                    if let cues = strategy.cues, !cues.isEmpty {
                        Text("Spot it: " + cues.prefix(3).map { "“\($0)”" }.joined(separator: " · "))
                            .font(.system(size: 11.5)).foregroundStyle(Palette.dim).lineLimit(1)
                    }
                }
                Spacer()
                Text("\(count - rc.unseen)/\(count) done").font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                if !mixing {
                    Button { withAnimation(.snappy) { open.toggle() } } label: {
                        Label(open ? "Hide recipe" : "Recipe", systemImage: "list.number")
                    }
                    .buttonStyle(GhostButtonStyle(compact: true))
                    .help("How to spot this move and the steps to do it")
                    ReviseButton(title: "Drill", style: .primary) { model.timeRequest = .subtopic(strategy.id) }
                        .disabled(count == 0)
                }
            }
            if open && !mixing { recipe.padding(.leading, 28).transition(.opacity) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(picked ? Palette.cardHi : hover || open ? Palette.cardHi.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if pickable { withAnimation(.snappy(duration: 0.15)) { model.mix?.toggle(strategy.id) } } }
        .opacity(mixing && !pickable ? 0.4 : 1)
    }

    var recipe: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cues = strategy.cues, !cues.isEmpty {
                section("Spot it when you see") {
                    Text(cues.map { "“\($0)”" }.joined(separator: "  ·  "))
                        .font(.system(size: 12)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let steps = strategy.steps, !steps.isEmpty {
                section("The recipe") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(i + 1)").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    .frame(width: 18, height: 18).background(Palette.gradient, in: Circle())
                                Text(step).font(.system(size: 12.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 18) {
                if let f = strategy.formula {
                    section("Formula booklet") { Text(f).font(.system(size: 12)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true) }
                }
                if let t = strategy.trap {
                    section("Watch out") { Text(t).font(.system(size: 12)).foregroundStyle(Palette.orange).fixedSize(horizontal: false, vertical: true) }
                }
            }
            if let ref = strategy.ref {
                Text("IB syllabus \(ref)").font(.system(size: 10.5, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.lilac)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.stroke))
    }

    func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Palette.violet).textCase(.uppercase).tracking(0.5)
            content()
        }
    }
}

/// The one-paragraph "how this works" at the top of the Maths page.
struct StrategyIntro: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.max.fill").font(.system(size: 18)).foregroundStyle(Palette.purple)
            VStack(alignment: .leading, spacing: 3) {
                Text("Learn the move, then mix them up").font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                Text("Every past-paper part is grouped by the strategy it needs, whatever the wording: \"greatest area\", \"minimum cost\" and \"least value\" are all one move. Drill a move until it's green, then mix an area to practise spotting which move each question wants, then go exam-style.")
                    .font(.system(size: 12)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.stroke))
    }
}
