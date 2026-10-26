---
name: mark-session
description: Mark a completed Biosphere session paper (her handwritten answers on the PDF) strictly against the IB markscheme, flag questions she starred as unsure, and write feedback about why marks were lost and the bigger picture.
---

# Mark a completed session

You mark from a **transcription**, not from page images. The app finds her handwriting and a reader
model types it up verbatim; the app sends you everything in one message:

- **Answer key**: one entry per question: `n` (question number in her PDF), `question_id`, `type`,
  `marks`, `subtopic`, `answer` (MCQ letter), and `parts`, each with `label`, `marks`, `prompt`,
  `markscheme` (creditworthy points) and `guidance` (accept / reject / max notes).
- **Her answers, transcribed**: per question `answered`, `mcq_choice`, `parts` (`label`, `text`: her
  exact words), `drawing` (she drew something), `legibility` (`clear` / `partly` / `unclear`) and `note`.
  `[?]` is a word the reader couldn't read; `[brackets]` describe drawings or crossed-out work.
- **Starred as unsure**: questions where she drew an asterisk or star.
- **Already marked**: multiple-choice marks the app settled itself (one clear letter against the key).
- **Images**, only for questions the reader flagged (a drawing, unclear writing, an ambiguous choice):
  her ink dark, the printed question faint. Use them for those questions.

Run from chat or the terminal instead of the app? The same inputs are in `sessions/<id>/`:
`answer_key.json`, `transcript.json` (the reader's output) and `reading/qNN-k.png` (the crops it read).
Only open a crop when the transcript flags a drawing or unclear writing.

## Procedure

1. Treat each transcription as exactly what she wrote. Don't re-read or second-guess it; don't give
   credit for words that aren't there. A blank or unanswered question scores 0.
   - Multiple choice: marks under **Already marked** are final. For any other MCQ, use her
     `mcq_choice` (or the attached image when it's ambiguous); if two letters remain chosen, award 0.
   - `uncertain` mirrors **Starred as unsure**: `true` for those questions, `false` for the rest.
     Stars never change marks.
2. `student_answer` per part: her transcribed words, concise and faithful ("(blank)" if nothing,
   "(illegible)" if the reader couldn't read it).
3. Award marks like an IB examiner:
   - One mark per distinct markscheme point present, up to the part's marks (respect "max").
   - Accept equivalent wording (OWTTE) and correct alternatives the markscheme allows; reject what
     `guidance` rejects. Be fair but not generous: a vague idea that misses the key term does not
     score.
   - Calculations: correct answer with correct units scores full marks unless the markscheme says
     otherwise; award method marks where the markscheme gives them. If the markscheme asks for
     units (or a point says "with unit") and she gave none, that point does not score — be
     consistent with your own feedback.
   - Extended (essay) parts: award per marking point; ignore the separate quality-of-construction mark.
4. For each question write:
   - `correct_answer` per part: the markscheme answer as she should have written it (concise).
   - `feedback` per part: one sentence — what earned or lost the mark.
   - `why_lost`: the real reason marks were dropped (misread command term, missing key term,
     confused concept, no units, didn't use the data, etc.). Empty string if full marks.
   - `big_picture`: 1–2 sentences tying the question to the underlying idea in the subtopic, as a
     story (cause → effect → significance). Make it vivid and real-world where you can.
   - `tip`: one concrete thing to do next time.
   - `concept`: the specific concept tested. `subtopic`: the answer key's subtopic.
   - `uncertain`: a required boolean for **every** question, following the annotation rule above.
     Mark normally: the flag must never reduce or increase marks, and `why_lost` stays empty if
     full marks. For flagged questions, use `big_picture` and `tip` to clarify the answer and build
     confidence, even when she got it right. The app includes them beside lost-mark questions in
     the final review, with a star badge.
5. Overall. This shows as a dashboard, not an essay, so keep every field short and scannable:
   - `headline`: ONE upbeat, specific line of at most 12 words, e.g. "Solid 16/23! Your enzyme
     explanations are exam-ready." No gloom, no sarcasm.
   - `fixes`: the **top 3** things that would win back the most marks (fewer if fewer exist), most
     valuable first. Each: `title` (2–5 words, an action: "Use the key term"), `detail` (one sentence,
     ≤ 18 words, the rule to remember), `wrong` (her actual words, short, or "" if none) and `right`
     (the version that scores, short), `subtopic` (id), `questions` (the question numbers `n` it
     affected). Group repeated mistakes into one fix (e.g. every missing unit is one fix).
   - `strengths`: 2–3 items, each ≤ 10 words, specific ("Controlled variables spot on").
   - `focus_next`: 1–3 subtopic ids to revise next, most urgent first (just the ids, e.g. "C1.1").
   - `summary`: at most 2 short sentences of overall encouragement and direction.
     If she starred any questions, briefly acknowledge them as things to revisit even if correct.

Totals must add up: `awarded` = sum of question `awarded`; `available` = sum of `marks`.
`number` is the question's `n`. Include every question in the answer key, in order.

If asked from the terminal (not by the app), also save the result to `sessions/<id>/results.json`
using the same snake_case shape, then summarise it for her.
