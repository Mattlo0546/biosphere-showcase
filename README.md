# Biosphere

> **About this repo.** This is the public source of Biosphere: the macOS app, the PDF pipeline, the marking
> pipeline and Hank's prompts. The question banks, exam packs and labelling data are built from IB past papers
> and markschemes, which are copyrighted, so they aren't included and the app won't build a paper without them.
> Generate your own bank from papers you own with `pipeline/` (see `pipeline/LABELING.md`).

**Built with:** Swift · SwiftUI · PDFKit · AppKit (Accessibility, AirDrop) · Python (PyMuPDF pipeline) · Claude Code CLI (headless, JSON Schema output)


A Mac app for IB Biology SL topical revision, with Hank (her own Claude Code CLI) as the tutor.

1. **Pick what to revise.** Choose a subtopic (e.g. B2.1), a whole topic (B2: mixes its subtopics),
   a whole theme, or "Mix everything — weakest first".
2. **Pick the question type and how long you've got.** Choose **Multiple choice**, **Structured writing**
   (including longer written responses), or **Both**. The choice applies to every revision mode,
   full sets and papers picked by Hank. Biosphere builds a PDF of real past-paper questions that fits the
   time (original crops with diagrams intact, purple question headers, answer space) and loads the
   timer with that time. Or switch on "Let Hank pick the questions" and Claude chooses them from
   your tracker and past mistakes.
3. **Send to iPad.** AirDrop (one tap on the iPad) or iCloud Drive. Start the timer and do the paper.
   Add a handwritten **asterisk (`*`) or star** beside any question or answer you're unsure about.
