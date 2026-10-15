"""Build the session report PDF (the main output) plus a scores CSV.

usage: uv run python build.py [source] [phases.csv] [out.pdf]

source is any of:
  - the host URL (https://berlogabob.github.io/IADE-counter/#/host/...), or a /report/ link
  - the profs token alone (4th segment of the host URL)
  - a report.json file saved from the /report endpoint
With no source it builds from the sample dataset. phases.csv is optional (flight
recorder stage durations); the app's own log already carries them for new sessions.
Default output: report/out/session-<date>.pdf and .csv next to it. When the source is a URL or
token (not a file) the PDF is also uploaded to the session folder in Nextcloud as report.pdf.
"""
import csv, json, re, subprocess, sys, urllib.request
from collections import defaultdict
from datetime import datetime
from pathlib import Path

here = Path(__file__).parent
W = "https://iade-sync.counter-iade.workers.dev"
arg = sys.argv[1] if len(sys.argv) > 1 else str(here / "sample/report.json")
phases_csv = Path(sys.argv[2]) if len(sys.argv) > 2 else here / "sample/phases.csv"
out = Path(sys.argv[3]) if len(sys.argv) > 3 else here / "out" / f"session-{datetime.now():%Y%m%d-%H%M}.pdf"
out.parent.mkdir(parents=True, exist_ok=True)

def load(arg):
    """Returns (data, token); token is None when the data came from a file."""
    if Path(arg).is_file():
        return json.loads(Path(arg).read_text()), None
    m = re.search(r"/host/[A-Za-z0-9]+/[A-Za-z0-9]+/[A-Za-z0-9]+/([A-Za-z0-9]+)", arg) or re.search(r"/report/([A-Za-z0-9]+)", arg)
    token = m.group(1) if m else arg
    if not re.fullmatch(r"[A-Za-z0-9]+", token):
        sys.exit("source must be a file, a host/report URL or a token")
    req = urllib.request.Request(f"{W}/report?t={token}", headers={"Origin": "https://berlogabob.github.io", "User-Agent": "Mozilla/5.0 report-builder"})
    return json.load(urllib.request.urlopen(req, timeout=30)), token

r, token = load(arg)
st, notes = r["state"], r["notes"]
LINE = re.compile(
    r"^(?P<who>.+?)\s+#(?P<n>\d+)\s+talk (?P<talk>\d\d:\d\d)(?: \(\+(?P<over>[\d:]+)\))?"
    r"(?:\s+Q&A (?P<qa>\d\d:\d\d))?"
    r"(?:\s+\[(?P<t1>[\d:]+) talk(?:, (?P<t2>[\d:]+) Q&A)?, (?P<t3>[\d:]+) end\])?"
    r"(?:\s+start (?P<delta>.+))?$")
SUFFIX = re.compile(r"\s*\{([^}]*)\}$")  # {draw 8, setup 5, pack 3; skipped talk, qa}
logs = {}
for line in st.get("log", []):
    sm = SUFFIX.search(line)
    extra = sm.group(1) if sm else ""
    line = SUFFIX.sub("", line)
    m = LINE.match(line)
    if m:
        g = m.groupdict()
        durs, _, skipped = extra.partition(";")
        g["dur"] = {k: int(v) for k, v in re.findall(r"(draw|setup|pack) (\d+)", durs)}
        g["skipped"] = [x.strip() for x in skipped.replace("skipped", "").split(",") if x.strip()]
        logs[m["who"].split(" · ")[0]] = g

obs = defaultdict(lambda: defaultdict(float))  # team -> stage -> seconds
if phases_csv.exists():
    for row in csv.DictReader(phases_csv.open()):
        if row["stage"]:
            obs[row["team"]][row["stage"]] += float(row["seconds"])

order = {gi: k + 1 for k, gi in enumerate(st.get("done", []))}
teams = []
for i, g in enumerate(st["groups"]):
    name = g["name"]
    scores = []
    for n in notes:
        text = n.get(name, "").strip()
        sc = n.get(f"_score:{name}", "")
        if text or sc != "":
            scores.append({"prof": n.get("_professor", "Professor"), "score": int(sc) if sc != "" else None, "note": text})
    vals = [s["score"] for s in scores if s["score"] is not None]
    lg = logs.get(name, {})
    teams.append({
        "name": name, "students": g.get("students", []), "planned": g.get("planned", ""),
        "presented": i in order, "order": order.get(i),
        "talk": lg.get("talk"), "over": lg.get("over"), "qa": lg.get("qa"),
        "t_talk": lg.get("t1"), "t_qa": lg.get("t2"), "t_end": lg.get("t3"), "delta": lg.get("delta"),
        "skipped": lg.get("skipped", []),
        # app-logged seconds win over the flight recorder's polled ones
        "obs": {**{k: round(v, 1) for k, v in obs.get(name, {}).items()}, **lg.get("dur", {})},
        "scores": scores, "avg": round(sum(vals) / len(vals), 1) if vals else None, "n": len(vals),
    })
ranked = sorted((t for t in teams if t["avg"] is not None), key=lambda t: -t["avg"])
for k, t in enumerate(ranked, 1):
    t["rank"] = k
for t in teams:
    t.setdefault("rank", None)
first = next((t["t_talk"] for t in sorted(teams, key=lambda t: t["order"] or 99) if t["t_talk"]), None)
last = next((t["t_end"] for t in sorted(teams, key=lambda t: -(t["order"] or 0)) if t["t_end"]), None)
raters = [n.get("_professor", "Professor") for n in notes]
for t in teams:
    by = {sc["prof"]: sc["score"] for sc in t["scores"]}
    t["row"] = [by.get(x) for x in raters]
data = {
    "raters": raters, "professors": r.get("professors", []), "teams": teams,
    "limits": {"talk": st.get("totalMs", 0) // 1000, "qa": st.get("qaMs", 0) // 1000,
               "setup": st.get("setupMs", 0) // 1000, "pack": st.get("packMs", 0) // 1000},
    "first": first, "last": last, "closed": bool(st.get("closed")),
    "mean": round(sum(t["avg"] for t in ranked) / len(ranked), 1) if ranked else None,
}
(here / "data.json").write_text(json.dumps(data, indent=1))
with out.with_suffix(".csv").open("w", newline="") as f:  # same table as the PDF's score matrix
    w = csv.writer(f)
    w.writerow(["team", "rank", "average", *raters])
    for t in sorted(teams, key=lambda t: t["rank"] or 99):
        w.writerow([t["name"], t["rank"], t["avg"], *["" if v is None else v for v in t["row"]]])
subprocess.run(["typst", "compile", "--root", str(here), str(here / "report.typ"), str(out)], check=True)
print("wrote", out, "and", out.with_suffix(".csv"))
if token:  # keep a copy with the session: Files/sessions/<s-...>/report.pdf
    req = urllib.request.Request(f"{W}/report-pdf?t={token}", data=out.read_bytes(), method="PUT",
                                 headers={"Origin": "https://berlogabob.github.io", "User-Agent": "Mozilla/5.0 report-builder", "Content-Type": "application/pdf"})
    print("uploaded to Nextcloud:", json.load(urllib.request.urlopen(req, timeout=60)).get("path"))
