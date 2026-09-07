# OVERLOAD — Design brief (Phase 1)

## The ask

**OVERLOAD — Phase 1, 8 iPhone screens (iOS 26, Liquid Glass).**
Personal strength tracker, single user. Three colours only: black ground `#000`, white in 100/60/30/12 % tiers, neon `#CCFF00` for action / progress / record. Glass surfaces for controls only — the bottom dock, tab bar, and sheets; content cards are flat `#0C0C0C`. Tabular numerals everywhere.
Screens and rules are below. Flow, hierarchy and real content: the attached flow mockup — every name and number there is real and should be reused. The one animation in the app is the PR moment on a set row (see Overload rules); everything else is still.
Build order: S1 Home → S2 Active session → S3 Summary (the loop), then S4, S8, then S5–S7.

## Terminology (use these words in the UI)

- **Exercise** — a movement (library or custom).
- **Workout** — a template: ordered slots of exercise · sets · rep range. Standalone; many.
- **Routine** — an ordered *loop* of workouts. One active; it holds the pointer to what's next.
- **Session** — a performed workout, dated. From a workout, or *fresh* (no template).


## Principles

| Principle | Meaning in practice |
|---|---|
| **Zero decisions at the gym** | App picks the next workout. Last time's numbers are prefilled. You repeat or beat them. |
| **One thumb, one glance** | Every mid-set action lives in the bottom half of the screen. Big tap targets. No rest timer, no chrome. |
| **Overload is the product** | Each exercise's progressive-overload state is first-class UI. A PR set is celebrated on the spot. |
| **Three colors, period** | Black, white, one neon. Neon means *action*, *progress* or *record* — never decoration. |
| **Simple graph** | One line per exercise. No toggles, no legends, no zoom. |
| **Your history is already here** | Hevy export imports on day one; nothing starts from zero. |
| **Phased** | Ship the loop first. Everything else waits. |

## Overload rules (what the badges and PR mean)

### 6.1 Metric of record — e1RM
Per set: `e1RM = w × (1 + r / 30)` (Epley). Per session per exercise: the max over its sets. Bodyweight exercises use best reps; time exercises best seconds — same graph, same badges.

### 6.2 Prefill (Phase 1 — no progression rule)
Each set row prefills with **last session's same-numbered set** (falls back to that session's top set) as ghost text. **Tapping ✓ with nothing typed repeats it**; typing overrides. The hint line shows `Last <top set> · best e1RM <b>` so you know what beating it means.

*Auto-progression targets (+1 rep / +2.5 kg, per-exercise increment) are deferred to Phase 2 — deliberately skipped for now.*

### 6.3 PR — the reward moment
A set is a **PR** when its e1RM beats the exercise's all-time best (evaluated per set, immediately on ✓). The set row lights neon with the new e1RM, haptic fires, and a `PR` tag stays on the row. This is the **only animation in the app** — spend it well (Liquid Glass highlight bloom, then settle). Session summary counts PRs; Home cards carry the `PR` tag on the exercise line.

### 6.4 Overload badge (per exercise, session vs. its previous session)

| State | Condition | Visual |
|---|---|---|
| **UP** | session e1RM higher | neon filled |
| **HELD** | equal | white outline |
| **DOWN** | lower | white outline |
| **STALL** | not UP for 3 consecutive sessions | neon outline, pulsing dot; nudge on S3 (deload flow is Phase 2) |

**Streak** = consecutive UP sessions. Resets on DOWN, not on HELD.

## Graph

- One SVG line, e1RM over the last 12 sessions. Latest point filled neon. STALL windows hatched.
- Tap a point → one tooltip: date · top set · e1RM.
- Under it: **Best · Last · Δ 30 d**. That's all the analytics.

## Screens

