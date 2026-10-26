import Foundation

/// A hand-picked Maths mock exam: whole past-paper questions in the order a real AA SL paper runs
/// (short Section A questions first, long Section B calculus at the end). The list lives in
/// `Resources/exam/maths-aa-sl-mock.json`; edit it and press ⌘R in Biosphere Dev.
struct MathsMock: Codable {
    var title: String
    var subtitle: String
    var minutes: Int
    var questionIds: [String]

    static var url: URL { Workspace.resources.appendingPathComponent("exam/maths-aa-sl-mock.json") }
    static func load(from url: URL = url) -> MathsMock? { try? JSON.load(MathsMock.self, from: url) }

    /// The questions in paper order; nil if any id has gone missing from the bank (so a stale list never
    /// prints a half paper).
    func questions(in bank: Bank) -> [Question]? {
        let qs = questionIds.compactMap { bank.question($0) }
        return qs.count == questionIds.count ? qs : nil
    }
}

extension AppModel {
    /// Builds the mock as a timed session, the same way a Hank-planned paper is built.
    func buildMathsMock() {
        guard let bank = maths, let mock = MathsMock.load(), let qs = mock.questions(in: bank) else {
            say("The mock exam isn't ready yet. Press ⌘R or update Biosphere."); return
        }
        createSession(kind: .timed, title: mock.title, subtitle: mock.subtitle,
                      scope: Array(Set(qs.map(\.primary))).sorted(), questions: qs, minutes: mock.minutes, from: bank)
    }
}
