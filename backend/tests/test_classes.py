from sqlalchemy import delete

from app.database import get_db
from app.main import app
from app.models import OtpCode, Student, Teacher

CLASSES = "/api/v1/classes"
STUDENTS = "/api/v1/students"
OTP_REQUEST = "/api/v1/auth/otp/request"
OTP_VERIFY = "/api/v1/auth/otp/verify"
PROFILE = "/api/v1/auth/me"
SIGNUP = "/api/v1/auth/signup"


def _db():
    return next(app.dependency_overrides[get_db]())


def _phone_login(client, phone: str) -> dict[str, str]:
    """Signs in with a phone number and returns the auth header.

    Called twice with the same number, this is two devices on one account —
    each gets its own token, but both tokens belong to the same user.
    """
    # The OTP resend cooldown would refuse a second code for the same number
    # straight away; clearing the codes stands in for waiting it out.
    db = _db()
    db.execute(delete(OtpCode).where(OtpCode.phone == phone))
    db.commit()
    db.close()

    code = client.post(OTP_REQUEST, json={"phone": phone}).json()["debug_otp"]
    token = client.post(OTP_VERIFY, json={"phone": phone, "otp": code}).json()[
        "access_token"
    ]
    return {"Authorization": f"Bearer {token}"}


def _teacher(client, phone: str) -> dict[str, str]:
    """A phone login that has picked "teacher" on the profile screen."""
    headers = _phone_login(client, phone)
    client.patch(PROFILE, json={"account_type": 0}, headers=headers)
    return headers


def _student(name: str = "Aarav", **overrides) -> dict:
    return {
        "name": name,
        "date_of_birth": "2021-04-12",
        "gender": "Male",
        "address": "12 MG Road, Pune",
        "mother_name": "Meera Sharma",
        "mother_mobile": "9876543210",
        "mother_email": "meera@example.com",
        "father_name": "Rohan Sharma",
        "father_mobile": "9876500000",
        "father_email": "rohan@example.com",
        **overrides,
    }


# --- Ids ---------------------------------------------------------------------


def test_every_table_hands_out_readable_ids(client):
    signup = client.post(
        SIGNUP,
        json={
            "full_name": "Asha",
            "identifier": "asha@example.com",
            "password": "correct-horse",
            "account_type": 0,
        },
    ).json()
    headers = {"Authorization": f"Bearer {signup['access_token']}"}

    assert signup["user"]["user_id"] == "U_000001"
    assert signup["user"]["role"] == "teacher"
    assert len(signup["user"]["uuid"]) == 36

    nursery = client.post(CLASSES, json={"name": "Nursery"}, headers=headers).json()
    assert nursery["class_id"] == "CL_000001"

    student = client.post(
        STUDENTS, json=_student(class_id=nursery["class_id"]), headers=headers
    ).json()
    assert student["student_id"] == "ST_000001"

    db = _db()
    teacher = db.query(Teacher).one()
    assert (teacher.teacher_id, teacher.user_id) == ("TR_000001", "U_000001")
    db.close()


def test_only_teachers_have_classes(client):
    headers = _phone_login(client, "+919100000020")
    client.patch(PROFILE, json={"account_type": 1}, headers=headers)

    response = client.get(CLASSES, headers=headers)
    assert response.status_code == 403


# --- Classes -----------------------------------------------------------------


def test_a_class_added_on_one_device_shows_on_another(client):
    phone = _teacher(client, "+919100000001")
    emulator = _phone_login(client, "+919100000001")

    created = client.post(CLASSES, json={"name": "Nursery", "color_slot": 3}, headers=phone)
    assert created.status_code == 201

    listed = client.get(CLASSES, headers=emulator).json()
    assert [(c["name"], c["color_slot"]) for c in listed] == [("Nursery", 3)]


def test_a_new_teacher_starts_with_no_classes(client):
    headers = _teacher(client, "+919100000002")
    assert client.get(CLASSES, headers=headers).json() == []


def test_classes_are_private_to_their_teacher(client):
    teacher_a = _teacher(client, "+919100000003")
    teacher_b = _teacher(client, "+919100000004")

    created = client.post(CLASSES, json={"name": "KG"}, headers=teacher_a).json()

    assert client.get(CLASSES, headers=teacher_b).json() == []
    # Someone else's class reads as missing, not forbidden.
    url = f"{CLASSES}/{created['class_id']}"
    assert client.patch(url, json={"name": "Stolen"}, headers=teacher_b).status_code == 404
    assert client.delete(url, headers=teacher_b).status_code == 404
    assert client.get(f"{url}/roster", headers=teacher_b).status_code == 404


def test_two_teachers_can_both_have_a_nursery(client):
    teacher_a = _teacher(client, "+919100000005")
    teacher_b = _teacher(client, "+919100000006")

    assert client.post(CLASSES, json={"name": "Nursery"}, headers=teacher_a).status_code == 201
    assert client.post(CLASSES, json={"name": "Nursery"}, headers=teacher_b).status_code == 201


