"""Verify local Firebase Admin access without printing project or account data."""

import sys

from firebase_admin import auth, firestore

from app.core.config import get_settings
from app.core.firebase import initialize_firebase


def main() -> None:
    try:
        settings = get_settings()
        if not settings.firebase_project_id:
            raise RuntimeError("FIREBASE_PROJECT_ID is not configured.")
        initialize_firebase(settings)
        auth.list_users(max_results=1)
        firestore.client().collection("users").limit(1).get()
    except Exception as error:
        print(
            f"Firebase Admin verification failed: {type(error).__name__}",
            file=sys.stderr,
        )
        raise SystemExit(1) from None

    print("Firebase Admin Authentication access verified.")
    print("Firebase Admin Firestore access verified.")


if __name__ == "__main__":
    main()
