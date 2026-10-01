from pathlib import Path
from unittest.mock import patch

import pytest

from app.core.config import Settings
from app.core.firebase import initialize_firebase


def _settings(**overrides: object) -> Settings:
    return Settings(_env_file=None, **overrides)


def test_initialize_firebase_uses_configured_certificate(tmp_path: Path) -> None:
    credentials_path = tmp_path / "firebase-admin.json"
    credentials_path.write_text("{}", encoding="utf-8")
    settings = _settings(
        firebase_project_id="configured-project",
        google_application_credentials=credentials_path,
    )

    with (
        patch("app.core.firebase.firebase_admin.get_app", side_effect=ValueError),
        patch(
            "app.core.firebase.credentials.Certificate", return_value="certificate"
        ) as certificate,
        patch("app.core.firebase.firebase_admin.initialize_app") as initialize,
    ):
        initialize_firebase(settings)

    certificate.assert_called_once_with(str(credentials_path))
    initialize.assert_called_once_with(
        "certificate",
        {"projectId": "configured-project"},
    )


def test_initialize_firebase_falls_back_to_application_default_credentials() -> None:
    settings = _settings(firebase_project_id="configured-project")

    with (
        patch("app.core.firebase.firebase_admin.get_app", side_effect=ValueError),
        patch(
            "app.core.firebase.credentials.ApplicationDefault", return_value="default"
        ) as application_default,
        patch("app.core.firebase.firebase_admin.initialize_app") as initialize,
    ):
        initialize_firebase(settings)

    application_default.assert_called_once_with()
    initialize.assert_called_once_with("default", {"projectId": "configured-project"})


def test_initialize_firebase_rejects_a_different_requested_project() -> None:
    settings = _settings(firebase_project_id="configured-project")

    with pytest.raises(ValueError, match="does not match"):
        initialize_firebase(settings, project_id="other-project")
