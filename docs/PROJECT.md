# GrowBuddy — Project Notes

School-management app (mobile + web planned) for GrowBuddy school. Flutter front
end, FastAPI back end.

_Last reviewed against the code: 2026-09-20. Phases 5 and 6 were committed on
2026-09-26, and this file is that commit's account of them._

## Start Here — Reading This Cold

This file is the project's memory. A new session, or a new person, should read
it before touching anything: it carries what the code cannot — the state of this
machine, the traps that have already cost hours, and what is genuinely finished
versus merely present.

Where things stand:

- The app builds and runs. `flutter devices` sees the phone (`223170c0`), an
  emulator, Windows, Chrome and Edge.
- The backend runs on **PostgreSQL 18** and its **222 tests pass**. Its schema
  is Alembic's as of 2026-09-17, at revision `0006`.
- The six-phase role rebuild is **finished**. The principal is the school's
  **administrator**: they create and delete classes, register and remove
  pupils, and choose who teaches what. A teacher doing any of those four
  **asks first** — see The Role Rebuild, phase 5.
- The Flutter suite is red and was already red: **74 of 176 fail**, and 62
  analyzer errors stop six files compiling at all. **10 of those errors are
  new** and mechanical; the rest is drift that predates this work. See
  Verification — the suite is Tastu's.
- Password reset, events, the six class features, grades, messages and the
  diary are still unbuilt — see Not Built Yet.

Two commands cover most work:

```powershell
# backend (from backend/)
.venvScriptspython.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload
# app
C:\src\flutter\bin\flutter.bat run
```

To reach it from off the LAN — mobile data, anywhere — see
docs/Tailscale_porting.md. Start the backend first, then:

```powershell
powershell -ExecutionPolicy Bypass -File tool\gb_tailscale_serve.ps1
```

## Environment — Traps That Have Already Bitten

Machine-level, not code-level. Each of these cost real time on 2026-09-13.

- **Never `git pull` inside `C:\src\flutter`.** The SDK is a clone reset to the
  3.32.2 release point, not a branch tip, so a pull tries to merge ~6800 commits
  and conflicts across ~80 files. That leaves `<<<<<<< HEAD` markers inside
  `bin/internal/engine.version`, which Flutter reads at startup — every command
  then dies with `<< was unexpected at this time`. Recover with
  `git -C C:\src\flutter merge --abort`; it loses nothing, because the 47
  commits that checkout holds are upstream Flutter releases, not ours.
- **Quick Heal is currently switched off, and must stay that way.** Its
  Behaviour Detection System quarantined `bin/flutter.bat` and
  `bin/internal/update_engine_version.ps1` into
  `QUARANTINE\BDSQUAR\`, which is what produced the original
  `CreateProcess error=2 ... flutter.bat` failure and an empty device list. Its
  "Exclude Files & Folders" list does **not** govern BDS — five attempts at
  excluding the SDK all failed. It was also killing detached background
  processes and eating their log files, which made the backend die instantly
  when started with `Start-Process`. If files start vanishing again, check
  `Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct`:
  `productState` is `0x041000` when real-time protection is on, `0x042000` when
  off. Beware a delayed sweep — a file reads as present for several seconds
  before it is taken, so an immediate existence check gives a false pass.
- **Android Studio shows "No device connected" while `flutter run` works.** The
  IDE spawns `flutter daemon` once per project open and never retries. If that
  daemon was started while the SDK was broken, the device list stays empty
  forever. Restart Android Studio — File → Invalidate Caches / Restart is the
  safer form after any SDK change.
- **Android builds need JDK 17** (`C:\Program Files\Java\jdk-17`, set via
  `flutter config --jdk-dir`). Android Studio bundles a Java 25 JBR, and Gradle
  8.3 refuses it with "Unsupported class file major version 69". An Android
  Studio upgrade can silently reset this — check `flutter doctor -v`.
- **Drive `adb` from PowerShell, not Git Bash.** Git Bash mangles `/sdcard`
  paths and truncates screenshots pulled off the device.
- **PostgreSQL** runs as the `postgresql-x64-18` Windows service and starts on
  boot; nothing needs starting by hand. `pg_hba.conf` is `scram-sha-256` for
  local and 127.0.0.1, so `psql` always needs a password — there is no trust
  auth to fall back on.

## Stack
- Flutter 3.32.2 (Dart 3.8.1) — targets Android, iOS, Windows today
- Backend: Python 3.12 + FastAPI + SQLAlchemy + PostgreSQL 18, in `backend/` (see `backend/README.md`)
- HTTP client: `http`, wrapped by `lib/GB_Services/` (base URL is `kApiBaseUrl` in `GB_Constants.dart`)
- Session storage: `flutter_secure_storage` (Android Keystore / iOS Keychain)
- Auth: `google_sign_in` ^7.2.0, `pinput` (OTP), `intl_phone_field`
- Class files: `excel` (read/write the .xlsx archive) + `file_picker` (system Save/Open dialogs)
- Student photo and profile picture: `image_picker`
- UI helpers: `carousel_slider`, `dropdown_button2`, `iconify_flutter`,
  `colorful_iconify_flutter`, `another_flutter_splash_screen`

## Folder Layout
```
lib/
├── main.dart                              splash → GB_SessionGate
├── GB_Pages/
│   ├── GB_Startup/
│   │   ├── GB_OnboardingPage.dart         carousel + welcome + FAB → login/signup dialog
│   │   └── GB_SessionGate.dart            resumes a stored session, or starts at onboarding
│   ├── GB_LoginSignUp/
│   │   ├── GB_Login.dart                  email/phone + password
│   │   ├── GB_SignUp.dart                 name / identifier / password / role
│   │   ├── GB_MobileLogin.dart            phone-number entry
│   │   ├── GB_Verify.dart                 OTP entry (Pinput)
│   │   ├── GB_ForgotPassword.dart         reset step 1 — email  (UI only, no backend)
│   │   ├── GB_VerifyEmail.dart            reset step 2 — code   (UI only, no backend)
│   │   ├── GB_CreateNewPassword.dart      reset step 3 — new pw (UI only, no backend)
│   │   └── GB_CompleteProfile.dart        asks for the missing role / email / phone → PATCH /me
│   ├── GB_HomeScreen/
│   │   ├── GB_Dashboard.dart              reads the role, shows the matching dashboard
│   │   ├── GB_HomeDashboard.dart          the shared dashboard body + GB_DashboardPermissions
│   │   ├── GB_PrincipalDashboard.dart     every class in the school; admin powers; Fee tab
│   │   ├── GB_TeacherDashboard.dart       classes they take; the same four acts, as requests
│   │   ├── GB_StudentDashboard.dart       the parent's portal: child picker, class, attendance
│   │   ├── GB_NotificationsScreen.dart    the notification tab, and the principal's approvals
│   │   ├── GB_NotificationStore.dart      this device's copy of it, and the bell's badge
│   │   ├── GB_HomeAppBar.dart             notification bell + profile menu
│   │   ├── GB_HomeModels.dart             GB_Event
│   │   ├── GB_HomeWidgets.dart            event card, class tile, add-class tile, carousel dots
│   │   ├── GB_Profile.dart                the signed-in user + profile picture
│   │   └── GB_Settings.dart               placeholder + the app's only logout
│   └── GB_Classes/
│       ├── GB_ClassScreen.dart            one class: features row + students row
│       ├── GB_ClassStore.dart             this device's copy of the teacher's classes
│       ├── GB_StudentStore.dart           …and of their students
│       ├── GB_ClassModels.dart            GB_ClassInfo, GB_Student, GB_StudentContact, GB_ClassPalette, GB_ClassFeature
│       ├── GB_ClassWidgets.dart           feature card, student card, colour swatches
│       ├── GB_ClassDialogs.dart           edit-class and confirm-delete dialogs
│       ├── GB_AddClassSheet.dart          add a class, or restore one from a class file
│       ├── GB_AddTeacherSheet.dart        the principal's multi-pick "who teaches this class"
│       ├── GB_RegisterStudentSheet.dart   the register-student form
│       ├── GB_StudentFormFields.dart      that form's field widgets
│       ├── GB_ClassArchive.dart           pure encode/decode of the .xlsx class file
│       └── GB_ClassArchiveFile.dart       the platform Save/Open dialogs for it
├── GB_Services/
│   ├── GB_ApiClient.dart                  HTTP + error/timeout handling, GB_ApiException
│   ├── GB_AuthApi.dart                    auth endpoints + GB_User / GB_AuthResult
│   ├── GB_ClassApi.dart                   classes + students endpoints and their JSON mapping
│   ├── GB_GoogleSignIn.dart               the plugin wrapper that yields an ID token
│   ├── GB_ApprovalApi.dart                the approval queue and the notification tab
│   ├── GB_ApprovalModels.dart             GB_ChangeRequest, GB_Notification, GB_NotificationFeed
│   ├── GB_GuardianApi.dart                what a parent's account may read
│   ├── GB_TeacherApi.dart                 the teacher directory, for the principal's pickers
│   ├── GB_ProfilePhotoStore.dart          the profile picture's path, per user, device-local
│   └── GB_SessionStore.dart               token + user in secure storage
└── GB_Utilities/
    ├── GB_Common_Utilities/
    │   ├── GB_AuthFlow.dart               gRouteAfterAuth / gSignOut / gSignInWithGoogle / gShowSnack
    │   ├── GB_Globals.dart                gLoginToken, gCurrentUser, session set/restore/clear
    │   ├── GB_Constants.dart              colours, sizes, URLs, account types, Google client IDs
    │   └── …                              shared widgets, functions, dropdown, buttons
    ├── GB_Utilities_Onboarding/           carousel + login-signup popup helpers
    └── GB_FloatingActionButton.dart       shared FAB
