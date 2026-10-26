import Foundation

/// Spaced repetition for past-paper questions — an SM-2 variant (the algorithm Anki grew out of),
/// driven entirely by her marked attempts, so there's no extra state to keep in sync.
///
/// Each marked attempt becomes a grade from the fraction of marks she got:
///   100% → 5 · ≥80% → 4 · ≥60% → 3 · ≥40% → 2 · >0 → 1 · 0 → 0
/// Grades below 3 are lapses: the question comes back tomorrow and gets harder to "graduate"
/// (ease drops). Passes grow the gap: first pass 1–4 days, second ~1 week, then interval × ease.
struct ReviewState: Hashable {
    var questionId: String
    var subtopic: String
    var reps = 0                 // consecutive passes
    var lapses = 0               // times she's failed it
    var ease = 2.5
    var intervalDays = 0.0
    var due = Date.distantPast
    var lastPercent = 0.0
    var lastDate = Date.distantPast
    var attempts = 0

    /// Lost at least one mark last time she did it.
    var isMistake: Bool { lastPercent < 0.999 }
    func isDue(_ now: Date = Date()) -> Bool { due <= now }
}

enum ReviewEngine {
    static func grade(_ pct: Double) -> Int {
        switch pct {
        case 0.999...: 5
        case 0.8...: 4
        case 0.6...: 3
        case 0.4...: 2
        case 0.0001...: 1
        default: 0
        }
    }

    static func apply(_ s: inout ReviewState, percent: Double, on date: Date) {
        let q = grade(percent)
        if q < 3 {
            s.lapses += 1
            s.reps = 0
            s.intervalDays = 1
            s.ease = max(1.3, s.ease - 0.2)
        } else {
            s.reps += 1
            switch s.reps {
            case 1: s.intervalDays = q == 5 ? 4 : (q == 4 ? 3 : 1)
            case 2: s.intervalDays = q == 3 ? 3 : 7
            default: s.intervalDays = (s.intervalDays * (q == 3 ? 1.2 : s.ease)).rounded()
            }
            let d = Double(5 - q)
            s.ease = max(1.3, s.ease + 0.1 - d * (0.08 + d * 0.02))
        }
        s.attempts += 1
        s.lastPercent = percent
        s.lastDate = date
        let cal = Calendar.current
        s.due = cal.date(byAdding: .day, value: Int(s.intervalDays), to: cal.startOfDay(for: date)) ?? date
    }

    /// Replays every attempt (oldest first) into a schedule per question.
    static func states(from attempts: [Attempt]) -> [String: ReviewState] {
        // A question can have several part-attempts in one session: combine them first.
        struct Key: Hashable { var session: String; var question: String }
        var combined: [Key: (date: Date, got: Int, of: Int, subtopic: String)] = [:]
        for a in attempts where a.available > 0 {
            let k = Key(session: a.sessionId, question: a.questionId)
            var c = combined[k] ?? (a.date, 0, 0, a.subtopic)
            c.got += a.awarded; c.of += a.available
            combined[k] = c
        }
        var out: [String: ReviewState] = [:]
        for (k, c) in combined.sorted(by: { $0.value.date < $1.value.date }) {
            var s = out[k.question] ?? ReviewState(questionId: k.question, subtopic: c.subtopic)
            apply(&s, percent: Double(c.got) / Double(max(c.of, 1)), on: c.date)
            out[k.question] = s
        }
        return out
    }
}

/// What kind of paper to build for a scope.
enum StudyMode: String, CaseIterable, Identifiable, Codable {
    case smart, fresh, mistakes, due
    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: "Smart mix"
        case .fresh: "New questions"
        case .mistakes: "My mistakes"
        case .due: "Due for review"
        }
    }

    var blurb: String {
        switch self {
        case .smart: "Reviews that are due first, then new questions — newest papers first. Best default."
        case .fresh: "Only questions you've never done, starting from the most recent exam year."
        case .mistakes: "Only questions you lost marks on, worst first, until you get them right."
        case .due: "Questions the review schedule says you're about to forget."
        }
    }

    var icon: String {
        switch self {
        case .smart: "sparkles"
        case .fresh: "leaf"
        case .mistakes: "arrow.uturn.backward.circle"
        case .due: "clock.arrow.circlepath"
        }
    }
}
