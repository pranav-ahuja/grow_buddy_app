"""student_mapping — parent accounts mapped to pupils by the contacts on the
pupil's record.

Case 1: the parent's account exists before the teacher registers the pupil.
Case 2: the pupil is registered first and the parent signs up afterwards.
Either way an account whose *verified* phone or email is the mother's or
father's on the record sees that pupil. A mother and a father keep separate
accounts and see the same children. A parent changing their own number moves
it onto the record too, and the class teachers are told.
"""

import helpers
from helpers import auth

STUDENTS = helpers.STUDENTS
ME = "/api/v1/auth/me"
OTP_REQUEST = "/api/v1/auth/otp/request"
OTP_VERIFY = "/api/v1/auth/otp/verify"
CONTACT_REQUEST = "/api/v1/auth/me/contact/request"
CONTACT_VERIFY = "/api/v1/auth/me/contact/verify"
NOTIFICATIONS = "/api/v1/notifications"

MOTHER_PHONE = "+919876500010"
FATHER_PHONE = "+919876500020"
STRANGER_PHONE = "+919876500030"


def otp_account(client, phone: str, name: str, *, role: int | None = 1) -> str:
    """Signs in with phone + OTP — the verified path — and picks a role.
    `role=None` leaves it unpicked, as right after a first OTP sign-in."""
    code = client.post(OTP_REQUEST, json={"phone": phone}).json()["debug_otp"]
    response = client.post(
        OTP_VERIFY, json={"phone": phone, "otp": code, "full_name": name}
    )
    assert response.status_code == 200, response.text
    token = response.json()["access_token"]
    if role is not None:
        picked = client.patch(ME, json={"account_type": role}, headers=auth(token))
        assert picked.status_code == 200, picked.text
    return token


def children_of(client, token) -> list[str]:
    response = client.get(STUDENTS, headers=auth(token))
    assert response.status_code == 200, response.text
    return sorted(student["name"] for student in response.json())


def links_of(client, staff, student_id) -> dict[str, str]:
    """full name -> relationship, as staff see it."""
    response = client.get(f"{STUDENTS}/{student_id}/guardians", headers=auth(staff))
    assert response.status_code == 200, response.text
    return {row["full_name"]: row["relation"] for row in response.json()}


def messages(client, token) -> list[str]:
    response = client.get(NOTIFICATIONS, headers=auth(token))
    assert response.status_code == 200, response.text
    return [item["message"] for item in response.json()["notifications"]]


def school(client):
    asha = helpers.signup(
        client, "Asha Rao", "asha@example.com", helpers.ACCOUNT_TYPE_TEACHER
    )
    head = helpers.signup(
        client, "Meera Iyer", "head@example.com", helpers.ACCOUNT_TYPE_PRINCIPAL
    )
    nursery = helpers.make_class(client, asha, "Nursery", principal=head)
    return {"asha": asha, "head": head, "nursery": nursery}


def register(client, s, name, **contacts) -> dict:
    """The teacher registers a pupil — outright, as teachers do now."""
    return helpers.add_student(client, s["asha"], s["nursery"], name, **contacts)


# --- Case 1: the account exists first ---------------------------------------


def test_case_1_registering_a_pupil_maps_the_existing_parent(client):
    s = school(client)
    priya = otp_account(client, MOTHER_PHONE, "Priya Rao")
    assert children_of(client, priya) == []

    diya = register(client, s, "Diya", mother_mobile=MOTHER_PHONE)

    assert children_of(client, priya) == ["Diya"]
    assert links_of(client, s["asha"], diya["student_id"]) == {"Priya Rao": "Mother"}


def test_a_number_typed_with_spaces_on_the_form_still_matches(client):
    s = school(client)
    priya = otp_account(client, MOTHER_PHONE, "Priya Rao")

    register(client, s, "Diya", mother_mobile="+91 98765 00010")

    assert children_of(client, priya) == ["Diya"]


def test_a_number_typed_without_the_country_code_still_matches(client):
    """The bug found on the live data 2026-09-27: the form stored 9876500010,
    the login +919876500010, and they never matched."""
    s = school(client)
    priya = otp_account(client, MOTHER_PHONE, "Priya Rao")

    diya = register(client, s, "Diya", mother_mobile="9876500010")

    assert diya["mother_mobile"] == MOTHER_PHONE
    assert children_of(client, priya) == ["Diya"]


def test_case_2_with_a_number_typed_with_a_leading_zero(client):
    s = school(client)
    register(client, s, "Diya", father_mobile="09876500020")

    rohan = otp_account(client, FATHER_PHONE, "Rohan Rao")

    assert children_of(client, rohan) == ["Diya"]


