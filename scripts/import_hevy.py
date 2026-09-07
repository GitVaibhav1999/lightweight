#!/usr/bin/env python3
"""Hevy CSV export -> OVERLOAD sessions (spike for PRD §7a).

usage: import_hevy.py [path/to/workout_data.csv]
- groups set rows into sessions keyed by (title, start_time)
- maps exercise_title -> library exercise via data/hevy_aliases.json
  (creates a DRAFT alias file with scored candidates if missing; review the low-confidence ones)
- writes .cache/hevy/sessions.json and prints a report
"""
import csv, json, re, sys, collections, datetime as dt, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
CSV = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / ".cache/hevy/workout_data.csv"
LIB = ROOT / "data/exercises.json"
ALIASES = ROOT / "data/hevy_aliases.json"
OUT = ROOT / ".cache/hevy/sessions.json"

EQUIP = {  # hevy "(…)" suffix -> tokens that appear in dataset names / equipment
    "barbell": ["barbell"], "dumbbell": ["dumbbell"], "cable": ["cable"], "machine": ["lever", "machine", "sled"],
    "smith machine": ["smith"], "pec deck": ["lever", "fly"], "kettlebell": ["kettlebell"], "band": ["band"],
}
SYN = {"bicep": "biceps", "tricep": "triceps", "flys": "fly", "flyes": "fly", "crossovers": "crossover",
       "curls": "curl", "raises": "raise", "rdl": "romanian", "pulldown": "pulldown", "pull-up": "pull-up"}
STOP = {"the", "with", "and", "of", "on", "a", "-", "grip"}

def tokens(s):
    t = re.findall(r"[a-z0-9\-]+", s.lower())
    return {SYN.get(x, x) for x in t if x not in STOP}

def split_hevy(name):
    m = re.match(r"^(.*?)\s*\((.*?)\)\s*$", name)
    return (m.group(1), m.group(2).lower()) if m else (name, "")

CURATED = {  # hand-checked overrides (Hevy name -> dataset name); None = custom exercise
    "Face Pull": None, "Cable Fly Crossovers": None, "Triceps Rope Pushdown": "cable triceps pushdown (v-bar)",
    "Single Arm Cable Row": None, "Butterfly (Pec Deck)": "lever seated fly", "Pull Up": "pull-up",
    "Squat (Barbell)": "barbell full squat", "Bicep Curl (Barbell)": "barbell curl", "Lat Pulldown (Cable)": "cable pulldown",
    "Leg Press (Machine)": "sled 45° leg press", "T Bar Row": "lever t bar row", "Triceps Pushdown": "cable pushdown",
    "Triceps Rope Pushdown": "cable pushdown (with rope attachment)", "Hack Squat (Machine)": "sled hack squat",
    "Overhead Press (Smith Machine)": "smith shoulder press", "Rear Delt Reverse Fly (Machine)": None,
    "Iso-Lateral Row (Machine)": None, "Single Leg Standing Calf Raise (Machine)": None,
    "Straight Leg Deadlift": "barbell straight leg deadlift", "Romanian Deadlift (Dumbbell)": "dumbbell romanian deadlift",
}

def score(hevy, ex):
    base, eq = split_hevy(hevy)
    bt, et = tokens(base), tokens(ex["name"]) | tokens(ex["equipment"])
    if eq: bt = bt | set(EQUIP.get(eq, [eq])[:1])   # equipment word joins the comparison
    j = len(bt & et) / len(bt | et) if bt | et else 0
    bonus = 0.15 if bt <= et else 0                  # every hevy word present
    bonus -= 0.04 * len(tokens(ex["name"]) - bt)     # prefer the plainest matching name
    return round(j + bonus, 3)

def draft_aliases(hevy_names, lib):
    out = {}
    by_name = {e["name"]: e for e in lib}
    for h in hevy_names:
        if h in CURATED:
            e = by_name.get(CURATED[h]) if CURATED[h] else None
            out[h] = {"id": e["id"] if e else None, "name": e["name"] if e else None, "confidence": 1.0, "candidates": [], "review": False, "curated": True}
            continue
        ranked = sorted(((score(h, e), e) for e in lib), key=lambda x: -x[0])[:3]
        best = ranked[0]
        out[h] = {
            "id": best[1]["id"] if best[0] >= 0.5 else None,
            "name": best[1]["name"] if best[0] >= 0.5 else None,
            "confidence": best[0],
            "candidates": [{"id": e["id"], "name": e["name"], "score": s} for s, e in ranked],
            "review": best[0] < 0.75,
        }
    return out

def parse_dt(s): return dt.datetime.strptime(s, "%d %b %Y, %H:%M")

def main():
    lib = json.load(open(LIB)); by_id = {e["id"]: e for e in lib}
    rows = list(csv.DictReader(open(CSV)))
    hevy_names = sorted({r["exercise_title"] for r in rows})
    if ALIASES.exists():
        aliases = json.load(open(ALIASES))
        missing = [h for h in hevy_names if h not in aliases]
        if missing:
            aliases.update(draft_aliases(missing, lib)); ALIASES.write_text(json.dumps(aliases, indent=2, ensure_ascii=False))
            print(f"added {len(missing)} draft aliases")
    else:
        aliases = draft_aliases(hevy_names, lib)
        ALIASES.write_text(json.dumps(aliases, indent=2, ensure_ascii=False))
        print(f"wrote DRAFT {ALIASES.relative_to(ROOT)} — review entries with \"review\": true")

    groups = collections.OrderedDict()
    for r in rows: groups.setdefault((r["title"], r["start_time"]), []).append(r)
    sessions = []
    for (title, start), rs in groups.items():
        exs = collections.OrderedDict()
        for r in rs: exs.setdefault(r["exercise_title"], []).append(r)
        st, en = parse_dt(start), parse_dt(rs[0]["end_time"])
        sessions.append({
            "title": title, "start": st.isoformat(), "end": en.isoformat(),
            "durationMin": int((en - st).total_seconds() // 60),
            "notes": rs[0]["description"] or None,
            "exercises": [{
                "hevyName": h,
                "exerciseId": aliases[h]["id"],
                "custom": aliases[h]["id"] is None,
                "notes": sets[0]["exercise_notes"] or None,
                "group": sets[0]["superset_id"] or None,
                "sets": [{
                    "i": int(s["set_index"]), "type": s["set_type"],
                    "kg": float(s["weight_kg"]) if s["weight_kg"] else None,
                    "reps": int(s["reps"]) if s["reps"] else None,
                    "seconds": int(s["duration_seconds"]) if s["duration_seconds"] else None,
                    "rpe": float(s["rpe"]) if s["rpe"] else None,
                } for s in sorted(sets, key=lambda s: int(s["set_index"]))],
            } for h, sets in exs.items()],
        })
    sessions.sort(key=lambda s: s["start"])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(sessions, indent=1, ensure_ascii=False))

    mapped = sum(1 for h in hevy_names if aliases[h]["id"])
    review = [h for h in hevy_names if aliases[h]["review"]]
    print(f"{len(rows)} rows -> {len(sessions)} sessions, {len(hevy_names)} exercises: {mapped} mapped, {len(hevy_names)-mapped} custom, {len(review)} flagged for review")
    for h in hevy_names:
        a = aliases[h]; flag = "  " if not a["review"] else "?!"
        print(f" {flag} {h:45s} -> {a['name'] or '(custom)':45s} {a['confidence']}")

if __name__ == "__main__":
    main()
