"""Verify live password sign-in without printing credentials, tokens, or user data."""

import argparse
import sys

import httpx
from firebase_admin import auth, firestore

from app.core.config import get_settings
from app.core.firebase import initialize_firebase

SIGN_IN_URL = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify a controlled Firebase email/password role account."
    )
    parser.add_argument("--email", required=True)
    parser.add_argument("--role", required=True, choices=("student", "agent", "admin"))
    return parser.parse_args()


def verify(email: str, role: str) -> bool:
    settings = get_settings()
    if not settings.firebase_api_key or not settings.seed_user_password:
        raise RuntimeError("Firebase client configuration and seed password are required.")
    initialize_firebase(settings)

    response = httpx.post(
        SIGN_IN_URL,
        params={"key": settings.firebase_api_key},
        json={
            "email": email.strip().lower(),
            "password": settings.seed_user_password,
            "returnSecureToken": True,
        },
        timeout=20,
    )
    if response.status_code != 200:
        raise RuntimeError("Firebase password sign-in was rejected.")
    payload = response.json()
    id_token = payload.get("idToken")
    local_id = payload.get("localId")
    if not isinstance(id_token, str) or not id_token or not isinstance(local_id, str):
        raise RuntimeError("Firebase password sign-in returned an invalid response.")

    decoded = auth.verify_id_token(id_token, check_revoked=True)
    profile_document = firestore.client().collection("users").document(local_id).get()
    profile = profile_document.to_dict() if profile_document.exists else None
    token_role = decoded.get("role")
    token_role_matches = token_role == role if role != "student" else token_role is None
    return (
        decoded.get("uid") == local_id
        and token_role_matches
        and isinstance(profile, dict)
        and profile.get("email") == email.strip().lower()
        and profile.get("role") == role
        and profile.get("status") == "active"
    )


def main() -> None:
    args = parse_args()
    try:
        verified = verify(args.email, args.role)
    except Exception as error:
        print(
            f"Firebase password sign-in verification failed: {type(error).__name__}",
            file=sys.stderr,
        )
        raise SystemExit(1) from None
    if not verified:
        print("Firebase password sign-in verification failed: role mismatch.", file=sys.stderr)
        raise SystemExit(1)
    print("Firebase password sign-in and role profile verified.")


if __name__ == "__main__":
    main()
