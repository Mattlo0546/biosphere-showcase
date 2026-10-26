import Foundation

/// The subjects practised as whole past-paper questions with their original case or texts, marked part by part
/// with essay feedback: Business HL and Economics HL. They share one engine (`BusinessSet`, `BusinessComposer`,
/// `BusinessMarking`, the practice planner); this says which bank, guide, skill and history a set belongs to.
enum CaseSubject: String, Codable, CaseIterable, Identifiable, Hashable {
    case business = "business-hl"
    case economics = "economics-hl"

    var id: String { rawValue }
    var slug: String { rawValue }

    /// Economics set ids start with "ECO-" (the pipeline adds it), so ids never collide across subjects.
    init(setId: String) { self = setId.hasPrefix("ECO-") ? .economics : .business }

    /// The `@AppStorage("subject")` value that shows this subject on the Topics page.
    var pageKey: String { self == .business ? "business" : "economics" }
    var name: String { self == .business ? "Business HL" : "Economics HL" }
    var shortName: String { self == .business ? "Business" : "Economics" }
    var readerName: String { self == .business ? "Business Management" : "Economics" }
    var icon: String { self == .business ? "briefcase.fill" : "chart.line.uptrend.xyaxis" }
    var markingSkill: String { self == .business ? "mark-business" : "mark-economics" }
    var historyFile: String { self == .business ? "business_history.json" : "economics_history.json" }
    var markingPack: String { "bank/\(slug)/marking-pack.md" }
    func caseFile(_ setId: String) -> String { "bank/\(slug)/cases/\(setId).pdf" }

