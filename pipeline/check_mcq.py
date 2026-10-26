"""Independently parse MCQ markscheme grids by word position and compare with labels."""
import json, re, sys
from pathlib import Path
import pymupdf
BANK = Path("/Users/mattlo/Desktop/University/Hackathon/eexuenhack-2026/IB Past Papers/Biology SL")
W = Path("pipeline/work/biology-sl")
mism, unparsed, ok = [], [], 0
for pk in sorted((W/"packets").glob("*.json")):
    pkt = json.load(open(pk)); paper = pkt["paper"]
    if not paper["mcq"] or not paper["markscheme"]: continue
    lab = {q["id"]: q for q in json.load(open(W/"labels"/pk.name))["questions"]}
    doc = pymupdf.open(BANK/paper["markscheme"])
    found = {}
    for page in doc:
        words = page.get_text("words")
        for w in words:
            m = re.fullmatch(r"(\d{1,2})\.?", w[4])
            if not m: continue
            n = int(m.group(1)); yc = (w[1]+w[3])/2
            right = [v for v in words if v[0] > w[2] and v[0] - w[2] < 80 and abs((v[1]+v[3])/2 - yc) < 4]
            right.sort(key=lambda v: v[0])
            if right and re.fullmatch(r"[A-D]", right[0][4]) and 1 <= n <= 40 and n not in found:
                found[n] = right[0][4]
    if len(found) < 25:
        unparsed.append((paper["id"], len(found))); continue
    for qid, q in lab.items():
        n = int(re.sub(r"\D", "", qid.rsplit("-Q",1)[1]))
        if n in found:
            if found[n] != q.get("answer"): mism.append((qid, q.get("answer"), found[n]))
            else: ok += 1
print("agree:", ok, "mismatch:", len(mism))
for m in mism: print("  ", m)
print("unparsed papers:", unparsed)
