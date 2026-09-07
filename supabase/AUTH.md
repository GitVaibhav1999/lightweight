# Auth

## Who owns what

Supabase owns the `auth` schema — 23 tables (`users`, `identities`, `sessions`, `refresh_tokens`,
`mfa_*`, `sso_*`, `oauth_*`, …) plus the GoTrue service that writes them, all migrated by Supabase.

**There is no auth schema work to do.** Never write a migration against `auth`; a Supabase upgrade
will fight it. We own exactly one thing on our side:

- `public.profiles` — our row per user, keyed by `auth.users.id` with `on delete cascade`
- `public.handle_new_user()` + the `on_auth_user_created` trigger, which mints that row at signup

Everything the app needs about a user beyond identity lives in `profiles`.

## Hosted project: Sign in with Apple

Project ref `wbjnwhefotslkjxrvrgm`. Dashboard → **Authentication → Sign In / Providers → Apple**:

1. Toggle Apple on.
2. **Client IDs** — a comma-separated allow-list of values accepted as the `aud` claim of the
   Apple identity token. Put the bundle id `com.vaibhavgautam.lightweight` here. Add a Services ID
   too only if a web sign-in is ever added.
3. **Secret Key (for OAuth)** — leave blank for now. See below.

The app uses the **native id_token flow**: `ASAuthorizationAppleIDProvider` returns an identity
token, the SDK posts it to `/auth/v1/token?grant_type=id_token`, and GoTrue verifies the signature
against Apple's public keys at `https://appleid.apple.com/auth/keys` and checks `aud` against the
Client IDs list. **No client secret is involved.** The secret — a JWT signed with a `.p8` key, and
a Services ID, Team ID and Key ID alongside it — is only needed for the *web* redirect flow
(`/auth/v1/callback`), which this app does not use. Set Site URL / redirect URLs to
`lightweight://auth-callback`, matching `config.toml`.

## Apple Developer account

Only one thing is required: in **Certificates, Identifiers & Profiles → Identifiers**, the App ID
for `com.vaibhavgautam.lightweight` must have the **Sign in with Apple** capability enabled, and
the matching entitlement must be on the Xcode target. Without it Apple returns error 1000 at the
authorization sheet and nothing reaches Supabase.

A Services ID + key is *not* needed unless the web flow is added later.

Note: Apple returns the user's full name only on the **first** authorization, and the native
id_token carries no name claim at all, so `profiles.display_name` is normally null after an Apple
signup — by design, see `migrations/20260907000300_auth_hardening.sql`. If the app ever requests
Apple sign-in without the email scope, GoTrue rejects the user unless the provider's
`email_optional` is turned on (`config.toml` locally, the provider panel when hosted).

## Local vs hosted keys

The local `anon` and `service_role` keys — and the JWT secret they are signed with,
`super-secret-jwt-token-with-at-least-32-characters-long` — are **fixed public demo values,
byte-identical on every machine that runs `supabase start`**, published in Supabase's own docs.
They authenticate nothing and are safe to paste into scripts and commit.

The hosted project's keys are real secrets: `service_role` bypasses RLS entirely. Read them from
the dashboard when needed, never commit them.

`supabase/.env` (gitignored) holds a placeholder `SUPABASE_AUTH_EXTERNAL_APPLE_SECRET` purely so
`config.toml`'s `env()` substitution resolves at `supabase start`. Nothing validates it locally,
because the native flow never uses a client secret.
