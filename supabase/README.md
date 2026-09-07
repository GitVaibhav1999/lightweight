# Backend

Local-first stays local: SwiftData remains the source of truth for a live session.
This project is for durability, the coach endpoint, and anything multi-device.

## One-time, needs your Supabase login
    supabase login
    supabase link --project-ref <ref>          # after creating the project in the dashboard
    supabase secrets set OPENROUTER_API_KEY=...  # the key stops shipping in the app
    supabase db push                           # apply migrations
    supabase functions deploy coach

## Local development (needs Docker running)
    supabase start          # Postgres + Auth + Studio on :54321/:54323
    supabase db reset       # re-apply migrations from scratch

## Sign in with Apple
`auth.external.apple.client_id` is the app bundle id for native sign-in.
For the cloud project also set the Services ID + key in Dashboard → Auth → Providers → Apple.
