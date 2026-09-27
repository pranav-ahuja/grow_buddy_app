"""Who teaches a class — one owner, any number of co-teachers, or nobody.

Two changes 0006 brought, and they are easiest to read together:

* a class may be **unassigned** (`classes.teacher_id` is null), because the
  principal creates classes now and one made in August has nobody taking it
  yet;
* a class may have **several** teachers, picked by the principal from the
  class screen, several at a time.

The trap this file is really guarding is the second half of "one owner plus a
set": every query that used to ask `teacher_id ==` about a class now has to
ask both halves, and the failure mode is silent — a co-teacher who simply
cannot see the class they were added to, or their pupils. So most of what
follows checks that a co-teacher reaches the same things the class teacher
does.
"""

import helpers
from helpers import (
    ACCOUNT_TYPE_PRINCIPAL,
    ACCOUNT_TYPE_TEACHER,
    CLASSES,
    STUDENTS,
    auth,
    signup,
    teacher_id_of,
)

ATTENDANCE = "/api/v1/attendance"


def cast(client) -> dict[str, str]:
    asha = signup(client, "Asha Rao", "asha@example.com", ACCOUNT_TYPE_TEACHER)
    bela = signup(client, "Bela Nair", "bela@example.com", ACCOUNT_TYPE_TEACHER)
    head = signup(
        client, "Meera Iyer", "head@example.com", ACCOUNT_TYPE_PRINCIPAL
    )
    return {
        "asha": asha,
        "bela": bela,
        "head": head,
        "asha_id": teacher_id_of(client, asha),
        "bela_id": teacher_id_of(client, bela),
    }


def set_teachers(client, head: str, class_id: str, teacher_ids: list[str]):
    return client.put(
        f"{CLASSES}/{class_id}/teachers",
        json={"teacher_ids": teacher_ids},
        headers=auth(head),
    )


def names_of(client, token: str) -> list[str]:
    return [c["name"] for c in client.get(CLASSES, headers=auth(token)).json()]


# --- An unassigned class ------------------------------------------------------


def test_the_principal_creates_a_class_with_no_teacher(client):
    """September has not happened yet. The class is still a real class."""
    c = cast(client)

    created = client.post(
        CLASSES, json={"name": "Nursery", "color_slot": 3}, headers=auth(c["head"])
    )

    assert created.status_code == 201, created.text
    body = created.json()["school_class"]
    assert body["teacher_id"] is None
    assert body["teacher_name"] is None
    assert body["teachers"] == []

    # And it is on the principal's list — an inner join would have hidden it.
    assert names_of(client, c["head"]) == ["Nursery"]
    # Nobody teaches it, so no teacher sees it.
    assert names_of(client, c["asha"]) == []


def test_two_unassigned_classes_cannot_share_a_name(client):
    """`=` against NULL is never true, which would have let this through."""
    c = cast(client)
    client.post(CLASSES, json={"name": "Nursery"}, headers=auth(c["head"]))

    duplicate = client.post(
        CLASSES, json={"name": "nursery"}, headers=auth(c["head"])
    )

    assert duplicate.status_code == 409
    assert duplicate.json()["detail"] == 'A class called "nursery" already exists'


def test_the_principal_creates_a_class_straight_onto_a_teacher(client):
    c = cast(client)

    created = client.post(
        CLASSES,
        json={"name": "Nursery", "teacher_id": c["asha_id"]},
        headers=auth(c["head"]),
    )

    assert created.status_code == 201, created.text
    assert created.json()["school_class"]["teacher_name"] == "Asha Rao"
    assert names_of(client, c["asha"]) == ["Nursery"]


def test_creating_a_class_for_a_teacher_who_does_not_exist_is_a_404(client):
    c = cast(client)

    response = client.post(
        CLASSES,
        json={"name": "Nursery", "teacher_id": "TR_999999"},
        headers=auth(c["head"]),
    )

    assert response.status_code == 404


# --- The picker ---------------------------------------------------------------


