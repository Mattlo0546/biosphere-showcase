"""Build the Business Management HL question bank from the past-paper folder.

    .venv/bin/python pipeline/build_business.py

A business question only makes sense with its case, so the unit here is a *set*: one Paper 2 question
(its stimulus plus parts (a), (b), … including the 10-marker), or a whole Paper 1 / Paper 3 (case plus
all its questions). Each part carries its marks, a topic and its own markscheme section.

Writes app/Resources/bank/business-hl/sets.json and cases/<id>.pdf (the original pages for that set).
"""
import json, re, sys
from pathlib import Path
import pymupdf
from business_labels import apply_labels

SRC = Path("/Users/mattlo/Desktop/University/Hackathon/eexuenhack-2026/IB Past Papers/Business Management HL")
OUT = Path(__file__).resolve().parent.parent / "app/Resources/bank/business-hl"

NOISE = re.compile(r"International Baccalaureate|Baccalauréat|Bachillerato|reproduc|licen[cs]|ibo\.org|prohib|interdit|"
                   r"prohíbe|infraction|delito|private teachers|fournisseurs|plataformas|enunciativo|systèmes|almacenamiento|"
                   r"écrite|escrito|parties, including|^\d{2}EP\d{2}$|^–\s?\d+\s?–|^\d{4} – \d{4}|Turn over|"
                   r"This question continues|Question \d+ continued|^\(Question|Please do not write on this page|"
                   r"Answers written on this page|will not be marked|^Candidate session number|^\d+ pages$|^[MN]\d{2}/\d/BUSMT")

def clean_lines(text):
    out = []
    for line in text.splitlines():
        s = re.sub(r"\s+", " ", line).strip()
        if not s or re.fullmatch(r"[\.…�\-_ ]{4,}", s):
            continue
        s = re.sub(r"[.…�]{6,}", "", s).replace("\x08", "").replace("\x07", "").strip()
        if not s or NOISE.search(s):
            continue
        # PyMuPDF puts question numbers, part letters, bullets and marks on their own lines: glue them back.
        if out and re.fullmatch(r"\[\d+\s*(?:marks)?\]", s):
            out[-1] += " " + s
        elif out and re.fullmatch(r"(\d{1,2}\.|\([a-z]+\)|y|•)", out[-1]):
            out[-1] = ("•" if out[-1] in ("y", "•") else out[-1]) + " " + s
        else:
            out.append(s)
    return out


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def page_rows(page):
    """Text rows top to bottom: [y0, y1, text, x], spans on the same baseline merged."""
    raw = []
    for b in page.get_text("dict")["blocks"]:
        for l in b.get("lines", []):
            t = "".join(s["text"] for s in l["spans"]).replace("\x08", "").replace("\x07", "").strip()
            if t:
                raw.append([l["bbox"][1], l["bbox"][3], l["bbox"][0], t])
    raw.sort(key=lambda r: r[0])
    groups = []
    for r in raw:
        if groups and abs(groups[-1][0][0] - r[0]) < 4:
            groups[-1].append(r)
        else:
            groups.append([r])
    rows = []
    for g in groups:
        g.sort(key=lambda r: r[2])            # left to right, so "(c)" comes before its text
        rows.append([min(r[0] for r in g), max(r[1] for r in g), " ".join(r[3] for r in g), g[0][2]])
    for r in rows:
        r[2] = re.sub(r"^\(Question \d+ continued\)\s*", "", r[2])
    return [r for r in rows if r[2]]


def is_dots(t):
    s = t.replace(" ", "")
    return len(s) > 10 and sum(c in "�.…" for c in s) / len(s) > 0.8


def first_content_page(doc):
    """The page after the cover (the PDFs start with a licence page, then the cover)."""
    for i in range(min(4, len(doc))):
        if re.search(r"nstructions to candidates", doc[i].get_text(), re.I):
            return i + 1
    return 1


def is_blank(page):
    """Blank pages, and the closing page of image credits and the IB disclaimer."""
    t = page.get_text()
    lines = clean_lines(t)
    credits = re.search(r"^\s*(References|Disclaimer):?\s*$", t, re.M) and not any(re.search(r"\[\d+\]", l) for l in lines)
    return len(t.strip()) < 60 or "Please do not write on this page" in t or bool(credits)


def has_answer_boxes(doc):
    return any("within the answer boxes" in doc[i].get_text() for i in range(min(3, len(doc))))


