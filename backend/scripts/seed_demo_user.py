"""Provision an agent or administrator account with Firebase Admin.

The password is read from SEED_USER_PASSWORD in the process environment or
the ignored local environment file so it is never accepted as a CLI argument.
"""

import argparse
import os
from dataclasses import dataclass

from firebase_admin import auth, firestore

from app.core.config import Settings, get_settings
from app.core.firebase import initialize_firebase

ALLOWED_ROLES = frozenset({"agent", "admin"})


@dataclass(frozen=True)
class SeedRequest:
    email: str
    name: str
    role: str
    project_id: str
    password: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Provision a Firebase agent or administrator demo account."
    )
    parser.add_argument("--email", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--role", required=True, choices=sorted(ALLOWED_ROLES))
    parser.add_argument("--project-id", required=True)
    return parser.parse_args()


def build_request(args: argparse.Namespace) -> SeedRequest:
    password = os.environ.get("SEED_USER_PASSWORD") or Settings().seed_user_password or ""
    if len(password) < 12:
        raise ValueError("SEED_USER_PASSWORD must contain at least 12 characters.")
    email = args.email.strip().lower()
    name = args.name.strip()
    if "@" not in email:
        raise ValueError("A valid email address is required.")
    if len(name) < 2:
        raise ValueError("A name with at least two characters is required.")
    return SeedRequest(
        email=email,
        name=name,
        role=args.role,
        project_id=args.project_id.strip(),
        password=password,
    )


def initialize(project_id: str) -> None:
    initialize_firebase(get_settings(), project_id=project_id)


def _existing_roles(user) -> set[str]:
    claims = getattr(user, "custom_claims", None)
    claim_role = claims.get("role") if isinstance(claims, dict) else None
    profile_document = firestore.client().collection("users").document(user.uid).get()
    profile = profile_document.to_dict() if profile_document.exists else None
    profile_role = profile.get("role") if isinstance(profile, dict) else None
    return {
        role for role in (claim_role, profile_role) if isinstance(role, str) and role.strip() != ""
    }


def provision(request: SeedRequest) -> tuple[str, bool]:
    initialize(request.project_id)
    created = False
    try:
        user = auth.get_user_by_email(request.email)
        existing_roles = _existing_roles(user)
        if existing_roles and existing_roles != {request.role}:
            raise ValueError(
                "The existing Firebase account has a different role and was not modified."
            )
        user = auth.update_user(
            user.uid,
            display_name=request.name,
            password=request.password,
            disabled=False,
        )
    except auth.UserNotFoundError:
        user = auth.create_user(
            email=request.email,
            password=request.password,
            display_name=request.name,
            disabled=False,
        )
        created = True

    try:
        auth.set_custom_user_claims(user.uid, {"role": request.role})
        profile = {
            "name": request.name,
            "email": request.email,
            "role": request.role,
            "status": "active",
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }
        if created:
            profile["createdAt"] = firestore.SERVER_TIMESTAMP
        firestore.client().collection("users").document(user.uid).set(profile, merge=True)
    except Exception:
        if created:
            auth.delete_user(user.uid)
        raise
    return user.uid, created


def verify_provisioned_user(request: SeedRequest, uid: str) -> bool:
    user = auth.get_user(uid)
    claims = user.custom_claims if isinstance(user.custom_claims, dict) else {}
    profile_document = firestore.client().collection("users").document(uid).get()
    profile = profile_document.to_dict() if profile_document.exists else None
    return (
        user.email == request.email
        and user.display_name == request.name
        and user.disabled is False
        and claims.get("role") == request.role
        and isinstance(profile, dict)
        and profile.get("email") == request.email
        and profile.get("name") == request.name
        and profile.get("role") == request.role
        and profile.get("status") == "active"
    )


def main() -> None:
    request = build_request(parse_args())
    uid, created = provision(request)
    if not verify_provisioned_user(request, uid):
        raise RuntimeError("The Firebase account could not be verified after provisioning.")
    action = "created" if created else "updated"
    print(f"Firebase {request.role} account {action} and verified.")


if __name__ == "__main__":
    main()