assets/images/                              PNGs used across screens (incl. features_of_class/)
backend/                                    FastAPI service — see backend/README.md
backend/alembic/                            migrations; Alembic owns the schema
backend/app/access.py                       who may do what — shared by every router
backend/app/school.py                       the four acts, callable directly or on approval
backend/app/approvals.py                    the request queue: raising, granting, refusing
backend/app/notifications.py                writing notifications, and the query that reads them
testcases/                                  unit + widget suites and their runner
integration_test/                           on-device end-to-end tests
tool/gb_make_app_icon.dart                  squares the logo for flutter_launcher_icons
tool/gb_tailscale_serve.ps1                 puts the backend on the tailnet over HTTPS
```

## Current Flow (implemented)
```
Splash → GB_SessionGate ─┬─ no token ──────────────→ Onboarding → GB_MobileLogin → Verify (OTP)  [SignUp, Login, Google alongside]
                         ├─ token + profile gaps ──→ GB_CompleteProfile ──┐
                         └─ token + complete ──────→ GB_Dashboard ←───────┘
                                                          ├─ teacher → GB_TeacherDashboard → GB_ClassScreen
                                                          └─ student → GB_StudentDashboard (placeholder)
```

`GB_SessionGate` calls `GET /auth/me` to check the stored JWT. A 401/403 clears
the session; **any other failure falls back to the cached user**, so a dropped
network does not sign the teacher out.

**Phone + OTP is the default login page.** The onboarding dialog's "Login"
button and the post-sign-out route in `gSignOut` both land on
`GB_MobileLogin`, not `GB_Login`. Because it is now the default, that screen
carries an icon row on to Google and to the email/password form — without
it a Google or password account would have no route back, since the dialog
no longer opens `GB_Login` directly. `GB_Login` itself is unchanged.

`GB_Verify` counts the resend button down from `kOtpResendCooldownSeconds`,
which mirrors the backend's `OTP_RESEND_COOLDOWN_SECONDS` (30). Keep the two
in step: if the button goes live first, the user earns a rejection they did
nothing to cause.

Every auth screen — password, OTP, and Google alike — funnels through
`gRouteAfterAuth` in `GB_AuthFlow.dart`, so the post-login rule lives in one
place. That rule is `needsProfileCompletion` (no role, or no email, or no
phone), **not** `isNewUser`: someone who abandons the profile screen stops being
new but is still incomplete. `isNewUser` only picks the wording.

## What Works Today
- **Auth**: email/phone + password, phone + OTP, and Google Sign-In, all wired
  end to end. Sessions survive a kill and relaunch.
- **Profile completion**: `GB_CompleteProfile` asks only for what is actually
  missing and sends it to `PATCH /auth/me`.
- **Profile menu**: the home bar's profile icon offers **Profile** and
  **Settings**. `GB_Profile` shows the cached `gCurrentUser` — avatar, name,
  role pill, and email/phone/role rows, with a missing contact marked "Not
  added yet" rather than left blank. It makes no request of its own, so it
  works offline. The **user id is deliberately not shown**: it is a database
  key, and putting `U_000001` on a profile invites it into a support
  conversation as though it meant something to the teacher.
- **Profile picture**: tapping the avatar offers camera / gallery / remove,
  through `image_picker` exactly as the register-student sheet does. With none
  set it draws the user's initials, or a person icon when the name yields none
  (the "GrowBuddy User" placeholder would otherwise show a misleading "G").
  **Stored on the device only** — `GB_ProfilePhotoStore`, keyed by user id, in
  the same secure storage as the session. There is no `users.photo_path`
  column to sync it to, and adding one needs Alembic (see Backend), so a
  teacher on a second phone sees initials again. A path whose file has since
  gone is forgotten and falls back to initials rather than drawing a broken
  box. Sign-out forgets the in-memory copy but keeps what is on disk, so the
  next account gets a blank avatar and the original owner gets theirs back.
  **Logout lives at the bottom of Settings**, behind `gConfirmAndSignOut`'s
  dialog, and nowhere else. It was a second entry in that popup until
  2026-09-17, where a mis-aimed tap on a 24px icon's menu ended the session
  outright — cheap to trigger, and expensive to undo when getting back in means
  waiting on an OTP mid-lesson. `gSignOut` is still the contract; the
  confirmation wraps it so a future second Logout inherits the guard.
- **Teacher dashboard**: the class list from the server, with a live student
  count per tile; reloads on open, on resume, and on pull-to-refresh; clears its
  stores on sign-out.
- **Classes**: add (with a 9-slot colour picker), rename, recolour, delete, and
  open. Names are unique per teacher, case-insensitively, checked on both sides.
- **Class files**: deleting a class first writes an `.xlsx` archive through the
  system Save dialog — and only deletes if that file was actually saved. Adding
  a class can restore one back, students and their original `ST_` ids included,
  in a single server transaction.
- **Students**: the register-student form (with optional photo), server-assigned
  ids, alphabetical roll numbers, and a duplicate-child rule.
- **Tests**: `testcases/` (unit + widget, no device or server needed) and
  `integration_test/` (real device against a real backend). See
  `testcases/README.md` — one command, one table of results.

## The Role Rebuild — In Progress

A six-phase change, agreed 2026-09-17: the app grows a **principal** (admin)
role, the dashboard currently built moves from the teacher to the principal,
teachers lose the fee view and gain attendance/grades/events, and students get
a real portal. Delivered one phase at a time, each reviewed before the next.

**Phase 1 — done (2026-09-17).** Alembic, and the principal role end to end.

- `account_type` is now `0` teacher, `1` student, **`2` principal**, mirrored
  in `backend/app/models.py` and `GB_Constants.dart`. Append-only: the existing
  numbers are written into live rows, so they are never renumbered.
- Migration `0002` widens the `ck_users_role` CHECK. **No account was
  promoted** — `U_000001` is still a teacher, `U_000002` still a student, by
  decision. The first principal is a deliberate sign-up.
- The three role pickers (sign-up dropdown, `DropDownTextFieldMenu`,
  `GB_CompleteProfile`'s icon row) now all read `kAccountTypeOptions` in
  `GB_Constants.dart`. They used to list the roles separately, so a new role
  meant three edits and a role missing from one screen was invisible.
- `GB_Dashboard` routes principal → `GB_TeacherDashboard` **for now**, so the
  role is usable the moment it exists rather than landing a new principal on
  the student placeholder. Phase 2 splits the two screens.
- A principal is **not** a teacher: they get no `TR_` row, and the classes
  router still refuses them with 403. Pinned by
  `backend/tests/test_principal_role.py` — the tempting shortcut was to let
  `_current_teacher` accept principals, which would have handed every
  principal a teacher's class-owning identity.

**Phase 2 — done (2026-09-18).** The dashboard split, and the principal's data.

- **The screen from Figma `360-39838` is the principal's now**
  (`GB_PrincipalDashboard`). It is a whole-school view, which is what the
  admin needs.
- `GB_HomeDashboard` holds the shared body; `GB_TeacherDashboard` and
  `GB_PrincipalDashboard` are thin wrappers supplying a
  `GB_DashboardPermissions`. One widget configured twice rather than two
  copies of ~450 lines that would drift the first time either was touched.
- **The teacher has no Fee tab** — absent, not present-and-refusing. A tab
  whose only job is to say no is worse than one never offered. Their bar is
  Home / Attendance / Message; the principal's keeps Fee.
- **The principal cannot add or delete a class**, in the app (no "Add a class"
  tile, no bin icon) *and* on the server (403 on POST/PATCH/DELETE
  `/classes`). A class belongs to the teacher who owns it. Assigning teachers
  to classes is a different act on an existing class, and comes later.
- **Read scope is decided on the server, by role.** The same `GET /classes`
  and `GET /students` return one teacher's to a teacher and the whole school's
  to a principal — `_reader_scope()` in `classes.py` returns the teacher to
  filter by, or **None meaning school-wide**. The app does no filtering of its
  own, so it cannot disagree with who the server thinks you are.
- `ClassOut` gained `teacher_id` and `teacher_name`, and tiles on the
  principal's list read "Asha Rao · 3 students". Two teachers each having a
  "Nursery" is normal, so a school-wide list without the owner's name is two
  identical rows.
- A principal may **register a student into any class**; a teacher only into
  their own. Another teacher's class reads 404, not 403, so the endpoint
  cannot be used to discover which ids exist.
- Covered by `backend/tests/test_principal_scope.py`. Note that phase 2
  deliberately *changed* a phase-1 test: `test_a_principal_is_not_a_teacher`
  asserted 403 on `GET /classes`, which is now 200 — rewritten as
  `test_a_principal_can_read_classes_but_owns_none`.

**Phase 3 — done (2026-09-18), backend only.** `subjects` and `attendance`.

Migration `0003`. **No UI yet** — the class screen's Attendance card still says
"coming soon"; wiring it is a later phase. What exists is the data and the API.

- **`subjects`** — `S_000001`, uuid, name, unique on `lower(name)` so there is
  one "Mathematics" per school. Note the prefix is `S` while a student is `ST`.
  They cannot collide (`codes.number_in_code` matches the prefix exactly, so
  `ST_000001` is not a subject id) but they do read alike; prefer the full word
  in anything a person sees.
- **The two-way check on adding a subject.** The principal's `POST /subjects`
  is `approved` at once; a teacher's is `pending` and does nothing until
  `POST /subjects/{id}/approve`. The request body is **identical** either way,
  so a teacher cannot ask for approval — there is no field to ask with, which
  is a stronger guarantee than checking one. A pending subject also blocks a
  duplicate, or the principal would get two identical rows to approve.
- A teacher's subject list shows approved subjects **plus their own
  proposals** — someone else's unapproved idea is not yet a fact about the
  school. The principal sees everything.
- **`attendance`** — `student_id`, `class_id`, `teacher_id`, `date`, `status`
  P/A, on an integer key because nobody quotes an attendance row.
  `uq_attendance_student_date` is unique, so **re-posting a day updates rather
  than duplicating**: a teacher fixing a child they marked absent by mistake is
  the normal case, not an error.
- A register is **one class, one day, one request**. Thirty pupils one request
  at a time is thirty chances to fail halfway, and a half-marked day does not
  read as "incomplete" later — it reads as "the rest were absent".
- `class_id` is stored even though a student already has one: it records the
  class the mark was taken in, so moving a pupil later cannot rewrite where
  they were last term.
- **Teachers mark; the principal only reads.** Attendance is a first-hand
  observation, and an admin recording one they did not make is how a register
  stops being evidence.
- **`proposed_by_teacher_id` and `attendance.teacher_id` are `ON DELETE SET
  NULL`** — the only non-cascades in the schema. A teacher leaving must not
  take the school's subject list or attendance history with them.
- `GET /attendance` requires `class_id` or `student_id`. Without either, a
  principal would get every mark in the school — a request nobody means to
  make.
- The role checks moved to **`app/access.py`**. They were private helpers in
  the classes router; three routers asking the same questions is how one copy
  ends up subtly wider than the others.
- 32 tests in `test_subjects.py` and `test_attendance.py`, plus a live
  PostgreSQL probe for the expression index and CHECK constraints, which SQLite
  enforces differently.

**Phase 4 — done (2026-09-18), backend only.** The teacher record.

Migration `0004`. **No UI yet** — the sign-up step and the profile form are
still to build on these endpoints.

- **`teachers` gained** `date_of_birth`, `highest_qualification`, `address`,
  `relationship_status`, `aadhaar_number`, `emergency_contact_name`,
  `emergency_contact_phone`, `updated_at`. All nullable: these rows predate
  the profile, and a sign-up cannot retroactively collect a date of birth.
  `Teacher.missing_profile_fields` is how the app knows what to still ask for.
- **Name and phone stay on `users`** and are joined in, not copied. A second
  copy is a second thing to keep in step, and the failure mode is a profile
  that disagrees with the account you log in with. A test renames the account
  and checks the profile follows.
- **Aadhaar never leaves the server in full.** `TeacherOut` exposes
  `aadhaar_last4` only — nothing in the app needs the rest, and a response
  carrying complete Aadhaar numbers is a liability in every log and cache it
  passes through. Stored bare (spacing stripped) so "1234 5678 9012" and
  "123456789012" are the same number to the unique index. It is **excluded
  from the completeness check**: a teacher may reasonably refuse it, and
  counting it would nag them forever over something optional.
  > Storing it at all deserves a deliberate decision — UIDAI's rules restrict
  > both storage and display.
- **`teacher_subjects`** — many-to-many, keyed on the pair so the same subject
  cannot be assigned twice. `PUT /teachers/{id}/subjects` sets the **whole
  set**, principal only: a screen of checkboxes knows what it wants the answer
  to be, and making it send a difference is how an unticked subject stays
  assigned. Only **approved** subjects can be assigned — assigning a pending
  one would let a proposal take effect without the approval it is waiting for.
- **`teacher_experience`** — its own table because work experience is a list;
  three sets of columns on `teachers` would cap it at three. `years` is
  `Numeric(4,1)`, so "2.5 years" survives what an integer would have rounded
  away.
- **`PATCH /classes/{id}/teacher`** is the principal's "add a teacher to a
  class". Its own endpoint rather than a field on `PATCH /classes/{id}`,
  because the two have different owners — a teacher renames their own class,
  only the principal hands it to someone else. **Students move with the
  class**, since they belong to the class and not the teacher.
- **`me` is resolved, not routed.** `/teachers/me` as its own path would work
  only while it stayed declared above `/teachers/{teacher_id}`; reordering the
  file would silently make "me" a teacher id and 404 every teacher. One helper
  resolves it instead.
- A teacher reading or editing a colleague gets **404, not 403**, so the
  endpoint cannot be used to enumerate `TR_` ids.
- 38 tests in `test_teacher_profile.py`, plus a PostgreSQL probe.

> **Autogenerate produced two real bugs here, both caught before they ran.**
> It added `updated_at` as NOT NULL with no default — PostgreSQL would have
> refused the statement outright, because `TR_000001` already exists and had
> no value for it. And it emitted `create_unique_constraint(None, ...)` with a
> matching `drop_constraint(None, ...)`, which the downgrade could never look
> up. Fixed by adding the column nullable, backfilling from `created_at`, then
> setting NOT NULL; and by naming the constraint `uq_teachers_aadhaar`. A
> third problem only SQLite shows: it cannot ALTER a constraint into an
> existing table at all, so the whole migration runs in batch mode.
> **Read every generated migration.**

Migration `0005`, plus a real `GB_StudentDashboard` — the first phase with UI
since phase 2.

- **`student_guardians` is the whole phase.** Nothing joined an account to a
  child before it: a `students` row is created by a teacher from a paper form,
  and a `users` row with role `student` was only a role. Without this a parent
  who signs up can see nothing at all.
- **Many-to-many**, because a parent may have two children at the school and a
  child may have two parents who each want the app. That is why the dashboard
  has a child picker rather than one name.
- **Only staff create links.** A parent cannot claim a child by asserting they
  are the parent — get that wrong and a stranger has a child's address,
  attendance and contact numbers. The teacher who registered the pupil, or the
  principal, makes the link, naming the account by **email or phone** (what
  they have in front of them, not a `U_` id).
  - A self-service claim — "my number is on that child's record, link me" — is
    deliberately absent. It needs an approval step, which is phase 5.
  - `matches_registered_contact` on the response says whether that account's
    email or phone is one of the contacts on the pupil's own record. It is
    **not** a permission check: a parent who changed their number since
    registering is an ordinary false negative, and gating on it would lock out
    exactly the families whose details moved on.
- **A parent's scope is the server's**, the same shape as everywhere else:
  `GET /classes` and `GET /students` answer a parent with their own children,
  `GET /attendance` and `/attendance/summary` with their own child's marks.
  The app sends no filter of its own, so it cannot get that filter wrong — and
  what is being filtered is other people's children.
- **Read-only, on purpose.** Editing a child's details and raising a
  class-deletion request both have to notify the teacher and the principal.
  Notifications are phase 5, and shipping the edit without the notice would be
  shipping half a safety mechanism.
- The **class colour stays the teacher's**, as the requirement says: the class
  card is not tappable, carries no menu, and the server refuses a parent's
  PATCH regardless.
- Four of the six things the dashboard is meant to show — grade sheet, teacher
  messages, events, diary — **have no data anywhere in the project**. The
  screen names them under "Coming soon" rather than faking rows: a
  convincing-looking empty grade sheet is worse than an honest gap.
- 26 tests in `test_student_portal.py`, 11 Flutter tests, plus a PostgreSQL
  probe.

**Still owed, on top of phases 3, 4 and 6:** the **UI** for attendance,
subjects, the teacher sign-up step and profile form, and the staff-side screen
for linking a parent to a pupil — that endpoint exists and nothing calls it
yet.

**Known gap, deliberate:** `POST /auth/signup` accepts `account_type = 2` from
anyone, so admin is self-service. Acceptable on a tailnet-only dev backend; it
needs an invite code or a first-principal-only rule before real users. Listed
in `backend/README.md`'s production checklist. Note this matters more now than
it did: an admin account creates and deletes classes and removes pupils
outright.

> **Two real privilege holes, found by the tests that were written to look for
> them.** Widening `readable_class` to include guardians leaked into two places
> it should not have: a linked parent could **register pupils** into their
> child's class, and could **read the whole class register** by passing
> `class_id` — every classmate's name and whether they were absent. Both now
> take `require_staff` first, and a guardian's attendance query is narrowed to
> their own children whatever else they ask for. The lesson worth keeping:
> widening a shared access helper widens every route that calls it, including
> the write paths.

**Phase 5 — done (2026-09-20).** The principal becomes an administrator, a
class gains co-teachers, and the approval queue behind both.

Migration `0006`. The largest single change since phase 1, because the four
acts it moves are the four the app was built around.

- **The principal is the school's admin.** They create classes, delete them,
  register pupils and remove them, all outright. Phase 2 refused them the
  first two on the reasoning that a class belongs to the teacher who owns it;
  that reasoning was overturned by decision, and `test_principal_scope.py`'s
  `test_principal_can_rename_and_delete_any_class` is the phase-2 test
  rewritten to say so.
  - The useful half of it survives in the schema. A principal still gets no
    `TR_` row, so a class they create is filed under the teacher they pick or
    under **nobody** — never under the principal. `require_teacher` still
    refuses them, and its docstring now says what that does and does not mean.
- **A teacher asks.** The same four acts, from a teacher, produce a
  `change_requests` row and **change nothing else at all**. No greyed-out
  tile, no provisional pupil, no count that includes something unagreed. Their
  dashboard after asking looks exactly as it did before, and the request is
  visible in one place — the notification screen's "Waiting for the
  principal".
  - Renaming and recolouring a class are **not** on the list, deliberately.
    They are reversible in one tap and destroy nothing, and a queue filled
    with colour changes is a queue the principal stops reading — which is
    what would make the deletions in it dangerous.
- **`classes.teacher_id` is nullable now.** An unassigned class is one the
  principal made in August before anyone was given their year. It is a real
  class: it appears on the school's dashboard, holds its name against
  duplicates, and waits. The duplicate-name check compares a null owner with
  `IS NULL` on purpose — `=` against NULL is never true, which would have let
  two unassigned "Nursery" classes through.
  - The class list's teacher join became an **outer** join for the same
    reason. An inner join made an unassigned class vanish from the very list
    it was created to appear in.
- **`class_teachers` — a class may have several teachers.** One class teacher
  (`classes.teacher_id`) plus a set, rather than the set alone, so
  `uq_classes_teacher_name` keeps meaning what it always did. The principal
  picks them from the class screen's "Add teacher" button, several at a time,
  and `PUT /classes/{id}/teachers` takes the **whole set** — an unticked name
  that stayed assigned is the obvious bug and the one nobody notices until a
  register turns up on the wrong dashboard.
  - The sitting class teacher **keeps the room** as long as they are still in
    the set; only a class with no owner takes the first id listed. Without
    that, reordering a list of checkboxes would quietly move who is
    answerable.
  - `PATCH /classes/{id}/teacher` still **moves** a class outright, as it has
    since phase 4 — it does not leave the outgoing teacher on as a
    co-teacher. Two endpoints because they answer different questions: "who
    takes this class" is a list, "who is the class teacher" is one person.
  - **The trap this created, and the one to remember:** every query that asked
    `teacher_id ==` about a class now has to ask both halves, and getting it
    wrong is silent — a co-teacher who sees the class but none of its pupils.
    `app/access.py`'s `teacher_class_ids` unions the two, and nothing outside
    that module should ask any other way. `list_students` filtered on
    `class_roster.teacher_id`, which is the **owner**, and had to change.
- **`notifications`, as specified.** Date and time as separate columns, a
  `source` in words, an audience of one named account or a broadcast, and the
  message as text. The message is **stored, not generated at read time**:
  "Asha Rao requests approval for removal of Nursery" has to still say that in
  a month, after Nursery is gone and Asha has left, and a template filled from
  live rows comes back blank exactly when the history matters.
  - Fanned out to principals as **a row each**, not one broadcast, because
    `read_at` lives on the row — one shared row would have the first reader
    clear it for the second. A broadcast cannot be marked read at all, and the
    endpoint says so rather than silently losing everyone else's unread state.
- **The bell lives in the home app bar**, not the bottom bar. Three of the
  four tabs there are still unbuilt, and adding a fifth to carry a queue would
  reshuffle a row nothing else is ready to change.
- 46 tests across `test_approvals.py` and `test_class_teachers.py`.

> **What phase 5 turned out not to need.** The original blocker was "design
> the notifications table", and the table on its own would not have been
> enough: a notification is a sentence *about* something, and without
> `change_requests` underneath it there is nothing for Approve to act on. The
> two arrived together, and the notification carries a nullable `request_id`
> that is what makes a line actionable rather than merely news.

**Phase 6 — done (2026-09-18).** The parent's portal. Taken before phase 5 by
decision.

## Not Built Yet
- **Password reset** — the three screens exist and navigate correctly, but there
  is **no backend for them**. `PasswordResetCode` is modelled in
  `backend/app/models.py` and nothing routes to it; the app carries four
  `TODO(backend)` markers across `GB_ForgotPassword`, `GB_VerifyEmail`, and
  `GB_CreateNewPassword`. The flow currently walks through without verifying
  anything.
- **Events** — the carousel on both the dashboard and the class screen is
  hard-coded placeholder data. `_events` in each file is the seam.
- **The six class features** — Assignment, Grade Book, Resources, Class
  Schedule, Attendance, Fee Payment are cards that say "coming soon".
- **Bottom-nav tabs** — Attendance, Fee, and Message announce themselves and
  leave the tab where it was. Only Home has a screen. The notification tab is
  **not** among them: it is behind the bell in the app bar, because three of
  these four are still unbuilt and a fifth destination would have reshuffled a
  row nothing else is ready to change.
- **The rest of the student portal** — the parent's dashboard is real now
  (class, teacher, roll number, attendance), but the **grade sheet, teacher
  messages, events and diary notes have no tables anywhere in the project**.
  The screen names them under "Coming soon" rather than faking rows. See The
  Role Rebuild, phase 6.
- **Linking a parent from the app** — `POST /students/{id}/guardians` exists
  and is tested, but no screen calls it. Until one does, a link has to be made
  with curl or from `/docs`, and an unlinked parent sees "ask your child's
  teacher" forever.
- **Settings** — nothing is configurable yet; the screen exists so the menu
  item goes somewhere real, and because it is where Logout now lives.
- **Editing a profile** — `GB_Profile` only displays. The form that writes
  `PATCH /auth/me` is `GB_CompleteProfile`; an "Edit" action here should reuse
  it rather than grow a second one.
- **"See All"** on the class screen's student list.
- **iOS Google Sign-In** — `kGoogleIosClientId` is still empty.
- **SMS** — `request_otp()` logs the code instead of sending it.

## Backend
Python 3.12 + FastAPI + SQLAlchemy in `backend/`. Seven routers: `auth`,
`classes`, `subjects`, `attendance`, `teachers`, `guardians` and `approvals`,
with the role rules they share in `app/access.py`.

Three modules sit under the routers, and are worth knowing about before
changing any of them:

- **`app/school.py`** — the four acts themselves: create a class, delete
  one, register a pupil, remove one. They live here because they have **two**
  callers now, the direct route and the approval that grants a teacher's
  request. The alternative was the approval path re-implementing "add a
  class", and the two drifting until a granted request did something the
  direct call would have refused.
- **`app/approvals.py`** — raising a request, granting it, refusing it. The
  payload is validated **again** at approval time, against the school as it is
  then: a class name that was free when it was asked for may have been taken
  by the time it is granted, and a rejection then is a normal outcome.
- **`app/notifications.py`** — every sentence the app puts in somebody's tab,
  composed in one place and stored as written.

Full run instructions and the checklist live in
`backend/README.md`; the interactive docs at `http://<host>:8080/docs` are the
source of truth for request/response shapes.

