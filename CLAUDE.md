# Biosphere — instructions for Claude Code sessions

Read this page, then start working. It tells you what the app is, how it works, which engine
owns what and the design rules. **`docs/ARCHITECTURE.md`** maps every file, on-disk format and flow;
check it to find the right file before you search the codebase.

The shared working agreement for all coding agents (branching, build/test commands, releases, product
rules, commits) is in AGENTS.md. It applies to you in full:

@AGENTS.md

(Hank's own persona — the tutor inside the app — is a different file: `app/Resources/template/CLAUDE.md`.
Don't confuse the two. Editing `~/Biosphere/CLAUDE.md` does nothing: the app overwrites it from
`app/Resources` on every launch.)

---

## 1. What Biosphere is, in one minute

A native **macOS SwiftUI app** (Swift Package in `app/`, macOS 14+, no third-party dependencies) that
helps one IB Diploma student revise **Biology SL**, **Business Management HL** and **Maths AA SL** from real
past papers. Maths is organised by **execution strategy** (the move a worded question needs, with the
wording that gives it away) rather than syllabus section; see `pipeline/maths_strategies.py`.
In code comments and prompts the student is "she" and the tutor is **Hank**.

The loop:

1. **Pick a topic** (subtopic → topic → theme → everything) on the Topics page.
2. **Pick the time** in the "How long have you got?" sheet, plus question type and study mode.
3. The app **builds a PDF** of original past-paper crops that fits the time, and loads the timer.
4. **Send to iPad** (AirDrop auto-tapped via Accessibility, or iCloud Drive). She handwrites answers and
   stars (`*`) anything she's unsure of.
5. She **sends it back**. The app spots the PDF in Downloads (the session id `BS-XXXXXX` is printed in the
   footer) or she drops it on the session.
6. **Hank marks it**: the app renders pages to PNG and runs *her own* `claude` CLI headlessly with a JSON
   Schema; results come back as structured JSON.
7. **Results** screen, then **spaced repetition** (SM-2) and the red/orange/green **Tracker** update.
8. **Ask Hank** (⌘E) is a chat panel on every screen, backed by the same CLI.

There's one real user (one IB student, stable releases) and one tester (Matt, betas). Her data in
`~/Biosphere` is precious; you work against `~/Biosphere-Dev`.

## 2. Architecture in one picture

```
SwiftUI Views ──@Environment(AppModel.self)──▶ AppModel (@Observable, @MainActor, the only state hub)
                                                  │
     Core engines (pure-ish Swift, no views) ◀────┤  Bank/Selector · ReviewEngine · ProgressStore · PDFComposer
                                                  │  Marking · Business* · PaperPack · Updater · AirDropAuto
                                                  ▼
                                   ~/Biosphere  (shared folder: JSON + PDFs + PNGs)
                                                  ▲
                                   `claude -p` run with cwd = ~/Biosphere  (Hank = CLAUDE.md + skills)
```

- **AppModel** (`Core/AppModel.swift`) owns all UI state and orchestrates every action. Views stay thin and
  call model methods. Sheets open by setting optional model properties (`timeRequest`, `businessRequest`,
  `businessPracticeRequest`); navigation is `model.selection` + `model.openSession`.
- **The workspace is the integration surface.** The app writes `answer_key.json` / `business.json`,
  `pages/page-NN.png` and `progress_summary.json`; Hank reads them; the app reads Hank's JSON back.
  Hank can also create sessions by writing `requests/*.json`, which the app polls for.
- Everything persists as JSON files via `JSON.save/load` (snake_case keys, ISO-8601 dates). There is no
  database and no server; the only network calls are GitHub Releases (updates, paper pack) and the CLI.

## 3. The engines (where the logic lives)

