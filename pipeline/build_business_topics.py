"""Build the Business syllabus/reading index from the student's unchanged notes PDF.
Run from the repo with Python + PyMuPDF; optionally pass a replacement notes PDF.
RevisionDojo chapter URLs were verified from its topic index on 10 October 2026.
"""
import json, re, shutil, sys
from pathlib import Path
import pymupdf

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "app/Resources/bank/business-hl"
SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else OUT / "notes.pdf"
UNITS = [
    ("1", "Introduction to business management", [
        ("What is a business?", 1), ("Types of business entities", 3),
        ("Business objectives", 6), ("Stakeholders", 7),
        ("Growth and evolution", 8), ("Multinational companies", 11)]),
    ("2", "Human resource management", [
        ("Introduction to HR management", 13), ("Organizational structure", 17),
        ("Leadership and management", 20), ("Motivation and demotivation", 23),
        ("Organizational culture", 31), ("Communication", 33),
        ("Industrial / employee relations", 35)]),
    ("3", "Finance and accounts", [
        ("Introduction to finance", 38), ("Sources of finance", 39),
        ("Costs and revenues", 42), ("Final accounts", 42),
        ("Profitability and liquidity ratios", 47), ("Efficiency ratios", 49),
        ("Cash flow", 52), ("Investment appraisal", 53), ("Budgets", 56)]),
    ("4", "Marketing", [
        ("Introduction to marketing", 58), ("Marketing planning", 60),
        ("Sales forecasting", 63), ("Market research", 64),
        ("The seven Ps of the marketing mix", 68), ("International marketing", 82)]),
    ("5", "Operations management", [
        ("Introduction to operations management", 83), ("Operations methods", 84),
        ("Lean production and quality management", 86), ("Location", 88),
        ("Break-even analysis", 90), ("Production planning", 92),
        ("Crisis management and contingency planning", 95),
        ("Research and development", 96), ("Management information systems", None)]),
]
HL = {"2.5", "2.7", "3.6", "3.9", "4.3", "4.6", "5.3", "5.6", "5.7", "5.8", "5.9"}
TOOLS = [
    ("swot", "SWOT analysis"), ("ansoff", "Ansoff matrix"), ("steeple", "STEEPLE analysis"),
    ("bcg", "BCG matrix"), ("business-plan", "Business plan"),
    ("decision-trees", "Decision trees"), ("statistics", "Descriptive statistics"),
    ("circular", "Circular business models"), ("force-field", "Force field analysis"),
    ("gantt", "Gantt chart"), ("hofstede", "Hofstede's cultural dimensions"),
    ("porter", "Porter's generic strategies"), ("contribution", "Contribution"),
    ("critical-path", "Critical path analysis"), ("regression", "Simple linear regression"),
]
DOJO = {
  "109": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-11-what-is-a-business/notes",
  "110": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-12-types-of-business-entities/notes",
  "111": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-13-business-objectives/notes",
  "112": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-14-stakeholders/notes",
  "113": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-15-growth-and-evolution/notes",
  "114": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-16-multinational-companies/notes",
  "115": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-21-introduction-to-hr-management/notes",
  "116": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-22-organizational-structure/notes",
  "117": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-23-leadership-and-management/notes",
  "118": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-24-motivation-and-demotivation/notes",
  "119": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-25-organizational-corporate-culture-hl-only/notes",
  "120": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-26-communication/notes",
  "121": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-27-industrialemployee-relations-hl-only/notes",
  "122": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-31-introduction-to-finance/notes",
  "123": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-32-sources-of-finance/notes",
  "124": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-33-costs-and-revenues/notes",
  "125": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-34-final-accounts/notes",
  "126": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-35-profitability-and-liquidity-ratio-analysis/notes",
  "127": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-36-efficiency-ratio-analysis-hl-only/notes",
  "128": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-37-cash-flow/notes",
  "129": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-38-investment-appraisal/notes",
  "130": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-39-budgets-hl-only/notes",
  "131": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-41-introduction-to-marketing/notes",
  "132": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-42-marketing-planning/notes",
  "133": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-43-sales-forecasting-hl-only/notes",
  "134": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-44-market-research/notes",
  "135": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-45-the-seven-ps-of-the-marketing-mix/notes",
  "136": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-46-international-marketing-hl-only/notes",
  "137": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-51-introduction-to-operations-management/notes",
  "138": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-52-operations-methods/notes",
  "139": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-53-lean-production-and-quality-management-hl-only/notes",
  "140": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-54-location/notes",
  "141": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-55-break-even-analysis/notes",
  "142": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-56-production-planning-hl-only/notes",
  "143": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-57-crisis-management-and-contingency-planning-hl-only/notes",
  "144": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-58-research-and-development-hl-only/notes",
  "145": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-59-management-information-systems-hl-only/notes",
  "146": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-swot-analysis/notes",
  "147": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-ansoff-matrix/notes",
  "148": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-steeple-analysis/notes",
  "149": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-boston-consulting-group-bcg-matrix/notes",
  "150": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-business-plan/notes",
  "151": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-decision-trees/notes",
  "152": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-descriptive-statistics/notes",
  "153": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-circular-business-models/notes",
  "154": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-force-field-analysis-hl-only/notes",
  "155": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-gantt-chart-hl-only/notes",
  "156": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-hofstedes-cultural-dimensions-hl-only/notes",
  "157": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-porters-generic-strategies-hl-only/notes",
  "158": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-contribution-hl-only/notes",
  "159": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-critical-path-analysis-hl-only/notes",
  "160": "https://www.revisiondojo.com/ib/ib-business-management/ib-business-management-simple-linear-regression-hl-only/notes"
}