**Endpoints** under `/api/v1`:

| | |
| --- | --- |
| `POST /auth/signup` | one "email or phone" field; the server decides which |
| `POST /auth/login` | email or phone + password |
| `POST /auth/otp/request` `POST /auth/otp/verify` | 30s resend cooldown; verify doubles as sign-up |
| `POST /auth/google` | takes a Google **ID token**, never an email |
| `GET /auth/me` `PATCH /auth/me` | read, and complete, the profile |
| `GET /classes` | the classes a teacher takes, owned **or** co-taught — or every class in the school for a principal |
| `POST /classes` | principal → created at once, under the `teacher_id` they name or unassigned. Teacher → **202** and a pending request |
| `PATCH /classes/{id}` | rename/recolour. The class teacher or the principal; a co-teacher gets 403. No approval needed |
| `DELETE /classes/{id}` | principal → 200 `done`. Teacher → **202** and a pending request. Never 204 any more |
| `PUT /classes/{id}/teachers` | principal only — **who teaches this class**, as the whole set. Empty unassigns it |
| `GET /classes/{id}/roster` | class id, class name, roll number, student name. A teacher's own class, any class for a principal; someone else's reads 404, not 403 |
| `GET /students` | every student of the signed-in teacher — or of the whole school for a principal |
| `POST /students` | principal into any class → created at once. Teacher → **202** and a pending request |
| `DELETE /students/{id}` | principal → 200 `done`. Teacher → **202** and a pending request. Staff only |
| `GET /subjects` | approved subjects + your own proposals; everything for a principal |
| `POST /subjects` | principal → approved at once; teacher → a `pending` proposal |
| `POST /subjects/{id}/approve` `DELETE /subjects/{id}` | principal only |
| `POST /attendance` | one class, one day, a mark per pupil. Teacher of that class only; re-posting updates |
| `GET /attendance` | needs `class_id` or `student_id`, optional `date`. Teacher's own classes, or school-wide for a principal |
| `GET /attendance/summary` | one pupil's present/absent totals, computed not stored |
| `GET /teachers` | every teacher — principal only; a teacher has no business enumerating colleagues |
| `GET/PATCH /teachers/{id}` | `me` for your own. A teacher on a colleague's id gets 404, not 403 |
| `POST /teachers/{id}/experience` `DELETE …/experience/{n}` | previous posts; own record, or any for a principal |
| `PUT /teachers/{id}/subjects` | principal only. The **whole set**, and approved subjects only |
| `PATCH /classes/{id}/teacher` | principal only — "add a teacher to a class". Students move with it |
| `GET/POST /students/{id}/guardians` `DELETE …/guardians/{u}` | staff only — links a parent's account to a pupil. A parent cannot link themselves |
| `GET /requests` | the whole queue for a principal, your own rows for a teacher. `?status=pending` is what the bell opens on. A parent gets 403 |
| `POST /requests/{id}/approve` | principal only — runs the change and returns what it produced. 409 if it was already answered |
| `POST /requests/{id}/reject` | principal only, with an optional `note` the teacher is shown |
| `GET /notifications` | your own plus every broadcast, newest first, with `unread` and `pending_requests` |
| `POST /notifications/{id}/read` `POST /notifications/read` | one line, or all of yours. A broadcast is refused — its `read_at` is shared |
| `GET /health` | **not** under the prefix — it is `/health`, so a probe pointed at `/api/v1/health` gets a 404 |

