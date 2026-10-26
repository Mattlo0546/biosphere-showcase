import Foundation

/// Every marked attempt, plus the red / orange / green status derived from them.
struct ProgressStore: Codable {
    var attempts: [Attempt] = []

    static func load() -> ProgressStore {
        (try? JSON.load(ProgressStore.self, from: Workspace.progressFile)) ?? ProgressStore()
    }

    func save() { try? JSON.save(self, to: Workspace.progressFile) }

    /// Best recent score per question (0...1), used to avoid repeating questions she has nailed.
    var seen: [String: Double] {
        var out: [String: Double] = [:]
        for a in attempts.sorted(by: { $0.date < $1.date }) where a.available > 0 {
            out[a.questionId] = Double(a.awarded) / Double(a.available)
        }
        return out
    }

    /// The spaced-repetition schedule, rebuilt from every attempt.
    var reviews: [String: ReviewState] { ReviewEngine.states(from: attempts) }

    /// Mastery rules (per subtopic), using her last three sessions on that subtopic:
    ///   red    – under 50%
    ///   orange – 50–75%, or not enough evidence yet (fewer than 8 marks or a single session)
    ///   green  – 75%+ across at least 8 marks and 2 sessions, and the latest session was 65%+
    func stats(for subtopic: String) -> SubtopicStats {
        let mine = attempts.filter { $0.subtopic == subtopic && $0.available > 0 }
        guard !mine.isEmpty else {
            return SubtopicStats(mastery: .notStarted, percent: nil, marksAttempted: 0, questionsSeen: 0,
                                 sessions: 0, lastDate: nil, history: [])
        }
        var bySession: [String: (date: Date, got: Int, of: Int)] = [:]
        for a in mine {
            var s = bySession[a.sessionId] ?? (a.date, 0, 0)
            s.got += a.awarded; s.of += a.available; s.date = max(s.date, a.date)
            bySession[a.sessionId] = s
        }
        let ordered = bySession.values.sorted { $0.date < $1.date }
        let history = ordered.map { Double($0.got) / Double(max($0.of, 1)) }
        let recent = ordered.suffix(3)
        let got = recent.reduce(0) { $0 + $1.got }, of = recent.reduce(0) { $0 + $1.of }
        let pct = Double(got) / Double(max(of, 1))
        let totalMarks = mine.reduce(0) { $0 + $1.available }
        let mastery: Mastery
        if pct < 0.5 { mastery = .red }
        else if pct >= 0.75 && totalMarks >= 8 && ordered.count >= 2 && (history.last ?? 0) >= 0.65 { mastery = .green }
        else { mastery = .orange }
        return SubtopicStats(mastery: mastery, percent: pct, marksAttempted: totalMarks,
                             questionsSeen: Set(mine.map(\.questionId)).count, sessions: ordered.count,
                             lastDate: ordered.last?.date, history: history)
    }

    /// Marks attempted per calendar day, for the activity calendar.
    var marksByDay: [Date: Int] {
        let cal = Calendar.current
        var out: [Date: Int] = [:]
        for a in attempts { out[cal.startOfDay(for: a.date), default: 0] += a.available }
        return out
    }

    mutating func record(_ result: MarkingResult, session: StudySession, bank: Bank) {
        attempts.removeAll { $0.sessionId == session.id }
        let date = session.completedAt ?? Date()
        for q in result.questions {
            guard let question = bank.question(q.questionId) else { continue }
            // Attribute each part's marks to that part's subtopic when the labels give one.
            if q.parts.count == question.parts.count, question.parts.count > 1 {
                for (pr, part) in zip(q.parts, question.parts) {
                    attempts.append(Attempt(sessionId: session.id, date: date, questionId: q.questionId,
                                            subtopic: part.subtopic ?? question.primary,
                                            awarded: pr.awarded, available: pr.available))
                }
            } else {
                attempts.append(Attempt(sessionId: session.id, date: date, questionId: q.questionId,
                                        subtopic: question.primary, awarded: q.awarded, available: q.available))
            }
        }
        save()
    }

    /// A compact summary Claude can read without parsing every attempt.
    func writeSummary(bank: Bank) {
        struct Row: Codable { var id, name, status: String; var percent: Int?; var marksAttempted, questionsSeen, sessions: Int; var lastPracticed: Date?; var bankQuestions: Int; var mistakes: Int; var dueForReview: Int; var notesUrl: String }
        struct Summary: Codable {
            var generatedAt: Date; var subject: String; var subtopics: [Row]; var seenQuestionIds: [String]
            var mistakeQuestionIds: [String]; var dueQuestionIds: [String]; var spacedRepetition: String
        }
        let rev = reviews.filter { bank.question($0.key) != nil }    // this subject's questions only
        let now = Date()
        let rows = bank.syllabus.slSubtopics.map { s -> Row in
            let st = stats(for: s.id)
            let mine = rev.values.filter { bank.question($0.questionId)?.primary == s.id }
            return Row(id: s.id, name: s.name, status: st.mastery.rawValue, percent: st.percent.map { Int($0 * 100) },
                       marksAttempted: st.marksAttempted, questionsSeen: st.questionsSeen, sessions: st.sessions,
                       lastPracticed: st.lastDate, bankQuestions: bank.count(for: s.id),
                       mistakes: mine.filter(\.isMistake).count, dueForReview: mine.filter { $0.isDue(now) }.count, notesUrl: s.notesUrl)
        }
        try? JSON.save(Summary(generatedAt: now, subject: bank.syllabus.subject, subtopics: rows,
                               seenQuestionIds: Array(rev.keys).sorted(),
                               mistakeQuestionIds: rev.values.filter(\.isMistake).sorted { $0.lastPercent < $1.lastPercent }.map(\.questionId),
                               dueQuestionIds: rev.values.filter { $0.isDue(now) }.sorted { $0.due < $1.due }.map(\.questionId),
                               spacedRepetition: "SM-2 style: a question scored under 60% is due again the next day; passes come back after growing gaps (~1, 3, 7, 18, 45 days)."),
                       to: Workspace.summaryFile(for: bank.slug))
    }
}
