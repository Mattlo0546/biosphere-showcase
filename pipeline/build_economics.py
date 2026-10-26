"""Build the Economics HL question bank from the past-paper folder.

    .venv/bin/python pipeline/build_economics.py

Same shape as the Business bank (see build_business.py), so the app's case-paper engine can use it: the
unit is a *set* = one numbered question with its texts, tables and parts.
  Paper 1  one essay question: (a) [10] + (b) [15]
  Paper 2  one data-response question: texts + tables, (a)–(g), the last a [15] (old syllabus: [20] in total)
  Paper 3  one policy question (HL): data, calculations, diagrams and a [10] policy recommendation
Set ids carry an "ECO-" prefix so they never collide with Business ids in her session history.

Writes app/Resources/bank/economics-hl/sets.json, topics.json and cases/<id>.pdf (the original pages).
"""
import json, re
from pathlib import Path
import pymupdf
from build_business import (clean_lines, norm, page_rows, is_dots, is_blank, has_answer_boxes, extract_markbands,
                            find_prompt, section_between, session_of, NOISE, COMMAND)
from economics_labels import apply_labels, topics_json

SRC = Path("/Users/mattlo/Desktop/University/Hackathon/eexuenhack-2026/IB Past Papers/Economics HL")
OUT = Path(__file__).resolve().parent.parent / "app/Resources/bank/economics-hl"
ECON_NOISE = re.compile(r"^[MN]\d{2}/\d/ECONO|^\d{2}EP\d{2}$|^Candidate session number|Section [AB]$|^Answer (?:one|all|two)", re.I)

# Minutes per mark: each paper's time over the marks she actually answers (P1: 75 min / 25; P2: 105 / 40;
# P3: 105 / 60). The old syllabus asked for two questions per paper in less time.
ROMAN = r"(i|ii|iii|iv|v|vi|vii|viii|ix|x|xi|xii)"

PACE = {(True, "1"): 3.0, (True, "2"): 2.6, (True, "3"): 1.75, (False, "1"): 1.8, (False, "2"): 2.25, (False, "3"): 1.2}


def parse_parts(doc):
    """Every part with marks, in order: dicts with q, label ("a", "b(ii)"), marks, prompt, page, plus q_pages
    (first page of each question) and titles ("1:title" = the text after the question number)."""
    parts, q, letter, cur, q_pages = [], None, "", None, {}

    def start(label, prompt, pi, stem=""):
        return dict(q=q, label=label, prompt=prompt, page=pi, stem=stem)

    for pi in range(len(doc)):
        page = doc[pi]
        h = page.rect.height
        for y0, y1, t, x in page_rows(page):
            if y0 < 58 or y0 > h - 60 or is_dots(t) or NOISE.search(t) or ECON_NOISE.search(t) \
                    or re.search(r"continues on the following page", t):
                continue
            mq = re.match(r"^(\d{1,2})\.\s*(.*)$", t) if x < 62 else None
            if mq:
                q, letter, cur = mq.group(1), "", None
                q_pages.setdefault(q, pi)
                rest = mq.group(2)
                lead = re.match(rf"^\(([a-h])\)\s*(?:\({ROMAN}\)\s*)?(.*)$", rest)
                if lead:                               # "1. (a) Explain …" (Paper 1 puts the first part on the number line)
                    letter = lead.group(1)
                    cur = start(letter + (f"({lead.group(2)})" if lead.group(2) else ""), lead.group(3), pi)
                    parts.append(cur)
                else:
                    q_pages.setdefault(q + ":title", rest)
                continue
            mp = re.match(r"^\(([a-hj-n])\)\s*(.*)$", t)
            mr = re.match(rf"^\({ROMAN}\)\s*(.*)$", t)
            if mr and mr.group(1) == "i" and letter == "h" and x < 90:
                mp, mr = mr, None                      # old Paper 3s run on past (h): there "(i)" is a letter
            elif mr and mr.group(1) in ("v", "x") and letter and ord(letter) + 1 == ord(mr.group(1)) and x < 90:
                mp, mr = mr, None
            if mp and q:
                letter = mp.group(1)
                sub = re.match(rf"^\({ROMAN}\)\s*(.*)$", mp.group(2))
                cur = start(f"{letter}({sub.group(1)})", sub.group(2), pi) if sub else start(letter, mp.group(2), pi)
                parts.append(cur)
            elif mr and q and letter:
                stem = ""
                if cur and cur["label"] == letter and not re.search(r"\[\d+\]", cur["prompt"]):
                    stem = cur["prompt"]               # "(b) Using Table 1:" introduces the sub-parts
                cur = start(f"{letter}({mr.group(1)})", mr.group(2), pi, stem)
                parts.append(cur)
            elif cur is not None and not re.search(r"\[\d+\]", cur["prompt"]):
                cur["prompt"] += " " + t               # question text running over several lines
                if len(cur["prompt"]) > 700:
                    cur = None
    out, seen = [], set()
    for p in parts:
        m = re.search(r"\[(\d+)\s*(?:marks)?\]\s*$", p["prompt"])
        if not m or (p["q"], p["label"]) in seen or re.search(r"removed for copyright", p["prompt"], re.I):
            continue
        seen.add((p["q"], p["label"]))
        p["marks"] = int(m.group(1))
        p["prompt"] = re.sub(r"\s*\[\d+\s*(?:marks)?\]\s*$", "", p["prompt"]).strip()
        out.append(p)
    return out, q_pages


