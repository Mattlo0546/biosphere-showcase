import SwiftUI

/// Exam prep: a timed two-hour plan on the left, the material for the chosen block on the right.
/// She presses Start once; the purple block follows the clock and Hank pings her when it's time to move on.
struct ExamPrepView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        if let pack = model.exam.pack {
            GeometryReader { g in
                if g.size.width >= 860 {
                    HStack(spacing: 0) {
                        ScrollView { ExamPlanColumn(pack: pack).padding(.horizontal, 18).padding(.top, 56).padding(.bottom, 30) }
                            .frame(width: 300)
                            .background(Palette.bg2)
                        Divider().overlay(Palette.stroke)
                        ScrollViewReader { proxy in
                            ScrollView {
                                ExamMaterial(pack: pack).id("top")
                                    .padding(.horizontal, 32).padding(.top, 56).padding(.bottom, 40)
                                    .frame(maxWidth: 820).frame(maxWidth: .infinity)
                            }
                            .onChange(of: model.exam.selected) { proxy.scrollTo("top", anchor: .top) }
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ExamPlanColumn(pack: pack)
                            ExamMaterial(pack: pack)
                        }
                        .padding(.horizontal, 24).padding(.top, 56).padding(.bottom, 40)
                    }
                }
            }
            .onAppear {
                UserDefaults.standard.set(true, forKey: "exam.opened")
                if model.exam.selected == nil { model.exam.selected = model.exam.current(model.timer)?.id ?? pack.blocks.first?.id }
            }
        } else {
            VStack(spacing: 10) {
                HankAvatar(size: 54, mood: .surprised)
                Text("The exam pack didn’t load.").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                Text("Quit and reopen Biosphere. If it’s still missing, tell Matt.").font(.system(size: 12.5)).foregroundStyle(Palette.dim)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: the plan

struct ExamPlanColumn: View {
    @Environment(AppModel.self) var model
    var pack: ExamPack

    var body: some View {
        let exam = model.exam, timer = model.timer
        let on = exam.isOn(timer)
        let now = exam.current(timer)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HankAvatar(size: 34, mood: on && timer.running ? .happy : .idle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your 2 hours").font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    Text(on ? "Block \(now.map { pack.index(of: $0) + 1 } ?? 1) of \(pack.blocks.count)" : "\(pack.blocks.count) blocks, in order")
                        .font(.system(size: 11.5)).foregroundStyle(Palette.dim)
                }
            }
            if on {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: Double(min(max(timer.elapsed, 0), timer.total)), total: Double(max(timer.total, 1)))
                        .tint(Palette.purple)
                    Text(timer.remaining >= 0 ? "\(StudyTimer.format(timer.remaining)) left" : "Time’s up. Brilliant work.")
                        .font(.system(size: 11.5, weight: .semibold)).monospacedDigit().foregroundStyle(Palette.dim)
                }
                Button { timer.running ? timer.pause() : exam.start(timer, announce: announce) } label: {
                    Label(timer.running ? "Pause" : "Resume", systemImage: timer.running ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GhostButtonStyle())
            } else {
                Button { exam.start(timer, announce: announce) } label: {
                    Label("Start my 2 hours", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .help("Starts a 2-hour timer. The plan moves on by itself and Hank tells you when.")
            }
            VStack(spacing: 4) {
                ForEach(pack.blocks) { b in row(b, number: pack.index(of: b) + 1, now: now?.id == b.id) }
            }
            .padding(.top, 4)
            Divider().overlay(Palette.stroke).padding(.vertical, 2)
            dayRow
            if !exam.done.isEmpty || on {
                Button("Start over") { withAnimation(.snappy) { exam.startOver(timer) } }
                    .buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(Palette.faint)
                    .help("Stops the timer and clears your ticks")
            }
        }
    }

    func announce(_ b: ExamBlock) {
        NSSound(named: "Glass")?.play()
        model.notify("Next: \(b.title)", "\(b.minutes) minutes. \(b.goal)")
    }

    func row(_ b: ExamBlock, number: Int, now: Bool) -> some View {
        let exam = model.exam
        let selected = exam.selected == b.id, done = exam.done.contains(b.id)
        return Button { withAnimation(.snappy) { exam.selected = b.id } } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(now ? AnyShapeStyle(.white.opacity(0.25)) : (done ? AnyShapeStyle(Palette.purple) : AnyShapeStyle(Palette.cardHi)))
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Text("\(number)").font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundStyle(now ? .white : Palette.lilac)
                    }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(b.title).font(.system(size: 12.5, weight: now || selected ? .semibold : .medium))
                        .foregroundStyle(now ? .white : (done ? Palette.dim : Palette.text))
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(exam.clock(b, model.timer) ?? "\(b.minutes) min")
                        .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(now ? .white.opacity(0.85) : Palette.faint)
                }
                Spacer(minLength: 0)
                if now { Text("Now").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(now ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(selected ? Color.white : Color.clear),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(selected && !now ? Palette.violet.opacity(0.5) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(done ? "Mark as not done" : "Mark as done") {
                if done { exam.done.remove(b.id) } else { exam.done.insert(b.id) }
            }
        }
    }

    var dayRow: some View {
        let selected = model.exam.selected == "day"
        return Button { withAnimation(.snappy) { model.exam.selected = "day" } } label: {
            HStack(spacing: 10) {
                Image(systemName: "checklist").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.lilac).frame(width: 24)
                Text("Before you walk in").font(.system(size: 12.5, weight: selected ? .semibold : .medium)).foregroundStyle(Palette.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(selected ? Palette.violet.opacity(0.5) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: the material for one block

struct ExamMaterial: View {
    @Environment(AppModel.self) var model
    var pack: ExamPack

    var body: some View {
        let id = model.exam.selected
        if id == "day" {
            dayChecklist
        } else if let b = pack.blocks.first(where: { $0.id == id }) ?? pack.blocks.first {
            block(b)
        }
    }

    func block(_ b: ExamBlock) -> some View {
        let n = pack.index(of: b) + 1
        let isLast = n == pack.blocks.count
        let isNow = model.exam.current(model.timer)?.id == b.id
        return VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Block \(n) of \(pack.blocks.count) · \(b.minutes) minutes\(model.exam.clock(b, model.timer).map { " · \($0)" } ?? "")")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.lilac)
                Text(b.title).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(b.goal).font(.system(size: 13.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
            }
            if n == 1 && !model.exam.isOn(model.timer) {
                HStack(spacing: 10) {
                    HankAvatar(size: 30, mood: .happy)
                    Text(pack.subtitle).font(.system(size: 12.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.cardHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Do this").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                    ExamSteps(items: b.steps)
                    if let check = b.check {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "questionmark.bubble.fill").foregroundStyle(Palette.violet)
                            (Text("Check yourself: ").bold() + Text(check))
                                .font(.system(size: 12.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    HStack(spacing: 10) {
                        if let prompt = b.hank {
                            Button { model.openHank(suggestionTitle: "Quiz me: \(b.title)", prompt: prompt) } label: {
                                HStack(spacing: 6) { HankAvatar(size: 16, animated: false); Text("Quiz me with Hank") }
                            }
                            .buttonStyle(GhostButtonStyle(compact: true))
                            .help("Opens Hank with a quiz ready to send")
                        }
                        Spacer()
                        if !isLast || !model.exam.done.contains(b.id) {
                            Button {
                                withAnimation(.snappy) { model.exam.finish(b) }
                                if isLast { model.say("That’s the two hours done. Rest up. You’ve got this.") }
                            } label: {
                                Label(isLast ? "Done" : "Done · next block", systemImage: isLast ? "checkmark" : "arrow.right")
                            }
                            .buttonStyle(PrimaryButtonStyle(compact: true))
                            .help(isNow ? "Tick this block and move on" : "Tick this block")
                        }
                    }
                }
            }
            ForEach(b.sections, id: \.self) { sid in
                if let s = pack.section(sid) { ExamSectionView(section: s) }
            }
            if b.id == "recall" {
                ExamSectionView(section: ExamSection(id: "day", title: "Before you walk in", subtitle: nil, icon: "checklist",
                                                     cards: [ExamCard(title: "Read this once more on the morning of the exam",
                                                                      items: [ExamItem(type: .bullets, items: pack.onTheDay)])]))
            }
        }
    }

    var dayChecklist: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("On the day").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.lilac)
                Text("Before you walk in").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                Text("Seven things to read once more on the way.").font(.system(size: 13.5)).foregroundStyle(Palette.dim)
            }
            Card { ExamSteps(items: pack.onTheDay) }
            HStack(spacing: 10) {
                HankAvatar(size: 30, mood: .happy)
                Text("You’ve done the work. Read the question twice, then trust your plan.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
            }
        }
    }
}

struct ExamSectionView: View {
    var section: ExamSection

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let icon = section.icon { Image(systemName: icon).foregroundStyle(Palette.purple).font(.system(size: 15, weight: .semibold)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
                    if let s = section.subtitle { Text(s).font(.system(size: 12)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .padding(.top, 6)
            ForEach(Array(section.cards.enumerated()), id: \.offset) { _, card in
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                            if let s = card.subtitle { Text(s).font(.system(size: 11.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true) }
                        }
                        ForEach(Array(card.items.enumerated()), id: \.offset) { _, item in ExamItemView(item: item) }
                    }
                }
            }
        }
    }
}

// MARK: items

/// Inline Markdown (**bold**, *italic*) for the pack's short strings.
func examText(_ s: String) -> Text {
    let a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    return Text(a)
}

struct ExamItemView: View {
    var item: ExamItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = item.title, item.type != .tip {
                Text(t).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.lilac)
            }
            content
        }
    }

    @ViewBuilder var content: some View {
        switch item.type {
        case .text:
            examText(item.text ?? "").font(.system(size: 13)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
        case .bullets: ExamBullets(items: item.items ?? [])
        case .steps: ExamSteps(items: item.items ?? [])
        case .formulas: ExamFormulas(formulas: item.formulas ?? [])
        case .table: ExamTable(headers: item.headers ?? [], rows: item.rows ?? [])
        case .ladder: ExamLadder(lines: item.lines ?? [])
        case .grid: ExamGrid(columns: item.columns ?? [], rows: item.rowLabels ?? [], cells: item.cells ?? [])
        case .letters: ExamLetters(letters: item.letters ?? [])
        case .tree: if let t = item.tree { DecisionTreeView(tree: t) }
        case .tip: ExamTip(title: item.title, text: item.text ?? "")
        case .flash: FlashDeck(cards: item.cards ?? [])
        case .prompts: ExamPrompts(prompts: item.prompts ?? [])
        case .myFixes: MyFixes()
        }
    }
}

struct ExamBullets: View {
    var items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Palette.violet).frame(width: 5, height: 5).offset(y: -2)
                    examText(s).font(.system(size: 13)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct ExamSteps: View {
    var items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("\(i + 1)").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .frame(width: 19, height: 19).background(Palette.gradient, in: Circle())
                    examText(s).font(.system(size: 13)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct ExamTip: View {
    var title: String?
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "lightbulb.fill").foregroundStyle(Palette.purple).font(.system(size: 12.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(title ?? "Exam tip").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.lilac)
                examText(text).font(.system(size: 12.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .leading) { Rectangle().fill(Palette.violet).frame(width: 3).clipShape(Capsule()).padding(.vertical, 8) }
    }
}

struct ExamFormulas: View {
    var formulas: [ExamItem.Formula]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(formulas.enumerated()), id: \.offset) { i, f in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(f.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
                            .frame(width: 170, alignment: .leading)
                        Text(f.formula).font(.system(size: 12.5, weight: .medium, design: .rounded)).foregroundStyle(Palette.lilac)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Palette.cardHi, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let note = f.note {
                        examText(note).font(.system(size: 11.5)).foregroundStyle(Palette.dim)
                            .padding(.leading, 182).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 7)
                if i < formulas.count - 1 { Divider().overlay(Palette.stroke) }
            }
        }
    }
}

struct ExamTable: View {
    var headers: [String]
    var rows: [[String]]
    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 0) {
            if !headers.isEmpty {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                        Text(h).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.lilac).textCase(.uppercase)
                    }
                }
                .padding(.bottom, 6)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Divider().overlay(Palette.stroke).gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { c, cell in
                        let text = examText(cell).font(.system(size: 12.5, weight: c == 0 ? .semibold : .regular))
                            .foregroundStyle(c == 0 ? Palette.text : Palette.dim)
                        if longest(c) <= 14 {
                            text.fixedSize()
                        } else {
                            text.fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: c == 0 ? 190 : .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.vertical, 7)
            }
        }
    }
}

extension ExamTable {
    /// Characters in a column's longest cell (header included).
    func longest(_ c: Int) -> Int {
        ((headers.indices.contains(c) ? [headers[c]] : []) + rows.compactMap { $0.indices.contains(c) ? $0[c] : nil })
            .map(\.count).max() ?? 0
    }
}

/// A statement drawn as a "tree": operations down the left, result lines highlighted.
struct ExamLadder: View {
    var lines: [ExamItem.Line]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                let result = l.op == "="
                let step = Int(l.op) != nil
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        if i < lines.count - 1 {
                            Rectangle().fill(Palette.stroke).frame(width: 2).offset(y: 18)
                        }
                        Text(l.op.isEmpty ? "•" : l.op)
                            .font(.system(size: step ? 12 : 15, weight: .bold, design: .rounded))
                            .foregroundStyle(result || step ? .white : Palette.lilac)
                            .frame(width: 26, height: 26)
                            .background(result || step ? AnyShapeStyle(Palette.gradient) : AnyShapeStyle(Palette.cardHi), in: Circle())
                    }
                    .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.label).font(.system(size: 13, weight: result || step ? .bold : .semibold))
                            .foregroundStyle(result ? Palette.purple : Palette.text)
                        if let n = l.note {
                            examText(n).font(.system(size: 11.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(result ? Palette.cardHi : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .padding(.vertical, 2)
            }
        }
    }
}

/// A 2×2 matrix with column headings across the top and row labels down the side (SWOT, Ansoff, BCG).
struct ExamGrid: View {
    var columns: [String]
    var rows: [String]
    var cells: [ExamItem.Cell]
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 96, height: 1)
                ForEach(Array(columns.enumerated()), id: \.offset) { _, c in
                    Text(c).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.lilac).textCase(.uppercase)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { r, label in
                HStack(spacing: 8) {
                    Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.lilac)
                        .multilineTextAlignment(.trailing).frame(width: 96, alignment: .trailing)
                    ForEach(0..<columns.count, id: \.self) { c in
                        let i = r * columns.count + c
                        if i < cells.count { cell(cells[i], strong: (r + c) % 2 == 0) }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func cell(_ c: ExamItem.Cell, strong: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(c.title).font(.system(size: 13.5, weight: .bold, design: .rounded)).foregroundStyle(Palette.purple)
            examText(c.text).font(.system(size: 11.5)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(strong ? Palette.cardHi : Palette.bg2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Palette.stroke))
    }
}

/// Acronyms (PEEL, STEEPLE, the 7Ps): one big letter per line.
struct ExamLetters: View {
    var letters: [ExamItem.Letter]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(letters.enumerated()), id: \.offset) { _, l in
                HStack(alignment: .top, spacing: 12) {
                    Text(l.letter).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .frame(width: 32, height: 32).background(Palette.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l.word).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.text)
                        examText(l.text).font(.system(size: 12.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// The worked decision tree, drawn the way the exam wants it: square, branches, circles, EVs, // on the losers.
struct DecisionTreeView: View {
    var tree: DecisionTree
    private let rowH: CGFloat = 24, gap: CGFloat = 16

    var body: some View {
        let height = CGFloat(tree.options.reduce(0) { $0 + $1.outcomes.count }) * rowH + CGFloat(max(tree.options.count - 1, 0)) * gap + 16
        VStack(alignment: .leading, spacing: 12) {
            if let q = tree.question { examText(q).font(.system(size: 12.5)).foregroundStyle(Palette.dim).fixedSize(horizontal: false, vertical: true) }
            Canvas { ctx, size in draw(ctx, size) }
                .frame(height: height)
                .frame(maxWidth: 640)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(tree.options.enumerated()), id: \.offset) { _, o in
                    let best = o.name == tree.best?.name
                    let sum = o.outcomes.map { "\(DecisionTree.number($0.probability)) × \(DecisionTree.number($0.value))" }.joined(separator: " + ")
                    (Text("\(o.name): ").bold() + Text("EV = \(sum) = \(DecisionTree.number(o.expectedValue)). Net = \(DecisionTree.number(o.expectedValue)) − \(DecisionTree.number(o.cost)) = ")
                     + Text("\(DecisionTree.number(o.netGain)) \(tree.unit)").bold())
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(best ? Palette.purple : Palette.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let b = tree.best {
                    Text("Choose \(b.name.components(separatedBy: ":").first ?? b.name): the highest expected net gain.")
                        .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Palette.text)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width
        let squareX: CGFloat = 14, circleX = w * 0.42, endX = w * 0.58
        let line = GraphicsContext.Shading.color(Palette.violet)
        // Outcome labels on the right, then each circle in the middle of its outcomes.
        var y: CGFloat = 8
        var circles: [(CGFloat, DecisionTree.Option)] = []
        for o in tree.options {
            let mid = y + CGFloat(o.outcomes.count) * rowH / 2
            for (k, out) in o.outcomes.enumerated() {
                let oy = y + CGFloat(k) * rowH + rowH / 2
                var p = Path()
                p.move(to: CGPoint(x: circleX, y: mid))
                p.addLine(to: CGPoint(x: endX, y: oy))
                ctx.stroke(p, with: line, lineWidth: 1.2)
                ctx.draw(Text("\(out.label) \(DecisionTree.number(out.probability))").font(.system(size: 10.5)).foregroundColor(Palette.dim),
                         at: CGPoint(x: endX + 6, y: oy), anchor: .leading)
                ctx.draw(Text("\(DecisionTree.number(out.value))").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundColor(Palette.text),
                         at: CGPoint(x: w - 4, y: oy), anchor: .trailing)
            }
            circles.append((mid, o))
            y += CGFloat(o.outcomes.count) * rowH + gap
        }
        let squareY = ((circles.first?.0 ?? 0) + (circles.last?.0 ?? 0)) / 2
        let trunkX = squareX + 30
        var trunk = Path()
        trunk.move(to: CGPoint(x: squareX + 10, y: squareY)); trunk.addLine(to: CGPoint(x: trunkX, y: squareY))
        trunk.move(to: CGPoint(x: trunkX, y: circles.first?.0 ?? squareY)); trunk.addLine(to: CGPoint(x: trunkX, y: circles.last?.0 ?? squareY))
        ctx.stroke(trunk, with: line, lineWidth: 1.2)
        for (cy, o) in circles {
            let best = o.name == tree.best?.name
            var p = Path()
            p.move(to: CGPoint(x: trunkX, y: cy))
            p.addLine(to: CGPoint(x: circleX - 8, y: cy))
            ctx.stroke(p, with: line, lineWidth: best ? 2.2 : 1.2)
            if !best {   // the exam's "//" through a rejected branch
                let mx = trunkX + 22
                for dx in [-3.0, 3.0] {
                    var s = Path()
                    s.move(to: CGPoint(x: mx + dx - 3, y: cy + 6)); s.addLine(to: CGPoint(x: mx + dx + 3, y: cy - 6))
                    ctx.stroke(s, with: .color(Palette.purple), lineWidth: 1.6)
                }
            }
            ctx.draw(Text("\(o.name.components(separatedBy: ":").first ?? o.name) · cost \(DecisionTree.number(o.cost))")
                        .font(.system(size: 10.5, weight: .semibold)).foregroundColor(best ? Palette.purple : Palette.dim),
                     at: CGPoint(x: trunkX + 40, y: cy - 9), anchor: .leading)
            ctx.fill(Path(ellipseIn: CGRect(x: circleX - 8, y: cy - 8, width: 16, height: 16)), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: circleX - 8, y: cy - 8, width: 16, height: 16)), with: line, lineWidth: 1.6)
            ctx.draw(Text("EV \(DecisionTree.number(o.expectedValue))").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundColor(Palette.lilac),
                     at: CGPoint(x: circleX - 12, y: cy + 10), anchor: .trailing)
        }
        let sq = CGRect(x: squareX - 10, y: squareY - 10, width: 20, height: 20)
        ctx.fill(Path(sq), with: .color(Palette.purple))
    }
}

/// Cover-and-recall flashcards. "Again" sends a card to the back of the pile until she gets it.
struct FlashDeck: View {
    var cards: [ExamItem.Flash]
    @State private var queue: [Int] = []
    @State private var revealed = false
    @State private var missed: Set<Int> = []
    @State private var started = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let i = queue.first {
                HStack {
                    Text("\(cards.count - queue.count + 1) of \(cards.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.faint)
                    Spacer()
                    if !missed.isEmpty { Text("\(missed.count) to repeat").font(.system(size: 11)).foregroundStyle(Palette.faint) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    examText(cards[i].q).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if revealed {
                        Divider().overlay(Palette.stroke)
                        examText(cards[i].a).font(.system(size: 13.5)).foregroundStyle(Palette.lilac).fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.stroke))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { revealed = true } }
                HStack(spacing: 8) {
                    if revealed {
                        Button { next(i, gotIt: false) } label: { Label("Again", systemImage: "arrow.uturn.left") }
                            .buttonStyle(GhostButtonStyle(compact: true))
                            .help("Puts this card at the back so it comes round again")
                        Button { next(i, gotIt: true) } label: { Label("Got it", systemImage: "checkmark") }
                            .buttonStyle(PrimaryButtonStyle(compact: true))
                    } else {
                        Text("Say the answer out loud first, then check.").font(.system(size: 11.5).italic()).foregroundStyle(Palette.faint)
                        Spacer()
                        Button { withAnimation(.snappy) { revealed = true } } label: { Label("Show answer", systemImage: "eye") }
                            .buttonStyle(PrimaryButtonStyle(compact: true))
                    }
                }
            } else {
                HStack(spacing: 12) {
                    HankAvatar(size: 30, mood: started ? .happy : .idle, animated: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(started ? "All \(cards.count) done\(missed.isEmpty ? ", every one first time. Superb." : ". \(cards.count - missed.count) right first time.")"
                                     : "\(cards.count) flashcards")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                        Text(started ? (missed.isEmpty ? "Locked in." : "Go again to make the tricky ones stick.") : "Cover, recall, check. The fastest way to remember.")
                            .font(.system(size: 11.5)).foregroundStyle(Palette.dim)
                    }
                    Spacer()
                    Button { begin() } label: { Label(started ? "Go again" : "Start", systemImage: started ? "arrow.clockwise" : "rectangle.stack.fill") }
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                }
            }
        }
    }

    func begin() {
        withAnimation(.snappy) {
            // Second time round, the ones she missed come first.
            let order = Array(cards.indices)
            queue = started ? order.filter { missed.contains($0) } + order.filter { !missed.contains($0) } : order
            missed = []; revealed = false; started = true
        }
    }

    func next(_ i: Int, gotIt: Bool) {
        withAnimation(.snappy) {
            queue.removeFirst()
            if !gotIt { missed.insert(i); queue.append(i) }
            revealed = false
        }
    }
}

/// Real past-paper 10-markers to plan, with the original case one click away.
struct ExamPrompts: View {
    var prompts: [ExamItem.Prompt]
    @State private var zoom: ZoomTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(prompts.enumerated()), id: \.offset) { _, p in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("“\(p.text)”").font(.system(size: 13)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                        Chip(text: p.source)
                    }
                    Spacer(minLength: 8)
                    if let id = p.set, FileManager.default.fileExists(atPath: BusinessBank.caseURL(id).path) {
                        Button { zoom = ZoomTarget(url: BusinessBank.caseURL(id), page: 0, title: p.source) } label: {
                            Label("Case", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(GhostButtonStyle(compact: true))
                        .help("Open the original case and question")
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .sheet(item: $zoom) { ZoomSheet(target: $0) }
    }
}

/// Her own fixes from the last Business paper Hank marked (nothing shows if she hasn't had one marked).
struct MyFixes: View {
    @State private var fixes: [String] = []
    var body: some View {
        Group {
            if !fixes.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        HankAvatar(size: 18, animated: false)
                        Text("Your fixes from the last essay Hank marked").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.lilac)
                    }
                    FlowChips(items: fixes)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.cardHi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .task { fixes = ExamCoach.latestFixes() }
    }
}

/// Chips that wrap onto new lines.
struct FlowChips: View {
    var items: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { ForEach(items, id: \.self) { Chip(text: $0) } }
            VStack(alignment: .leading, spacing: 6) { ForEach(items, id: \.self) { Chip(text: $0) } }
        }
    }
}
