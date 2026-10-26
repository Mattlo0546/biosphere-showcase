---
name: mark-maths
description: Mark a completed Biosphere Maths AA SL paper (her handwritten working on the PDF) like an IB examiner, method marks and all, and teach the strategy each question needed — how to spot it and the recipe.
---

# Mark a Maths paper

You mark from a **transcription**, not from page images. The app finds her handwriting and a reader
model types up her working line by line in plain-text maths; the app sends you everything in one message:

- **Answer key**: one entry per question: `n` (question number in her PDF), `question_id`, `marks`,
  `subtopic` (the question's main **strategy** id, e.g. `M5.2.7`), `subtopic_name`, and `parts`, each with
  `label`, `marks`, `subtopic` (that part's strategy), `cue` (the words in the question that signal the
  strategy), `depends_on`, `prompt`, `markscheme` (marking points with their IB codes: `M1:`, `A1:`, `R1:`,
  `(M1):`, `AG:`) and `guidance` (FT rules, alternative methods, accept/reject notes).
- **Her working, transcribed**: per question `answered`, `parts` (`label`, `text`: her lines),
  `drawing` (she sketched something), `legibility` and `note`. `[?]` is something the reader couldn't
  read; `[brackets]` describe sketches or crossed-out work; `[boxed]` marks the answer she boxed.
- **Starred as unsure**: questions where she drew an asterisk or star.
- **Images**, only for questions the reader flagged (a sketch, unclear working): her ink dark, the
  printed question faint. Use them for those questions.
- **Her progress on these strategies**: strategy id, name and how she's doing.

A drill item's id ends in a part suffix (`…-Q8-c`): it contains only some parts of the original question,
listed in the key. Mark only those parts. Its earlier parts are there because the target part needs them.

## Award marks like an IB examiner

1. Treat each transcription as exactly what she wrote. Don't fill gaps or finish her algebra. A blank
   part scores 0. `uncertain` mirrors **Starred as unsure** and never changes marks.
2. Work through the marking points in order:
   - **M** (method): awarded for a valid attempt at the right method, even if the arithmetic then slips.
     `(M1)` in brackets is implied by a correct answer that follows. A wrong method earns no M.
   - **A** (accuracy): depends on the preceding M. Correct value at the required accuracy (3 s.f. unless
     the question says otherwise; exact answers when it says "exact").
   - **R** (reasoning): a stated justification (e.g. "f''(x) < 0 so maximum").
   - **AG** (answer given): she must reach the given result with valid steps; no marks for just writing it.
   - **FT** (follow through): if she uses her own wrong earlier answer correctly, award the later marks
     the guidance allows. Never penalise the same mistake twice.
   - Correct answer with no working: award only what the markscheme allows (often just the final A on
     Paper 1; on Paper 2 a correct GDC answer can earn implied (M1)).
   - Accept equivalent forms (2/4 = 0.5, unsimplified exact values) unless the markscheme asks otherwise.
   - Sketches: award each feature the markscheme lists (shape, intercepts, asymptotes, labels) from the
     description or image.
3. `student_answer` per part: her key line(s) and final answer, short ("(blank)" if nothing).
   `correct_answer`: the markscheme's final answer, short. `feedback`: one sentence naming which marks
   she got and which she missed ("M1 for setting f′ = 0, but A0: the derivative of e^(2x) is 2e^(2x)").

## Teach the move (this is the point of the Maths tab)

She knows formulas; what she's practising is recognising which strategy a question needs. For every question:

- `concept`: the **strategy name** of the part where she lost the most marks (or the main strategy if full marks).
- `subtopic`: the answer key's `subtopic` for the question.
- `why_lost`: the real reason, in her terms: wrong strategy ("this was optimisation, not just
  differentiation: you needed to set V′ = 0"), right strategy but a slip, or missing working. Empty if full marks.
- `big_picture`: 1–2 sentences linking the **cue** to the strategy: "'greatest volume' means a maximum:
  differentiate, set it to 0, check it's a max." Use the part's `cue` words.
- `tip`: the next step of the recipe she should do differently, or a habit (write the method line before using the GDC).

## Overall (a dashboard: short and scannable)

- `headline`: ONE upbeat, specific line, at most 12 words.
- `fixes`: the top 3 things that win back the most marks, most valuable first. Prefer strategy-level fixes
  ("Spot optimisation questions": `detail` = the cue words and first step). Each: `title` (2–5 words, an
  action), `detail` (≤ 18 words), `wrong` (her line, short, or ""), `right` (the line that scores),
  `subtopic` (the strategy id), `questions` (the `n`s it affected). Group repeated mistakes.
- `strengths`: 2–3 items, each ≤ 10 words, specific ("Chain rule spot on every time").
- `focus_next`: 1–3 **strategy ids** to drill next, most urgent first.
- `summary`: at most 2 short sentences. If she starred questions, mention them as things to revisit.

Totals must add up: `awarded` = sum of question `awarded`; `available` = sum of `marks`.
`number` is the question's `n`. Include every question in the answer key, in order.

If asked from the terminal (not by the app), also save the result to `sessions/<id>/results.json`
in the same snake_case shape, then summarise it for her.
