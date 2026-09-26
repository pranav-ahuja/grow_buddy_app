"""The parent's view — what a linked account can and cannot reach.

Phase 6. The app is for parents, so a "student" account is a parent operating
on a child's behalf. The link is the whole phase, and the boundary it draws is
the most important one in the app: a parent sees their own children and
nothing else, and the link can only be made by the school.

Everything here is read-only for the parent, on purpose. Editing a child's
details and raising a class-deletion request both have to notify the teacher
and the principal, and notifications are phase 5 — shipping the edit without
the notice would be shipping half a safety mechanism.
"""

from datetime import date, timedelta

import helpers

SIGNUP = "/api/v1/auth/signup"
CLASSES = "/api/v1/classes"
STUDENTS = "/api/v1/students"
ATTENDANCE = "/api/v1/attendance"
TEACHERS = "/api/v1/teachers"
SUBJECTS = "/api/v1/subjects"

TEACHER = 0
STUDENT = 1
PRINCIPAL = 2

TODAY = date.today().isoformat()
YESTERDAY = (date.today() - timedelta(days=1)).isoformat()


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def signup(client, name, email, account_type, phone=None):
    response = client.post(
        SIGNUP,
        json={
            "full_name": name,
            "identifier": phone or email,
            "password": "supersecret123",
            "account_type": account_type,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["access_token"]


def school(client):
    """Asha with Nursery (Diya, Kabir), Bela with Playgroup (Rhea), a
    principal, and two parent accounts — one linked, one not."""
    asha = signup(client, "Asha Rao", "asha@example.com", TEACHER)
    bela = signup(client, "Bela Nair", "bela@example.com", TEACHER)
    head = signup(client, "Meera Iyer", "head@example.com", PRINCIPAL)

    # Built by the principal rather than by each teacher. Since 2026-09-20 a
    # teacher's class and pupil creation is a request for the principal to
    # approve, and the setup for a test about what a *parent* can see should
    # not be a queue to work through. The rows are identical either way.
    nursery = helpers.make_class(
        client, asha, "Nursery", color_slot=3, principal=head
    )
    playgroup = helpers.make_class(
        client, bela, "Playgroup", color_slot=1, principal=head
    )

    def add(class_id, name, mother_mobile=""):
        return helpers.add_student(
            client,
            head,
            class_id,
            name,
            mother_name="Priya Rao",
            mother_mobile=mother_mobile,
        )["student_id"]

    diya = add(nursery, "Diya", "+919876500010")
    kabir = add(nursery, "Kabir")
    rhea = add(playgroup, "Rhea")

    # Two parent accounts. Priya's phone is the one on Diya's record.
    priya = signup(client, "Priya Rao", None, STUDENT, phone="+919876500010")
    stranger = signup(client, "Nobody", "nobody@example.com", STUDENT)

    return {
        "asha": asha,
        "bela": bela,
        "head": head,
        "nursery": nursery,
        "playgroup": playgroup,
        "diya": diya,
        "kabir": kabir,
        "rhea": rhea,
        "priya": priya,
        "stranger": stranger,
    }


def link(client, staff_token, student_id, identifier, relation="Mother"):
    return client.post(
        f"{STUDENTS}/{student_id}/guardians",
        json={"identifier": identifier, "relation": relation},
        headers=auth(staff_token),
    )


# --- Before any link --------------------------------------------------------


def test_an_unlinked_parent_sees_nothing_but_is_not_refused(client):
    """Empty, not 403. They have done nothing wrong and can do nothing yet."""
    s = school(client)

    assert client.get(CLASSES, headers=auth(s["priya"])).json() == []
    assert client.get(STUDENTS, headers=auth(s["priya"])).json() == []


# --- Linking ----------------------------------------------------------------


def test_a_teacher_links_a_parent_to_their_pupil(client):
    s = school(client)

    response = link(client, s["asha"], s["diya"], "+919876500010")

    assert response.status_code == 201, response.text
    guardians = response.json()
    assert len(guardians) == 1
    assert guardians[0]["full_name"] == "Priya Rao"
    assert guardians[0]["relation"] == "Mother"
    # Her phone is the mother_mobile on Diya's registration.
    assert guardians[0]["matches_registered_contact"] is True


def test_a_link_with_no_matching_registered_contact_is_still_allowed(client):
    """A parent who changed their number since registering is ordinary.

    The flag reports corroboration; it must not gate the link, or the app would
    lock out exactly the families whose details moved on.
    """
    s = school(client)

    response = link(client, s["asha"], s["kabir"], "nobody@example.com")

    assert response.status_code == 201, response.text
    assert response.json()[0]["matches_registered_contact"] is False


def test_the_principal_can_link_anyone(client):
    s = school(client)

    response = link(client, s["head"], s["rhea"], "nobody@example.com")

    assert response.status_code == 201, response.text


def test_a_teacher_cannot_link_a_pupil_outside_their_class(client):
    s = school(client)

    response = link(client, s["asha"], s["rhea"], "nobody@example.com")

    assert response.status_code == 404


def test_a_parent_cannot_link_themselves(client):
    """The one thing that must never work: claiming a child."""
    s = school(client)

    response = link(client, s["priya"], s["diya"], "+919876500010")

    assert response.status_code == 403


def test_a_parent_cannot_link_themselves_to_a_stranger_either(client):
    s = school(client)

    response = link(client, s["stranger"], s["rhea"], "nobody@example.com")

    assert response.status_code == 403


def test_linking_an_account_that_does_not_exist_says_so(client):
    s = school(client)

    response = link(client, s["asha"], s["diya"], "ghost@example.com")

    assert response.status_code == 404
    assert "has to sign up first" in response.json()["detail"]


def test_a_teacher_account_cannot_be_linked_as_a_parent(client):
    """They already see the pupil through their role; two kinds of access in
    one table would blur into each other."""
    s = school(client)

    response = link(client, s["asha"], s["diya"], "bela@example.com")

    assert response.status_code == 400
    assert "not as a parent" in response.json()["detail"]


def test_linking_twice_updates_the_relation_rather_than_failing(client):
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010", relation="Mother")

    response = link(client, s["asha"], s["diya"], "+919876500010", relation="Guardian")

    assert response.status_code == 201
    assert len(response.json()) == 1
    assert response.json()[0]["relation"] == "Guardian"


def test_unlinking_takes_the_access_away_but_leaves_the_account(client):
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010")

    removed = client.delete(
        f"{STUDENTS}/{s['diya']}/guardians/"
        + client.get(f"{STUDENTS}/{s['diya']}/guardians", headers=auth(s["asha"]))
        .json()[0]["user_id"],
        headers=auth(s["asha"]),
    )

    assert removed.status_code == 204
    assert client.get(STUDENTS, headers=auth(s["priya"])).json() == []
    # The login still works; there is just nothing to look at.
    assert client.get("/api/v1/auth/me", headers=auth(s["priya"])).status_code == 200


def test_a_parent_cannot_see_who_else_is_linked(client):
    """A family matter, and the app has no business reporting it."""
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010")

    response = client.get(
        f"{STUDENTS}/{s['diya']}/guardians", headers=auth(s["priya"])
    )

    assert response.status_code == 403


# --- What a linked parent can see -------------------------------------------


def test_a_linked_parent_sees_their_child_and_their_class(client):
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010")

    students = client.get(STUDENTS, headers=auth(s["priya"])).json()
    classes = client.get(CLASSES, headers=auth(s["priya"])).json()

    assert [p["name"] for p in students] == ["Diya"]
    assert [k["name"] for k in classes] == ["Nursery"]
    # Including who teaches it.
    assert classes[0]["teacher_name"] == "Asha Rao"


def test_a_linked_parent_does_not_see_the_classmates(client):
    """Kabir is in the same class and is somebody else's child."""
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010")

    students = client.get(STUDENTS, headers=auth(s["priya"])).json()

    assert [p["name"] for p in students] == ["Diya"]


def test_a_parent_with_two_children_sees_both(client):
    """Which is why the link is many-to-many, and why the dashboard needs a
    child picker."""
    s = school(client)
    link(client, s["asha"], s["diya"], "nobody@example.com")
    link(client, s["head"], s["rhea"], "nobody@example.com")

    students = client.get(STUDENTS, headers=auth(s["stranger"])).json()
    classes = client.get(CLASSES, headers=auth(s["stranger"])).json()

    assert {p["name"] for p in students} == {"Diya", "Rhea"}
    assert {k["name"] for k in classes} == {"Nursery", "Playgroup"}


def test_a_linked_parent_reads_their_childs_attendance(client):
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010")
    for day, mark in ((YESTERDAY, "A"), (TODAY, "P")):
        client.post(
            ATTENDANCE,
            json={
                "class_id": s["nursery"],
                "date": day,
                "entries": [{"student_id": s["diya"], "status": mark}],
            },
            headers=auth(s["asha"]),
        )

    history = client.get(
        ATTENDANCE, params={"student_id": s["diya"]}, headers=auth(s["priya"])
    )
    summary = client.get(
        f"{ATTENDANCE}/summary",
        params={"student_id": s["diya"]},
        headers=auth(s["priya"]),
    )

    assert history.status_code == 200, history.text
    assert [(r["date"], r["status"]) for r in history.json()] == [
        (TODAY, "P"),
        (YESTERDAY, "A"),
    ]
    assert summary.json()["percent_present"] == 50.0


def test_a_parent_cannot_read_another_childs_attendance(client):
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010")

    history = client.get(
        ATTENDANCE, params={"student_id": s["kabir"]}, headers=auth(s["priya"])
    )
    summary = client.get(
        f"{ATTENDANCE}/summary",
        params={"student_id": s["kabir"]},
        headers=auth(s["priya"]),
    )

    assert history.status_code == 404
    assert summary.status_code == 404


def test_asking_by_class_still_only_returns_their_own_child(client):
    """The leak this test was written to find.

    A parent can reach their child's class, so `?class_id=` alone came back
    with the **whole register** — every classmate's name and whether they were
    absent. Reaching the class is not permission to read the other children in
    it, so a guardian is narrowed to their own children whatever they ask for.
    """
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010")
    client.post(
        ATTENDANCE,
        json={
            "class_id": s["nursery"],
            "date": TODAY,
            "entries": [
                {"student_id": s["diya"], "status": "P"},
                {"student_id": s["kabir"], "status": "A"},
            ],
        },
        headers=auth(s["asha"]),
    )

    response = client.get(
        ATTENDANCE, params={"class_id": s["nursery"]}, headers=auth(s["priya"])
    )

    assert response.status_code == 200
    assert [r["student_name"] for r in response.json()] == ["Diya"]


def test_a_teacher_asking_by_class_still_gets_the_whole_register(client):
    """The narrowing above must not have narrowed the teacher too."""
    s = school(client)
    client.post(
        ATTENDANCE,
        json={
            "class_id": s["nursery"],
            "date": TODAY,
            "entries": [
                {"student_id": s["diya"], "status": "P"},
                {"student_id": s["kabir"], "status": "A"},
            ],
        },
        headers=auth(s["asha"]),
    )

    response = client.get(
        ATTENDANCE, params={"class_id": s["nursery"]}, headers=auth(s["asha"])
    )

    assert {r["student_name"] for r in response.json()} == {"Diya", "Kabir"}


def test_a_parent_cannot_read_the_class_roster(client):
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010")

    response = client.get(
        f"{CLASSES}/{s['nursery']}/roster", headers=auth(s["priya"])
    )

    # The roster is every pupil's name and roll number.
    assert response.status_code == 403


# --- What a parent must not change ------------------------------------------


def test_a_parent_cannot_change_the_class_colour(client):
    """Explicitly in the requirements: the colour stays as the teacher set it."""
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010")

    response = client.patch(
        f"{CLASSES}/{s['nursery']}",
        json={"color_slot": 7},
        headers=auth(s["priya"]),
    )

    assert response.status_code == 403
    assert client.get(CLASSES, headers=auth(s["priya"])).json()[0]["color_slot"] == 3


def test_a_parent_cannot_rename_or_delete_the_class(client):
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010")

    renamed = client.patch(
        f"{CLASSES}/{s['nursery']}", json={"name": "Mine"}, headers=auth(s["priya"])
    )
    deleted = client.delete(f"{CLASSES}/{s['nursery']}", headers=auth(s["priya"]))

    assert renamed.status_code == 403
    assert deleted.status_code == 403
    # Still there, still called Nursery.
    assert client.get(CLASSES, headers=auth(s["priya"])).json()[0]["name"] == "Nursery"


def test_a_parent_cannot_register_a_student(client):
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010")

    response = client.post(
        STUDENTS,
        json={
            "class_id": s["nursery"],
            "name": "Invented",
            "date_of_birth": "2021-04-12",
            "gender": "Female",
            "address": "12 Rose Lane",
        },
        headers=auth(s["priya"]),
    )

    assert response.status_code == 403


def test_a_parent_reaches_no_teacher_records_or_subjects(client):
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010")

    assert client.get(TEACHERS, headers=auth(s["priya"])).status_code == 403
    assert client.get(f"{TEACHERS}/me", headers=auth(s["priya"])).status_code == 403
    assert client.get(SUBJECTS, headers=auth(s["priya"])).status_code == 403


# --- Cascades ---------------------------------------------------------------


def test_deleting_the_pupil_removes_the_link(client):
    """Otherwise the parent's list points at a child who is gone."""
    s = school(client)
    link(client, s["asha"], s["diya"], "+919876500010")

    # Deleting the class deletes its pupils. Sent by the principal, whose
    # delete takes effect at once — the teacher's would only raise a request,
    # and this test is about what happens once the pupil is actually gone.
    deleted = client.delete(f"{CLASSES}/{s['nursery']}", headers=auth(s["head"]))
    assert deleted.status_code == 200, deleted.text
    assert deleted.json()["status"] == "done"

    assert client.get(STUDENTS, headers=auth(s["priya"])).json() == []
    assert client.get(CLASSES, headers=auth(s["priya"])).json() == []
