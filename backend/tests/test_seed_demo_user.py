import argparse
from types import SimpleNamespace
from unittest.mock import patch

import pytest

from scripts.seed_demo_user import (
    SeedRequest,
    build_request,
    provision,
    verify_provisioned_user,
)


def _args(**overrides: str) -> argparse.Namespace:
    values = {
        "email": "agent@example.test",
        "name": "Demo Agent",
        "role": "agent",
        "project_id": "demo-project",
    }
    values.update(overrides)
    return argparse.Namespace(**values)


def test_build_request_normalizes_valid_input(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SEED_USER_PASSWORD", "long-demo-password")

    request = build_request(_args(email=" Agent@Example.Test "))

    assert request.email == "agent@example.test"
    assert request.role == "agent"


def test_build_request_requires_password_from_environment(
    monkeypatch: pytest.MonkeyPatch, tmp_path
) -> None:
    monkeypatch.delenv("SEED_USER_PASSWORD", raising=False)
    monkeypatch.chdir(tmp_path)

    with pytest.raises(ValueError, match="at least 12"):
        build_request(_args())


def test_build_request_reads_password_from_ignored_environment_file(
    monkeypatch: pytest.MonkeyPatch, tmp_path
) -> None:
    monkeypatch.delenv("SEED_USER_PASSWORD", raising=False)
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".env").write_text(
        "SEED_USER_PASSWORD=controlled-demo-password\n",
        encoding="utf-8",
    )

    request = build_request(_args())

    assert request.password == "controlled-demo-password"


def _request() -> SeedRequest:
    return SeedRequest(
        email="agent@example.test",
        name="Demo Agent",
        role="agent",
        project_id="demo-project",
        password="controlled-demo-password",
    )


def test_provision_rejects_existing_account_with_a_different_role() -> None:
    existing_user = SimpleNamespace(
        uid="existing-user",
        custom_claims={"role": "student"},
    )
    with (
        patch("scripts.seed_demo_user.initialize"),
        patch("scripts.seed_demo_user.auth.get_user_by_email", return_value=existing_user),
        patch("scripts.seed_demo_user.auth.update_user") as update_user,
        patch("scripts.seed_demo_user.firestore.client") as firestore_client,
    ):
        document = firestore_client.return_value.collection.return_value.document.return_value
        profile = document.get.return_value
        profile.exists = True
        profile.to_dict.return_value = {"role": "student"}

        with pytest.raises(ValueError, match="different role"):
            provision(_request())

    update_user.assert_not_called()


def test_provision_updates_existing_account_with_the_same_role() -> None:
    existing_user = SimpleNamespace(
        uid="existing-user",
        custom_claims={"role": "agent"},
    )
    updated_user = SimpleNamespace(uid="existing-user")
    with (
        patch("scripts.seed_demo_user.initialize"),
        patch("scripts.seed_demo_user.auth.get_user_by_email", return_value=existing_user),
        patch("scripts.seed_demo_user.auth.update_user", return_value=updated_user) as update_user,
        patch("scripts.seed_demo_user.auth.set_custom_user_claims"),
        patch("scripts.seed_demo_user.firestore.client") as firestore_client,
    ):
        document = firestore_client.return_value.collection.return_value.document.return_value
        profile = document.get.return_value
        profile.exists = True
        profile.to_dict.return_value = {"role": "agent"}

        uid, created = provision(_request())

    assert uid == "existing-user"
    assert created is False
    update_user.assert_called_once()


def test_verify_provisioned_user_requires_matching_auth_and_profile() -> None:
    user = SimpleNamespace(
        email="agent@example.test",
        display_name="Demo Agent",
        disabled=False,
        custom_claims={"role": "agent"},
    )
    with (
        patch("scripts.seed_demo_user.auth.get_user", return_value=user),
        patch("scripts.seed_demo_user.firestore.client") as firestore_client,
    ):
        document = firestore_client.return_value.collection.return_value.document.return_value
        profile = document.get.return_value
        profile.exists = True
        profile.to_dict.return_value = {
            "email": "agent@example.test",
            "name": "Demo Agent",
            "role": "agent",
            "status": "active",
        }

        verified = verify_provisioned_user(_request(), "existing-user")

    assert verified is True


def test_verify_provisioned_user_rejects_mismatched_profile_role() -> None:
    user = SimpleNamespace(
        email="agent@example.test",
        display_name="Demo Agent",
        disabled=False,
        custom_claims={"role": "agent"},
    )
    with (
        patch("scripts.seed_demo_user.auth.get_user", return_value=user),
        patch("scripts.seed_demo_user.firestore.client") as firestore_client,
    ):
        document = firestore_client.return_value.collection.return_value.document.return_value
        profile = document.get.return_value
        profile.exists = True
        profile.to_dict.return_value = {
            "email": "agent@example.test",
            "name": "Demo Agent",
            "role": "student",
            "status": "active",
        }

        verified = verify_provisioned_user(_request(), "existing-user")

    assert verified is False
