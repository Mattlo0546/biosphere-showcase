"""Render crops for given question ids to a PDF/PNGs for visual QA.
Usage: preview.py OUT.pdf QID [QID ...]   (subject is taken from the id: AA-… = Maths AA SL, else Biology SL)"""
import json, sys
from pathlib import Path
import pymupdf
ROOT = Path("/Users/mattlo/Desktop/University/Hackathon/eexuenhack-2026/IB Past Papers")
out = pymupdf.open()
for qid in sys.argv[2:]:
    subject, slug = ("Maths AA SL", "maths-aa-sl") if qid.startswith("AA-") else ("Biology SL", "biology-sl")
    pid = qid.rsplit("-Q", 1)[0]
    pk = json.load(open(Path(__file__).parent / f"work/{slug}/packets/{pid}.json"))
    q = next(q for q in pk["questions"] if q["id"] == qid)
    src = pymupdf.open(ROOT / subject / pk["paper"]["source"])
    for r in q["regions"]:
        sp = src[r["page"]]; H = sp.rect.height; Wd = sp.rect.width
        clip = pymupdf.Rect(r["x0"] * Wd, r["y0"] * H, r["x1"] * Wd, r["y1"] * H)
        page = out.new_page(width=clip.width, height=clip.height + 20)
        page.insert_text((10, 14), qid, fontsize=9, color=(0.5, 0, 0.7))
        page.show_pdf_page(pymupdf.Rect(0, 20, clip.width, 20 + clip.height), src, r["page"], clip=clip)
out.save(sys.argv[1])
d = pymupdf.open(sys.argv[1])
for i, p in enumerate(d):
    p.get_pixmap(dpi=60).save(sys.argv[1].replace(".pdf", f"_{i}.png"))
print(len(d), "pages")
