import AppKit
import Observation

/// A one-off exam pack: a timed revision plan (blocks) plus the notes, tools and flashcards each block
/// points to. The content is `Resources/exam/business-hl.json`; edit it and press ⌘R in Biosphere Dev.
struct ExamPack: Codable {
    var title: String
    var subtitle: String
    var subject: String
    var onTheDay: [String]
    var blocks: [ExamBlock]
    var sections: [ExamSection]

    var totalMinutes: Int { blocks.reduce(0) { $0 + $1.minutes } }
    func section(_ id: String) -> ExamSection? { sections.first { $0.id == id } }
    func index(of block: ExamBlock) -> Int { blocks.firstIndex { $0.id == block.id } ?? 0 }

    /// Minutes from the start of the plan to the start of a block.
    func start(of block: ExamBlock) -> Int { blocks.prefix(index(of: block)).reduce(0) { $0 + $1.minutes } }

    /// The block she should be on `seconds` into the plan; the last one once time is up.
    func block(at seconds: Int) -> ExamBlock? {
        var end = 0
        for b in blocks {
            end += b.minutes * 60
            if seconds < end { return b }
        }
        return blocks.last
    }

    static var url: URL { Workspace.resources.appendingPathComponent("exam/business-hl.json") }
    static func load(from url: URL = url) -> ExamPack? { try? JSON.load(ExamPack.self, from: url) }
}

struct ExamBlock: Codable, Identifiable, Hashable {
    var id: String
    var minutes: Int
    var title: String
    var goal: String
    var sections: [String]
    var steps: [String]
    var check: String?
    var hank: String?
}

struct ExamSection: Codable, Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var icon: String?
    var cards: [ExamCard]
}

struct ExamCard: Codable {
    var title: String
    var subtitle: String?
    var items: [ExamItem]
}

/// One piece of a card. A flat bag of optional fields keeps the JSON easy to write by hand;
/// `type` says which fields the view reads.
struct ExamItem: Codable {
    enum Kind: String, Codable {
        case text, bullets, steps, formulas, table, ladder, grid, letters, tree, tip, flash, prompts
        case myFixes = "my_fixes"   // her latest Business fixes, read from business_history.json at run time
    }
    var type: Kind
    var title: String?
    var text: String?
    var items: [String]?
    var formulas: [Formula]?
    var headers: [String]?
    var rows: [[String]]?
    var lines: [Line]?
    var columns: [String]?
    var rowLabels: [String]?
    var cells: [Cell]?
    var letters: [Letter]?
    var tree: DecisionTree?
    var cards: [Flash]?
    var prompts: [Prompt]?

    struct Formula: Codable { var name: String; var formula: String; var note: String? }
    /// A row of a statement "tree": `op` is "", "+", "−", "=" or a step number.
    struct Line: Codable { var op: String; var label: String; var note: String? }
    struct Cell: Codable { var title: String; var text: String }
    struct Letter: Codable { var letter: String; var word: String; var text: String }
    struct Flash: Codable { var q: String; var a: String }
    struct Prompt: Codable { var text: String; var source: String; var set: String? }
}

/// A worked decision tree. The app does the arithmetic so the example can't disagree with itself.
struct DecisionTree: Codable {
    var question: String?
    var unit: String
    var options: [Option]

    struct Option: Codable {
        var name: String
        var cost: Double
        var outcomes: [Outcome]
        var expectedValue: Double { outcomes.reduce(0) { $0 + $1.probability * $1.value } }
        var netGain: Double { expectedValue - cost }
    }
    struct Outcome: Codable { var label: String; var probability: Double; var value: Double }

    var best: Option? { options.max { $0.netGain < $1.netGain } }

    /// "3.7", "1.45", "-1": two decimals at most, no trailing zeros.
    static func number(_ d: Double) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0; f.maximumFractionDigits = 2; f.minimumIntegerDigits = 1
        return f.string(from: NSNumber(value: (d * 100).rounded() / 100)) ?? "\(d)"
    }
}

/// Runs the plan: starts the shared timer as a two-hour "Exam prep" countdown, follows which block is due,
/// and pings her when it's time to move on. Ticked blocks persist so a relaunch doesn't lose her place.
@MainActor
@Observable
final class ExamCoach {
    static let timerId = "exam-prep"
    var pack: ExamPack? = ExamPack.load()
    /// The block shown on the right ("day" = the exam-day checklist). Follows the clock while the plan runs.
    var selected: String?
    var done: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "exam.done") ?? []) {
        didSet { UserDefaults.standard.set(Array(done), forKey: "exam.done") }
    }
    private var watcher: Timer?
    private var announced: String?

    func reload() { pack = ExamPack.load() }

    func isOn(_ timer: StudyTimer) -> Bool { timer.sessionId == Self.timerId }
    func current(_ timer: StudyTimer) -> ExamBlock? { isOn(timer) ? pack?.block(at: timer.elapsed) : nil }

    /// Starts (or resumes) the two hours. `announce` is called each time a new block comes due.
    func start(_ timer: StudyTimer, announce: @escaping (ExamBlock) -> Void) {
        guard let pack else { return }
        if !isOn(timer) {
            timer.stop()
            timer.sessionId = Self.timerId
            timer.title = "Exam prep"
            timer.total = pack.totalMinutes * 60
            timer.remaining = timer.total
        }
        timer.resume()
        announced = current(timer)?.id
        selected = announced
        watcher?.invalidate()
        watcher = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.follow(timer, announce) }
        }
    }

    private func follow(_ timer: StudyTimer, _ announce: (ExamBlock) -> Void) {
        guard isOn(timer) else { watcher?.invalidate(); watcher = nil; return }
        guard timer.running, let b = current(timer), b.id != announced else { return }
        announced = b.id
        selected = b.id
        announce(b)
    }

    /// Ticks a block and moves on to the next one.
    func finish(_ block: ExamBlock) {
        done.insert(block.id)
        guard let pack else { return }
        let i = pack.index(of: block)
        if i + 1 < pack.blocks.count { selected = pack.blocks[i + 1].id }
    }

    func startOver(_ timer: StudyTimer) {
        if isOn(timer) { timer.stop() }
        done = []
        announced = nil
        selected = pack?.blocks.first?.id
    }

    /// Clock times for a block once the plan is running ("6:40 – 6:55"); before that, nil.
    func clock(_ block: ExamBlock, _ timer: StudyTimer) -> String? {
        guard isOn(timer), let pack else { return nil }
        let begin = Date().addingTimeInterval(TimeInterval(pack.start(of: block) * 60 - timer.elapsed))
        let end = begin.addingTimeInterval(TimeInterval(block.minutes * 60))
        let f = DateFormatter(); f.timeStyle = .short
        return "\(f.string(from: begin)) – \(f.string(from: end))"
    }

    /// Her latest fixes from Business marking, so the essay page can remind her of her own habits.
    static func latestFixes() -> [String] {
        let url = Workspace.root.appendingPathComponent("business_history.json")
        guard let entries = try? JSON.load([BusinessHistoryEntry].self, from: url),
              let last = entries.max(by: { $0.date < $1.date }) else { return [] }
        return last.fixes
    }
}
