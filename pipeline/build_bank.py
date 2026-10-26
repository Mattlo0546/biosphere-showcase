"""Merge packets + labels into app/Resources/bank/<slug>/ (questions.json, index.tsv, papers/).
Usage: build_bank.py ["Biology SL" | "Maths AA SL"]

Maths also gets *drill items*: a long (Section B) question is cut into one item per strategy, each showing
the stem, the parts it needs ("hence…") and the part itself, so a strategy drill isn't padded with the
other parts of a 15-mark question. Drill items have `parent` set to the whole question's id."""
import json, re, shutil, sys
from pathlib import Path
import pymupdf
ROOT = Path(__file__).resolve().parent.parent
SUBJECT = sys.argv[1] if len(sys.argv) > 1 else "Biology SL"
SLUG = SUBJECT.lower().replace(" ", "-").replace("&", "and")
MATHS = SLUG == "maths-aa-sl"
BANK = Path("/Users/mattlo/Desktop/University/Hackathon/eexuenhack-2026/IB Past Papers") / SUBJECT
W = ROOT / "pipeline/work" / SLUG
OUT = ROOT / "app/Resources/bank" / SLUG
(OUT / "papers").mkdir(parents=True, exist_ok=True)
if MATHS:
    sys.path.insert(0, str(ROOT / "pipeline"))
    import maths_strategies
    (ROOT / "bank" / SLUG).mkdir(parents=True, exist_ok=True)
    (ROOT / "bank" / SLUG / "syllabus.json").write_text(json.dumps(maths_strategies.build(), indent=1, ensure_ascii=False) + "\n")
shutil.copy(ROOT / "bank" / SLUG / "syllabus.json", OUT / "syllabus.json")

def strs(v):
    if v is None: return []
    v = v if isinstance(v, list) else [v]
    return [str(x) for x in v if x is not None and not (isinstance(x, (int, float)) and not isinstance(x, bool) and False)]

def opt(v):
    return None if v in (None, "", []) else (v if isinstance(v, str) else "; ".join(strs(v)))

def diff(lab):
    for v in (lab.get("difficulty"), lab.get("skills")):
        vals = v if isinstance(v, list) else [v]
        for x in vals:
            if isinstance(x, (int, float)) or (isinstance(x, str) and x.isdigit()):
                return max(1, min(3, int(x)))
    return 2

_docs = {}
def crop_text(paper, regions):
    """Text inside a question's crop regions (to spot IB's 'content removed' placeholders)."""
    d = _docs.setdefault(paper["id"], pymupdf.open(BANK / paper["source"]))
    out = []
    for r in regions:
        pg = d[r["page"]]; H, Wd = pg.rect.height, pg.rect.width
        out.append(pg.get_text(clip=pymupdf.Rect(r["x0"] * Wd, r["y0"] * H, r["x1"] * Wd, r["y1"] * H)))
    return " ".join(out)

REMOVED = re.compile(r"removed for copyright|copyright reasons|content removed|image removed", re.I)

# MARK: maths drill items

MINUTES_PER_MARK = 1.1 if MATHS else 1.25   # IB maths: 90 minutes for 80 marks

def letter(label):
    m = re.match(r"\(([a-h])\)", label or "")
    return f"({m.group(1)})" if m else ""

def clip(regions, start, end):
    """The parts of a question's regions between two (page, y) positions (end None = to the end)."""
    out = []
    for r in regions:
        lo = (r["page"], r["y0"]); hi = (r["page"], r["y1"])
        if hi <= tuple(start) or (end is not None and lo >= tuple(end)):
            continue
        y0 = max(r["y0"], start[1]) if r["page"] == start[0] else r["y0"]
        y1 = min(r["y1"], end[1]) if end is not None and r["page"] == end[0] else r["y1"]
        if y1 - y0 > 0.012:
            out.append(dict(r, y0=round(y0, 4), y1=round(y1, 4)))
    return out

def merge(regions):
    out = []
    for r in regions:
        if out and out[-1]["page"] == r["page"] and abs(out[-1]["y1"] - r["y0"]) < 0.006:
            out[-1] = dict(out[-1], y1=r["y1"])
        else:
            out.append(r)
    return out

