"""Segment IB question papers into questions with crop regions.

Output (per subject): pipeline/work/<subject-slug>/papers.json and packets/<paper_id>.json
Each question records the page regions (fractions of page height) that contain it, so the
app can crop the original vector PDF pages and keep diagrams intact.
"""
import json, re, sys, shutil
from pathlib import Path
import pymupdf

BANK = Path("/Users/mattlo/Desktop/University/Hackathon/eexuenhack-2026/IB Past Papers")
ROOT = Path(__file__).resolve().parent
SUBJECT = sys.argv[1] if len(sys.argv) > 1 else "Biology SL"
SLUG = SUBJECT.lower().replace(" ", "-").replace("&", "and")
WORK = ROOT / "work" / SLUG
# Maths has no multiple choice, and its question ids get a prefix so they never collide with Biology's
# in progress.json (both subjects use ids like 2019M-P1-TZ1-Q3).
IS_MATHS = SUBJECT.lower().startswith("maths")
ID_PREFIX = "AA-" if IS_MATHS else ""

QNUM = re.compile(r"^([A-H]?)(\d{1,2})\s*\.$")
QNUM_INLINE = re.compile(r"^([A-H]?)(\d{1,2})\.\s+\S")
PART = re.compile(r"^\(([a-z]|[ivx]+)\)$")
MARKS = re.compile(r"^\[(\d{1,2})\]$")
FOOTER_PAT = re.compile(
    r"(This question continues|Turn over|Please do not write on this page|Blank page|"
    r"References?:|^\d{2}EP\d{2}$|^\d{4}\s*[–-]\s*\d{4}$|^[MN]\d{2}\s*/|Please do not write|"
    r"International Baccalaureate|Answers written on this page|^–\s*\d+\s*–$|^\-\s*\d+\s*\-$)", re.I)
CONT = re.compile(r"\((Question|Option)\s.*continued\)", re.I)
# Maths: marks can be "[4]" or "[4 marks]", and the printed answer boxes (dotted lines inside a frame) are
# dropped from the crop so the app can draw its own working space and cut single parts out cleanly.
MATHS_MARKS = re.compile(r"\[(\d{1,2})(?:\s*marks?)?\]\s*$", re.I)
MATHS_NOISE = re.compile(r"Do not write solutions on this page|Answers? written|Write your answers? in the answer booklet|"
                         r"^\.{3,}|(\.\s?){8,}|[\x08\ufffd]{5,}", re.I)
LETTER = re.compile(r"^\(([a-h])\)$")


def paper_id(rel: Path) -> str:
    session = rel.parent.name  # e.g. "2019 May"
    year, month = session.split()
    s = f"{year}{'M' if month.startswith('May') else 'N'}"
    stem = rel.stem
    m = re.search(r"paper_?\s*(\d[AB]?)", stem, re.I)
    p = m.group(1).upper() if m else "X"
    tz = re.search(r"TZ(\d|A)", stem)
    tz = f"TZ{tz.group(1)}" if tz else "TZ0"
    return f"{ID_PREFIX}{s}-P{p}-{tz}"


def lines_of(page):
    out = []
    d = page.get_text("dict")
    for b in d["blocks"]:
        for l in b.get("lines", []):
            spans = [s for s in l["spans"] if s["text"].strip()]
            if not spans:
                continue
            text = "".join(s["text"] for s in spans).strip()
            out.append(dict(x0=l["bbox"][0], y0=l["bbox"][1], x1=l["bbox"][2], y1=l["bbox"][3],
                            text=text, bold="Bold" in spans[0]["font"] or (spans[0]["flags"] & 16) > 0,
                            first=spans[0]["text"].strip(), size=spans[0]["size"]))
    out.sort(key=lambda l: (round(l["y0"]), l["x0"]))
    return out


def graphics_boxes(page, maths=False):
    """Vertical extents of diagrams/images, ignoring barcodes, margin bars and page frames.
    For maths, near-full-width rectangles are answer boxes, not diagrams."""
    W, H = page.rect.width, page.rect.height
    rects = []
    try:
        rects += [dr["rect"] for dr in page.get_drawings()]
    except Exception:
        pass
    rects += [pymupdf.Rect(im["bbox"]) for im in page.get_image_info()]
    boxes = []
    for r in rects:
        if r.height > H * 0.8 or r.y0 > H - 75 or r.y1 < 55:
            continue
        if r.x1 < 32 or r.x0 > W - 32:
            continue
        if maths and (r.width > W * 0.75 or (r.width < 1.5 and r.height > 150) or r.x0 < 25):   # box edges, margin hatching
            continue
        boxes.append((max(r.y0, 55), min(r.y1, H - 75)))
    return boxes


