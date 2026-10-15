"""Build the session report PDF.

usage: uv run python build.py <report.json> [phases.csv] [out.pdf]

report.json is the /report endpoint output saved to a file, e.g.
  curl -H "Origin: https://berlogabob.github.io" "https://iade-sync.counter-iade.workers.dev/report?t=<profs token>" > report.json
(the profs token is the 4th segment of the host URL); phases.csv is optional
(observed stage durations from the flight recorder). Typst does the layout, this
script only turns the raw data into the numbers the template shows.
"""
import csv, json, re, subprocess, sys
from collections import defaultdict
from pathlib import Path

here = Path(__file__).parent
src = Path(sys.argv[1] if len(sys.argv) > 1 else here / "sample/report.json")
phases_csv = Path(sys.argv[2]) if len(sys.argv) > 2 else here / "sample/phases.csv"
out = Path(sys.argv[3] if len(sys.argv) > 3 else here / "report.pdf")

r = json.loads(src.read_text())
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
data = {
    "professors": r.get("professors", []), "teams": teams,
    "limits": {"talk": st.get("totalMs", 0) // 1000, "qa": st.get("qaMs", 0) // 1000,
               "setup": st.get("setupMs", 0) // 1000, "pack": st.get("packMs", 0) // 1000},
    "first": first, "last": last, "closed": bool(st.get("closed")),
    "mean": round(sum(t["avg"] for t in ranked) / len(ranked), 1) if ranked else None,
}
(here / "data.json").write_text(json.dumps(data, indent=1))
subprocess.run(["typst", "compile", "--root", str(here), str(here / "report.typ"), str(out)], check=True)
print("wrote", out)