def drills(q, seg):
    """One item per run of lettered parts sharing a strategy, plus whatever earlier parts they rely on."""
    spans = {s["label"]: s for s in seg.get("part_spans") or []}
    if q["type"] != "extended" or len(spans) < 2 or not seg.get("stem_end"):
        return []
    letters = [L for L in spans]
    leaves = {L: [p for p in q["parts"] if letter(p["label"]) == L] for L in letters}
    if any(not leaves[L] for L in letters) or sum(len(v) for v in leaves.values()) != len(q["parts"]):
        return []    # labels and the paper's lettering disagree: keep it whole
    def strategy(L):
        by = {}
        for p in leaves[L]:
            by[p["subtopic"]] = by.get(p["subtopic"], 0) + p["marks"]
        return max(by, key=by.get) if by else None
    groups = []           # consecutive letters with the same strategy drill together
    for L in letters:
        if groups and strategy(groups[-1][-1]) == strategy(L):
            groups[-1].append(L)
        else:
            groups.append([L])
    deps = {L: {letter(d) for p in leaves[L] for d in (p.get("depends_on") or []) if letter(d) in spans and letter(d) != L} for L in letters}
    items = []
    for g in groups:
        need, todo = set(g), list(g)
        while todo:
            for d in deps[todo.pop()]:
                if d not in need:
                    need.add(d); todo.append(d)
        use = [L for L in letters if L in need]
        target_marks = sum(p["marks"] for L in g for p in leaves[L])
        if len(use) == len(letters) or target_marks < 2:
            continue      # the drill would be the whole question, or a lone 1-mark "write down"
        regions = clip(seg["regions"], (seg["regions"][0]["page"], 0), seg["stem_end"])
        for L in use:
            regions += clip(seg["regions"], spans[L]["start"], spans[L]["end"])
        parts = [p for L in use for p in leaves[L]]
        marks = sum(p["marks"] for p in parts)
        tag = "".join(L.strip("()") for L in g)
        items.append(dict(q, id=f"{q['id']}-{tag}", parent=q["id"], number=f"{q['number']}({tag})" if len(g) == 1 else f"{q['number']}({g[0].strip('()')}–{g[-1].strip('()')})",
                          title=f"{q['title']}, part{'s' if len(g) > 1 else ''} {' '.join(g)}",
                          primary=strategy(g[0]), subtopics=list(dict.fromkeys([strategy(L) for L in g] + [p["subtopic"] for p in parts])),
                          marks=marks, minutes=round(marks * MINUTES_PER_MARK, 1), parts=parts, regions=merge(regions),
                          focus=[p["label"] for L in g for p in leaves[L]]))
    return items

# MARK: build

# Maths: where each question and part sits in its markscheme PDF (pipeline/segment_markschemes.py), so the
# results screen can show the original markscheme beside her answer.
MS = json.load(open(W / "markscheme_regions.json")) if MATHS and (W / "markscheme_regions.json").exists() else {}

