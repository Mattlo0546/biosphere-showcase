import Foundation

/// The question bank for one subject, loaded from bank/<slug>/.
final class Bank {
    let slug: String
    let dir: URL
    let syllabus: Syllabus
    let questions: [Question]
    private let byId: [String: Question]
    private let split: Set<String>      // Maths: whole questions that were cut into drill items

    init(slug: String, directory: URL? = nil) throws {
        self.slug = slug
        let copy = Workspace.bank.appendingPathComponent(slug)
        dir = directory ?? (FileManager.default.fileExists(atPath: copy.appendingPathComponent("questions.json").path)
            ? copy : Workspace.resources.appendingPathComponent("bank/\(slug)"))
        syllabus = try JSON.load(Syllabus.self, from: dir.appendingPathComponent("syllabus.json"))
        questions = try JSON.load([Question].self, from: dir.appendingPathComponent("questions.json"))
        byId = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        split = Set(questions.compactMap(\.parent))
    }

    func question(_ id: String) -> Question? { byId[id] }
    func paperURL(_ paperId: String) -> URL { dir.appendingPathComponent("papers/\(paperId).pdf") }
    /// Maths markscheme PDF, shipped in the paper pack; nil until a pack that includes it is installed.
    func markschemeURL(_ paperId: String) -> URL? {
        let url = dir.appendingPathComponent("papers/\(paperId)-markscheme.pdf")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// In-syllabus questions whose main subtopic is one of `ids`.
    ///
    /// Maths (a strategy bank) works differently. A drill (`examStyle == false`) takes the drill items cut for
    /// those strategies plus the short questions that spend real marks on them, so "Find a max or min" brings
    /// every part that needs it, however it's worded. Exam style takes whole questions only.
    func pool(for ids: Set<String>, format: QuestionFormat = .both, examStyle: Bool = false) -> [Question] {
        guard syllabus.isStrategyBank else {
            return questions.filter { $0.inSyllabus && ids.contains($0.primary) && format.includes($0) }
        }
        return questions.filter { q in
            guard q.inSyllabus, format.includes(q) else { return false }
            if examStyle { return q.parent == nil && ids.contains(q.primary) }
            if q.parent != nil { return ids.contains(q.primary) }
            if split.contains(q.id) { return false }       // its drill items stand in for it
            let marks = q.parts.filter { ids.contains($0.subtopic ?? q.primary) }.reduce(0) { $0 + $1.marks }
            return ids.contains(q.primary) || marks >= max(2, (q.marks + 2) / 3)
        }
    }

    func pool(for scope: RevisionScope, format: QuestionFormat = .both) -> [Question] {
        pool(for: scope.subtopicIds(in: syllabus), format: format, examStyle: scope.isExamStyle)
    }

    func count(for subtopic: String) -> Int {
        if syllabus.isStrategyBank { return pool(for: [subtopic]).count }
        return questions.lazy.filter { $0.inSyllabus && $0.primary == subtopic }.count
    }
}

/// Picks questions for a practice set.
enum Selector {
    struct Options {
        var targetMinutes: Double
        var interleave: Bool = false            // mix subtopics round-robin (whole-topic revision)
        var weights: [String: Double] = [:]     // subtopic -> priority weight (timed sessions)
    }

    /// Exam session order: November 2025 > May 2025 > November 2024 > …
    static func sessionRank(_ q: Question) -> Int { q.year * 2 + (q.session.localizedCaseInsensitiveContains("nov") ? 1 : 0) }

