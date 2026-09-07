# Runbook

## Start everything

```sh
./scripts/dev.sh
```

Idempotent — run it any time, including when things are already up. It starts Docker
(waiting for the engine, which is not the same as the Docker Desktop window appearing),
starts Supabase if it isn't already, ensures a local dev user exists, and prints every
host and credential you need.

```sh
./scripts/dev.sh --reset      # wipe the local DB, replay all migrations from scratch
./scripts/dev.sh --no-user    # skip seeding the dev user
```

## What it gives you

| | |
|---|---|
| DB | `postgresql://postgres:postgres@127.0.0.1:54322/postgres` |
| API (Kong) | `http://127.0.0.1:54321` |
| Studio | `http://127.0.0.1:54323` |
| Mail (Mailpit) | `http://127.0.0.1:54324` — catches every local email |
| Dev env | `https://wbjnwhefotslkjxrvrgm.supabase.co` |

`54322` is Postgres, `54321` is the API gateway. Pointing a SQL client at `54321` fails
confusingly; Supabase avoids the default `5432` so it never collides with a native install.

**Sequel Ace cannot connect to any of this** — it is MySQL-only. Use Studio, DBeaver, or
`/opt/homebrew/opt/libpq/bin/psql` (Homebrew keeps `libpq` keg-only, so `psql` is not on PATH).

## The dev user

Every table is default-deny under RLS, so **without a user you cannot read or write a
single row** — `auth.uid()` returns null and every policy fails. That is why the script
seeds one. Credentials and a fresh JWT land in `supabase/.dev-user.env` (gitignored):

```sh
set -a; . supabase/.dev-user.env; set +a

curl -s "$LW_API/rest/v1/workouts?select=*" \
  -H "apikey: $LW_ANON_KEY" -H "Authorization: Bearer $LW_DEV_JWT"
```

The JWT expires after an hour — rerun `./scripts/dev.sh` to refresh it. `LW_DEV_USER_ID`
is the `user_id` to use when hand-writing rows or testing an edge function.

Connecting to Postgres as `postgres` makes you a **superuser, which bypasses RLS entirely**.
Studio and psql therefore show every row from every user — not what the app sees. To check
the app's view, always go through PostgREST with a user's JWT, as above.

## Which backend does the app talk to?

| Build | Backend | Why |
|---|---|---|
| Simulator | local stack | shares the Mac's loopback |
| Device (debug and release) | hosted project | see below |

A device cannot use the local stack for OAuth. Google only allows `http://` redirect URIs
for `localhost`; every other host must be `https://`, so a plain-HTTP LAN address can't even
be registered. And GoTrue hands Google its configured `api_external_url` (`127.0.0.1`), which
on a phone is the phone. The callback dead-ends. Hence: devices use hosted.

## Migrations

```sh
supabase migration list          # local vs remote
supabase db reset                # local: replay everything
supabase db push                 # apply to the hosted project
supabase config push             # apply config.toml (auth providers etc.) to hosted
```

`config push` **fails as a whole** if `config.toml` enables an email template override —
hosted free-tier rejects those without custom SMTP. The six-digit-code template therefore
lives at `supabase/templates/magic_link.html` but is deliberately not wired up in
`config.toml`. Re-enable it locally if you need email codes.

## Device install

Sign in with Apple needs a **paid** Apple Developer membership; a personal team cannot
provision the capability. Until enrolment completes, device builds strip the entitlement:

```sh
xcodebuild -project LightWeight.xcodeproj -scheme LightWeight \
  -destination 'id=<UDID>' -derivedDataPath build/DerivedData-device \
  CODE_SIGN_ENTITLEMENTS=/tmp/nosignin.entitlements -allowProvisioningUpdates build

xcrun devicectl device install app --device <UDID> <path>/LightWeight.app
```

`project.yml` keeps the real entitlement, so once the team is paid the override is simply
dropped. Team `T963382R64` belongs to `vaibhavsanjaymishra@gmail.com` — that Apple ID must
be signed in under Xcode → Settings → Accounts, or signing fails with a misleading
"capability missing" error.

## Gotchas seen for real

- **Docker socket answers `500`** while Docker Desktop looks fine: the Linux VM died and the
  socket proxy outlived it. `pgrep -f com.docker.virtualization` returning nothing is the
  tell. Quit Docker fully and relaunch — waiting does nothing.
- **Google `access_denied`**: the OAuth consent screen is in Testing mode. Add the address
  under *APIs & Services → OAuth consent screen → Audience → Test users*.
- **`e2e` needs `--mock-auth`** or every step sits behind a real login wall. `run.mjs`
  passes it already.
