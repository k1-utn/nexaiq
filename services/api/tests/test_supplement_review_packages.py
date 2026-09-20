from uuid import UUID

from fastapi.testclient import TestClient

from app.core.auth import RequestContext, require_request_context
from app.main import app
from app.services.supabase_gateway import (
    CreatedSupplementReviewPackage,
    RecordedSupplementReviewPackageDecision,
    SupabaseGateway,
)


def context() -> RequestContext:
    return RequestContext(
        organization_id=UUID("00000000-0000-0000-0000-000000000001"),
        actor_id=UUID("00000000-0000-0000-0000-000000000002"),
        authentication_context="supabase_verified_user",
        bearer_token="test-user-token",  # noqa: S106 - inert test value
    )


def test_create_review_package_uses_authenticated_context(monkeypatch) -> None:
    async def fake_create(
        gateway: SupabaseGateway,
        *,
        context: RequestContext,
        repair_order_id: UUID,
    ) -> CreatedSupplementReviewPackage:
        del gateway
        assert context.actor_id == UUID("00000000-0000-0000-0000-000000000002")
        assert repair_order_id == UUID("00000000-0000-0000-0000-000000000003")
        return CreatedSupplementReviewPackage(
            package_id=UUID("00000000-0000-0000-0000-000000000004"),
            package_number=1,
            item_count=2,
            package_status="draft",
        )

    monkeypatch.setattr(SupabaseGateway, "create_supplement_review_package", fake_create)
    app.dependency_overrides[require_request_context] = context
    try:
        response = TestClient(app).post(
            "/v1/supplement-analysis/repair-orders/00000000-0000-0000-0000-000000000003/review-packages"
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()["item_count"] == 2


def test_package_decision_validates_and_returns_result(monkeypatch) -> None:
    async def fake_decision(
        gateway: SupabaseGateway,
        *,
        context: RequestContext,
        package_id: UUID,
        decision: str,
        note: str | None,
        attestation: str | None,
    ) -> RecordedSupplementReviewPackageDecision:
        del gateway, context, note
        assert package_id == UUID("00000000-0000-0000-0000-000000000004")
        assert decision == "approved"
        assert attestation is not None
        return RecordedSupplementReviewPackageDecision(
            package_id=package_id,
            package_status="approved",
            decided_at="2026-09-20T19:00:00+00:00",
        )

    monkeypatch.setattr(
        SupabaseGateway,
        "record_supplement_review_package_decision",
        fake_decision,
    )
    app.dependency_overrides[require_request_context] = context
    try:
        response = TestClient(app).post(
            "/v1/supplement-analysis/review-packages/00000000-0000-0000-0000-000000000004/decision",
            json={"decision": "approved", "attestation": "accepted"},
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()["package_status"] == "approved"
