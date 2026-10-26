"""Label Maths AA SL packets with Claude: strategy per part, cue words, dependencies, markscheme points.

Usage: label_maths.py [PAPER_ID ...] [--model sonnet] [--jobs 4] [--force]
Runs your own `claude` CLI headlessly once per paper (spec: LABELING_MATHS.md, catalogue: maths_strategies.py),
validates the result with validate_labels.py and retries once with the errors. Writes
work/maths-aa-sl/labels/<PAPER_ID>.json; papers that already have a valid label file are skipped.
"""
import argparse, json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import maths_strategies
import validate_labels

SUBJECT, SLUG = "Maths AA SL", "maths-aa-sl"
BANK = Path("/Users/mattlo/Desktop/University/Hackathon/eexuenhack-2026/IB Past Papers") / SUBJECT
W = HERE / "work" / SLUG

PART = {"type": "object", "additionalProperties": False,
        "required": ["label", "marks", "subtopic", "cue", "depends_on", "prompt", "markscheme", "guidance", "concept"],
        "properties": {"label": {"type": "string"}, "marks": {"type": "integer"}, "subtopic": {"type": "string"},
                       "cue": {"type": "string"}, "depends_on": {"type": "array", "items": {"type": "string"}},
                       "prompt": {"type": "string"}, "markscheme": {"type": "array", "items": {"type": "string"}},
                       "guidance": {"type": "string"}, "concept": {"type": "string"}}}
QUESTION = {"type": "object", "additionalProperties": False,
            "required": ["id", "type", "in_syllabus", "primary_subtopic", "subtopics", "title", "concepts",
                         "difficulty", "total_marks", "parts"],
            "properties": {"id": {"type": "string"}, "type": {"type": "string", "enum": ["structured", "extended"]},
                           "in_syllabus": {"type": "boolean"}, "primary_subtopic": {"type": "string"},
                           "subtopics": {"type": "array", "items": {"type": "string"}}, "title": {"type": "string"},
                           "concepts": {"type": "array", "items": {"type": "string"}},
                           "difficulty": {"type": "integer", "minimum": 1, "maximum": 3},
                           "total_marks": {"type": "integer"}, "parts": {"type": "array", "items": PART}}}
SCHEMA = {"type": "object", "additionalProperties": False, "required": ["questions"],
          "properties": {"questions": {"type": "array", "items": QUESTION}}}


def prompt_for(pid, errors=None, previous=None):
    pk = json.load(open(W / "packets" / f"{pid}.json"))
    paper = pk["paper"]
    qs = [dict(id=q["id"], number=q["number"],
               maximum_mark=(m.group(1) if (m := re.search(r"Maximum\s*mark:\s*(\d+)", q["text"])) else None),
               lettered_parts_on_paper=[s["label"] for s in q.get("part_spans", [])],
               marks_found=q["marks_found"], text=q["text"]) for q in pk["questions"]]
    out = [
        open(HERE / "LABELING_MATHS.md").read(),
        "# Strategy catalogue (use these ids only)\n" + maths_strategies.catalogue(),
        f"# Paper {pid}: {paper['session']}, Paper {paper['paper']} "
        f"({'no calculator' if paper['paper'] == '1' else 'calculator allowed'}), {paper['tz']}",
        f"Question paper PDF: {BANK / paper['source']}",
        f"Markscheme PDF: {BANK / paper['markscheme']}" if paper.get("markscheme") else "No markscheme PDF.",
        "## Questions (extracted text, may be garbled: check the PDF)\n" + json.dumps(qs, ensure_ascii=False, indent=1),
        "## Markscheme (extracted text)\n" + pk["markscheme_text"][:60000],
        f"Label all {len(qs)} questions in order. Submit the result once with the StructuredOutput tool.",
    ]
    if errors:
        out.append("## Your previous attempt failed validation. Fix exactly these problems and resubmit everything:\n"
                   + "\n".join(errors) + "\n\nPrevious attempt:\n" + json.dumps(previous, ensure_ascii=False))
    return "\n\n".join(out)


def run_claude(prompt, model):
    env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE", "ANTHROPIC_"))}
    args = ["claude", "-p", "--output-format", "json", "--json-schema", json.dumps(SCHEMA),
            "--allowedTools", "Read", "--add-dir", str(BANK), "--strict-mcp-config",
            "--no-session-persistence", "--model", model]
    r = subprocess.run(args, input=prompt, capture_output=True, text=True, env=env, cwd=HERE, timeout=3600)
    try:
        obj = json.loads(r.stdout)
    except json.JSONDecodeError:
        raise RuntimeError(f"claude exited {r.returncode}: {r.stderr[-500:] or r.stdout[-500:]}")
    if obj.get("is_error") or not obj.get("structured_output"):
        raise RuntimeError(str(obj.get("result"))[:500])
    return obj["structured_output"], obj.get("total_cost_usd")


def label(pid, model, force):
    dest = W / "labels" / f"{pid}.json"
    if dest.exists() and not force and not validate_labels.check(pid):
        return pid, "skip", 0
    errors, previous, cost = None, None, 0.0
    for attempt in range(2):
        try:
            out, c = run_claude(prompt_for(pid, errors, previous), model)
        except Exception as e:
            return pid, f"error: {e}", cost
        cost += c or 0
        dest.write_text(json.dumps(dict(paper_id=pid, **out), indent=1, ensure_ascii=False))
        first = errors
        errors = validate_labels.check(pid)
        if not errors:
            return pid, "ok" if attempt == 0 else f"ok (retry after: {first[0] if first else ''})", cost
        previous = out
    return pid, f"invalid: {len(errors)} problems, e.g. {errors[0]}", cost


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("papers", nargs="*")
    ap.add_argument("--model", default="sonnet")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    (W / "labels").mkdir(parents=True, exist_ok=True)
    ids = a.papers or [p.stem for p in sorted((W / "packets").glob("*.json"), reverse=True)]   # newest first
    total = 0.0
    with ThreadPoolExecutor(a.jobs) as pool:
        for pid, status, cost in pool.map(lambda p: label(p, a.model, a.force), ids):
            total += cost or 0
            print(f"{pid:22s} {status}  ${cost or 0:.2f}", flush=True)
    print(f"done; ${total:.2f} in total")


if __name__ == "__main__":
    main()