def test_every_spelling_of_an_indian_number_is_one_number():
    from app.schemas import normalize_phone

    for spelling in (
        "9876500010",
        "09876500010",
        "919876500010",
        "+919876500010",
        "+91 98765-00010",
        "0091 98765 00010",
    ):
        assert normalize_phone(spelling) == MOTHER_PHONE, spelling
    # A number already carrying another country's code is left alone.
    assert normalize_phone("+14155550100") == "+14155550100"


# --- Case 2: the pupil exists first ------------------------------------------


def test_case_2_a_parent_signing_up_later_finds_their_child(client):
    s = school(client)
    register(client, s, "Diya", father_mobile=FATHER_PHONE)

    # First OTP sign-in: no role yet, so nothing is shown.
    rohan = otp_account(client, FATHER_PHONE, "Rohan Rao", role=None)
    assert client.get(ME, headers=auth(rohan)).json()["role"] is None

    client.patch(ME, json={"account_type": 1}, headers=auth(rohan))

    assert children_of(client, rohan) == ["Diya"]


def test_picking_the_teacher_role_maps_nothing(client):
    s = school(client)
    diya = register(client, s, "Diya", mother_mobile=MOTHER_PHONE)

    otp_account(client, MOTHER_PHONE, "Priya Rao", role=helpers.ACCOUNT_TYPE_TEACHER)

    assert links_of(client, s["asha"], diya["student_id"]) == {}


# --- Both parents, several children -----------------------------------------


def test_mother_and_father_each_see_the_same_child_on_their_own_account(client):
    s = school(client)
    diya = register(
        client, s, "Diya", mother_mobile=MOTHER_PHONE, father_mobile=FATHER_PHONE
    )

    priya = otp_account(client, MOTHER_PHONE, "Priya Rao")
    rohan = otp_account(client, FATHER_PHONE, "Rohan Rao")

    assert priya != rohan
    assert children_of(client, priya) == ["Diya"]
    assert children_of(client, rohan) == ["Diya"]
    assert links_of(client, s["asha"], diya["student_id"]) == {
        "Priya Rao": "Mother",
        "Rohan Rao": "Father",
    }


def test_one_parent_account_tracks_every_child_with_their_number(client):
    s = school(client)
    register(client, s, "Diya", mother_mobile=MOTHER_PHONE)
    register(client, s, "Kabir", mother_mobile=MOTHER_PHONE)
    register(client, s, "Rhea", mother_mobile=STRANGER_PHONE)

    priya = otp_account(client, MOTHER_PHONE, "Priya Rao")

    assert children_of(client, priya) == ["Diya", "Kabir"]


def test_a_parent_sees_the_whole_record_of_their_child(client):
    s = school(client)
    register(
        client,
        s,
        "Diya",
        mother_mobile=MOTHER_PHONE,
        mother_name="Priya Rao",
        address="12 Rose Lane",
    )
    priya = otp_account(client, MOTHER_PHONE, "Priya Rao")

    [child] = client.get(STUDENTS, headers=auth(priya)).json()

    assert child["address"] == "12 Rose Lane"
    assert child["mother_name"] == "Priya Rao"
    assert child["roll_number"] == 1


# --- Only a verified contact maps --------------------------------------------


def test_a_password_sign_up_with_the_mothers_number_sees_nothing(client):
    """Typing a number into a sign-up form proves nothing about holding it."""
    s = school(client)
    register(client, s, "Diya", mother_mobile=MOTHER_PHONE)

    stranger = helpers.signup(
        client, "Not Priya", MOTHER_PHONE, helpers.ACCOUNT_TYPE_STUDENT
    )

    assert children_of(client, stranger) == []


def test_the_same_account_is_mapped_once_the_number_is_proved_by_otp(client):
    s = school(client)
    register(client, s, "Diya", mother_mobile=MOTHER_PHONE)
    helpers.signup(client, "Priya Rao", MOTHER_PHONE, helpers.ACCOUNT_TYPE_STUDENT)

    # The OTP login reaches the same account (same number) and proves it.
    code = client.post(OTP_REQUEST, json={"phone": MOTHER_PHONE}).json()["debug_otp"]
    token = client.post(
        OTP_VERIFY, json={"phone": MOTHER_PHONE, "otp": code}
    ).json()["access_token"]

    assert children_of(client, token) == ["Diya"]


def test_an_email_typed_into_the_profile_does_not_map(client):
    s = school(client)
    register(client, s, "Diya", mother_email="priya@example.com")
    priya = otp_account(client, STRANGER_PHONE, "Priya Rao")

    client.patch(ME, json={"email": "priya@example.com"}, headers=auth(priya))

    assert children_of(client, priya) == []


