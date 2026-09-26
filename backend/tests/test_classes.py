import helpers
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


def _token(headers: dict[str, str]) -> str:
    return headers["Authorization"].removeprefix("Bearer ")


def _class(client, headers: dict[str, str], name: str, **kwargs) -> dict:
    """A class owned by the teacher behind [headers], as a dict.

    Created by a principal through `helpers`, because a teacher's own POST
    /classes became a request for approval on 2026-09-20. Most tests below
    only ever needed the class to exist; the ones that are about *who may
    create one* post for themselves and are marked as doing so.
    """
    class_id = helpers.make_class(client, _token(headers), name, **kwargs)
    return {"class_id": class_id, "name": name}


def _register(client, headers: dict[str, str], **student) -> dict:
    """Registers a pupil into a class, as staff who may do it outright.

    Same reason as [_class]: a teacher's registration is a request now, and a
    test about roll numbers wants pupils rather than a queue.
    """
    response = client.post(
        STUDENTS, json=_student(**student), headers=helpers.auth(
            helpers.admin_token(client)
        )
    )
    assert response.status_code == 201, response.text
    return response.json()["student"]


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

    nursery = _class(client, headers, "Nursery")
    assert nursery["class_id"] == "CL_000001"

    student = _register(client, headers, class_id=nursery["class_id"])
    assert student["student_id"] == "ST_000001"

    db = _db()
    teacher = db.query(Teacher).one()
    assert (teacher.teacher_id, teacher.user_id) == ("TR_000001", "U_000001")
    db.close()


def test_a_student_account_sees_no_classes_until_it_is_linked(client):
    """Changed in phase 6, deliberately.

    This asserted 403 — a student account reached nothing at all. A student
    account is a parent now, and `GET /classes` answers with the classes their
    children are in. Until the school links the account to a child there are
    none, so the answer is an empty list: the parent has done nothing wrong
    and can do nothing about it themselves, which is not what 403 says.
    """
    headers = _phone_login(client, "+919100000020")
    client.patch(PROFILE, json={"account_type": 1}, headers=headers)

    response = client.get(CLASSES, headers=headers)

    assert response.status_code == 200
    assert response.json() == []


def test_a_student_account_still_cannot_create_a_class(client):
    """Reading widened in phase 6; writing did not."""
    headers = _phone_login(client, "+919100000021")
    client.patch(PROFILE, json={"account_type": 1}, headers=headers)

    response = client.post(
        CLASSES, json={"name": "Nursery", "color_slot": 0}, headers=headers
    )

    assert response.status_code == 403


# --- Classes -----------------------------------------------------------------


def test_a_class_added_on_one_device_shows_on_another(client):
    phone = _teacher(client, "+919100000001")
    emulator = _phone_login(client, "+919100000001")

    _class(client, phone, "Nursery", color_slot=3)

    listed = client.get(CLASSES, headers=emulator).json()
    assert [(c["name"], c["color_slot"]) for c in listed] == [("Nursery", 3)]


def test_a_new_teacher_starts_with_no_classes(client):
    headers = _teacher(client, "+919100000002")
    assert client.get(CLASSES, headers=headers).json() == []


def test_classes_are_private_to_their_teacher(client):
    teacher_a = _teacher(client, "+919100000003")
    teacher_b = _teacher(client, "+919100000004")

    created = _class(client, teacher_a, "KG")

    assert client.get(CLASSES, headers=teacher_b).json() == []
    # Someone else's class reads as missing, not forbidden.
    url = f"{CLASSES}/{created['class_id']}"
    assert client.patch(url, json={"name": "Stolen"}, headers=teacher_b).status_code == 404
    assert client.delete(url, headers=teacher_b).status_code == 404
    assert client.get(f"{url}/roster", headers=teacher_b).status_code == 404


def test_two_teachers_can_both_have_a_nursery(client):
    teacher_a = _teacher(client, "+919100000005")
    teacher_b = _teacher(client, "+919100000006")

    _class(client, teacher_a, "Nursery")
    _class(client, teacher_b, "Nursery")

    # Each sees exactly one, and it is their own.
    assert [c["name"] for c in client.get(CLASSES, headers=teacher_a).json()] == [
        "Nursery"
    ]
    assert [c["name"] for c in client.get(CLASSES, headers=teacher_b).json()] == [
        "Nursery"
    ]


