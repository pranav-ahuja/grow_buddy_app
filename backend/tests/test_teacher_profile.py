"""The teacher record — details, experience, subject assignment, and who may
touch which.

Phase 4. The boundaries worth pinning: a teacher edits their own record and
nobody else's, the principal edits anyone's, only the principal assigns
subjects, and the Aadhaar number never leaves the server in full.
"""

import helpers

SIGNUP = "/api/v1/auth/signup"
TEACHERS = "/api/v1/teachers"
SUBJECTS = "/api/v1/subjects"
CLASSES = "/api/v1/classes"

TEACHER = 0
STUDENT = 1
PRINCIPAL = 2


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


def cast(client) -> dict[str, str]:
    asha = signup(client, "Asha Rao", "asha@example.com", TEACHER)
    bela = signup(client, "Bela Nair", "bela@example.com", TEACHER)
    head = signup(client, "Meera Iyer", "head@example.com", PRINCIPAL)
    # Reading /teachers/me is what materialises the TR_ row.
    asha_id = client.get(f"{TEACHERS}/me", headers=auth(asha)).json()["teacher_id"]
    bela_id = client.get(f"{TEACHERS}/me", headers=auth(bela)).json()["teacher_id"]
    return {"asha": asha, "bela": bela, "head": head, "asha_id": asha_id, "bela_id": bela_id}


# --- Reading ----------------------------------------------------------------


def test_a_new_teacher_has_an_empty_but_valid_record(client):
    asha = signup(client, "Asha Rao", "asha@example.com", TEACHER)

    response = client.get(f"{TEACHERS}/me", headers=auth(asha))

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["teacher_id"].startswith("TR_")
    # Name and contact come from users, not from a copy on teachers.
    assert body["full_name"] == "Asha Rao"
    assert body["email"] == "asha@example.com"
    assert body["date_of_birth"] is None
    assert body["classes"] == []
    assert body["subjects"] == []
    assert body["experience"] == []
    assert body["is_profile_complete"] is False
    assert "date_of_birth" in body["missing_profile_fields"]


def test_the_name_follows_the_user_record(client):
    """Not copied, so renaming the account renames the profile."""
    asha = signup(client, "Asha Rao", "asha@example.com", TEACHER)
    client.patch(
        "/api/v1/auth/me", json={"full_name": "Asha Rao-Mehta"}, headers=auth(asha)
    )

    body = client.get(f"{TEACHERS}/me", headers=auth(asha)).json()

    assert body["full_name"] == "Asha Rao-Mehta"


def test_a_teachers_classes_appear_on_their_record(client):
    c = cast(client)
    helpers.make_class(client, c["asha"], "Nursery", principal=c["head"])

    body = client.get(f"{TEACHERS}/me", headers=auth(c["asha"])).json()

    assert [k["name"] for k in body["classes"]] == ["Nursery"]


def test_a_teacher_cannot_read_a_colleagues_record(client):
    """404, not 403 — the endpoint must not confirm which TR_ ids exist."""
    c = cast(client)

    response = client.get(f"{TEACHERS}/{c['bela_id']}", headers=auth(c["asha"]))

    assert response.status_code == 404


def test_a_teacher_may_name_their_own_id_explicitly(client):
    c = cast(client)

    response = client.get(f"{TEACHERS}/{c['asha_id']}", headers=auth(c["asha"]))

    assert response.status_code == 200
    assert response.json()["teacher_id"] == c["asha_id"]


def test_only_the_principal_lists_every_teacher(client):
    c = cast(client)

    refused = client.get(TEACHERS, headers=auth(c["asha"]))
    listed = client.get(TEACHERS, headers=auth(c["head"]))

    assert refused.status_code == 403
    assert "Only the principal can see every teacher" in refused.json()["detail"]
    assert {t["full_name"] for t in listed.json()} == {"Asha Rao", "Bela Nair"}


def test_a_principal_has_no_teacher_record_of_their_own(client):
    c = cast(client)

    response = client.get(f"{TEACHERS}/me", headers=auth(c["head"]))

    assert response.status_code == 404
    assert "no teacher record" in response.json()["detail"]


def test_a_student_account_reaches_nothing(client):
    pupil = signup(client, "Aarav Sharma", "pupil@example.com", STUDENT)

    assert client.get(f"{TEACHERS}/me", headers=auth(pupil)).status_code == 403


# --- Editing ----------------------------------------------------------------


FULL_PROFILE = {
    "date_of_birth": "1990-06-15",
    "highest_qualification": "M.Ed",
    "address": "12 Rose Lane, Pune",
    "relationship_status": "Married",
    "emergency_contact_name": "Ravi Rao",
    "emergency_contact_phone": "+919876500001",
}


