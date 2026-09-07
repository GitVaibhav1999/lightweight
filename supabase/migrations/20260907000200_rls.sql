-- Row level security. Default deny: every table is locked, then opened by explicit policy.
-- The pattern is identical everywhere, which is the point: one rule to audit, not fourteen.

alter table profiles          enable row level security;
alter table exercises         enable row level security;
alter table workouts          enable row level security;
alter table workout_slots     enable row level security;
alter table routines          enable row level security;
alter table routine_entries   enable row level security;
alter table sessions          enable row level security;
alter table session_exercises enable row level security;
alter table set_logs          enable row level security;
alter table coach_notes       enable row level security;
alter table coach_actions     enable row level security;
alter table coach_calls       enable row level security;

create policy "own profile" on profiles
  for all using (id = auth.uid()) with check (id = auth.uid());

-- the shipped catalog is readable by everyone; only your own custom exercises are writable
create policy "read catalog and own"  on exercises for select
  using (user_id is null or user_id = auth.uid());
create policy "write own exercises"   on exercises for insert with check (user_id = auth.uid());
create policy "update own exercises"  on exercises for update using (user_id = auth.uid());

do $$
declare t text;
begin
  foreach t in array array['workouts','workout_slots','routines','routine_entries',
                           'sessions','session_exercises','set_logs','coach_notes','coach_actions']
  loop
    execute format('create policy "own rows" on %I for all using (user_id = auth.uid()) with check (user_id = auth.uid())', t);
  end loop;
end $$;

-- usage is written by the edge function on the user's behalf and is read-only to the client
create policy "read own usage" on coach_calls for select using (user_id = auth.uid());

-- keep updated_at honest for last-write-wins sync, without trusting the client's clock
create function touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

do $$
declare t text;
begin
  foreach t in array array['profiles','exercises','workouts','workout_slots','routines','routine_entries',
                           'sessions','session_exercises','set_logs','coach_notes','coach_actions']
  loop
    execute format('create trigger touch before update on %I for each row execute function touch_updated_at()', t);
  end loop;
end $$;