def is_blank_page(lines):
    txt = " ".join(l["text"] for l in lines)
    if re.search(r"Please do not write on this page|Blank page", txt, re.I) and len(lines) < 12:
        return True
    # IB's closing "Disclaimer / References / Acknowledgements" page is not part of any question, unless a
    # question carries on there ("(Question 9 continued)" above the references).
    if any(CONT.search(l["text"]) for l in lines):
        return False
    return any(re.match(r"^(Disclaimer|References|Acknowledg(e)?ments?)\s*:?\s*$", l["text"].strip(), re.I) for l in lines)


def find_qstarts(pages_lines, left_col):
    """Find question-number lines; enforce sequential numbering."""
    cands = []
    for pi, lines in enumerate(pages_lines):
        for l in lines:
            if l["x0"] > left_col + 14:
                continue
            m = QNUM.match(l["first"]) or QNUM.match(l["text"]) or QNUM_INLINE.match(l["text"])
            if m and (l["bold"] or l["x0"] <= left_col + 4):
                cands.append((pi, l, m.group(1), int(m.group(2))))
    # sequential filter per prefix: accept n == last+1 (or first one being 1 / any if prefix changes)
    accepted, last = [], {}
    for pi, l, pre, n in cands:
        prev = last.get(pre)
        if (prev is None and n <= 3) or (prev is not None and n == prev + 1):
            accepted.append((pi, l, pre, n))
            last[pre] = n
    return accepted


# "Questions 2 and 3 refer to the following electron micrograph…" — shared material printed ABOVE the
# first question number. It belongs to every question in the range, not to the question before it.
STIM = re.compile(r"^(?:Questions?|Use the .{0,80}?questions?|The following .{0,80}?questions?)\s+(\d{1,2})\s*(?:and|to|–|—|-|&)\s*(\d{1,2})\b", re.I)
STIM_INLINE = re.compile(r"\brefers? to questions?\s+(\d{1,2})\s*(?:and|to|–|—|-|&)\s*(\d{1,2})\b", re.I)


def find_stimuli(pages_lines, left_col):
    out = []
    for pi, lines in enumerate(pages_lines):
        for l in lines:
            if l["x0"] > left_col + 40:
                continue
            m = STIM.match(l["text"].strip()) or STIM_INLINE.search(l["text"])
            if m and int(m.group(2)) > int(m.group(1)):
                out.append((pi, l, int(m.group(1)), int(m.group(2))))
    return out


def stimulus_regions(doc, pages_lines, sp, header, qp, qline):
    """Page regions from the stimulus header down to the first question it introduces."""
    regs = []
    for p in range(sp, qp + 1):
        H = doc[p].rect.height
        top = (header["y0"] - 4) if p == sp else 54
        bot = (qline["y0"] - 3) if p == qp else H - 70
        stops = [x["y0"] for x in pages_lines[p] if x["y0"] > top + 10 and x["y0"] < bot and re.search(
            r"This question continues|continues on the following page|Turn over", x["text"], re.I)]
        if stops:
            bot = min(stops) - 3
        if bot - top > 12:
            regs.append(dict(page=p, x0=0.035, x1=0.955, y0=round(max(top, 54) / H, 4), y1=round(bot / H, 4)))
    return regs


