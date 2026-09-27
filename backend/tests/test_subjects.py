"""Subjects, and the two-way check on adding one.

The principal adds a subject outright. A teacher proposes one, which is
`pending` and does nothing until the principal approves it. What is worth
pinning is that a teacher cannot get an approved subject by any route — not by
asking, and not by proposing twice.
"""

SIGNUP = "/api/v1/auth/signup"
SUBJECTS = "/api/v1/subjects"

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


def cast(client) -> tuple[str, str, str]:
    return (
        signup(client, "Asha Rao", "asha@example.com", TEACHER),
        signup(client, "Bela Nair", "bela@example.com", TEACHER),
        signup(client, "Meera Iyer", "head@example.com", PRINCIPAL),
    )


def test_principal_adds_a_subject_and_it_is_approved_at_once(client):
    _, _, head = cast(client)

    response = client.post(SUBJECTS, json={"name": "Mathematics"}, headers=auth(head))

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["subject_id"] == "S_000001"
    assert body["name"] == "Mathematics"
    assert body["status"] == "approved"
    assert body["approved_at"] is not None
    assert body["proposed_by_teacher_id"] is None


def test_a_teachers_subject_arrives_pending(client):
    asha, _, _ = cast(client)

    response = client.post(SUBJECTS, json={"name": "Music"}, headers=auth(asha))

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["status"] == "pending"
    assert body["approved_at"] is None
    assert body["proposed_by_teacher_id"] is not None
    assert body["proposed_by_name"] == "Asha Rao"


def test_a_teacher_cannot_ask_for_approval_in_the_request(client):
    """There is no field to ask with, which is why this is safe.

    Sending status/approved_at anyway must not reach the row — extra keys are
    ignored, not honoured.
    """
    asha, _, _ = cast(client)

    response = client.post(
        SUBJECTS,
        json={"name": "Music", "status": "approved", "approved_at": "2020-01-01"},
        headers=auth(asha),
    )

    assert response.status_code == 201, response.text
    assert response.json()["status"] == "pending"


def test_the_principal_approves_a_proposal(client):
    asha, _, head = cast(client)
    subject_id = client.post(
        SUBJECTS, json={"name": "Music"}, headers=auth(asha)
    ).json()["subject_id"]

    response = client.post(f"{SUBJECTS}/{subject_id}/approve", headers=auth(head))

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "approved"
    assert body["approved_at"] is not None
    # Who proposed it is kept — it is history, not a workflow flag to clear.
    assert body["proposed_by_name"] == "Asha Rao"


def test_a_teacher_cannot_approve_anything(client):
    asha, bela, _ = cast(client)
    subject_id = client.post(
        SUBJECTS, json={"name": "Music"}, headers=auth(asha)
    ).json()["subject_id"]

    # Not their own proposal, and not somebody else's either.
    own = client.post(f"{SUBJECTS}/{subject_id}/approve", headers=auth(asha))
    other = client.post(f"{SUBJECTS}/{subject_id}/approve", headers=auth(bela))

    assert own.status_code == 403
    assert other.status_code == 403
    assert "Only the principal can approve a subject" in own.json()["detail"]


def test_approving_twice_is_not_an_error(client):
    """Two taps on a slow connection should not read as a failure."""
    _, _, head = cast(client)
    subject_id = client.post(
        SUBJECTS, json={"name": "Mathematics"}, headers=auth(head)
    ).json()["subject_id"]

    first = client.post(f"{SUBJECTS}/{subject_id}/approve", headers=auth(head))
    second = client.post(f"{SUBJECTS}/{subject_id}/approve", headers=auth(head))

    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json()["status"] == "approved"


def test_a_teacher_sees_approved_subjects_and_only_their_own_proposals(client):
    asha, bela, head = cast(client)
    client.post(SUBJECTS, json={"name": "Mathematics"}, headers=auth(head))
    client.post(SUBJECTS, json={"name": "Music"}, headers=auth(asha))
    client.post(SUBJECTS, json={"name": "Pottery"}, headers=auth(bela))

    seen = client.get(SUBJECTS, headers=auth(asha)).json()

    # Bela's unapproved idea is not yet a fact about the school.
    assert {s["name"] for s in seen} == {"Mathematics", "Music"}


def test_the_principal_sees_every_proposal(client):
    asha, bela, head = cast(client)
    client.post(SUBJECTS, json={"name": "Mathematics"}, headers=auth(head))
    client.post(SUBJECTS, json={"name": "Music"}, headers=auth(asha))
    client.post(SUBJECTS, json={"name": "Pottery"}, headers=auth(bela))

    seen = client.get(SUBJECTS, headers=auth(head)).json()

    assert {s["name"] for s in seen} == {"Mathematics", "Music", "Pottery"}
    pending = {s["name"]: s["proposed_by_name"] for s in seen if s["status"] == "pending"}
    assert pending == {"Music": "Asha Rao", "Pottery": "Bela Nair"}


def test_subject_names_are_unique_case_insensitively(client):
    _, _, head = cast(client)
    client.post(SUBJECTS, json={"name": "Mathematics"}, headers=auth(head))

    response = client.post(
        SUBJECTS, json={"name": "  mathematics "}, headers=auth(head)
    )

    assert response.status_code == 409
    assert "already a subject" in response.json()["detail"]


def test_a_pending_subject_also_blocks_a_duplicate(client):
    """Otherwise the principal gets two identical rows to approve."""
    asha, bela, _ = cast(client)
    client.post(SUBJECTS, json={"name": "Music"}, headers=auth(asha))

    response = client.post(SUBJECTS, json={"name": "music"}, headers=auth(bela))

    assert response.status_code == 409
    assert "waiting for approval" in response.json()["detail"]


def test_the_principal_removes_a_subject_and_a_teacher_cannot(client):
    asha, _, head = cast(client)
    subject_id = client.post(
        SUBJECTS, json={"name": "Mathematics"}, headers=auth(head)
    ).json()["subject_id"]

    refused = client.delete(f"{SUBJECTS}/{subject_id}", headers=auth(asha))
    assert refused.status_code == 403

    removed = client.delete(f"{SUBJECTS}/{subject_id}", headers=auth(head))
    assert removed.status_code == 204
    assert client.get(SUBJECTS, headers=auth(head)).json() == []


def test_a_student_account_reaches_no_subjects(client):
    pupil = signup(client, "Aarav Sharma", "pupil@example.com", STUDENT)

    assert client.get(SUBJECTS, headers=auth(pupil)).status_code == 403
    assert (
        client.post(SUBJECTS, json={"name": "Music"}, headers=auth(pupil)).status_code
        == 403
    )


def test_a_blank_name_is_refused(client):
    _, _, head = cast(client)

    response = client.post(SUBJECTS, json={"name": "   "}, headers=auth(head))

    assert response.status_code == 422


def test_approving_a_subject_that_does_not_exist_is_a_404(client):
    _, _, head = cast(client)

    response = client.post(f"{SUBJECTS}/S_999999/approve", headers=auth(head))

    assert response.status_code == 404
