"""What a teacher may only ask for, and what happens when the principal answers.

Phase 5. Four acts moved: creating a class, deleting one, registering a pupil
and removing one are the principal's to do outright, and a teacher's version of
each raises a request instead.

The assertion this file exists for is the negative one, and it is repeated in
every shape: **nothing happens until the request is granted.** Not a greyed-out
row, not a provisional pupil, not a count that includes something nobody has
agreed to. A teacher's dashboard after they ask looks exactly as it did before.

The rest is the paperwork around that: who is notified, who may answer, what
the teacher is told afterwards, and what happens when two principals reach for
the same request.
"""

import helpers
from helpers import (
    ACCOUNT_TYPE_PRINCIPAL,
    ACCOUNT_TYPE_STUDENT,
    ACCOUNT_TYPE_TEACHER,
    CLASSES,
    STUDENTS,
    auth,
    signup,
)

REQUESTS = "/api/v1/requests"
NOTIFICATIONS = "/api/v1/notifications"


def staff(client) -> dict[str, str]:
    """Asha teaching, Meera in the office."""
    return {
        "asha": signup(
            client, "Asha Rao", "asha@example.com", ACCOUNT_TYPE_TEACHER
        ),
        "head": signup(
            client, "Meera Iyer", "head@example.com", ACCOUNT_TYPE_PRINCIPAL
        ),
    }


def a_pupil(class_id: str, name: str = "Diya") -> dict:
    return {
        "class_id": class_id,
        "name": name,
        "date_of_birth": "2021-04-12",
        "gender": "Female",
        "address": "12 Rose Lane",
    }


def pending(client, token: str) -> list[dict]:
    response = client.get(
        REQUESTS, params={"status": "pending"}, headers=auth(token)
    )
    assert response.status_code == 200, response.text
    return response.json()


def notices(client, token: str) -> dict:
    response = client.get(NOTIFICATIONS, headers=auth(token))
    assert response.status_code == 200, response.text
    return response.json()


# --- Creating a class ---------------------------------------------------------


def test_a_teachers_new_class_does_not_exist_until_it_is_approved(client):
    """The whole design in one test."""
    s = staff(client)

    asked = client.post(
        CLASSES, json={"name": "KG", "color_slot": 2}, headers=auth(s["asha"])
    )

    assert asked.status_code == 202, asked.text
    body = asked.json()
    assert body["status"] == "pending"
    assert body["school_class"] is None
    assert body["request"]["summary"] == 'the new class "KG"'

    # Nobody can see a class, because there is not one.
    assert client.get(CLASSES, headers=auth(s["asha"])).json() == []
    assert client.get(CLASSES, headers=auth(s["head"])).json() == []


def test_approving_creates_the_class_under_the_teacher_who_asked(client):
    s = staff(client)
    client.post(CLASSES, json={"name": "KG"}, headers=auth(s["asha"]))

    [request] = pending(client, s["head"])
    granted = client.post(
        f"{REQUESTS}/{request['id']}/approve", headers=auth(s["head"])
    )

    assert granted.status_code == 200, granted.text
    created = granted.json()["school_class"]
    assert created["name"] == "KG"
    assert created["teacher_name"] == "Asha Rao"

    # It is Asha's class, indistinguishable from one she had made herself.
    assert [c["name"] for c in client.get(CLASSES, headers=auth(s["asha"])).json()] == [
        "KG"
    ]


def test_rejecting_leaves_nothing_behind_but_the_answer(client):
    s = staff(client)
    client.post(CLASSES, json={"name": "KG"}, headers=auth(s["asha"]))
    [request] = pending(client, s["head"])

    refused = client.post(
        f"{REQUESTS}/{request['id']}/reject",
        json={"note": "We are not opening a KG this year"},
        headers=auth(s["head"]),
    )

    assert refused.status_code == 200, refused.text
    assert refused.json()["status"] == "rejected"
    assert client.get(CLASSES, headers=auth(s["asha"])).json() == []

    # The row stays, answered. A request that simply vanished would read as a
    # bug the teacher then repeats.
    mine = client.get(REQUESTS, headers=auth(s["asha"])).json()
    assert [r["status"] for r in mine] == ["rejected"]
    assert mine[0]["decision_note"] == "We are not opening a KG this year"


