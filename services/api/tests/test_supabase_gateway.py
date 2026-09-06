import asyncio
from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID

import pytest

from app.core.auth import RequestContext
from app.domain.estimates import EstimateLineDraft, SourceProvenance
from app.services import supabase_gateway as gateway_module
from app.services.supabase_gateway import SupabaseGateway


class FakeResponse:
    def __init__(self, status_code: int, payload: object | None = None) -> None:
        self.status_code = status_code
        self.payload = payload

    def json(self) -> object:
        return self.payload


class FakeSupabaseClient:
    rpc_payload: dict[str, object] | None = None
    object_url: str | None = None

    async def __aenter__(self) -> "FakeSupabaseClient":
        return self

    async def __aexit__(self, *args: object) -> None:
        return None

    async def post(self, url: str, **kwargs: object) -> FakeResponse:
        if "/storage/v1/object/" in url:
            type(self).object_url = url
            return FakeResponse(201)

        payload = kwargs["json"]
        assert isinstance(payload, dict)
        type(self).rpc_payload = payload
        return FakeResponse(
            200,
            [
                {
                    "estimate_version_id": "00000000-0000-0000-0000-000000000020",
                    "source_media_id": payload["p_source_media_id"],
                }
            ],
        )


def test_persistence_keeps_storage_path_and_media_identity_aligned(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(gateway_module.settings, "supabase_url", "https://project.supabase.co")
    monkeypatch.setattr(gateway_module.settings, "supabase_publishable_key", "publishable-key")
    monkeypatch.setattr(
        gateway_module.httpx,
        "AsyncClient",
        lambda **kwargs: FakeSupabaseClient(),
    )
    FakeSupabaseClient.rpc_payload = None
    FakeSupabaseClient.object_url = None

    result = asyncio.run(
        SupabaseGateway().persist_estimate(
            context=RequestContext(
                organization_id=UUID("00000000-0000-0000-0000-000000000001"),
                actor_id=UUID("00000000-0000-0000-0000-000000000002"),
                authentication_context="supabase_verified_user",
                bearer_token="user-token",  # noqa: S106 - inert test value
            ),
            repair_order_id=UUID("00000000-0000-0000-0000-000000000003"),
            data=b"%PDF-test",
            source=SourceProvenance(
                original_filename="estimate.pdf",
                mime_type="application/pdf",
                content_sha256="0" * 64,
                uploaded_at=datetime.now(UTC),
                page_count=1,
                parser_name="test",
                parser_version="1",
            ),
            lines=[
                EstimateLineDraft(
                    source_line_number=1,
                    operation_code="R&I",
                    description="Radar bracket",
                    amount=Decimal("1.00"),
                    raw_text="1 R&I Radar bracket 1.00",
                    confidence=0.9,
                )
            ],
        )
    )

    assert result is not None
    payload = FakeSupabaseClient.rpc_payload
    assert payload is not None
    media_id = str(payload["p_source_media_id"])
    assert result.source_media_id == UUID(media_id)
    assert FakeSupabaseClient.object_url is not None
    assert f"/{media_id}/estimate.pdf" in FakeSupabaseClient.object_url
