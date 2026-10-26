import Foundation

// MARK: - Syllabus

struct Syllabus: Codable {
    var subject: String
    var slug: String
    var syllabus: String
    var notesSite: String
    var themes: [Theme]
    var strategies: Bool? = nil   // Maths: "subtopics" are execution strategies (see pipeline/maths_strategies.py)

    var allSubtopics: [Subtopic] { themes.flatMap(\.subtopics) }
    var slSubtopics: [Subtopic] { allSubtopics.filter { !$0.hlOnly } }
    var isStrategyBank: Bool { strategies == true }

    func subtopic(_ id: String) -> Subtopic? { allSubtopics.first { $0.id == id } }
    func theme(containing id: String) -> Theme? { themes.first { id.hasPrefix($0.id) } }

    /// The topic a subtopic belongs to: its id up to the last dot ("A1.1" → "A1", "M5.2.7" → "M5.2").
    static func topicId(_ subtopicId: String) -> String {
        subtopicId.lastIndex(of: ".").map { String(subtopicId[..<$0]) } ?? subtopicId
    }

    /// Topics such as "A1 · Molecules" (or, for Maths, "Using derivatives"), built from the subtopic ids.
    func topics(in theme: Theme) -> [Topic] {
        var order: [String] = []
        var groups: [String: [Subtopic]] = [:]
        for s in theme.subtopics where !s.hlOnly {
            let key = Self.topicId(s.id)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(s)
        }
        return order.map { Topic(id: $0, name: groups[$0]!.first!.level, theme: theme.id, subtopics: groups[$0]!) }
    }
}

struct Theme: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var notesUrl: String
    var subtopics: [Subtopic]
}

struct Subtopic: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var hlOnly: Bool
    var level: String
    var notesUrl: String
    // Maths strategies only: how to spot it, the recipe, the booklet hint and the classic trap.
    var ref: String? = nil
    var cues: [String]? = nil
    var steps: [String]? = nil
    var formula: String? = nil
    var trap: String? = nil

    /// What to print beside the name: the IB syllabus reference for a strategy, the id otherwise.
    var tag: String { ref ?? id }
}

struct Topic: Identifiable, Hashable {
    var id: String
    var name: String
    var theme: String
    var subtopics: [Subtopic]
}

// MARK: - Question bank

struct Region: Codable, Hashable {
    var page: Int
    var x0: Double
    var x1: Double
    var y0: Double
    var y1: Double
}

struct Part: Codable, Hashable {
    var label: String
    var marks: Int
    var subtopic: String?
    var prompt: String
    var markscheme: [String]
    var guidance: String?
    var concept: String?
    var cue: String? = nil           // Maths: the words in the question that give the strategy away
    var dependsOn: [String]? = nil   // Maths: earlier lettered parts whose results this part needs
    var msRegions: [Region]? = nil   // Maths: this part's crop of the markscheme PDF (pipeline/segment_markschemes.py)
}

struct Question: Codable, Identifiable, Hashable {
    var id: String
    var paperId: String
    var session: String          // "2019 May"
    var paper: String            // "1", "2", "1A" ...
    var tz: String
    var number: String
    var type: String             // mcq | structured | extended
    var inSyllabus: Bool
    var primary: String
    var subtopics: [String]
    var title: String
    var concepts: [String]
    var skills: [String]
    var difficulty: Int
    var marks: Int
    var minutes: Double
    var answer: String?
    var parts: [Part]
    var regions: [Region]
    var needsSpace: Bool
    var parent: String? = nil        // Maths drill item: the whole question it was cut from
    var focus: [String]? = nil       // Maths drill item: the part labels that drill its strategy
    var msRegions: [Region]? = nil   // Maths: the whole question's crop of the markscheme PDF

    var isMCQ: Bool { type == "mcq" }
    /// The bank part a marked part refers to; Hank may write "(b)(i)", "b(i)" or "b i".
    func part(labelled label: String) -> Part? {
        let key = { (s: String) in s.lowercased().filter { $0.isLetter || $0.isNumber } }
        return parts.first { key($0.label) == key(label) }
    }
    /// A whole question and the drill items cut from it are one family: never two in the same paper.
    var family: String { parent ?? id }
    var year: Int { Int(session.prefix(4)) ?? 2000 }
    var sourceLabel: String { "\(session) · Paper \(paper)\(tz == "TZ0" ? "" : " " + tz) · Q\(number)" }
}

/// The answer format she wants to practise; written sets include longer essay parts too.
enum QuestionFormat: String, CaseIterable, Identifiable, Codable {
    case both, multipleChoice, structuredWriting
    var id: String { rawValue }

    var title: String {
        switch self {
        case .both: "Both"
        case .multipleChoice: "Multiple choice"
        case .structuredWriting: "Structured writing"
        }
    }

    var blurb: String {
        switch self {
        case .both: "A mix of multiple choice and written questions."
        case .multipleChoice: "Only multiple-choice questions."
        case .structuredWriting: "Written answers, including structured questions and longer responses."
        }
    }