    /// Newest papers first: every unseen question from the most recent exam session comes before any
    /// older one, so she works backwards through the years (2025 → 2024 → … → 2010). Within a session,
    /// weaker subtopics first, then random. Questions she's already done come last (lowest score first).
    /// Roughly 40% of the time goes to multiple choice.
    static func pick(from pool: [Question], seen: [String: Double], options: Options) -> [Question] {
        guard !pool.isEmpty else { return [] }
        func key(_ q: Question) -> (Int, Int, Int, Double) {
            let unseen = seen[q.id] == nil ? 1 : 0
            let fits = q.minutes > options.targetMinutes * 0.6 ? 0 : 1     // don't let one giant question eat the set
            return (unseen, fits, unseen == 1 ? sessionRank(q) : 0, (options.weights[q.primary] ?? 1) - (seen[q.id] ?? 0))
        }
        let ranked = pool.shuffled().sorted { key($0) > key($1) }
        let mcq = ranked.filter(\.isMCQ)
        let written = ranked.filter { !$0.isMCQ }
        let mcqBudget = written.isEmpty ? options.targetMinutes : (mcq.isEmpty ? 0 : options.targetMinutes * 0.4)

        var chosen: [Question] = []
        var used = 0.0
        func take(_ list: [Question], budget: Double) {
            var spent = 0.0
            let ordered = options.interleave ? roundRobin(list) : list
            for q in ordered where spent + q.minutes <= budget + 2 && used + q.minutes <= options.targetMinutes + 3
                && !chosen.contains(where: { $0.family == q.family }) {
                chosen.append(q); spent += q.minutes; used += q.minutes
            }
        }
        take(mcq, budget: mcqBudget)
        take(written, budget: options.targetMinutes - used)
        if used < options.targetMinutes * 0.8 {  // top up with whatever is left
            take(ranked.filter { q in !chosen.contains(q) }, budget: options.targetMinutes - used)
        }
        if chosen.isEmpty, let first = ranked.first { chosen = [first] }
        // MCQs first, then written questions; within each, keep the interleaved order.
        let m = chosen.filter(\.isMCQ), w = chosen.filter { !$0.isMCQ }
        return options.interleave ? roundRobin(m) + roundRobin(w) : m + w
    }

    /// Mode-aware selection on top of the spaced-repetition schedule.
    static func pick(from pool: [Question], reviews: [String: ReviewState], mode: StudyMode, options: Options,
                     now: Date = Date()) -> [Question] {
        let seen = reviews.mapValues(\.lastPercent)
        func take(_ list: [Question], budget: Double) -> [Question] {
            var out: [Question] = [], used = 0.0
            for q in list where used + q.minutes <= budget + 3 && !out.contains(where: { $0.family == q.family }) {
                out.append(q); used += q.minutes
            }
            return out
        }
        func ordered(_ qs: [Question]) -> [Question] {
            let m = qs.filter(\.isMCQ), w = qs.filter { !$0.isMCQ }
            return options.interleave ? roundRobin(m) + roundRobin(w) : m + w
        }
        let mistakes = pool.filter { reviews[$0.id]?.isMistake == true }
            .sorted { a, b in
                let ra = reviews[a.id]!, rb = reviews[b.id]!
                return (ra.lastPercent, -ra.lapses, ra.lastDate) < (rb.lastPercent, -rb.lapses, rb.lastDate)
            }
        let due = pool.filter { reviews[$0.id]?.isDue(now) == true }
            .sorted { reviews[$0.id]!.due < reviews[$1.id]!.due }
        let unseen = pool.filter { reviews[$0.id] == nil }

        switch mode {
        case .fresh:
            return pick(from: unseen, seen: [:], options: options)
        case .mistakes:
            return ordered(take(mistakes, budget: options.targetMinutes))
        case .due:
            return ordered(take(due, budget: options.targetMinutes))
        case .smart:
            // Due reviews get up to 40% of the time (all of it if nothing new is left), then new questions.
            let reviewBudget = unseen.isEmpty ? options.targetMinutes : options.targetMinutes * 0.4
            let reviewsPicked = take(due, budget: reviewBudget)
            let used = reviewsPicked.reduce(0) { $0 + $1.minutes }
            var rest = options; rest.targetMinutes = max(0, options.targetMinutes - used)
            let freshPool = unseen.filter { q in !reviewsPicked.contains { $0.family == q.family } }
            var fresh = rest.targetMinutes > 2 ? pick(from: freshPool, seen: [:], options: rest) : []
            if fresh.isEmpty && rest.targetMinutes > 2 {   // nothing new left: least-recently-mastered questions
                let leftovers = pool.filter { q in !reviewsPicked.contains { $0.family == q.family } }
                fresh = pick(from: leftovers, seen: seen, options: rest)
            }
            return ordered(reviewsPicked + fresh)
        }
    }

    static func roundRobin(_ list: [Question]) -> [Question] {
        var buckets: [String: [Question]] = [:]
        var keys: [String] = []
        for q in list {
            if buckets[q.primary] == nil { keys.append(q.primary) }
            buckets[q.primary, default: []].append(q)
        }
        var out: [Question] = []
        while out.count < list.count {
            for k in keys where !(buckets[k]?.isEmpty ?? true) { out.append(buckets[k]!.removeFirst()) }
        }
        return out
    }
}
