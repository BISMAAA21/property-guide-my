from pathlib import Path

import firebase_admin
from firebase_admin import credentials

from app.core.config import Settings


def _credential_for(credentials_path: Path | None):
    if credentials_path is None:
        return credentials.ApplicationDefault()
    if not credentials_path.is_file():
        raise RuntimeError("The configured Firebase Admin credential file does not exist.")
    return credentials.Certificate(str(credentials_path))


def initialize_firebase(
    settings: Settings,
    *,
    project_id: str | None = None,
) -> None:
    configured_project = settings.firebase_project_id
    requested_project = project_id.strip() if project_id is not None else None
    if requested_project == "":
        requested_project = None
    if (
        configured_project is not None
        and requested_project is not None
        and configured_project != requested_project
    ):
        raise ValueError("The requested Firebase project does not match local configuration.")

    try:
        firebase_admin.get_app()
        return
    except ValueError:
        pass

    resolved_project = requested_project or configured_project
    options = {"projectId": resolved_project} if resolved_project else None
    firebase_admin.initialize_app(
        _credential_for(settings.google_application_credentials),
        options,
    )
