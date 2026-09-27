# GrowBuddy — Database Tables and Relations

PostgreSQL 18, schema owned by Alembic at revision **`0009`**. Drawn from
`backend/app/models.py` and `backend/app/database.py` on 2026-09-27. When a
migration changes a table, update this file in the same pass.

17 tables and 1 view. The diagrams are split by area because one diagram with
every table and every foreign key is unreadable; the overview comes first.

**Reading the diagrams:**

- `||--o{` one to many, `||--o|` one to zero-or-one, `|o--o{` optional parent
  (the foreign key is nullable).
- `PK` primary key, `FK` foreign key. Unique columns, and a key that is also
  a foreign key, are noted in the column's comment instead: older Mermaid
  builds (as bundled in some editors) reject `UK` and `PK, FK`.
- Readable ids (`U_000001`, `TR_…`, `CL_…`, `ST_…`, `S_…`) are handed out by
  `id_counters`; every such table also carries a random `uuid`.

---

## 1. Overview

Every table and how they connect. Columns are in the sections below.







Refer the diagram below

```mermaid
erDiagram
    users ||--o| teachers : "is a (staff facet)"
    users ||--o{ student_mapping : "parent account"
    users ||--o{ notifications : "receives"
    users ||--o{ contact_change_codes : "changes own contact"

    teachers |o--o{ classes : "class teacher of"
    teachers ||--o{ class_teachers : "co-teaches"
    teachers ||--o{ teacher_subjects : "teaches"
    teachers ||--o{ teacher_experience : "worked at"
    teachers |o--o{ subjects : "proposed"
    teachers |o--o{ attendance : "marked"
    teachers |o--o{ change_requests : "asked for"

    classes ||--o{ class_teachers : "has co-teachers"
    classes ||--o{ students : "contains"
    classes ||--o{ attendance : "taken in"
    classes |o--o{ change_requests : "about"

    students ||--o{ attendance : "marked for"
    students ||--o{ student_mapping : "mapped to"
    students |o--o{ change_requests : "about"

    subjects ||--o{ teacher_subjects : "assigned as"

    change_requests |o--o{ notifications : "makes actionable"
```

Standalone, with no foreign keys: `id_counters`, `otp_codes`,
`password_reset_codes`. The two code tables key off a bare phone or email
because a code is often issued before the account exists.

---

## 2. People — accounts, staff and parents

One `users` row per person who signs in, whatever their role. A teacher also
has a `teachers` row; a principal and a parent do not. A parent reaches a
pupil **only** through `student_mapping` (called `student_guardians` before
migration `0008`).

```mermaid
erDiagram
    users {
        string user_id PK "U_000001"
        uuid uuid "unique"
        string full_name
        string email "unique, nullable, lower-cased"
        string phone "unique, nullable, +91... form"
        string password_hash "nullable"
        string google_id "unique, nullable, Google sub claim"
        string role "teacher | student | principal, nullable"
        bool is_phone_verified "a code reached this number"
        bool is_email_verified "Google or a code vouched for it"
        bool is_active
        datetime created_at
    }
    teachers {
        string teacher_id PK "TR_000001"
        uuid uuid "unique"
        string user_id FK "unique, one teacher row per user"
        date date_of_birth "nullable"
        string highest_qualification "nullable"
        string address "nullable"
        string relationship_status "nullable"
        string aadhaar_number "unique, nullable, only last 4 ever returned"
        string emergency_contact_name "nullable"
        string emergency_contact_phone "nullable"
        datetime created_at
        datetime updated_at
    }
    teacher_experience {
        int id PK
        string teacher_id FK
        string school_name
        string school_address
        decimal years "Numeric(4,1), so 2.5 survives"
        datetime created_at
    }
    student_mapping {
        string user_id PK "also FK to users, the parent account"
        string student_id PK "also FK to students, the pupil"
        string relationship "Mother, Father or Parent"
        string source "contact_match or staff"
        string linked_by_user_id FK "staff who linked by hand, else null"
        datetime created_at
    }
    students {
        string student_id PK "ST_000001"
        string mother_mobile "a parent's login"
        string father_mobile "a parent's login"
        string mother_email "a parent's login"
        string father_email "a parent's login"
    }

    users ||--o| teachers : "is a"
    teachers ||--o{ teacher_experience : "previous posts"
    users ||--o{ student_mapping : "parent side"
    students ||--o{ student_mapping : "child side"
    users |o--o{ student_mapping : "linked by"
```

