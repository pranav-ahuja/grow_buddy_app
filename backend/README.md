# GrowBuddy Backend

FastAPI + SQLAlchemy service backing the GrowBuddy Flutter app. This first pass
covers authentication only: email/password sign-up and login, phone OTP login,
and the current-user endpoint.

## Running it

Python 3.12 is already installed on this machine, but only as `py` — the
`python` on PATH is the Microsoft Store stub, which prints "Python was not
found" instead of running anything.

Run these **from the `backend/` directory**. Every path below is relative to it,
so run `cd backend` first only if you are somewhere else; some editors and
terminals already open here.

### PowerShell (Windows default)

```powershell
py -3 -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item .env.example .env
.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```

### Git Bash / WSL

Backslashes are escape characters in bash, so paths need forward slashes and
`copy` becomes `cp`:

```bash
py -3 -m venv .venv
.venv/Scripts/python.exe -m pip install -r requirements.txt
cp .env.example .env
.venv/Scripts/python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```

The first three commands are one-time setup; only the last one is needed on
subsequent runs.

`--host 0.0.0.0` matters: it is what lets a phone on the same Wi-Fi reach the
server. Binding to the default `127.0.0.1` only accepts connections from this
machine.

Then open **http://127.0.0.1:8080/docs** for interactive API docs where every
endpoint can be tried in the browser. Stop the server with `Ctrl+C`.

## Tests

```bash
.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.venv\Scripts\python.exe -m pytest -q
```

149 tests cover sign-up, login, OTP, Google, classes and students, the
principal's scope, subjects, attendance and the teacher record — all against
an in-memory database. The Google tests stub out token verification, so they
never call Google and need no credentials.

The tests build their database by running the **real migrations**, so a
migration that is wrong or missing fails the suite rather than passing against
a schema no real database ever went through.

## Migrations (Alembic)

Alembic has owned the schema since 2026-09-17. `create_schema()` is gone: it
called `create_all`, which only ever creates tables that are *missing*, so once
a table existed, adding a column or widening a constraint did nothing at all —
silently.

```powershell
# apply everything outstanding
.venv\Scripts\python.exe -m alembic upgrade head

# where is this database?
.venv\Scripts\python.exe -m alembic current
.venv\Scripts\python.exe -m alembic history

# after changing a model — review the generated file before running it
.venv\Scripts\python.exe -m alembic revision --autogenerate -m "what changed"

# undo the last one
.venv\Scripts\python.exe -m alembic downgrade -1
```

Things to know:

- **The server checks, but never migrates.** `app/main.py` refuses to start if
  the database is behind the code, and prints the command to fix it. Applying a
  migration stays something a person runs — an auto-upgrade on boot is how two
  workers race each other through the same DDL.
- **The URL is not in `alembic.ini`.** `alembic/env.py` overwrites it with
  `settings.database_url` from `.env`, so the password is never committed and a
  migration cannot run against a different database than the server uses. The
  placeholder in the ini file is meant to stay a placeholder.
- **Autogenerate does not see everything.** It ignores CHECK constraints
  entirely (migration `0002` is hand-written for that reason), it cannot
  reflect expression indexes such as `uq_students_same_child` or
  `uq_subjects_name` on SQLite, it does not seed rows (migration `0003` adds
  the `S` counter by hand), and it does not manage the `class_roster` view —
  `env.py` excludes that view by name so autogenerate stops offering to drop
  it. Always read the generated file.
- **Adopting an existing pre-Alembic database**: `alembic stamp 0001` first,
  which records "this schema is already here" without running the CREATEs, then
  `alembic upgrade head`.

### What autogenerate got wrong in `0004`

Both of these would have failed on the real database. They are worth knowing
because the next `--autogenerate` will do the same:

- **A NOT NULL column with no default.** It added `teachers.updated_at` as
  `nullable=False`. A row already existed (`TR_000001`), and no existing row
  can satisfy a NOT NULL column that has no value — PostgreSQL refuses the
  whole statement. The fix is three steps: add it nullable, backfill (here
  from `created_at`, since a row never edited was last "updated" when it was
  made), then set NOT NULL.
- **An unnamed constraint.** It emitted `create_unique_constraint(None, ...)`
  and a matching `drop_constraint(None, ...)`. The database names an unnamed
  constraint itself, so the downgrade has nothing to look up. Always name it.

And one that only SQLite shows, which matters because the tests run there:
**SQLite cannot ALTER a constraint into an existing table at all.** Wrap that
kind of change in `op.batch_alter_table`, which recreates the table; on
PostgreSQL it is an ordinary ALTER.

