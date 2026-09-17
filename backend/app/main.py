import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.config import settings
from app.database import engine
from app.migrations import require_current
from app.routers import attendance, auth, classes, subjects, teachers

logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Before anything else: a dev-only setting left on in a real deployment
    # should stop the server, not serve traffic.
    settings.check_safe_for_environment()

    if settings.otp_debug_return:
        logging.getLogger(__name__).warning(
            "OTP_DEBUG_RETURN is on: verification codes are returned in the API "
            "response and printed below. Development only."
        )

    # The schema is Alembic's now. This only checks; it never migrates — see
    # app/migrations.py for why applying one stays a command someone runs.
    require_current(engine)
    yield


app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)

# Wide open because the only clients today are a Flutter app on a LAN and the
# Swagger page. Restrict to real origins before this is exposed publicly.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(RequestValidationError)
async def validation_error_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    """Collapse FastAPI's nested validation errors into one readable sentence.

    The app drops `detail` straight into a SnackBar, and the default payload is
    a list of objects that renders as noise.
    """
    messages = []
    for error in exc.errors():
        field = error["loc"][-1] if error.get("loc") else "request"
        message = error.get("msg", "is invalid")
        message = message.removeprefix("Value error, ")
        messages.append(f"{field}: {message}")

    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={"detail": " | ".join(messages) or "Invalid request"},
    )


@app.get("/health", tags=["meta"])
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(auth.router, prefix=settings.api_prefix)
app.include_router(classes.router, prefix=settings.api_prefix)
app.include_router(subjects.router, prefix=settings.api_prefix)
app.include_router(attendance.router, prefix=settings.api_prefix)
app.include_router(teachers.router, prefix=settings.api_prefix)