def test_duplicate_class_names_are_refused_ignoring_case(client):
    headers = _teacher(client, "+919100000007")
    client.post(CLASSES, json={"name": "Nursery"}, headers=headers)

    duplicate = client.post(CLASSES, json={"name": "  nursery "}, headers=headers)
    assert duplicate.status_code == 409
    assert duplicate.json()["detail"] == 'A class called "nursery" already exists'


def test_edit_class_changes_name_and_colour_together(client):
    headers = _teacher(client, "+919100000008")
    created = client.post(CLASSES, json={"name": "Daycare"}, headers=headers).json()

    edited = client.patch(
        f"{CLASSES}/{created['class_id']}",
        json={"name": "Day Care", "color_slot": 6},
        headers=headers,
    ).json()
    assert (edited["name"], edited["color_slot"]) == ("Day Care", 6)


def test_edit_class_rejects_an_out_of_range_colour(client):
    headers = _teacher(client, "+919100000010")
    created = client.post(CLASSES, json={"name": "KG"}, headers=headers).json()

    response = client.patch(
        f"{CLASSES}/{created['class_id']}", json={"color_slot": 9}, headers=headers
    )
    assert response.status_code == 422


def test_deleting_a_class_deletes_its_students(client):
    headers = _teacher(client, "+919100000014")
    nursery = client.post(CLASSES, json={"name": "Nursery"}, headers=headers).json()
    kg = client.post(CLASSES, json={"name": "KG"}, headers=headers).json()
    client.post(STUDENTS, json=_student(class_id=nursery["class_id"]), headers=headers)
    client.post(STUDENTS, json=_student("Diya", class_id=kg["class_id"]), headers=headers)

    response = client.delete(f"{CLASSES}/{nursery['class_id']}", headers=headers)
    assert response.status_code == 204

    remaining = client.get(STUDENTS, headers=headers).json()
    assert [s["name"] for s in remaining] == ["Diya"]


# --- Students ----------------------------------------------------------------


def test_a_student_needs_a_class(client):
    headers = _teacher(client, "+919100000030")
    response = client.post(STUDENTS, json=_student(), headers=headers)
    assert response.status_code == 422


def test_a_student_needs_a_date_of_birth_in_the_past(client):
    headers = _teacher(client, "+919100000031")
    nursery = client.post(CLASSES, json={"name": "Nursery"}, headers=headers).json()

    missing = _student(class_id=nursery["class_id"])
    del missing["date_of_birth"]
    assert client.post(STUDENTS, json=missing, headers=headers).status_code == 422

    future = _student(class_id=nursery["class_id"], date_of_birth="2999-01-01")
    assert client.post(STUDENTS, json=future, headers=headers).status_code == 422


def test_students_get_sequential_ids_across_devices(client):
    phone = _teacher(client, "+919100000011")
    emulator = _phone_login(client, "+919100000011")
    nursery = client.post(CLASSES, json={"name": "Nursery"}, headers=phone).json()

    first = client.post(STUDENTS, json=_student(class_id=nursery["class_id"]), headers=phone)
    second = client.post(
        STUDENTS, json=_student("Diya", class_id=nursery["class_id"]), headers=emulator
    )

    # Two devices each counting on their own would both have said ST_000001.
    assert first.json()["student_id"] == "ST_000001"
    assert second.json()["student_id"] == "ST_000002"
    assert len(client.get(STUDENTS, headers=phone).json()) == 2


def test_a_student_cannot_be_filed_in_someone_elses_class(client):
    teacher_a = _teacher(client, "+919100000012")
    teacher_b = _teacher(client, "+919100000013")
    theirs = client.post(CLASSES, json={"name": "KG"}, headers=teacher_a).json()

    response = client.post(
        STUDENTS, json=_student(class_id=theirs["class_id"]), headers=teacher_b
    )
    assert response.status_code == 404


def test_roll_numbers_are_alphabetical_and_renumber(client):
    headers = _teacher(client, "+919100000040")
    nursery = client.post(CLASSES, json={"name": "Nursery"}, headers=headers).json()
    class_id = nursery["class_id"]

    for name in ("Kabir", "aarav", "Diya"):
        client.post(STUDENTS, json=_student(name, class_id=class_id), headers=headers)

    def rolls():
        return {
            s["name"]: s["roll_number"]
            for s in client.get(STUDENTS, headers=headers).json()
        }

    # Alphabetical regardless of the order they were registered in, and
    # regardless of case.
    assert rolls() == {"aarav": 1, "Diya": 2, "Kabir": 3}

    # A student joining earlier in the alphabet moves everyone after them.
    client.post(STUDENTS, json=_student("Bela", class_id=class_id), headers=headers)
    assert rolls() == {"aarav": 1, "Bela": 2, "Diya": 3, "Kabir": 4}

    # A student leaving closes the gap.
    db = _db()
    db.execute(delete(Student).where(Student.name == "Bela"))
    db.commit()
    db.close()
    assert rolls() == {"aarav": 1, "Diya": 2, "Kabir": 3}