COMMAND = re.compile(r"^(State|Define|Describe|Explain|Discuss|Recommend|Evaluate|Examine|Analyse|Outline|Calculate|Comment|"
                     r"Construct|Using|With reference|Referring|Identify|Distinguish|Prepare|Complete|To what extent|Apply|"
                     r"Contrast|Compare|Justify|Suggest|Draw|Label|Plot|Determine|Interpret|List|Sketch)", re.I)


def parse_parts(doc, numbered_questions):
    """Every question part with marks, in order: dicts with q, label, marks, prompt, page.

    numbered_questions: P1/P3 style, where "3. Describe …" is itself a question. In P2, "3. Roscas" is the
    case title and the parts are (a), (b)(i), …"""
    parts, q, letter, stem, cur, q_pages = [], None, "", "", None, {}
    for pi in range(len(doc)):
        page = doc[pi]
        h = page.rect.height
        for y0, y1, t, x in page_rows(page):
            if y0 < 58 or y0 > h - 70 or is_dots(t) or NOISE.search(t) or re.search(r"continues on the following page", t):
                continue
            mq = re.match(r"^(\d{1,2})\.\s*(.*)$", t) if x < 62 else None
            if mq:
                q = mq.group(1); q_pages.setdefault(q, pi)
                letter, stem = "", ""
                rest = mq.group(2)
                lead = re.match(r"^\(([a-h])\)\s*(.*)$", rest)
                if numbered_questions and lead:       # "3. (a) Describe …"
                    letter = lead.group(1)
                    cur = dict(q=q, label=f"{q}({letter})", prompt=lead.group(2), page=pi)
                elif numbered_questions:              # in P1/P3 every numbered line at the margin is a question
                    cur = dict(q=q, label=q, prompt=rest, page=pi)
                else:
                    cur = None
                    if not numbered_questions:
                        q_pages[q + ":title"] = rest
                    continue
            else:
                mp = re.match(r"^\(([a-h])\)\s*(.*)$", t)
                mr = re.match(r"^\((i|ii|iii|iv|v|vi)\)\s*(.*)$", t)
                if mp and q:
                    letter = mp.group(1); stem = ""
                    base = f"{q}({letter})" if numbered_questions else letter
                    sub = re.match(r"^\((i|ii|iii|iv)\)\s*(.*)$", mp.group(2))
                    if sub:                           # "(b) (i) calculate …" on one line
                        cur = dict(q=q, label=f"{base}({sub.group(1)})", prompt=sub.group(2), page=pi)
                    else:
                        cur = dict(q=q, label=base, prompt=mp.group(2), page=pi)
                elif mr and q and letter:
                    base = f"{q}({letter})" if numbered_questions else letter
                    if cur and not re.search(r"\[\d+\]", cur["prompt"]) and cur["label"] == base:
                        stem = cur["prompt"]          # "(b) Using Table 1:" introduces the sub-parts
                    cur = dict(q=q, label=f"{base}({mr.group(1)})", prompt=mr.group(2), page=pi, stem=stem)
                elif cur is not None and not re.search(r"\[\d+\]", cur["prompt"]):
                    cur["prompt"] += " " + t          # question text running over several lines
                    if not COMMAND.match(cur["prompt"]) and len(cur["prompt"]) > 600:
                        cur = None
                    continue
                else:
                    continue
            if cur is not None:
                parts.append(cur)
        # close: parts are finished when their [marks] is seen; done below
    out = []
    for p in parts:
        m = re.search(r"\[(\d+)\s*(?:marks)?\]\s*$", p["prompt"])
        if not m:
            continue
        p["marks"] = int(m.group(1))
        p["prompt"] = re.sub(r"\s*\[\d+\s*(?:marks)?\]\s*$", "", p["prompt"]).strip()
        out.append(p)
    # A part can be appended twice if its first row also started a new object; keep the last complete one per label.
    seen, uniq = set(), []
    for p in out:
        key = (p["q"], p["label"])
        if key in seen:
            continue
        seen.add(key); uniq.append(p)
    return uniq, q_pages


def ms_lines(ms_doc):
    lines = []
    for page in ms_doc:
        lines += clean_lines(page.get_text())
    return lines


