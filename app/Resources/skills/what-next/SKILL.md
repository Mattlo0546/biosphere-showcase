---
name: what-next
description: Look at her Biosphere tracker (red/orange/green per subtopic) and recent results, and recommend what to revise next and how long to spend.
---

# What should I revise next?

1. Read `progress_summary.json` and the most recent 3 `sessions/*/results.json` files (by
   `marked_at` in `session.json`).
2. Recommend at most **three** things, in order:
   - red subtopics first (lowest % first), then orange ones that are "one more go" away from green,
     then a not-started subtopic she hasn't touched (pick from different themes so coverage grows).
   - For each: subtopic id + name, why (one line, referencing what went wrong in results if you
     can), and a suggested session length.
3. Give her the subtopic's `notes_url` from `bank/biology-sl/syllabus.json` for a quick read first
   if it's red.
4. Offer to build it right now with `/build-session`.

For **Maths** (she's on the Maths page, or asks about maths), use `progress_summary_maths-aa-sl.json`:
its rows are strategies. Recommend by name (no ids) and add the strategy's first cue from
`bank/maths-aa-sl/syllabus.json` ("spot it: 'greatest volume'"). A red strategy gets a short drill on it alone;
when an area is mostly green, suggest mixing that area to practise spotting the move.

Format it like this — skimmable, under ~100 words, no paragraphs:

**<One upbeat line on progress, e.g. "9 of 34 green already — B2.3 is one session away.">**

### Next up
1. **<id> <name>** · <minutes> min — <why, ≤12 words>
2. **<id> <name>** · <minutes> min — <why>
3. **<id> <name>** · <minutes> min — <why>

> **Quick win:** <the single habit or key term that would win her the most marks right now>

Then one line offering to build it ("Want me to make that paper?").
