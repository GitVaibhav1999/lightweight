#!/usr/bin/env python3
"""Same-workout comparison — UP / DOWN / HELD / STALLED / BEST.  This file IS the spec (PRD §6).

Reads .cache/hevy/sessions.json (from import_hevy.py) and prints a validation report.
"""
import json, collections, pathlib, statistics

ROOT = pathlib.Path(__file__).resolve().parent.parent
BAND = 1.0            # % mean e1RM change treated as noise -> HELD  (≈ SEM of 1 rep spread over 4–5 lifts)
MIN_COMMON = 2        # exercises shared with the previous session of this workout...
MIN_COVERAGE = 0.5    # ...and at least this share of today's exercises, else "new mix" (no verdict)
STALL_WINDOW = 3      # consecutive verdicts without an UP -> STALLED
PR_MIN_PRIOR = 3      # an exercise needs this many prior sessions before a set can be a PR
BASELINE_N = 3        # exercise baseline = median e1RM of its first N sessions (for the workout index)

def e1(kg, reps):                       # Epley; bodyweight -> reps. Direction-only use: fine at any rep count.
    return kg * (1 + reps / 30) if kg else float(reps)

def ex_metrics(sets):
    work = [s for s in sets if s.get("type", "normal") != "warmup" and s.get("reps")]
    return {"e1": max(e1(s["kg"], s["reps"]) for s in work)} if work else None

def session_delta(cur, prev):
    """Mean % change of top-set e1RM over exercises present in both sessions. None if not comparable."""
    common = [x for x in cur if x in prev]
    if len(common) < MIN_COMMON or len(common) < MIN_COVERAGE * len(cur): return None, common
    return sum((cur[x]["e1"] - prev[x]["e1"]) / prev[x]["e1"] for x in common) / len(common) * 100, common

def verdict_from_delta(d):
    return "UP" if d > BAND else "DOWN" if d < -BAND else "HELD"

def workout_index(cur, baseline):
    """Mean of e1RM / exercise-baseline over exercises with a baseline. 'How strong is this workout today'."""
    xs = [x for x in cur if x in baseline]
    return sum(cur[x]["e1"] / baseline[x] for x in xs) / len(xs) if len(xs) >= 2 else None

def run(sessions):
    """Chronological walk. Yields one record per session."""
    baseline, firsts = {}, collections.defaultdict(list)
    pr_best, seen = collections.defaultdict(float), collections.Counter()
    last, recent, best_idx = {}, collections.defaultdict(list), collections.defaultdict(float)
    for s in sessions:
        cur, prs = {}, []
        for ex in s["exercises"]:
            n, m = ex["hevyName"], ex_metrics(ex["sets"])
            if not m: continue
            cur[n] = m
            if n not in baseline:
                firsts[n].append(m["e1"])
                if len(firsts[n]) == BASELINE_N: baseline[n] = statistics.median(firsts[n])
            b = pr_best[n]
            for st in ex["sets"]:
                if st.get("type", "normal") == "warmup" or not st.get("reps"): continue
                v = e1(st["kg"], st["reps"])
                if v > b:
                    if seen[n] >= PR_MIN_PRIOR: prs.append((n, st["kg"], st["reps"], round(v, 1)))
                    b = v
            pr_best[n] = b; seen[n] += 1
        t = s["title"]; prev = last.get(t)
        d, common = (None, []) if prev is None else session_delta(cur, prev)
        verdict = None if d is None else verdict_from_delta(d)
        idx = workout_index(cur, baseline)
        state = verdict
        if verdict is not None:
            h = recent[t] + [verdict]
            if len(h) >= STALL_WINDOW and "UP" not in h[-STALL_WINDOW:]: state = "STALLED"
            if idx is not None and idx > best_idx[t] and verdict != "DOWN": state = "BEST"
            recent[t] = h[-10:]
        if idx is not None: best_idx[t] = max(best_idx[t], idx)
        last[t] = cur
        yield {"title": t, "start": s["start"], "verdict": verdict, "state": state, "delta": d,
               "index": idx, "prs": prs, "common": len(common), "of": len(cur)}

if __name__ == "__main__":
    out = list(run(json.load(open(ROOT / ".cache/hevy/sessions.json"))))
    yr = [r for r in out if r["start"] >= "2025-08-27"]
    c = collections.Counter(r["state"] for r in yr)
    print(f"{len(out)} sessions; last 12 months n={len(yr)}: " + " · ".join(f"{k or 'no verdict'} {c[k]}" for k in ["UP", "DOWN", "HELD", "STALLED", "BEST", None]))
    by = collections.defaultdict(list)
    for r in out: by[r["title"]].append(r)
    for t in ["Legs", "Push 1", "Back", "Shoulders and biceps"]:
        print(f"\n{t}")
        for r in by[t][-8:]:
            print(f"  {r['start'][:10]}  {str(r['state']):8s} {'' if r['delta'] is None else f'{r[chr(100)+chr(101)+chr(108)+chr(116)+chr(97)]:+5.1f}%':7s} idx={'—' if r['index'] is None else f'{r[chr(105)+chr(110)+chr(100)+chr(101)+chr(120)]:.2f}'}  {r['common']}/{r['of']} common  {len(r['prs'])} PR")
