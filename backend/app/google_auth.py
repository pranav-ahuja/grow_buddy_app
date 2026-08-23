"""Verification of Google Sign-In ID tokens.

The app never tells us who the user is. It hands us an **ID token**: a JWT that
Google itself signed. We check that signature against Google's public keys, so a
caller cannot simply POST `{"email": "principal@school.com"}` and be believed.

Trusting a client-supplied email is the classic way this feature gets built
insecurely — anyone with curl could then log in as anybody.
"""

from dataclasses import dataclass

from google.auth import exceptions as google_exceptions
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token


class GoogleAuthError(Exception):
    """The token was missing, malformed, expired, or not meant for us."""


@dataclass(frozen=True)
class GoogleProfile:
    """The bits of a verified Google account we actually store."""

    google_id: str  # the "sub" claim — permanent and unique per Google account
    email: str | None
    email_verified: bool
    full_name: str | None


def verify_google_id_token(token: str, allowed_client_ids: list[str]) -> GoogleProfile:
    """Validate `token` with Google and return the profile inside it.

    Raises GoogleAuthError if the token cannot be trusted.
    """
    if not allowed_client_ids:
        raise GoogleAuthError(
            "Google sign-in is not configured on the server "
            "(GOOGLE_CLIENT_IDS is empty)."
        )

    try:
        # One call checks the signature against Google's published keys, that
        # the token has not expired, that Google issued it, and that its "aud"
        # claim is one of ours. The audience check is what stops a token minted
        # for somebody else's app from being replayed against this backend.
        claims = google_id_token.verify_oauth2_token(
            token,
            google_requests.Request(),
            audience=allowed_client_ids,
        )
    except (ValueError, google_exceptions.GoogleAuthError) as error:
        # ValueError covers a bad signature, expiry, or audience mismatch;
        # GoogleAuthError covers an unexpected issuer.
        raise GoogleAuthError(f"Could not verify Google sign-in: {error}") from error

    google_id = claims.get("sub")
    if not google_id:
        raise GoogleAuthError("Google sign-in token is missing a subject.")

    return GoogleProfile(
        google_id=google_id,
        email=(claims.get("email") or "").lower() or None,
        email_verified=bool(claims.get("email_verified")),
        full_name=claims.get("name"),
    )
