# Reaching the Backend From Anywhere — Tailscale

How the GrowBuddy app talks to the FastAPI backend when the phone is not on the
same Wi-Fi. Setup is once; after that the daily routine is one command.

_Verified working on this machine: 2026-09-13. Every value below is the real
one, not a placeholder._

## This Machine's Values

| | |
| --- | --- |
| Machine name | `laptop-9iu37vee` |
| Tailnet | `tailee091f.ts.net` |
| **Base URL** | **`https://laptop-9iu37vee.tailee091f.ts.net`** |
| Tailscale IP | `100.85.148.90` |
| Phone on the tailnet | `oneplus-13s` (`100.98.136.11`, Android) |

The machine name comes from the Windows hostname `LAPTOP-9IU37VEE`, lowercased.
The tailnet half was assigned by Tailscale at first sign-in and could not have
been known in advance. Both are renameable in the admin console; the URL follows
a rename.

## Why This Exists

`kApiBaseUrl` used to be a LAN address, so the app could only reach the backend
while the phone sat on the same Wi-Fi. Tailscale is a WireGuard mesh: it gives
this laptop a stable name that resolves from any network — mobile data, another
building, a different city — with no port-forwarding on the router and nothing
published to the public internet. Only devices signed into the tailnet can
connect.

```
Phone                          LAPTOP-9IU37VEE
+-------------+                +----------------------------------------+
| GrowBuddy   |   WireGuard    |  tailscale serve      uvicorn          |
| app         |===============>|  HTTPS :443      -->  127.0.0.1:8080   |
| + Tailscale |   any network  |  Let's Encrypt        FastAPI/Postgres |
+-------------+                +----------------------------------------+
```

The last hop is loopback, so Windows Firewall never sees an inbound connection
to 8080 and there is no rule to add.

### Why HTTPS rather than the 100.x address

Tailscale also hands out `100.85.148.90`, and `http://100.85.148.90:8080` would
reach the backend directly — the traffic is WireGuard-encrypted either way.
`tailscale serve` is still the better route:

- **No cleartext exception.** A plain-HTTP host needs an entry in
  `android/app/src/debug/res/xml/network_security_config.xml`, which is
  `src/debug` only — so that path can never work in a release build. The
  `.ts.net` certificate is a real Let's Encrypt one that Android trusts out of
  the box.
- **No port.** `serve` listens on 443, so the URL carries no `:8080`.
- **No firewall rule**, per the loopback point above.

## One-Time Setup

### 1. On the laptop

```powershell
winget install --id Tailscale.Tailscale
tailscale up
```

`tailscale up` opens a browser. **Whichever account is used here is the account
the phone must use too** — a Google login and a GitHub login produce two
separate tailnets that cannot see each other. Confirm with `tailscale status`;
this machine should be listed with its `100.x` address.

### 2. In the admin console

Both of these are off by default and **both are required** — `tailscale serve`
cannot get a certificate without them. This is the step that gets skipped, and
the failure it causes does not mention either one.

At <https://login.tailscale.com/admin/dns>:

- **MagicDNS** — gives the machine a name instead of only a number.
- **HTTPS Certificates** — the toggle just below it.

Then at <https://login.tailscale.com/admin/machines>, open the `···` menu on
this laptop and choose **Disable key expiry**. Node keys otherwise expire after
180 days, and when this one does the backend simply becomes unreachable with no
obvious cause.

### 3. On the phone

Install Tailscale from the Play Store, sign in with **the same account**, and
turn the toggle on. Android asks to add a VPN configuration; a key icon shows in
the status bar while it is connected. The phone has to stay connected — if the
toggle is off, every request fails with the app's "Can't reach the server"
message.

## Each Session

Start the backend as usual, from `backend/`:

```powershell
.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
```

Keep `--host 0.0.0.0`. Tailscale itself only needs loopback, but narrowing to
`127.0.0.1` would break the plain LAN path at the same time.

Then, from the project root:

```powershell
powershell -ExecutionPolicy Bypass -File tool\gb_tailscale_serve.ps1
```

The script finds this node's real name, checks something is actually listening
on 8080, runs `tailscale serve`, and prints the finished URL — so the
`<machine>` / `<tailnet>` placeholders never have to be filled in by hand:

```
Node    : laptop-9iu37vee.tailee091f.ts.net
Address : 100.85.148.90

Backend is on the tailnet:
  https://laptop-9iu37vee.tailee091f.ts.net/health
  https://laptop-9iu37vee.tailee091f.ts.net/docs

Run the app against it (phone must be signed into the same tailnet):
  flutter run --dart-define=GB_API_BASE_URL=https://laptop-9iu37vee.tailee091f.ts.net
```

`tool\gb_tailscale_serve.ps1 -Off` takes it back off the tailnet.

### Check it before touching Flutter

