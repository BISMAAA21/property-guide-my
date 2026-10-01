"""Exercise the live Firebase client self-registration path for one student."""

import argparse
import sys
from dataclasses import dataclass

import httpx
from firebase_admin import auth, firestore

from app.core.config import Settings, get_settings
from app.core.firebase import initialize_firebase
from scripts.verify_firebase_password_sign_in import verify as verify_password_sign_in

SIGN_UP_URL = "https://identitytoolkit.googleapis.com/v1/accounts:signUp"
UPDATE_ACCOUNT_URL = "https://identitytoolkit.googleapis.com/v1/accounts:update"
DELETE_ACCOUNT_URL = "https://identitytoolkit.googleapis.com/v1/accounts:delete"


@dataclass(frozen=True)
class StudentRegistration:
    email: str
    name: str
    password: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Register a controlled student through Firebase client APIs."
    )
    parser.add_argument("--email", required=True)
    parser.add_argument("--name", required=True)
    return parser.parse_args()


def build_registration(args: argparse.Namespace, settings: Settings) -> StudentRegistration:
    email = args.email.strip().lower()
    name = args.name.strip()
    password = settings.seed_user_password or ""
    if "@" not in email:
        raise ValueError("A valid email address is required.")
    if len(name) < 2:
        raise ValueError("A name with at least two characters is required.")
    if len(password) < 12:
        raise ValueError("SEED_USER_PASSWORD must contain at least 12 characters.")
    if not settings.firebase_api_key or not settings.firebase_project_id:
        raise RuntimeError("Firebase client configuration is required.")
    return StudentRegistration(email=email, name=name, password=password)


def _post(
    url: str,
    settings: Settings,
    *,
    payload: dict,
    headers: dict[str, str] | None = None,
) -> dict:
    response = httpx.post(
        url,
        params={"key": settings.firebase_api_key} if url != _commit_url(settings) else None,
        json=payload,
        headers=headers,
        timeout=20,
    )
    if response.status_code != 200:
        raise RuntimeError("A Firebase client registration request was rejected.")
    result = response.json()
    if not isinstance(result, dict):
        raise RuntimeError("Firebase returned an invalid registration response.")
    return result


def _commit_url(settings: Settings) -> str:
    return (
        "https://firestore.googleapis.com/v1/projects/"
        f"{settings.firebase_project_id}/databases/(default)/documents:commit"
    )


def _profile_is_exact(uid: str, registration: StudentRegistration) -> bool:
    user = auth.get_user(uid)
    claims = user.custom_claims if isinstance(user.custom_claims, dict) else {}
    profile_document = firestore.client().collection("users").document(uid).get()
    profile = profile_document.to_dict() if profile_document.exists else None
    return (
        user.email == registration.email
        and user.display_name == registration.name
        and user.disabled is False
        and claims.get("role") is None
        and isinstance(profile, dict)
        and profile.get("email") == registration.email
        and profile.get("name") == registration.name
        and profile.get("role") == "student"
        and profile.get("status") == "active"
    )


def _existing_registration_is_exact(registration: StudentRegistration) -> bool:
    try:
        existing = auth.get_user_by_email(registration.email)
    except auth.UserNotFoundError:
        return False
    if not _profile_is_exact(existing.uid, registration):
        raise RuntimeError("The existing Firebase account does not match the controlled student.")
    return True


def _delete_new_account(settings: Settings, id_token: str) -> bool:
    try:
        _post(
            DELETE_ACCOUNT_URL,
            settings,
            payload={"idToken": id_token},
        )
    except Exception:
        return False
    return True


def register(registration: StudentRegistration, settings: Settings) -> bool:
    initialize_firebase(settings)
    if _existing_registration_is_exact(registration):
        if not verify_password_sign_in(registration.email, "student"):
            raise RuntimeError("The existing controlled student could not be verified.")
        return False

    sign_up = _post(
        SIGN_UP_URL,
        settings,
        payload={
            "email": registration.email,
            "password": registration.password,
            "returnSecureToken": True,
        },
    )
    id_token = sign_up.get("idToken")
    uid = sign_up.get("localId")
    if not isinstance(id_token, str) or not id_token or not isinstance(uid, str) or not uid:
        raise RuntimeError("Firebase returned an invalid sign-up response.")

    try:
        updated = _post(
            UPDATE_ACCOUNT_URL,
            settings,
            payload={
                "idToken": id_token,
                "displayName": registration.name,
                "returnSecureToken": True,
            },
        )
        updated_token = updated.get("idToken")
        if isinstance(updated_token, str) and updated_token:
            id_token = updated_token

        document_name = (
            f"projects/{settings.firebase_project_id}/databases/(default)/documents/users/{uid}"
        )
        _post(
            _commit_url(settings),
            settings,
            headers={"Authorization": f"Bearer {id_token}"},
            payload={
                "writes": [
                    {
                        "update": {
                            "name": document_name,
                            "fields": {
                                "name": {"stringValue": registration.name},
                                "email": {"stringValue": registration.email},
                                "role": {"stringValue": "student"},
                                "status": {"stringValue": "active"},
                            },
                        },
                        "updateTransforms": [
                            {
                                "fieldPath": "createdAt",
                                "setToServerValue": "REQUEST_TIME",
                            },
                            {
                                "fieldPath": "updatedAt",
                                "setToServerValue": "REQUEST_TIME",
                            },
                        ],
                        "currentDocument": {"exists": False},
                    }
                ]
            },
        )
        if not _profile_is_exact(uid, registration):
            raise RuntimeError("The controlled student profile could not be verified.")
        if not verify_password_sign_in(registration.email, "student"):
            raise RuntimeError("The controlled student sign-in could not be verified.")
    except Exception:
        if not _delete_new_account(settings, id_token):
            raise RuntimeError("Student registration and rollback both failed.") from None
        raise
    return True


def main() -> None:
    try:
        settings = get_settings()
        registration = build_registration(parse_args(), settings)
        created = register(registration, settings)
    except Exception as error:
        print(
            f"Firebase student registration failed: {type(error).__name__}",
            file=sys.stderr,
        )
        raise SystemExit(1) from None
    action = "created" if created else "already existed"
    print(f"Firebase student account {action} and verified through client APIs.")


if __name__ == "__main__":
    main()
