-- Hardening for the signup trigger. Two problems, both of which only bite in production:
--   1. handle_new_user is `security definer` with no fixed search_path, so it resolves `profiles`
--      against whatever path the caller brought with them. Anything able to create an object earlier
--      on that path shadows the table and runs as the function's owner. Supabase's database linter
--      flags exactly this (function_search_path_mutable). Pin the path rather than trust the caller.
--   2. The trigger runs inside the signup transaction, so any failure to insert the profile fails
--      the signup itself. A user who cannot be created can never sign in; a missing profile row is
--      recoverable, because the client owns that row under RLS and can write it. Fail soft.
-- Behaviour is otherwise unchanged: one profile per auth.users row, named from provider metadata.

create or replace function public.handle_new_user() returns trigger
  language plpgsql
  security definer
  set search_path = public, pg_temp
as $$
declare
  meta    jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  display text;
begin
  -- Sign in with Apple hands over the name exactly once, at the first authorization, and the native
  -- id_token flow carries no name claim at all. It lands under `full_name` or `name` depending on
  -- the path taken, and `name` is sometimes an object rather than a string. Having no name is the
  -- ordinary case here, not an error -- the user names themselves later in the app.
  if jsonb_typeof(meta->'full_name') = 'string' then
    display := meta->>'full_name';
  elsif jsonb_typeof(meta->'name') = 'string' then
    display := meta->>'name';
  end if;

  insert into public.profiles (id, display_name)
  values (new.id, nullif(btrim(coalesce(display, '')), ''))
  on conflict (id) do nothing;          -- an id we already hold is not a reason to reject the user

  return new;
exception when others then
  raise warning 'handle_new_user: profile insert failed for %: %', new.id, sqlerrm;
  return new;
end $$;