def rows(page):
    return [(stripped, line["bbox"][1] / page.rect.height)
            for block in page.get_text("dict")["blocks"]
            for line in block.get("lines", [])
            if (stripped := "".join(span["text"] for span in line["spans"]).strip())]

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if not SOURCE.exists():
        raise SystemExit("Supply the student's notes PDF to build the reading index.")
    doc = pymupdf.open(SOURCE)
    pages = [rows(page) for page in doc]
    toc = doc.get_toc()
    topics = []
    link_id = 109
    for unit, name, entries in UNITS:
        for n, (title, page) in enumerate(entries, 1):
            id = f"{unit}.{n}"
            heading = next((t.strip() for _, t, p in toc if page == p and re.match(rf"^{re.escape(id)}[. ]", t.strip())), "")
            y = next((y for text, y in pages[page-1] if text == heading), 0.06) if page else None
            topics.append(dict(id=id, name=title, blurb=title, unit=unit, unit_name=name,
                               hl_only=id in HL, notes_page=page, notes_y=y,
                               notes_heading=heading or None, revision_dojo_url=DOJO[str(link_id)]))
            link_id += 1
    # Only link tools with a real explanatory section in these notes. A passing mention
    # or a prompt in the 2026 mock pack is not a reading section.
    tool_sections = {
        "swot": ("SWOT", 1, 97), "ansoff": ("Ansoff", 1, 97),
        "bcg": ("Boston Consulting Group (BCG) Matrix", 106, 106),
        "decision-trees": ("Decision Tree", 108, 108),
        "statistics": ("Descriptive Statistics", 110, 110),
        "circular": ("Circular Business Models", 110, 110),
        "contribution": ("Contribution", 90, 91),
    }
    for n, (key, title) in enumerate(TOOLS):
        found = None
        if key in tool_sections:
            needle, start, stop = tool_sections[key]
            for i in range(start-1, min(stop, len(doc))):
                for text, y in pages[i]:
                    if needle.lower() in text.lower() and len(text) < 90:
                        found = (i+1, y, text)
                        break
                if found:
                    break
        topics.append(dict(id="toolkit."+key, name=title, blurb=title,
                           unit="toolkit", unit_name="Business management toolkit",
                           hl_only=n >= 8, notes_page=found[0] if found else None,
                           notes_y=found[1] if found else None,
                           notes_heading=found[2] if found else None,
                           revision_dojo_url=DOJO[str(146+n)]))
    (OUT / "topics.json").write_text(json.dumps(topics, ensure_ascii=False, indent=2)+"\n")
    if SOURCE.resolve() != (OUT / "notes.pdf").resolve():
        shutil.copyfile(SOURCE, OUT / "notes.pdf")
    print(f"{len(topics)} topics; {sum(t['notes_page'] is not None for t in topics)} personal reading sections; {len(doc)} unchanged notes pages")

if __name__ == "__main__":
    main()