def test_duplicate_class_names_are_refused_ignoring_case(client):
    """Checked before the request is even raised.

    The teacher posts for themselves here, on purpose: the point is that they
    are told "that name is taken" straight away rather than being left waiting
    on an approval that could never have succeeded.
    """
    headers = _teacher(client, "+919100000007")
    _class(client, headers, "Nursery")

    duplicate = client.post(CLASSES, json={"name": "  nursery "}, headers=headers)
    assert duplicate.status_code == 409
    assert duplicate.json()["detail"] == 'A class called "nursery" already exists'


def test_edit_class_changes_name_and_colour_together(client):
    headers = _teacher(client, "+919100000008")
    created = _class(client, headers, "Daycare")

    edited = client.patch(
        f"{CLASSES}/{created['class_id']}",
        json={"name": "Day Care", "color_slot": 6},
        headers=headers,
    ).json()
    assert (edited["name"], edited["color_slot"]) == ("Day Care", 6)


def test_edit_class_rejects_an_out_of_range_colour(client):
    headers = _teacher(client, "+919100000010")
    created = _class(client, headers, "KG")

    response = client.patch(
        f"{CLASSES}/{created['class_id']}", json={"color_slot": 9}, headers=headers
    )
    assert response.status_code == 422


def test_deleting_a_class_deletes_its_students(client):
    """Deleted by the principal, whose delete takes effect at once.

    A teacher's delete raises a request instead and changes nothing until it
    is granted — which is test_approvals.py's subject, not this one's.
    """
    headers = _teacher(client, "+919100000014")
    nursery = _class(client, headers, "Nursery")
    kg = _class(client, headers, "KG")
    _register(client, headers, class_id=nursery["class_id"])
    _register(client, headers, name="Diya", class_id=kg["class_id"])

    response = client.delete(
        f"{CLASSES}/{nursery['class_id']}",
        headers=helpers.auth(helpers.admin_token(client)),
    )
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "done"

    remaining = client.get(STUDENTS, headers=headers).json()
    assert [s["name"] for s in remaining] == ["Diya"]


# --- Students ----------------------------------------------------------------


def test_a_student_needs_a_class(client):
    headers = _teacher(client, "+919100000030")
    response = client.post(STUDENTS, json=_student(), headers=headers)
    assert response.status_code == 422


def test_a_student_needs_a_date_of_birth_in_the_past(client):
    headers = _teacher(client, "+919100000031")
    nursery = _class(client, headers, "Nursery")

    missing = _student(class_id=nursery["class_id"])
    del missing["date_of_birth"]
    assert client.post(STUDENTS, json=missing, headers=headers).status_code == 422

    future = _student(class_id=nursery["class_id"], date_of_birth="2999-01-01")
    assert client.post(STUDENTS, json=future, headers=headers).status_code == 422


def test_students_get_sequential_ids_across_devices(client):
    phone = _teacher(client, "+919100000011")
    emulator = _phone_login(client, "+919100000011")
    nursery = _class(client, phone, "Nursery")

    first = _register(client, phone, class_id=nursery["class_id"])
    second = _register(client, emulator, name="Diya", class_id=nursery["class_id"])

    # Two devices each counting on their own would both have said ST_000001.
    assert first["student_id"] == "ST_000001"
    assert second["student_id"] == "ST_000002"
    assert len(client.get(STUDENTS, headers=phone).json()) == 2


def test_a_student_cannot_be_filed_in_someone_elses_class(client):
    teacher_a = _teacher(client, "+919100000012")
    teacher_b = _teacher(client, "+919100000013")
    theirs = _class(client, teacher_a, "KG")

    response = client.post(
        STUDENTS, json=_student(class_id=theirs["class_id"]), headers=teacher_b
    )
    assert response.status_code == 404