def test_roll_numbers_restart_in_each_class(client):
    headers = _teacher(client, "+919100000041")
    nursery = client.post(CLASSES, json={"name": "Nursery"}, headers=headers).json()
    kg = client.post(CLASSES, json={"name": "KG"}, headers=headers).json()

    client.post(STUDENTS, json=_student("Zoya", class_id=nursery["class_id"]), headers=headers)
    client.post(STUDENTS, json=_student("Yash", class_id=kg["class_id"]), headers=headers)

    assert [s["roll_number"] for s in client.get(STUDENTS, headers=headers).json()] == [1, 1]


def test_the_roster_is_the_class_as_a_table(client):
    headers = _teacher(client, "+919100000042")
    nursery = client.post(CLASSES, json={"name": "Nursery"}, headers=headers).json()
    for name in ("Kabir", "Aarav"):
        client.post(
            STUDENTS, json=_student(name, class_id=nursery["class_id"]), headers=headers
        )

    roster = client.get(f"{CLASSES}/{nursery['class_id']}/roster", headers=headers).json()
    assert [
        (r["class_id"], r["class_name"], r["roll_number"], r["student_name"])
        for r in roster
    ] == [
        (nursery["class_id"], "Nursery", 1, "Aarav"),
        (nursery["class_id"], "Nursery", 2, "Kabir"),
    ]


def test_the_same_child_cannot_be_registered_twice(client):
    headers = _teacher(client, "+919100000050")
    nursery = client.post(CLASSES, json={"name": "Nursery"}, headers=headers).json()
    client.post(STUDENTS, json=_student(class_id=nursery["class_id"]), headers=headers)

    # The same child, typed a little differently — spacing, case, and a
    # formatted mobile number are not what makes two children different.
    again = _student(
        " aarav ",
        class_id=nursery["class_id"],
        address="12  MG Road,  Pune",
        mother_name="MEERA SHARMA",
        mother_mobile="98765 43210",
        father_email="Rohan@Example.com",
    )
    response = client.post(STUDENTS, json=again, headers=headers)

    assert response.status_code == 409
    assert "already registered in Nursery as ST_000001" in response.json()["detail"]


def test_twins_are_two_students(client):
    headers = _teacher(client, "+919100000051")
    nursery = client.post(CLASSES, json={"name": "Nursery"}, headers=headers).json()

    first = client.post(
        STUDENTS, json=_student("Aarav", class_id=nursery["class_id"]), headers=headers
    )
    twin = client.post(
        STUDENTS, json=_student("Arjun", class_id=nursery["class_id"]), headers=headers
    )

    assert first.status_code == twin.status_code == 201


def test_a_different_detail_is_a_different_child(client):
    headers = _teacher(client, "+919100000052")
    nursery = client.post(CLASSES, json={"name": "Nursery"}, headers=headers).json()
    client.post(STUDENTS, json=_student(class_id=nursery["class_id"]), headers=headers)

    other = _student(class_id=nursery["class_id"], date_of_birth="2021-05-01")
    assert client.post(STUDENTS, json=other, headers=headers).status_code == 201


# --- Restore -----------------------------------------------------------------


def test_restore_creates_the_class_and_keeps_student_ids(client):
    headers = _teacher(client, "+919100000015")

    restored = client.post(
        CLASSES,
        json={
            "name": "Nursery",
            "students": [
                _student("Kabir", student_id="ST_000007"),
                _student("Diya", student_id="ST_000003"),
            ],
        },
        headers=headers,
    )
    assert restored.status_code == 201

    students = client.get(STUDENTS, headers=headers).json()
    assert {s["student_id"] for s in students} == {"ST_000007", "ST_000003"}
    assert {s["class_id"] for s in students} == {restored.json()["class_id"]}

    # The next registration is not handed an id that just came back.
    fresh = client.post(
        STUDENTS,
        json=_student("Aarav", class_id=restored.json()["class_id"]),
        headers=headers,
    ).json()
    assert fresh["student_id"] == "ST_000008"


def test_restore_gives_foreign_ids_fresh_ones(client):
    headers = _teacher(client, "+919100000016")
    client.post(
        CLASSES,
        json={"name": "Nursery", "students": [_student(student_id="GB-0007")]},
        headers=headers,
    )
    [student] = client.get(STUDENTS, headers=headers).json()
    assert student["student_id"] == "ST_000001"


def test_restoring_the_same_file_twice_is_refused_whole(client):
    headers = _teacher(client, "+919100000017")
    archive = [_student(student_id="ST_000001")]
    client.post(CLASSES, json={"name": "Nursery", "students": archive}, headers=headers)

    again = client.post(
        CLASSES, json={"name": "Nursery Again", "students": archive}, headers=headers
    )
    assert again.status_code == 409

    # All or nothing: the refused restore did not leave an empty class behind.
    names = [c["name"] for c in client.get(CLASSES, headers=headers).json()]
    assert names == ["Nursery"]
