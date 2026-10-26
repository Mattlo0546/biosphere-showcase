"""Find each Maths question and lettered part in its markscheme PDF, so the results screen can show the
original markscheme crop beside her answer.

Output: pipeline/work/maths-aa-sl/markscheme_regions.json
  {question_id: {"regions": [Region...], "parts": {"(a)": [Region...], "(b)(i)": [...]}}}
Regions are fractions of the markscheme page (same shape as question regions). build_bank.py merges them
into questions.json as `ms_regions` and copies the markscheme PDFs to papers/<paper_id>-markscheme.pdf.

Markschemes are laid out the same way every year: "Section A", then each question number ("3.") in the left
margin, part letters ("(b)") in the next column, roman numerals ("(ii)") after that, and "Total [N marks]"
at the end of each question. Matching is sequential (1, 2, 3… and a, b, c… in the order the bank expects),
so the numbered general instructions at the front never get picked up.
Usage: segment_markschemes.py"""
import json, re
from pathlib import Path
import pymupdf

ROOT = Path(__file__).resolve().parent
BANK = Path("/Users/mattlo/Desktop/University/Hackathon/eexuenhack-2026/IB Past Papers/Maths AA SL")
WORK = ROOT / "work" / "maths-aa-sl"

QNUM = re.compile(r"^(\d{1,2})\.?$")
LETTER = re.compile(r"^\(([a-h])\)$")
ROMAN = re.compile(r"^\((i|ii|iii|iv|v|vi)\)$")
CONTINUED = re.compile(r"^(\(?(question|option)\s*\d*\s*continued\)?\.?|continued\W*)$", re.I)   # page-break stubs
SECTION_A = re.compile(r"^section\s*a$", re.I)
PAD = 5            # points of white space kept around a crop
HEADER = 66        # the running header ("– 7 –  M19/5/MATME/…") sits above this


def words(page):
    """Words in reading order, with a flag for "first on its line" (labels always start a line)."""
    ws = sorted(page.get_text("words"), key=lambda w: (round(w[1] / 3), w[0]))
    out = []
    for w in ws:
        left = [o for o in ws if abs(o[1] - w[1]) < 4 and o[2] <= w[0] + 1 and o is not w]
        out.append(dict(x0=w[0], y0=w[1], x1=w[2], y1=w[3], t=w[4], lead=not left,
                        after_label=all(LETTER.match(o[4]) or QNUM.match(o[4]) for o in left)))
    return out


def content_boxes(page):
    """Everything drawn on the page (text, sketches, images), below the running header."""
    boxes = [pymupdf.Rect(w[:4]) for w in page.get_text("words")]
    for d in page.get_drawings():
        r = d["rect"]
        if r.width < page.rect.width * 0.9 or r.height < 3:   # skip page frames, keep sketches and rules
            boxes.append(r)
    boxes += [pymupdf.Rect(i["bbox"]) for i in page.get_image_info()]
    return [b for b in boxes if b.y0 > HEADER and not b.is_empty]


def regions_between(doc, boxes, start, end):
    """Crop regions from (page, y) start to end, one per page, trimmed to the content that starts inside.
    The end is exclusive: the next label's line (whose top sits a hair above the label's own) stays out."""
    out = []
    for p in range(start[0], end[0] + 1):
        H = doc[p].rect.height
        lo = start[1] if p == start[0] else HEADER
        hi = end[1] if p == end[0] else H
        inside = [b for b in boxes[p] if b.y0 >= lo - 1 and b.y0 < hi]
        if not inside:
            continue
        y0, y1 = min(b.y0 for b in inside) - PAD, min(hi, max(b.y1 for b in inside) + PAD)
        stub = CONTINUED.match(" ".join(doc[p].get_text("text", clip=pymupdf.Rect(0, y0, doc[p].rect.width, y1)).split()))
        if y1 - y0 > 12 and not stub:
            out.append(dict(page=p, x0=0.035, x1=0.965, y0=round(max(y0, HEADER) / H, 4), y1=round(min(y1, H) / H, 4)))
    return out


def back(pos):
    """Just above a label: the end of whatever comes before it."""
    return (pos[0], pos[1] - 3)


def is_number(w, prev, n):
    """A question start: "3." in the left margin (some papers drop the dot), or "QUESTION 3" (2010)."""
    if w["t"].rstrip(".") != str(n):
        return False
    if prev and prev["t"].upper() == "QUESTION" and abs(prev["y0"] - w["y0"]) < 3:
        return True
    return w["lead"] and (w["x0"] < 75 if w["t"].endswith(".") else w["x0"] < 62)