Success on the auth routes returns `{access_token, token_type, is_new_user,
user}`; every error returns `{"detail": "<message>"}`, which the app shows
verbatim in a SnackBar — including FastAPI's validation errors, which
`main.py` collapses into one readable sentence.

### Data model
Readable ids from a counter table — `U_000001`, `TR_000001`, `CL_000001`,
`ST_000001` — with a random UUID alongside each. A counter row rather than
"highest id + 1" so two devices saving at once cannot take the same number, and
numbers are never reused, which is what lets a restored class file bring its
students back under their old ids. Each table also carries a UUID for anywhere
an id is shown outside the app.

**The tables, and how they connect** (verified against PostgreSQL 18,
2026-09-18):

```
users --1:1-- teachers --1:N-- classes --1:N-- students
  |              |  |             |               |
  |              |  |             +-------+-------+
  |              |  |                     |
  |              |  |              class_roster (view)
  |              |  |
  |              |  +-- SET NULL --> attendance <-- CASCADE --+
  |              |                     ^                      |
  |              |                     |  (student_id, class_id)
  |              +-- SET NULL --> subjects.proposed_by_teacher_id
  |
  +-- SET NULL --> subjects.approved_by_user_id

id_counters        otp_codes        password_reset_codes
```

Every foreign key is `ON DELETE CASCADE` **except** the two teacher links on
`subjects` and `attendance`, which are `SET NULL`: a teacher leaving the school
must not take the subject list or the attendance history with them.