**Name and phone are not copied onto `teachers`.** They are joined in from
`users`, so a profile can never disagree with the account it logs in with.

### How a parent's login maps to a pupil

The mother's and father's mobile numbers and emails the teacher types on the
register-student form **are the parents' logins**. A parent account
(`role = student`) whose **verified** phone or email equals one of them gets a
`student_mapping` row for that pupil, as Mother or Father (`source =
contact_match`). It works whichever side exists first:

```mermaid
flowchart TD
    subgraph C1["Case 1: the parent's account exists first"]
        A1["Teacher saves the pupil<br/>mother_mobile = +9198..."] --> B1["students row written"]
        B1 --> D1["Search users by that number<br/>role student, phone verified"]
        D1 --> E1["student_mapping row<br/>user_id, student_id, Mother"]
    end
    subgraph C2["Case 2: the pupil exists first"]
        A2["Parent logs in with phone + OTP<br/>and picks Student"] --> B2["users row, phone verified"]
        B2 --> D2["Search students by that number<br/>mother_mobile or father_mobile"]
        D2 --> E2["student_mapping row<br/>user_id, student_id, Father"]
    end
```

- **Verified only.** An OTP login proves a phone. Google sign-in or a confirmed
  email change proves an email. A number typed into the password sign-up form
  proves nothing, so it maps nothing until that account logs in once with OTP.
  Without this rule, anyone could type a mother's number and read her child's
  record.
- **Separate accounts, same children.** The mother's and father's accounts
  each get their own row for the pupil, and one account gets a row for every
  pupil carrying its number.
- **Recomputed, not frozen.** Automatic rows follow the record. If the teacher
  changes a number, the account it used to match loses the pupil and the new
  one gains it. Rows staff add by hand (`source = staff`) are never removed
  automatically.

When a **parent** changes their own number (after confirming it with a code),
the new number goes onto `users` and onto every mapped pupil's record where the
old one was, and the class teachers are told:

```mermaid
sequenceDiagram
    participant M as Mother
    participant API
    participant U as users
    participant S as students
    participant N as notifications

    M->>API: POST /auth/me/contact/verify (code for the new number)
    API->>U: phone = new number
    API->>S: mother_mobile = new number, on each mapped pupil where it was the old one
    API->>N: one row per class teacher, "changed their mobile number to ..."
    API-->>M: 200, still mapped to the same children
```

---

## 3. School — classes, pupils, subjects and attendance

```mermaid
erDiagram
    teachers {
        string teacher_id PK "TR_000001"
    }
    classes {
        string class_id PK "CL_000001"
        uuid uuid "unique"
        string teacher_id FK "class teacher, null means unassigned"
        string name "unique per teacher, case-insensitive"
        int color_slot "palette index 0-8, not a colour"
        datetime created_at
    }
    class_teachers {
        string class_id PK "also FK to classes"
        string teacher_id PK "also FK to teachers, the co-teacher"
        string assigned_by_user_id FK
        datetime created_at
    }
    students {
        string student_id PK "ST_000001"
        uuid uuid "unique"
        string class_id FK
        string name
        date date_of_birth
        string gender
        string address
        string photo_path "nullable, device-local path"
        string mother_name
        string mother_mobile
        string mother_email
        string father_name
        string father_mobile
        string father_email
        string guardian_name
        string guardian_relation
        string guardian_mobile
        string guardian_address
        datetime created_at
    }
    subjects {
        string subject_id PK "S_000001"
        uuid uuid "unique"
        string name "unique school-wide, case-insensitive"
        string status "approved | pending"
        string proposed_by_teacher_id FK "nullable"
        string approved_by_user_id FK "nullable"
        datetime approved_at
        datetime created_at
    }
    teacher_subjects {
        string teacher_id PK "also FK to teachers"
        string subject_id PK "also FK to subjects"
        string assigned_by_user_id FK
        datetime created_at
    }
    attendance {
        int id PK
        string student_id FK
        string class_id FK "class the mark was taken in"
        string teacher_id FK "nullable, who marked it"
        date date
        string status "P | A"
        datetime created_at
        datetime updated_at
    }

    teachers |o--o{ classes : "class teacher"
    classes ||--o{ class_teachers : "has co-teachers"
    teachers ||--o{ class_teachers : "co-teaches"
    classes ||--o{ students : "contains"
    teachers ||--o{ teacher_subjects : "teaches"
    subjects ||--o{ teacher_subjects : "assigned as"
    teachers |o--o{ subjects : "proposed"
    students ||--o{ attendance : "marked for"
    classes ||--o{ attendance : "taken in"
    teachers |o--o{ attendance : "marked by"
```