    /// Economics ships the official markscheme pages, one file per paper ("ECO-2025M-P2-TZ1-Q1" → "…-TZ1.pdf"),
    /// so her results can show the real markscheme beside her answer. Business has none (nil).
    static func markschemeURL(setId: String) -> URL? {
        guard CaseSubject(setId: setId) == .economics else { return nil }
        let paper = setId.replacingOccurrences(of: #"-Q\d+$"#, with: "", options: .regularExpression)
        let url = Workspace.bank.appendingPathComponent("economics-hl/markschemes/\(paper).pdf")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Business Paper 3 is one integrated plan of action, so it's never split; every Economics question splits.
    func keepsWhole(paper: String) -> Bool { self == .business && paper == "3" }

    /// One line per paper for the "papers to mix" picker.
    var paperBlurbs: [(String, String)] {
        self == .business ? [("1", "case study"), ("2", "short cases"), ("3", "social enterprise")]
                          : [("1", "essays"), ("2", "data response"), ("3", "policy paper")]
    }

    /// Extra minutes to read a case before writing: a whole Business Paper 1/3 case is long, a P2 stimulus is short.
    /// Economics paces already include reading (105 min for 40 marks), so it only adds a short skim.
    func readingAllowance(paper: String) -> Int {
        switch (self, paper) {
        case (.business, "2"): 4
        case (.business, _): 8
        case (.economics, "1"): 1
        case (.economics, _): 3
        }
    }

    /// The "how to get the marks" guide printed on the first page of the PDF and shown on the Topics page.
    var commandRules: [(String, String)] {
        self == .business ? BusinessComposer.commandRules : EconomicsGuide.commandRules
    }

    func guideSections(for set: BusinessSet) -> [(title: String, lines: [String])] {
        switch self {
        case .business:
            var out: [(String, [String])] = []
            if set.hasExtended && set.paper != "3" { out.append(("The 10-marker: five steps, and why each one matters", BusinessComposer.tenMarkerSteps)) }
            if set.paper == "3" { out.append(("Paper 3, question 3 (17 marks): how the plan is marked", BusinessComposer.paper3Steps)) }
            if set.hasExtended { out.append(("SWOT and STEEPLE: when they help, and when they waste your time", [BusinessComposer.swotWhy])) }
            return out
        case .economics:
            var out: [(String, [String])] = []
            if set.parts.contains(where: { !$0.extended && $0.prompt.range(of: "diagram", options: .caseInsensitive) != nil }) {
                out.append(("Diagrams: where the marks are", EconomicsGuide.diagramSteps))
            }
            if set.parts.contains(where: { $0.extended && $0.marks >= 15 }) {
                out.append(("The 15-marker: four steps, and why each one matters", EconomicsGuide.fifteenMarkerSteps))
            }
            if set.paper == "1" && set.parts.contains(where: { $0.extended && $0.marks == 10 }) {
                out.append(("The 10-marker (a): explain, don't evaluate", EconomicsGuide.essayTenSteps))
            }
            if set.paper == "3" && set.parts.contains(where: { $0.extended }) {
                out.append(("The policy recommendation (10 marks)", EconomicsGuide.policySteps))
            }
            return out
        }
    }
}

/// Economics HL guide text. Every rule comes from the IB markbands and the 2022–2025 markschemes.
enum EconomicsGuide {
    static let commandRules: [(String, String)] = [
        ("Define  [2]", "The precise definition of the term in bold. **Why:** \"the idea of it\" gets 1 of 2; the second mark needs the key words (inflation is a **sustained** rise in the **general** price level)."),
        ("Calculate  [1–2]", "Show your working, give units, round to 2 decimal places. **Why:** 1 mark is for valid working, so a bare wrong answer gets 0, and an upside-down formula gets 0 too."),
        ("Sketch / Draw  [2]", "A correctly labelled diagram showing the change. **Why:** wrong or missing labels drop you to 1 of 2, even if the shift is right."),
        ("Explain, using a diagram  [4]", "Diagram **and** words that walk through it, linked to the text. **Why:** the 3–4 band needs both; a diagram on its own, or words on their own, stop at 2."),
        ("Outline / Describe  [2–4]", "Say what it is or what the data shows, briefly. **Why:** no evaluation is asked for, so it earns nothing."),
        ("Discuss / Evaluate / Recommend  [10–15]", "Weigh both sides, then judge. **Why:** see the steps below."),
    ]

    static let diagramSteps = [
        "**Big, ruled and fully labelled:** title, both axes (P and Q, or Average price level and Real GDP), every curve, the old and new equilibrium. Why: examiners mark labels first, and a mislabelled diagram loses the diagram marks however good the writing is.",
        "**Show the change with arrows and new labels** (S1 → S2, P1 → P2). Why: the mark is for showing what happens, not only the starting point.",
        "**Refer to it in your words:** \"as shown in the diagram, the price rises from P1 to P2\". Why: a diagram the answer never mentions isn't explaining anything.",
    ]

    static let fifteenMarkerSteps = [
        "**1. Define the key terms and explain the theory.** Why: knowledge and understanding is the first thing the markband checks.",
        "**2. Use the text and data by name:** \"Text B, paragraph 2 says…\", \"Table 3 shows the Gini fell from 0.41 to 0.39\". Why: the question says \"using information from the text/data\", and the top band needs effective use of it.",
        "**3. At least one relevant, labelled diagram that you explain.** Why: relevant diagrams are named in the top band; a 15-marker without one rarely gets there.",
        "**4. Evaluate, then conclude:** short run vs long run, who wins and who loses, what it depends on, priorities. End with a judgement that answers the question. Why: 13–15 needs synthesis and evaluation backed by evidence; a one-sided list stays in the middle bands.",
    ]

    static let essayTenSteps = [
        "**Define the terms, explain the theory, draw and explain a diagram.** Why: the 10-mark (a) band rewards clear explanation with a relevant diagram; evaluation isn't asked for, so it earns nothing here.",
        "**Part (b) is the 15-marker: use real-world examples.** Why: the question says \"using real-world examples\" and the top bands need them; name a real country, firm or policy and what happened.",
    ]

    static let policySteps = [
        "**Name one clear policy** and say what it's for. Why: \"recommend a policy\" needs a recommendation, not a list of options.",
        "**Explain how it works with theory and the data you were given.** Why: the top band needs the recommendation built on the information in the paper.",
        "**Weigh it:** costs, side effects, who's affected, alternatives, time lags. Then confirm or qualify your recommendation. Why: the 9–10 band needs a balanced, justified recommendation.",
    ]

    /// A gentle first go: one Paper 1 essay (75 min), then a data response and a policy question.
    static let startHere = ["ECO-2025M-P1-TZ1-Q3", "ECO-2025M-P2-TZ1-Q1", "ECO-2025M-P3-TZ0-Q2", "ECO-2025N-P1-TZ1-Q1"]
}