| Table | Id | What it holds |
| --- | --- | --- |
| `users` | `U_` | Identity. `email`, `phone`, `password_hash`, `google_id` and `role` are all nullable — one nullable set per sign-in path. A CHECK pins `role` to `teacher`, `student` or `principal`. |
| `teachers` | `TR_` | The teacher facet of a user, plus their profile — DOB, qualification, address, relationship status, Aadhaar, emergency contact. `user_id` is **unique**, so exactly one teacher row per user. Every profile column is nullable; name and phone stay on `users` and are joined in. |
| `teacher_subjects` | pair | Many-to-many, keyed on `(teacher_id, subject_id)` so the same subject cannot be assigned twice. Principal assigns; approved subjects only. |
| `teacher_experience` | int | One previous post per row — school, address, `years` as `Numeric(4,1)` so "2.5" survives. A list, hence its own table. |
| `classes` | `CL_` | `teacher_id` is the class teacher and is **nullable** — null means unassigned, a class the principal made before giving it to anyone. `uq_classes_teacher_name` is unique on `(teacher_id, lower(name))`, and the duplicate check compares a null owner with `IS NULL` because `=` against NULL is never true. |
| `students` | `ST_` | The registration record. `uq_students_same_child` spans ten columns (see the duplicate rule below). |
| `class_roster` | view | Joins students to classes and derives `roll_number` at read time. |
| `subjects` | `S_` | School-wide. `status` is `approved` or `pending`; `uq_subjects_name` is unique on `lower(name)`. `S_` reads like `ST_` but cannot collide — `number_in_code` matches the prefix exactly. |
| `class_teachers` | pair | The **co-teachers** on a class, beside the owner. The class teacher is deliberately not repeated here — one fact, one place; `access.teacher_class_ids` unions the two halves. |
| `change_requests` | int | A teacher asking the principal to create or delete a class, or add or remove a pupil. `payload` is the request's own copy of what to do, re-validated when it runs. Until it is granted **nothing else has changed**. |
| `notifications` | int | One line in somebody's tab: `date` and `time` apart, a `source` in words, an audience of one `user_id` or a `broadcast`, and the message as **stored** text. A nullable `request_id` is what makes a line actionable. |
| `student_guardians` | pair | Which account may see which pupil — a parent's link to their child. Many-to-many: a parent may have two children, a child two parents. **Only staff create rows.** |
| `attendance` | int | One mark per pupil per day: `uq_attendance_student_date` is unique, so re-marking updates. `status` CHECKed to `P`/`A`. `class_id` records the class the mark was taken in, so moving a pupil later cannot rewrite last term. |
| `id_counters` | `prefix` | One row per id prefix (`U`, `TR`, `CL`, `ST`, `S`) holding `last_value`. |
| `otp_codes` | int | Phone codes: `code_hash`, `expires_at`, `attempts`, `consumed_at`. |
| `password_reset_codes` | int | As above plus `verified_at`, which separates "code proven" from "password changed". Table exists; the reset flow is still UI-only. |

