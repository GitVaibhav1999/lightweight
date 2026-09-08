-- Aggregates the client can read without pulling the rows behind them. History pages
-- 50 at a time; a 60-day chart or a lifetime total must not require 6,000 set logs.
--
-- Views, not tables: a rollup table needs a trigger on every set_logs write and is wrong
-- the moment one is missed. These are computed on read and cannot drift. PostgREST serves
-- a view exactly like a table, so if one ever gets slow it becomes a materialized view
-- with no client change.
--
-- security_invoker is not optional. A view runs as its OWNER by default, which bypasses
-- RLS entirely — without this every user would read everyone's totals.

-- One row per finished session, with its own sets rolled up. Everything else builds on
-- this, so the set-level join happens once rather than in each summary.
create or replace view session_totals
with (security_invoker = true) as
select
  s.id, s.user_id, s.workout_id, s.title, s.started_at,
  (s.started_at at time zone 'UTC')::date              as day,
  count(l.id) filter (where l.done)                    as sets,
  coalesce(sum(l.kg * l.reps) filter (where l.done and l.kg is not null), 0)::numeric(12,2) as volume,
  greatest(0, extract(epoch from (coalesce(s.ended_at, s.started_at) - s.started_at)) / 60)::int as minutes
from sessions s
left join session_exercises se on se.session_id = s.id and se.deleted_at is null
left join set_logs l          on l.session_exercise_id = se.id and l.deleted_at is null
where s.deleted_at is null and not s.is_draft
group by s.id;

-- The 60-day chart, the year strip and the streak all read days, not sessions.
create or replace view daily_summary
with (security_invoker = true) as
select user_id, day,
       count(*)::int      as sessions,
       sum(sets)::int     as sets,
       sum(volume)::numeric(12,2) as volume,
       sum(minutes)::int  as minutes
from session_totals
group by user_id, day;

-- The account page's headline numbers.
create or replace view user_totals
with (security_invoker = true) as
select user_id,
       count(*)::int              as sessions,
       sum(sets)::int             as sets,
       sum(volume)::numeric(14,2) as volume,
       sum(minutes)::int          as minutes,
       min(started_at)            as first_session,
       max(started_at)            as last_session
from session_totals
group by user_id;

-- Per-workout rollup: what the Home cards and the routine hero need without loading
-- a workout's whole history.
create or replace view workout_totals
with (security_invoker = true) as
select user_id, workout_id, title,
       count(*)::int              as sessions,
       sum(volume)::numeric(14,2) as volume,
       max(volume)::numeric(12,2) as best_volume,
       max(started_at)            as last_session
from session_totals
group by user_id, workout_id, title;

grant select on session_totals, daily_summary, user_totals, workout_totals to authenticated;

comment on view daily_summary  is 'per-day rollup; the 60-day chart and year strip read this, not sessions';
comment on view user_totals    is 'lifetime headline numbers for the account page';
comment on view workout_totals is 'per-workout rollup for Home cards and the routine hero';