def extract_markbands(lines):
    """Return the source MS's general markband table before the paper questions."""
    start = next((i for i, line in enumerate(lines)
                  if re.search(r"markbands and assessment criteria|marks\s+level descriptor", line, re.I)), None)
    if start is None:
        return ""
    end = next((i for i in range(start + 1, len(lines))
                if re.match(r"^(?:Section [ABC]|\d{1,2}\.\s*$)", lines[i], re.I)), len(lines))
    return "\n".join(lines[start:end]).strip()


LEAD = re.compile(r"^((\d{1,2}\.|\([a-z]+\))\s*)+")


def find_prompt(lines, prompt, start_at=0):
    target = norm(prompt)
    if len(target) < 12:
        return None

    def opens(line):
        n = norm(re.sub(r"\s*\[\d+\s*(?:marks)?\]\s*$", "", LEAD.sub("", line)))
        return len(n) >= 12 and target.startswith(n[:60])

    for i in range(start_at, len(lines)):
        if opens(lines[i]):
            return i
    for i in range(start_at, len(lines)):
        if target[:28] in norm(lines[i] + " " + (lines[i + 1] if i + 1 < len(lines) else "")):
            return i

    return None


def section_between(lines, start, stop):
    end = next((j for j in range(start, min(start + 6, len(lines))) if re.search(r"\[\d+\s*(?:marks)?\]\s*$", lines[j])), start)
    return "\n".join(lines[end + 1:stop]).strip()