def segment(doc, numbers, part_labels):
    """numbers: the question numbers the bank has for this paper, in order. part_labels: number → labels."""
    ws = [words(p) for p in doc]
    boxes = [content_boxes(p) for p in doc]
    # Start after the "Section A" heading so the numbered instructions at the front are skipped.
    begin = next(((p, w["y1"]) for p in range(len(doc)) for w in ws[p] if SECTION_A.match(w["t"])
                  or (w["t"].lower() == "section" and any(o["t"] == "A" and abs(o["y0"] - w["y0"]) < 3 for o in ws[p]))), (0, 0))
    tokens = [(p, w) for p in range(len(doc)) for w in ws[p] if (p, w["y0"]) > begin]

    # Question starts: the expected numbers, in order, in the left margin.
    starts, i = {}, 0
    want = [int(n) for n in numbers if n.isdigit()]
    prev = None
    for p, w in tokens:
        if i < len(want) and is_number(w, prev, want[i]):
            starts[str(want[i])] = (p, w["y0"]); i += 1
        prev = w
    order = [str(n) for n in want if str(n) in starts]
    # Each question ends at its "Total [N marks]" line, or failing that where the next one starts.
    totals = [(p, w["y1"]) for p, w in tokens if w["t"].lower() == "total" and
              any(o["t"].startswith("[") and abs(o["y0"] - w["y0"]) < 4 for o in ws[p])]
    last = (len(doc) - 1, doc[-1].rect.height)
    out = {}
    for k, n in enumerate(order):
        s = starts[n]
        nxt = starts[order[k + 1]] if k + 1 < len(order) else last
        tot = next((t for t in totals if s < t <= nxt), None)
        e = (tot[0], tot[1] + PAD) if tot else back(nxt)
        q_tokens = [(p, w) for p, w in tokens if back(s) <= (p, w["y0"]) < e]   # "(a)" can sit a hair above "9."
        out[n] = dict(regions=regions_between(doc, boxes, s, e), parts=parts(doc, boxes, q_tokens, e, part_labels.get(n, [])))
    return out


def parts(doc, boxes, q_tokens, q_end, labels):
    """Regions for each bank part label ("(a)", "(b)(ii)"), found as sequential letter/roman starts."""
    letters = list(dict.fromkeys(m.group(1) for L in labels if (m := re.match(r"\(([a-h])\)", L))))
    if not letters:
        return {}
    starts, i, col = {}, 0, None
    for p, w in q_tokens:
        if i < len(letters) and (w["lead"] or w["after_label"]) and LETTER.match(w["t"]) and w["t"][1] == letters[i]:
            if col is None or abs(w["x0"] - col) < 12:   # letters line up in one column
                col = col if col is not None else w["x0"]
                starts[letters[i]] = (p, w["y0"]); i += 1
    found = [L for L in letters if L in starts]
    spans = {}
    for k, L in enumerate(found):
        end = back(starts[found[k + 1]]) if k + 1 < len(found) else q_end
        spans[L] = (starts[L], end)
    out = {}
    for L in found:
        s, e = spans[L]
        out[f"({L})"] = regions_between(doc, boxes, s, e)
        romans = [m.group(1) for lab in labels if (m := re.match(rf"\({L}\)\((i|ii|iii|iv|v|vi)\)$", lab))]
        rs, j = {}, 0
        for p, w in q_tokens:
            if j < len(romans) and s <= (p, w["y0"]) < e and (w["lead"] or w["after_label"]) and \
                    ROMAN.match(w["t"]) and w["t"][1:-1] == romans[j]:
                rs[romans[j]] = (p, w["y0"]); j += 1
        rfound = [r for r in romans if r in rs]
        for k, r in enumerate(rfound):
            # (i) usually sits on the same line as (b), so the first roman part starts with its letter.
            out[f"({L})({r})"] = regions_between(doc, boxes, s if k == 0 else rs[r], back(rs[rfound[k + 1]]) if k + 1 < len(rfound) else e)
    # A label the markscheme doesn't split (e.g. no roman numerals printed) falls back to its letter.
    return {lab: out.get(lab) or out.get(lab[:3]) for lab in labels if out.get(lab) or out.get(lab[:3])}


def main():
    papers = {p["id"]: p for p in json.load(open(WORK / "papers.json"))}
    result, stats = {}, [0, 0, 0, 0]
    for pk in sorted((WORK / "labels").glob("*.json")):
        pid = pk.stem
        paper = papers.get(pid)
        if not paper or not paper.get("markscheme"):
            continue
        labels = json.load(open(pk))["questions"]
        numbers = [q["id"].rsplit("-Q", 1)[1] for q in labels]
        part_labels = {q["id"].rsplit("-Q", 1)[1]: [str(p.get("label") or "") for p in q["parts"]] for q in labels}
        doc = pymupdf.open(BANK / paper["markscheme"])
        seg = segment(doc, numbers, part_labels)
        for n, s in seg.items():
            result[f"{pid}-Q{n}"] = s
            want = [L for L in part_labels[n] if L]
            stats[2] += len(want); stats[3] += sum(1 for L in want if L in s["parts"])
        stats[0] += len(numbers); stats[1] += len(seg)
        missing = [n for n in numbers if n not in seg]
        if missing:
            print(f"{pid}: no markscheme found for Q{', Q'.join(missing)}")
    (WORK / "markscheme_regions.json").write_text(json.dumps(result, indent=1))
    print(f"questions {stats[1]}/{stats[0]}, parts {stats[3]}/{stats[2]}")


if __name__ == "__main__":
    main()
