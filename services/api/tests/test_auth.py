import asyncio
from uuid import UUID

import pytest
from fastapi import HTTPException

from app.core import auth as auth_module
from app.core.auth import require_request_context


class FakeResponse:
    def __init__(self, status_code: int, payload: object) -> None:
        self.status_code = status_code
        self.payload = payload

    def json(self) -> object:
        return self.payload


class FakeAuthClient:
    def __init__(self, *, member: bool = True) -> None:
        self.member = member

    async def __aenter__(self) -> "FakeAuthClient":
        return self

    async def __aexit__(self, *args: object) -> None:
        return None

    async def get(self, url: str, **kwargs: object) -> FakeResponse:
        if url.endswith("/auth/v1/user"):
            return FakeResponse(200, {"id": "00000000-0000-0000-0000-000000000002"})
        return FakeResponse(200, [{"id": "membership"}] if self.member else [])


def test_requires_bearer_authentication() -> None:
    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(
            require_request_context(
                authorization=None,
                organization_id=UUID("00000000-0000-0000-0000-000000000001"),
            )
        )

    assert exc_info.value.status_code == 401


def test_requires_explicit_organization_scope() -> None:
    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(
            require_request_context(authorization="Bearer test-token", organization_id=None)
        )

    assert exc_info.value.status_code == 400


def test_verifies_supabase_user_and_membership(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(auth_module.settings, "supabase_url", "https://project.supabase.co")
    monkeypatch.setattr(auth_module.settings, "supabase_publishable_key", "publishable-key")
    monkeypatch.setattr(
        auth_module.httpx,
        "AsyncClient",
        lambda **kwargs: FakeAuthClient(),
    )

    context = asyncio.run(
        require_request_context(
            authorization="Bearer user-token",
            organization_id=UUID("00000000-0000-0000-0000-000000000001"),
        )
    )

    assert context.actor_id == UUID("00000000-0000-0000-0000-000000000002")
    assert context.bearer_token == "user-token"  # noqa: S105 - inert test value
    assert context.authentication_context == "supabase_verified_user"


def test_rejects_user_outside_organization(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(auth_module.settings, "supabase_url", "https://project.supabase.co")
    monkeypatch.setattr(auth_module.settings, "supabase_publishable_key", "publishable-key")
    monkeypatch.setattr(
        auth_module.httpx,
        "AsyncClient",
        lambda **kwargs: FakeAuthClient(member=False),
    )

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(
            require_request_context(
                authorization="Bearer user-token",
                organization_id=UUID("00000000-0000-0000-0000-000000000001"),
            )
        )

    assert exc_info.value.status_code == 403
