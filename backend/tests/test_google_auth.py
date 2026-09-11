import pytest

from app import google_auth
from app.google_auth import GoogleAuthError, GoogleProfile, verify_google_id_token
from app.routers import auth as auth_router

GOOGLE = "/api/v1/auth/google"
SIGNUP = "/api/v1/auth/signup"
PROFILE = "/api/v1/auth/me"


@pytest.fixture()
def fake_google(monkeypatch):
    """Replace token verification so tests never call Google.

    Returns a setter the test uses to decide which profile the "token" resolves
    to. The real verification is covered separately in test_verification_*.
    """
    holder = {}

    def _verify(token: str, allowed_client_ids: list[str]) -> GoogleProfile:
        if token not in holder:
            raise GoogleAuthError("Could not verify Google sign-in: bad token")
        return holder[token]

    monkeypatch.setattr(auth_router, "verify_google_id_token", _verify)

    def register(token: str, **kwargs) -> None:
        holder[token] = GoogleProfile(
            google_id=kwargs.get("google_id", "google-sub-1"),
            email=kwargs.get("email", "pranav@gmail.com"),
            email_verified=kwargs.get("email_verified", True),
            full_name=kwargs.get("full_name", "Pranav Ahuja"),
        )

    return register


def test_first_google_login_creates_an_account(client, fake_google):
    fake_google("tok")

    response = client.post(GOOGLE, json={"id_token": "tok"})

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["is_new_user"] is True
    assert body["access_token"]
    assert body["user"]["email"] == "pranav@gmail.com"
    assert body["user"]["full_name"] == "Pranav Ahuja"
    # No teacher/student yet, so the app should show "Who are you?".
    assert body["user"]["account_type"] is None
    assert body["user"]["role"] is None
    assert body["user"]["needs_account_type"] is True


def test_second_google_login_reuses_the_same_account(client, fake_google):
    fake_google("tok")
    first = client.post(GOOGLE, json={"id_token": "tok"}).json()

    second = client.post(GOOGLE, json={"id_token": "tok"}).json()

    assert second["is_new_user"] is False
    assert second["user"]["user_id"] == first["user"]["user_id"]


def test_google_login_matches_on_sub_even_if_the_email_changed(client, fake_google):
    fake_google("tok")
    first = client.post(GOOGLE, json={"id_token": "tok"}).json()

    # Same Google account, new address — must not create a second user.
    fake_google("tok2", email="pranav.new@gmail.com")
    second = client.post(GOOGLE, json={"id_token": "tok2"}).json()

    assert second["user"]["user_id"] == first["user"]["user_id"]
    assert second["is_new_user"] is False


def test_google_login_links_to_an_existing_password_account(client, fake_google):
    created = client.post(
        SIGNUP,
        json={
            "full_name": "Pranav Ahuja",
            "identifier": "pranav@gmail.com",
            "password": "supersecret123",
            "account_type": 0,
        },
    ).json()

    fake_google("tok", email="pranav@gmail.com")
    response = client.post(GOOGLE, json={"id_token": "tok"}).json()

    # Same account, not a duplicate — and the teacher role is preserved.
    assert response["user"]["user_id"] == created["user"]["user_id"]
    assert response["is_new_user"] is False
    assert response["user"]["role"] == "teacher"
    assert response["user"]["needs_account_type"] is False


def test_google_login_will_not_take_over_an_account_via_unverified_email(
    client, fake_google
):
    created = client.post(
        SIGNUP,
        json={
            "full_name": "Pranav Ahuja",
            "identifier": "pranav@gmail.com",
            "password": "supersecret123",
            "account_type": 0,
        },
    ).json()

    # Google says it never confirmed this address, so claiming the existing
    # account would be an account-takeover hole.
    fake_google("tok", email="pranav@gmail.com", email_verified=False)
    response = client.post(GOOGLE, json={"id_token": "tok"})

    assert created["user"]["user_id"]
    assert response.status_code == 409
    assert "password" in response.json()["detail"]


def test_google_signup_drops_an_unverified_email(client, fake_google):
    """A new account may still be created, just without the untrusted address."""
    fake_google("tok", email="stranger@gmail.com", email_verified=False)

    response = client.post(GOOGLE, json={"id_token": "tok"})

    assert response.status_code == 200, response.text
    assert response.json()["is_new_user"] is True
    assert response.json()["user"]["email"] is None


def test_google_login_rejects_an_unverifiable_token(client, fake_google):
    fake_google("good-token")

    response = client.post(GOOGLE, json={"id_token": "forged"})

    assert response.status_code == 401
    assert "verify" in response.json()["detail"].lower()


def test_profile_completion_sets_name_and_account_type(client, fake_google):
    fake_google("tok")
    token = client.post(GOOGLE, json={"id_token": "tok"}).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    response = client.patch(
        PROFILE,
        json={"full_name": "Pranav A", "account_type": 0},
        headers=headers,
    )

    assert response.status_code == 200, response.text
    assert response.json()["full_name"] == "Pranav A"
    assert response.json()["role"] == "teacher"
    assert response.json()["needs_account_type"] is False