def segment(pdf_path: Path):
    doc = pymupdf.open(pdf_path)
    pages_lines = [lines_of(p) for p in doc]
    xs = [l["x0"] for ls in pages_lines[1:] for l in ls if QNUM.match(l["first"]) and l["bold"]]
    left_col = min(xs) if xs else 43
    starts = find_qstarts(pages_lines, left_col)
    stimuli = find_stimuli(pages_lines, left_col)
    questions = []
    for qi, (pi, l, pre, n) in enumerate(starts):
        end_pi, end_y = (starts[qi + 1][0], starts[qi + 1][1]["y0"] - 3) if qi + 1 < len(starts) else (len(doc) - 1, None)
        # A shared stimulus header between this question and the next ends this question early.
        here = (pi, l["y0"])
        nxt = (end_pi, end_y if end_y is not None else 1e9)
        cut = [(sp, h["y0"]) for sp, h, a, b in stimuli if here < (sp, h["y0"]) < nxt]
        if cut:
            end_pi, end_y = min(cut)[0], min(cut)[1] - 3
        regions, text_parts, parts, marks = [], [], [], []
        part_starts, mark_lines = [], []   # maths: where each lettered part and each [n] sits (page, y fraction)
        real_lines = []                    # maths: (page, y) of every line of real text, to place part boundaries
        for p in range(pi, end_pi + 1):
            page = doc[p]
            H, W = page.rect.height, page.rect.width
            lines = pages_lines[p]
            if p != pi and is_blank_page(lines):
                continue
            y_top = (l["y0"] - 6) if p == pi else 52
            y_bot = end_y if (p == end_pi and end_y is not None) else H - 52
            # Biology's "Option A" section stop doesn't apply to maths ("Option A: …" is question text there).
            stops = [x["y0"] for x in lines if x["y0"] > y_top + 10 and re.search(
                r"This question continues|continues on the following page|Turn over|^SECTION\s+[AB]\b|^Section\s+[AB]\b|"
                r"^Disclaimer\b"  # IB's closing disclaimer can share the last question's page
                + ("" if IS_MATHS else r"|^Option\s+[A-H]\b"), x["text"].strip(), re.I)]
            if stops:
                y_bot = min(y_bot, min(stops) - 3)
            content = [x for x in lines if x["y0"] >= y_top - 1 and x["y1"] <= y_bot + 2
                       and not FOOTER_PAT.search(x["text"]) and not CONT.search(x["text"])
                       and x["y0"] > 50 and x["y1"] < H - 40]
            if IS_MATHS:
                content = [x for x in content if not MATHS_NOISE.search(x["text"].strip())]
            if p != pi:
                # continuation pages: start below the "(Question n continued)" header
                hdr = [x for x in lines if CONT.search(x["text"])]
                if hdr:
                    y_top = max(y_top, hdr[0]["y1"] + 4)
                    content = [x for x in content if x["y0"] >= y_top]
            real = [x for x in content if not re.fullmatch(r"[.\s�_]+", x["text"])]
            if not content or (p != pi and not real):
                continue  # nothing, or a page of bare answer lines
            gfx = [g for g in graphics_boxes(page, IS_MATHS) if g[0] >= y_top - 2 and g[1] <= y_bot + 2]
            bottom = max([x["y1"] for x in content] + [g[1] for g in gfx]) + 8
            top = min([x["y0"] for x in content] + [g[0] for g in gfx]) - 6 if p != pi else y_top
            top = max(top, 54, y_top - 2 if p != pi else 0)
            bottom = min(bottom, y_bot, H - 70)
            if bottom - top < 12:
                continue
            regions.append(dict(page=p, x0=0.035, x1=0.955, y0=round(top / H, 4), y1=round(bottom / H, 4)))
            for x in content:
                if PART.match(x["first"]) and x["x0"] < left_col + 70:
                    parts.append(x["first"])
                    lm = LETTER.match(x["first"])
                    # "(i)" is a roman sub-part unless it follows "(h)".
                    if IS_MATHS and lm and (lm.group(1) != "i" or (part_starts and part_starts[-1]["label"] == "(h)")):
                        if x["x0"] < min([ps["x"] for ps in part_starts], default=1e9) + 6:
                            part_starts.append(dict(label=x["first"], page=p, y=round((x["y0"] - 3) / H, 4), x=round(x["x0"], 1)))
                if IS_MATHS:
                    mm = MATHS_MARKS.search(x["text"])
                else:
                    mm = MARKS.match(x["text"].split()[-1]) if x["text"].split() else None
                if mm and x["x1"] > W * 0.8:
                    marks.append(int(mm.group(1)))
                    if IS_MATHS:
                        mark_lines.append(dict(page=p, y=round((x["y1"] + 4) / H, 4), marks=int(mm.group(1))))
                if not re.fullmatch(r"[.\s�_]+", x["text"]):
                    text_parts.append(x["text"])
                    real_lines.append((p, round((x["y0"] - 3) / H, 4)))
        has_lines = any(re.search(r"(\. ){8,}|�{8,}|_{10,}", x["text"]) for p in range(pi, end_pi + 1)
                        for x in pages_lines[p])
        q = dict(number=f"{pre}{n}", regions=regions, parts=parts, marks_found=marks,
                 total_marks=sum(marks) if marks else None, has_answer_lines=has_lines,
                 text="\n".join(text_parts))
        if IS_MATHS:
            q.update(part_starts=part_starts, mark_lines=mark_lines,
                     **part_spans(part_starts, mark_lines, real_lines))
        questions.append(q)
    # Prepend each shared stimulus to every question it covers.
    by_number = {(st[2], st[3]): st for st in starts}
    for sp, header, a, b in stimuli:
        first = next(((qp, ql) for qp, ql, pre, n in starts if n == a and (qp, ql["y0"]) > (sp, header["y0"])), None)
        if not first:
            continue
        regs = stimulus_regions(doc, pages_lines, sp, header, first[0], first[1])
        for q in questions:
            num = re.sub(r"\D", "", q["number"])
            if num and a <= int(num) <= b and not re.match(r"[A-H]", q["number"]):
                q["regions"] = regs + q["regions"]
                q["shared_stimulus"] = header["text"][:120]
    return doc, questions


