"""Shared setup for tests whose subject is not class creation.

Creating a class stopped being a teacher's act on 2026-09-20: a teacher now
raises a request and the principal grants it. That is the right rule and it is
covered thoroughly in `test_approvals.py` — but most of this suite only ever
needed *a class that belongs to Asha* in order to get to the thing it actually
tests, and making every one of them stage a two-step approval would bury what
they are about.

So [make_class] produces exactly the row those tests always had: a class owned
by the named teacher, created in one call by a principal. The resulting
`classes` row is identical to the one a granted request produces — same owner,
same name, same colour — because both paths go through `app.school.create_class`.

The principal it uses is its own, made once per test client and reused. A test
that has its own principal is unaffected: an extra admin account changes no
assertion in this suite, because `GET /teachers` lists teacher records and a
principal has none.
"""

SIGNUP = "/api/v1/auth/signup"
CLASSES = "/api/v1/classes"
STUDENTS = "/api/v1/students"
TEACHERS = "/api/v1/teachers"
REQUESTS = "/api/v1/requests"

PASSWORD = "supersecret123"

ACCOUNT_TYPE_TEACHER = 0
ACCOUNT_TYPE_STUDENT = 1
ACCOUNT_TYPE_PRINCIPAL = 2

# The helper's own admin. Named so it is obvious in a failing test that this
# account came from here and not from the test itself.
HELPER_ADMIN_EMAIL = "helper-admin@growbuddy.test"


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def signup(client, name: str, identifier: str, account_type: int) -> str:
    response = client.post(
        SIGNUP,
        json={
            "full_name": name,
            "identifier": identifier,
            "password": PASSWORD,
            "account_type": account_type,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["access_token"]


def admin_token(client) -> str:
    """The principal this module creates classes through.

    Cached on the client so one test gets one admin however many classes it
    makes — a second signup with the same address would 409, and a second
    admin would quietly change what "every principal" means in a notification
    fan-out test.
    """
    cached = getattr(client, "_gb_helper_admin", None)
    if cached is not None:
        return cached

    token = signup(
        client, "Helper Admin", HELPER_ADMIN_EMAIL, ACCOUNT_TYPE_PRINCIPAL
    )
    client._gb_helper_admin = token
    return token


def teacher_id_of(client, token: str) -> str:
    """The TR_ id behind a teacher's token."""
    response = client.get(f"{TEACHERS}/me", headers=auth(token))
    assert response.status_code == 200, response.text
    return response.json()["teacher_id"]


def make_class(
    client,
    token: str,
    name: str,
    *,
    color_slot: int = 0,
    students: list[dict] | None = None,
    principal: str | None = None,
) -> str:
    """A class called [name], owned by the teacher behind [token].

    [principal] lets a test that already has one use it instead of the
    helper's, which matters where the test asserts something about who was
    notified.

    Returns the class id, which is what every caller wanted from the old
    `client.post(CLASSES, ...)` two-liner.
    """
    response = client.post(
        CLASSES,
        json={
            "name": name,
            "color_slot": color_slot,
            "teacher_id": teacher_id_of(client, token),
            "students": students or [],
        },
        headers=auth(principal or admin_token(client)),
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["status"] == "done", body
    return body["school_class"]["class_id"]


def add_student(client, token: str, class_id: str, name: str, **overrides) -> dict:
    """Registers a pupil and returns them.

    Goes in as the principal by default for the same reason [make_class]
    does: a teacher's registration is a request now, and a test about
    attendance wants a pupil, not a queue.
    """
    response = client.post(
        STUDENTS,
        json={
            "class_id": class_id,
            "name": name,
            "date_of_birth": "2021-04-12",
            "gender": "Female",
            "address": "12 Rose Lane",
            **overrides,
        },
        headers=auth(token),
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["status"] == "done", body
    return body["student"]


def approve_latest(client, principal: str) -> dict:
    """Grants the newest pending request. The two-step path, for tests that
    are about it."""
    pending = client.get(
        REQUESTS, params={"status": "pending"}, headers=auth(principal)
    ).json()
    assert pending, "no pending request to approve"

    response = client.post(
        f"{REQUESTS}/{pending[0]['id']}/approve", headers=auth(principal)
    )
    assert response.status_code == 200, response.text
    return response.json()
