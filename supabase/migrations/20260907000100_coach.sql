-- Coach tables. coach_notes is what the app caches today; coach_actions is the ledger that lets the
-- coach grade its own advice (feature 5); coach_calls is usage, rate limiting and cost in one place.

create table coach_notes (
  id         uuid primary key,
  user_id    uuid not null references auth.users on delete cascade,
  kind       text not null,                       -- cycleInsight | sessionCoach | stallAdvice
  key        text not null,                       -- cycle-N | <sessionID>
  headline   text not null,
  body       text not null,
  model      text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (user_id, kind, key)                     -- one read per subject, regenerated in place
);

-- every suggestion the coach has ever made, and what became of it
create table coach_actions (
  id            uuid primary key,
  user_id       uuid not null references auth.users on delete cascade,
  note_id       uuid references coach_notes on delete set null,
  type          text not null check (type in
                  ('weight','step','repRange','loadType','reorder','sets','swap','addExercise')),
  exercise_id   text,
  exercise_name text not null,
  workout_id    uuid references workouts on delete cascade,
  from_value    text,
  to_value      text,
  reason        text,
  issued_cycle  int,
  state         text not null default 'offered'
                  check (state in ('offered','accepted','skipped','reverted')),
  decided_at    timestamptz,
  -- the outcome window: the affected lift when the call was made, and one and two cycles later
  index_at_issue numeric(8,3),
  index_after_1  numeric(8,3),
  index_after_2  numeric(8,3),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index on coach_actions (user_id, exercise_id, created_at desc);
-- "stop re-proposing what was skipped three times" is a query, not a heuristic in the prompt
create index on coach_actions (user_id, exercise_id, type, state);

create table coach_calls (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users on delete cascade,
  kind              text not null,
  model             text,
  prompt_tokens     int,
  completion_tokens int,
  cost              numeric(10,6),
  ms                int,
  ok                boolean not null default true,
  created_at        timestamptz not null default now()
);
create index on coach_calls (user_id, created_at desc);