| # | Screen | Purpose | Key elements |
|---|---|---|---|
| S1 | **Home** | See history, start | Top: date + week dots (tap → S8). **Session cards**, newest first: workout name · when · duration, then each exercise line = name · `PR` tag · top set · badge (row → S4, card → S3 read-only). **Glass dock** pinned at bottom: `START NEXT · <WORKOUT>` (neon) + `Fresh workout` (outline). Tab bar. |
| S2 | **Active session** | Log | Header: workout name · elapsed · close. Per exercise: name + badge, hint `Last <top set> · best e1RM <b>`, set rows `# · prev · kg · reps · ✓` prefilled with last session's sets. **PR row state** (). Remaining exercises collapsed to first set. `+ Add exercise` → S7 (this is how a fresh session is built). Dock: `FINISH` (outline — the neon action here is ✓). No rest timer. |
| S3 | **Session summary** | Payoff | Name, time. Three numbers: duration · **PRs** (neon) · went-UP count. Per-exercise rows with `PR`, top set, streak, badge. Fresh session → `Save as workout`. `Next up · <WORKOUT>`. `DONE` (neon) commits + advances the pointer. |
| S4 | **Exercise detail** | Progress | Name, `target · equipment`, badge + streak, the simple graph, Best/Last/Δ30d, history rows (date · top set · e1RM · badge). Edit → name / target / increment / dataset link. |
| S5 | **Routines & workouts** | Setup | Active routine name + loop rows (drag, neon dot = pointer, tap → S6), `+ Add workout to loop`, **All workouts** list with session counts and `IN LOOP` tag, `+ New workout`. Also serves as "choose different". |
| S6 | **Workout edit** | Setup | Inline name, `n exercises · ~m min`, slot rows (drag · name · `sets × lo–hi`), `+ Add exercise` → S7, row tap → bottom sheet: sets · rep range. |
| S7 | **Exercise picker** | Setup / in-session | Sheet over S6 or S2. Search; target chips (19, pre-selected to the workout's dominant target); equipment chips (top 5 + more). Sections: **In your workouts** (with last top set) · Recent · All. Row = 40 px thumb · name · `target · equipment` · `+`. Tap adds and returns. `Create custom exercise`. Attribution line. |
| S8 | **Calendar & import** | Review | Month grid (Mon-first), trained days neon-dotted, today outlined, month totals; tap day → S3 read-only. Month's sessions as rows with PR counts. **Import from Hevy** + review sheet live here (and on first-run empty Home). |

Navigation: floating glass **tab bar** — Home · Exercises · Routines. Exercises tab = S7's list landing on S4. Active session is a full-screen modal. S8 hangs off the week dots, not a tab.

## Design system

```
BLACK  #000000   ground
WHITE  #FFFFFF   text, outlines, inactive  — opacity tiers 100 / 60 / 30 / 12 % are the only greys
NEON   #CCFF00   action · progress · record  (alternates: #39FF14 · #00FFD1 — one token)
```

- **Liquid Glass (iOS 26)**: the dock, tab bar, picker sheet and slot-edit sheet are glass surfaces floating over the black ground; content scrolls beneath them. Cards are flat panels (#0C0C0C), not glass — glass is reserved for controls so it stays legible.
- Neon is never a background for text longer than one word/number. Neon text on black for numbers; black text on neon for buttons and PR rows.
- Type: system display (SF) for the UI, **tabular numerals everywhere**; a mono face for set rows and stats is acceptable if it reads better on glass.
- Radius: 14 px buttons/cards, 22 px glass containers, 999 px pills. 1 px white-12 % dividers. No shadows — glass provides depth.
- Motion: **only** the PR moment and the STALL dot. Nothing else moves.

## Not in Phase 1 (don't draw these)

Rest timer · progression targets · supersets · RPE / warm-up · deload flow · exercise GIFs · settings screen · units toggle · social anything.


## Success criteria

- Start the next workout in **1 tap** from cold open; a fresh one in 1 tap + picker.
- Log a set in ≤ 1 tap when repeating last time.
- A PR is visible the moment the set is checked — no digging.
- Answer "am I progressing on this lift?" in ≤ 3 s from a Home card.
