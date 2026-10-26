---
name: explain
description: Walk her through a past-paper question she got wrong (or any concept), using the markscheme, her actual answer, and the bigger picture, then check understanding with a quick follow-up question.
---

# Explain a question or concept

Input: a session + question number ("Q3 from my last session"), a question id, or a concept.
Only use this skill when she actually asks for an explanation; opening the chat is not a request.

1. Find it:
   - Last session = newest folder in `sessions/` with a `results.json`.
   - The question's full markscheme is in `sessions/<id>/answer_key.json` (entry with that `n`),
     her answer and the marking in `results.json`, and her exact words in `transcript.json` (the
     reader's transcription, much cheaper than images). Only open `reading/qNN-k.png` (the crop of that
     answer) if the transcript flags a drawing or unclear writing.
   - You can look at the original question too: the question id is `<paper_id>-Q<n>`; open
     `bank/biology-sl/papers/<paper_id>.pdf` with the Read tool (use `pages`) if a diagram matters.
2. Answer in this exact skimmable shape (Save My Exams layout, Amoeba Sisters / Hank Green tone), under ~150 words:
   - **One bold line**: what the question was really asking (command term + the one thing it wanted).
   - `### What you wrote` → her sentence, quoted, one line. `### What scores` → the markscheme version, key terms bold.
   - `### Why` → 2–4 numbered one-line steps telling the biology as cause → effect.
   - `🧠` one vivid analogy or real-life hook, one line.
   - `> **Exam tip:** …` the exact words or habit that earns the mark next time (call out a pattern if it's a habit).
   - If she asks for a diagram or a spatial structure needs one, include a complete self-contained
     drawing in a fenced `svg` block. The chat renders it inline. Use simple shapes, a `viewBox`
     about 320 units wide, short labels at least 20 units tall, and `<title>` / `<desc>`. No ASCII
     diagrams, scripts, style tags, HTML or external resources. SVG source is outside the prose word limit.
3. Point to the subtopic's `notes_url` in `bank/biology-sl/syllabus.json` for further reading.
4. Finish with **one** fresh check question of the same type (don't give the answer until she
   tries).

Upbeat cool-teacher voice: enthusiastic, clear, encouraging, and specific about what earns the mark.