Open `https://laptop-9iu37vee.tailee091f.ts.net/health` in the laptop's browser,
then **in the phone's browser**. The second test is the one that matters: it
separates a Tailscale problem from a Flutter problem in ten seconds. Both should
return `{"status":"ok"}` with no certificate warning.

**The first HTTPS request takes 10–30 seconds** while the certificate is issued
— measured at 24.7s here on 2026-09-13. Every request after that was 20–60ms. A
slow first load is not a fault.

If the laptop's browser works and the phone's does not, the phone is signed into
a different account or its Tailscale toggle is off. Nothing further down works
until that passes.

## Running the App Against It

```powershell
flutter run --dart-define=GB_API_BASE_URL=https://laptop-9iu37vee.tailee091f.ts.net
```

No port — `serve` listens on 443. This overrides the `kApiBaseUrl` default in
`GB_Constants.dart` without editing the file, so the committed LAN address stays
put for anyone testing on Wi-Fi.

**A `--dart-define` is compiled in.** Changing it needs a full stop and re-run;
hot reload and hot restart both keep the old value, which looks exactly like the
flag being ignored.

Release builds take the same flag, and unlike every other address in this
project it works there, because it is genuine HTTPS:

```powershell
flutter build apk --dart-define=GB_API_BASE_URL=https://laptop-9iu37vee.tailee091f.ts.net
```

Anyone given that APK needs Tailscale on their phone and an invite to the
tailnet.

## Wi-Fi and Mobile Data Both Work

Nothing about the LAN path was removed. `tailscale serve` proxies to
`127.0.0.1:8080` and uvicorn is still bound to `0.0.0.0:8080`, so the backend
answers on every route at once — verified 2026-09-13:

| URL | Reachable from |
| --- | --- |
| `https://laptop-9iu37vee.tailee091f.ts.net` | any network, tailnet devices only |
| `http://192.168.0.157:8080` | same Wi-Fi only |
| `http://127.0.0.1:8080` | this laptop only |

What is *not* simultaneous is the app: one build carries one compiled-in URL.
The Tailscale URL is the one to use, because it covers both cases — when the
phone and laptop are on the same Wi-Fi, Tailscale negotiates a direct
peer-to-peer connection over that LAN rather than routing out to the internet,
so it is not slower than the plain LAN address. A build with no `--dart-define`
still falls back to `192.168.0.157` and still works on Wi-Fi.

## What Survives a Reboot

| | | |
| --- | --- | --- |
| Tailscale sign-in | survives | Windows service, starts on boot |
| `tailscale serve` config | survives | `--bg` stores it in the tailnet config |
| PostgreSQL | survives | `postgresql-x64-18` service, starts on boot |
| **uvicorn** | **start it** | nothing supervises it — the one thing to redo |
| The app's baked URL | survives | compiled in; rebuild only to change it |

So after a restart: start uvicorn, and it is up. Re-running the helper script is
harmless if in doubt. `tailscale serve status` shows what is currently
published.

## When It Doesn't Work

| Symptom | Cause and fix |
| --- | --- |
| Script says *Tailscale is not installed* | Not installed, or in an unusual location. Reopen the terminal after installing. |
| Script says *This node has no MagicDNS name* | MagicDNS is off. |
| `tailscale serve` fails mentioning certificates | HTTPS Certificates is off — the second toggle, easy to miss. |
| Script warns *nothing is listening on port 8080* | uvicorn is not running, or is on another port. |
| **`[WinError 10013]` on starting uvicorn** | **A uvicorn is already running.** Windows reports a duplicate bind on `0.0.0.0` as 10013 ("access permissions") rather than the 10048 you would expect, so it reads like a firewall or privilege problem and is not one. Check with `Get-NetTCPConnection -LocalPort 8080 -State Listen`; the backend is probably already healthy. |
| Laptop browser loads `/health`, phone does not | Phone's VPN toggle is off, or it is on a different account. |
| Browser works but the app says *"Can't reach the server"* | The URL was not compiled in — hot reload instead of a re-run, or a mistyped flag. It is `GB_API_BASE_URL` exactly. |
| Worked for months, then stopped | The node key expired. `tailscale up` again, then disable key expiry. |
| Unreachable while out of the house | The laptop slept. Tailscale cannot wake it. |

## What Is and Isn't Exposed

This uses `tailscale serve`, which publishes only to the tailnet. Its sibling
`tailscale funnel` publishes to the public internet, and the distinction is
doing real work here: the backend is still in development mode, with
`OTP_DEBUG_RETURN=true` handing out login codes in API responses,
`allow_origins=["*"]`, and a development `SECRET_KEY`.

That is fine while only signed-in devices can connect. **Before running
`funnel`, or putting this anywhere public, work through _Before this goes
anywhere real_ in `backend/README.md`.**

## Related

- `tool/gb_tailscale_serve.ps1` — the helper script
- `backend/README.md` — the same setup in brief, plus the production checklist
- `docs/PROJECT.md` — _Notes that bite_ carries the short version