def test_a_teacher_fills_in_their_own_profile(client):
    c = cast(client)

    response = client.patch(
        f"{TEACHERS}/me", json=FULL_PROFILE, headers=auth(c["asha"])
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["highest_qualification"] == "M.Ed"
    assert body["date_of_birth"] == "1990-06-15"
    assert body["is_profile_complete"] is True
    assert body["missing_profile_fields"] == []


def test_a_partial_update_leaves_the_rest_alone(client):
    c = cast(client)
    client.patch(f"{TEACHERS}/me", json=FULL_PROFILE, headers=auth(c["asha"]))

    client.patch(
        f"{TEACHERS}/me", json={"address": "9 New Street"}, headers=auth(c["asha"])
    )

    body = client.get(f"{TEACHERS}/me", headers=auth(c["asha"])).json()
    assert body["address"] == "9 New Street"
    assert body["highest_qualification"] == "M.Ed"


def test_an_explicit_null_clears_a_field(client):
    """Absent and null must differ, or a mistake can never be removed."""
    c = cast(client)
    client.patch(f"{TEACHERS}/me", json=FULL_PROFILE, headers=auth(c["asha"]))

    client.patch(f"{TEACHERS}/me", json={"address": None}, headers=auth(c["asha"]))

    body = client.get(f"{TEACHERS}/me", headers=auth(c["asha"])).json()
    assert body["address"] is None
    # And the profile is incomplete again, so the screen asks for it.
    assert "address" in body["missing_profile_fields"]


def test_an_empty_update_is_refused(client):
    c = cast(client)

    response = client.patch(f"{TEACHERS}/me", json={}, headers=auth(c["asha"]))

    assert response.status_code == 422


def test_an_unknown_field_is_refused(client):
    """extra="forbid", so a typo'd key fails loudly instead of being dropped."""
    c = cast(client)

    response = client.patch(
        f"{TEACHERS}/me", json={"qualification": "M.Ed"}, headers=auth(c["asha"])
    )

    assert response.status_code == 422


def test_a_teacher_cannot_edit_a_colleague(client):
    c = cast(client)

    response = client.patch(
        f"{TEACHERS}/{c['bela_id']}",
        json={"address": "somewhere else"},
        headers=auth(c["asha"]),
    )

    assert response.status_code == 404
    assert client.get(f"{TEACHERS}/me", headers=auth(c["bela"])).json()["address"] is None


def test_the_principal_can_edit_any_teacher(client):
    c = cast(client)

    response = client.patch(
        f"{TEACHERS}/{c['asha_id']}",
        json={"highest_qualification": "B.Ed"},
        headers=auth(c["head"]),
    )

    assert response.status_code == 200, response.text
    assert response.json()["highest_qualification"] == "B.Ed"


def test_a_future_date_of_birth_is_refused(client):
    c = cast(client)

    response = client.patch(
        f"{TEACHERS}/me", json={"date_of_birth": "2099-01-01"}, headers=auth(c["asha"])
    )

    assert response.status_code == 422


def test_a_bad_emergency_number_is_refused(client):
    c = cast(client)

    response = client.patch(
        f"{TEACHERS}/me",
        json={"emergency_contact_phone": "12"},
        headers=auth(c["asha"]),
    )

    assert response.status_code == 422


# --- Aadhaar ----------------------------------------------------------------


def test_only_the_last_four_aadhaar_digits_come_back(client):
    """The full number must never leave the server."""
    c = cast(client)

    response = client.patch(
        f"{TEACHERS}/me",
        json={"aadhaar_number": "1234 5678 9012"},
        headers=auth(c["asha"]),
    )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["aadhaar_last4"] == "9012"
    # Not under any key, and not anywhere in the serialised response.
    assert "aadhaar_number" not in body
    assert "123456789012" not in response.text
    assert "1234 5678 9012" not in response.text


def test_aadhaar_spacing_does_not_create_a_second_identity(client):
    """Stored bare, so the spaced and unspaced forms are the same number."""
    c = cast(client)
    client.patch(
        f"{TEACHERS}/me",
        json={"aadhaar_number": "1234 5678 9012"},
        headers=auth(c["asha"]),
    )

    clash = client.patch(
        f"{TEACHERS}/me",
        json={"aadhaar_number": "123456789012"},
        headers=auth(c["bela"]),
    )

    assert clash.status_code == 409
    assert "already on another teacher's record" in clash.json()["detail"]


def test_a_short_aadhaar_is_refused(client):
    c = cast(client)

    response = client.patch(
        f"{TEACHERS}/me", json={"aadhaar_number": "1234"}, headers=auth(c["asha"])
    )

    assert response.status_code == 422
    assert "12 digits" in response.json()["detail"]


def test_aadhaar_does_not_count_towards_a_complete_profile(client):
    """A teacher may reasonably refuse it; nagging forever would be wrong."""
    c = cast(client)

    body = client.patch(
        f"{TEACHERS}/me", json=FULL_PROFILE, headers=auth(c["asha"])
    ).json()

    assert body["is_profile_complete"] is True
    assert body["aadhaar_last4"] is None


# --- Work experience --------------------------------------------------------


POST = {"school_name": "St Mary's", "school_address": "Pune", "years": 2.5}


def test_a_teacher_adds_and_removes_experience(client):
    c = cast(client)

    added = client.post(
        f"{TEACHERS}/me/experience", json=POST, headers=auth(c["asha"])
    )

    assert added.status_code == 201, added.text
    entries = added.json()["experience"]
    assert len(entries) == 1
    assert entries[0]["school_name"] == "St Mary's"
    # Half years survive — an integer column would have rounded this away.
    assert entries[0]["years"] == 2.5

    removed = client.delete(
        f"{TEACHERS}/me/experience/{entries[0]['id']}", headers=auth(c["asha"])
    )
    assert removed.status_code == 204
    assert client.get(f"{TEACHERS}/me", headers=auth(c["asha"])).json()["experience"] == []


def test_several_posts_are_listed_longest_first(client):
    c = cast(client)
    for name, years in (("St Mary's", 2.5), ("Green Valley", 7), ("Little Steps", 1)):
        client.post(
            f"{TEACHERS}/me/experience",
            json={"school_name": name, "years": years},
            headers=auth(c["asha"]),
        )

    body = client.get(f"{TEACHERS}/me", headers=auth(c["asha"])).json()

    assert [e["school_name"] for e in body["experience"]] == [
        "Green Valley",
        "St Mary's",
        "Little Steps",
    ]


def test_a_teacher_cannot_delete_a_line_off_another_record(client):
    """Guessing an integer must not reach somebody else's CV."""
    c = cast(client)
    entry_id = client.post(
        f"{TEACHERS}/me/experience", json=POST, headers=auth(c["bela"])
    ).json()["experience"][0]["id"]

    response = client.delete(
        f"{TEACHERS}/me/experience/{entry_id}", headers=auth(c["asha"])
    )

    assert response.status_code == 404
    assert len(client.get(f"{TEACHERS}/me", headers=auth(c["bela"])).json()["experience"]) == 1


def test_negative_years_are_refused(client):
    c = cast(client)

    response = client.post(
        f"{TEACHERS}/me/experience",
        json={"school_name": "St Mary's", "years": -1},
        headers=auth(c["asha"]),
    )

    assert response.status_code == 422


# --- Subject assignment -----------------------------------------------------


def approved_subject(client, head_token: str, name: str) -> str:
    response = client.post(SUBJECTS, json={"name": name}, headers=auth(head_token))
    assert response.status_code == 201, response.text
    return response.json()["subject_id"]


def test_the_principal_assigns_subjects(client):
    c = cast(client)
    maths = approved_subject(client, c["head"], "Mathematics")
    music = approved_subject(client, c["head"], "Music")

    response = client.put(
        f"{TEACHERS}/{c['asha_id']}/subjects",
        json={"subject_ids": [maths, music]},
        headers=auth(c["head"]),
    )

    assert response.status_code == 200, response.text
    assert {s["name"] for s in response.json()["subjects"]} == {"Mathematics", "Music"}


def test_assignment_replaces_the_whole_set(client):
    """PUT, not a patch — an unticked subject must actually come off."""
    c = cast(client)
    maths = approved_subject(client, c["head"], "Mathematics")
    music = approved_subject(client, c["head"], "Music")
    client.put(
        f"{TEACHERS}/{c['asha_id']}/subjects",
        json={"subject_ids": [maths, music]},
        headers=auth(c["head"]),
    )

    response = client.put(
        f"{TEACHERS}/{c['asha_id']}/subjects",
        json={"subject_ids": [music]},
        headers=auth(c["head"]),
    )

    assert [s["name"] for s in response.json()["subjects"]] == ["Music"]


def test_an_empty_list_means_none(client):
    c = cast(client)
    maths = approved_subject(client, c["head"], "Mathematics")
    client.put(
        f"{TEACHERS}/{c['asha_id']}/subjects",
        json={"subject_ids": [maths]},
        headers=auth(c["head"]),
    )

    response = client.put(
        f"{TEACHERS}/{c['asha_id']}/subjects",
        json={"subject_ids": []},
        headers=auth(c["head"]),
    )

    assert response.json()["subjects"] == []


def test_a_teacher_cannot_assign_their_own_subjects(client):
    c = cast(client)
    maths = approved_subject(client, c["head"], "Mathematics")

    response = client.put(
        f"{TEACHERS}/{c['asha_id']}/subjects",
        json={"subject_ids": [maths]},
        headers=auth(c["asha"]),
    )

    assert response.status_code == 403


def test_a_pending_subject_cannot_be_assigned(client):
    """Otherwise a proposal takes effect without the approval it waits for."""
    c = cast(client)
    pending = client.post(
        SUBJECTS, json={"name": "Pottery"}, headers=auth(c["asha"])
    ).json()["subject_id"]

    response = client.put(
        f"{TEACHERS}/{c['asha_id']}/subjects",
        json={"subject_ids": [pending]},
        headers=auth(c["head"]),
    )

    assert response.status_code == 400
    assert "has to be approved" in response.json()["detail"]


def test_the_same_subject_twice_is_refused(client):
    c = cast(client)
    maths = approved_subject(client, c["head"], "Mathematics")

    response = client.put(
        f"{TEACHERS}/{c['asha_id']}/subjects",
        json={"subject_ids": [maths, maths]},
        headers=auth(c["head"]),
    )

    assert response.status_code == 422


def test_deleting_a_subject_removes_it_from_teachers(client):
    """The cascade — otherwise a profile lists a subject that is gone."""
    c = cast(client)
    maths = approved_subject(client, c["head"], "Mathematics")
    client.put(
        f"{TEACHERS}/{c['asha_id']}/subjects",
        json={"subject_ids": [maths]},
        headers=auth(c["head"]),
    )

    assert client.delete(f"{SUBJECTS}/{maths}", headers=auth(c["head"])).status_code == 204

    assert client.get(f"{TEACHERS}/me", headers=auth(c["asha"])).json()["subjects"] == []


# --- Assigning a class to a teacher -----------------------------------------


def test_the_principal_moves_a_class_to_another_teacher(client):
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
    assert response.json()["teacher_name"] == "Bela Nair"
    # It has left Asha's list and joined Bela's.
    assert client.get(CLASSES, headers=auth(c["asha"])).json() == []
    assert [k["name"] for k in client.get(CLASSES, headers=auth(c["bela"])).json()] == [
        "Nursery"
    ]


def test_the_students_move_with_the_class(client):
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )
    helpers.add_student(client, c["head"], class_id, "Diya")

    client.patch(
        f"{CLASSES}/{class_id}/teacher",
        json={"teacher_id": c["bela_id"]},
        headers=auth(c["head"]),
    )

    # The pupil belongs to the class, not the teacher.
    assert [s["name"] for s in client.get("/api/v1/students", headers=auth(c["bela"])).json()] == [
        "Diya"
    ]
    assert client.get("/api/v1/students", headers=auth(c["asha"])).json() == []


