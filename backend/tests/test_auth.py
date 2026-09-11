SIGNUP = "/api/v1/auth/signup"
LOGIN = "/api/v1/auth/login"
OTP_REQUEST = "/api/v1/auth/otp/request"
OTP_VERIFY = "/api/v1/auth/otp/verify"
ME = "/api/v1/auth/me"

TEACHER = {
    "full_name": "Pranav Ahuja",
    "identifier": "pranav@example.com",
    "password": "supersecret123",
    "account_type": 0,
}


def test_signup_returns_token_and_user(client):
    response = client.post(SIGNUP, json=TEACHER)

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["token_type"] == "bearer"
    assert body["access_token"]
    assert body["user"]["email"] == "pranav@example.com"
    assert body["user"]["role"] == "teacher"
    assert body["user"]["phone"] is None


def test_signup_rejects_duplicate_email(client):
    client.post(SIGNUP, json=TEACHER)
    response = client.post(SIGNUP, json=TEACHER)

    assert response.status_code == 409


def test_signup_accepts_a_phone_number_as_identifier(client):
    response = client.post(
        SIGNUP, json={**TEACHER, "identifier": "+91 98765-43210", "account_type": 1}
    )

    assert response.status_code == 201, response.text
    user = response.json()["user"]
    assert user["phone"] == "+919876543210"
    assert user["email"] is None
    assert user["role"] == "student"


def test_signup_rejects_a_short_password(client):
    response = client.post(SIGNUP, json={**TEACHER, "password": "short"})

    assert response.status_code == 422
    # The handler flattens errors to a string the app can show directly.
    assert isinstance(response.json()["detail"], str)


def test_login_succeeds_and_token_works_on_me(client):
    client.post(SIGNUP, json=TEACHER)

    response = client.post(
        LOGIN, json={"email": "pranav@example.com", "password": "supersecret123"}
    )
    assert response.status_code == 200, response.text
    token = response.json()["access_token"]

    me = client.get(ME, headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert me.json()["full_name"] == "Pranav Ahuja"


def test_login_is_case_insensitive_on_email(client):
    client.post(SIGNUP, json=TEACHER)

    response = client.post(
        LOGIN, json={"email": "PRANAV@Example.com", "password": "supersecret123"}
    )

    assert response.status_code == 200, response.text


def test_login_rejects_a_wrong_password(client):
    client.post(SIGNUP, json=TEACHER)

    response = client.post(
        LOGIN, json={"email": "pranav@example.com", "password": "wrongpassword"}
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid email or password"


def test_login_for_an_unknown_email_looks_identical(client):
    response = client.post(
        LOGIN, json={"email": "nobody@example.com", "password": "wrongpassword"}
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid email or password"


def test_me_requires_a_token(client):
    assert client.get(ME).status_code == 401
    assert client.get(ME, headers={"Authorization": "Bearer nonsense"}).status_code == 401


def test_otp_flow_creates_an_account_on_first_verify(client):
    requested = client.post(OTP_REQUEST, json={"phone": "+91 90000 00001"})
    assert requested.status_code == 200, requested.text
    code = requested.json()["debug_otp"]
    assert code and len(code) == 6

    verified = client.post(
        OTP_VERIFY, json={"phone": "+919000000001", "otp": code}
    )
    assert verified.status_code == 200, verified.text
    user = verified.json()["user"]
    assert user["phone"] == "+919000000001"
    assert user["is_phone_verified"] is True


def test_otp_cannot_be_reused(client):
    code = client.post(OTP_REQUEST, json={"phone": "+919000000002"}).json()["debug_otp"]
    client.post(OTP_VERIFY, json={"phone": "+919000000002", "otp": code})

    replay = client.post(OTP_VERIFY, json={"phone": "+919000000002", "otp": code})

    assert replay.status_code == 400


def test_otp_rejects_a_wrong_code(client):
    code = client.post(OTP_REQUEST, json={"phone": "+919000000003"}).json()["debug_otp"]
    wrong = "000000" if code != "000000" else "111111"

    response = client.post(OTP_VERIFY, json={"phone": "+919000000003", "otp": wrong})

    assert response.status_code == 400
    assert "attempt" in response.json()["detail"].lower()


def test_otp_request_is_rate_limited(client):
    client.post(OTP_REQUEST, json={"phone": "+919000000004"})

    response = client.post(OTP_REQUEST, json={"phone": "+919000000004"})

    assert response.status_code == 429


def test_otp_rejects_a_malformed_phone_number(client):
    response = client.post(OTP_REQUEST, json={"phone": "not-a-number"})

    assert response.status_code == 422


# --- Every user has both an email and a phone number ------------------------


def _auth(response) -> dict[str, str]:
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_an_email_signup_is_asked_for_a_phone_number(client):
    created = client.post(SIGNUP, json=TEACHER)
    assert created.json()["user"]["needs_contact_details"] is True

    updated = client.patch(ME, json={"phone": "+91 98765-43210"}, headers=_auth(created))

    assert updated.status_code == 200
    assert updated.json()["phone"] == "+919876543210"
    assert updated.json()["needs_contact_details"] is False
    # Typed into a form, not proven by a code.
    assert updated.json()["is_phone_verified"] is False


def test_a_phone_signup_is_asked_for_an_email(client):
    code = client.post(OTP_REQUEST, json={"phone": "+919000000050"}).json()["debug_otp"]
    created = client.post(OTP_VERIFY, json={"phone": "+919000000050", "otp": code})
    assert created.json()["user"]["needs_contact_details"] is True

    updated = client.patch(ME, json={"email": "Asha@Example.com"}, headers=_auth(created))

    assert updated.json()["email"] == "asha@example.com"
    assert updated.json()["needs_contact_details"] is False


def test_a_contact_already_on_another_account_is_refused(client):
    client.post(SIGNUP, json={**TEACHER, "identifier": "+919000000051"})
    other = client.post(SIGNUP, json={**TEACHER, "identifier": "other@example.com"})

    response = client.patch(ME, json={"phone": "+919000000051"}, headers=_auth(other))

    assert response.status_code == 409
    assert response.json()["detail"] == "That phone number is already used by another account"


def test_a_user_can_sign_in_with_either(client):
    created = client.post(SIGNUP, json=TEACHER)
    client.patch(ME, json={"phone": "+919000000052"}, headers=_auth(created))

    by_email = client.post(LOGIN, json={"email": "pranav@example.com", "password": "supersecret123"})
    by_phone = client.post(LOGIN, json={"email": "+919000000052", "password": "supersecret123"})

    assert by_email.status_code == by_phone.status_code == 200
    assert by_email.json()["user"]["user_id"] == by_phone.json()["user"]["user_id"]
