import SwiftUI

/// Floats at the bottom of the Topics page while she ticks subtopics to mix into one paper.
/// Topic first, then time: "How long?" opens the usual time sheet for her mix.
struct MixBar: View {
    @Environment(AppModel.self) var model

    var body: some View {
        if let mix = model.mix, let bank = model.bank {
            let picked = mix.picked.sorted()
            let questions = bank.pool(for: mix.picked).count
            let strategies = bank.syllabus.isStrategyBank
            let noun = strategies ? "strategies" : "subtopics"
            HStack(spacing: 14) {
                HankAvatar(size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline(mix, bank: bank)).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.text)
                    if picked.isEmpty {
                        Text(mix.topic == nil ? "Tick \(noun) from any topic: you'll get one paper that mixes them all, like the real exam."
                                              : "Tick the \(noun) you want, then choose how long you've got.")
                            .font(.system(size: 11.5)).foregroundStyle(Palette.dim)
                    } else {
                        // Maths shows strategy names, never ids: on a mix she should be spotting the move herself.
                        Text((strategies ? picked.compactMap { bank.syllabus.subtopic($0)?.name } : picked).joined(separator: " · ")
                             + "  ·  \(questions) past-paper questions")
                            .font(.system(size: 11.5, design: strategies ? .default : .monospaced)).foregroundStyle(Palette.lilac).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                if mix.topic == nil {
                    Button(action: pickWeak) { Label("My red & orange", systemImage: "wand.and.stars") }
                        .buttonStyle(GhostButtonStyle(compact: true))
                        .help("Tick every \(strategies ? "strategy" : "subtopic") you're still working on")
                }
                Button("Cancel") { model.mix = nil }
                    .buttonStyle(GhostButtonStyle(compact: true))
                    .keyboardShortcut(.cancelAction)
                Button { model.timeRequest = mix.scope } label: { Label("How long?", systemImage: "arrow.right") }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(questions == 0)
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.violet.opacity(0.5)))
            .shadow(color: Palette.purple.opacity(0.18), radius: 16, y: 4)
            .frame(maxWidth: 1036)
            .padding(.horizontal, 32).padding(.bottom, 16)
        }
    }

    func headline(_ mix: SubtopicMix, bank: Bank) -> String {
        let n = mix.picked.count
        let what = mix.topic.map { "Mixing within " + RevisionScope.topic($0).title(in: bank.syllabus) } ?? "Building your own paper"
        let noun = bank.syllabus.isStrategyBank ? (n == 1 ? "strategy" : "strategies") : (n == 1 ? "subtopic" : "subtopics")
        return n == 0 ? what : "\(what) · \(n) \(noun)"
    }

    /// Red and orange squares, plus anything with questions she has tried but not mastered yet.
    func pickWeak() {
        guard let bank = model.bank else { return }
        let weak = bank.syllabus.slSubtopics.map(\.id).filter {
            let m = model.progress.stats(for: $0).mastery
            return (m == .red || m == .orange) && bank.count(for: $0) > 0
        }
        guard !weak.isEmpty else { model.say("No red or orange squares yet. Tick any subtopics you like!"); return }
        withAnimation(.snappy) { model.mix?.picked.formUnion(weak) }
    }
}

/// "Select all" / "Clear" for a topic or theme while she's picking subtopics.
struct MixSelectAll: View {
    @Environment(AppModel.self) var model
    var ids: [String]

    var body: some View {
        let usable = ids.filter { model.mix?.allows($0) == true && (model.bank?.count(for: $0) ?? 0) > 0 }
        let all = !usable.isEmpty && Set(usable).isSubset(of: model.mix?.picked ?? [])
        Button {
            withAnimation(.snappy) {
                if all { model.mix?.picked.subtract(usable) } else { model.mix?.picked.formUnion(usable) }
            }
        } label: { Label(all ? "Clear" : "Select all", systemImage: all ? "square" : "checkmark.square") }
        .buttonStyle(GhostButtonStyle(compact: true))
        .disabled(usable.isEmpty)
    }
}
