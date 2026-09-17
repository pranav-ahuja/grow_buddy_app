"""Taking the register, and who may read it back.

The register is a class on a day, marked in one request. The things worth
pinning: a correction updates rather than duplicating, a pupil from another
class cannot be marked, and the read scope matches the rest of the app — a
teacher's own classes, the whole school for the principal.
"""

from datetime import date, timedelta

SIGNUP = "/api/v1/auth/signup"
CLASSES = "/api/v1/classes"
STUDENTS = "/api/v1/students"
ATTENDANCE = "/api/v1/attendance"

TEACHER = 0
STUDENT = 1
PRINCIPAL = 2

TODAY = date.today().isoformat()
YESTERDAY = (date.today() - timedelta(days=1)).isoformat()
TOMORROW = (date.today() + timedelta(days=1)).isoformat()


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def signup(client, name: str, email: str, account_type: int) -> str:
    response = client.post(
        SIGNUP,
        json={
            "full_name": name,
            "identifier": email,
            "password": "supersecret123",
            "account_type": account_type,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["access_token"]


def make_class(client, token: str, name: str) -> str:
    response = client.post(
        CLASSES, json={"name": name, "color_slot": 0}, headers=auth(token)
    )
    assert response.status_code == 201, response.text
    return response.json()["class_id"]


def add_student(client, token: str, class_id: str, name: str) -> str:
    response = client.post(
        STUDENTS,
        json={
            "class_id": class_id,
            "name": name,
            "date_of_birth": "2021-04-12",
            "gender": "Female",
            "address": "12 Rose Lane",
        },
        headers=auth(token),
    )
    assert response.status_code == 201, response.text
    return response.json()["student_id"]


def a_class_of_two(client):
    """Asha with two pupils, Bela with one, and a principal."""
    asha = signup(client, "Asha Rao", "asha@example.com", TEACHER)
    bela = signup(client, "Bela Nair", "bela@example.com", TEACHER)
    head = signup(client, "Meera Iyer", "head@example.com", PRINCIPAL)

    nursery = make_class(client, asha, "Nursery")
    diya = add_student(client, asha, nursery, "Diya")
    kabir = add_student(client, asha, nursery, "Kabir")

    playgroup = make_class(client, bela, "Playgroup")
    rhea = add_student(client, bela, playgroup, "Rhea")

    return {
        "asha": asha,
        "bela": bela,
        "head": head,
        "nursery": nursery,
        "playgroup": playgroup,
        "diya": diya,
        "kabir": kabir,
        "rhea": rhea,
    }


def test_a_teacher_takes_the_register(client):
    s = a_class_of_two(client)

    response = client.post(
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

    assert response.status_code == 200, response.text
    marks = {row["student_name"]: row["status"] for row in response.json()}
    assert marks == {"Diya": "P", "Kabir": "A"}


def test_a_correction_updates_rather_than_duplicating(client):
    """The normal case, not an error: a child marked absent by mistake."""
    s = a_class_of_two(client)
    register = {
        "class_id": s["nursery"],
        "date": TODAY,
        "entries": [{"student_id": s["diya"], "status": "A"}],
    }
    client.post(ATTENDANCE, json=register, headers=auth(s["asha"]))

    register["entries"][0]["status"] = "P"
    response = client.post(ATTENDANCE, json=register, headers=auth(s["asha"]))

    assert response.status_code == 200, response.text
    rows = [r for r in response.json() if r["student_name"] == "Diya"]
    assert len(rows) == 1, "a second row would mean two answers for one day"
    assert rows[0]["status"] == "P"


def test_lower_case_marks_are_accepted(client):
    s = a_class_of_two(client)

    response = client.post(
        ATTENDANCE,
        json={
            "class_id": s["nursery"],
            "date": TODAY,
            "entries": [{"student_id": s["diya"], "status": "p"}],
        },
        headers=auth(s["asha"]),
    )

    assert response.status_code == 200, response.text
    assert response.json()[0]["status"] == "P"


def test_an_unknown_mark_is_refused(client):
    s = a_class_of_two(client)

    response = client.post(
        ATTENDANCE,
        json={
            "class_id": s["nursery"],
            "date": TODAY,
            "entries": [{"student_id": s["diya"], "status": "X"}],
        },
        headers=auth(s["asha"]),
    )

    assert response.status_code == 422
    assert "P" in response.json()["detail"]


def test_a_pupil_from_another_class_cannot_be_marked(client):
    """Otherwise a mark lands on a register the child was never on."""
    s = a_class_of_two(client)

    response = client.post(
        ATTENDANCE,
        json={
            "class_id": s["nursery"],
            "date": TODAY,
            "entries": [{"student_id": s["rhea"], "status": "P"}],
        },
        headers=auth(s["asha"]),
    )

    assert response.status_code == 400
    assert s["rhea"] in response.json()["detail"]


def test_a_teacher_cannot_mark_another_teachers_class(client):
    s = a_class_of_two(client)

    response = client.post(
        ATTENDANCE,
        json={
            "class_id": s["playgroup"],
            "date": TODAY,
            "entries": [{"student_id": s["rhea"], "status": "P"}],
        },
        headers=auth(s["asha"]),
    )

    assert response.status_code == 404


def test_the_same_pupil_twice_in_one_register_is_refused(client):
    s = a_class_of_two(client)

    response = client.post(
        ATTENDANCE,
        json={
            "class_id": s["nursery"],
            "date": TODAY,
            "entries": [
                {"student_id": s["diya"], "status": "P"},
                {"student_id": s["diya"], "status": "A"},
            ],
        },
        headers=auth(s["asha"]),
    )

    assert response.status_code == 422
    assert "twice" in response.json()["detail"]


def test_attendance_cannot_be_taken_for_a_future_date(client):
    s = a_class_of_two(client)

    response = client.post(
        ATTENDANCE,
        json={
            "class_id": s["nursery"],
            "date": TOMORROW,
            "entries": [{"student_id": s["diya"], "status": "P"}],
        },
        headers=auth(s["asha"]),
    )

    assert response.status_code == 422


def test_the_principal_does_not_take_the_register(client):
    """Reading is theirs; marking is a first-hand observation."""
    s = a_class_of_two(client)

    response = client.post(
        ATTENDANCE,
        json={
            "class_id": s["nursery"],
            "date": TODAY,
            "entries": [{"student_id": s["diya"], "status": "P"}],
        },
        headers=auth(s["head"]),
    )

    assert response.status_code == 403


def test_the_principal_reads_any_register(client):
    s = a_class_of_two(client)
    client.post(
        ATTENDANCE,
        json={
            "class_id": s["nursery"],
            "date": TODAY,
            "entries": [{"student_id": s["diya"], "status": "P"}],
        },
        headers=auth(s["asha"]),
    )

    response = client.get(
        ATTENDANCE, params={"class_id": s["nursery"]}, headers=auth(s["head"])
    )

    assert response.status_code == 200, response.text
    assert [r["student_name"] for r in response.json()] == ["Diya"]


def test_a_teacher_cannot_read_another_teachers_register(client):
    s = a_class_of_two(client)

    response = client.get(
        ATTENDANCE, params={"class_id": s["playgroup"]}, headers=auth(s["asha"])
    )

    assert response.status_code == 404


def test_reading_without_a_subject_is_refused(client):
    """Neither class_id nor student_id is a request nobody means to make."""
    s = a_class_of_two(client)

    response = client.get(ATTENDANCE, headers=auth(s["asha"]))

    assert response.status_code == 400
    assert "class_id or student_id" in response.json()["detail"]


def test_one_pupils_history_across_days(client):
    s = a_class_of_two(client)
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

    response = client.get(
        ATTENDANCE, params={"student_id": s["diya"]}, headers=auth(s["asha"])
    )

    assert response.status_code == 200, response.text
    # Newest first.
    assert [(r["date"], r["status"]) for r in response.json()] == [
        (TODAY, "P"),
        (YESTERDAY, "A"),
    ]


def test_filtering_a_register_to_one_day(client):
    s = a_class_of_two(client)
    for day in (YESTERDAY, TODAY):
        client.post(
            ATTENDANCE,
            json={
                "class_id": s["nursery"],
                "date": day,
                "entries": [{"student_id": s["diya"], "status": "P"}],
            },
            headers=auth(s["asha"]),
        )

    response = client.get(
        ATTENDANCE,
        params={"class_id": s["nursery"], "date": YESTERDAY},
        headers=auth(s["asha"]),
    )

    assert [r["date"] for r in response.json()] == [YESTERDAY]


def test_the_summary_counts_days(client):
    s = a_class_of_two(client)
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

    response = client.get(
        f"{ATTENDANCE}/summary",
        params={"student_id": s["diya"]},
        headers=auth(s["head"]),
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["student_name"] == "Diya"
    assert body["days_recorded"] == 2
    assert body["present"] == 1
    assert body["absent"] == 1
    assert body["percent_present"] == 50.0


def test_an_unmarked_pupil_has_no_percentage_rather_than_zero(client):
    """"0% attendance" is a claim; "not recorded" is the truth."""
    s = a_class_of_two(client)

    response = client.get(
        f"{ATTENDANCE}/summary",
        params={"student_id": s["kabir"]},
        headers=auth(s["asha"]),
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["days_recorded"] == 0
    assert body["percent_present"] is None


def test_deleting_a_class_takes_its_attendance_with_it(client):
    """The cascade, which is what keeps orphan marks out of the summaries."""
    s = a_class_of_two(client)
    client.post(
        ATTENDANCE,
        json={
            "class_id": s["nursery"],
            "date": TODAY,
            "entries": [{"student_id": s["diya"], "status": "P"}],
        },
        headers=auth(s["asha"]),
    )

    assert (
        client.delete(f"{CLASSES}/{s['nursery']}", headers=auth(s["asha"])).status_code
        == 204
    )

    # The pupil is gone with the class, so their register is unreachable.
    response = client.get(
        ATTENDANCE, params={"student_id": s["diya"]}, headers=auth(s["asha"])
    )
    assert response.status_code == 404


def test_a_student_account_reaches_no_registers(client):
    pupil = signup(client, "Aarav Sharma", "pupil@example.com", STUDENT)

    response = client.get(
        ATTENDANCE, params={"class_id": "CL_000001"}, headers=auth(pupil)
    )

    assert response.status_code == 403
