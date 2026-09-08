-- Hevy parity: every column a Hevy export carries now has somewhere to land, so an
-- import is lossless and a re-import is a no-op rather than a quiet truncation.
--
-- Export shape (14 columns) and where each goes:
--   title, start_time, end_time            -> sessions.title / started_at / ended_at
--   description                            -> sessions.description          [added here]
--   exercise_title                         -> session_exercises.exercise_name
--   superset_id                            -> session_exercises.superset_id [added here]
--   exercise_notes                         -> session_exercises.notes       [added here]
--   set_index, set_type                    -> set_logs.position / kind
--   weight_kg, reps, duration_seconds      -> set_logs.kg / reps / seconds
--   distance_km                            -> set_logs.distance_km          [added here]
--   rpe                                    -> set_logs.rpe                  [added here]

alter table sessions          add column if not exists description text;
alter table session_exercises add column if not exists notes       text;
-- Groups exercises performed together. Hevy emits a per-workout group id, not a global one.
alter table session_exercises add column if not exists superset_id text;
alter table set_logs          add column if not exists distance_km numeric(8,3);
-- Hevy's PER-SET rpe. Distinct from sessions.srpe, which rates the whole session:
-- one is how hard that set was, the other how hard the workout was. Both may exist.
alter table set_logs          add column if not exists rpe numeric(3,1) check (rpe between 0 and 10);

comment on column sessions.description          is 'Hevy workout description';
comment on column session_exercises.notes       is 'Hevy exercise_notes';
comment on column session_exercises.superset_id is 'Hevy superset grouping, scoped to its workout';
comment on column set_logs.distance_km          is 'Hevy distance_km — cardio/carry work';
comment on column set_logs.rpe                  is 'Hevy PER-SET rpe; sessions.srpe rates the whole session';

-- History is read newest-first, 50 at a time, keyset-paginated on (started_at, id).
-- sessions (user_id, started_at desc) already exists from the core migration and is the
-- index that serves it; this one covers the tie-break so deep pages stay on the index.
create index if not exists sessions_history_page_idx
  on sessions (user_id, started_at desc, id desc) where deleted_at is null;
