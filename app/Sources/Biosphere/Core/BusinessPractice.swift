import Foundation

struct BusinessPracticeScope: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, Hashable {
        case everything, unit, topic, chosen
    }

    var id: String
    var title: String
    var topicIds: [String]
    var kind: Kind
    var subject: CaseSubject = .business

    init(id: String, title: String, topicIds: [String], kind: Kind, subject: CaseSubject = .business) {
        self.id = id
        self.title = title
        self.topicIds = Array(Set(topicIds)).sorted()
        self.kind = kind
        self.subject = subject
    }

    static func everything(bank: BusinessBank) -> Self {
        let subject = bank.caseSubject
        return Self(id: "\(subject.pageKey).everything", title: "All \(subject.shortName)", topicIds: bank.topics.map(\.id),
                    kind: .everything, subject: subject)
    }

    static func unit(_ id: String, bank: BusinessBank) -> Self {
        let topics = bank.topics.filter { $0.unit == id }
        return Self(id: "\(bank.caseSubject.pageKey).unit.\(id)", title: topics.first?.unitName ?? "Unit \(id)",
                    topicIds: topics.map(\.id), kind: .unit, subject: bank.caseSubject)
    }

    static func topic(_ id: String, bank: BusinessBank) -> Self {
        let topic = bank.topic(id)
        return Self(id: "\(bank.caseSubject.pageKey).topic.\(id)", title: topic?.displayName ?? id,
                    topicIds: topic.map { [$0.id] } ?? [], kind: .topic, subject: bank.caseSubject)
    }

    static func chosen(_ ids: [String], bank: BusinessBank) -> Self {
        let selected = Array(Set(ids)).sorted()
        let names = selected.compactMap { bank.topic($0)?.displayName }
        let title = names.isEmpty ? "Chosen topics" : names.count <= 2 ? names.joined(separator: ", ") : "Mixed practice · \(names.count) subtopics"
        return Self(id: "\(bank.caseSubject.pageKey).chosen.\(selected.joined(separator: ","))", title: title,
                    topicIds: selected, kind: .chosen, subject: bank.caseSubject)
    }
}

enum BusinessQuestionFormat: String, Codable, CaseIterable, Hashable, Identifiable {
    case both, short, essays
    var id: String { rawValue }

    var title: String {
        switch self {
        case .both: "All questions"
        case .short: "Short questions"
        case .essays: "Essays"
        }
    }

    func includes(_ part: BusinessPart) -> Bool {
        switch self {
        case .both: true
        case .short: !part.extended
        case .essays: part.extended
        }
    }
}

struct BusinessPaperComponent: Codable, Hashable, Identifiable {
    var setId: String
    var labels: [String]
    var id: String { setId }

    init(setId: String, labels: [String]) {
        self.setId = setId
        var seen = Set<String>()
        self.labels = labels.filter { seen.insert($0).inserted }
    }
}

enum BusinessPracticePlanner {
    private struct Candidate {
        var setIndex: Int
        var partIndex: Int
        var score: Double
        var year: Int
        var label: String
        var topics: Set<String>
    }

    /// The papers a mix draws from unless she picks others.
    static let defaultPapers: Set<String> = ["1", "2"]

    /// "Paper 2", "Papers 1 + 3".
    static func papersTitle(_ papers: Set<String>) -> String {
        let sorted = papers.sorted()
        return (sorted.count == 1 ? "Paper " : "Papers ") + sorted.joined(separator: " + ")
    }