| Revision | What it does |
| --- | --- |
| `0001` | Baseline — the schema as it stood before Alembic. Tables, both expression indexes, the `class_roster` view, and the seeded `id_counters` rows. |
| `0002` | Widens `ck_users_role` to allow `role = 'principal'`. Backfills nothing; no existing account changes role. |
| `0003` | Adds `subjects` and `attendance`, plus the `S` row in `id_counters`. Hand-written for the `lower(name)` index and that counter row. |
| `0004` | Expands `teachers` (DOB, qualification, address, relationship status, Aadhaar, emergency contact, `updated_at`) and adds `teacher_subjects` and `teacher_experience`. Rewritten after autogenerate produced two bugs — see below. |
| `0005` | Adds `student_guardians` — a parent's account linked to their child. Nothing backfilled: there is no safe guess about which account belongs to which child. |
| `0006` | Makes `classes.teacher_id` nullable and adds `class_teachers`, `change_requests` and `notifications` — the principal-as-admin approval queue. Drops and rebuilds the `class_roster` view and `uq_classes_teacher_name` by hand. |
| `0007` | Adds `contact_change_codes`, so a new email or phone waits for its code before reaching `users`. |
| `0008` | Renames `student_guardians` to `student_mapping` (and `relation` to `relationship`, plus the PostgreSQL constraint names), adds `source`, and adds `users.is_email_verified`. Backfills automatic mappings for parent accounts with a verified phone on a pupil's record. Batch mode on SQLite reflects neighbouring tables, hence harmless "Skipped unsupported reflection of expression-based index" warnings in the test run. |
| `0009` | Rewrites every stored phone number (`students` mother/father/guardian, `users`) to `+91XXXXXXXXXX`, maps the parents that then match, and rebuilds `class_roster` so roll numbers follow registration order instead of the alphabet. Downgrade restores the alphabetical view; the numbers stay normalised. |

## Endpoints

All under `/api/v1/auth`. Errors always come back as `{"detail": "message"}`,
which the app shows directly in a SnackBar.

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| POST | `/signup` | `full_name`, `identifier`, `password`, `account_type` | 201 + token |
| POST | `/login` | `email`, `password` | 200 + token |
| POST | `/otp/request` | `phone` | 200 + `expires_in_seconds` |
| POST | `/otp/verify` | `phone`, `otp` | 200 + token |
| POST | `/google` | `id_token` | 200 + token |
| GET | `/me` | — (Bearer token) | 200 + user |
| PATCH | `/me` | `full_name` and/or `account_type` (Bearer token) | 200 + user |
| POST | `/me/contact/request` | `channel` (`phone`/`email`), `value` (Bearer token) | 200 + `expires_in_seconds`. **Changes nothing yet** |
| POST | `/me/contact/verify` | `channel`, `otp` (Bearer token) | 200 + user, with the new contact on it |

`identifier` is either an email address or a phone number — the server works out
which, so the app's single "Email id / Phone Number" field maps straight
through. `account_type` is `0` for teacher, `1` for student and `2` for
principal, matching `GB_Constants.dart`.

A token response looks like:

```json
{
  "access_token": "eyJhbGciOi...",
  "token_type": "bearer",
  "is_new_user": false,
  "user": {
    "id": 1,
    "full_name": "Pranav Ahuja",
    "email": "pranav@example.com",
    "phone": null,
    "account_type": 0,
    "role": "teacher",
    "needs_account_type": false,
    "is_phone_verified": false,
    "created_at": "2026-08-09T13:31:00.800778"
  }
}
```

Two fields drive what the app does next:

- `needs_account_type` — `account_type` is still null, because Google and phone
  sign-ins cannot tell us teacher vs student. Send the user to the sign-up
  screen to enter a name and pick a role, then `PATCH /me`.
- `is_new_user` — this call created the account rather than signing in to one.

**Route on `needs_account_type`, not `is_new_user`.** Someone who abandons the
sign-up screen is no longer "new" on their next login but still has no role, so
keying off `is_new_user` would strand them with an incomplete profile forever.
Use `is_new_user` only to choose the wording ("Welcome!" vs "Finish setting up").

## How Google Sign-In works here

The app sends an **ID token** — a JWT that Google signed — and the server
verifies that signature against Google's public keys before believing a word of
it. It never accepts an email from the client: anyone with curl could then post
`{"email": "principal@school.com"}` and be logged in as the principal.

Deciding whether it is a first login is a three-step lookup, in
[app/routers/auth.py](app/routers/auth.py):