def test_the_same_request_cannot_be_answered_twice(client):
    """Two principals opening the same queue is ordinary, not rare."""
    s = staff(client)
    other = signup(
        client, "Vikram Shah", "vikram@example.com", ACCOUNT_TYPE_PRINCIPAL
    )
    client.post(CLASSES, json={"name": "KG"}, headers=auth(s["asha"]))
    [request] = pending(client, s["head"])

    first = client.post(
        f"{REQUESTS}/{request['id']}/approve", headers=auth(s["head"])
    )
    second = client.post(
        f"{REQUESTS}/{request['id']}/approve", headers=auth(other)
    )

    assert first.status_code == 200
    assert second.status_code == 409
    assert "already approved" in second.json()["detail"]
    # And exactly one class came of it.
    assert len(client.get(CLASSES, headers=auth(s["asha"])).json()) == 1


def test_asking_twice_for_the_same_class_is_refused(client):
    """What a teacher does when nothing appears to have happened."""
    s = staff(client)
    client.post(CLASSES, json={"name": "KG"}, headers=auth(s["asha"]))

    again = client.post(CLASSES, json={"name": "KG"}, headers=auth(s["asha"]))

    assert again.status_code == 409
    assert "still waiting for the principal" in again.json()["detail"]
    assert len(pending(client, s["head"])) == 1


def test_a_name_taken_while_the_request_waited_is_caught_at_approval(client):
    """The payload is validated again when it runs, not only when it is made."""
    s = staff(client)
    client.post(CLASSES, json={"name": "KG"}, headers=auth(s["asha"]))
    [request] = pending(client, s["head"])

    # The principal makes Asha a "KG" directly in the meantime.
    helpers.make_class(client, s["asha"], "KG", principal=s["head"])

    granted = client.post(
        f"{REQUESTS}/{request['id']}/approve", headers=auth(s["head"])
    )

    assert granted.status_code == 409
    assert 'A class called "KG" already exists' in granted.json()["detail"]


# --- Deleting a class ---------------------------------------------------------


def test_a_teachers_delete_leaves_the_class_and_its_pupils_alone(client):
    s = staff(client)
    class_id = helpers.make_class(
        client, s["asha"], "Nursery", principal=s["head"]
    )
    client.post(STUDENTS, json=a_pupil(class_id), headers=auth(s["head"]))

    asked = client.delete(f"{CLASSES}/{class_id}", headers=auth(s["asha"]))

    assert asked.status_code == 202, asked.text
    assert asked.json()["status"] == "pending"
    # The summary counts what would go, so the principal decides knowing.
    assert asked.json()["request"]["summary"] == (
        'removal of the class "Nursery" and its 1 student'
    )

    # Still there, pupil included.
    assert len(client.get(CLASSES, headers=auth(s["asha"])).json()) == 1
    assert len(client.get(STUDENTS, headers=auth(s["asha"])).json()) == 1


def test_approving_the_delete_takes_the_class_and_its_pupils(client):
    s = staff(client)
    class_id = helpers.make_class(
        client, s["asha"], "Nursery", principal=s["head"]
    )
    client.post(STUDENTS, json=a_pupil(class_id), headers=auth(s["head"]))
    client.delete(f"{CLASSES}/{class_id}", headers=auth(s["asha"]))

    [request] = pending(client, s["head"])
    granted = client.post(
        f"{REQUESTS}/{request['id']}/approve", headers=auth(s["head"])
    )

    assert granted.status_code == 200, granted.text
    assert client.get(CLASSES, headers=auth(s["asha"])).json() == []
    assert client.get(STUDENTS, headers=auth(s["asha"])).json() == []


