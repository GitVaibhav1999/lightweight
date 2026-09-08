-- Locks schema v1 against the shipped SwiftData model.
--
-- Three things were true before this migration and are not after:
--   1. Columns the app writes had no home here (is_started, srpe, prs, skipped).
--   2. Two child tables had no tombstone, so an offline delete could not sync.
--   3. Only one table was indexed for the query delta sync actually runs.

-- ─────────────────────────────────────────────────── 1. columns the app writes

-- A draft that has begun. isDraft alone cannot tell "composed, not started" from
-- "running right now", and the resume pill needs that distinction.
alter table sessions add column if not exists is_started boolean not null default false;

-- The post-session pair. Effort rises with fatigue AND with genuine intensity, so
-- srpe alone cannot separate a productive session from an under-recovered one;
-- prs is what breaks the tie. Legacy `rpe` (1-3) stays for sessions answered before.
alter table sessions add column if not exists srpe int check (srpe between 0 and 10);
alter table sessions add column if not exists prs  int check (prs  between 0 and 10);

-- Navigated past without checking. Distinct from absent: a skipped set is a
-- decision, and storing it as 0 x 0 would poison every volume and e1RM number.
alter table set_logs add column if not exists skipped boolean not null default false;

-- ─────────────────────────────────────────────── 2. tombstones on the children

-- Rule 2 of the core schema says deletes are soft, because a row hard-deleted on
-- the server is invisible to a device that was offline and resurrects on its next
-- push. That rule was only applied to the top-level tables. Deleting one set is a
-- routine action, so these two need it most.
alter table session_exercises add column if not exists deleted_at timestamptz;
alter table set_logs         add column if not exists deleted_at timestamptz;

-- ──────────────────────────────────────────────────── 3. the sync-shaped index

-- Pull sync asks exactly one question per table: "what changed for me since T?".
-- Without these it is a sequential scan per table per sync.
create index if not exists sessions_sync_idx          on sessions          (user_id, updated_at desc);
create index if not exists session_exercises_sync_idx on session_exercises (user_id, updated_at desc);
create index if not exists set_logs_sync_idx          on set_logs          (user_id, updated_at desc);
create index if not exists workout_slots_sync_idx     on workout_slots     (user_id, updated_at desc);
create index if not exists routines_sync_idx          on routines          (user_id, updated_at desc);
create index if not exists routine_entries_sync_idx   on routine_entries   (user_id, updated_at desc);
create index if not exists exercises_sync_idx         on exercises         (user_id, updated_at desc) where user_id is not null;
create index if not exists coach_notes_sync_idx       on coach_notes       (user_id, updated_at desc);

-- The live session is fetched by state, not by time.
create index if not exists sessions_draft_idx on sessions (user_id) where is_draft and deleted_at is null;

-- ──────────────────────────────────────────────────────────── 4. write it down

comment on column sessions.is_started is 'draft that has begun; isDraft says composed, this says running';
comment on column sessions.rpe        is 'legacy 1-3 ask; superseded by srpe/prs, kept so old sessions still read';
comment on column sessions.srpe       is 'Borg CR-10 session effort (Foster session-RPE). Ratio scale: srpe x duration is a real load';
comment on column sessions.prs        is 'Perceived Recovery Status (Laurent 2011), 0-10. The tie-breaker for effort';
comment on column set_logs.skipped    is 'moved past without checking; never store as 0 x 0';
comment on column exercises.user_id   is 'null = the shipped catalog (readable by all, writable by none). Non-null = a user''s own. This is what carries the client''s source=dataset|custom';
comment on column workout_slots.own_step is 'the client''s learned progression step, already snapped to an increment the equipment has';
