#!/usr/bin/env python3
"""Generate docs/flow-mockup.html — low-fi flow wireframes filled with the user's real Hevy history.
Re-run after changing screens or after a new Hevy export. Pure stdlib."""
import csv, json, html, collections, statistics, datetime as dt, pathlib, calendar

ROOT = pathlib.Path(__file__).resolve().parent.parent
CSV, LIB, OUT = ROOT / ".cache/hevy/workout_data.csv", ROOT / "data/exercises.json", ROOT / "docs/flow-mockup.html"
TODAY, INC = dt.date(2026, 8, 27), 2.5

# ---------------------------------------------------------------- data
def pd(s): return dt.datetime.strptime(s, "%d %b %Y, %H:%M")
rows = list(csv.DictReader(open(CSV)))
groups = collections.OrderedDict()
for r in rows: groups.setdefault((r["title"], r["start_time"]), []).append(r)
S = []
for (t, st), rs in groups.items():
    ex = collections.OrderedDict()
    for r in rs: ex.setdefault(r["exercise_title"], []).append(r)
    sets = {h: [(float(r["weight_kg"]) if r["weight_kg"] else None, int(r["reps"] or 0))
                for r in sorted(v, key=lambda r: int(r["set_index"]))] for h, v in ex.items()}
    a, b = pd(st), pd(rs[0]["end_time"])
    S.append(dict(title=t, start=a, end=b, mins=int((b - a).total_seconds() // 60), ex=sets))
S.sort(key=lambda s: s["start"])

def e1(kg, reps): return round(kg * (1 + reps / 30), 1) if kg else float(reps)
def top(sets): return max(sets, key=lambda s: e1(*s))
hist = collections.defaultdict(list)                     # exercise -> chronological sessions
for i, s in enumerate(S):
    for h, sets in s["ex"].items():
        k, r = top(sets); hist[h].append(dict(i=i, date=s["start"].date(), kg=k, reps=r, e1=e1(k, r), sets=sets))

def verdicts(h):
    L, raw = hist[h], []
    for n, x in enumerate(L):
        raw.append("HELD" if n == 0 else "UP" if x["e1"] > L[n-1]["e1"] else "HELD" if x["e1"] == L[n-1]["e1"] else "DOWN")
    return ["STALL" if v != "UP" and n >= 2 and raw[n-1] != "UP" and raw[n-2] != "UP" else v for n, v in enumerate(raw)]
def state(h, n=None):
    vs = verdicts(h); n = len(vs) - 1 if n is None else n
    streak = 0
    for v in reversed(vs[:n+1]):
        if v == "UP": streak += 1
        else: break
    return vs[n], streak
def hidx(h, i): return next(n for n, x in enumerate(hist[h]) if x["i"] == i)
def best_before(h, n): return max((x["e1"] for x in hist[h][:n]), default=0)
def prs_in(i):                                            # sets in session i that beat the all-time best
    out = []
    for h, sets in S[i]["ex"].items():
        b = best_before(h, hidx(h, i))
        for k, r in sets:
            if e1(k, r) > b: out.append((h, k, r, e1(k, r))); b = e1(k, r)
    return out

recent = [s for s in S if (TODAY - s["start"].date()).days <= 120]
cnt = collections.Counter(s["title"] for s in recent)
loop = sorted([t for t, c in cnt.items() if c >= 3], key=lambda t: max(s["start"] for s in S if s["title"] == t))
NEXT = loop[0]
def template(title):
    ss = [s for s in S if s["title"] == title][-6:]
    pos, ns, reps = collections.defaultdict(list), collections.defaultdict(list), collections.defaultdict(list)
    for s in ss:
        for p, (h, sets) in enumerate(s["ex"].items()):
            pos[h].append(p); ns[h].append(len(sets)); reps[h] += [r for _, r in sets]
    exs = sorted([h for h in pos if len(pos[h]) >= len(ss) / 2], key=lambda h: sum(pos[h]) / len(pos[h]))[:6]
    out = []
    for h in exs:
        rs = sorted(reps[h]); out.append(dict(name=h, sets=int(statistics.median(ns[h])), lo=rs[len(rs)//4], hi=rs[(3*len(rs))//4]))
    return out
TPL = template(NEXT)
def target(h, n=0):
    """Phase 1 prefill = last session's same-numbered set (falls back to its top set). No progression rule."""
    sets = hist[h][-1]["sets"]
    return sets[n] if n < len(sets) else top(sets)

# ---------------------------------------------------------------- html helpers
esc = html.escape
def kgf(k): return f"{k:g}"
def setf(k, r): return f"{kgf(k)} × {r}" if k else f"BW × {r}"
def rel(d):
    n = (TODAY - d).days
    return "today" if n == 0 else "yesterday" if n == 1 else f"{n} days ago" if n < 7 else d.strftime("%a %-d %b")
def badge(v):
    if v == "UP": return '<span class="badge up">UP</span>'
    if v == "STALL": return '<span class="badge stall"><i></i>STALL</span>'
    return f'<span class="badge">{v}</span>'
def streak(n): return f'<span class="streak">×{n}</span>' if n > 1 else ""
ICON = {
 "home": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M3 11l9-7 9 7"/><path d="M5 10v10h14V10"/></svg>',
 "ex": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12h3M19 12h3M8 12h8"/><rect x="5" y="8" width="3" height="8" rx="1"/><rect x="16" y="8" width="3" height="8" rx="1"/></svg>',
 "rt": '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M8 6h13M8 12h13M8 18h13M3.5 6h.01M3.5 12h.01M3.5 18h.01"/></svg>',
 "x": '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>',
 "back": '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg>',
 "chk": '<svg viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5 9-10"/></svg>',
 "drag": '<span class="handle"><svg viewBox="0 0 12 16" fill="currentColor"><circle cx="3" cy="3" r="1.4"/><circle cx="9" cy="3" r="1.4"/><circle cx="3" cy="8" r="1.4"/><circle cx="9" cy="8" r="1.4"/><circle cx="3" cy="13" r="1.4"/><circle cx="9" cy="13" r="1.4"/></svg></span>',
}
def tabs(on):
    return ('<nav class="tabs">' + "".join(f'<a class="{"on" if k == on else ""}" href="#{a}">{ICON[k]}{l}</a>'
            for k, a, l in [("home", "s1", "Home"), ("ex", "s4", "Exercises"), ("rt", "s5", "Routines")]) + "</nav>")
def pin(n): return f'<i class="pin">{n}</i>'
def note(n, t): return f'<li><i class="n">{n}</i><p>{t}</p></li>'
def screen(sid, phone, title, lead, notes, rule="", exits=""):
    return f'''
    <div class="screen" id="{sid}">
      <div class="phone">{phone}</div>
      <div class="sid">
        <h3><small>{sid.upper()}</small>{title}</h3>
        <p>{lead}</p>
        <ul class="notes">{"".join(notes)}</ul>
        {f'<div class="rule">{rule}</div>' if rule else ""}
        {f'<div class="exits">exits → {exits}</div>' if exits else ""}
      </div>
    </div>'''

# ---------------------------------------------------------------- S1 home
wk0 = TODAY - dt.timedelta(days=TODAY.weekday())
trained = {s["start"].date() for s in S}
week = "".join(f'<i class="{"done" if wk0 + dt.timedelta(d) in trained else ""}{" today" if wk0 + dt.timedelta(d) == TODAY else ""}"></i>' for d in range(7))
def card(i):
    s = S[i]; items = list(s["ex"].items())
    prs = {h for h, *_ in prs_in(i)}
    rws = "".join(f'<a class="crow" href="#s4"><span>{esc(h)}</span><span class="r">{"<span class=\"pr\">PR</span>" if h in prs else ""}<span class="m dim">{setf(*top(sets))}</span>{badge(state(h, hidx(h, i))[0])}</span></a>' for h, sets in items[:3])
    more = f'<div class="crow dim">+{len(items)-3} more</div>' if len(items) > 3 else ""
    return f'<a class="card" href="#s3"><div class="card-h"><b>{esc(s["title"])}</b><span class="m dim">{rel(s["start"].date())} · {s["mins"]} min</span></div>{rws}{more}</a>'
cards = "".join(card(i) for i in range(len(S) - 1, len(S) - 4, -1))
s1 = f'''<div class="top rel"><span>{TODAY.strftime("%a %-d %b")}</span><a class="week rel" href="#s8">{week}{pin(1)}</a></div>
<div class="feed rel" style="margin-top:16px">{cards}{pin(2)}</div>
<div class="grow"></div>
<div class="dock rel"><a class="cta" href="#s2">START NEXT · {esc(NEXT.upper())}</a><a class="ghost" href="#s2">Fresh workout</a>{pin(3)}</div>
{tabs("home")}'''

# ---------------------------------------------------------------- S2 active session
def setrow(n, prev, kg, reps, done, ghost=False, pr=None):
    cls = "in ghosted" if ghost else "in"
    chk = f'<span class="chk done">{ICON["chk"]}</span>' if done else '<span class="chk"></span>'
    prv = setf(*prev) if prev else "—"
    tag = f'<span class="prtag">PR · {pr:g}</span>' if pr else ""
    return f'<div class="set{" is-pr" if pr else ""}"><span class="dim">{n}</span><span class="dim">{prv}</span><span class="{cls}">{kgf(kg) if kg else "BW"}</span><span class="{cls}">{reps}</span>{chk}{tag}</div>'
h0 = TPL[0]["name"]; last0 = hist[h0][-1]; tk, tr = target(h0)
best0 = max(x["e1"] for x in hist[h0])
prk = tk
if tk:
    while e1(prk, tr) <= best0: prk += INC
pr_e1 = e1(prk, tr) if tk else None
prev_sets = last0["sets"] + [None] * 3
s2_rows = setrow(1, prev_sets[0], tk, tr, True) + setrow(2, prev_sets[1], prk if tk else tk, tr, True, pr=pr_e1) + setrow(3, prev_sets[2], *(target(h0, 2)), False, ghost=True)
others = "".join(f'''<div class="stack" style="gap:4px;margin-top:14px"><div class="ex-t">{esc(t["name"])} {badge(state(t["name"])[0])}</div>
<div class="hint">Last <em>{setf(hist[t["name"]][-1]["kg"], hist[t["name"]][-1]["reps"])}</em> · best e1RM <em>{max(x["e1"] for x in hist[t["name"]]):g}</em></div>
{setrow(1, hist[t["name"]][-1]["sets"][0], *target(t["name"]), False, ghost=True)}</div>''' for t in TPL[1:3])
s2 = f'''<div class="top rel"><a href="#s1" aria-label="Close" style="color:var(--ink-60)">{ICON["x"]}</a><span style="color:var(--ink);font-weight:800;font-size:15px">{esc(NEXT.upper())} <span class="m dim" style="font-weight:400;margin-left:8px">12:04</span></span><span></span>{pin(1)}</div>
<div class="stack rel" style="margin-top:18px; gap:6px">
  <div class="ex-t">{esc(h0)} {badge(state(h0)[0])}</div>
  <div class="hint">Last <em>{setf(last0["kg"], last0["reps"])}</em> · best e1RM <em>{best0:g}</em></div>
  <div class="set-h"><span>Set</span><span>Prev</span><span>kg</span><span>Reps</span><span></span></div>
  {s2_rows}{pin(2)}
</div>
<div class="rel">{others}{pin(3)}</div>
<a class="ghost rel" href="#s7" style="margin-top:14px;border-color:var(--neon);color:var(--neon)">+ Add exercise{pin(4)}</a>
<div class="wf" style="text-align:center;margin-top:10px">… {esc(", ".join(t["name"] for t in TPL[3:]))} (scroll)</div>
<div class="grow"></div>
<div class="dock rel"><a class="ghost" href="#s3">FINISH</a>{pin(5)}</div>'''

# ---------------------------------------------------------------- S3 summary
li = len(S) - 1; ls = S[li]; prs = prs_in(li); pr_ex = {h for h, *_ in prs}
vol = sum((k or 0) * r for sets in ls["ex"].values() for k, r in sets)
ups = sum(1 for h in ls["ex"] if state(h, hidx(h, li))[0] == "UP")
s3_rows = "".join(f'<a class="row" href="#s4">{esc(h)}<span class="r">{"<span class=\"pr\">PR</span>" if h in pr_ex else ""}<span class="m dim">{setf(*top(sets))}</span>{streak(state(h, hidx(h, li))[1])}{badge(state(h, hidx(h, li))[0])}</span></a>' for h, sets in ls["ex"].items())
s3 = f'''<div class="stack rel" style="margin-top:20px; gap:6px"><span class="lab neon">Session complete</span><div class="big">{esc(ls["title"].upper())}</div><span class="m dim" style="font-size:12px">{ls["start"].strftime("%a %-d %b · %H:%M")}</span></div>
<div class="stats rel" style="margin-top:22px"><div class="stat"><b>{ls["mins"]}<span class="dim" style="font-size:13px"> min</span></b><span class="lab">Duration</span></div><div class="stat"><b class="neon">{len(prs)} PR</b><span class="lab">e1RM records</span></div><div class="stat"><b>{ups}<span class="dim" style="font-size:13px"> / {len(ls["ex"])}</span></b><span class="lab">Went up</span></div>{pin(1)}</div>
<div class="list rel" style="margin-top:20px">{s3_rows}{pin(2)}</div>
<div class="wf rel" style="margin-top:12px">Fresh session? → <span style="color:var(--neon)">Save as workout</span>{pin(3)}</div>
<div class="grow"></div>
<div class="hint" style="margin-bottom:10px">Next up · <em>{esc(NEXT.upper())}</em> · loop advanced</div>
<div class="dock rel" style="padding-bottom:20px"><a class="cta" href="#s1">DONE</a>{pin(4)}</div>'''

# ---------------------------------------------------------------- S4 exercise detail
H = hist[h0][-12:]; V = verdicts(h0)[-12:]
lo_, hi_ = min(x["e1"] for x in H), max(x["e1"] for x in H); span = (hi_ - lo_) or 1
pts = [(10 + n * 280 / (len(H) - 1), 128 - (x["e1"] - lo_) / span * 100) for n, x in enumerate(H)]
hatch, n = "", 0
while n < len(V):
    if V[n] == "STALL":
        a = n - 2; b = n
        while b + 1 < len(V) and V[b+1] == "STALL": b += 1
        hatch += f'<rect x="{pts[max(a,0)][0]-8:.0f}" y="8" width="{pts[b][0]-pts[max(a,0)][0]+16:.0f}" height="122" fill="url(#hatch)"/><text x="{(pts[max(a,0)][0]+pts[b][0])/2:.0f}" y="144" text-anchor="middle" font-family="IBM Plex Mono, monospace" font-size="9" fill="#CCFF00">STALL</text>'
        n = b + 1
    else: n += 1
poly = " ".join(f"{x:.0f},{y:.0f}" for x, y in pts)
lx, ly = pts[-1]
tip = f"{H[-1]['date'].strftime('%-d %b')} · {setf(H[-1]['kg'], H[-1]['reps'])} · {H[-1]['e1']:g}"
best_all = max(x["e1"] for x in hist[h0]); lastv = hist[h0][-1]["e1"]
ref = [x for x in hist[h0] if (hist[h0][-1]["date"] - x["date"]).days >= 30]
d30 = lastv - (ref[-1]["e1"] if ref else hist[h0][0]["e1"])
lib = json.load(open(LIB)); aliases = json.load(open(ROOT / "data/hevy_aliases.json"))
libx = {e["id"]: e for e in lib}; a0 = aliases.get(h0, {}); e0 = libx.get(a0.get("id") or "", {})
s4_hist = "".join(f'<div class="row"><span class="m dim">{x["date"].strftime("%-d %b")}</span><span class="r"><span class="m">{setf(x["kg"], x["reps"])}</span><span class="m dim">{x["e1"]:g}</span>{badge(v)}</span></div>' for x, v in list(zip(H, V))[::-1][:4])
s4 = f'''<div class="top"><a href="#s1" aria-label="Back" style="color:var(--ink-60)">{ICON["back"]}</a><span>Edit</span></div>
<div class="stack rel" style="margin-top:14px; gap:4px"><div style="font-size:30px;font-weight:800;letter-spacing:-0.02em;line-height:1.1">{esc(h0)}</div><span class="dim" style="font-size:13px">{esc(e0.get("target", "custom"))} · {esc(e0.get("equipment", "—"))}</span><div style="display:flex;gap:10px;align-items:center;margin-top:6px">{badge(state(h0)[0])}{streak(state(h0)[1]) or '<span class="streak" style="color:var(--ink-30)">no streak</span>'}</div>{pin(1)}</div>
<div class="graph rel" style="margin-top:16px"><svg viewBox="0 0 300 150" role="img" aria-label="e1RM over the last {len(H)} sessions"><defs><pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><line x1="0" y1="0" x2="0" y2="6" stroke="#CCFF00" stroke-opacity="0.3" stroke-width="1"/></pattern></defs>{hatch}<polyline fill="none" stroke="#CCFF00" stroke-width="1.5" stroke-linejoin="round" points="{poly}"/><circle cx="{lx:.0f}" cy="{ly:.0f}" r="4" fill="#CCFF00"/><g font-family="IBM Plex Mono, monospace" font-size="9" fill="rgba(255,255,255,0.4)"><text x="10" y="144">{H[0]["date"].strftime("%-d %b")}</text><text x="290" y="144" text-anchor="end">{H[-1]["date"].strftime("%-d %b")}</text></g><g transform="translate({min(lx-120, 170):.0f} 6)"><rect width="122" height="18" rx="4" fill="#000" stroke="rgba(255,255,255,0.3)"/><text x="6" y="12.5" font-family="IBM Plex Mono, monospace" font-size="9" fill="#fff">{tip}</text></g></svg>{pin(2)}</div>
<div class="stats rel" style="margin-top:14px"><div class="stat"><b>{best_all:g}</b><span class="lab">Best e1RM</span></div><div class="stat"><b>{lastv:g}</b><span class="lab">Last</span></div><div class="stat"><b class="{"neon" if d30 > 0 else ""}">{d30:+g}</b><span class="lab">Δ 30 days</span></div>{pin(3)}</div>
<div class="list rel" style="margin-top:14px">{s4_hist}{pin(4)}</div>
<div class="grow"></div>{tabs("ex")}'''

# ---------------------------------------------------------------- S8 calendar
Y, M = S[-1]["start"].year, S[-1]["start"].month
first, ndays = calendar.monthrange(Y, M)
month_s = [s for s in S if s["start"].year == Y and s["start"].month == M]
cells = "".join('<span></span>' for _ in range(first)) + "".join(
    f'<span class="day{" on" if dt.date(Y, M, d) in trained else ""}{" today" if dt.date(Y, M, d) == TODAY else ""}"><b>{d}</b><i></i></span>' for d in range(1, ndays + 1))
mlist = "".join(f'<a class="row" href="#s3">{esc(s["title"])}<span class="r"><span class="m dim">{s["start"].strftime("%a %-d")}</span><span class="m dim">{s["mins"]} min</span>{f"<span class=\"pr\">{len(prs_in(S.index(s)))} PR</span>" if prs_in(S.index(s)) else ""}</span></a>' for s in month_s[::-1][:5])
s8 = f'''<div class="top"><a href="#s1" aria-label="Back" style="color:var(--ink-60)">{ICON["back"]}</a><a href="#s8" style="font-weight:600">Import from Hevy</a></div>
<div class="stack rel" style="margin-top:14px;gap:2px"><div style="font-size:26px;font-weight:800;letter-spacing:-0.02em">{calendar.month_name[M]} {Y}</div><span class="m dim" style="font-size:12px">{len(month_s)} sessions · {sum(s["mins"] for s in month_s)//60} h {sum(s["mins"] for s in month_s)%60} m</span>{pin(1)}</div>
<div class="cal rel" style="margin-top:14px"><div class="cal-h">{"".join(f"<span>{d}</span>" for d in "MTWTFSS")}</div><div class="cal-g">{cells}</div>{pin(2)}</div>
<div class="list rel" style="margin-top:14px">{mlist}{pin(3)}</div>
<div class="wf rel" style="margin-top:12px">Import review: 49 matched · 7 custom · 6 to confirm{pin(4)}</div>
<div class="grow"></div>{tabs("home")}'''

# ---------------------------------------------------------------- S5 routines
all_titles = collections.Counter(s["title"] for s in S).most_common(6)
loop_rows = "".join(f'<a class="row" href="#s6" style="height:50px"><span class="r">{ICON["drag"]}<span class="m dimmer">{n+1}</span>{esc(t)}</span><span class="r">{"<span class=\"lab neon\" style=\"font-size:10px\">● next</span>" if n == 0 else ""}<span class="m dim">{len(template(t))} ex</span></span></a>' for n, t in enumerate(loop))
wk_rows = "".join(f'<a class="row" href="#s6"><span>{esc(t)}</span><span class="r"><span class="m dim">{c}×</span>{"<span class=\"badge\" style=\"font-size:9px\">IN LOOP</span>" if t in loop else ""}</span></a>' for t, c in all_titles)
s5 = f'''<div style="font-size:28px;font-weight:800;letter-spacing:-0.02em;margin-top:6px">Routines</div>
<div class="stack rel" style="margin-top:16px; gap:4px"><span class="lab neon">Active routine</span><div style="font-size:18px;font-weight:700">Hevy split <span class="dim" style="font-weight:400;font-size:13px">· {len(loop)}-workout loop</span></div>{pin(1)}</div>
<div class="list rel" style="margin-top:8px">{loop_rows}{pin(2)}</div>
<a class="ghost rel" href="#s5" style="margin-top:12px;height:40px">+ Add workout to loop{pin(3)}</a>
<div class="stack rel" style="margin-top:22px; gap:4px"><span class="lab">All workouts</span>{wk_rows}<a class="row" href="#s6"><span class="dim">+ New workout</span><span></span></a>{pin(4)}</div>
<div class="grow"></div>{tabs("rt")}'''

# ---------------------------------------------------------------- S6 workout edit
slots = "".join(f'<div class="row" style="height:48px"><span class="r">{ICON["drag"]}{esc(t["name"])}</span><span class="r"><span class="m dim">{t["sets"]} × {t["lo"]}–{t["hi"]}</span><span class="dimmer">›</span></span></div>' for t in TPL)
t0 = TPL[0]
s6 = f'''<div class="top"><a href="#s5" style="color:var(--ink-60);display:flex;align-items:center;gap:4px">{ICON["back"]}Routines</a><a href="#s5" style="font-weight:600">Save</a></div>
<div class="stack rel" style="margin-top:14px; gap:4px"><div style="font-size:30px;font-weight:800;letter-spacing:-0.02em;line-height:1.1;border-bottom:1px dashed var(--ink-30);align-self:flex-start">{esc(NEXT)}</div><span class="dim" style="font-size:13px">{len(TPL)} exercises · ~{int(statistics.median(s["mins"] for s in S if s["title"] == NEXT))} min · in loop</span>{pin(1)}</div>
<div class="list rel" style="margin-top:14px">{slots}{pin(2)}</div>
<a class="ghost rel" href="#s7" style="margin-top:12px;border-color:var(--neon);color:var(--neon)">+ Add exercise{pin(3)}</a>
<div class="grow"></div>
<div class="sheet rel"><span class="grab"></span><div class="ex-t">{esc(t0["name"])} <span class="dim" style="font-weight:400;font-size:12px">Remove</span></div>
<div class="stats" style="grid-template-columns:repeat(2,minmax(0,1fr))"><div class="stat"><span class="lab">Sets</span><span class="in m field">{t0["sets"]}</span></div><div class="stat"><span class="lab">Rep range</span><span class="in m field">{t0["lo"]}–{t0["hi"]}</span></div></div>{pin(4)}</div>'''

# ---------------------------------------------------------------- S7 picker
tgt = e0.get("target", "lats") if e0 else "lats"
targets = ["All", tgt] + [t for t in ["upper back", "lats", "biceps", "delts", "traps", "pectorals"] if t != tgt][:4]
chips_t = "".join(f'<span class="chip{" on" if t == tgt else ""}">{esc(t)}</span>' for t in targets)
chips_e = "".join(f'<span class="chip">{e}</span>' for e in ["barbell", "cable", "dumbbell", "machine", "body weight", "more…"])
mine = "".join(f'<a class="row prow" href="#s6"><span class="th"></span><span class="grow"><span>{esc(t["name"])}</span><span class="m dim" style="display:block;font-size:11px">in {esc(NEXT)} · last {setf(hist[t["name"]][-1]["kg"], hist[t["name"]][-1]["reps"])}</span></span><span class="dimmer">+</span></a>' for t in TPL[:2])
pool = sorted([e for e in lib if e["target"] == tgt and e["equipment"] in ("cable", "barbell", "body weight", "leverage machine")], key=lambda e: e["name"])[:4]
allrows = "".join(f'<a class="row prow" href="#s6"><span class="th"></span><span class="grow"><span>{esc(e["name"])}</span><span class="m dim" style="display:block;font-size:11px">{esc(e["target"])} · {esc(e["equipment"])}</span></span><span class="dimmer">+</span></a>' for e in pool)
ntg = sum(1 for e in lib if e["target"] == tgt)
s7 = f'''<div class="top"><a href="#s6" style="color:var(--ink-60)">Cancel</a><span style="color:var(--ink);font-weight:700">Add to {esc(NEXT)}</span><span></span></div>
<div class="wf rel" style="margin-top:14px">Search {len(lib):,} exercises{pin(1)}</div>
<div class="chips" style="margin-top:10px">{chips_t}</div><div class="chips" style="margin-top:6px">{chips_e}</div>
<div class="stack rel" style="margin-top:14px;gap:0"><span class="lab">In your workouts</span>{mine}{pin(2)}</div>
<div class="stack rel" style="margin-top:12px;gap:0"><span class="lab">All · {esc(tgt)} · {ntg}</span>{allrows}{pin(3)}</div>
<div class="grow"></div>
<a class="ghost rel" href="#s7" style="border-color:var(--neon);color:var(--neon)">Create custom exercise{pin(4)}</a>
<div class="m dimmer" style="font-size:10px;text-align:center;padding:10px 0 14px">Thumbnails © Gym visual — gymvisual.com</div>'''

# ---------------------------------------------------------------- page
CSS = open(ROOT / "docs/mockup.css").read()
map_svg = f'''<svg viewBox="0 0 900 340" role="img" aria-labelledby="mapt"><title id="mapt">Screen flow map</title>
<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#CCFF00"/></marker><marker id="ahs" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="rgba(255,255,255,0.3)"/></marker></defs>
<rect class="box hot" x="20" y="30" width="200" height="64"/><text x="36" y="58">S1 Home</text><text class="sub" x="36" y="78">session cards · start next / fresh</text>
<rect class="box hot" x="350" y="30" width="200" height="64"/><text x="366" y="58">S2 Active session</text><text class="sub" x="366" y="78">sets vs target · PR moments</text>
<rect class="box hot" x="680" y="30" width="200" height="64"/><text x="696" y="58">S3 Summary</text><text class="sub" x="696" y="78">PRs · UP / HELD / DOWN / STALL</text>
<path class="arrow" d="M220 62H350" marker-end="url(#ah)"/><text class="lbl" x="240" y="52">START NEXT / FRESH</text>
<path class="arrow" d="M550 62H680" marker-end="url(#ah)"/><text class="lbl" x="588" y="52">FINISH</text>
<path class="arrow" d="M780 94V128H120V96" marker-end="url(#ah)"/><text class="lbl" x="330" y="122">DONE → loop pointer advances → new card on Home</text>
<rect class="box" x="20" y="176" width="200" height="56"/><text x="36" y="200">S4 Exercise detail</text><text class="sub" x="36" y="218">graph · best / last / Δ</text>
<rect class="box" x="350" y="176" width="200" height="56"/><text x="366" y="200">S5 Routines</text><text class="sub" x="366" y="218">active loop · all workouts</text>
<rect class="box" x="680" y="176" width="200" height="56"/><text x="696" y="200">S6 Workout edit</text><text class="sub" x="696" y="218">slots · sets × rep range</text>
<rect class="box" x="20" y="270" width="200" height="56"/><text x="36" y="294">S8 Calendar</text><text class="sub" x="36" y="312">month · import from Hevy</text>
<rect class="box" x="680" y="270" width="200" height="56"/><text x="696" y="294">S7 Exercise picker</text><text class="sub" x="696" y="312">search · target / equipment</text>
<path class="arrow soft" d="M60 94V176" marker-end="url(#ahs)"/><text class="lbl soft" x="68" y="150">tap a card row</text>
<path class="arrow soft" d="M200 94V140H450V176" marker-end="url(#ahs)"/><text class="lbl soft" x="300" y="164">Routines tab</text>
<path class="arrow soft" d="M550 204H680" marker-end="url(#ahs)"/><text class="lbl soft" x="580" y="196">tap workout</text>
<path class="arrow soft" d="M20 78H6V298H20" marker-end="url(#ahs)"/>
<path class="arrow soft" d="M780 232V270" marker-end="url(#ahs)"/><text class="lbl soft" x="788" y="256">+ add exercise</text>
<path class="arrow soft" d="M550 80H600V298H680" marker-end="url(#ahs)"/><text class="lbl soft" x="606" y="256">+ add (fresh session)</text>
</svg>'''

page = f'''<title>OVERLOAD Flow Mockup</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Archivo:wdth,wght@75..125,400..900&family=IBM+Plex+Mono:wght@400;600&display=swap">
<style>{CSS}</style>
<div class="page">
  <header class="hdr">
    <div class="eyebrow">OVERLOAD · <b>Phase 1</b> · flow mockup · low-fi · v0.4 · generated from your Hevy export ({len(S)} sessions)</div>
    <h1>Eight screens, one loop.</h1>
    <p class="lede">Wireframes for the Phase 1 scope in the PRD. Every name and number is real — it's what the Hevy import produces on day one. Neon marks the primary action on each screen; click it to follow the flow. Final frames are built in Claude Design as iOS 26 Liquid Glass: the floating bottom dock and tab bar here are placeholders for glass surfaces over the black ground.</p>
    <div class="legend"><span><i class="sw neon"></i>primary action / flow link</span><span><i class="sw dash"></i>placeholder block</span><span><i class="sw glass"></i>glass surface (dock / tab bar)</span><span><i class="n" style="width:16px;height:16px;font-size:10px">1</i>annotation</span></div>
  </header>
  <section class="map" aria-label="Flow map">{map_svg}</section>

  <section class="sec"><div class="sec-h"><h2>The loop</h2><span class="eyebrow">S1 → S2 → S3 → S1</span></div>
  {screen("s1", s1, "Home", "Your history as cards, newest first, and the two ways to start. The next workout is picked for you; a fresh session needs no template.", [
    note(1, "Week dots — filled = trained, outline = today. Tap → S8 calendar."),
    note(2, "One card per past session: workout name, when, duration, then each exercise with top set, <b>PR</b> tag and overload badge. Tap a row → S4, the card → its summary."),
    note(3, "Bottom dock (glass): <b>Start next</b> = the loop's next workout, big and neon. <b>Fresh workout</b> = empty session, add exercises as you go. <span>Nothing else on this screen is tappable except cards.</span>"),
  ], f"<b>Selector rule</b> · next = the workout after the last completed session's workout in the active routine loop, wrapping. Fresh sessions don't move the pointer. <em>&gt;10 days idle</em> → the dock asks \"Restart from {esc(loop[0])}?\".", '<a href="#s2">S2 start</a> <a href="#s4">S4 exercise</a> <a href="#s8">S8 calendar</a>')}
  {screen("s2", s2, "Active session", "Full-screen. No rest timer, no chrome — last time's numbers are prefilled, you repeat or beat them.", [
    note(1, "Header: workout name, elapsed time, close. <span>Closing without finishing keeps the session as a draft; it doesn't advance the loop.</span>"),
    note(2, "Set rows. Ghost text = <b>last session's same set</b>; tapping ✓ with nothing typed repeats it, typing overrides. No progression maths in Phase 1. Set 2 shows the <b>PR moment</b>: the row lights neon with the new e1RM the instant the set is checked — this is the reward UI, and the only animation in the app."),
    note(3, "Remaining exercises collapsed to their first set until you reach them."),
    note(4, "Add exercise mid-session → S7. This is how a fresh session is built."),
    note(5, "FINISH is outlined — the neon action on this screen is ✓."),
  ], "<b>PR rule</b> · a set is a PR when its e1RM = w × (1 + r/30) beats the exercise's all-time best. Checked per set, not per session.", '<a href="#s3">S3 finish</a> <a href="#s7">S7 add</a> <a href="#s1">S1 close</a>')}
  {screen("s3", s3, "Session summary", "The payoff. Records first, then the verdict per exercise, then back to Home — where this session is now the top card.", [
    note(1, "Three numbers: duration, <b>PRs set</b> (neon), exercises that went UP."),
    note(2, "Per exercise: PR tag if any set was a record, top set, streak, badge. Tap → S4."),
    note(3, "A fresh session can be saved as a Workout entity here, so it can join a routine later."),
    note(4, "DONE commits and advances the loop pointer."),
  ], "<b>Badge rule</b> (session e1RM vs. the exercise's previous session) · <em>UP</em> higher · <b>HELD</b> equal · <b>DOWN</b> lower · <em>STALL</em> = not UP three sessions running. Streak = consecutive UP sessions; resets on DOWN, not on HELD.", '<a href="#s1">S1 home</a> <a href="#s4">S4 exercise</a>')}
  </section>

  <section class="sec"><div class="sec-h"><h2>Progress</h2><span class="eyebrow">S4 · S8</span></div>
  {screen("s4", s4, "Exercise detail", f"\"Am I progressing on this lift\" in one glance. Shown here with your real {esc(h0)} history.", [
    note(1, "Badge + streak, same component as everywhere. Edit → name, target; the dataset link and thumbnail are here too."),
    note(2, "The simple graph: one line (e1RM), last 12 sessions, latest point filled, STALL windows hatched. Tap a point → one tooltip. <span>No legend, no toggles, no zoom.</span>"),
    note(3, "Best · Last · Δ 30 days. That's all the analytics."),
    note(4, "History rows: date · top set · e1RM · verdict. Scrolls."),
  ], "<b>Metric of record</b> · session e1RM = max over sets of <em>w × (1 + r / 30)</em>. Bodyweight exercises plot best reps on the same graph.", '<a href="#s1">back</a>')}
  {screen("s8", s8, "Calendar & import", "Month view of what actually happened, and where Hevy data comes in.", [
    note(1, "Month totals. Swipe for other months."),
    note(2, "Trained days carry a neon dot; today is outlined. Tap a day → that session's summary (S3, read-only)."),
    note(3, "The month's sessions as rows with PR counts."),
    note(4, "<b>Import from Hevy</b>: pick the CSV → review sheet lists unmatched exercise names (map to library or create custom) → sessions, badges, graphs and this calendar fill in. Re-import is idempotent; that's the Phase 1 sync."),
  ], "<b>Import key</b> · session = (title, start_time). Names map through <code>hevy_aliases.json</code>; unknowns go to the review sheet. Warm-up sets stored, excluded from overload.", '<a href="#s3">S3 read-only</a> <a href="#s1">back</a>')}
  </section>

  <section class="sec"><div class="sec-h"><h2>Setup</h2><span class="eyebrow">S5 → S6 → S7 · done once, rarely revisited</span></div>
  {screen("s5", s5, "Routines & workouts", "Workouts are standalone entities. A routine is an ordered loop of them. Exactly one routine is active — that loop is what the selector walks.", [
    note(1, "Active routine. Reconstructed from your Hevy titles on import (workouts used ≥ 3× in the last 120 days); rename freely."),
    note(2, "Loop order = drag order. Neon dot = where the pointer sits. Tap → S6."),
    note(3, "Add any existing workout to the loop."),
    note(4, "All workouts, in the loop or not, with how often you've done them. New workout → blank S6."),
  ], "", '<a href="#s6">S6 edit</a> <a href="#s1">home</a>')}
  {screen("s6", s6, "Workout edit", "Slots, not exercises: exercise · sets · rep range. The rep range is reference only in Phase 1.", [
    note(1, "Name edited inline. Duration estimate derived from set count."),
    note(2, "Drag to reorder. Sets × rep range reconstructed from your last six sessions (median sets, p25–p75 reps)."),
    note(3, "Add exercise → S7."),
    note(4, "Tap a row → bottom sheet: sets · rep range. <span>Nothing else to configure in Phase 1.</span>"),
  ], "", '<a href="#s7">S7 picker</a> <a href="#s5">Save → S5</a>')}
  {screen("s7", s7, "Exercise picker", f"Sheet over S6 (or S2 in a fresh session). {len(lib):,} library exercises plus yours, one search box, two chip rows.", [
    note(1, "Search by name. Target chips first (19), equipment chips second (top 5 + more). Chips pre-select the workout's dominant target."),
    note(2, "<b>In your workouts</b> first — exercises you already log, with last top set. Then Recent."),
    note(3, "Library rows: 40 px thumbnail · name · target · equipment · +. Tap adds and returns, no confirm."),
    note(4, "Create custom: name · target · equipment · load type. Face Pull, Cable Fly Crossovers and 5 more of yours are customs — not in the dataset."),
  ], "<b>Load type</b> derived from the dataset: cardio → time · body weight / assisted → bodyweight + reps · else weight + reps. Editable per exercise.", '<a href="#s6">S6</a> <a href="#s2">S2</a>')}
  </section>

  <section class="sec"><div class="sec-h"><h2>Not on these screens, on purpose</h2><span class="eyebrow">Phase 2+</span></div>
    <div class="rule" style="max-width:none; display:grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 8px 32px; border-style: dashed">
      <span>Rest timer</span><span>Progression targets (+1 rep / +2.5 kg)</span><span>Supersets / circuits</span><span>RPE · warm-up flag</span><span>Deload / swap flow from STALL</span><span>Exercise GIF + steps on S4</span><span>Hevy API sync (needs Pro key)</span><span>Body-weight log · notes</span><span>lb toggle · cloud backup</span>
    </div>
  </section>
</div>
'''
OUT.write_text(page)
print(f"wrote {OUT.relative_to(ROOT)} · next={NEXT} · loop={loop} · s2 exercise={h0} target={setf(tk, tr)} pr@{prk if tk else '-'} · {len(page)//1024} KB")
