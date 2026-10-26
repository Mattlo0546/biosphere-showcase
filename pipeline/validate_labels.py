"""Validate label files against packets and the syllabus. Usage: validate_labels.py [PAPER_ID ...]
Paper ids starting with AA- are Maths AA SL (strategy labels); everything else is Biology SL."""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TYPES = {"mcq", "structured", "extended"}


def subject(pid):
    return "maths-aa-sl" if pid.startswith("AA-") else "biology-sl"


def valid_ids(slug):
    syl = json.load(open(ROOT / f"bank/{slug}/syllabus.json"))
    return {s["id"] for t in syl["themes"] for s in t["subtopics"]}


def letter(label):
    m = re.match(r"\(([a-h])\)", label or "")
    return f"({m.group(1)})" if m else ""


def check(pid):
    slug = subject(pid)
    W = ROOT / "pipeline/work" / slug
    VALID = valid_ids(slug)
    maths = slug == "maths-aa-sl"
    errs = []
    pk = json.load(open(W / "packets" / f"{pid}.json"))
    f = W / "labels" / f"{pid}.json"
    if not f.exists():
        return ["missing label file"]
    try:
        lab = json.load(open(f))
    except Exception as e:
        return [f"invalid JSON: {e}"]
    want = [q["id"] for q in pk["questions"]]
    got = [q.get("id") for q in lab.get("questions", [])]
    if want != got:
        errs.append(f"ids differ: missing={sorted(set(want)-set(got))} extra={sorted(set(got)-set(want))}")
    packets = {q["id"]: q for q in pk["questions"]}
    for q in lab.get("questions", []):
        qid = q.get("id")
        if q.get("type") not in (TYPES - {"mcq"} if maths else TYPES):
            errs.append(f"{qid}: bad type {q.get('type')}")
        if q.get("primary_subtopic") not in VALID:
            errs.append(f"{qid}: bad primary_subtopic {q.get('primary_subtopic')}")
        for s in q.get("subtopics", []):
            if s not in VALID:
                errs.append(f"{qid}: bad subtopic {s}")
        parts = q.get("parts") or []
        if not parts:
            errs.append(f"{qid}: no parts")
        if q.get("type") == "mcq":
            if q.get("answer") not in list("ABCD"):
                errs.append(f"{qid}: mcq answer {q.get('answer')!r}")
        tot = sum(p.get("marks", 0) or 0 for p in parts)
        if q.get("total_marks") != tot:
            errs.append(f"{qid}: total_marks {q.get('total_marks')} != sum(parts) {tot}")
        for p in parts:
            if not p.get("markscheme"):
                errs.append(f"{qid} {p.get('label')}: empty markscheme")
            if p.get("subtopic") and p["subtopic"] not in VALID:
                errs.append(f"{qid} {p.get('label')}: bad subtopic {p['subtopic']}")
        if maths and qid in packets:
            seg = packets[qid]
            m = re.search(r"Maximum\s*mark:\s*(\d+)", seg["text"])
            if m and int(m.group(1)) != tot:
                errs.append(f"{qid}: parts add to {tot} but the paper's maximum mark is {m.group(1)}")
            letters = [s["label"] for s in seg.get("part_spans", [])]
            seen = []
            for p in parts:
                if not p.get("subtopic"):
                    errs.append(f"{qid} {p.get('label')}: no strategy")
                if not (p.get("cue") or "").strip():
                    errs.append(f"{qid} {p.get('label')}: no cue")
                L = letter(p.get("label"))
                if letters and L not in letters:
                    errs.append(f"{qid} {p.get('label')}: label not on the paper (found {letters})")
                if not letters and p.get("label"):
                    errs.append(f"{qid} {p.get('label')}: the paper shows no lettered parts; use label \"\"")
                for d in p.get("depends_on") or []:
                    if letter(d) not in seen:      # "(a)" or a leaf like "(a)(i)"; the app drills by letter
                        errs.append(f"{qid} {p.get('label')}: depends_on {d} is not an earlier part")
                if L and L not in seen:
                    seen.append(L)
    return errs


if __name__ == "__main__":
    ids = sys.argv[1:] or [p.stem for p in sorted((ROOT / "pipeline/work/biology-sl/packets").glob("*.json"))]
    bad = 0
    for pid in ids:
        e = check(pid)
        if e:
            bad += 1
            print(f"✗ {pid}"); [print("   ", x) for x in e[:25]]
        elif len(ids) < 10:
            print(f"✓ {pid}")
    print(f"{len(ids)-bad}/{len(ids)} OK")
