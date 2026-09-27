"""Editing a pupil's details — `PATCH /students/{id}`.

Staff edit outright; nothing here waits for the principal. Removing the pupil
is the act that does, and it stays on DELETE (see test_approvals.py). A changed
mobile number is told to the parent accounts linked to the pupil.
"""

import helpers
from helpers import auth

STUDENTS = helpers.STUDENTS
NOTIFICATIONS = "/api/v1/notifications"
REQUESTS = helpers.REQUESTS

DIYA_MOTHER_MOBILE = "+919876500010"


def school(client):
    """Asha teaches Nursery (Diya, Kabir); Bela teaches Playgroup. Priya is
    linked to Diya as her mother; Sunil is a parent linked to nobody."""
    asha = helpers.signup(
        client, "Asha Rao", "asha@example.com", helpers.ACCOUNT_TYPE_TEACHER
    )
    bela = helpers.signup(
        client, "Bela Nair", "bela@example.com", helpers.ACCOUNT_TYPE_TEACHER
    )
    head = helpers.signup(
        client, "Meera Iyer", "head@example.com", helpers.ACCOUNT_TYPE_PRINCIPAL
    )
    nursery = helpers.make_class(client, asha, "Nursery", principal=head)
    helpers.make_class(client, bela, "Playgroup", principal=head)

    diya = helpers.add_student(
        client,
        head,
        nursery,
        "Diya",
        mother_name="Priya Rao",
        mother_mobile=DIYA_MOTHER_MOBILE,
    )
    kabir = helpers.add_student(client, head, nursery, "Kabir")

    priya = helpers.signup(
        client, "Priya Rao", "priya@example.com", helpers.ACCOUNT_TYPE_STUDENT
    )
    sunil = helpers.signup(
        client, "Sunil Das", "sunil@example.com", helpers.ACCOUNT_TYPE_STUDENT
    )
    linked = client.post(
        f"{STUDENTS}/{diya['student_id']}/guardians",
        json={"identifier": "priya@example.com", "relation": "Mother"},
        headers=auth(asha),
    )
    assert linked.status_code == 201, linked.text

    return {
        "asha": asha,
        "bela": bela,
        "head": head,
        "nursery": nursery,
        "diya": diya,
        "kabir": kabir,
        "priya": priya,
        "sunil": sunil,
    }


def edit(client, token, student, **changes):
    """PATCHes [student] with every field it already has, plus [changes] —
    the shape the app's edit form sends."""
    body = {
        key: value
        for key, value in student.items()
        if key not in ("student_id", "roll_number", "created_at")
    }
    return client.patch(
        f"{STUDENTS}/{student['student_id']}",
        json=body | changes,
        headers=auth(token),
    )


def messages(client, token) -> list[str]:
    response = client.get(NOTIFICATIONS, headers=auth(token))
    assert response.status_code == 200, response.text
    return [item["message"] for item in response.json()["notifications"]]


def test_a_teacher_edits_their_pupil_outright(client):
    s = school(client)

    response = edit(
        client, s["asha"], s["diya"], name="Diya Rao", address="4 Lotus Road"
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "done"
    assert body["student"]["name"] == "Diya Rao"
    assert body["student"]["address"] == "4 Lotus Road"
    assert body["student"]["student_id"] == s["diya"]["student_id"]

    # No request was raised for the principal to answer.
    pending = client.get(
        REQUESTS, params={"status": "pending"}, headers=auth(s["head"])
    ).json()
    assert pending == []


def test_changing_a_mobile_notifies_the_linked_parent(client):
    s = school(client)

    response = edit(client, s["asha"], s["diya"], mother_mobile="+919876500099")

    assert response.status_code == 200, response.text
    assert response.json()["student"]["mother_mobile"] == "+919876500099"

    [message] = messages(client, s["priya"])
    assert "Asha Rao" in message
    assert "Diya" in message
    assert "mother's mobile is now +919876500099" in message


def test_the_notice_goes_only_to_that_pupils_parents(client):
    s = school(client)

    edit(client, s["asha"], s["diya"], mother_mobile="+919876500099")

    assert messages(client, s["sunil"]) == []


def test_an_edit_that_leaves_the_numbers_alone_notifies_nobody(client):
    s = school(client)

    response = edit(client, s["asha"], s["diya"], address="4 Lotus Road")

    assert response.status_code == 200, response.text
    assert messages(client, s["priya"]) == []


def test_a_number_retyped_with_spaces_is_not_a_change(client):
    """Mobiles are normalised on the way in, so the comparison is too."""
    s = school(client)

    edit(client, s["asha"], s["diya"], mother_mobile="+91 98765 00010")

    assert messages(client, s["priya"]) == []


def test_clearing_a_mobile_says_it_was_removed(client):
    s = school(client)

    edit(client, s["asha"], s["diya"], mother_mobile="")

    [message] = messages(client, s["priya"])
    assert "mother's mobile was removed" in message


def test_the_principal_edits_any_pupil(client):
    s = school(client)

    response = edit(client, s["head"], s["kabir"], name="Kabir Shah")

    assert response.status_code == 200, response.text
    assert response.json()["student"]["name"] == "Kabir Shah"


def test_another_classes_teacher_cannot_see_the_pupil_to_edit(client):
    s = school(client)

    response = edit(client, s["bela"], s["diya"], name="Someone Else")

    assert response.status_code == 404


def test_a_parent_cannot_edit_even_their_own_child(client):
    s = school(client)

    response = edit(client, s["priya"], s["diya"], mother_mobile="+919876500099")

    assert response.status_code == 403


def test_saving_unchanged_details_does_not_clash_with_itself(client):
    s = school(client)

    response = edit(client, s["asha"], s["diya"])

    assert response.status_code == 200, response.text


def test_an_edit_that_makes_a_duplicate_of_a_classmate_is_refused(client):
    s = school(client)

    # Kabir, edited to match Diya in every field of the duplicate rule.
    duplicate = {
        key: s["diya"][key]
        for key in (
            "name",
            "date_of_birth",
            "address",
            "mother_name",
            "father_name",
            "mother_email",
            "father_email",
            "mother_mobile",
            "father_mobile",
        )
    }
    response = edit(client, s["asha"], s["kabir"], **duplicate)

    assert response.status_code == 409
    assert "Diya" in response.json()["detail"]


def test_a_class_id_in_the_body_does_not_move_the_pupil(client):
    s = school(client)
    elsewhere = helpers.make_class(client, s["asha"], "Reception", principal=s["head"])

    response = edit(client, s["asha"], s["diya"], class_id=elsewhere)

    assert response.status_code == 200, response.text
    assert response.json()["student"]["class_id"] == s["nursery"]
