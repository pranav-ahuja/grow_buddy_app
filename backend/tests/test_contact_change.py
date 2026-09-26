"""Changing your own email or mobile number, and proving it first.

A teacher editing their own contact details is the ordinary case this covers.
The rule being pinned is that the typed value is **not** their contact until a
code sent to it comes back: until then the account still signs in with the old
one, which is what stops a typo from locking somebody out of a flow the app
opens on.

The tests worth reading before changing any of this are the last three. They
are the ones that say what a code *cannot* do — commit a value it was not
issued for, commit somebody else's address, or survive being used twice.
"""

SIGNUP = "/api/v1/auth/signup"
LOGIN = "/api/v1/auth/login"
ME = "/api/v1/auth/me"
OTP_VERIFY = "/api/v1/auth/otp/verify"
CONTACT_REQUEST = "/api/v1/auth/me/contact/request"
CONTACT_VERIFY = "/api/v1/auth/me/contact/verify"

PASSWORD = "supersecret123"
ACCOUNT_TYPE_TEACHER = 0

OLD_EMAIL = "asha@example.com"
NEW_EMAIL = "asha.rao@example.com"
OLD_PHONE = "+919876543210"
NEW_PHONE = "+919000000001"


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def signup(client, identifier: str, name: str = "Asha Rao") -> str:
    response = client.post(
        SIGNUP,
        json={
            "full_name": name,
            "identifier": identifier,
            "password": PASSWORD,
            "account_type": ACCOUNT_TYPE_TEACHER,
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["access_token"]


def teacher_with_both(client) -> str:
    """A signed-up teacher who has an email *and* a number.

    Sign-up takes one identifier, so the other is filled in through
    `PATCH /auth/me` — which is still the right route for a contact that is
    missing. What needs proving is a contact being *replaced*.
    """
    token = signup(client, OLD_EMAIL)
    response = client.patch(ME, json={"phone": OLD_PHONE}, headers=auth(token))
    assert response.status_code == 200, response.text
    return token


def request_code(client, token: str, channel: str, value: str):
    return client.post(
        CONTACT_REQUEST,
        json={"channel": channel, "value": value},
        headers=auth(token),
    )


# --- The number ------------------------------------------------------------


def test_requesting_a_code_does_not_change_the_number(client):
    """The whole reason the change is staged.

    A request that moved the number first and flagged it unverified would make
    the unproven number the one login looks up — so this asserts the opposite
    of what the obvious implementation does.
    """
    token = teacher_with_both(client)

    response = request_code(client, token, "phone", NEW_PHONE)

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["channel"] == "phone"
    assert body["value"] == NEW_PHONE
    # Dev-only, and the only way to exercise this without an SMS provider.
    assert body["debug_otp"] is not None

    me = client.get(ME, headers=auth(token)).json()
    assert me["phone"] == OLD_PHONE


def test_the_old_number_still_logs_in_while_a_change_is_pending(client):
    """An abandoned change costs nothing.

    Phone + OTP is the default login screen, so "can I still get in?" is the
    question a half-finished change has to answer the same way as no change
    at all.
    """
    token = teacher_with_both(client)
    request_code(client, token, "phone", NEW_PHONE)

    # The old number still signs in, because it is still the number on the
    # account. This is the assertion the whole staged design exists to make
    # true.
    response = client.post(LOGIN, json={"email": OLD_PHONE, "password": PASSWORD})
    assert response.status_code == 200, response.text
    assert response.json()["user"]["phone"] == OLD_PHONE

    # And the number being moved to belongs to nobody yet, so it signs in as
    # nobody — rather than as a half-made version of this account.
    pending = client.post(LOGIN, json={"email": NEW_PHONE, "password": PASSWORD})
    assert pending.status_code == 401, pending.text


def test_verifying_the_code_moves_the_number_and_marks_it_verified(client):
    token = teacher_with_both(client)
    code = request_code(client, token, "phone", NEW_PHONE).json()["debug_otp"]

    response = client.post(
        CONTACT_VERIFY,
        json={"channel": "phone", "otp": code},
        headers=auth(token),
    )

    assert response.status_code == 200, response.text
    user = response.json()
    assert user["phone"] == NEW_PHONE
    # Earned by the round trip, not assumed. PATCH /auth/me clears this flag
    # for exactly the reason this route may set it.
    assert user["is_phone_verified"] is True


def test_after_verifying_the_new_number_is_the_one_that_logs_in(client):
    """What the change is *for*: the next login uses the new number."""
    token = teacher_with_both(client)
    code = request_code(client, token, "phone", NEW_PHONE).json()["debug_otp"]
    client.post(
        CONTACT_VERIFY,
        json={"channel": "phone", "otp": code},
        headers=auth(token),
    )

    # Logging in by the new number reaches the same account...
    response = client.post(LOGIN, json={"email": NEW_PHONE, "password": PASSWORD})
    assert response.status_code == 200, response.text
    assert response.json()["user"]["email"] == OLD_EMAIL

    # ...and the old one no longer resolves to anybody.
    stale = client.post(LOGIN, json={"email": OLD_PHONE, "password": PASSWORD})
    assert stale.status_code == 401, stale.text


def test_an_otp_login_on_the_new_number_is_the_same_account(client):
    """Not a second account.

    The trap this whole design exists to avoid: `/auth/otp/verify` resolves an
    account *from the number in the request* and creates one when nobody holds
    it. Once the change is committed, that number is held — by this user.
    """
    token = teacher_with_both(client)
    code = request_code(client, token, "phone", NEW_PHONE).json()["debug_otp"]
    client.post(
        CONTACT_VERIFY,
        json={"channel": "phone", "otp": code},
        headers=auth(token),
    )

    sent = client.post("/api/v1/auth/otp/request", json={"phone": NEW_PHONE})
    login = client.post(
        OTP_VERIFY,
        json={"phone": NEW_PHONE, "otp": sent.json()["debug_otp"]},
    )

    assert login.status_code == 200, login.text
    assert login.json()["is_new_user"] is False
    assert login.json()["user"]["email"] == OLD_EMAIL


# --- The email -------------------------------------------------------------


def test_the_email_change_works_the_same_way(client):
    token = teacher_with_both(client)

    pending = request_code(client, token, "email", NEW_EMAIL)
    assert pending.status_code == 200, pending.text
    assert client.get(ME, headers=auth(token)).json()["email"] == OLD_EMAIL

    response = client.post(
        CONTACT_VERIFY,
        json={"channel": "email", "otp": pending.json()["debug_otp"]},
        headers=auth(token),
    )

    assert response.status_code == 200, response.text
    assert response.json()["email"] == NEW_EMAIL
    # And the new address is what signs in.
    login = client.post(LOGIN, json={"email": NEW_EMAIL, "password": PASSWORD})
    assert login.status_code == 200, login.text


def test_an_email_is_normalised_before_it_is_stored(client):
    """Stored lower-cased, like every other route that writes this column.

    Two rules for one column is how an address is saved in a form no login
    will ever match.
    """
    token = teacher_with_both(client)
    pending = request_code(client, token, "email", "  Asha.RAO@Example.COM ")

    assert pending.json()["value"] == NEW_EMAIL
    response = client.post(
        CONTACT_VERIFY,
        json={"channel": "email", "otp": pending.json()["debug_otp"]},
        headers=auth(token),
    )
    assert response.json()["email"] == NEW_EMAIL


# --- Refusals --------------------------------------------------------------


def test_an_unauthenticated_request_is_refused(client):
    """Unlike `/auth/otp/request`, which has to be open for phone login.

    This route changes a specific account's contact, so it needs to know which
    account before it will send anything at all.
    """
    response = client.post(
        CONTACT_REQUEST, json={"channel": "phone", "value": NEW_PHONE}
    )
    assert response.status_code in (401, 403), response.text


def test_asking_for_the_number_you_already_have_is_refused(client):
    token = teacher_with_both(client)

    response = request_code(client, token, "phone", OLD_PHONE)

    assert response.status_code == 400, response.text
    assert "already your phone number" in response.json()["detail"]


def test_a_number_another_account_holds_is_refused_before_a_code_is_sent(client):
    """Told now rather than after waiting for a code that could never work."""
    other = signup(client, "someone-else@example.com", name="Ravi Kumar")
    client.patch(ME, json={"phone": NEW_PHONE}, headers=auth(other))

    token = teacher_with_both(client)
    response = request_code(client, token, "phone", NEW_PHONE)

    assert response.status_code == 409, response.text
    assert "already used by another account" in response.json()["detail"]


def test_a_wrong_code_counts_down_and_changes_nothing(client):
    token = teacher_with_both(client)
    request_code(client, token, "phone", NEW_PHONE)

    response = client.post(
        CONTACT_VERIFY,
        json={"channel": "phone", "otp": "000000"},
        headers=auth(token),
    )

    assert response.status_code == 400, response.text
    assert "attempt(s) left" in response.json()["detail"]
    assert client.get(ME, headers=auth(token)).json()["phone"] == OLD_PHONE


def test_a_second_code_retires_the_first(client):
    """Changing the number twice must not leave the first code able to commit
    the first number — the value rides on the row, so a stale code is a stale
    destination."""
    token = teacher_with_both(client)
    first = request_code(client, token, "phone", NEW_PHONE).json()["debug_otp"]

    # The cooldown is per user and channel, so the second request has to come
    # from outside it. Retiring is what the endpoint does before issuing.
    import app.routers.auth as auth_routes

    original = auth_routes.OTP_RESEND_COOLDOWN_SECONDS
    auth_routes.OTP_RESEND_COOLDOWN_SECONDS = 0
    try:
        second = request_code(client, token, "phone", "+919000000002")
    finally:
        auth_routes.OTP_RESEND_COOLDOWN_SECONDS = original

    assert second.status_code == 200, second.text

    stale = client.post(
        CONTACT_VERIFY,
        json={"channel": "phone", "otp": first},
        headers=auth(token),
    )
    assert stale.status_code == 400, stale.text
    assert client.get(ME, headers=auth(token)).json()["phone"] == OLD_PHONE

    # The newest code commits the newest value, not the first one.
    ok = client.post(
        CONTACT_VERIFY,
        json={"channel": "phone", "otp": second.json()["debug_otp"]},
        headers=auth(token),
    )
    assert ok.status_code == 200, ok.text
    assert ok.json()["phone"] == "+919000000002"


def test_a_phone_code_cannot_be_redeemed_as_an_email_change(client):
    """The channel picks the column, so a code is only good for the one it was
    issued on."""
    token = teacher_with_both(client)
    code = request_code(client, token, "phone", NEW_PHONE).json()["debug_otp"]

    response = client.post(
        CONTACT_VERIFY,
        json={"channel": "email", "otp": code},
        headers=auth(token),
    )

    assert response.status_code == 400, response.text
    me = client.get(ME, headers=auth(token)).json()
    assert me["email"] == OLD_EMAIL
    assert me["phone"] == OLD_PHONE


def test_a_code_cannot_be_used_twice(client):
    token = teacher_with_both(client)
    code = request_code(client, token, "phone", NEW_PHONE).json()["debug_otp"]

    first = client.post(
        CONTACT_VERIFY,
        json={"channel": "phone", "otp": code},
        headers=auth(token),
    )
    assert first.status_code == 200, first.text

    again = client.post(
        CONTACT_VERIFY,
        json={"channel": "phone", "otp": code},
        headers=auth(token),
    )
    assert again.status_code == 400, again.text


def test_a_number_claimed_between_the_code_and_the_verify_is_refused(client):
    """Re-validated against the world as it is at verify time.

    The same rule `app/approvals.py` follows when it grants a request: what was
    free when it was asked for may be taken by the time it runs, and a refusal
    then is a normal outcome — not a 500 from a unique index.
    """
    token = teacher_with_both(client)
    code = request_code(client, token, "phone", NEW_PHONE).json()["debug_otp"]

    # Somebody else takes that number in the meantime.
    other = signup(client, "someone-else@example.com", name="Ravi Kumar")
    client.patch(ME, json={"phone": NEW_PHONE}, headers=auth(other))

    response = client.post(
        CONTACT_VERIFY,
        json={"channel": "phone", "otp": code},
        headers=auth(token),
    )

    assert response.status_code == 409, response.text
    assert client.get(ME, headers=auth(token)).json()["phone"] == OLD_PHONE


def test_a_resend_inside_the_cooldown_is_refused(client):
    """The same 30 seconds as phone login, from the same constant."""
    token = teacher_with_both(client)
    request_code(client, token, "phone", NEW_PHONE)

    response = request_code(client, token, "phone", NEW_PHONE)

    assert response.status_code == 429, response.text
    assert "before requesting another code" in response.json()["detail"]


def test_an_unknown_channel_is_refused(client):
    token = teacher_with_both(client)

    response = request_code(client, token, "fax", "+919000000003")

    assert response.status_code == 422, response.text