1. **Match on `google_id`** (the token's `sub` claim). This is the right key
   because Google guarantees it is unique and permanent — it survives the user
   renaming their Gmail address.
2. **Otherwise match on a verified email**, which means they already have an
   account from the password or phone flow and are now pressing the Google
   button. Link the two rather than creating a duplicate.
3. **Otherwise create the account**, with `is_new_user: true` in the response.

Matching on email alone is the tempting shortcut, but emails get reassigned and
users change theirs, whereas `sub` never changes. An email Google reports as
*unverified* is never used to find or fill in an account, since it would
otherwise be a way to claim somebody else's.

### Identity vs. attributes

`google_id` is the account's **identity**; email and name are **attributes** of
it. So if somebody renames their Gmail address, the account does not change —
the next token carries the same `sub`, resolves to the same row, and keeps all
their data. What *must* happen is that the row's stored email is refreshed, or it
goes stale and email/password login breaks for them. `_sync_google_profile` in
[app/routers/auth.py](app/routers/auth.py) does that on every returning login:

- The email is updated only when Google reports it verified.
- If some *other* account already holds the new address, the update is skipped
  and a warning logged. The sign-in still succeeds — `google_id` identifies them
  regardless, and locking someone out over another row's data would be worse.
  (Realistic on school/Workspace domains, where addresses get reassigned.)
- A name is only backfilled when ours is empty or the `"GrowBuddy User"`
  placeholder, so a name the user chose in our app is never overwritten.

### Getting the client IDs

`GOOGLE_CLIENT_IDS` is empty by default, and `POST /auth/google` answers with a
clear "not configured" 401 until it is set. To fill it in:

1. In [Google Cloud Console](https://console.cloud.google.com/), create a
   project and open **APIs & Services → Credentials**.
2. Configure the **OAuth consent screen** (External, add yourself as a test
   user while developing).
3. Create an **OAuth client ID → Android**: package name
   `com.example.grow_buddy_app`, plus the debug SHA-1 from
   `cd android && ./gradlew signingReport`.
4. Create a second **OAuth client ID → Web application**. This one is what the
   app passes as `serverClientId`, and its value is what ends up in the token's
   `aud` claim.
5. Put both IDs in `.env`, comma-separated:
   `GOOGLE_CLIENT_IDS=123-web.apps.googleusercontent.com,456-android.apps.googleusercontent.com`

A token is accepted only if its `aud` matches one of these, which is what stops
a token minted for a different app being replayed against this backend.

## How OTP works right now

There is no SMS provider wired up yet. While `OTP_DEBUG_RETURN=true`, the code
is returned in the `debug_otp` field and printed to the server log, so phone
login is fully testable. The app surfaces it in a SnackBar as `(dev code:
123456)`.

Codes are stored hashed, expire after 5 minutes, allow 5 wrong attempts, are
single-use, and requesting a new one is rate-limited to once per 30 seconds.

To go live, replace the `# TODO: send code over SMS` line in
[app/routers/auth.py](app/routers/auth.py) with an MSG91/Twilio call and set
`OTP_DEBUG_RETURN=false`.

### Changing a contact you already have

`PATCH /me` fills in a **missing** email or phone. **Replacing** one goes
through `/me/contact/request` and `/me/contact/verify` instead, and the typed
value waits in `contact_change_codes` until the code comes back — `users.email`
and `users.phone` are not touched before that.

This is not caution for its own sake. `users.phone` is what `/otp/verify` and
`/login` look an account up by, so writing an unproven number there makes it the
number the person has to log in with, while `is_phone_verified = false` records,
too late, that nobody ever proved they could receive anything at it. One typo
and the account is unreachable by the flow the app opens on.

The codes are the same shape as an OTP — hashed, 5 minutes, 5 attempts,
single-use, one per 30 seconds — but a **separate table**, for the reason
`password_reset_codes` is separate: an `OtpCode` is redeemable for a login token
and resolves the account from the number in the request, so a code that could be
either kind could be spent creating a second account for the new number. The
email half logs its code exactly as SMS does; there is no email provider wired
up either.

## Connecting the app

`kApiBaseUrl` in `lib/GB_Utilities/GB_Common_Utilities/GB_Constants.dart` is the
single place to change:

| Where the app runs | Value |
| --- | --- |
| Android emulator | `http://10.0.2.2:8080` |
| iOS simulator / Windows desktop | `http://127.0.0.1:8080` |
| Physical phone on the same Wi-Fi | `http://<this-machine-LAN-IP>:8080` |

This machine's LAN IP is currently `192.168.0.157`, which is what is committed.
It can change when the router reassigns leases — recheck with `ipconfig`.

The committed value is a compile-time default. Override it without touching
the file:

```powershell
flutter run --dart-define=GB_API_BASE_URL=http://10.0.2.2:8080
```

Android 9+ blocks plain HTTP, so
`android/app/src/debug/res/xml/network_security_config.xml` allow-lists the dev
hosts. **If your LAN IP changes, update it in both that file and
`GB_Constants.dart`**, otherwise calls fail with a bare connection error.
That file only applies to debug builds; release builds keep the HTTPS-only
default.

## Reaching it from anywhere (Tailscale)

Every address in the table above is local: the moment the phone leaves the
Wi-Fi, the app cannot see the backend. Tailscale fixes that by giving this
machine a stable name that works from any network — a coffee shop, mobile data,
another city — without port-forwarding the router or exposing anything to the
public internet. Only devices signed into the same tailnet can connect.

One-time setup:

1. **This machine** — install and sign in. `tailscale up` opens a browser.

   ```powershell
   winget install --id Tailscale.Tailscale
   tailscale up
   ```

2. **The phone** — install Tailscale from the Play Store / App Store and sign in
   with the *same account*. It has to stay connected for the app to reach the
   backend.

3. **Enable MagicDNS and HTTPS certificates** at
   <https://login.tailscale.com/admin/dns>. Both are off by default, and
   `tailscale serve` needs them to issue the certificate.

Then, each time you want the backend reachable — start uvicorn as usual, and:

```powershell
powershell -ExecutionPolicy Bypass -File tool\gb_tailscale_serve.ps1
```

That script finds this node's MagicDNS name, checks something is really
listening on 8080, runs `tailscale serve` to front uvicorn with HTTPS, and
prints the `flutter run` line to copy:

```powershell
flutter run --dart-define=GB_API_BASE_URL=https://<machine>.<tailnet>.ts.net
```

Stop serving with `tool\gb_tailscale_serve.ps1 -Off`.

### Why HTTPS rather than the 100.x address

Tailscale also hands out a `100.x.y.z` address that `http://100.x.y.z:8080`
would reach directly, and the traffic is WireGuard-encrypted either way. The
`tailscale serve` route is still the better one here:

- **No cleartext exception.** A plain-HTTP host would need adding to
  `network_security_config.xml`, which is `src/debug` only — so that path can
  never work in a release build. The `.ts.net` certificate is a real Let's
  Encrypt one, which Android trusts out of the box.
- **No port.** `serve` listens on 443, so the URL carries no `:8080`.
- **The name is stable.** The `100.x` address is stable too, but the DNS name
  survives a node being removed and re-added.
- **No firewall rule.** `serve` connects to uvicorn over loopback
  (`127.0.0.1:8080`), so Windows Firewall never sees an inbound connection to
  port 8080. Hitting `http://100.x.y.z:8080` directly would need a rule allowing
  it on the Tailscale interface.

### What this does not change

- **The backend stays in development mode.** `OTP_DEBUG_RETURN=true`, the
  wildcard CORS and a dev `SECRET_KEY` are all still in place. That is fine
  while only your own tailnet devices can connect, and is exactly why this uses
  `tailscale serve` and **not** `tailscale funnel` — funnel would put all of
  that on the public internet. Work through *Before this goes anywhere real*
  below before changing that.
- **`--host 0.0.0.0` is still wanted.** Serve proxies to `127.0.0.1:8080`, so
  binding only to localhost would work for the Tailscale path — but it would
  break the LAN path at the same time. Leave it as it is.
- **Nothing is auto-started.** `serve --bg` survives a reboot as a Tailscale
  config, but uvicorn does not. The backend still has to be running.

## Before this goes anywhere real

- Set a fixed `SECRET_KEY` in `.env`. Without one a fresh key is generated at
  every startup, so all existing tokens stop working on restart.
- Set `OTP_DEBUG_RETURN=false` and send codes over SMS instead.
- Switch `DATABASE_URL` to PostgreSQL (uncomment `psycopg` in
  `requirements.txt`). SQLite is the zero-setup default for development.
- ~~Replace `Base.metadata.create_all` with Alembic migrations.~~ **Done
  2026-09-17** — see Migrations above. Remember that deploying now means
  running `alembic upgrade head` as a step of the deploy, because the server
  deliberately will not do it for you.
- **Gate who can become a principal.** `POST /auth/signup` currently accepts
  `account_type = 2` from anyone, so the admin role is self-service. Fine on a
  tailnet-only dev backend; before this is reachable by real users it needs an
  invite code, a first-principal-only rule, or creation by an existing
  principal.
- Narrow the CORS `allow_origins=["*"]` in `app/main.py` to real origins.
- Move the token out of the in-memory `gLoginToken` global in the app and into
  `flutter_secure_storage`.

## Layout

```
backend/
├── app/
│   ├── main.py         FastAPI app, CORS, error shaping, health check
│   ├── config.py       settings from .env
│   ├── database.py     engine + session
│   ├── models.py       User, OtpCode
│   ├── schemas.py      request/response contracts + validation
│   ├── security.py     bcrypt hashing, JWT, OTP generation
│   ├── deps.py         get_current_user (Bearer auth)
│   ├── timeutils.py    naive-UTC helper shared by models and JWT
│   └── routers/auth.py the endpoints
└── tests/              pytest suite over an in-memory database
```
