import asyncio
from uuid import UUID

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.core.auth import RequestContext, require_request_context
from app.main import app
from app.services import supabase_gateway as gateway_module
from app.services.supabase_gateway import (
    SupabaseGateway,
    SupplementAnalysisReadinessRecord,
)


class FakeResponse:
    status_code = 200

    def json(self) -> object:
        return [
            {
                "verified_estimate_version_id": "00000000-0000-0000-0000-000000000020",
                "photo_count": 4,
                "eligible_photo_count": 3,
                "withheld_photo_count": 1,
                "voice_note_count": 2,
                "approved_provider_policy_count": 0,
                "eligible_model_version_count": 0,
            }
        ]


class FakeClient:
    payload: dict[str, object] | None = None

    async def __aenter__(self) -> "FakeClient":
        return self

    async def __aexit__(self, *args: object) -> None:
        return None

    async def post(self, url: str, **kwargs: object) -> FakeResponse:
        assert url.endswith("/rest/v1/rpc/get_supplement_analysis_readiness")
        payload = kwargs.get("json")
        assert isinstance(payload, dict)
        type(self).payload = payload
        return FakeResponse()


def context(*, token: str | None) -> RequestContext:
    return RequestContext(
        organization_id=UUID("00000000-0000-0000-0000-000000000001"),
        actor_id=UUID("00000000-0000-0000-0000-000000000002"),
        authentication_context="supabase_verified_user",
        bearer_token=token,
    )


def test_readiness_uses_user_token_and_tenant_scope(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(gateway_module.settings, "supabase_url", "https://project.supabase.co")
    monkeypatch.setattr(gateway_module.settings, "supabase_publishable_key", "publishable-key")
    monkeypatch.setattr(gateway_module.settings, "environment", "development")
    monkeypatch.setattr(gateway_module.httpx, "AsyncClient", lambda **kwargs: FakeClient())
    repair_order_id = UUID("00000000-0000-0000-0000-000000000003")

    result = asyncio.run(
        SupabaseGateway().get_supplement_analysis_readiness(
            context=context(token="test-user-token"),  # noqa: S106 - inert test value
            repair_order_id=repair_order_id,
        )
    )

    assert result.photo_count == 4
    assert result.approved_provider_policy_count == 0
    assert FakeClient.payload == {
        "p_organization_id": "00000000-0000-0000-0000-000000000001",
        "p_repair_order_id": str(repair_order_id),
        "p_environment": "development",
    }


def test_readiness_fails_closed_without_authenticated_configuration(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(gateway_module.settings, "supabase_url", None)

    with pytest.raises(HTTPException) as raised:
        asyncio.run(
            SupabaseGateway().get_supplement_analysis_readiness(
                context=context(token=None),
                repair_order_id=UUID("00000000-0000-0000-0000-000000000003"),
            )
        )

    assert raised.value.status_code == 503


def test_server_secret_headers_support_new_and_legacy_supabase_keys(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(gateway_module.settings, "supabase_url", "https://project.supabase.co")
    monkeypatch.setattr(gateway_module.settings, "supabase_secret_key", "sb_secret_test")
    assert SupabaseGateway()._server_headers() == {"apikey": "sb_secret_test"}

    monkeypatch.setattr(gateway_module.settings, "supabase_secret_key", "legacy-service-role")
    assert SupabaseGateway()._server_headers() == {
        "apikey": "legacy-service-role",
        "Authorization": "Bearer legacy-service-role",
    }


def test_readiness_route_reports_policy_and_model_blockers(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def fake_readiness(
        gateway: SupabaseGateway,
        *,
        context: RequestContext,
        repair_order_id: UUID,
    ) -> SupplementAnalysisReadinessRecord:
        del gateway, context, repair_order_id
        return SupplementAnalysisReadinessRecord(
            verified_estimate_version_id=UUID("00000000-0000-0000-0000-000000000020"),
            photo_count=4,
            eligible_photo_count=3,
            withheld_photo_count=1,
            voice_note_count=4,
            approved_provider_policy_count=0,
            eligible_model_version_count=0,
        )

    monkeypatch.setattr(SupabaseGateway, "get_supplement_analysis_readiness", fake_readiness)
    monkeypatch.setattr(gateway_module.settings, "supabase_secret_key", "test-secret")
    monkeypatch.setattr(gateway_module.settings, "openai_api_key", "test-provider-key")
    app.dependency_overrides[require_request_context] = lambda: context(
        token="test-user-token"  # noqa: S106 - inert test value
    )
    try:
        response = TestClient(app).get(
            "/v1/supplement-analysis/repair-orders/00000000-0000-0000-0000-000000000003/readiness"
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    payload = response.json()
    assert payload["ready"] is False
    assert payload["blockers"] == [
        "approved_provider_policy_required",
        "evaluated_model_required",
    ]
    assert payload["human_review_required"] is True