def ms_lines(ms_doc):
    lines = []
    for page in ms_doc:
        lines += [l for l in clean_lines(page.get_text()) if not ECON_NOISE.search(l)]
    return lines


def short(s, n=64):
    s = re.sub(r"\s+", " ", s).strip().rstrip(".")
    return s if len(s) <= n else s[:n].rsplit(" ", 1)[0].rstrip(",;:") + "…"


def title_for(paper, q, ps, doc, first, q_pages):
    """Something she can recognise in a list: the country/market of a data response, or the essay's theme."""
    text = " ".join(doc[i].get_text() for i in range(first, min(first + 2, len(doc))))
    m = re.search(r"Text [A-Z]\s*[—–-]+\s*([^\n]{6,90})", text)
    if m:
        return short(m.group(1))
    title = q_pages.get(q + ":title", "")
    if re.match(r"^(Read|Study)", title, re.I):      # old Paper 2: the extract's headline comes next
        after = re.search(r"questions? that follows?\.?\s*\n((?:\s*\d+\s*\n)?)\s*([^\n]{6,90})", text)
        title = after.group(2) if after and not re.match(r"^\d", after.group(2)) else ""
    if title and not re.match(r"^(Read|Answer|Study)", title, re.I):
        return short(title)
    if paper == "1":
        return ""                                       # filled from the topic after labelling
    m = re.search(r"([A-Z][^.]{20,140}\.)", text)       # Paper 3: the stimulus' opening sentence
    return short(m.group(1)) if m else ""


def content_box(page):
    """Top and bottom of a markscheme page's content, below the "– 4 – 2225 – 5206M" header and above the footer."""
    h = page.rect.height
    blocks = [b for b in page.get_text("blocks") if b[1] > 70 and b[3] < h - 30 and b[4].strip()]
    return (min(b[1] for b in blocks), max(b[3] for b in blocks)) if blocks else (70, h - 40)


def locate_starts(ms, prompts):
    """Where each part's restated question begins in the markscheme PDF: (page, y) in order, or None.
    Searches forward only, so a repeated opener ("Using information from…") lands on the right part."""
    out, cur = [], (0, 0.0)
    for prompt in prompts:
        words = re.sub(r"\s*\[\d+\]\s*$", "", prompt).split()
        found = None
        for n in (8, 5):
            snippet = " ".join(words[:n])
            if len(snippet) < 12:
                continue
            for pi in range(cur[0], len(ms)):
                hits = [r for r in ms[pi].search_for(snippet) if pi > cur[0] or r.y0 > cur[1] + 1]
                if hits:
                    found = (pi, hits[0].y0)
                    break
            if found:
                break
        out.append(found)
        if found:
            cur = found
    return out


