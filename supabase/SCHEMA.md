# Schema v1 — locked

Five migrations, applied identically to local and to `wbjnwhefotslkjxrvrgm`.
Twelve tables, all owned by `public`; the `auth` schema is GoTrue's and is never touched.

## The three rules everything follows

1. **Primary keys are client-generated.** The phone mints a UUID in a gym with no signal
   and that id is final. The server never reassigns one.
2. **Deletes are soft.** A row hard-deleted server-side is invisible to a device that was
   offline, so it resurrects on the next push. `deleted_at` is the tombstone sync reads.
   Every one of the nine user tables now carries it.
3. **Every user row carries `user_id` and is fenced by RLS.** Default deny, opened by
   explicit policy. There is no trusted-client path.

## Tables

| Table | Holds | Notes |
|---|---|---|
| `profiles` | display name, unit | 1:1 with `auth.users`, created by trigger |
| `exercises` | the catalog | `user_id null` = shipped, readable by all, writable by none |
| `workouts` | templates | |
| `workout_slots` | a template's exercises | `own_step` = learned progression step |
| `routines` | the loop | one active per user, enforced by partial unique index |
| `routine_entries` | loop order | |
| `sessions` | performed workouts | `hevy_key` unique per user = idempotent import |
| `session_exercises` | what was done | |
| `set_logs` | the sets | |
| `coach_notes` | cached reads | unique `(user_id, kind, key)` — regenerates in place |
| `coach_actions` | every suggestion + its fate | the outcome ledger |
| `coach_calls` | usage, cost, rate limit | append-only; no tombstone by design |

## Field mapping — SwiftData ↔ Postgres

Not cosmetic. A sync layer needs this explicitly, and getting it wrong is silent.

| SwiftData | Postgres | Why it differs |
|---|---|---|
| `order` (slot, entry, sessionExercise) | `position` | `order` is a SQL reserved word |
| `index` (SetLog) | `position` | same shape as its siblings |
| `type` (SetLog) | `kind` | `type` is reserved in enough dialects to avoid |
| `source` (Exercise: dataset\|custom) | *derived* from `user_id is null` | one fact, one column |
| camelCase | snake_case | Postgres convention |

**Columns Postgres has that the client does not yet write:** `user_id` (every table),
`deleted_at` (nine tables), `workout_slots.own_step`. These are the sync surface, unused
until the client gains a `user_id`.

**Legacy kept deliberately:** `sessions.rpe` (1–3). Superseded by `srpe`/`prs` but still
read, so sessions answered before the change do not lose their answer.

## What is NOT in v1, and why

- **`user_id` on the SwiftData models.** The app is still local-only. Auth identifies you;
  it does not yet move data. Adding `user_id` client-side is step one of sync, not of auth.
- **Connections / friends.** Deliberately deferred — see below. This is the only pending
  decision that rewrites existing policies.
- **A server-side exercise catalog.** `exercises` with `user_id null` is empty in both
  databases; all 1,312 rows still live in the app bundle.

## Hevy parity

Every column a Hevy export carries has a home, so an import is lossless and a re-import
is a no-op rather than a quiet truncation. Idempotency is `sessions.hevy_key`
(`"title|start_time"`), unique per user.

| Hevy CSV | Lands in |
|---|---|
| `title` · `start_time` · `end_time` | `sessions.title` · `started_at` · `ended_at` |
| `description` | `sessions.description` |
| `exercise_title` | `session_exercises.exercise_name` |
| `exercise_notes` | `session_exercises.notes` |
| `superset_id` | `session_exercises.superset_id` |
| `set_index` · `set_type` | `set_logs.position` · `kind` |
| `weight_kg` · `reps` · `duration_seconds` | `set_logs.kg` · `reps` · `seconds` |
| `distance_km` | `set_logs.distance_km` |
| `rpe` | `set_logs.rpe` |

**`set_logs.rpe` is per-set; `sessions.srpe` rates the whole session.** Different questions —
how hard that set was, versus how hard the workout was. Both can be present.

