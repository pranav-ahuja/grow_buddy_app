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


def test_a_principal_can_read_classes_but_owns_none(client):
    """A principal reads school-wide, but gets no TR_ row and owns nothing.

    This is the guard worth keeping. The obvious way to make the principal's
    dashboard work would have been to let `_current_teacher` accept them, which
    would have quietly given every principal a teacher's class-owning identity
    — and every class they created would have been filed under it. Reading is
    scoped by role instead; owning stays a teacher's.
    """
    token = client.post(SIGNUP, json=PRINCIPAL).json()["access_token"]

    assert client.get(CLASSES, headers=auth(token)).status_code == 200

    refused = client.post(
        CLASSES,
        json={"name": "Nursery", "color_slot": 0},
        headers=auth(token),
    )
    assert refused.status_code == 403
    assert "does not own one" in refused.json()["detail"]


def test_a_student_still_reaches_nothing(client):
    """The 403 a student gets is unchanged — only the principal's path moved."""
    token = client.post(
        SIGNUP,
        json={
            "full_name": "Aarav Sharma",
            "identifier": "pupil@example.com",
            "password": "supersecret123",
            "account_type": ACCOUNT_TYPE_STUDENT,
        },
    ).json()["access_token"]

    response = client.get(CLASSES, headers=auth(token))

    assert response.status_code == 403
    assert response.json()["detail"] == "Only teachers can manage classes"


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