Every foreign key is `ON DELETE CASCADE`, so removing a user takes their
teacher row, classes and students with it. The two code tables are the
exception to the graph: they key off a bare `phone`/`email` string with **no
foreign key** to `users`, because a code is often issued before the account
exists.

Things worth knowing before changing this:
- **Classes belong to a teacher (`TR_`), not to a user**, and two teachers each
  having a "Nursery" is normal — neither sees the other's.
- **Never ask `teacher_id ==` about a class again.** Since 0006 a teacher's
  classes are the ones they own *plus* the ones they were added to in
  `class_teachers`, and a query that remembers only the first hides half a
  teacher's timetable — silently. `app.access.teacher_class_ids` is the one
  place that unions them. `class_roster.teacher_id` is the **owner**, so it is
  no longer a scope to filter by; `list_students` used to and had to change.
- **Roll numbers are not stored.** They are alphabetical within a class and
  renumber when a student leaves, so the `class_roster` **view** computes them
  on every read. Stored, one missed rewrite would leave two students sharing a
  number.
- **The duplicate-student rule** is a unique index over class + name + DOB +
  address + both parents' names, emails, and mobiles. The name is part of the
  key on purpose: twins share everything else and are two students. Optional
  text is stored `""` rather than NULL and normalised on the way in, because a
  unique index treats two NULLs — and `"Meera"` vs `" meera"` — as different.