qs, used_papers, used_markschemes, skipped = [], set(), set(), []
for pk in sorted((W / "packets").glob("*.json")):
    pkt = json.load(open(pk)); paper = pkt["paper"]
    paper.update(paper=paper["id"].split("-")[-2][1:], tz=paper["id"].split("-")[-1])   # "AA-2021M-P1-TZ1" → "1", "TZ1"
    if not (W / "labels" / pk.name).exists():
        skipped.append(paper["id"] + " (not labelled)"); continue
    labels = {q["id"]: q for q in json.load(open(W / "labels" / pk.name))["questions"]}
    for seg in pkt["questions"]:
        lab = labels[seg["id"]]
        issue = lab.get("segmentation_issue", "")
        if re.search(r"copyright|removed", issue, re.I) and not re.search(r"heading", issue, re.I):
            skipped.append(seg["id"]); continue
        if not seg["regions"]:
            skipped.append(seg["id"]); continue
        if REMOVED.search(crop_text(paper, seg["regions"])):   # the diagram it needs isn't in the paper
            skipped.append(seg["id"]); continue
        mcq = lab["type"] == "mcq"
        marks = lab["total_marks"]
        part = lambda p: dict(label=str(p.get("label") or ""), marks=int(p.get("marks") or 0), subtopic=opt(p.get("subtopic")),
                              prompt=str(p.get("prompt") or ""), markscheme=strs(p.get("markscheme")),
                              guidance=opt(p.get("guidance")), concept=opt(p.get("concept")))
        ms = MS.get(seg["id"], {})
        mathsPart = lambda p: dict(part(p), cue=opt(p.get("cue")), depends_on=strs(p.get("depends_on")),
                                   **({"ms_regions": ms["parts"][p["label"]]} if p.get("label") in ms.get("parts", {}) else {}))
        q = dict(
            id=seg["id"], paper_id=paper["id"], session=paper["session"], paper=paper["paper"], tz=paper["tz"],
            number=seg["number"], type=lab["type"], in_syllabus=bool(lab["in_syllabus"]),
            primary=lab["primary_subtopic"], subtopics=strs(lab.get("subtopics")) or [lab["primary_subtopic"]],
            title=str(lab.get("title", "")), concepts=strs(lab.get("concepts")), skills=[x for x in strs(lab.get("skills")) if not x.isdigit()],
            difficulty=diff(lab), marks=marks,
            minutes=1.5 if mcq else round(marks * MINUTES_PER_MARK, 1), answer=opt(lab.get("answer")),
            parts=[(mathsPart if MATHS else part)(p) for p in lab["parts"]],
            regions=seg["regions"],
            # Maths crops stop before the printed answer box, so the app always adds working space.
            needs_space=True if MATHS else ((not mcq) and (lab["type"] == "extended" or not seg["has_answer_lines"])),
        )
        if ms.get("regions"):
            q["ms_regions"] = ms["regions"]
        qs.append(q)
        if MATHS:
            qs.extend(drills(q, seg))
        used_papers.add((paper["id"], paper["source"]))
        if ms:
            used_markschemes.add((paper["id"], paper["markscheme"]))

for pid, src in sorted(used_papers):
    dest = OUT / "papers" / f"{pid}.pdf"
    if not dest.exists():
        d = pymupdf.open(BANK / src)
        d.save(dest, garbage=3, deflate=True)
for pid, src in sorted(used_markschemes):
    dest = OUT / "papers" / f"{pid}-markscheme.pdf"
    if not dest.exists():
        pymupdf.open(BANK / src).save(dest, garbage=3, deflate=True)
json.dump(qs, open(OUT / "questions.json", "w"), ensure_ascii=False, separators=(",", ":"))
with open(OUT / "index.tsv", "w") as f:
    f.write("id\tsubtopic\tother_subtopics\ttype\tmarks\tminutes\tdifficulty\tin_syllabus\tyear\ttitle\tconcepts\n")
    for q in qs:
        f.write("\t".join(map(str, [q["id"], q["primary"], ",".join(q["subtopics"][1:]), q["type"], q["marks"], q["minutes"],
                                     q["difficulty"], "yes" if q["in_syllabus"] else "no", q["session"], q["title"],
                                     "; ".join(q["concepts"])])) + "\n")
# The paper PDFs ship as a separate GitHub release ("paper pack"). Its tag changes only when the papers do.
import hashlib
pdfs = sorted((OUT / "papers").glob("*.pdf"))
digest = hashlib.sha1("".join(f"{p.name}:{p.stat().st_size};" for p in pdfs).encode()).hexdigest()[:10]
json.dump({"tag": f"papers-{SLUG}-{digest}", "asset": f"papers-{SLUG}.zip", "count": len(pdfs)},
          open(OUT / "pack.json", "w"), indent=1)
print(len(qs), "questions" + (f" ({sum(1 for q in qs if q.get('parent'))} drill items)" if MATHS else "") + ";",
      len(used_papers), "papers; skipped", len(skipped), skipped[:20], "; pack", digest)
