"""Inventory the past-paper bank: pair papers with markschemes, detect text layers."""
import json, re, sys
from pathlib import Path
import pymupdf

BANK = Path("/Users/mattlo/Desktop/University/Hackathon/eexuenhack-2026/IB Past Papers")
subject = sys.argv[1] if len(sys.argv) > 1 else "Biology SL"
out = []
for pdf in sorted((BANK / subject).rglob("*.pdf")):
    session = pdf.parent.name
    name = pdf.stem
    is_ms = "markscheme" in name.lower()
    m = re.search(r"paper_?\s*(\d[AB]?)", name, re.I) or re.search(r"Paper (\d[AB]?)", name)
    paper = m.group(1).upper() if m else None
    tz = re.search(r"TZ(\d|A|0)", name)
    try:
        doc = pymupdf.open(pdf)
        chars = [len(p.get_text()) for p in doc]
        n = len(doc)
    except Exception as e:
        chars, n = [], 0
    out.append(dict(path=str(pdf.relative_to(BANK)), session=session, paper=paper,
                    tz=tz.group(1) if tz else None, markscheme=is_ms, pages=n,
                    text_pages=sum(c > 200 for c in chars), avg_chars=int(sum(chars)/max(n,1))))
json.dump(out, sys.stdout, indent=1)