    /// Produces one component per case, retaining original set and part labels.
    /// Score-only history cannot establish calendar due dates, so `.due` is empty;
    /// use `.smart` or `.mistakes` until review dates are available to the caller.
    /// `papers` picks which original papers to mix; a Business Paper 3 only ever comes whole.
    static func plan(bank: BusinessBank, topics: [String], minutes: Int,
                     format: BusinessQuestionFormat, mode: StudyMode,
                     history: [String: [String: Double]], everyQuestion: Bool,
                     papers: Set<String> = defaultPapers) -> [BusinessPaperComponent] {
        let scope = Set(topics)
        guard !scope.isEmpty, mode != .due else { return [] }

        let sets = bank.sets
        var candidates: [Candidate] = []
        for (si, set) in sets.enumerated() where set.currentSyllabus && papers.contains(set.paper) {
            if set.subject.keepsWhole(paper: set.paper) {
                // One candidate for the whole paper: its 17-mark plan needs parts 1 and 2 and the full case,
                // so it never fits a short-answers-only paper.
                let topics = Set(set.parts.flatMap(\.topicIds)).intersection(scope)
                guard format != .short, let last = set.parts.indices.last, !topics.isEmpty,
                      set.parts.allSatisfy({ !$0.markscheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { continue }
                let ratios = set.parts.compactMap { history[set.id]?[$0.label].flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } }
                let ratio = ratios.isEmpty ? nil : ratios.reduce(0, +) / Double(ratios.count)
                guard keeps(ratio: ratio, mode: mode) else { continue }
                candidates.append(Candidate(setIndex: si, partIndex: last, score: priority(ratio: ratio, mode: mode),
                                            year: Int(set.session.prefix(4)) ?? 0, label: set.parts[last].label, topics: topics))
                continue
            }
            for (pi, part) in set.parts.enumerated() where part.isCurrentContent && format.includes(part)
                && !part.markscheme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !part.topicIds.filter({ scope.contains($0) }).isEmpty {
                let ratio = history[set.id]?[part.label].flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
                guard keeps(ratio: ratio, mode: mode) else { continue }
                candidates.append(Candidate(setIndex: si, partIndex: pi,
                                            score: priority(ratio: ratio, mode: mode),
                                            year: Int(set.session.prefix(4)) ?? 0,
                                            label: part.label,
                                            topics: Set(part.topicIds).intersection(scope)))
            }
        }
        candidates.sort(by: candidateOrder)
        guard !candidates.isEmpty else { return [] }

        if everyQuestion {
            var labelsBySet: [String: Set<String>] = [:]
            for candidate in candidates {
                let set = sets[candidate.setIndex]
                labelsBySet[set.id, default: []].insert(candidate.label)
            }
            return sets.compactMap { set in
                guard let direct = labelsBySet[set.id], !direct.isEmpty else { return nil }
                let closed = prerequisiteClosure(in: set, labels: direct)
                let labels = set.parts.filter { closed.contains($0.label) }.map(\.label)
                return labels.isEmpty ? nil : BusinessPaperComponent(setId: set.id, labels: labels)
            }
        }

        let budget = max(1, minutes)
        var selected: [String: Set<String>] = [:]
        var skipped = Set<String>()
        var lastSetId: String?

        while true {
            let coveredTopics = Set(selected.flatMap { setId, labels in
                guard let set = bank.set(setId) else { return [String]() }
                return set.parts.filter { labels.contains($0.label) }.flatMap(\.topicIds).filter(scope.contains)
            })
            let coveredPapers = Set(selected.keys.compactMap { bank.set($0)?.paper })
            let remaining = candidates.filter { candidate in
                let setId = sets[candidate.setIndex].id
                return !skipped.contains("\(setId)|\(candidate.label)")
                    && !(selected[setId]?.contains(candidate.label) ?? false)
            }
            guard !remaining.isEmpty else { break }
            let ranked = remaining.sorted { lhs, rhs in
                // Every paper she ticked gets a turn; an indivisible paper goes first so smaller parts fill around it.
                let lhsPaper = sets[lhs.setIndex].paper, rhsPaper = sets[rhs.setIndex].paper
                let lhsNewPaper = !coveredPapers.contains(lhsPaper), rhsNewPaper = !coveredPapers.contains(rhsPaper)
                if lhsNewPaper != rhsNewPaper { return lhsNewPaper }
                let lhsWhole = sets[lhs.setIndex].subject.keepsWhole(paper: lhsPaper)
                if lhsNewPaper, lhsWhole != sets[rhs.setIndex].subject.keepsWhole(paper: rhsPaper) { return lhsWhole }
                let lhsUncovered = !lhs.topics.isSubset(of: coveredTopics)
                let rhsUncovered = !rhs.topics.isSubset(of: coveredTopics)
                if lhsUncovered != rhsUncovered { return lhsUncovered }
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                let lhsSameCase = sets[lhs.setIndex].id == lastSetId
                let rhsSameCase = sets[rhs.setIndex].id == lastSetId
                if lhsSameCase != rhsSameCase { return lhsSameCase }
                return candidateOrder(lhs, rhs)
            }

            var added: Candidate?
            for candidate in ranked {
                let set = sets[candidate.setIndex]
                let current = selected[set.id] ?? []
                let proposed = prerequisiteClosure(in: set, labels: current.union([candidate.label]))
                var proposedSelection = selected
                proposedSelection[set.id] = proposed
                let components = bank.sets.compactMap { source -> BusinessPaperComponent? in
                    guard let labels = proposedSelection[source.id], !labels.isEmpty else { return nil }
                    return BusinessPaperComponent(setId: source.id,
                        labels: source.parts.filter { labels.contains($0.label) }.map(\.label))
                }
                if estimatedMinutes(bank: bank, components: components) <= budget {
                    selected[set.id] = proposed
                    lastSetId = set.id
                    added = candidate
                    break
                }
                skipped.insert("\(set.id)|\(candidate.label)")
            }
            if added == nil {
                // Permit one oversized question only when no complete question fits.
                guard selected.isEmpty, let candidate = ranked.first else { break }
                let set = sets[candidate.setIndex]
                selected[set.id] = prerequisiteClosure(in: set, labels: [candidate.label])
                break
            }
        }

        return sets.compactMap { set in
            guard let labels = selected[set.id], !labels.isEmpty else { return nil }
            let ordered = set.parts.filter { labels.contains($0.label) }.map(\.label)
            return BusinessPaperComponent(setId: set.id, labels: ordered)
        }
    }

    /// Includes original per-mark pace and one reading allowance for each distinct case.
    static func estimatedMinutes(bank: BusinessBank, components: [BusinessPaperComponent]) -> Int {
        var labelsBySet: [String: Set<String>] = [:]
        for component in components {
            labelsBySet[component.setId, default: []].formUnion(component.labels)
        }
        var total = 0.0
        for set in bank.sets {
            guard let labels = labelsBySet[set.id] else { continue }
            let parts = set.parts.filter { labels.contains($0.label) }
            guard !parts.isEmpty else { continue }
            let pace = Double(set.minutes) / Double(max(set.marks, 1))
            total += Double(parts.reduce(0) { $0 + $1.marks }) * pace
            total += Double(readingAllowance(for: set))
        }
        return Int(ceil(total))
    }

    /// Restores the chosen subset while keeping each paper's original case and markschemes.
    static func selectedSets(bank: BusinessBank, components: [BusinessPaperComponent]) -> [BusinessSet] {
        guard Set(components.map(\.setId)).count == components.count else { return [] }
        var result: [BusinessSet] = []
        for component in components {
            guard !component.labels.isEmpty,
                  Set(component.labels).count == component.labels.count,
                  let set = bank.set(component.setId),
                  Set(component.labels).isSubset(of: Set(set.parts.map(\.label))),
                  let selected = set.selecting(labels: component.labels) else { return [] }
            result.append(selected)
        }
        return result
    }

    /// A Business Paper 3 is closed over all its parts: picking any of it brings the whole paper.
    private static func prerequisiteClosure(in set: BusinessSet, labels initial: Set<String>) -> Set<String> {
        guard !set.subject.keepsWhole(paper: set.paper) else { return initial.isEmpty ? [] : Set(set.parts.map(\.label)) }
        let byLabel = Dictionary(uniqueKeysWithValues: set.parts.map { ($0.label, $0) })
        var labels = initial
        var previousCount = -1
        while previousCount != labels.count {
            previousCount = labels.count
            for label in labels {
                labels.formUnion((byLabel[label]?.prerequisites ?? []).filter { byLabel[$0] != nil })
            }
        }
        return labels
    }

    private static func keeps(ratio: Double?, mode: StudyMode) -> Bool {
        switch mode {
        case .smart: true
        case .fresh: ratio == nil
        case .mistakes: ratio.map { $0 < 0.999 } ?? false
        case .due: false
        }
    }

    private static func priority(ratio: Double?, mode: StudyMode) -> Double {
        guard let ratio else { return mode == .fresh ? 1 : 2.0 }
        return switch mode {
        case .smart, .mistakes: 1.0 + (1.0 - ratio) * 3.0
        case .fresh, .due: 0
        }
    }

    private static func candidateOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.year != rhs.year { return lhs.year > rhs.year }
        if lhs.setIndex != rhs.setIndex { return lhs.setIndex < rhs.setIndex }
        return lhs.partIndex < rhs.partIndex
    }

    private static func readingAllowance(for set: BusinessSet) -> Int {
        set.subject.readingAllowance(paper: set.paper)
    }
}
