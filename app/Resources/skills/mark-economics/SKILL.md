---
name: mark-economics
description: Mark a completed Economics HL question (a Paper 1 essay, a Paper 2 data response or a Paper 3 policy question) part by part against the IB markscheme, with full essay feedback for the 8-, 10- and 15-mark answers.
---

# Mark an Economics question

Economics runs on the same engine as Business, so the files and output shape are the Business ones.
You mark from a **transcription**, not from page images. The app finds her handwriting, numbers every
handwritten line (L1, L2…) and a reader model types each line up verbatim. The app sends you everything
in one message:

- **Marking pack** (`bank/economics-hl/marking-pack.md`): command-word rules and why, diagrams,
  long-answer expectations, sentence labels, feedback style. Apply it every time.
- **This paper** (the session key, also `sessions/<id>/business.json`; `subject` is `economics-hl`):
  `paper`, `company` (the question's title), `marks`, `writes_in_paper`, `answer_pages`, `markbands`
  (the original paper's bands) and `parts`. Each part has `label`, `marks`, `prompt`, `markscheme`
  (that part's own section, with its level descriptors and N.B. rules), `topic`, `extended` (marked on
  bands, with essay feedback) and `command`. `selected_labels` is present for topic practice: mark ONLY
  these parts. Other questions printed in the original paper are context, not unanswered work.
  `current_syllabus` is false for 2016–2021 questions: use their own markscheme and bands.
- **The original question** as text: the texts, tables and figures she answered from.
- **Her answers, transcribed**, grouped by part, one line per handwritten line with its id. `[?]` is a
  word the reader couldn't read; `[brackets]` describe diagrams, tables or crossed-out work.
- **Images**, only for parts the reader flagged (diagrams, tables, unclear writing): the page with her
  ink dark, the printed paper faint and the line ids in the margin. **Diagrams are marked from these.**
- **Her earlier Economics sessions** (`economics_history.json`): use them to spot habits ("third time a
  diagram had no axis labels").

For a mixed topical paper, `sources` lists each original question, its `case_file`, `markbands`, and
`labels` mapping this paper's unique labels (e.g. `2.c`) to the original labels (e.g. `c`). Use that
source's exact markscheme and bands for its parts. All selected parts are required.

## Procedure

1. Treat each transcribed line as exactly what she wrote; don't give credit for words that aren't there.
   A part with no lines and no drawing is blank and scores 0.
2. Short parts: follow the part's `markscheme` exactly: its levels (e.g. "Level 1: vague definition [1]"),
   its point marks, and every N.B. Apply the own-figure rule where the scheme allows it. Penalise
   rounding/units only as the scheme says (once per script for each type of error).
3. Diagrams: judge from the flagged image. Check the axes, the curves, the shift, the new equilibrium and
   the labels the scheme asks for. "Using a diagram, explain" needs the diagram **and** the explanation
   for the top level; say which one was missing.
4. Long parts (`extended`): place her answer in the original `markbands` (best fit), then the scheme's
   indicative content. Use the pack for what moves her up a level. Don't expect evaluation in a Paper 1
   (a) [10]. A Paper 1 (b) needs real-world examples; a Paper 2 [15] and a Paper 3 [10] need the text/data.
5. If a part's `markscheme` is empty, don't invent an official answer or grade: report that the source
   markscheme must be repaired before this part can be marked.

## Output

The same JSON as Business (`BusinessResult`).

**Write every formula, calculation, fraction or symbol as LaTeX inside `\( … \)`** (or `\[ … \]` for a worked
line on its own); the app typesets it. Keep the words outside the delimiters. Don't use `$…$` (a dollar sign
means money here). For example, `correct_answer`:
`\(\text{PES} = \dfrac{\%\Delta Q_s}{\%\Delta P} = \dfrac{29.73}{4.94} = 6.02\)`, or a `tip`: "Show both
\(\%\Delta\) steps before dividing." Use it in `student_answer`, `correct_answer`, `feedback`, `why_lost`, `tip`
and the fixes' `detail`/`wrong`/`right`. Supported: `\frac`, `^`, `_`, `\sqrt`, `\text{}`, Greek letters,
`\times \div \approx \le \ge \rightarrow \uparrow \downarrow`. In JSON, escape each backslash (`\\frac`).

- `parts`: one entry per part she was meant to answer, in paper order: `label`, `awarded`, `available`,
  `student_answer` (her words, short; describe a diagram in brackets), `correct_answer` (what scores, as
  she should have written it, concise), `feedback` (one sentence), `why_lost` (the real reason: "definition
  missed 'sustained'", "diagram had no labels", "no reference to Table 2"; empty if full marks), `tip`
  (one concrete thing for next time; empty if nothing).
- `essays`: for each extended part answered:
  - `label`, `band` (the level and mark range, e.g. "Level 3 · 7–9").
  - `strands`: "Terms & theory", "Diagrams", "Evidence" (text/data or real-world examples) and
    "Evaluation & judgement" (for a Paper 1 (a) set its level to "not required"). Each has a `level` and
    a one-sentence `comment` pointing at her work.
  - `caps_hit`: anything in the bands or scheme that limited the mark ("no real-world example", "no
    diagram"), as a short plain sentence. Empty if none.
  - `points_hit` / `points_missed`: up to 5 each, from the scheme's indicative content.
  - `sentences`: her whole answer, one entry per sentence: `text`, `label` (`knowledge` | `application` |
    `analysis` | `evaluation` | `none`), `note` (a concise teacher comment), `judgement` (`strength` or
    `improve`), and `lines`: the ids of the handwritten lines it's written on, in order. The app turns
    them into highlights on her paper, so get them right. Use [] only if the sentence isn't in the transcription.
  - `rewrite`: her weakest paragraph (`original`) moved up one level (`improved`), keeping her ideas and
    adding only the missing step, evidence or judgement. Then `why`, one sentence.
  - `next_time`: one instruction for her next long answer.
- `awarded` / `available`: the sums over `parts`.
- `headline`: one upbeat, specific line, at most 12 words.
- `summary`: at most 2 short sentences.
- `strengths`: 2–3 items, each at most 8 words.
- `fixes`: the top 3 changes that would win the most marks, most valuable first: `title` (2–5 words, an
  action), `detail` (one sentence, at most 18 words, with the reason it earns marks), `wrong`, `right`,
  `subtopic` (the part's topic, e.g. "2.5") and `questions` (empty list). Group repeated habits into one fix.
- `transcription_note`: anything the reader flagged or you couldn't follow, or "".

If asked from the terminal (not by the app), save the result to `sessions/<id>/business_results.json`
using the same snake_case shape, then talk her through it briefly.