Things the diagram cannot show:

- **A teacher's classes are two halves:** the ones they own
  (`classes.teacher_id`) plus the ones in `class_teachers`.
  `app.access.teacher_class_ids` is the one place that unions them.
- **No roll-number column.** Roll numbers follow registration order within a
  class and are computed on every read by the `class_roster` view (below).
- **Phone numbers are stored as `+91XXXXXXXXXX`** on both `users` and
  `students`, however they were typed. That is what lets a parent's login
  match the number on their child's record.
- **Duplicate pupil rule:** the unique index `uq_students_same_child` covers
  class + name + date of birth + address + both parents' names, emails and
  mobiles. The name is in it so that twins are two pupils.
- **One mark per pupil per day:** `uq_attendance_student_date` on
  `(student_id, date)`. Re-marking a day updates the row.

### The `class_roster` view

```mermaid
flowchart LR
    C[(classes)] --> V
    S[(students)] --> V
    V[["class_roster (view)<br/>class_id, class_name,<br/>roll_number, student_name,<br/>teacher_id, student_id"]]
    V --> A["GET /students<br/>GET /classes/{id}/roster"]
```

`roll_number` is the pupil's position in the class by registration order
(`student_id`, which is handed out in sequence and kept by a restored class
file). A new pupil gets the next number; removing one closes the gap behind
them. The view's current SQL is in migration `0009` (alphabetical before
that).
`class_roster.teacher_id` is the class **owner** only, so it must not be used
to decide what a co-teacher can see.

---

## 4. Approvals and notifications

A teacher asking to create or delete a class, or to remove a pupil, writes a
`change_requests` row and changes nothing else. The principal's answer runs
the change. Every line in someone's notification tab is a `notifications`
row; a `request_id` on it is what puts Approve and Reject on that line.

```mermaid
erDiagram
    change_requests {
        int id PK
        uuid uuid "unique"
        string kind "class_create | class_delete | student_add | student_remove"
        string status "pending | approved | rejected"
        string requested_by_teacher_id FK "nullable"
        string requested_by_name "kept if the teacher leaves"
        string class_id FK "nullable"
        string student_id FK "nullable"
        string summary
        json payload "the request's own copy of what to do"
        string decided_by_user_id FK "nullable"
        datetime decided_at
        string decision_note
        datetime created_at
    }
    notifications {
        int id PK
        uuid uuid "unique"
        date date
        time time
        string source "who or what said it, in words"
        string audience "user | broadcast"
        string user_id FK "NULL for a broadcast"
        string message "stored as written, never re-rendered"
        int request_id FK "nullable, makes the line actionable"
        datetime read_at
        datetime created_at
    }
    teachers {
        string teacher_id PK
    }
    users {
        string user_id PK
    }
    classes {
        string class_id PK
    }
    students {
        string student_id PK
    }

    teachers |o--o{ change_requests : "asked by"
    users |o--o{ change_requests : "decided by"
    classes |o--o{ change_requests : "about"
    students |o--o{ change_requests : "about"
    users |o--o{ notifications : "addressed to"
    change_requests |o--o{ notifications : "about"
```