def test_approving_a_delete_for_a_class_already_gone_says_so(client):
    s = staff(client)
    class_id = helpers.make_class(
        client, s["asha"], "Nursery", principal=s["head"]
    )
    client.delete(f"{CLASSES}/{class_id}", headers=auth(s["asha"]))
    [request] = pending(client, s["head"])

    # The principal deletes it themselves before getting to the queue.
    client.delete(f"{CLASSES}/{class_id}", headers=auth(s["head"]))

    granted = client.post(
        f"{REQUESTS}/{request['id']}/approve", headers=auth(s["head"])
    )

    assert granted.status_code == 409
    assert "already been deleted" in granted.json()["detail"]
    # Rejecting is still open, so the queue can be cleared.
    assert (
        client.post(
            f"{REQUESTS}/{request['id']}/reject",
            json={"note": "Already done"},
            headers=auth(s["head"]),
        ).status_code
        == 200
    )


# --- Students -----------------------------------------------------------------


def test_a_teachers_registration_waits_and_then_lands(client):
    s = staff(client)
    class_id = helpers.make_class(
        client, s["asha"], "Nursery", principal=s["head"]
    )

    asked = client.post(
        STUDENTS, json=a_pupil(class_id), headers=auth(s["asha"])
    )

    assert asked.status_code == 202, asked.text
    assert asked.json()["request"]["summary"] == 'registration of Diya in "Nursery"'
    assert client.get(STUDENTS, headers=auth(s["asha"])).json() == []

    [request] = pending(client, s["head"])
    granted = client.post(
        f"{REQUESTS}/{request['id']}/approve", headers=auth(s["head"])
    )

    assert granted.status_code == 200, granted.text
    assert granted.json()["student"]["name"] == "Diya"
    # With a roll number, like any other registration.
    assert granted.json()["student"]["roll_number"] == 1


def test_a_teachers_removal_waits_and_then_takes_the_pupil(client):
    s = staff(client)
    class_id = helpers.make_class(
        client, s["asha"], "Nursery", principal=s["head"]
    )
    pupil = client.post(
        STUDENTS, json=a_pupil(class_id), headers=auth(s["head"])
    ).json()["student"]

    asked = client.delete(
        f"{STUDENTS}/{pupil['student_id']}", headers=auth(s["asha"])
    )

    assert asked.status_code == 202, asked.text
    assert asked.json()["request"]["summary"] == 'removal of Diya from "Nursery"'
    assert len(client.get(STUDENTS, headers=auth(s["asha"])).json()) == 1

    [request] = pending(client, s["head"])
    client.post(f"{REQUESTS}/{request['id']}/approve", headers=auth(s["head"]))

    assert client.get(STUDENTS, headers=auth(s["asha"])).json() == []


def test_the_principal_removes_a_pupil_outright(client):
    s = staff(client)
    class_id = helpers.make_class(
        client, s["asha"], "Nursery", principal=s["head"]
    )
    pupil = client.post(
        STUDENTS, json=a_pupil(class_id), headers=auth(s["head"])
    ).json()["student"]

    removed = client.delete(
        f"{STUDENTS}/{pupil['student_id']}", headers=auth(s["head"])
    )

    assert removed.status_code == 200, removed.text
    assert removed.json()["status"] == "done"
    assert client.get(STUDENTS, headers=auth(s["head"])).json() == []
    # Nothing went to the queue.
    assert pending(client, s["head"]) == []