    var planningInstruction: String {
        switch self {
        case .both: "Use both multiple-choice (mcq) and written (structured or extended) questions where available."
        case .multipleChoice: "Only choose questions with type mcq. Do not include written questions."
        case .structuredWriting: "Only choose questions with type structured or extended. Do not include mcq questions."
        }
    }

    func includes(_ question: Question) -> Bool {
        switch self {
        case .both: true
        case .multipleChoice: question.isMCQ
        case .structuredWriting: question.type == "structured" || question.type == "extended"
        }
    }
}

// MARK: - Sessions

enum SessionKind: String, Codable {
    case subtopic, topic, theme, timed, custom
}

enum SessionStatus: String, Codable {
    case ready, sent, completed, marking, marked, failed
}

/// Where a question landed in the composed PDF, as fractions of the page measured from the top.
struct Placement: Codable, Hashable {
    var page: Int
    var x0: Double
    var y0: Double
    var x1: Double
    var y1: Double
}

struct StudySession: Codable, Identifiable, Hashable {
    var id: String               // BS-XXXXXX
    var title: String
    var subtitle: String
    var kind: SessionKind
    var scope: [String]          // subtopic ids
    var questionIds: [String]
    var totalMarks: Int
    var minutes: Int
    var createdAt: Date
    var status: SessionStatus
    var placements: [String: [Placement]] = [:]   // question id -> placements in questions.pdf
    var pageCount: Int = 0
    var rationale: String?
    var score: Int?
    var completedAt: Date?
    var markedAt: Date?
    var timeSpentSeconds: Int?
    var error: String?
    var subject: String?         // nil = Biology SL; "business-hl" / "economics-hl" = a case-paper set; "maths-aa-sl" = Maths
    var businessSetId: String?
    var businessPartLabels: [String]?  // nil = original full set; otherwise only these parts
    var businessTopicId: String?      // the chosen topic, including when a task spans other areas
    var answerPages: [Int]?      // Business: 1-based pages of the PDF that hold her answers

    var businessComponents: [BusinessPaperComponent]? // mixed paper: original cases and part labels

    /// Business or Economics: one engine for both (original case or texts, part-by-part marking, essay feedback).
    /// The `business…` fields above hold either subject's sets; `caseSubject` says which.
    var isCasePaper: Bool { businessSetId != nil || businessComponents != nil || caseSubjectTag != nil }
    var caseSubject: CaseSubject? { isCasePaper ? (caseSubjectTag ?? .business) : nil }
    private var caseSubjectTag: CaseSubject? { subject.flatMap(CaseSubject.init(rawValue:)) }
    var isMaths: Bool { subject == Subject.maths.slug }

    static func newID() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return "BS-" + String((0..<6).map { _ in chars.randomElement()! })
    }
}

// MARK: - Marking results

struct PartResult: Codable, Hashable {
    var label: String
    var awarded: Int
    var available: Int
    var studentAnswer: String
    var correctAnswer: String
    var feedback: String
}

struct QuestionResult: Codable, Hashable, Identifiable {
    var questionId: String
    var number: Int
    var awarded: Int
    var available: Int
    var subtopic: String
    var concept: String
    var parts: [PartResult]
    var whyLost: String
    var bigPicture: String
    var tip: String
    var uncertain: Bool?        // nil for papers marked before starred-answer support
    var isUncertain: Bool { uncertain == true }
    var needsReview: Bool { awarded < available || isUncertain }
    var id: String { questionId }
}

/// One of the "fix these" cards on the results page.
struct Fix: Codable, Hashable {
    var title: String
    var detail: String
    var wrong: String?
    var right: String?
    var subtopic: String?
    var questions: [Int]?
}

struct MarkingResult: Codable, Hashable {
    var sessionId: String
    var awarded: Int
    var available: Int
    var headline: String
    var summary: String
    var strengths: [String]
    var focusNext: [String]
    var fixes: [Fix]?            // newer results only
    var questions: [QuestionResult]
    var reviewQuestions: [QuestionResult] { questions.filter(\.needsReview) }
    var uncertainQuestions: [QuestionResult] { questions.filter(\.isUncertain) }
}

// MARK: - Progress

struct Attempt: Codable, Hashable {
    var sessionId: String
    var date: Date
    var questionId: String
    var subtopic: String
    var awarded: Int
    var available: Int
}

enum Mastery: String, Codable {
    case notStarted, red, orange, green

    var label: String {
        switch self {
        case .notStarted: "Not started"
        case .red: "Not good enough yet"
        case .orange: "One more go"
        case .green: "Nailed it"
        }
    }
}

struct SubtopicStats: Hashable {
    var mastery: Mastery
    var percent: Double?     // recent performance, 0...1
    var marksAttempted: Int
    var questionsSeen: Int
    var sessions: Int
    var lastDate: Date?
    var history: [Double]    // per session percent, oldest → newest
}
