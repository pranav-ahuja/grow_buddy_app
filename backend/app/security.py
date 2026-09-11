import secrets
from datetime import timedelta

import bcrypt
import jwt

from app.config import settings
from app.timeutils import utcnow

# bcrypt refuses inputs longer than this, so the API rejects them up front
# rather than letting the hash call blow up mid-request.
MAX_PASSWORD_BYTES = 72


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode()[:MAX_PASSWORD_BYTES], bcrypt.gensalt()).decode()


def verify_password(password: str, hashed: str | None) -> bool:
    if not hashed:
        return False
    try:
        return bcrypt.checkpw(password.encode()[:MAX_PASSWORD_BYTES], hashed.encode())
    except ValueError:
        # Malformed hash in the database — treat as a failed login, not a 500.
        return False


def create_access_token(user_id: str) -> str:
    expires_at = utcnow() + timedelta(minutes=settings.access_token_expire_minutes)
    payload = {
        "sub": user_id,
        "exp": expires_at,
        "iat": utcnow(),
    }
    return jwt.encode(
        payload, settings.resolved_secret_key(), algorithm=settings.algorithm
    )


def decode_access_token(token: str) -> str | None:
    """Return the user id (U_000001) carried by the token, or None if it is not
    valid."""
    try:
        payload = jwt.decode(
            token, settings.resolved_secret_key(), algorithms=[settings.algorithm]
        )
        subject = payload["sub"]
    except (jwt.InvalidTokenError, KeyError, TypeError, ValueError):
        return None
    return subject if isinstance(subject, str) and subject else None


def generate_otp() -> str:
    upper_bound = 10**settings.otp_length
    return str(secrets.randbelow(upper_bound)).zfill(settings.otp_length)


def hash_otp(code: str) -> str:
    return bcrypt.hashpw(code.encode(), bcrypt.gensalt()).decode()


def verify_otp(code: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(code.encode(), hashed.encode())
    except ValueError:
        return False