def test_roll_numbers_are_alphabetical_and_renumber(client):
    headers = _teacher(client, "+919100000040")
    nursery = _class(client, headers, "Nursery")
    class_id = nursery["class_id"]

    for name in ("Kabir", "aarav", "Diya"):
        _register(client, headers, name=name, class_id=class_id)

    def rolls():
        return {
            s["name"]: s["roll_number"]
            for s in client.get(STUDENTS, headers=headers).json()
        }

    # Alphabetical regardless of the order they were registered in, and
    # regardless of case.
    assert rolls() == {"aarav": 1, "Diya": 2, "Kabir": 3}

    # A student joining earlier in the alphabet moves everyone after them.
    _register(client, headers, name="Bela", class_id=class_id)
    assert rolls() == {"aarav": 1, "Bela": 2, "Diya": 3, "Kabir": 4}

    # A student leaving closes the gap.
    db = _db()
    db.execute(delete(Student).where(Student.name == "Bela"))
    db.commit()
    db.close()
    assert rolls() == {"aarav": 1, "Diya": 2, "Kabir": 3}


def test_roll_numbers_restart_in_each_class(client):
    headers = _teacher(client, "+919100000041")
    nursery = _class(client, headers, "Nursery")
    kg = _class(client, headers, "KG")

    _register(client, headers, name="Zoya", class_id=nursery["class_id"])
    _register(client, headers, name="Yash", class_id=kg["class_id"])

    assert [s["roll_number"] for s in client.get(STUDENTS, headers=headers).json()] == [1, 1]


def test_the_roster_is_the_class_as_a_table(client):
    headers = _teacher(client, "+919100000042")
    nursery = _class(client, headers, "Nursery")
    for name in ("Kabir", "Aarav"):
        _register(client, headers, name=name, class_id=nursery["class_id"])

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
    nursery = _class(client, headers, "Nursery")
    _register(client, headers, class_id=nursery["class_id"])

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
    nursery = _class(client, headers, "Nursery")

    first = _register(client, headers, name="Aarav", class_id=nursery["class_id"])
    twin = _register(client, headers, name="Arjun", class_id=nursery["class_id"])

    # Two rows, not one refused as a duplicate.
    assert first["student_id"] != twin["student_id"]


def test_a_different_detail_is_a_different_child(client):
    headers = _teacher(client, "+919100000052")
    nursery = _class(client, headers, "Nursery")
    _register(client, headers, class_id=nursery["class_id"])

    other = _register(
        client, headers, class_id=nursery["class_id"], date_of_birth="2021-05-01"
    )
    assert other["student_id"] == "ST_000002"


# --- Restore -----------------------------------------------------------------


def test_restore_creates_the_class_and_keeps_student_ids(client):
    headers = _teacher(client, "+919100000015")

    class_id = _class(
        client,
        headers,
        "Nursery",
        students=[
            _student("Kabir", student_id="ST_000007"),
            _student("Diya", student_id="ST_000003"),
        ],
    )["class_id"]

    students = client.get(STUDENTS, headers=headers).json()
    assert {s["student_id"] for s in students} == {"ST_000007", "ST_000003"}
    assert {s["class_id"] for s in students} == {class_id}

    # The next registration is not handed an id that just came back.
    fresh = _register(client, headers, name="Aarav", class_id=class_id)
    assert fresh["student_id"] == "ST_000008"


def test_restore_gives_foreign_ids_fresh_ones(client):
    headers = _teacher(client, "+919100000016")
    _class(client, headers, "Nursery", students=[_student(student_id="GB-0007")])
    [student] = client.get(STUDENTS, headers=headers).json()
    assert student["student_id"] == "ST_000001"


def test_restoring_the_same_file_twice_is_refused_whole(client):
    headers = _teacher(client, "+919100000017")
    archive = [_student(student_id="ST_000001")]
    _class(client, headers, "Nursery", students=archive)

    again = client.post(
        CLASSES,
        json={
            "name": "Nursery Again",
            "teacher_id": helpers.teacher_id_of(client, _token(headers)),
            "students": archive,
        },
        headers=helpers.auth(helpers.admin_token(client)),
    )
    assert again.status_code == 409

    # All or nothing: the refused restore did not leave an empty class behind.
    names = [c["name"] for c in client.get(CLASSES, headers=headers).json()]
    assert names == ["Nursery"]
