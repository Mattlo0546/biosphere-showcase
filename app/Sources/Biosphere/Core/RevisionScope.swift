import Foundation

/// What she chose to revise, before choosing how long for.
/// In Maths the same levels mean: one strategy → an area of strategies → a whole IB topic → everything.
enum RevisionScope: Hashable, Identifiable {
    case subtopic(String)
    case topic(String)       // e.g. "A1", or "M5.2" in Maths
    case theme(String)       // e.g. "A", or "M5"
    case everything          // all SL subtopics, weakest first
    case custom(Set<String>) // her own pick-and-mix of subtopics (within a topic or across the syllabus)

    /// Her ticked subtopics as a scope: one pick is plain subtopic practice (so "every question" still works).
    static func mix(_ ids: Set<String>) -> RevisionScope? {
        ids.count > 1 ? .custom(ids) : ids.first.map { .subtopic($0) }
    }

    var id: String {
        switch self {
        case .subtopic(let s): "s:" + s
        case .topic(let t): "t:" + t
        case .theme(let t): "th:" + t
        case .everything: "all"
        case .custom(let ids): "c:" + ids.sorted().joined(separator: ",")
        }
    }

    var kind: SessionKind {
        switch self {
        case .subtopic: .subtopic
        case .topic: .topic
        case .theme: .theme
        case .everything: .timed
        case .custom: spansTopics ? .timed : .topic
        }
    }

    /// Mixed scopes interleave subtopics and lean towards the weak ones.
    var isMixed: Bool { if case .subtopic = self { false } else { true } }

    /// Maths: a whole topic or everything is exam-style practice with whole questions; a strategy or an
    /// area of strategies is drilled with the parts that use them.
    var isExamStyle: Bool {
        switch self {
        case .theme, .everything: true
        case .subtopic, .topic, .custom: false
        }
    }

    /// The topic a subtopic sits in: "A1.2" → "A1"; in Maths a strategy's area, "M5.2.7" → "M5.2".
    static func topicId(_ id: String) -> String { id.lastIndex(of: ".").map { String(id[..<$0]) } ?? id }

    /// A custom mix drawn from more than one topic: a "full paper" rather than topic practice.
    var spansTopics: Bool {
        guard case .custom(let ids) = self else { return false }
        return Set(ids.map(Self.topicId)).count > 1
    }

    func subtopicIds(in syl: Syllabus) -> Set<String> {
        let sl = syl.slSubtopics
        switch self {
        case .subtopic(let s): return [s]
        case .topic(let t): return Set(sl.filter { $0.id.hasPrefix(t + ".") }.map(\.id))
        case .theme(let t): return Set(sl.filter { $0.id.hasPrefix(t) }.map(\.id))
        case .everything: return Set(sl.map(\.id))
        case .custom(let ids): return ids.intersection(sl.map(\.id))
        }
    }

    func title(in syl: Syllabus) -> String {
        let strategies = syl.isStrategyBank
        switch self {
        case .subtopic(let s):
            guard let sub = syl.subtopic(s) else { return s }
            return strategies ? sub.name : "\(sub.id) \(sub.name)"
        case .topic(let t):
            let name = syl.allSubtopics.first { $0.id.hasPrefix(t + ".") }?.level ?? ""
            let theme = syl.theme(containing: t)?.name ?? ""
            return strategies ? "\(theme) · \(name)" : "\(t) \(theme) · \(name)"
        case .theme(let t):
            let name = syl.themes.first { $0.id == t }?.name ?? ""
            return strategies ? "\(name): exam-style mix" : "Theme \(t): " + name
        case .everything: return "Mixed — weakest first"
        case .custom(let ids):
            if !spansTopics, let t = ids.first.map(Self.topicId) {
                return RevisionScope.topic(t).title(in: syl) + " · your mix"
            }
            return "Your mix · \(ids.count) \(strategies ? "strategies" : "subtopics")"
        }
    }

    func subtitle(in syl: Syllabus) -> String {
        if syl.isStrategyBank {
            switch self {
            case .subtopic: return "Strategy drill"
            case .topic, .custom: return "Mixed strategies: spot which one each question needs"
            case .theme: return "Whole exam questions from this topic"
            case .everything: return "Whole exam questions, weighted to your red and orange strategies"
            }
        }
        switch self {
        case .subtopic: return "Subtopic practice"
        case .topic, .theme, .custom: return "Mixed: " + subtopicIds(in: syl).sorted().joined(separator: " · ")
        case .everything: return "Across the whole syllabus, weighted to your red and orange squares"
        }
    }
}

/// Her pick-and-mix on the Topics page: the subtopics she has ticked, optionally kept inside one topic.
struct SubtopicMix: Equatable {
    var topic: String?            // nil = pick from the whole syllabus
    var picked: Set<String> = []

    func allows(_ id: String) -> Bool { topic.map { id.hasPrefix($0 + ".") } ?? true }

    mutating func toggle(_ id: String) {
        guard allows(id) else { return }
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    var scope: RevisionScope? { RevisionScope.mix(picked) }
}