**Client gap:** the DB can hold all of this; `HevyImporter` does not yet read
`description`, `exercise_notes`, `superset_id`, `distance_km` or per-set `rpe`, and the
SwiftData models have no fields for them. Until that is closed, a re-export would lose
them. In the current 470-session export that is 23 descriptions and 33 exercise notes;
superset, distance and per-set rpe are unused.

## Paginating history

Newest-first, 50 at a time, **keyset** — not offset. Offset re-scans everything it skips,
so page 20 costs twenty times page 1; keyset costs the same at any depth.

```
GET /rest/v1/sessions
  ?select=id,title,started_at,ended_at,source
  &deleted_at=is.null
  &order=started_at.desc,id.desc
  &limit=50
```

Next page — carry the last row's `(started_at, id)` forward:

```
  &or=(started_at.lt.<ts>,and(started_at.eq.<ts>,id.lt.<id>))
```

The `id` tie-break is not optional: two sessions can share a `started_at`, and ordering on
the timestamp alone silently drops or repeats rows across the boundary.

Served by `sessions_history_page_idx (user_id, started_at desc, id desc) where deleted_at
is null` — verified as an **Index Only Scan**, and verified across 120 rows / 3 pages with
zero duplicates and correct ordering. URL-encode the timestamp; its `+00:00` offset
otherwise decodes as a space.

## Summaries

The client pages history 50 at a time, so it never holds the whole history. A 60-day chart,
a streak or a lifetime total must therefore not require the rows behind them.

| View | Row shape | Used by |
|---|---|---|
| `session_totals` | one per finished session, sets/volume/minutes rolled up | the base the others build on |
| `daily_summary` | one per day | the 60-day chart, year strip, streak |
| `user_totals` | one per user | account page headline numbers |
| `workout_totals` | one per workout | Home cards, routine hero |

```
GET /rest/v1/daily_summary?select=day,sessions,sets,volume,minutes
  &day=gte.<60 days ago>&order=day.desc
```

Verified: a 60-day window returns **43 rows** rather than the sessions and thousands of set
logs underneath them.

**Views, not a rollup table.** A table needs a trigger on every `set_logs` write and is wrong
the moment one is missed; these are computed on read and cannot drift. PostgREST serves a view
exactly like a table, so if one becomes slow it can be made a materialized view with no client
change at all.

**`security_invoker = true` is load-bearing.** A Postgres view runs as its *owner* by default,
which bypasses RLS — without it every user would read everyone else's totals. Verified: a second
user and anon both get `[]` from all four views while the owner still sees their own.

## The friends decision (open)

Every policy today is one shape:

```sql
using (user_id = auth.uid()) with check (user_id = auth.uid())
```

That is the entire security model, and it is auditable at a glance. The moment a friend can
see your sessions, the predicate on every shared table becomes "mine, **or** shared with me
by someone who has accepted me" — a join against a `connections` table, evaluated per row.

Consequences worth knowing before agreeing to it:

- **Performance.** A policy that joins runs for every row of every query. It needs its own
  index and it will not be free at 470 sessions/user, let alone later.
- **Blast radius.** One wrong predicate leaks another person's training history. Today the
  worst a policy bug can do is show you your own data.
- **It is one-way in practice.** Once sharing exists, tightening it back is a product
  decision, not a migration.

Recommendation: **do not build it until there is a second user.** When it comes, add it as
a separate `shared_*` view or a security-definer function rather than widening the base
policies, so `user_id = auth.uid()` stays the rule and sharing is the explicit exception.

## Migrating from here

Every change is a new numbered file — never edit an applied migration.

```sh
supabase migration new <name>     # scaffold
supabase db reset                 # replay all, locally, from empty
supabase db push                  # apply the new one to hosted
supabase migration list           # local vs remote, must match
```

`db reset` is the real test: it proves the whole stack applies in order on an empty
database, which is what a new install or a rebuilt environment actually does.