def part_spans(starts, mark_lines, real_lines):
    """Maths: split a question into its stem and one span per lettered part, as (page, y) positions.

    A part runs from the end of the previous part to the first line of new text after its own last
    [marks] line. So an answer box or a sketch grid printed after "(b) … [4]" stays with (b), while
    linking text such as "Consider the circle with centre B…" (and its diagram) goes with the part it
    introduces. The app crops single parts with these spans for strategy drills."""
    if not starts:
        return dict(stem_end=None, part_spans=[])
    pos = [(s["page"], s["y"]) for s in starts]
    marks = sorted((m["page"], m["y"]) for m in mark_lines)
    bounds = [pos[0]]
    for i in range(1, len(pos)):
        before = [m for m in marks if pos[i - 1] < m <= pos[i]]
        after = [r for r in sorted(real_lines) if before and before[-1] <= r <= pos[i]]
        bounds.append(after[0] if after else pos[i])
    spans = [dict(label=s["label"], start=list(bounds[i]), end=list(bounds[i + 1]) if i + 1 < len(bounds) else None)
             for i, s in enumerate(starts)]
    return dict(stem_end=list(pos[0]), part_spans=spans)


def markscheme_for(pdf: Path):
    cand = pdf.with_name(pdf.stem + "_markscheme.pdf")
    return cand if cand.exists() else None


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / "packets").mkdir(exist_ok=True)
    papers = []
    # When two files map to the same paper id, the official one (with a markscheme) wins over scans and
    # third-party copies that sit in the same folder.
    pdfs = sorted((BANK / SUBJECT).rglob("*.pdf"), key=lambda f: (markscheme_for(f) is None, str(f)))
    for pdf in pdfs:
        rel = pdf.relative_to(BANK / SUBJECT)
        if "markscheme" in pdf.stem.lower():
            continue
        ms = markscheme_for(pdf)
        if not re.search(r"paper_?\s*\d", pdf.stem, re.I):
            print("skip (unrecognised name):", rel); continue
        if IS_MATHS and not ms:
            print("skip (no markscheme):", rel); continue
        pid = paper_id(rel)
        doc, qs = segment(pdf)
        if not any(len(p.get_text()) > 200 for p in doc):
            print("skip (no text layer):", rel); continue
        is_mcq = not IS_MATHS and bool(re.search(r"paper_?\s*_?1A?_", pdf.stem, re.I)) and not re.search(r"1B", pdf.stem)
        rec = dict(id=pid, source=str(rel), markscheme=str(ms.relative_to(BANK / SUBJECT)) if ms else None,
                   session=rel.parent.name, paper=pid.split("-")[-2][1:], tz=pid.split("-")[-1], mcq=is_mcq,
                   pages=len(doc), n_questions=len(qs))
        if pid in {p["id"] for p in papers}:
            print("duplicate id, skipping", rel); continue
        papers.append(rec)
        ms_text = ""
        if ms:
            md = pymupdf.open(ms)
            ms_text = "\n\n".join(f"--- markscheme page {i+1} ---\n" + p.get_text() for i, p in enumerate(md))
        packet = dict(paper=rec, questions=[dict(id=f"{pid}-Q{q['number']}", **{k: v for k, v in q.items()})
                                            for q in qs], markscheme_text=ms_text)
        (WORK / "packets" / f"{pid}.json").write_text(json.dumps(packet, indent=1, ensure_ascii=False))
        print(f"{pid:22s} {len(qs):3d} q  ms={'Y' if ms else '-'}  {rel}")
    (WORK / "papers.json").write_text(json.dumps(papers, indent=1))
    print("papers:", len(papers), "questions:", sum(p["n_questions"] for p in papers))


if __name__ == "__main__":
    main()