def test_profile_update_leaves_out_fields_alone(client, fake_google):
    fake_google("tok")
    token = client.post(GOOGLE, json={"id_token": "tok"}).json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    response = client.patch(PROFILE, json={"account_type": 1}, headers=headers)

    assert response.status_code == 200, response.text
    # Name came from the Google profile and was not part of this request.
    assert response.json()["full_name"] == "Pranav Ahuja"
    assert response.json()["role"] == "student"


def test_profile_update_rejects_an_empty_request(client, fake_google):
    fake_google("tok")
    token = client.post(GOOGLE, json={"id_token": "tok"}).json()["access_token"]

    response = client.patch(
        PROFILE, json={}, headers={"Authorization": f"Bearer {token}"}
    )

    assert response.status_code == 422


def test_profile_update_rejects_an_unknown_account_type(client, fake_google):
    fake_google("tok")
    token = client.post(GOOGLE, json={"id_token": "tok"}).json()["access_token"]

    response = client.patch(
        PROFILE,
        json={"account_type": 7},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 422


def test_profile_update_requires_a_token(client):
    assert client.patch(PROFILE, json={"account_type": 0}).status_code == 401


def test_unfinished_signup_still_asks_for_account_type_next_time(client, fake_google):
    """Someone who abandons the sign-up screen is not new, but still needs it.

    This is why the app must route on needs_account_type rather than
    is_new_user.
    """
    fake_google("tok")
    client.post(GOOGLE, json={"id_token": "tok"})

    second = client.post(GOOGLE, json={"id_token": "tok"}).json()

    assert second["is_new_user"] is False
    assert second["user"]["needs_account_type"] is True


def test_returning_login_updates_a_changed_email(client, fake_google):
    fake_google("tok")
    first = client.post(GOOGLE, json={"id_token": "tok"}).json()

    fake_google("tok2", email="pranav.new@gmail.com")
    second = client.post(GOOGLE, json={"id_token": "tok2"}).json()

    assert second["user"]["user_id"] == first["user"]["user_id"]
    assert second["user"]["email"] == "pranav.new@gmail.com"


def test_returning_login_keeps_old_email_when_the_new_one_is_taken(
    client, fake_google
):
    """A collision must never lock the user out — google_id still identifies
    them, so sign them in and leave the address alone."""
    client.post(
        SIGNUP,
        json={
            "full_name": "Somebody Else",
            "identifier": "taken@gmail.com",
            "password": "supersecret123",
            "account_type": 1,
        },
    )
    fake_google("tok")
    first = client.post(GOOGLE, json={"id_token": "tok"}).json()

    fake_google("tok2", email="taken@gmail.com")
    second = client.post(GOOGLE, json={"id_token": "tok2"})

    assert second.status_code == 200, second.text
    assert second.json()["user"]["user_id"] == first["user"]["user_id"]
    assert second.json()["user"]["email"] == "pranav@gmail.com"


def test_returning_login_does_not_overwrite_a_chosen_name(client, fake_google):
    fake_google("tok")
    token = client.post(GOOGLE, json={"id_token": "tok"}).json()["access_token"]
    client.patch(
        PROFILE,
        json={"full_name": "Mr. Ahuja"},
        headers={"Authorization": f"Bearer {token}"},
    )

    fake_google("tok2", full_name="Pranav Ahuja")
    second = client.post(GOOGLE, json={"id_token": "tok2"}).json()

    assert second["user"]["full_name"] == "Mr. Ahuja"


def test_returning_login_backfills_a_placeholder_name(client, fake_google):
    # A Google account with no name at all leaves the placeholder behind.
    fake_google("tok", full_name=None)
    first = client.post(GOOGLE, json={"id_token": "tok"}).json()
    assert first["user"]["full_name"] == "GrowBuddy User"

    fake_google("tok2", full_name="Pranav Ahuja")
    second = client.post(GOOGLE, json={"id_token": "tok2"}).json()

    assert second["user"]["full_name"] == "Pranav Ahuja"


def test_an_unverified_email_never_clears_a_stored_one(client, fake_google):
    fake_google("tok")
    client.post(GOOGLE, json={"id_token": "tok"})

    fake_google("tok2", email="spoofed@gmail.com", email_verified=False)
    second = client.post(GOOGLE, json={"id_token": "tok2"}).json()

    assert second["user"]["email"] == "pranav@gmail.com"


def test_verification_fails_when_no_client_ids_are_configured():
    with pytest.raises(GoogleAuthError, match="not configured"):
        verify_google_id_token("anything", [])


def test_verification_rejects_a_garbage_token(monkeypatch):
    """A malformed token must raise GoogleAuthError, not leak a library error.

    google-auth signals a bad token with ValueError and a bad issuer with its
    own GoogleAuthError; both have to be caught or the route returns a 500.
    """

    def _boom(*args, **kwargs):
        raise ValueError("Wrong number of segments in token")

    monkeypatch.setattr(google_auth.google_id_token, "verify_oauth2_token", _boom)

    with pytest.raises(GoogleAuthError, match="Could not verify"):
        verify_google_id_token("not-a-jwt", ["client-id.apps.googleusercontent.com"])
