import argparse
from types import SimpleNamespace
from unittest.mock import patch

import pytest
from firebase_admin import auth

from app.core.config import Settings
from scripts.register_firebase_student import (
    StudentRegistration,
    build_registration,
    register,
)


def _settings() -> Settings:
    return Settings(
        _env_file=None,
        firebase_project_id="demo-project",
        firebase_api_key="controlled-client-key",
        seed_user_password="controlled-demo-password",
    )


def _registration() -> StudentRegistration:
    return StudentRegistration(
        email="student@example.test",
        name="Demo Student",
        password="controlled-demo-password",
    )


def test_build_registration_normalizes_owner_inputs() -> None:
    args = argparse.Namespace(email=" Student@Example.Test ", name=" Demo Student ")

    registration = build_registration(args, _settings())

    assert registration.email == "student@example.test"
    assert registration.name == "Demo Student"


def test_register_rejects_a_conflicting_existing_account() -> None:
    existing = SimpleNamespace(uid="existing-user")
    with (
        patch("scripts.register_firebase_student.initialize_firebase"),
        patch(
            "scripts.register_firebase_student.auth.get_user_by_email",
            return_value=existing,
        ),
        patch("scripts.register_firebase_student._profile_is_exact", return_value=False),
        patch("scripts.register_firebase_student.httpx.post") as post,
        pytest.raises(RuntimeError, match="does not match"),
    ):
        register(_registration(), _settings())

    post.assert_not_called()


def test_register_uses_client_auth_and_firestore_server_timestamps() -> None:
    responses = []
    for payload in (
        {"idToken": "sign-up-token", "localId": "student-one"},
        {"idToken": "updated-token", "localId": "student-one"},
        {"writeResults": [{}]},
    ):
        response = SimpleNamespace(status_code=200, json=lambda payload=payload: payload)
        responses.append(response)

    with (
        patch("scripts.register_firebase_student.initialize_firebase"),
        patch(
            "scripts.register_firebase_student.auth.get_user_by_email",
            side_effect=auth.UserNotFoundError("missing"),
        ),
        patch("scripts.register_firebase_student.httpx.post", side_effect=responses) as post,
        patch("scripts.register_firebase_student._profile_is_exact", return_value=True),
        patch(
            "scripts.register_firebase_student.verify_password_sign_in",
            return_value=True,
        ),
    ):
        created = register(_registration(), _settings())

    assert created is True
    commit_call = post.call_args_list[2]
    assert commit_call.kwargs["headers"] == {"Authorization": "Bearer updated-token"}
    write = commit_call.kwargs["json"]["writes"][0]
    assert write["update"]["fields"]["role"] == {"stringValue": "student"}
    assert write["updateTransforms"] == [
        {"fieldPath": "createdAt", "setToServerValue": "REQUEST_TIME"},
        {"fieldPath": "updatedAt", "setToServerValue": "REQUEST_TIME"},
    ]
    assert write["currentDocument"] == {"exists": False}
