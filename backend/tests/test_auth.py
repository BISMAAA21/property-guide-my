from unittest.mock import patch

import pytest
from firebase_admin import auth

from app.core.auth import AuthenticatedUser, require_student, require_user
from app.core.errors import ApiError


@pytest.mark.asyncio
async def test_require_user_rejects_missing_header() -> None:
    with pytest.raises(ApiError) as captured:
        await require_user(None)

    assert captured.value.code == "AUTH_REQUIRED"


@pytest.mark.asyncio
async def test_require_user_accepts_verified_firebase_uid() -> None:
    with patch(
        "app.core.auth.auth.verify_id_token", return_value={"uid": "student-1"}
    ), patch("app.core.auth.auth.get_user") as get_user:
        get_user.return_value.disabled = False
        with patch("app.core.auth.firestore.client") as firestore_client:
            profile = (
                firestore_client.return_value.collection.return_value.document.return_value.get.return_value
            )
            profile.exists = True
            profile.to_dict.return_value = {"status": "active", "role": "student"}
            user = await require_user("Bearer token")

    assert user.uid == "student-1"
    assert user.role == "student"


@pytest.mark.asyncio
async def test_student_boundary_rejects_other_authenticated_roles() -> None:
    with pytest.raises(ApiError) as captured:
        await require_student(AuthenticatedUser(uid="agent-1", role="agent"))

    assert captured.value.status_code == 403
    assert captured.value.code == "ROLE_FORBIDDEN"


@pytest.mark.asyncio
async def test_student_boundary_accepts_active_student() -> None:
    user = AuthenticatedUser(uid="student-1", role="student")

    assert await require_student(user) is user


@pytest.mark.asyncio
async def test_require_user_rejects_invalid_token() -> None:
    with patch(
        "app.core.auth.auth.verify_id_token",
        side_effect=auth.InvalidIdTokenError("invalid"),
    ), pytest.raises(ApiError) as captured:
        await require_user("Bearer invalid")

    assert captured.value.code == "AUTH_INVALID"


@pytest.mark.asyncio
async def test_require_user_rejects_disabled_account() -> None:
    with patch(
        "app.core.auth.auth.verify_id_token", return_value={"uid": "disabled-1"}
    ), patch("app.core.auth.auth.get_user") as get_user:
        get_user.return_value.disabled = True
        with patch("app.core.auth.firestore.client") as firestore_client:
            profile = (
                firestore_client.return_value.collection.return_value.document.return_value.get.return_value
            )
            profile.exists = True
            profile.to_dict.return_value = {"status": "active"}
            with pytest.raises(ApiError) as captured:
                await require_user("Bearer token")

    assert captured.value.code == "ACCOUNT_DISABLED"
    assert captured.value.status_code == 403


@pytest.mark.asyncio
async def test_require_user_rejects_firestore_disabled_profile() -> None:
    with patch(
        "app.core.auth.auth.verify_id_token", return_value={"uid": "disabled-profile"}
    ), patch("app.core.auth.auth.get_user") as get_user, patch(
        "app.core.auth.firestore.client"
    ) as firestore_client:
        get_user.return_value.disabled = False
        profile = (
            firestore_client.return_value.collection.return_value.document.return_value.get.return_value
        )
        profile.exists = True
        profile.to_dict.return_value = {"status": "disabled"}

        with pytest.raises(ApiError) as captured:
            await require_user("Bearer token")

    assert captured.value.code == "ACCOUNT_DISABLED"


@pytest.mark.asyncio
async def test_require_user_rejects_missing_firestore_profile() -> None:
    with patch(
        "app.core.auth.auth.verify_id_token", return_value={"uid": "missing-profile"}
    ), patch("app.core.auth.auth.get_user") as get_user, patch(
        "app.core.auth.firestore.client"
    ) as firestore_client:
        get_user.return_value.disabled = False
        profile = (
            firestore_client.return_value.collection.return_value.document.return_value.get.return_value
        )
        profile.exists = False

        with pytest.raises(ApiError) as captured:
            await require_user("Bearer token")

    assert captured.value.code == "ACCOUNT_DISABLED"
