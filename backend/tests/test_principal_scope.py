"""What the principal can see, and what stays a teacher's.

Phase 2 of the role rebuild. The dashboard that was built for the teacher is
the principal's now, so the principal needs the data behind it: every class and
every student in the school, not one teacher's. The thing worth pinning is the
boundary — reading widened, owning did not.
"""

SIGNUP = "/api/v1/auth/signup"
CLASSES = "/api/v1/classes"
STUDENTS = "/api/v1/students"

ACCOUNT_TYPE_TEACHER = 0
ACCOUNT_TYPE_PRINCIPAL = 2


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def signup(client, *, name: str, email: str, account_type: int) -> str:
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


def add_student(client, token: str, class_id: str, name: str) -> dict:
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
    return response.json()


def two_teachers_and_a_principal(client) -> tuple[str, str, str]:
    asha = signup(
        client,
        name="Asha Rao",
        email="asha@example.com",
        account_type=ACCOUNT_TYPE_TEACHER,
    )
    bela = signup(
        client,
        name="Bela Nair",
        email="bela@example.com",
        account_type=ACCOUNT_TYPE_TEACHER,
    )
    head = signup(
        client,
        name="Meera Iyer",
        email="head@example.com",
        account_type=ACCOUNT_TYPE_PRINCIPAL,
    )
    return asha, bela, head


def test_principal_sees_every_class_in_the_school(client):
    asha, bela, head = two_teachers_and_a_principal(client)
    make_class(client, asha, "Nursery")
    make_class(client, bela, "Playgroup")

    seen = client.get(CLASSES, headers=auth(head)).json()

    assert {item["name"] for item in seen} == {"Nursery", "Playgroup"}


def test_each_teacher_still_sees_only_their_own(client):
    """The change must not have widened the teacher's view by accident."""
    asha, bela, _ = two_teachers_and_a_principal(client)
    make_class(client, asha, "Nursery")
    make_class(client, bela, "Playgroup")

    assert [c["name"] for c in client.get(CLASSES, headers=auth(asha)).json()] == [
        "Nursery"
    ]
    assert [c["name"] for c in client.get(CLASSES, headers=auth(bela)).json()] == [
        "Playgroup"
    ]


def test_two_teachers_may_share_a_class_name_and_the_principal_can_tell(client):
    """The reason teacher_name is on the list at all.

    "Nursery" belonging to two different teachers is normal and allowed. On the
    principal's dashboard that is two identical tiles unless the owner's name
    comes with them.
    """
    asha, bela, head = two_teachers_and_a_principal(client)
    make_class(client, asha, "Nursery")
    make_class(client, bela, "Nursery")

    seen = client.get(CLASSES, headers=auth(head)).json()

    assert [item["name"] for item in seen] == ["Nursery", "Nursery"]
    assert {item["teacher_name"] for item in seen} == {"Asha Rao", "Bela Nair"}
    # Distinct owners, so the two tiles are genuinely different classes.
    assert len({item["teacher_id"] for item in seen}) == 2


def test_a_teacher_sees_the_owner_name_on_their_own_class(client):
    asha, _, _ = two_teachers_and_a_principal(client)
    make_class(client, asha, "Nursery")

    seen = client.get(CLASSES, headers=auth(asha)).json()

    assert seen[0]["teacher_name"] == "Asha Rao"


def test_principal_sees_every_student_in_the_school(client):
    asha, bela, head = two_teachers_and_a_principal(client)
    add_student(client, asha, make_class(client, asha, "Nursery"), "Diya")
    add_student(client, bela, make_class(client, bela, "Playgroup"), "Kabir")

    seen = client.get(STUDENTS, headers=auth(head)).json()

    assert {item["name"] for item in seen} == {"Diya", "Kabir"}


def test_a_teacher_still_sees_only_their_own_students(client):
    asha, bela, _ = two_teachers_and_a_principal(client)
    add_student(client, asha, make_class(client, asha, "Nursery"), "Diya")
    add_student(client, bela, make_class(client, bela, "Playgroup"), "Kabir")

    assert [s["name"] for s in client.get(STUDENTS, headers=auth(asha)).json()] == [
        "Diya"
    ]


def test_principal_can_read_any_class_roster(client):
    asha, _, head = two_teachers_and_a_principal(client)
    class_id = make_class(client, asha, "Nursery")
    add_student(client, asha, class_id, "Diya")

    response = client.get(f"{CLASSES}/{class_id}/roster", headers=auth(head))

    assert response.status_code == 200, response.text
    assert [row["student_name"] for row in response.json()] == ["Diya"]


def test_a_teacher_cannot_read_another_teachers_roster(client):
    """404, not 403 — the endpoint must not confirm which ids exist."""
    asha, bela, _ = two_teachers_and_a_principal(client)
    class_id = make_class(client, asha, "Nursery")

    response = client.get(f"{CLASSES}/{class_id}/roster", headers=auth(bela))

    assert response.status_code == 404


def test_principal_can_register_a_student_into_any_class(client):
    asha, _, head = two_teachers_and_a_principal(client)
    class_id = make_class(client, asha, "Nursery")

    created = add_student(client, head, class_id, "Diya")

    assert created["class_id"] == class_id
    # And the owning teacher sees them, because the student is the class's.
    assert [s["name"] for s in client.get(STUDENTS, headers=auth(asha)).json()] == [
        "Diya"
    ]


def test_principal_cannot_rename_or_delete_a_class(client):
    asha, _, head = two_teachers_and_a_principal(client)
    class_id = make_class(client, asha, "Nursery")

    renamed = client.patch(
        f"{CLASSES}/{class_id}", json={"name": "Reception"}, headers=auth(head)
    )
    deleted = client.delete(f"{CLASSES}/{class_id}", headers=auth(head))

    assert renamed.status_code == 403
    assert deleted.status_code == 403
    # Untouched.
    assert client.get(CLASSES, headers=auth(asha)).json()[0]["name"] == "Nursery"


def test_a_principal_with_no_classes_gets_an_empty_list_not_an_error(client):
    """A brand-new school. The principal has no TR_ row, which used to 403."""
    _, _, head = two_teachers_and_a_principal(client)

    response = client.get(CLASSES, headers=auth(head))

    assert response.status_code == 200
    assert response.json() == []