4. **Send it back.** AirDrop the annotated PDF back to the Mac. Biosphere spots it in Downloads (it
   reads the session ID printed in the footer, so renaming doesn't matter) and Hank marks it
   against the markscheme. To save her plan, marking has two steps: Biosphere finds her handwriting by
   comparing the returned PDF with the one it made, a small model (Haiku, or Sonnet in Settings) types up
   only her answers, and Hank's model marks that text. It only looks at the page itself for drawings or
   writing the reader couldn't make out.
5. **Results.** The review opens with questions that lost marks **and questions you starred as unsure**,
   even if correct. Starred questions have an **Unsure** badge and their own filter; stars don't affect
   marks. You get the score, and for each question: the original question, *your handwriting*,
   your answer next to the markscheme answer, why marks were lost, the bigger picture, a tip, a link
   to the Biology for Life page for that subtopic, and "Ask Hank about this". For multiple choice,
   the annotated scan is collapsed under **View your working**, so you can check notes and crossed-out
   choices without repeating the question by default.
6. **Spaced repetition.** Every marked question gets an Anki-style (SM-2) schedule from her score:
   under 60% comes back tomorrow; passes come back after growing gaps (~1 → 3 → 7 → 18 → 45 days).
   For any subtopic, topic, theme or everything she can choose **Smart mix** (due reviews first,
   then new questions), **New questions**, **My mistakes** (only what she lost marks on, worst first)
   or **Due for review**. The Topics page shows the review queue and "to fix" / "due" badges.
7. **Tracker.** One square per SL subtopic: grey not started, **red** under 50%, **orange** one more
   go, **green** done (75%+ across 2+ sessions). Plus a revision-days calendar and per-session history.
8. **Screenshot → iPad** (⇧⌘S): drag over anything on screen and it goes straight to the iPad.
9. **Ask Hank** (⌘E): a chat panel on the right, on every screen. Hank is her own Claude Code
   login running in `~/Biosphere`, knows what's on screen, can explain any marked question and can
   build papers from chat. The ring next to him is her real Claude plan usage (tightest limit window,
   read from the CLI's rate-limit events); hover for every limit and when it resets.
   Opening Hank starts with a fresh question composer; **Ask Hank about this** offers an explanation
   suggestion without sending it. **Resume previous chat** brings back the last conversation. Hank
   can write labelled SVG diagrams that render directly in his reply, with **Enlarge diagram** for a
   closer look (static drawings, with no scripts or external resources).


## Business Management HL

The Topics page has a **Biology SL | Business HL** switch. Business questions only make sense with their
case, so the unit is a **set**: one Paper 2 question (its stimulus and every part, usually ending in a
10-marker), or a whole Paper 1 or Paper 3.

1. **By topic:** choose a numbered syllabus section within the five units or the business toolkit.
   Practise only the relevant Paper 1 / Paper 2 parts, with their original case and any prerequisite
   calculations. **Full cases & papers** keeps complete Paper 2 questions and whole Paper 1 / Paper 3.
2. **Timed or not.** The timer is optional, in both subjects.
3. **The PDF.** A one-page guide comes first: what each command word wants and *why*, the 10-marker steps
   and the caps behind them, and when SWOT/STEEPLE helps or hurts. Then the original case pages. Recent Paper 2s
   are answered in the paper's own answer boxes; Paper 1, Paper 3 and older Paper 2s get answer pages with each
   question printed above its lines.
4. **Marking** (`/mark-business`): every part against its own markscheme section, like Biology, plus essay
   feedback for 10/17-markers: band per strand, caps hit, sentences labelled knowledge / application / analysis /
   evaluation, and her weakest paragraph moved up a band. `business_history.json` lets Hank spot habits.
5. **Further reading:** every marked part links to its section in her personal notes inside the app,
   with the matching RevisionDojo chapter alongside it. Missing personal sections use RevisionDojo.
   The supplied PDF stays unchanged; page and heading positions live in `topics.json`.

**My sessions** can be sorted by date, subject or topic, ascending or descending.

Bank: `pipeline/build_business.py` → `app/Resources/bank/business-hl/` (`sets.json`, `cases/<set>.pdf`,
`marking-pack.md`). 132 sets / 609 parts: every 2024–25 Paper 1, 2 and 3 plus 2016–2023 Paper 2 (Sections A
and B). The case PDFs ship inside the app (~25 MB), not in the paper pack.

```bash
.venv/bin/python pipeline/build_business_topics.py "/path/to/her-notes.pdf"
.venv/bin/python pipeline/build_business.py
```

The personal notes PDF and original cases are local build assets excluded from Git. Keep
`app/Resources/bank/business-hl/notes.pdf` available when building the app. Older question parts
outside the current syllabus stay in full older sets and are excluded from topic practice.

## First run

A short setup walks her through it: welcome → **sign in to Claude** (one click, browser login) →
**her iPad** (allow Biosphere under Accessibility once, press *Find my iPad* and pick it; after that
*Send to iPad* AirDrops straight to it with no picker) → **permissions** (notifications, Downloads)
→ done. It can be re-run from Settings, where she can also change the Claude **model** and **effort**.

## Installing on her Mac

1. Copy `app/dist/Biosphere.zip` over (AirDrop is fine), unzip, and drag **Biosphere** into Applications.
2. First open: the app isn't notarised, so macOS will block it. Go to **System Settings → Privacy &
   Security**, scroll down and click **Open Anyway** (or run
   `xattr -dr com.apple.quarantine /Applications/Biosphere.app` in Terminal).
3. If Claude Code isn't installed, Biosphere shows the one-line installer. Then click
   **Sign in with Claude** — it opens her Claude login in the browser. That's the only setup.
4. Allow Downloads access and notifications when asked (that's how returned papers are detected).

Everything she does lives in `~/Biosphere` (sessions, marked papers, progress). Hank's persona is
`~/Biosphere/CLAUDE.md`; skills are in `~/Biosphere/.claude/skills` (`/build-session`, `/mark-session`,
`/what-next`, `/explain`). Both are refreshed from the app on every launch.

## The question bank

`pipeline/` turns the past-paper folder into the bank that ships inside the app:

| Step | Script | Output |
|---|---|---|
| Inventory | `pipeline/inventory.py` | papers ↔ markschemes, text-layer check |
| Segment | `pipeline/segment.py "Biology SL"` | per-question crop regions + text → `pipeline/work/biology-sl/packets/` |
| Label (subagents) | spec: `pipeline/LABELING.md` | subtopic, type, marks, markscheme points per part → `labels/` |
| Validate | `pipeline/validate_labels.py`, `pipeline/check_mcq.py` | schema + an independent re-read of every MCQ answer grid |
| Build | `pipeline/build_bank.py` | `app/Resources/bank/biology-sl/` (questions.json, index.tsv, papers/) |

Current bank: 150 papers (2010–May 2026), 2,671 questions, 2,137 of them on the current (2025) SL
syllabus, covering all 34 SL subtopics. Old-syllabus option content is kept but flagged out of
syllabus and never served.

## Building the app

```bash
cd app && ./scripts/build_app.sh
```

Builds a universal `dist/Biosphere.app` (~17 MB) and `dist/Biosphere.zip`, signed with the
**Biosphere Developer** certificate. The past-paper PDFs are *not* inside the app: they're published once
as their own GitHub release (the "paper pack") and each Mac downloads them on first launch. On the
developer's Mac they're copied straight from the repo instead. `BUNDLE_PAPERS=1` makes a
self-contained build if you ever need one.

On a fresh clone, regenerate the PDFs from the local past-paper folder first:

```bash
python3 -m venv .venv && .venv/bin/pip install pymupdf
.venv/bin/python pipeline/segment.py "Biology SL" && .venv/bin/python pipeline/build_bank.py
```

## Developing (live)

- **`app/scripts/dev.sh`**: runs **Biosphere Dev** (a separate app with its own data in `~/Biosphere-Dev`)
  and rebuilds + relaunches it ~10–20 s after you save any Swift file. Leave it running in a terminal.
- **⌘R** in the app reloads Hank's persona, skills and the question bank from `app/Resources` instantly.
- **Xcode previews**: open `app/Package.swift` in Xcode, open `Views/Previews.swift`, press ⌥⌘↩. Topics,
  Tracker, the time sheet, Settings, Hank's chat, Results and Hank's moods redraw as you type.
- Coding agents (Codex, Claude) follow **`AGENTS.md`**.

## Branches, versions and releases

- **`main` = production.** Only what's released to her. **`dev` = work in progress.** Feature branches
  (`feature/…`) merge into `dev` via pull requests.
- Versions are semantic (`MAJOR.MINOR.PATCH`) and live in `app/VERSION`; each release is a git tag `vX.Y.Z`.
- **Channels.** Stable releases reach everyone. Releases marked *pre-release* (betas) only reach apps with
  **Settings › Updates › Beta updates** switched on (your Mac).
- **Updates.** The app checks GitHub Releases on launch and every 6 hours, shows **Update ready** in the
  sidebar, downloads, verifies the new app is signed with the same Biosphere Developer key, swaps it in and
  relaunches. Her data in `~/Biosphere` is untouched.

```bash
# 1. work on dev, commit, then publish a beta to test on your Mac
git checkout dev
app/scripts/release.sh 0.7.1 --beta

# 2. happy with it? ship to her
git checkout main && git merge --ff-only dev
app/scripts/release.sh 0.7.1        # (or bump: 0.8.0 for features, 0.7.2 for fixes)
git checkout dev && git merge main
```

`release.sh` checks the tree is clean, publishes the paper pack if it changed (`release_papers.sh`),
bumps `VERSION`, tags, builds and signs, pushes, and creates the GitHub release with `Biosphere.zip`.

### One-time setup (already done on Matt's Mac)

- **Signing certificate**: a self-signed "Biosphere Developer" identity in the login keychain, backed up in
  `~/.biosphere-signing/` (keep that folder safe; the `.p12` + `p12.pass` restore it on another Mac with
  `security import`). A stable signature is what lets macOS keep her permissions across updates.
- **Update key**: a fine-grained GitHub token with **Contents: read-only** on this repo only, saved to
  `~/.biosphere-update-token`. The build embeds it (lightly obfuscated) so her app can read releases. It's
  never committed. If it's ever exposed, revoke it on GitHub and publish a new build with a fresh key.