def test_a_parent_cannot_remove_a_pupil(client):
    """The guard that matters most on this endpoint."""
    s = staff(client)
    class_id = helpers.make_class(
        client, s["asha"], "Nursery", principal=s["head"]
    )
    pupil = client.post(
        STUDENTS, json=a_pupil(class_id), headers=auth(s["head"])
    ).json()["student"]
    parent = signup(
        client, "Priya Rao", "priya@example.com", ACCOUNT_TYPE_STUDENT
    )
    client.post(
        f"{STUDENTS}/{pupil['student_id']}/guardians",
        json={"identifier": "priya@example.com", "relation": "Mother"},
        headers=auth(s["head"]),
    )

    removed = client.delete(
        f"{STUDENTS}/{pupil['student_id']}", headers=auth(parent)
    )

    assert removed.status_code == 403
    assert len(client.get(STUDENTS, headers=auth(s["head"])).json()) == 1


# --- Who sees the queue -------------------------------------------------------


def test_a_teacher_sees_only_their_own_requests(client):
    s = staff(client)
    bela = signup(client, "Bela Nair", "bela@example.com", ACCOUNT_TYPE_TEACHER)
    client.post(CLASSES, json={"name": "KG"}, headers=auth(s["asha"]))
    client.post(CLASSES, json={"name": "Playgroup"}, headers=auth(bela))

    assert [r["summary"] for r in client.get(REQUESTS, headers=auth(s["asha"])).json()] == [
        'the new class "KG"'
    ]
    assert [r["summary"] for r in client.get(REQUESTS, headers=auth(bela)).json()] == [
        'the new class "Playgroup"'
    ]
    # The principal sees both — that is the queue.
    assert len(client.get(REQUESTS, headers=auth(s["head"])).json()) == 2


def test_a_teacher_cannot_approve_anything(client):
    s = staff(client)
    bela = signup(client, "Bela Nair", "bela@example.com", ACCOUNT_TYPE_TEACHER)
    client.post(CLASSES, json={"name": "KG"}, headers=auth(bela))
    [request] = pending(client, s["head"])

    assert (
        client.post(
            f"{REQUESTS}/{request['id']}/approve", headers=auth(s["asha"])
        ).status_code
        == 403
    )
    # Not even their own.
    assert (
        client.post(
            f"{REQUESTS}/{request['id']}/approve", headers=auth(bela)
        ).status_code
        == 403
    )


def test_a_parent_reaches_no_part_of_the_queue(client):
    s = staff(client)
    parent = signup(
        client, "Priya Rao", "priya@example.com", ACCOUNT_TYPE_STUDENT
    )

    assert client.get(REQUESTS, headers=auth(parent)).status_code == 403


def test_the_payload_is_never_exposed(client):
    """A request carries a whole register-student form — address, both
    parents' numbers. The queue only ever needs the summary to decide from."""
    s = staff(client)
    class_id = helpers.make_class(
        client, s["asha"], "Nursery", principal=s["head"]
    )
    client.post(STUDENTS, json=a_pupil(class_id), headers=auth(s["asha"]))

    [request] = pending(client, s["head"])

    assert "payload" not in request
    assert "12 Rose Lane" not in str(request)


# --- Notifications ------------------------------------------------------------


def test_raising_a_request_notifies_every_principal(client):
    s = staff(client)
    other = signup(
        client, "Vikram Shah", "vikram@example.com", ACCOUNT_TYPE_PRINCIPAL
    )
    class_id = helpers.make_class(
        client, s["asha"], "Nursery", principal=s["head"]
    )

    client.delete(f"{CLASSES}/{class_id}", headers=auth(s["asha"]))

    for token in (s["head"], other):
        body = notices(client, token)
        assert body["unread"] == 1
        assert body["pending_requests"] == 1
        [line] = body["notifications"]
        assert line["message"] == (
            'Asha Rao requests approval for removal of the class "Nursery"'
        )
        # The source is the teacher: this notice is one person asking another
        # for something, not the app saying something.
        assert line["source"] == "Asha Rao"
        assert line["audience"] == "user"
        # Actionable — the principal can decide from the tab itself.
        assert line["request_id"] is not None
        # Date and time are stored apart, as the tab reads them.
        assert line["date"].count("-") == 2
        assert line["time"].count(":") == 2