def test_the_principal_puts_two_teachers_on_one_class(client):
    """The "Add teacher" picker: several at a time, in one call."""
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )

    response = set_teachers(
        client, c["head"], class_id, [c["asha_id"], c["bela_id"]]
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert [t["full_name"] for t in body["teachers"]] == ["Asha Rao", "Bela Nair"]
    # The class teacher is named first and flagged, so the class screen can
    # say who is answerable for the room.
    assert [t["is_class_teacher"] for t in body["teachers"]] == [True, False]

    # Both of them have it on their dashboard.
    assert names_of(client, c["asha"]) == ["Nursery"]
    assert names_of(client, c["bela"]) == ["Nursery"]


def test_the_sitting_class_teacher_keeps_the_room(client):
    """Reordering a list of checkboxes must not move who is answerable."""
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )

    # Bela listed first, but Asha is already the class teacher.
    body = set_teachers(
        client, c["head"], class_id, [c["bela_id"], c["asha_id"]]
    ).json()

    assert body["teacher_name"] == "Asha Rao"
    assert [t["full_name"] for t in body["teachers"]] == ["Asha Rao", "Bela Nair"]


def test_the_first_listed_takes_an_unassigned_class(client):
    c = cast(client)
    class_id = client.post(
        CLASSES, json={"name": "Nursery"}, headers=auth(c["head"])
    ).json()["school_class"]["class_id"]

    body = set_teachers(
        client, c["head"], class_id, [c["bela_id"], c["asha_id"]]
    ).json()

    assert body["teacher_name"] == "Bela Nair"


def test_the_set_is_what_is_sent_not_a_difference(client):
    """An unhighlighted name that stayed assigned would be the obvious bug."""
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )
    set_teachers(client, c["head"], class_id, [c["asha_id"], c["bela_id"]])

    set_teachers(client, c["head"], class_id, [c["asha_id"]])

    assert names_of(client, c["asha"]) == ["Nursery"]
    assert names_of(client, c["bela"]) == []


def test_an_empty_set_unassigns_the_class(client):
    """A legitimate end state — the one a class is created in."""
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )

    body = set_teachers(client, c["head"], class_id, []).json()

    assert body["teacher_id"] is None
    assert body["teachers"] == []
    assert names_of(client, c["asha"]) == []
    # Still the school's class, still on the principal's list.
    assert names_of(client, c["head"]) == ["Nursery"]


def test_only_the_principal_may_choose(client):
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )

    response = set_teachers(
        client, c["asha"], class_id, [c["asha_id"], c["bela_id"]]
    )

    assert response.status_code == 403


def test_an_unknown_teacher_is_named_in_the_404(client):
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )

    response = set_teachers(client, c["head"], class_id, ["TR_999999"])

    assert response.status_code == 404
    assert "TR_999999" in response.json()["detail"]


def test_the_same_teacher_twice_is_refused(client):
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )

    response = set_teachers(
        client, c["head"], class_id, [c["asha_id"], c["asha_id"]]
    )

    assert response.status_code == 422


def test_handing_a_class_to_someone_who_has_that_name_is_refused(client):
    """uq_classes_teacher_name is per teacher, so the receiver may have one."""
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )
    helpers.make_class(client, c["bela"], "Nursery", principal=c["head"])

    response = set_teachers(client, c["head"], class_id, [c["bela_id"]])

    assert response.status_code == 409
    assert response.json()["detail"] == 'Bela Nair already has a class called "Nursery"'


# --- What a co-teacher can reach ---------------------------------------------


def test_a_co_teacher_sees_the_pupils(client):
    """The silent failure this file exists for.

    `list_students` filtered on the class's **owner** until 0006. Left that
    way, a co-teacher would see the class on their dashboard with nobody in
    it.
    """
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )
    helpers.add_student(client, c["head"], class_id, "Diya")
    set_teachers(client, c["head"], class_id, [c["asha_id"], c["bela_id"]])

    assert [s["name"] for s in client.get(STUDENTS, headers=auth(c["bela"])).json()] == [
        "Diya"
    ]