def test_a_verified_email_maps_like_a_number(client):
    s = school(client)
    register(client, s, "Diya", mother_email="priya@example.com")
    priya = otp_account(client, STRANGER_PHONE, "Priya Rao")

    code = client.post(
        CONTACT_REQUEST,
        json={"channel": "email", "value": "priya@example.com"},
        headers=auth(priya),
    ).json()["debug_otp"]
    client.post(
        CONTACT_VERIFY, json={"channel": "email", "otp": code}, headers=auth(priya)
    )

    assert children_of(client, priya) == ["Diya"]
    assert client.get(ME, headers=auth(priya)).json()["is_email_verified"] is True


# --- The teacher changes the number on the record ----------------------------


def test_correcting_the_number_moves_the_child_to_the_right_account(client):
    s = school(client)
    diya = register(client, s, "Diya", mother_mobile=STRANGER_PHONE)
    wrong = otp_account(client, STRANGER_PHONE, "Somebody Else")
    priya = otp_account(client, MOTHER_PHONE, "Priya Rao")
    assert children_of(client, wrong) == ["Diya"]

    body = {k: v for k, v in diya.items() if k not in ("student_id", "roll_number", "created_at")}
    response = client.patch(
        f"{STUDENTS}/{diya['student_id']}",
        json=body | {"mother_mobile": MOTHER_PHONE},
        headers=auth(s["asha"]),
    )
    assert response.status_code == 200, response.text

    assert children_of(client, wrong) == []
    assert children_of(client, priya) == ["Diya"]
    # The account that lost the child is told, not left wondering.
    assert any("mother's mobile is now" in m for m in messages(client, wrong))


def test_a_link_staff_made_by_hand_survives_a_number_change(client):
    s = school(client)
    diya = register(client, s, "Diya", mother_mobile=MOTHER_PHONE)
    priya = otp_account(client, MOTHER_PHONE, "Priya Rao")
    client.post(
        f"{STUDENTS}/{diya['student_id']}/guardians",
        json={"identifier": MOTHER_PHONE, "relation": "Mother"},
        headers=auth(s["asha"]),
    )

    body = {k: v for k, v in diya.items() if k not in ("student_id", "roll_number", "created_at")}
    client.patch(
        f"{STUDENTS}/{diya['student_id']}",
        json=body | {"mother_mobile": ""},
        headers=auth(s["asha"]),
    )

    assert children_of(client, priya) == ["Diya"]


# --- The parent changes their own number -------------------------------------


def test_a_parents_new_number_reaches_the_record_and_the_teacher(client):
    s = school(client)
    diya = register(client, s, "Diya", mother_mobile=MOTHER_PHONE)
    priya = otp_account(client, MOTHER_PHONE, "Priya Rao")
    new_phone = "+919876500099"

    code = client.post(
        CONTACT_REQUEST,
        json={"channel": "phone", "value": new_phone},
        headers=auth(priya),
    ).json()["debug_otp"]
    verified = client.post(
        CONTACT_VERIFY, json={"channel": "phone", "otp": code}, headers=auth(priya)
    )
    assert verified.status_code == 200, verified.text

    # users table
    assert verified.json()["phone"] == new_phone
    # students table
    [record] = client.get(STUDENTS, headers=auth(s["asha"])).json()
    assert record["mother_mobile"] == new_phone
    # still mapped
    assert children_of(client, priya) == ["Diya"]
    # the class teacher is told
    [message] = messages(client, s["asha"])
    assert "Priya Rao" in message
    assert "Diya" in message
    assert new_phone in message
    assert record["student_id"] == diya["student_id"]


def test_the_other_parents_number_is_left_alone(client):
    s = school(client)
    register(
        client, s, "Diya", mother_mobile=MOTHER_PHONE, father_mobile=FATHER_PHONE
    )
    rohan = otp_account(client, FATHER_PHONE, "Rohan Rao")
    priya = otp_account(client, MOTHER_PHONE, "Priya Rao")

    code = client.post(
        CONTACT_REQUEST,
        json={"channel": "phone", "value": "+919876500099"},
        headers=auth(rohan),
    ).json()["debug_otp"]
    client.post(
        CONTACT_VERIFY, json={"channel": "phone", "otp": code}, headers=auth(rohan)
    )

    [record] = client.get(STUDENTS, headers=auth(s["asha"])).json()
    assert record["father_mobile"] == "+919876500099"
    assert record["mother_mobile"] == MOTHER_PHONE
    assert children_of(client, priya) == ["Diya"]
    assert children_of(client, rohan) == ["Diya"]


def test_deleting_the_class_removes_its_mappings(client):
    s = school(client)
    register(client, s, "Diya", mother_mobile=MOTHER_PHONE)
    priya = otp_account(client, MOTHER_PHONE, "Priya Rao")

    response = client.delete(
        f"{helpers.CLASSES}/{s['nursery']}", headers=auth(s["head"])
    )
    assert response.status_code == 200, response.text

    assert children_of(client, priya) == []
