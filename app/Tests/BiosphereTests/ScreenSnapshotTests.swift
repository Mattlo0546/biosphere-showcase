import XCTest
import SwiftUI
@testable import Biosphere

/// Renders the main screens to PNGs without opening any window (safe to run while you're using the Mac).
///
///   cd app && BIOSPHERE_HOME=~/Biosphere-Dev BIOSPHERE_SNAPSHOTS=/tmp/biosphere-shots swift test --filter ScreenSnapshotTests
///
/// Skipped unless BIOSPHERE_SNAPSHOTS is set. Uses the dev data folder (BIOSPHERE_HOME), never real data.
@MainActor
final class ScreenSnapshotTests: XCTestCase {
    func testRenderScreens() throws {
        guard let outPath = ProcessInfo.processInfo.environment["BIOSPHERE_SNAPSHOTS"] else {
            throw XCTSkip("Set BIOSPHERE_SNAPSHOTS=<folder> to render screen snapshots.")
        }
        let out = URL(fileURLWithPath: NSString(string: outPath).expandingTildeInPath)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let model = AppModel()
        model.settings.onboarded = true

        _ = NSApplication.shared
        // Host each screen in a window that is never ordered on screen (no focus stealing, nothing visible),
        // let SwiftUI lay it out, then capture the view hierarchy. Unlike ImageRenderer this draws ScrollViews.
        func snap<V: View>(_ name: String, width: CGFloat = 1100, height: CGFloat = 900, _ view: V) {
            let host = NSHostingView(rootView: view.environment(model).frame(width: width, height: height).background(Color.white))
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: width, height: height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            for _ in 0..<6 {   // let async layout / task modifiers settle
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            }
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { XCTFail("no rep for \(name)"); return }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: out.appendingPathComponent("\(name).png"))
            }
            window.close()
        }

        // Biology
        UserDefaults.standard.set("biology", forKey: "subject")
        snap("bio-01-topics", ReviseView())
        snap("bio-02-timesheet", width: 620, height: 760, TimeSheet(scope: .subtopic("B2.1")))
        model.mix = SubtopicMix(picked: ["A1.1", "B2.1", "C1.2"])
        snap("bio-01b-mix", ReviseView())
        model.mix = SubtopicMix(topic: "B2", picked: ["B2.1"])
        snap("bio-01c-topic-mix", height: 1400, ReviseView())
        model.mix = nil
        snap("bio-02b-timesheet-mix", width: 620, height: 760, TimeSheet(scope: .custom(["A1.1", "B2.1", "C1.2"])))
        snap("bio-03-sessions", width: 1200, SessionsView())
        let marked = model.sessions.filter { $0.status == .marked }
        if let s = marked.first(where: { model.results($0) != nil }), let r = model.results(s) {
            snap("bio-04-results", height: 1600, ResultsView(session: s, result: r, back: {}))
        }
        snap("bio-05-tracker", height: 1000, TrackerView())
        snap("bio-06-settings", width: 900, height: 1700, SettingsView())
        snap("bio-07-onboarding", width: 680, height: 600, OnboardingView(isPresented: .constant(true)))
        snap("bio-08-hank", width: 400, height: 800, HankPanel(width: 400))

        // Maths: strategy rows, a strategy drill's time sheet, the strategy tracker.
        if let maths = model.maths, let first = maths.syllabus.slSubtopics.first(where: { maths.count(for: $0.id) > 0 }) {
            UserDefaults.standard.set("maths", forKey: "subject")
            snap("maths-01-topics", height: 1400, ReviseView())
            snap("maths-02-timesheet", width: 620, height: 760, TimeSheet(scope: .subtopic(first.id)))
            snap("maths-03-tracker", height: 1000, TrackerView())
            // A real strategy-drill paper (from the bank's crops) to check the "The move" card and the drill crops.
            let drill = Array(maths.pool(for: .subtopic("M5.2.5")).sorted { $0.parent != nil && $1.parent == nil }.prefix(3))
            if !drill.isEmpty {
                let s = StudySession(id: "BS-SNAPMA", title: "Find and classify stationary points", subtitle: "30-minute session · Strategy drill",
                                     kind: .subtopic, scope: ["M5.2.5"], questionIds: drill.map(\.id), totalMarks: drill.reduce(0) { $0 + $1.marks },
                                     minutes: 30, createdAt: Date(), status: .ready)
                _ = try? PDFComposer.compose(session: s, questions: drill, bank: maths, syllabus: maths.syllabus,
                                             to: out.appendingPathComponent("maths-04-drill.pdf"))
            }
            // A marked part-by-part card: each part's markscheme crop sits beside what she wrote.
            if let q = maths.question("AA-2019N-P1-TZ0-Q2") {
                let s = StudySession(id: "BS-SNAPMS", title: "Venn diagrams", subtitle: "", kind: .subtopic, scope: [q.primary],
                                     questionIds: [q.id], totalMarks: q.marks, minutes: 10, createdAt: Date(), status: .marked,
                                     subject: "maths-aa-sl")
                let parts = q.parts.map { PartResult(label: $0.label, awarded: max(0, $0.marks - 1), available: $0.marks,
                                                     studentAnswer: "18 + 10 + 5 = 33, so n = 3", correctAnswer: $0.markscheme.last ?? "",
                                                     feedback: "Method mark for a valid approach; check the final value.") }
                let r = QuestionResult(questionId: q.id, number: 2, awarded: parts.reduce(0) { $0 + $1.awarded }, available: q.marks,
                                       subtopic: q.primary, concept: q.title, parts: parts, whyLost: "", bigPicture: "Read the Venn diagram region by region.", tip: "")
                // Her "handwriting" on the working lines of a real composed paper, so each part shows its own crop.
                let dir = Workspace.sessionDir(s.id)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: dir) }
                let sent = dir.appendingPathComponent("questions.pdf")
                var reading: BiologyReading?
                if let composed = try? PDFComposer.compose(session: s, questions: [q], bank: maths, syllabus: maths.syllabus, to: sent),
                   let doc = CGPDFDocument(sent as CFURL), let working = composed.placements[q.id]?.last {
                    var box = CGRect(origin: .zero, size: PDFComposer.page)
                    let ctx = CGContext(dir.appendingPathComponent("completed.pdf") as CFURL, mediaBox: &box, nil)!
                    let written: [(part: String, text: String)] = [("(a)", "(a)  q = 30 − 18 − 10 + n … q = 5"), ("(b)", "(b)  18 + 10 + 5 = 33"),
                                                                    ("(b)", "33 − 30 = 3   so  n = 3"), ("(c)", "(c)  m = 18 − 3 = 15"),
                                                                    ("(c)", "p = 10 − 3 = 7")]
                    var anchors: [String: EssayAnchor] = [:]
                    for i in 1...doc.numberOfPages {
                        ctx.beginPDFPage(nil)
                        if let pg = doc.page(at: i) { ctx.drawPDFPage(pg) }
                        if i == working.page + 1 {
                            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
                            for (k, w) in written.enumerated() {
                                let top = working.y0 * box.height + 4 + Double(k) * 22
                                NSAttributedString(string: w.text, attributes: [.font: NSFont(name: "Noteworthy-Light", size: 15) ?? .systemFont(ofSize: 15),
                                                                                .foregroundColor: NSColor(calibratedRed: 0.1, green: 0.15, blue: 0.5, alpha: 1)])
                                    .draw(at: CGPoint(x: 48, y: box.height - top - 18))
                                anchors["L\(k + 1)"] = EssayAnchor(page: i, x: 0.08, y: top / box.height, width: 0.5, height: 20 / box.height)
                            }
                            NSGraphicsContext.current = nil
                        }
                        ctx.endPDFPage()
                    }
                    ctx.closePDF()
                    let readParts = ["(a)", "(b)", "(c)"].map { label in
                        ReadPart(label: label, text: "", lines: written.indices.filter { written[$0].part == label }.map { "L\($0 + 1)" })
                    }
                    reading = BiologyReading(questions: [ReadQuestion(n: 2, answered: true, mcqChoice: "", parts: readParts, starred: false,
                                                                      drawing: false, legibility: "clear", note: "")],
                                             model: "haiku", inkSeparated: true, anchors: anchors)
                }
                snap("maths-05-results-card", height: 1500, ScrollView { QuestionResultCard(session: s, result: r, reading: reading, open: true).padding(30) })
            }
            UserDefaults.standard.set("biology", forKey: "subject")
        }

        // Subject-specific screens (e.g. Business) can add their own snap(...) calls here.
        if let bank = model.business {
            let papers = UserDefaults.standard.string(forKey: "business.mixPapers")
            UserDefaults.standard.set("123", forKey: "business.mixPapers")
            snap("biz-01-timesheet", width: 640, height: 900, BusinessTimeSheet(scope: .everything(bank: bank)))
            UserDefaults.standard.set(papers, forKey: "business.mixPapers")
        }
        if let bank = model.economics {
            UserDefaults.standard.set("economics", forKey: "subject")
            let topic = UserDefaults.standard.string(forKey: "economics.topic")
            UserDefaults.standard.set("all", forKey: "economics.topic")
            snap("eco-01-topics", height: 2400, ReviseView())
            UserDefaults.standard.set("4.5", forKey: "economics.topic")
            snap("eco-01b-topic", height: 1800, ReviseView())
            UserDefaults.standard.set(topic, forKey: "economics.topic")
            snap("eco-02-timesheet", width: 640, height: 900, BusinessTimeSheet(scope: .topic("4.5", bank: bank)))
            if let set = bank.set(EconomicsGuide.startHere[1]) {
                snap("eco-03-sheet", width: 620, height: 760, BusinessSheet(set: set))
            }
        }
        // Exam prep: the first block, the toolkit (grids + decision tree), finance (statement trees).
        if let pack = model.exam.pack {
            for id in ["papers", "toolkit", "finance"] where pack.blocks.contains(where: { $0.id == id }) {
                model.exam.selected = id
                snap("exam-\(id)", width: 1200, height: id == "papers" ? 1500 : 3400, ExamPrepView())
            }
            model.exam.selected = "toolkit"
            snap("exam-narrow", width: 700, height: 1400, ExamPrepView())
        }
        UserDefaults.standard.set("biology", forKey: "subject")
    }
}