def test_a_co_teacher_reads_the_roster(client):
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )
    helpers.add_student(client, c["head"], class_id, "Diya")
    set_teachers(client, c["head"], class_id, [c["asha_id"], c["bela_id"]])

    response = client.get(f"{CLASSES}/{class_id}/roster", headers=auth(c["bela"]))

    assert response.status_code == 200, response.text
    assert [r["student_name"] for r in response.json()] == ["Diya"]


def test_a_co_teacher_takes_the_register(client):
    """Attendance is a first-hand observation, and a co-teacher is in the
    room. This is the reason the mark is scoped to classes they take rather
    than classes they own."""
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )
    pupil = helpers.add_student(client, c["head"], class_id, "Diya")
    set_teachers(client, c["head"], class_id, [c["asha_id"], c["bela_id"]])

    response = client.post(
        ATTENDANCE,
        json={
            "class_id": class_id,
            "date": "2026-09-18",
            "entries": [{"student_id": pupil["student_id"], "status": "P"}],
        },
        headers=auth(c["bela"]),
    )

    assert response.status_code == 200, response.text


def test_a_co_teacher_may_not_rename_the_class(client):
    """Renaming the room out from under the person answerable for it is a
    surprise nobody asked for."""
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )
    set_teachers(client, c["head"], class_id, [c["asha_id"], c["bela_id"]])

    refused = client.patch(
        f"{CLASSES}/{class_id}", json={"name": "Reception"}, headers=auth(c["bela"])
    )
    allowed = client.patch(
        f"{CLASSES}/{class_id}", json={"name": "Reception"}, headers=auth(c["asha"])
    )

    assert refused.status_code == 403
    assert allowed.status_code == 200, allowed.text


def test_a_co_teacher_may_ask_for_the_class_to_go(client):
    """They teach it, so they may raise the request — and it is still only a
    request."""
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )
    set_teachers(client, c["head"], class_id, [c["asha_id"], c["bela_id"]])

    asked = client.delete(f"{CLASSES}/{class_id}", headers=auth(c["bela"]))

    assert asked.status_code == 202, asked.text
    assert asked.json()["request"]["requested_by_name"] == "Bela Nair"
    assert names_of(client, c["asha"]) == ["Nursery"]


def test_taking_a_teacher_off_takes_their_access_with_it(client):
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )
    helpers.add_student(client, c["head"], class_id, "Diya")
    set_teachers(client, c["head"], class_id, [c["asha_id"], c["bela_id"]])

    set_teachers(client, c["head"], class_id, [c["asha_id"]])

    assert names_of(client, c["bela"]) == []
    assert client.get(STUDENTS, headers=auth(c["bela"])).json() == []
    # And someone else's class reads as missing, not forbidden.
    assert (
        client.get(f"{CLASSES}/{class_id}/roster", headers=auth(c["bela"])).status_code
        == 404
    )


def test_moving_the_class_teacher_does_not_leave_them_on_it(client):
    """PATCH /teacher moves a class; it does not quietly demote."""
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )

    response = client.patch(
        f"{CLASSES}/{class_id}/teacher",
        json={"teacher_id": c["bela_id"]},
        headers=auth(c["head"]),
    )

    assert response.status_code == 200, response.text
    assert [t["full_name"] for t in response.json()["teachers"]] == ["Bela Nair"]
    assert names_of(client, c["asha"]) == []
    assert names_of(client, c["bela"]) == ["Nursery"]


def test_promoting_a_co_teacher_does_not_list_them_twice(client):
    """One fact, one place — the owner is never repeated in class_teachers."""
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )
    set_teachers(client, c["head"], class_id, [c["asha_id"], c["bela_id"]])

    response = client.patch(
        f"{CLASSES}/{class_id}/teacher",
        json={"teacher_id": c["bela_id"]},
        headers=auth(c["head"]),
    )

    assert response.status_code == 200, response.text
    teachers = response.json()["teachers"]
    assert [t["full_name"] for t in teachers] == ["Bela Nair"]
    assert [t["teacher_id"] for t in teachers].count(c["bela_id"]) == 1
