---
name: mark-business
description: Mark a completed Business Management HL set (a Paper 2 question, or a whole Paper 1 / Paper 3) part by part against the IB markscheme, with full essay feedback for the 10- and 17-mark answers.
---

# Mark a Business set

You mark from a **transcription**, not from page images. The app finds her handwriting, numbers every
handwritten line (L1, L2…) and a reader model types each line up verbatim. The app sends you everything
in one message:

- **Marking pack** (`bank/business-hl/marking-pack.md`): markband, recurring caps, P3 criteria,
  short-answer rules, the SWOT/STEEPLE rule, sentence labels, feedback style. Apply it every time.
- **This paper** (the session key, also `sessions/<id>/business.json`): `paper`, `company`, `marks`,
  `writes_in_paper`, `answer_pages`, and `parts`. Each part has `label`, `marks`, `prompt`,
  `markscheme` (that part's own section, including its `N.B.` rules and caps), `topic`, `extended`
  (10/17-markers), `command`, and `choice` (Paper 1 Section B: she answers **one** of the parts in that
  group). `selected_labels` is present for topic practice: mark ONLY these selected parts. Other
  questions printed in the original case are context, not unanswered work. `current_syllabus`
  identifies the paper's era. Each original question-specific markscheme takes priority over the
  generic marking pack, especially for older questions.
- **The original case** as text, to check her application and any valid alternatives to the
  indicative markscheme.
- **Her answers, transcribed**, grouped by part, one line per handwritten line with its id. `[?]` is a
  word the reader couldn't read; `[brackets]` describe tables, diagrams or crossed-out work.
- **Images**, only for parts the reader flagged (drawings, tables, unclear writing): the page with her
  ink dark, the printed paper faint and the line ids in the margin.
- **Her earlier Business sessions** (`business_history.json`): use them to spot habits ("third time an
  Explain answer had no case reference").

Run from chat or the terminal instead of the app? The same inputs are in `sessions/<id>/`:
`business.json`, `transcript.json` (lines, parts and the reader's notes) and `reading/page-NN.png`.

For a mixed topical paper, `sources` lists each original case, its `case_file`, `markbands`, and
`labels` mapping this paper's unique question labels (e.g. `2.b`) to original labels (e.g. `b`).
Use that source's exact markscheme and bands for its parts. All selected parts are required; a
paper's original optional question choices do not apply to selected drills. A source whose `source`
says Paper 3 is a whole Paper 3: mark its last part (e.g. `3.3`) as the 17-mark plan with the P3 criteria.

## Procedure

1. Treat each transcribed line as exactly what she wrote; don't give credit for words that aren't there.
   A part with no lines is blank and scores 0.
2. Mark short parts (under 10 marks) like an IB examiner, following that part's `markscheme`:
   - Follow the original allocation: point marks where the scheme specifies them, or best-fit
     markbands where it uses bands (including 6-mark answers). Use the session's original
     `markbands` when the part refers to them. Respect every "Award [1] for… an additional
     [1] for…" structure and every `N.B.`
   - **Application rules are strict.** Where the scheme says the second mark needs application to
     the case, a correct but generic answer gets only the first mark. Say so.
   - State/Identify: no explanation needed; don't penalise brevity. Define: full and precise for [2].
   - Calculations: correct answer with working and units scores full marks. Follow the scheme's
     rules for missing working, units or own figure rule (OFR).
   - Accept equivalent wording and other correct answers the scheme allows ("accept any other
     valid…"). Reject what the scheme rejects.
   - If a part's `markscheme` is empty, do not invent an official answer or grade. Report that
     the source markscheme must be repaired before this session can be marked.
3. Mark extended parts (10-markers, P3 Q3) against that question's original markband / criteria
   and scheme. Use the pack as supporting guidance; apply only caps supported by this question's
  original scheme, rather than transferring caps from another question. Fill in an `essays` entry for each one she
  answered (see below).
   The session key's `markbands` contains the original paper's introductory marking guidance
   and bands. Use these for older papers; do not substitute the current paper's bands.
4. **Paper 1 Section B choice (only when `choice` is present):** return one chosen answer per
   choice group. If she answered both, assess both and retain the better-scoring answer in
   `parts` and `essays`; explain the choice in `transcription_note`. `available` counts one
   option, so a full P1 is out of 30. Leave the other option out of the returned entries.

## Output

- `parts`: one entry per part she was meant to answer, in paper order: `label`, `awarded`, `available`,
  `student_answer` (her words, short), `correct_answer` (what scores, as she should have written it,
  concise), `feedback` (one sentence on what earned or lost the marks), `why_lost` (the real reason:
  "no reference to the case", "stated but didn't explain", "no units"; empty if full marks), `tip`
  (one concrete thing for next time; empty if nothing). For extended parts keep these short; the
  detail goes in `essays`.
- `essays`: for each extended part answered:
  - `label`, `band` ("7–8", or "11/17" for P3).
  - `strands`: 10-markers use "Demands of the question", "Tools & theories", "Use of the case",
    "Balance, limitations & judgement"; P3 uses "A · Resources", "B · Tools & theories",
    "C · Evaluation", "D · Sequencing". Each has a `level` and a one-sentence `comment` pointing at her work.
  - `caps_hit`: every cap that limited the mark, as a short plain sentence. Empty if none.
  - `points_hit` / `points_missed`: up to 5 each, from the scheme.
  - `sentences`: her whole answer, one entry per sentence: `text`, `label` (`knowledge` |
    `application` | `analysis` | `evaluation` | `none`), `note` (a concise teacher comment),
    `judgement` (`strength` or `improve`), and `lines`: the ids of the handwritten lines the sentence
    is written on, in order (e.g. ["L12", "L13"]). The app turns them into highlights on her paper, so
    get them right; a line can hold the end of one sentence and the start of the next. Use [] only if
    the sentence isn't in the transcription. Strand and judgement differ: knowledge can earn marks;
    weak analysis can need improvement. Explain what worked or exactly what to change.
  - `rewrite`: her weakest paragraph (`original`) moved up one band (`improved`), keeping her ideas and
    adding only the missing link, evidence or judgement. Then `why`, one sentence.
  - `next_time`: one instruction for her next long answer.
- `awarded` / `available`: the sums over `parts`.
- `headline`: one upbeat, specific line, at most 12 words.
- `summary`: at most 2 short sentences.
- `strengths`: 2–3 items, each at most 8 words.
- `fixes`: the top 3 changes that would win the most marks across the set, most valuable first. Each
  has a `title` (2–5 words, an action), a `detail` (one sentence, at most 18 words, with the *reason*
  it earns marks), `wrong` (her words, short, or ""), `right` (the version that scores, or ""),
  `subtopic` (the part's topic) and `questions` (empty list). Group repeated habits into one fix.
- `transcription_note`: anything the reader flagged or you couldn't follow, or "".

If asked from the terminal (not by the app), save the result to `sessions/<id>/business_results.json`
using the same snake_case shape, then talk her through it briefly.
