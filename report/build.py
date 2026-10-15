"""Build the session report PDF (the main output) plus a scores CSV.

usage: uv run python build.py [source] [phases.csv] [out.pdf]
       uv run python build.py --all <sessions dir>     # rebuild report.pdf in every s-* folder

--all works on the files themselves (state.json, professors.json, notes*.json), no network:
run it where the Nextcloud data lives, e.g. `--all /nextcloud/sessions`, then `occ files:scan`.

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
if len(sys.argv) > 2 and sys.argv[1] == "--all":
    done = skipped = 0
    for d in sorted(Path(sys.argv[2]).glob("s-*")):
        if not d.is_dir(): continue
        r = subprocess.run([sys.executable, __file__, str(d), "/nonexistent.csv", str(d / "report.pdf")], capture_output=True, text=True)
        ok = r.returncode == 0
        done, skipped = done + ok, skipped + (not ok)
        print(("rebuilt " if ok else "skipped ") + d.name, "" if ok else (r.stderr.strip().splitlines() or ["?"])[-1])
    print(f"{done} rebuilt, {skipped} skipped")
    sys.exit(0)
W = "https://iade-sync.counter-iade.workers.dev"
arg = sys.argv[1] if len(sys.argv) > 1 else str(here / "sample/report.json")
phases_csv = Path(sys.argv[2]) if len(sys.argv) > 2 else here / "sample/phases.csv"
out = Path(sys.argv[3]) if len(sys.argv) > 3 else here / "out" / f"session-{datetime.now():%Y%m%d-%H%M}.pdf"
out.parent.mkdir(parents=True, exist_ok=True)

def load(arg):
    """Returns (data, token); token is None when the data came from a file or folder."""
    if Path(arg).is_dir():  # a session folder as Nextcloud stores it
        def rd(f):
            try: return json.loads(f.read_text())
            except Exception: return {}
        d = Path(arg)
        return {"state": rd(d / "state.json"), "professors": rd(d / "professors.json").get("names", []),
                "notes": [rd(f) for f in sorted(d.glob("notes*.json"))]}, None
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
if not st.get("groups"):
    sys.exit("no teams in this session")
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
    studs = []  # personal grades, graded separately from the team: keys "team/student", "_score:team/student"
    for stu in g.get("students", []):
        sid = f"{name.replace('/', '')}/{stu.replace('/', '')}"
        ss = []
        for n in notes:
            text, sc = n.get(sid, "").strip(), n.get(f"_score:{sid}", "")
            if text or sc != "":
                ss.append({"prof": n.get("_professor", "Professor"), "score": int(sc) if sc != "" else None, "note": text})
        sv = [x["score"] for x in ss if x["score"] is not None]
        studs.append({"name": stu, "scores": ss, "avg": round(sum(sv) / len(sv), 1) if sv else None})
    lg = logs.get(name, {})
    teams.append({
        "name": name, "students": g.get("students", []), "planned": g.get("planned", ""),
        "presented": i in order, "order": order.get(i),
        "talk": lg.get("talk"), "over": lg.get("over"), "qa": lg.get("qa"),
        "t_talk": lg.get("t1"), "t_qa": lg.get("t2"), "t_end": lg.get("t3"), "delta": lg.get("delta"),
        "skipped": lg.get("skipped", []),
        # app-logged seconds win over the flight recorder's polled ones
        "obs": {**{k: round(v, 1) for k, v in obs.get(name, {}).items()}, **lg.get("dur", {})},
        "student_grades": studs, "scores": scores, "avg": round(sum(vals) / len(vals), 1) if vals else None, "n": len(vals),
    })
def sec(v):  # "mm:ss" or "hh:mm:ss" -> seconds, None when absent
    if not v: return None
    n = [int(x) for x in v.split(":")]
    return n[0] * 3600 + n[1] * 60 + n[2] if len(n) == 3 else n[0] * 60 + n[1]
import statistics
for t in teams:
    o = t["obs"]
    t.update(talk_s=sec(t["talk"]), qa_s=sec(t["qa"]), over_s=sec(t["over"]) or 0,
             t0=sec(t["t_talk"]), t1=sec(t["t_qa"]), t2=sec(t["t_end"]),
             draw_s=round(o.get("draw", 0)), setup_s=round(o.get("setup", 0)), pack_s=round(o.get("pack", 0)))
    dm = re.search(r"([+-]\d+)", t["delta"] or "")
    t["delta_min"] = int(dm.group(1)) if dm else (0 if t["delta"] else None)
    v = [x["score"] for x in t["scores"] if x["score"] is not None]
    t["lo"], t["hi"] = (min(v), max(v)) if v else (None, None)
    t["sd"] = round(statistics.pstdev(v), 1) if len(v) > 1 else None
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
    for sg in t["student_grades"]:
        sby = {sc["prof"]: sc["score"] for sc in sg["scores"]}
        sg["row"] = [sby.get(x) for x in raters]
lim_t, lim_q = st.get("totalMs", 0) // 1000, st.get("qaMs", 0) // 1000
pres = [t for t in teams if t["presented"] and t["talk_s"] is not None]
span = (max(t["t2"] for t in pres if t["t2"]) - min(t["t0"] - t["draw_s"] - t["setup_s"] for t in pres if t["t0"])) if any(t["t2"] for t in pres) else None
dels = [t["delta_min"] for t in pres if t["delta_min"] is not None]
full = [t for t in pres if lim_t and t["talk_s"] >= lim_t]
skipt = [t for t in pres if "talk" in t["skipped"]]
sdt = [t for t in ranked if t["sd"] is not None]
insights = []
if pres and lim_t:
    insights.append(f"Presentations used on average {round(100 * sum(t['talk_s'] for t in pres) / len(pres) / lim_t)} % of the {lim_t // 60}:{lim_t % 60:02d} limit; {len(full)} ran to the limit, {len(skipt)} were ended early with Skip.")
if dels:
    avg = sum(dels) / len(dels)
    insights.append(f"Start times averaged {abs(round(avg, 1))} min {'ahead of' if avg < 0 else 'behind'} the plan (range {min(dels):+d} to {max(dels):+d} min).")
if ranked:
    insights.append(f"Highest score: {ranked[0]['name']} ({ranked[0]['avg']}). Lowest: {ranked[-1]['name']} ({ranked[-1]['avg']}).")
if sdt:
    w = max(sdt, key=lambda t: t["hi"] - t["lo"])
    insights.append(f"Widest disagreement between professors: {w['name']} (scores {w['lo']} to {w['hi']}).")
if span and pres:
    insights.append(f"The session took {span // 60}:{span % 60:02d} for {len(pres)} teams, {round(span / len(pres))} s per team including draw, setup and pack.")
def stat(label, vals, limit):
    vals = [v for v in vals if v is not None and v > 0]
    return {"stage": label, "limit": limit or None, "n": len(vals), "avg": round(sum(vals) / len(vals)) if vals else None,
            "min": min(vals) if vals else None, "max": max(vals) if vals else None}
budget = [stat("Draw", [t["draw_s"] for t in pres], None),
          stat("Setup", [t["setup_s"] for t in pres], st.get("setupMs", 0) // 1000),
          stat("Talk", [t["talk_s"] for t in pres], lim_t),
          stat("Q&A", [t["qa_s"] for t in pres], lim_q),
          stat("Pack", [t["pack_s"] for t in pres], st.get("packMs", 0) // 1000)]
data = {
    "budget": budget, "span": span, "insights": insights, "n_skip_talk": len(skipt), "n_full": len(full), "spread": [ranked[0]["avg"], ranked[-1]["avg"]] if ranked else None,
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