- **`account_type` is null** for Google and phone sign-ups; phone sign-ups get
  the placeholder name `"GrowBuddy User"`. Route on `needs_account_type` /
  `needs_contact_details`, not on `is_new_user`.
- **Google accounts are keyed on the `sub` claim**, never on email. A changed
  email updates the existing row instead of creating a second account.
- **`color_slot` is a palette index, not a colour.** Retuning a pastel in
  `GB_Constants.dart` reaches every existing class with no data migration.

### Notes that bite
- `kApiBaseUrl` differs per target. The committed **default** is a LAN IP
  (`http://192.168.0.157:8080`); Android emulator wants `10.0.2.2`, desktop/iOS
  sim `127.0.0.1`. It is a `String.fromEnvironment`, so prefer
  `--dart-define=GB_API_BASE_URL=...` over editing the constant — and note that
  a `--dart-define` change does **not** hot-reload, it needs a full restart.
- **Tailscale is how the app reaches the backend off the LAN.** Every other
  address above dies the moment the phone leaves the Wi-Fi.
  `tool/gb_tailscale_serve.ps1` runs `tailscale serve`, which fronts uvicorn
  with a real Let's Encrypt certificate at
  `https://laptop-9iu37vee.tailee091f.ts.net` (verified 2026-09-13),
  and prints the `flutter run --dart-define=...` line to copy. Setup is in
  docs/Tailscale_porting.md. Three things make it work or not: MagicDNS **and** HTTPS
  certificates both enabled in the tailnet admin console, and the phone signed
  into the same tailnet. Because it is genuine HTTPS it needs no
  `network_security_config.xml` entry, which makes it the only path that works
  in a release build. It is `serve`, **not** `funnel` — nothing is on the public
  internet, which is what makes it safe to leave the dev-mode backend
  (`OTP_DEBUG_RETURN`, wildcard CORS, dev `SECRET_KEY`) as it is.
- Android 9+ blocks plain HTTP. `android/app/src/debug/res/xml/network_security_config.xml`
  allow-lists dev hosts for debug builds only; a changed LAN IP must be updated
  there **and** in `GB_Constants.dart`.
- `OTP_DEBUG_RETURN=true` returns the code in the response (shown as
  `(dev code: 123456)` in **debug builds only** — `kDebugMode` is the half of
  that check a server setting cannot undo). The server **refuses to start** with
  it on when `ENVIRONMENT` is anything but development.
- Storage is **PostgreSQL 18** as of 2026-09-13 — `.env` points at
  `postgresql+psycopg://growbuddy@localhost:5432/growbuddy`, served by the
  `postgresql-x64-18` Windows service. The `growbuddy` role owns the database;
  the password lives in `.env` only. The SQLite files are kept as a backup and
  nothing reads them; the fallback URL is commented above the live one.