def ms_regions(ms, start, end):
    """Crop rectangles (fractions of the page) from one part's start to the next part's start, across pages."""
    if start is None:
        return []
    (p0, y0), (p1, y1) = start, end
    regions = []
    for pi in range(p0, p1 + 1):
        h = ms[pi].rect.height
        # Pages it runs onto start just under the header: diagrams there aren't text, so don't measure text.
        a = max(y0 - 8, 64) if pi == p0 else 64
        b = (y1 - 6) if pi == p1 else h - 40
        # Trim to what's printed in between (text, tables, diagrams), so a part ending mid-page has no white tail.
        page = ms[pi]
        lines = [l for bl in page.get_text("dict")["blocks"] for l in bl.get("lines", [])]
        printed = ([pymupdf.Rect(l["bbox"]) for l in lines if "".join(sp["text"] for sp in l["spans"]).strip()]
                   + [pymupdf.Rect(d["rect"]) for d in page.get_drawings()]
                   + [pymupdf.Rect(im["bbox"]) for im in page.get_image_info()])
        marks = [r.y1 for r in printed if a < r.y1 <= b + 1]
        tops = [r.y0 for r in printed if a - 1 <= r.y0 < b]
        if not marks:
            continue
        a, b = max(a, min(tops) - 8) if tops else a, min(b, max(marks) + 8)
        if b - a > 30:                                 # skip a sliver when the next part starts at the top
            regions.append(dict(page=pi, x0=0.07, x1=0.95, y0=round(a / h, 4), y1=round(min(b, h - 30) / h, 4)))
    return regions


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for folder in ("cases", "markschemes"):
        (OUT / folder).mkdir(exist_ok=True)
        for old in (OUT / folder).glob("*.pdf"):
            old.unlink()
    sets, seen_sets = [], set()
    for folder in sorted(p for p in SRC.iterdir() if p.is_dir()):
        year, s, label = session_of(folder.name)
        current = int(year) >= 2022
        if int(year) < 2016:
            continue
        for pdf in sorted(folder.glob("*.pdf")):
            name = pdf.name
            if "markscheme" in name or "(2)" in name or not name.startswith("Economics_paper"):
                continue
            pm = re.search(r"paper_+(\d)", name)
            if not pm:
                continue
            paper = pm.group(1)
            tzm = re.search(r"TZ(\d)", name)
            tz = f"TZ{tzm.group(1)}" if tzm else "TZ0"
            ms_path = pdf.with_name(pdf.stem + "_markscheme.pdf")
            if not ms_path.exists():
                continue
            doc, ms = pymupdf.open(pdf), pymupdf.open(ms_path)
            boxes = has_answer_boxes(doc)
            parts, q_pages = parse_parts(doc)
            # The official markscheme for each part, as crops of the IB's own pages (shown beside her answer).
            starts = locate_starts(ms, [p["prompt"] for p in parts])
            last_page = ms[len(ms) - 1]
            doc_end = (len(ms) - 1, content_box(last_page)[1] + 10)
            crops, saved_ms = {}, []
            for k, p in enumerate(parts):
                nxt = next((starts[j] for j in range(k + 1, len(parts)) if starts[j]), None)
                crops[(p["q"], p["label"])] = ms_regions(ms, starts[k], nxt or doc_end)
            lines = ms_lines(ms)
            markbands = extract_markbands(lines)
            groups = {}
            for p in parts:
                groups.setdefault(p["q"], []).append(p)
            ms_cursor = 0
            for q, ps in groups.items():
                # Only search this question's own markscheme: every Paper 2 ends with the same "Using information
                # from the text/data…" wording, so a search across the whole scheme can land in another question.
                head = lambda n, after: next((j for j in range(after, len(lines))
                                              if re.match(rf"^{n}\.\s*(?:\(a\).*)?$", lines[j])), None)
                lo = head(q, ms_cursor)
                hi = head(int(q) + 1, lo + 1) if lo is not None else None
                lo, hi = (lo if lo is not None else ms_cursor), (hi if hi is not None else len(lines))
                # Markscheme section for each part: from its prompt to the next part's prompt.
                starts, cursor = [], lo
                for p in ps:
                    i = find_prompt(lines[:hi], p["prompt"], cursor)
                    starts.append(i)
                    if i is not None:
                        cursor = i + 1
                ms_cursor = max(cursor, lo)
                out_parts = []
                for k, p in enumerate(ps):
                    i, scheme = starts[k], ""
                    if i is not None:
                        nxt = next((starts[j] for j in range(k + 1, len(ps)) if starts[j] is not None), hi)
                        scheme = section_between(lines, i, nxt)
                    prompt = (p["stem"] + " " + p["prompt"]).strip() if p.get("stem") else p["prompt"]
                    # "Using an AD/AS diagram, explain …": the command is the verb, not "Using".
                    cm = re.search(r"\b(define|explain|discuss|evaluate|calculate|sketch|draw|recommend|examine|outline|"
                                   r"identify|construct|analyse|compare|distinguish|describe|state|list|determine|plot|"
                                   r"label|show|comment|suggest)\b", p["prompt"], re.I) or COMMAND.match(p["prompt"])
                    out_parts.append(dict(
                        label=p["label"], marks=p["marks"], prompt=prompt, markscheme=scheme, topic="1.1",
                        extended=p["marks"] >= 8, command=(cm.group(1).capitalize() if cm else ""), choice=None,
                        ms_regions=crops.get((q, p["label"]), []),
                    ))
                first = q_pages.get(q, ps[0]["page"])
                later = [v for k2, v in q_pages.items() if ":" not in k2 and int(k2) > int(q)]
                last = (min(later) - 1) if later and paper != "1" else (len(doc) - 1 if paper != "1" else ps[-1]["page"])
                if paper == "1":
                    first = ps[0]["page"]
                pages = [i for i in range(first, max(first, last) + 1) if not is_blank(doc[i])] or [first]
                sid = f"ECO-{year}{s}-P{paper}-{tz}-Q{q}"
                dedupe = (year, s, paper, re.sub(r"\d", "", norm(" ".join(p["prompt"] for p in out_parts)))[:200])
                if dedupe in seen_sets:
                    continue
                seen_sets.add(dedupe)
                case_doc = pymupdf.open()
                for i in pages:
                    case_doc.insert_pdf(doc, from_page=i, to_page=i)
                case_doc.save(OUT / "cases" / f"{sid}.pdf", garbage=4, deflate=True)
                saved_ms.append(out_parts)
                marks = sum(p["marks"] for p in out_parts)
                sets.append(dict(
                    id=sid, session=label, paper=paper, tz=tz, number=q,
                    company=title_for(paper, q, ps, doc, first, q_pages),
                    current_syllabus=current, marks=marks,
                    minutes=max(10, round(marks * PACE[(current, paper)] / 5) * 5),
                    writes_in_paper=boxes, case_pages=case_doc.page_count, topics=[], parts=out_parts,
                    markbands=markbands, has_extended=any(p["extended"] for p in out_parts),
                ))
            # One markscheme file per paper (its questions share it, and the fonts with it): only the pages
            # with a crop, regions renumbered into it. Swift finds it by the set id without "-Qn".
            used = sorted({r["page"] for ps2 in saved_ms for p in ps2 for r in p["ms_regions"]})
            if used:
                ms_doc = pymupdf.open()
                for i in used:
                    ms_doc.insert_pdf(ms, from_page=i, to_page=i)
                ms_doc.subset_fonts()                  # whole embedded fonts would make these ~40 MB
                ms_doc.save(OUT / "markschemes" / f"ECO-{year}{s}-P{paper}-{tz}.pdf", garbage=4, deflate=True)
                for ps2 in saved_ms:
                    for p in ps2:
                        p["ms_regions"] = [dict(r, page=used.index(r["page"])) for r in p["ms_regions"]]
    sets.sort(key=lambda e: (not e["current_syllabus"], e["paper"], -int(e["session"][:4]), e["session"], e["id"]))
    unlabelled = apply_labels(sets)
    topics = topics_json()
    names = {t["id"]: t["name"] for t in topics}
    for s in sets:
        if not s["company"]:
            s["company"] = "Essay · " + names[s["parts"][-1]["topic"]]
    json.dump(topics, open(OUT / "topics.json", "w"), indent=1, ensure_ascii=False)
    json.dump(dict(subject="Economics HL", slug="economics-hl", topics=topics, sets=sets),
              open(OUT / "sets.json", "w"), indent=1, ensure_ascii=False)
    nparts = sum(len(x["parts"]) for x in sets)
    missing = [f'{s["id"]} {p["label"]}' for s in sets for p in s["parts"] if not p["markscheme"].strip()]
    print(f"{len(sets)} sets, {nparts} parts ({len(missing)} without a markscheme section, "
          f"{len(unlabelled)} with no topic match), {sum(x['current_syllabus'] for x in sets)} sets on the "
          f"current syllabus → {OUT}")
    for m in missing[:40]:
        print("  no markscheme:", m)
    for u in unlabelled[:40]:
        print("  no topic:", u)


if __name__ == "__main__":
    main()
