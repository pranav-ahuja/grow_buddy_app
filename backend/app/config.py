import secrets

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "GrowBuddy API"
    api_prefix: str = "/api/v1"

    # Gates the dev-only conveniences below. Defaults to development so a fresh
    # clone runs with zero setup; anything else is treated as "this is real".
    environment: str = "development"

    # Empty means "generate a throwaway key at startup" — every restart then
    # invalidates existing tokens. Set SECRET_KEY in .env before deploying.
    secret_key: str = ""
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7

    database_url: str = "sqlite:///./growbuddy.db"

    otp_debug_return: bool = True
    otp_expire_minutes: int = 5
    otp_max_attempts: int = 5
    otp_length: int = 6

    # Comma-separated OAuth client IDs that we accept ID tokens for. Each
    # platform (Android, iOS, web) gets its own ID from Google Cloud Console,
    # and a token is only trusted if its "aud" claim matches one of these.
    google_client_ids: str = ""

    @property
    def is_development(self) -> bool:
        return self.environment.strip().lower() in {"development", "dev", "local"}

    @property
    def google_client_id_list(self) -> list[str]:
        return [item.strip() for item in self.google_client_ids.split(",") if item.strip()]

    def check_safe_for_environment(self) -> None:
        """Refuse to start with a development-only setting in a real deployment.

        `otp_debug_return` hands the OTP back in the API response. That is the
        only reason phone login works before an SMS provider exists, so it
        cannot simply be deleted — but left on outside development it means
        anyone can request a code for a number they do not own and read it
        straight out of the response, which is a full account takeover of every
        phone account.

        Failing at startup rather than warning is deliberate: a warning in a log
        nobody reads is how this reaches production.
        """
        if self.is_development:
            return

        if self.otp_debug_return:
            raise RuntimeError(
                f"OTP_DEBUG_RETURN must be false when ENVIRONMENT is "
                f"{self.environment!r}. It returns the OTP in the API response, "
                "which lets anyone take over any phone account. Set "
                "OTP_DEBUG_RETURN=false and wire up an SMS provider in "
                "app/routers/auth.py request_otp()."
            )

    def resolved_secret_key(self) -> str:
        if not self.secret_key:
            self.secret_key = secrets.token_urlsafe(48)
        return self.secret_key


settings = Settings()