```mermaid
sequenceDiagram
    participant T as Teacher
    participant API
    participant CR as change_requests
    participant N as notifications
    participant P as Principal

    T->>API: DELETE /students/ST_000007
    API->>CR: insert (kind student_remove, status pending)
    API->>N: one row per principal, with request_id
    API-->>T: 202 pending, nothing else changed
    P->>API: POST /requests/{id}/approve
    API->>CR: status approved, decided_by
    API->>API: app/school.py runs the removal
    API->>N: row for the teacher, "approved your request..."
```

Which acts need this path (as of 2026-09-27):

| Act              | Principal     | Teacher                                                    |
| ---------------- | ------------- | ---------------------------------------------------------- |
| Create a class   | done outright | request                                                    |
| Delete a class   | done outright | request                                                    |
| Register a pupil | done outright | done outright, principals notified                         |
| Edit a pupil     | done outright | done outright; mapped parents notified if a mobile changes |
| Remove a pupil   | done outright | request                                                    |

---

## 5. Sign-in codes and counters

```mermaid
erDiagram
    users {
        string user_id PK
    }
    contact_change_codes {
        int id PK
        string user_id FK
        string channel "phone | email"
        string new_value "the contact being moved to"
        string code_hash
        datetime expires_at
        int attempts
        datetime consumed_at
        datetime created_at
    }
    otp_codes {
        int id PK
        string phone "no FK: issued before an account may exist"
        string code_hash
        datetime expires_at
        int attempts
        datetime consumed_at
        datetime created_at
    }
    password_reset_codes {
        int id PK
        string email "no FK"
        string code_hash
        datetime expires_at
        int attempts
        datetime verified_at
        datetime consumed_at
        datetime created_at
    }
    id_counters {
        string prefix PK "U, TR, CL, ST, S"
        int last_value
    }

    users ||--o{ contact_change_codes : "moving own email or phone"
```

- **`otp_codes`** is for phone login. A verified code signs in to (or creates)
  whichever account holds that number.
- **`contact_change_codes`** is kept separate for that reason. It is keyed to
  one `user_id` and can only move that user's contact; it can never sign
  anyone in.
- **`password_reset_codes`** exists, but no route uses it yet: password reset
  is UI only.
- **`id_counters`** holds one row per id prefix. Numbers are never reused,
  which is what lets a restored class file bring pupils back under their old
  `ST_` ids.

---

## What deleting a row takes with it

Most foreign keys are `ON DELETE CASCADE`. The `SET NULL` ones keep history
alive when a person or thing goes away.

```mermaid
flowchart TD
    U[users] -->|CASCADE| TR[teachers]
    U -->|CASCADE| SG[student_mapping]
    U -->|CASCADE| NO[notifications]
    U -->|CASCADE| CC[contact_change_codes]

    TR -->|CASCADE| CL[classes]
    TR -->|CASCADE| CT[class_teachers]
    TR -->|CASCADE| TS[teacher_subjects]
    TR -->|CASCADE| TE[teacher_experience]
    TR -.->|SET NULL| SU[subjects.proposed_by]
    TR -.->|SET NULL| AT[attendance.teacher_id]
    TR -.->|SET NULL| CR[change_requests.requested_by]

    CL -->|CASCADE| ST[students]
    CL -->|CASCADE| CT
    CL -->|CASCADE| AT2[attendance]
    CL -.->|SET NULL| CR2[change_requests.class_id]

    ST -->|CASCADE| AT2
    ST -->|CASCADE| SG
    ST -.->|SET NULL| CR3[change_requests.student_id]

    CRQ[change_requests] -.->|SET NULL| NO2[notifications.request_id]
```

Solid arrows delete the child rows; dotted arrows only blank the column.
Every `assigned_by_user_id`, `linked_by_user_id`, `approved_by_user_id` and
`decided_by_user_id` is also `SET NULL`.

**Deleting a pupil or a class in code also deletes the attendance and
`student_mapping` rows explicitly** (`app/school.py`). PostgreSQL would apply the cascades on its
own, but the test suite runs on SQLite, which ignores them unless each
connection turns them on.
