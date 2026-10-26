# Biosphere question labelling spec: Maths AA SL

You are labelling IB Mathematics past-paper questions so a student can revise **by execution strategy**
and Claude can later mark her handwritten working against the markscheme.

Why strategies: she knows the formulas but often can't tell which method a worded question wants. "Find the
greatest possible area", "the minimum cost" and "the least value of" all mean *Find a maximum or minimum*.
The app groups every past-paper part by the move it needs, so she can drill one move until spotting it
is automatic, then mix moves together. Your strategy tags are what makes that work, so take care with them.

## Inputs

- The paper's packet: each question's id, number, extracted text, the lettered parts detected and the
  `[n]` marks found, plus the whole markscheme's extracted text. Maths text extraction is often garbled
  (fractions, powers and roots come out scrambled). **Open the original PDFs with the Read tool** (use the
  `pages` parameter) whenever the text is unclear: the question paper for what is asked, the markscheme
  for the marking points. Never guess a markscheme.
- The strategy catalogue (ids such as `M5.2.7`), each with the wording that typically signals it.
- Old papers (2010–2020) were written for the old Mathematics SL course. Label them the same way.

## Output, one entry per question id (same ids, same order; never drop or invent ids)

```json
{
  "id": "AA-2019M-P1-TZ1-Q8",
  "type": "structured | extended",
  "in_syllabus": true,
  "primary_subtopic": "M5.2.7",
  "subtopics": ["M5.2.7", "M5.1.1", "M3.1.1"],
  "title": "Open box of greatest volume",
  "concepts": ["optimisation", "volume of a cuboid"],
  "difficulty": 2,
  "total_marks": 14,
  "parts": [
    {
      "label": "(c)",
      "marks": 4,
      "subtopic": "M5.2.7",
      "cue": "find the value of x that gives the greatest volume",
      "depends_on": ["(b)"],
      "prompt": "Find the value of x that maximises V(x) = 4x^3 - 60x^2 + 200x.",
      "markscheme": ["M1: sets V'(x) = 0", "A1: 12x^2 - 120x + 200 = 0", "A1: x = 2.11", "R1: justifies maximum (V''<0 or graph)"],
      "guidance": "Award M1 for any attempt to differentiate and set equal to zero. FT from (b).",
      "concept": "optimisation in context"
    }
  ]
}
```

## Rules

**Parts.** One entry per markable leaf part, labels exactly like the paper: `(a)`, `(b)(ii)`. A question with
no lettered parts has a single part with label `""`. `marks` from the `[n]` (or `[n marks]`) on the paper;
part marks must add up to `total_marks`, the question's "Maximum mark". `type`: Section A (short, answered
in the box on the paper) → `structured`; Section B (long, answered in the booklet) → `extended`.

**Strategy (`subtopic`) for each part: the move, not the topic.** Pick the ONE catalogue strategy whose
recipe a student has to carry out to earn most of that part's marks.
- Tag by what the student must *do*. "Find the dimensions that give the least surface area" is `M5.2.7`
  optimisation even though it's about a cylinder. "Find the coordinates of the vertex" of a parabola is
  `M2.3.1`, but "find the maximum value of f" for a cubic is `M5.2.5`.
- A "show that" part takes the strategy it uses (a show-that about a tangent is `M5.2.2`); `M1.4.1` is only
  for algebraic proof in its own right.
- 1-mark "write down" parts still get the nearest strategy.
- On Paper 2 (calculator), a part that is essentially "put it in the GDC" still takes the strategy whose
  idea it tests (normal probability → `M4.4.3`; intersection of graphs → `M2.4.2`).
- "When is it less than / more than…", "for how long is…" on Paper 2 is usually solving with the graph
  (`M2.4.2`), not max/min, unless they ask for the greatest or least value.
- If nothing in the catalogue fits (e.g. vectors or matrices from the old course), use the closest one
  and set `in_syllabus: false` on the question.

**`cue`**: the exact words from *this* part (or the stem it relies on) that tell you which strategy to use,
copied verbatim, at most ~12 words. This is what she'll learn to spot, so choose the giveaway phrase
("the total distance travelled", "given that it is a girl"), not the whole sentence. A bare instruction
("Find V", "Find p", "Write down the value") is not a cue: quote the words that say *what kind* of thing V or p
is ("the volume of the solid formed", "the probability that exactly three"). If the giveaway is in the stem
rather than the part, quote the stem.

**`depends_on`**: the earlier *lettered* parts (e.g. `["(a)", "(b)"]`) whose results this part needs: "hence",
"using your answer to (b)", or a value/expression found earlier that the part can't be done without.
Leave it empty if the part can be done from the stem alone. Only reference earlier letters.

**Markscheme.** `markscheme` is the list of marking points in order, each starting with its IB mark code
(`M1:`, `A1:`, `R1:`, `(M1):`, `AG:`) followed by a short faithful description in plain text maths
(`x^2`, `sqrt(3)`, `pi/6`, `ln 2`, `f'(x)`). Include the final answer's accuracy where the markscheme states
it. Put alternative methods, FT rules, accept/reject notes and "N2" type notes in `guidance`.
`prompt`: the part's task in one line, keeping every number and expression needed to mark it.

**Question level.** `primary_subtopic`: the strategy carrying the most marks. `subtopics`: every strategy
used by any part, primary first. `title`: 2–6 words, textbook-style. `concepts`: 1–4. `difficulty`: 1 easy,
2 medium, 3 hard for an SL student. `in_syllabus: false` for content not in AA SL (vectors, matrices,
volumes of revolution, the old course's other HL-only bits).