| Engine | File(s) | Responsibility |
|---|---|---|
| Question bank + selection | `Core/Bank.swift`, `Core/RevisionScope.swift`, `Core/Subject.swift` | One `Bank` each for Biology and Maths (`AppModel.bank` = the one on screen, `bank(for:)` per session); Maths drills use cut-down drill items, mixes use whole questions. Load bank; build the pool for a scope + `QuestionFormat`; `Selector` picks questions to fit the minutes (unseen first, **newest exam session first**, ~40 % MCQ time, MCQs printed first, round-robin across subtopics, weak subtopics weighted up). |
| Spaced repetition | `Core/Review.swift` | SM-2 variant replayed from attempts: grade from % → interval/ease; `StudyMode` smart / fresh / mistakes / due. |
| Progress + mastery | `Core/Progress.swift` | `progress.json` attempts; red < 50 %, green ≥ 75 % over ≥ 8 marks and ≥ 2 sessions (latest ≥ 65 %), else orange; writes `progress_summary.json` for Hank. |
| PDF building | `Core/PDFComposer.swift`, `Core/Business.swift` (`BusinessComposer`), `Core/BusinessMixedPaper.swift` | Vector crops of original papers on A4 with purple headers, answer lines and the `BS-XXXXXX` footer; Business = guide page → original case → answer pages. |
| Reading handwriting | `Core/Ink.swift`, `Core/Reader.swift` | The app diffs her returned PDF against the one it made to find her ink (and exact line rectangles); a cheap reader model (Haiku by default) transcribes only that, verbatim. |
| Marking | `Core/MarkingPipeline.swift`, `Core/MarkerInput.swift`, `Core/Marking.swift`, `Core/Business.swift` (`BusinessMarking`), `Core/BusinessAnnotations.swift` | Her chosen model marks the **transcription** in one tool-less turn (images only for flagged answers); the app settles MCQs, stars and totals, and turns essay line ids into highlights on `marked.pdf`. |
| Claude bridge | `Core/ClaudeCLI.swift`, `Core/HankChat.swift`, `Core/ClaudeUsage.swift`, `Core/ChatContent.swift` | Find/scrub/run the CLI; `ask<T>` for structured calls (read-only tools); streaming chat with resume; plan-usage ring; Markdown + safe SVG diagrams. |
| Business practice | `Core/BusinessPractice.swift`, `Core/BusinessPracticeModel.swift` | Topic/unit/mixed Business papers that keep each original case and only the selected parts (+ prerequisite parts). |
| Delivery | `Core/AirDropAuto.swift`, `Core/Sharing.swift`, `Core/Permissions.swift` | One-click AirDrop to her iPad, iCloud fallback, screenshot → iPad, permission prompts only when needed. |
| Workspace + settings | `Core/Workspace.swift`, `Core/DevTools.swift` | Paths, copying bank/persona/skills into the workspace, `AppSettings`, ⌘R reload, dev-data seeding. |
| Distribution | `Core/Updater.swift`, `Core/GitHub.swift`, `Core/PaperPack.swift` | Self-update from GitHub Releases (signature-checked), paper-pack download. |

Hank's prompts are content, not code: persona `app/Resources/template/CLAUDE.md`, skills
`app/Resources/skills/*/SKILL.md` (build-session, mark-session, mark-business, explain, what-next), chat
format `HankChat.chatPrompt`. Edit them, then press **⌘R** in Biosphere Dev; no rebuild needed.

## 4. UI/UX principles (follow these for every screen)

**Who it's for.** A busy student who is easily overwhelmed. Every screen should have one obvious next step,
sensible defaults already chosen (Smart mix, 30 min, Both), and detail behind progressive disclosure
(e.g. MCQ working collapsed under "View your working").

**Look: 80 % white, 20 % purple, light mode only.** Use the design system in `Views/Theme.swift`;
never hard-code colours or reinvent components.

- Colours: `Palette.bg` (white) for content, `Palette.bg2` (lavender wash) for the sidebar/panes,
  `Palette.purple`/`violet`/`lilac` for accents and accent text, `Palette.text`/`dim`/`faint` for the text
  hierarchy, `Palette.stroke` for borders, `Palette.gradient` for primary buttons and the selected state.
  `Palette.red`/`orange`/`green` mean performance (mastery, score, usage) only.
- Components: `Card` (16 pt continuous corners, 1 pt stroke, faint purple shadow), `PrimaryButtonStyle`
  (gradient capsule, one per area), `GhostButtonStyle` (lavender capsule for secondary actions),
  `Chip`, `MasterySquare`, `UsageRing`, `PDFCropImage`, `PDFKitView` + `PDFZoomBar`, `ZoomSheet` (all in
  `Theme.swift`), plus `HankAvatar`, `StatusChip` (`SessionsView`), `ResizeHandle`, `SettingsSection`.
- Type: system font. Page titles 22–30 pt bold `.rounded`; section titles 14–16 bold; body 12–13.5;
  captions 10.5–11.5 in `dim`/`faint`; subtopic ids monospaced in `lilac`.
- Layout: scrolling content capped at `maxWidth: 1100` and centred, ~30–32 pt side padding, ~52–56 pt top
  padding (the title bar is transparent and `TopBar` floats top-right). Sheets: white, ~600 pt wide,
  26 pt padding, a 26 pt rounded bold question as the title ("How long have you got?").
- Motion: `.snappy` for toggles/panels, `.spring` for toasts; keep animation subtle. Hank honours
  Reduce Motion; keep it that way.

**Interaction rules.**
- **Topic first, then time.** Never ask for time before the topic.
- Feedback goes through `model.say(_:)` toasts (Hank avatar + one short line) and `notify` for background
  events. No alert dialogs for routine errors; say what to do next in plain words.
- Long work shows Hank working: the marking log, "Hank is choosing your questions…", Hank's moods.
- Ask for permissions only at the moment they're needed (Downloads is watched only while a paper is out).
- Opening Hank never sends a prompt. Suggestions are offered, not auto-sent.
- Never show her file paths, JSON or internal ids (the session id on the PDF footer is the exception).
- Add `.help(...)` tooltips to icon-only buttons and keep the keyboard shortcuts working (⌘E, ⇧⌘S, ⌘R, ⌘1,
  ⌘+/⌘−/⌘0 in PDF views).
