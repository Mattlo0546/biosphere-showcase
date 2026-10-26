# Biosphere question labelling spec

You are labelling IB Biology SL past-paper questions so a student can revise topic by topic and
Claude can later mark her handwritten answers against the markscheme.

## Inputs

- Packets: `pipeline/work/biology-sl/packets/<PAPER_ID>.json` — one per paper. Each has
  `paper` (metadata, `source` and `markscheme` paths relative to the bank), `questions`
  (id, number, extracted text, detected parts `parts`, detected marks `marks_found`) and
  `markscheme_text` (the whole markscheme, extracted text).
- Bank root (original PDFs): `/Users/mattlo/Desktop/University/Hackathon/eexuenhack-2026/IB Past Papers/Biology SL/`
  If the question text or markscheme text is missing, garbled or ambiguous (e.g. an MCQ answer
  grid that didn't extract, or a question that depends on a diagram), open the original PDF with
  the Read tool (use the `pages` parameter) and look. Do not guess an MCQ answer.
- Syllabus: `bank/biology-sl/syllabus.json` — the CURRENT IB Biology syllabus (first exams 2025).
  Every label must use these subtopic ids (e.g. `B2.1`). HL-only subtopics (`hl_only: true`) are
  not in SL.

Old papers (2010–2024) were written for older syllabuses. Map their content onto the current
syllabus. A question whose content is not in the current SL syllabus at all (e.g. old option
topics like microbes/biotechnology, neurobiology & behaviour beyond C2.2, human nutrition
details, exercise physiology, HL-only content) gets `"in_syllabus": false` but is still fully
labelled with the closest subtopic.

## Output

Write `pipeline/work/biology-sl/labels/<PAPER_ID>.json` (UTF-8, valid JSON, no comments):

```json
{
  "paper_id": "2019M-P2-TZ1",
  "questions": [
    {
      "id": "2019M-P2-TZ1-Q1",
      "type": "mcq | structured | extended",
      "in_syllabus": true,
      "primary_subtopic": "C3.2",
      "subtopics": ["C3.2", "C4.1"],
      "title": "Ebola epidemic data",
      "concepts": ["pathogen transmission", "interpreting epidemiological graphs"],
      "skills": ["data analysis"],
      "difficulty": 2,
      "total_marks": 12,
      "parts": [
        {
          "label": "(a)(i)",
          "marks": 1,
          "subtopic": "C3.2",
          "prompt": "State the country with the highest number of deaths.",
          "markscheme": ["Liberia"],
          "guidance": "Accept ... / Do not accept ...",
          "concept": "reading data from a table"
        }
      ]
    }
  ]
}
```

Rules:

- One entry per question id in the packet, same ids, same order. Never drop or invent ids.
  If the packet's segmentation is clearly wrong (e.g. one question's text contains two
  questions), still label each id as best you can and add `"segmentation_issue": "<what's wrong>"`.
- `type`: `mcq` for Paper 1 / 1A multiple choice; `extended` for essay-style questions
  (old Paper 2 Section B, new Paper 2 Section B, marks usually 4–8 per part with no answer lines);
  otherwise `structured`.
- MCQ: exactly one part with `label: ""`, `marks: 1`, `markscheme: ["C"]` (the correct letter
  only, from the markscheme), and set a top-level `"answer": "C"`. `prompt` is a one-line
  paraphrase of what is asked.
- Structured / extended: one entry per markable leaf part, labels in the form `(a)`, `(b)(ii)`
  etc. `marks` from the `[n]` in the question paper (the `marks_found` list helps). Total of part
  marks must equal `total_marks`. `prompt`: the part's command term + task, shortened to one line
  but keeping what is needed to mark it. `markscheme`: the list of creditworthy marking points,
  each a short string, faithful to the markscheme (one bullet per mark point, include "max N" in
  guidance when the markscheme caps marks). Put accept/reject/OWTTE notes in `guidance`.
  For Section B choices ("Answer two questions"), label every question anyway.
- `primary_subtopic`: the single best subtopic for revising this question. `subtopics`: all
  subtopics the question draws on (primary first). Per-part `subtopic` too.
- `title`: 2–6 words, like a textbook heading. `concepts`: 1–4 specific concepts tested.
  `skills`: any of `recall`, `application`, `data analysis`, `calculation`, `experimental design`,
  `drawing`, `extended writing`. `difficulty`: 1 easy, 2 medium, 3 hard (for an SL student).
- Do not copy whole paragraphs of question text; paraphrase prompts briefly.

When finished with a paper, validate your file:
`/Users/mattlo/Desktop/University/Hackathon/biosphere/.venv/bin/python pipeline/validate_labels.py <PAPER_ID>`
and fix anything it reports before moving to the next paper.
