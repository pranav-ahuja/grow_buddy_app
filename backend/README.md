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

26 tests cover the sign-up, login, OTP, and Google flows against an in-memory
database. The Google tests stub out token verification, so they never call
Google and need no credentials.

> **Schema changed?** `create_all` only creates missing tables, it never alters
> existing ones. After a model change during development, stop the server and
> delete `growbuddy.db` so it is rebuilt. Alembic replaces this ritual once
> there is data worth keeping.

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

`identifier` is either an email address or a phone number — the server works out
which, so the app's single "Email id / Phone Number" field maps straight
through. `account_type` is `0` for teacher and `1` for student, matching
`GB_Constants.dart`.

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

Android 9+ blocks plain HTTP, so
`android/app/src/debug/res/xml/network_security_config.xml` allow-lists the dev
hosts. **If your LAN IP changes, update it in both that file and
`GB_Constants.dart`**, otherwise calls fail with a bare connection error.
That file only applies to debug builds; release builds keep the HTTPS-only
default.

## Before this goes anywhere real

- Set a fixed `SECRET_KEY` in `.env`. Without one a fresh key is generated at
  every startup, so all existing tokens stop working on restart.
- Set `OTP_DEBUG_RETURN=false` and send codes over SMS instead.
- Switch `DATABASE_URL` to PostgreSQL (uncomment `psycopg` in
  `requirements.txt`). SQLite is the zero-setup default for development.
- Replace `Base.metadata.create_all` in `app/main.py` with Alembic migrations —
  the current call creates missing tables but never alters existing ones, so
  column changes will not apply to a database that already has data.
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
