from dataclasses import dataclass
from typing import Annotated, Literal

from fastapi import Depends, Header, status
from firebase_admin import auth, firestore

from app.core.config import Settings, get_settings
from app.core.errors import ApiError


@dataclass(frozen=True)
class AuthenticatedUser:
    uid: str
    role: Literal["student", "agent", "admin"] = "student"
    disabled: bool = False


async def require_user(authorization: str | None = Header(default=None)) -> AuthenticatedUser:
    if not authorization or not authorization.startswith("Bearer "):
        raise ApiError(
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="AUTH_REQUIRED",
            message="A Firebase ID token is required.",
        )

    token = authorization.removeprefix("Bearer ").strip()
    if not token:
        raise ApiError(
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="AUTH_REQUIRED",
            message="A Firebase ID token is required.",
        )

    try:
        decoded = auth.verify_id_token(token, check_revoked=True)
        firebase_user = auth.get_user(decoded["uid"])
    except (auth.InvalidIdTokenError, auth.ExpiredIdTokenError, auth.RevokedIdTokenError) as error:
        raise ApiError(
            status_code=status.HTTP_401_UNAUTHORIZED,
            code="AUTH_INVALID",
            message="The Firebase ID token is invalid or expired.",
        ) from error

    profile = firestore.client().collection("users").document(decoded["uid"]).get()
    profile_data = profile.to_dict() if profile.exists else None
    role = profile_data.get("role") if profile_data is not None else None
    if (
        firebase_user.disabled
        or profile_data is None
        or profile_data.get("status") != "active"
        or role not in {"student", "agent", "admin"}
    ):
        raise ApiError(
            status_code=status.HTTP_403_FORBIDDEN,
            code="ACCOUNT_DISABLED",
            message="This account is disabled or unavailable.",
        )

    return AuthenticatedUser(uid=decoded["uid"], role=role, disabled=False)


async def require_student(
    user: Annotated[AuthenticatedUser, Depends(require_user)],
) -> AuthenticatedUser:
    if user.role != "student":
        raise ApiError(
            status_code=status.HTTP_403_FORBIDDEN,
            code="ROLE_FORBIDDEN",
            message="This AI feature is available only to active student accounts.",
        )
    return user


def settings_for_auth() -> Settings:
    return get_settings()