def test_the_teacher_is_told_either_way(client):
    s = staff(client)
    client.post(CLASSES, json={"name": "KG"}, headers=auth(s["asha"]))
    [request] = pending(client, s["head"])

    client.post(f"{REQUESTS}/{request['id']}/approve", headers=auth(s["head"]))

    [line] = notices(client, s["asha"])["notifications"]
    assert line["message"] == 'Meera Iyer approved your request for the new class "KG"'
    assert line["source"] == "Meera Iyer"


def test_a_rejection_carries_the_reason(client):
    """"Rejected" on its own is how a teacher asks again tomorrow."""
    s = staff(client)
    client.post(CLASSES, json={"name": "KG"}, headers=auth(s["asha"]))
    [request] = pending(client, s["head"])

    client.post(
        f"{REQUESTS}/{request['id']}/reject",
        json={"note": "No room this year"},
        headers=auth(s["head"]),
    )

    [line] = notices(client, s["asha"])["notifications"]
    assert line["message"] == (
        'Meera Iyer turned down your request for the new class "KG" '
        "— No room this year"
    )


def test_a_teacher_is_never_told_the_queue_depth(client):
    s = staff(client)
    bela = signup(client, "Bela Nair", "bela@example.com", ACCOUNT_TYPE_TEACHER)
    client.post(CLASSES, json={"name": "KG"}, headers=auth(bela))

    assert notices(client, s["head"])["pending_requests"] == 1
    assert notices(client, s["asha"])["pending_requests"] == 0
    assert notices(client, bela)["pending_requests"] == 0


def test_marking_read_clears_the_badge(client):
    s = staff(client)
    client.post(CLASSES, json={"name": "KG"}, headers=auth(s["asha"]))

    [line] = notices(client, s["head"])["notifications"]
    read = client.post(
        f"{NOTIFICATIONS}/{line['id']}/read", headers=auth(s["head"])
    )

    assert read.status_code == 200, read.text
    assert read.json()["read_at"] is not None
    assert notices(client, s["head"])["unread"] == 0


def test_one_principal_marking_read_does_not_clear_it_for_the_other(client):
    """Why the fan-out is a row each rather than one shared broadcast."""
    s = staff(client)
    other = signup(
        client, "Vikram Shah", "vikram@example.com", ACCOUNT_TYPE_PRINCIPAL
    )
    client.post(CLASSES, json={"name": "KG"}, headers=auth(s["asha"]))

    [line] = notices(client, s["head"])["notifications"]
    client.post(f"{NOTIFICATIONS}/{line['id']}/read", headers=auth(s["head"]))

    assert notices(client, s["head"])["unread"] == 0
    assert notices(client, other)["unread"] == 1


def test_somebody_elses_notification_reads_as_missing(client):
    s = staff(client)
    client.post(CLASSES, json={"name": "KG"}, headers=auth(s["asha"]))
    [line] = notices(client, s["head"])["notifications"]

    response = client.post(
        f"{NOTIFICATIONS}/{line['id']}/read", headers=auth(s["asha"])
    )

    # 404, not 403: the endpoint must not be usable to count what the school
    # is being told.
    assert response.status_code == 404


def test_mark_all_read_clears_the_lot(client):
    s = staff(client)
    bela = signup(client, "Bela Nair", "bela@example.com", ACCOUNT_TYPE_TEACHER)
    client.post(CLASSES, json={"name": "KG"}, headers=auth(s["asha"]))
    client.post(CLASSES, json={"name": "Playgroup"}, headers=auth(bela))

    assert notices(client, s["head"])["unread"] == 2

    cleared = client.post(f"{NOTIFICATIONS}/read", headers=auth(s["head"]))

    assert cleared.status_code == 200, cleared.text
    assert cleared.json()["unread"] == 0
    # The lines are still there to read back; only the badge went.
    assert len(cleared.json()["notifications"]) == 2
