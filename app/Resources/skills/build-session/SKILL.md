---
name: build-session
description: Build a custom timed IB Biology revision session (e.g. "I have 40 minutes", "30 min on cells", "quick 15 minute MCQ blast") by choosing past-paper questions from the bank and handing them to the Biosphere app, which makes the PDF and can AirDrop it to her iPad.
---

# Build a timed revision session

Arguments: how much time she has (minutes) and optionally a focus (subtopic ids, a theme, "weak
stuff", "MCQ only", "essay practice", a concept…). If the time is missing, ask once; default 30.

## 1. Read her state

- `progress_summary.json` — status per subtopic and `seen_question_ids`.
- `bank/biology-sl/index.tsv` — the question index (columns: id, subtopic, other_subtopics, type,
  marks, minutes, difficulty, in_syllabus, year, title, concepts). Use `grep`/`awk` on it rather
  than reading the whole file if you only need part of it.

## 2. Choose questions

If she asks to **redo mistakes** or **review**, use the spaced-repetition lists in
`progress_summary.json`: `mistake_question_ids` (questions she lost marks on, worst first) and
`due_question_ids` (due on her review schedule, most overdue first). Otherwise:

- Only `in_syllabus = yes`.
- The `minutes` column is the time budget per question (MCQ 1.5 min; written 1.25 min per mark).
  Total should land within ±10% of the time she has. Never exceed it by more than 3 minutes.
- Without a focus, weight towards **red** subtopics, then **orange**, then **notStarted**; include at
  most a little **green** for retrieval practice. Interleave 2–4 subtopics rather than one block.
- Start with any `due_question_ids` in scope (up to ~40% of the time), then questions she hasn't seen
  (not in `seen_question_ids`). Prefer newer papers (2025+ were
  written for the current syllabus) but older ones are fine.
- Mix: roughly 30–45% of the time on MCQs and the rest on structured questions, unless she asked
  otherwise. Respect her question-type choice throughout, including mistakes and due reviews:
  **Multiple choice** means only `type = mcq`; **Structured writing** means only `structured` or
  `extended` (written answers); **Both** means a mix where available. A required question-format
  instruction from the app takes priority over conflicting free-text focus requests. Never fill
  a short set with a type she excluded. Avoid a single question taking more than ~60% of a short session.
- Order: MCQs first, then structured questions, then any extended (essay) question last.

## Maths AA SL

For Maths, read `progress_summary_maths-aa-sl.json` and `bank/maths-aa-sl/index.tsv` instead. Its
"subtopics" are execution strategies (`M5.2.7` = optimisation). There's no multiple choice: `minutes` is
1.1 per mark. Ids with a part suffix (`…-Q8-c`) are drill items cut from long questions: use them to drill
one strategy; use whole questions (no suffix) for mixed, exam-style practice. Never put a whole question
and one of its drill items (same id before the suffix) in the same session. To build understanding,
start a weak strategy with a short drill on just that strategy; once it's orange or green, interleave
2–4 strategies so she practises spotting which one each question needs.

## 3. Hand it to the app

Unless you were told to return JSON instead, write a file
`requests/<YYYYMMDD-HHMMSS>.json`:

```json
{
  "title": "40 minutes: membranes & enzymes",
  "minutes": 40,
  "question_ids": ["2024M-P1-TZ1-Q7", "2025M-P2-TZ1-Q3"],
  "rationale": "B2.1 and C1.1 are red; you haven't tried any 2025 data questions yet."
}
```

Titles are short (≤ 40 characters). The app watches `requests/`, builds the PDF within a few
seconds and shows it in the Sessions tab, where she can press **Send to iPad**.

Then tell her (briefly, upbeat) what you picked and why, and that it's waiting in
Biosphere.
