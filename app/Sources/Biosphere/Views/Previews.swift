#if DEBUG
import SwiftUI

// Live previews for Xcode's canvas: open app/Package.swift in Xcode, open this file (or any view file),
// and press ⌥⌘↩ to show the canvas. Edits to the views redraw within a second, no app restart.
// Previews use the dev data folder (~/Biosphere-Dev), never her real data.

@MainActor
enum PreviewSupport {
    static let model: AppModel = {
        AppModel.seedDevDataIfNeeded()
        let m = AppModel()
        m.settings.onboarded = true
        return m
    }()

    /// A marked session to show the results screen without needing a real marked paper.
    static var sampleSession: StudySession {
        if let real = model.sessions.first(where: { $0.status == .marked }) { return real }
        return StudySession(id: "BS-PREVW1", title: "B2.1 Membranes and membrane transport", subtitle: "30-minute session",
                            kind: .subtopic, scope: ["B2.1"], questionIds: sampleResult.questions.map(\.questionId),
                            totalMarks: 9, minutes: 30, createdAt: .now, status: .marked, score: 6)
    }

    static var sampleResult: MarkingResult {
        if let s = model.sessions.first(where: { $0.status == .marked }), let r = model.results(s) { return r }
        let ids = Array((model.bank?.pool(for: ["B2.1"]) ?? []).prefix(3).map(\.id))
        func q(_ i: Int, _ got: Int, _ of: Int, _ why: String) -> QuestionResult {
            QuestionResult(questionId: i < ids.count ? ids[i] : "missing", number: i + 1, awarded: got, available: of,
                           subtopic: "B2.1", concept: "Osmosis", parts: [
                               PartResult(label: of > 1 ? "(a)" : "", awarded: got, available: of,
                                          studentAnswer: "water moves to where there's more salt",
                                          correctAnswer: "water moves from low to high solute concentration through a partially permeable membrane",
                                          feedback: got == of ? "Spot on." : "Name the membrane and use 'solute concentration'.")],
                           whyLost: got == of ? "" : "Vague wording: no mention of the partially permeable membrane.",
                           bigPicture: "Water follows solutes: it's why salted slugs shrivel and fresh-water fish never drink.",
                           tip: "Always say 'partially permeable membrane' in osmosis answers.", uncertain: nil)
        }
        return MarkingResult(sessionId: "BS-PREVW1", awarded: 6, available: 9, headline: "Nice 6/9! Osmosis is nearly there.",
                             summary: "Strong on diffusion; tighten the osmosis wording.",
                             strengths: ["Diffusion explained clearly", "Good use of data"], focusNext: ["B2.1"],
                             fixes: [Fix(title: "Name the membrane", detail: "Osmosis answers need 'partially permeable membrane'.",
                                         wrong: "water moves to more salt", right: "water moves across a partially permeable membrane to higher solute concentration",
                                         subtopic: "B2.1", questions: [2])],
                             questions: [q(0, 1, 1, ""), q(1, 1, 4, "x"), q(2, 4, 4, "")])
    }

    static func withChat(_ m: AppModel) -> AppModel {
        if m.chat.messages.isEmpty {
            m.chat.messages = [
                ChatMessage(role: .user, text: "why do enzymes stop working when it's hot?"),
                ChatMessage(role: .tutor, text: """
                **Heat changes the enzyme's shape, so the substrate no longer fits. This is denaturation.**

                ### How it works
                1. Heat makes the enzyme vibrate more.
                2. Bonds holding its 3D shape break.
                3. The **active site** changes shape.
                4. The substrate can't bind, so the reaction stops.

                🧠 Like a key melted in the oven: same metal, wrong shape.

                > **Exam tip:** write "the **active site** changes shape so the **substrate** no longer fits": never "the enzyme dies".

                ### Quick check
                Why does the rate go *up* before the enzyme denatures?
                """),
            ]
        }
        return m
    }
}

#Preview("Topics", traits: .fixedLayout(width: 1000, height: 800)) {
    ReviseView().environment(PreviewSupport.model)
}

#Preview("Tracker", traits: .fixedLayout(width: 1000, height: 800)) {
    TrackerView().environment(PreviewSupport.model)
}

#Preview("Time sheet") {
    TimeSheet(scope: .subtopic("B2.1")).environment(PreviewSupport.model)
}

#Preview("Settings", traits: .fixedLayout(width: 860, height: 900)) {
    SettingsView().environment(PreviewSupport.model)
}

#Preview("Hank chat", traits: .fixedLayout(width: 400, height: 760)) {
    HankPanel(width: 400).environment(PreviewSupport.withChat(PreviewSupport.model))
}

#Preview("Results", traits: .fixedLayout(width: 1000, height: 900)) {
    ResultsView(session: PreviewSupport.sampleSession, result: PreviewSupport.sampleResult, back: {})
        .environment(PreviewSupport.model)
}

#Preview("Hank moods") {
    HStack(spacing: 18) {
        ForEach(HankMood.allCases, id: \.self) { m in
            VStack(spacing: 6) { HankAvatar(size: 64, mood: m); Text(m.rawValue).font(.caption) }
        }
    }
    .padding(24)
    .background(.white)
}
#endif
