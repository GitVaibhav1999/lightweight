-- LIGHT WEIGHT core schema.
-- Three rules shape everything here:
--   1. The client is offline-first, so PRIMARY KEYS ARE CLIENT GENERATED. The phone mints a UUID in
--      the gym with no signal and that id is final; the server never reassigns it.
--   2. Deletes are SOFT. A row hard-deleted on the server is invisible to a device that was offline,
--      so it would resurrect on the next push. deleted_at is the tombstone sync reads.
--   3. Every user row carries user_id and is fenced by RLS. There is no "trusted client" path.

create extension if not exists "pgcrypto";

-- ─────────────────────────────────────────────────────────────── identity

create table profiles (
  id           uuid primary key references auth.users on delete cascade,
  display_name text,
  unit         text not null default 'kg' check (unit in ('kg','lb')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- a profile row should exist the moment someone signs in, not on first write
create function handle_new_user() returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, display_name) values (new.id, new.raw_user_meta_data->>'full_name');
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- ─────────────────────────────────────────────── catalog: shared rows + custom rows

-- user_id null  = the shipped catalog, readable by everyone, writable by no one
-- user_id set   = an exercise this user invented ("custom-<uuid>" ids in the app today)
create table exercises (
  id          text primary key,
  user_id     uuid references auth.users on delete cascade,
  name        text not null,
  body_part   text,
  target      text,
  equipment   text,
  load_type   text not null default 'weight+reps',
  thumb       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index on exercises (user_id) where user_id is not null;

-- ─────────────────────────────────────────────────────────────── training structure

create table workouts (
  id          uuid primary key,
  user_id     uuid not null references auth.users on delete cascade,
  name        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);
create index on workouts (user_id, updated_at desc);

create table workout_slots (
  id            uuid primary key,
  workout_id    uuid not null references workouts on delete cascade,
  user_id       uuid not null references auth.users on delete cascade,
  position      int  not null,                       -- "order" is reserved in SQL
  exercise_id   text not null,
  exercise_name text not null,                       -- denormalised: survives a catalog change
  sets          int  not null default 3,
  rep_lo        int  not null default 8,
  rep_hi        int  not null default 12,
  own_step      numeric(6,2),                        -- the client's learned progression step
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  unique (workout_id, position) deferrable initially deferred   -- reorder writes many rows at once
);
create index on workout_slots (workout_id);

create table routines (
  id               uuid primary key,
  user_id          uuid not null references auth.users on delete cascade,
  name             text not null,
  is_active        boolean not null default true,
  pointer          int  not null default 0,
  cycles_completed int  not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz
);
-- one active routine per user, enforced by the database rather than by hope
create unique index one_active_routine on routines (user_id) where is_active and deleted_at is null;

create table routine_entries (
  id         uuid primary key,
  routine_id uuid not null references routines on delete cascade,
  user_id    uuid not null references auth.users on delete cascade,
  position   int  not null,
  workout_id uuid not null references workouts on delete cascade,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (routine_id, position) deferrable initially deferred
);

-- ─────────────────────────────────────────────────────────────── logged training

create table sessions (
  id          uuid primary key,
  user_id     uuid not null references auth.users on delete cascade,
  workout_id  uuid references workouts on delete set null,   -- keep the history if the workout goes
  title       text not null,
  started_at  timestamptz not null,
  ended_at    timestamptz,
  source      text not null default 'app',                   -- app | hevy | seed
  hevy_key    text,                                          -- "title|start_time" from the export
  is_draft    boolean not null default false,
  rpe         int check (rpe between 1 and 3),
  edited      boolean not null default false,
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,
  -- idempotent import, but scoped per user: two people may own the same Hevy row
  unique (user_id, hevy_key)
);
create index on sessions (user_id, started_at desc);
create index on sessions (user_id, workout_id, started_at desc);

create table session_exercises (
  id            uuid primary key,
  session_id    uuid not null references sessions on delete cascade,
  user_id       uuid not null references auth.users on delete cascade,
  position      int  not null,
  exercise_id   text not null,
  exercise_name text not null,
  updated_at    timestamptz not null default now()
);
create index on session_exercises (session_id);

create table set_logs (
  id                  uuid primary key,
  session_exercise_id uuid not null references session_exercises on delete cascade,
  user_id             uuid not null references auth.users on delete cascade,
  position            int  not null,
  kind                text not null default 'normal',        -- normal | warmup | failure | dropset
  kg                  numeric(6,2),                          -- null means bodyweight, never zero
  reps                int,
  seconds             int,
  done                boolean not null default false,
  is_pr               boolean not null default false,
  updated_at          timestamptz not null default now()
);
create index on set_logs (session_exercise_id);
