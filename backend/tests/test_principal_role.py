"""The principal — this school's admin, and the third account type.

Phase 1 covers the role existing end to end: sign-up, profile completion, and
the fact that it is a genuinely distinct role rather than a teacher by another
name. What a principal is actually *allowed* to do arrives in later phases;
what is pinned here is that they do not silently inherit a teacher's access on
the way.
"""

SIGNUP = "/api/v1/auth/signup"
ME = "/api/v1/auth/me"
CLASSES = "/api/v1/classes"

ACCOUNT_TYPE_TEACHER = 0
ACCOUNT_TYPE_STUDENT = 1
ACCOUNT_TYPE_PRINCIPAL = 2

PRINCIPAL = {
    "full_name": "Meera Iyer",
    "identifier": "principal@example.com",
    "password": "supersecret123",
    "account_type": ACCOUNT_TYPE_PRINCIPAL,
}


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_signup_as_principal_sets_the_role(client):
    response = client.post(SIGNUP, json=PRINCIPAL)

    assert response.status_code == 201, response.text
    user = response.json()["user"]
    assert user["role"] == "principal"
    assert user["account_type"] == ACCOUNT_TYPE_PRINCIPAL
    # The role is chosen at sign-up, so there is nothing left to ask for.
    assert user["needs_account_type"] is False


def test_principal_role_survives_a_round_trip(client):
    token = client.post(SIGNUP, json=PRINCIPAL).json()["access_token"]

    response = client.get(ME, headers=auth(token))

    assert response.status_code == 200, response.text
    assert response.json()["role"] == "principal"


def test_an_unknown_account_type_is_still_refused(client):
    # The CHECK constraint on users.role is the backstop, but it should never
    # be reached: 3 is not a role, and the API says so before the INSERT.
    response = client.post(SIGNUP, json={**PRINCIPAL, "account_type": 3})

    assert response.status_code == 422
    assert "principal" in response.json()["detail"]


def test_profile_completion_can_choose_principal(client):
    # The path a Google or phone sign-up takes: no role until the profile
    # screen asks for one.
    token = client.post(
        SIGNUP,
        json={**PRINCIPAL, "identifier": "+919876500011"},
    ).json()["access_token"]

    response = client.patch(
        ME,
        json={"account_type": ACCOUNT_TYPE_PRINCIPAL},
        headers=auth(token),
    )

    assert response.status_code == 200, response.text
    assert response.json()["role"] == "principal"


def test_a_principal_creates_classes_but_still_has_no_teacher_record(client):
    """Half of this reversed on 2026-09-20, and half of it must not.

    What changed: the principal is the school's admin and creates classes
    outright. Phase 1 refused them, on the reasoning that a class belongs to
    the teacher who owns it; the role is an administrator now and that
    reasoning no longer holds.

    What did **not** change, and is the guard still worth keeping: a principal
    gets no `TR_` row. The tempting shortcut was always to let the teacher
    lookup accept them, which would have handed every principal a teacher's
    class-owning identity and filed their classes under it. Instead a class
    they create with no `teacher_id` is genuinely **unassigned** — owned by
    nobody — until they give it to someone.
    """
    token = client.post(SIGNUP, json=PRINCIPAL).json()["access_token"]

    assert client.get(CLASSES, headers=auth(token)).status_code == 200

    created = client.post(
        CLASSES,
        json={"name": "Nursery", "color_slot": 0},
        headers=auth(token),
    )
    assert created.status_code == 201, created.text
    body = created.json()
    assert body["status"] == "done"
    # Unassigned, not filed under a teacher record invented for the principal.
    assert body["school_class"]["teacher_id"] is None
    assert body["school_class"]["teachers"] == []

    # And they still have no teacher record of their own.
    assert client.get("/api/v1/teachers/me", headers=auth(token)).status_code == 404


def test_a_student_account_owns_no_classes_either(client):
    """Rewritten in phase 6.

    This asserted 403 on `GET /classes`. A student account is a parent now and
    reads the classes its children are in — none yet, so an empty list. What
    still holds, and is the point of the test, is that it owns nothing: it
    cannot create a class any more than a principal can.
    """
    token = client.post(
        SIGNUP,
        json={
            "full_name": "Aarav Sharma",
            "identifier": "pupil@example.com",
            "password": "supersecret123",
            "account_type": ACCOUNT_TYPE_STUDENT,
        },
    ).json()["access_token"]

    assert client.get(CLASSES, headers=auth(token)).json() == []

    refused = client.post(
        CLASSES, json={"name": "Nursery", "color_slot": 0}, headers=auth(token)
    )
    assert refused.status_code == 403
    assert refused.json()["detail"] == "Only teachers can manage classes"


def test_teacher_and_student_signups_are_unaffected(client):
    """The roles that already existed keep working exactly as they did.

    Migration 0002 widened a CHECK constraint, which is the kind of change that
    can quietly break the values it used to allow.
    """
    teacher = client.post(
        SIGNUP,
        json={
            "full_name": "Pranav Ahuja",
            "identifier": "teacher@example.com",
            "password": "supersecret123",
            "account_type": ACCOUNT_TYPE_TEACHER,
        },
    )
    student = client.post(
        SIGNUP,
        json={
            "full_name": "Aarav Sharma",
            "identifier": "student@example.com",
            "password": "supersecret123",
            "account_type": ACCOUNT_TYPE_STUDENT,
        },
    )

    assert teacher.status_code == 201, teacher.text
    assert student.status_code == 201, student.text
    assert teacher.json()["user"]["role"] == "teacher"
    assert student.json()["user"]["role"] == "student"

    # And a teacher still reaches their own classes.
    token = teacher.json()["access_token"]
    assert client.get(CLASSES, headers=auth(token)).status_code == 200
