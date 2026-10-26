import SwiftUI

/// GitHub-style tracker: one square per subtopic, red → orange → green, plus a revision calendar.
struct TrackerView: View {
    @Environment(AppModel.self) var model
    @State private var hovered: String?

    var body: some View {
        if let bank = model.bank {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(bank)
                    Card { grid(bank) }
                    Card { calendar }
                    Card { history(bank) }
                }
                .padding(.horizontal, 32).padding(.top, 56).padding(.bottom, 40)
                .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }
        }
    }

    /// Maths strategies go by name; Biology subtopics keep their syllabus id.
    func fullName(_ s: Subtopic) -> String { model.bank?.syllabus.isStrategyBank == true ? s.name : "\(s.id) \(s.name)" }

    func header(_ bank: Bank) -> some View {
        let subs = bank.syllabus.slSubtopics
        let counts = Dictionary(grouping: subs, by: { model.progress.stats(for: $0.id).mastery }).mapValues(\.count)
        let green = counts[.green] ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Text("Tracker").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Palette.text)
            Text(bank.syllabus.isStrategyBank ? "\(bank.syllabus.subject): every square is a strategy. The goal is simple: make them all green."
                                              : "Every square is a subtopic. The goal is simple: make them all green.")
                .font(.system(size: 14)).foregroundStyle(Palette.dim)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach([Mastery.green, .orange, .red, .notStarted], id: \.self) { m in
                        Rectangle().fill(Palette.color(m)).frame(width: geo.size.width * CGFloat(counts[m] ?? 0) / CGFloat(max(subs.count, 1)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            Text("\(green) of \(subs.count) green · \(counts[.orange] ?? 0) need one more go · \(counts[.red] ?? 0) need work · \(counts[.notStarted] ?? 0) not started")
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.lilac)
        }
    }

    func grid(_ bank: Bank) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Subtopics").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                Spacer()
                ForEach([Mastery.notStarted, .red, .orange, .green], id: \.self) { m in
                    HStack(spacing: 5) { MasterySquare(mastery: m, size: 11); Text(m.label).font(.system(size: 11)).foregroundStyle(Palette.dim) }
                }
            }
            ForEach(bank.syllabus.themes) { theme in
                HStack(alignment: .center, spacing: 14) {
                    Text(bank.syllabus.isStrategyBank ? String(theme.id.dropFirst()) : theme.id).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Palette.violet).frame(width: 18)
                    ForEach(bank.syllabus.topics(in: theme)) { topic in
                        HStack(spacing: 6) {
                            ForEach(topic.subtopics) { s in square(s) }
                        }
                        .padding(6)
                        .background(Palette.bg2, in: RoundedRectangle(cornerRadius: 10))
                    }
                    Spacer()
                }
            }
            if let id = hovered, let s = bank.syllabus.subtopic(id) {
                let st = model.progress.stats(for: id)
                HStack(spacing: 10) {
                    MasterySquare(mastery: st.mastery, size: 14)
                    Text("\(fullName(s))").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(st.mastery.label).font(.system(size: 12)).foregroundStyle(Palette.color(st.mastery))
                    if let p = st.percent { Text("· recent \(Int(p * 100))% · \(st.marksAttempted) marks over \(st.sessions) session\(st.sessions == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(Palette.dim) }
                }
            } else {
                Text("Hover a square for details · click to revise it · green = 75%+ across at least two sessions")
                    .font(.system(size: 12)).foregroundStyle(Palette.faint)
            }
        }
    }

    func square(_ s: Subtopic) -> some View {
        let st = model.progress.stats(for: s.id)
        return Button { model.timeRequest = .subtopic(s.id) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.color(st.mastery))
                Text(model.bank?.syllabus.isStrategyBank == true ? String(s.id.dropFirst()) : s.id).font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(st.mastery == .notStarted ? Palette.dim : .white)
            }
            .frame(width: 50, height: 50)
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(hovered == s.id ? Palette.purple : .black.opacity(0.04), lineWidth: hovered == s.id ? 2 : 1))
            .scaleEffect(hovered == s.id ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.snappy(duration: 0.15)) { hovered = h ? s.id : (hovered == s.id ? nil : hovered) } }
        .help("\(fullName(s)) — \(st.mastery.label)")
    }

    var calendar: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weeks = 26
        let weekStart = cal.date(byAdding: .day, value: -(cal.component(.weekday, from: today) - 1), to: today)!
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7, to: weekStart)!
        let byDay = model.progress.marksByDay
        let maxMarks = max(byDay.values.max() ?? 1, 1)
        let total = byDay.values.reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Revision days").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
                Spacer()
                Text("\(total) marks attempted · \(byDay.count) \(byDay.count == 1 ? "day" : "days")").font(.system(size: 12)).foregroundStyle(Palette.dim)
            }
            HStack(alignment: .top, spacing: 4) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                            let marks = byDay[day] ?? 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(marks == 0 ? Palette.empty : Palette.purple.opacity(0.3 + 0.7 * Double(marks) / Double(maxMarks)))
                                .frame(width: 14, height: 14)
                                .opacity(day > today ? 0.25 : 1)
                                .help("\(day.formatted(date: .abbreviated, time: .omitted)): \(marks) marks")
                        }
                    }
                }
            }
        }
    }

    func history(_ bank: Bank) -> some View {
        let practiced = bank.syllabus.slSubtopics.filter { model.progress.stats(for: $0.id).sessions > 0 }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Each session, per subtopic").font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.text)
            if practiced.isEmpty {
                Text("Once a paper is marked, each subtopic gets a row here — one square per attempt, so you can watch it turn green.")
                    .font(.system(size: 12.5)).foregroundStyle(Palette.faint)
            }
            ForEach(practiced) { s in
                let st = model.progress.stats(for: s.id)
                HStack(spacing: 10) {
                    MasterySquare(mastery: st.mastery, size: 12)
                    Text("\(fullName(s))").font(.system(size: 12.5)).foregroundStyle(Palette.text).frame(width: 260, alignment: .leading)
                    HStack(spacing: 3) {
                        ForEach(Array(st.history.suffix(24).enumerated()), id: \.offset) { _, p in
                            RoundedRectangle(cornerRadius: 3).fill(p >= 0.75 ? Palette.green : p >= 0.5 ? Palette.orange : Palette.red)
                                .frame(width: 14, height: 14).help("\(Int(p * 100))%")
                        }
                    }
                    Spacer()
                    // Why a high score can still be orange: green needs a second session to confirm it.
                    if st.mastery == .orange, (st.percent ?? 0) >= 0.75 {
                        Text("1 more session to go green").font(.system(size: 11)).foregroundStyle(Palette.faint)
                    }
                    if let p = st.percent { Text("\(Int(p * 100))%").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.color(st.mastery)) }
                }
            }
        }
    }
}
