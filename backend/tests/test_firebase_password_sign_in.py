from unittest.mock import patch

from app.core.config import Settings
from scripts.verify_firebase_password_sign_in import verify


def _settings() -> Settings:
    return Settings(
        _env_file=None,
        firebase_project_id="demo-project",
        firebase_api_key="controlled-client-key",
        seed_user_password="controlled-demo-password",
    )


def test_verify_accepts_matching_token_and_active_profile() -> None:
    with (
        patch(
            "scripts.verify_firebase_password_sign_in.get_settings",
            return_value=_settings(),
        ),
        patch("scripts.verify_firebase_password_sign_in.initialize_firebase"),
        patch("scripts.verify_firebase_password_sign_in.httpx.post") as post,
        patch(
            "scripts.verify_firebase_password_sign_in.auth.verify_id_token",
            return_value={"uid": "agent-one", "role": "agent"},
        ),
        patch("scripts.verify_firebase_password_sign_in.firestore.client") as firestore_client,
    ):
        post.return_value.status_code = 200
        post.return_value.json.return_value = {
            "idToken": "controlled-token",
            "localId": "agent-one",
        }
        document = firestore_client.return_value.collection.return_value.document.return_value
        profile = document.get.return_value
        profile.exists = True
        profile.to_dict.return_value = {
            "email": "agent@example.test",
            "role": "agent",
            "status": "active",
        }

        verified = verify("agent@example.test", "agent")

    assert verified is True
    request_json = post.call_args.kwargs["json"]
    assert request_json["password"] == "controlled-demo-password"


def test_verify_rejects_a_mismatched_profile_role() -> None:
    with (
        patch(
            "scripts.verify_firebase_password_sign_in.get_settings",
            return_value=_settings(),
        ),
        patch("scripts.verify_firebase_password_sign_in.initialize_firebase"),
        patch("scripts.verify_firebase_password_sign_in.httpx.post") as post,
        patch(
            "scripts.verify_firebase_password_sign_in.auth.verify_id_token",
            return_value={"uid": "agent-one", "role": "agent"},
        ),
        patch("scripts.verify_firebase_password_sign_in.firestore.client") as firestore_client,
    ):
        post.return_value.status_code = 200
        post.return_value.json.return_value = {
            "idToken": "controlled-token",
            "localId": "agent-one",
        }
        document = firestore_client.return_value.collection.return_value.document.return_value
        profile = document.get.return_value
        profile.exists = True
        profile.to_dict.return_value = {
            "email": "agent@example.test",
            "role": "student",
            "status": "active",
        }

        verified = verify("agent@example.test", "agent")

    assert verified is False


def test_verify_accepts_student_without_a_privileged_token_claim() -> None:
    with (
        patch(
            "scripts.verify_firebase_password_sign_in.get_settings",
            return_value=_settings(),
        ),
        patch("scripts.verify_firebase_password_sign_in.initialize_firebase"),
        patch("scripts.verify_firebase_password_sign_in.httpx.post") as post,
        patch(
            "scripts.verify_firebase_password_sign_in.auth.verify_id_token",
            return_value={"uid": "student-one"},
        ),
        patch("scripts.verify_firebase_password_sign_in.firestore.client") as firestore_client,
    ):
        post.return_value.status_code = 200
        post.return_value.json.return_value = {
            "idToken": "controlled-token",
            "localId": "student-one",
        }
        document = firestore_client.return_value.collection.return_value.document.return_value
        profile = document.get.return_value
        profile.exists = True
        profile.to_dict.return_value = {
            "email": "student@example.test",
            "role": "student",
            "status": "active",
        }

        verified = verify("student@example.test", "student")

    assert verified is True