def test_a_teacher_cannot_reassign_a_class(client):
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )

    response = client.patch(
        f"{CLASSES}/{class_id}/teacher",
        json={"teacher_id": c["bela_id"]},
        headers=auth(c["asha"]),
    )

    assert response.status_code == 403


def test_reassigning_into_a_name_clash_is_refused(client):
    """uq_classes_teacher_name is per teacher, so the receiver may have one."""
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )
    helpers.make_class(
        client, c["bela"], "Nursery", color_slot=1, principal=c["head"]
    )

    response = client.patch(
        f"{CLASSES}/{class_id}/teacher",
        json={"teacher_id": c["bela_id"]},
        headers=auth(c["head"]),
    )

    assert response.status_code == 409
    # Names the receiving teacher, so the reader is not sent looking at their own list.
    assert response.json()["detail"] == 'Bela Nair already has a class called "Nursery"'


def test_reassigning_to_the_current_teacher_is_not_an_error(client):
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )

    response = client.patch(
        f"{CLASSES}/{class_id}/teacher",
        json={"teacher_id": c["asha_id"]},
        headers=auth(c["head"]),
    )

    assert response.status_code == 200
    assert response.json()["teacher_name"] == "Asha Rao"


def test_assigning_to_a_teacher_that_does_not_exist_is_a_404(client):
    c = cast(client)
    class_id = helpers.make_class(
        client, c["asha"], "Nursery", principal=c["head"]
    )

    response = client.patch(
        f"{CLASSES}/{class_id}/teacher",
        json={"teacher_id": "TR_999999"},
        headers=auth(c["head"]),
    )

    assert response.status_code == 404