def session_of(folder):
    year, sess = folder.split()
    return year, ("M" if sess.startswith("May") else "N"), f"{year} {'May' if sess.startswith('May') else 'Nov'}"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "cases").mkdir(exist_ok=True)
    for old in list((OUT / "cases").glob("*.pdf")) + [OUT / "essays.json"]:
        if old.exists():
            old.unlink()
    sets, missing, seen_sets = [], 0, set()
    for folder in sorted(p for p in SRC.iterdir() if p.is_dir()):
        year, s, label = session_of(folder.name)
        current = int(year) >= 2024
        if int(year) < 2016:
            continue
        for pdf in sorted(folder.glob("*.pdf")):
            name = pdf.name
            if "markscheme" in name or "case_study" in name or "pre-released" in name or "(2)" in name or name.startswith(("N24", "BM ")):
                continue
            pm = re.search(r"paper_+(\d)", name)
            if not pm:
                continue
            paper = pm.group(1)
            if not current and paper != "2":
                continue                      # older Paper 1s used a different format (pre-issued case, 20-markers)
            tzm = re.search(r"TZ(\d)", name)
            tz = f"TZ{tzm.group(1)}" if tzm else "TZ0"
            ms_path = pdf.with_name(pdf.stem + "_markscheme.pdf")
            if not ms_path.exists():
                continue
            doc, ms = pymupdf.open(pdf), pymupdf.open(ms_path)
            boxes = has_answer_boxes(doc)
            parts, q_pages = parse_parts(doc, numbered_questions=paper in ("1", "3"))
            lines = ms_lines(ms)
            markbands = extract_markbands(lines)
            if paper == "2":
                groups = {}
                for p in parts:
                    groups.setdefault(p["q"], []).append(p)
                units = [(q, ps) for q, ps in groups.items() if not any(p["marks"] >= 20 for p in ps)]
            else:
                units = [("", parts)]
            for q, ps in units:
                if not ps:
                    continue
                # Markscheme section for each part: from its prompt to the next part's prompt.
                starts = []
                cursor = 0
                for p in ps:
                    i = find_prompt(lines, p["prompt"], cursor)
                    starts.append(i)
                    if i is not None:
                        cursor = i + 1
                out_parts = []
                for k, p in enumerate(ps):
                    i = starts[k]
                    if i is None:
                        missing += 1
                        scheme = ""
                    else:
                        nxt = next((starts[j] for j in range(k + 1, len(ps)) if starts[j] is not None), None)
                        if nxt is None:
                            stop_rx = re.compile(rf"^({int(p['q']) + 1}\.\s|Section [ABC]\b)")
                            nxt = next((j for j in range(i + 1, len(lines)) if stop_rx.match(lines[j])), len(lines))
                        scheme = section_between(lines, i, nxt)
                    prompt = (p.get("stem", "") + " " + p["prompt"]).strip() if p.get("stem") else p["prompt"]
                    cm = COMMAND.match(p["prompt"])
                    out_parts.append(dict(
                        label=p["label"], marks=p["marks"], prompt=prompt, markscheme=scheme,
                        topic="1.1",
                        extended=p["marks"] >= 10, command=(cm.group(1).capitalize() if cm else ""),
                        choice="B" if paper == "1" and p["marks"] >= 10 else None,
                    ))
                # Pages: P2 from the question's first page to the page before the next question; P1/P3 the whole paper.
                if paper == "2":
                    first = q_pages.get(q, ps[0]["page"])
                    later = [v for k2, v in q_pages.items() if ":" not in k2 and int(k2) > int(q)]
                    last = (min(later) - 1) if later else len(doc) - 1
                    company = q_pages.get(q + ":title", "")
                    if not company or re.search(r"\b(19|20)\d\d\b|n\.d\.", company):
                        # The title row picked up a photo credit: use the case's first "Name (ABC)" instead.
                        text = " ".join(doc[i].get_text() for i in range(first, min(first + 2, len(doc))))
                        m = re.search(r"([A-Z][\w’'&.\-]*(?: [A-Z][\w’'&.\-]*){0,4}) \(([A-Z][A-Za-z0-9]{0,5})\)", text)
                        company = f"{m.group(1)} ({m.group(2)})" if m else company
                else:
                    first, last = first_content_page(doc), len(doc) - 1
                    company = next((r[2] for r in page_rows(doc[first]) if r[0] > 58 and len(r[2]) > 3
                                    and not re.match(r"^(Business|Higher|Paper|Read|\d)", r[2])), "")
                pages = [i for i in range(first, last + 1) if not is_blank(doc[i])]
                sid = f"{year}{s}-P{paper}-{tz}" + (f"-Q{q}" if q else "")
                dedupe = (year, s, paper, q, re.sub(r"\d", "", norm(" ".join(p["prompt"] for p in out_parts)))[:200])
                if dedupe in seen_sets:
                    continue
                seen_sets.add(dedupe)
                case_doc = pymupdf.open()
                for i in pages:
                    case_doc.insert_pdf(doc, from_page=i, to_page=i)
                case_doc.save(OUT / "cases" / f"{sid}.pdf", garbage=4, deflate=True)
                counted = [p for p in out_parts if p["choice"] is None] + [p for p in out_parts if p["choice"]][:1]
                marks = sum(p["marks"] for p in counted)
                minutes = {"1": 90, "3": 75}.get(paper, max(10, round(marks * 2.1 / 5) * 5))
                topics = []
                for p in out_parts:
                    if p["topic"] not in topics:
                        topics.append(p["topic"])
                sets.append(dict(
                    id=sid, session=label, paper=paper, tz=tz, number=q, company=re.sub(r"\s*\(continued\)", "", company)[:60],
                    current_syllabus=current, marks=marks, minutes=minutes, writes_in_paper=boxes,
                    case_pages=case_doc.page_count, topics=topics, parts=out_parts, markbands=markbands,
                    has_extended=any(p["extended"] for p in out_parts),
                ))
    sets.sort(key=lambda e: (not e["current_syllabus"], e["paper"], -int(e["session"][:4]), e["session"], e["id"]))
    apply_labels(sets)
    topic_path = OUT / "topics.json"
    if not topic_path.exists():
        raise SystemExit(f"Missing topic index {topic_path}; build_business_topics.py must run first")
    topics = json.loads(topic_path.read_text())
    valid_ids = {t["id"] for t in topics}
    invalid = [(s["id"], p["label"], p["topic"]) for s in sets for p in s["parts"] if p["topic"] not in valid_ids]
    invalid += [(s["id"], p["label"], topic) for s in sets for p in s["parts"] for topic in p["topics"] if topic not in valid_ids]
    if invalid:
        raise SystemExit(f"Invalid topic ids: {invalid[:10]}")
    json.dump(dict(subject="Business Management HL", slug="business-hl",
                   topics=topics, sets=sets),
              open(OUT / "sets.json", "w"), indent=1, ensure_ascii=False)
    nparts = sum(len(x["parts"]) for x in sets)
    missing_after_repairs = sum(not p.get("markscheme", "").strip() for s in sets for p in s["parts"])
    print(f"{len(sets)} sets, {nparts} parts ({missing_after_repairs} without a markscheme section), "
          f"{sum(x['current_syllabus'] for x in sets)} sets on the current syllabus → {OUT}")


if __name__ == "__main__":
    main()