- **`uuid` columns are a native `uuid` type on PostgreSQL**, not the `CHAR(32)`
  SQLite used. Anything comparing a uuid to a raw string needs a cast.
- **Read migration `0006` before writing the next one.** It changes a
  column on `classes`, which carries two things `--autogenerate` cannot
  see: the expression index `uq_classes_teacher_name` on `lower(name)`,
  which Alembic cannot reflect on SQLite at all, and the `class_roster`
  view, which `env.py` excludes by name. A generated batch operation would
  have reflected the table to rebuild it, lost the index, and left the view
  pointing at a table dropped and remade underneath it. So it drops the
  view, drops the index, alters the column, and puts both back — in that
  order, by hand.
- **Alembic owns the schema as of 2026-09-17.** `create_schema()` is gone —
  it used `create_all`, which only creates *missing* tables, so once a table
  existed, adding a column or widening a constraint did nothing, silently. The
  live database was backed up, stamped `0001`, and upgraded.
  - `.venvScriptspython.exe -m alembic upgrade head` applies; `alembic
    current` says where a database is.
  - **The server checks but never migrates.** `main.py` refuses to start when
    the database is behind the code and prints the command. Deploying now
    includes running the upgrade as its own step.
  - The URL comes from `.env` via `alembic/env.py`, never from `alembic.ini` —
    the placeholder there is meant to stay one, or the password gets committed.
  - Autogenerate is blind to CHECK constraints, cannot reflect expression
    indexes on SQLite, and does not manage the `class_roster` view (`env.py`
    excludes it by name). **Read every generated migration.**
  - `backend/tests/` now builds its database by running the real migrations,
    so a broken migration fails the suite.
- CORS is `allow_origins=["*"]` — fine for a LAN and Swagger, not for public.
- `photo_path` is a path on the device that picked the photo; it will not
  resolve anywhere else. Cards fall back to the stock asset.

## Design Conventions in the Code
- File and class names use the `GB_` prefix and `Snake_Case`/PascalCase. The
  linter flags this as non-idiomatic; it is the project's chosen convention —
  do not mass-rename without discussion.
- Colours and reusable sizes live in `GB_Constants.dart`, most of them traced to
  a named Figma frame (`360-39838` home, `360-45584` class, `360-44515` register
  student) and commented with it.
- The design misspells "Attendence". The app ships **"Attendance"** in the
  bottom nav and feature list deliberately — do not "correct" it back.
- State is `ValueNotifier` + `ValueListenableBuilder`, not a state-management
  package. Stores assign a new list rather than mutating, or listeners hear
  nothing.
- Stores write to the server first and only then update the local copy, so the
  UI can never show a class that does not really exist.

- **The launcher icon is generated, not hand-drawn.**
  `dart run tool/gb_make_app_icon.dart` squares the logo into `tool/icon/`, then
  `dart run flutter_launcher_icons` writes the Android mipmaps and the iOS
  appiconset. Run both after changing the art; hand-editing the generated PNGs
  gets overwritten.
  The source art carries a wide transparent margin — the drawn logo is only
  631x509 of its 846x633 canvas — so the script **trims that margin first**.
  Without the trim the scale constants described padding rather than the logo,
  which put it at 46% of the icon canvas and is why the icon looked far too
  small until 2026-09-13. The adaptive foreground is now sized by the logo's
  **diagonal** (0.66 of the canvas), not its width, because a circular launcher
  mask clips the bounding-box corners of landscape art first. That caps how
  large this logo can go on Android: at 526px wide its diagonal already fills
  the largest circle any launcher draws. Making it meaningfully bigger needs
  squarer artwork — a stacked or symbol-only mark — not a bigger number here.

## Verification

_Backend and analyzer run 2026-09-20, after phase 5. The device checks are
still from 2026-09-13._

- `cd backend && .venv\Scripts\python.exe -m pytest -q` — **222 passed** in
  138s. That is the 176 that passed before phase 5 plus 46 new ones, and the
  176 are not all untouched: several asserted the *old* rule and were
  rewritten to assert the new one. Each rewrite says so in its docstring,
  which is the only honest way to change a test that was passing.
  - `tests/helpers.py` is new and worth knowing about. Most of this suite only
    ever needed *a class belonging to Asha* in order to reach the thing it
    tests, and making every one of them stage a two-step approval would have
    buried what they are about — so the helper creates that class through a
    principal in one call. The row is identical either way; both paths go
    through `app/school.py`. The files that are genuinely about who may do
    what — `test_approvals.py`, `test_class_teachers.py` — do it the long way.
- `flutter analyze lib` — **clean**: no errors, no warnings.
- `dart run testcases/run_tests.dart --suite unit,widget` — **102 passed, 74
  failed** in 51s. The total fell from 188 to 176 because six files no longer
  compile.
  - `flutter analyze testcases integration_test` reports **62 errors**. **Ten
    of them are new**, all the same mechanical shape: `createClass`,
    `createStudent`, `deleteClass` and the two sheets return a
    `GB_ActionResult` now rather than the thing itself, so those call sites
    need `.classInfo` / `.student`. They are in `gb_class_store_test`,
    `gb_student_store_test`, `gb_class_archive_test`,
    `gb_add_class_sheet_test`, `gb_class_screen_test` and
    `gb_register_student_test`.
  - **The other 52 predate this work** and are the drift already recorded on
    2026-09-13: `GB_Student.age`, `GB_Student.id`,
    `GB_ClassArchive.serialInStudentId` and `GB_StudentStore.restoreStudents`
    do not exist on the app any more.
  - Among the failures that do run, `type 'Null' is not a subtype of type
    'String' in type cast` is still the largest family, and still points at
    `GB_AuthApi.dart:47-48`, where `user_id` and `full_name` are cast to
    non-nullable `String` while the fixtures leave them out.
  - Full report in `testcases/reports/last_run.json`.
  - **This suite belongs to Tastu.** The ten new errors were left for them
    rather than fixed in passing — coordinate before changing it.
- A full API round-trip was exercised by hand against PostgreSQL on
  2026-09-13: signup — `U_000001` — class `CL_000001` — two students —
  roster, plus both rejection paths (duplicate class name, duplicate child).
  The smoke data was then truncated, so the database is empty.
- **Phase 5 has not been exercised on a device.** It is covered by the backend
  suite and by the analyzer, and by nothing else. The approval round trip —
  a teacher asking, the bell appearing for the principal, the grant landing
  back on the teacher's screen — has not been watched happen.
- Android builds need JDK 17 — Android Studio's bundled Java 25 JBR breaks
  Gradle 8.3.