- The generated PDFs follow the same look: purple gradient title band, lilac question bars with a purple
  "Question n" pill, clear answer space, footer with the session id.

**Voice.** Second person ("you"), warm, upbeat, short. Explain the *why* behind a rule. Hank sounds like a cool
biology teacher (Crash Course energy, Amoeba Sisters clarity, Save My Exams layout). Chat answers follow
`HankChat.chatPrompt`: bold one-line answer → ≤ 4 numbered steps → one 🧠 analogy → `> **Exam tip:**` →
quick check. Canned lines live in `HankLines`.

## 5. Code conventions

- Swift 5.10, SwiftUI + AppKit where needed (PDFKit, NSWindow, Accessibility, WebKit). `@Observable` +
  `@MainActor` for model classes; `enum` namespaces for stateless engines (`Selector`, `Marking`,
  `PDFComposer`, `ReviewEngine`). Heavy work (PDF rendering, folder listing) goes in `Task.detached`.
- Match the surrounding style: short doc comments (`///`) that explain *why*, compact one-line guards,
  no extra abstraction layers. Comments use "she" for the student.
- **Persisted models must stay backward-compatible.** New fields on anything saved to disk
  (`StudySession`, `MarkingResult`, `BusinessResult`, `AppSettings`…) are optional or defaulted;
  `AppSettings` needs a line in its tolerant `init(from:)`. Old learner data must still decode (there are
  tests for this).
- Changing what Hank returns means changing **four places together**: the Swift `Codable` type, its JSON
  Schema (`Marking.schema`, `BusinessMarking.schema`, `SessionPlan.schema`), the skill that instructs Hank,
  and the view that shows it. Validate Hank's output in Swift; never trust it blindly
  (see `SessionPlan.validatedQuestions`, `BusinessMarking.validate`).
- Bank files under `app/Resources/bank/` are generated by `pipeline/`. Fix the pipeline or labels, then
  rebuild; don't hand-edit `questions.json`/`sets.json`.

## 6. Where to change what

| Task | Touch |
|---|---|
| New setting | `AppSettings` (+ tolerant decode) in `Workspace.swift`, UI in `SettingsView.swift` |
| How questions are chosen | `Selector` in `Bank.swift` (+ `RevisionTests`) |
| Spaced-repetition or mastery rules | `Review.swift` / `ProgressStore.stats` (keep `progress_summary.json` + `what-next` skill in sync) |
| Biology paper layout | `PDFComposer.swift` (keep the footer session id: return detection depends on it) |
| Marking output / results screen | `Marking.swift` + `Models.swift` + `skills/mark-session` + `ResultsView.swift` |
| Business marking | `Business.swift` (`BusinessMarking`, `BusinessResult`) + `skills/mark-business` + `marking-pack.md` + `BusinessResultsView.swift` |
| Hank's voice / chat format | `app/Resources/template/CLAUDE.md`, `HankChat.chatPrompt` (+ `HankChatTests`) |
| A new screen in the sidebar | `AppModel.SidebarItem`, `Sidebar` + `RootView.content`, `AppModel.screenContext()` |
| A new sheet | optional `AppModel` property + `.sheet(item:)` in `RootView` |
| Hank's look / moods | `HankAvatar.swift` (preview with `HankPreview`) |

## 7. Gotchas

- Worktrees have no past-paper PDFs (git-ignored). `PaperPack` copies them from `~/Biosphere` when it can;
  building a paper fails with a toast if they're missing.
- `ClaudeCLI` strips inherited `CLAUDE*`/`ANTHROPIC_*` env vars so a parent Claude Code session can't leak
  into her CLI. Keep that if you touch process launching.
- Structured calls (`ClaudeCLI.ask`) only get read-only tools; the chat additionally gets Write/Edit/Skill/
  WebFetch. Don't widen these casually. Every call passes `--strict-mcp-config` so her claude.ai connectors
  don't add tool definitions to each request.
- **Never send page images to the marking model.** Marking goes reader (cheap, sees her ink) → marker (her model,
  sees text). If you need more from the paper, add it to the reader's output, not the marker's input.
- Chat diagrams are SVG run through an allow-list validator and shown in a script-free, network-free web
  view (`ChatContent.swift`, `ChatDiagramView.swift`). Keep both layers.
- Business has no due-date review yet: `StudyMode.due` is deliberately unavailable there.
- Business Paper 3 is never split into parts; Paper 1 Section B is "answer one of two" (`choice`).
- `swift test` must pass before a PR; `ScreenSnapshotTests` only runs with `BIOSPHERE_SNAPSHOTS` set.
- When you add, move or delete files or change a data format, update `docs/ARCHITECTURE.md` in the same PR.
