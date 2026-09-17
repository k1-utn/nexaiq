from typing import Annotated
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, Header

from app.core.auth import RequestContext, require_request_context
from app.core.config import settings
from app.domain.supplements import (
    ReadinessBlocker,
    SupplementAnalysisReadiness,
    SupplementAnalysisRunResult,
)
from app.services.supabase_gateway import SupabaseGateway
from app.services.supplement_analysis import run_supplement_analysis

router = APIRouter(tags=["supplement analysis"])


@router.get(
    "/repair-orders/{repair_order_id}/readiness",
    response_model=SupplementAnalysisReadiness,
)
async def get_readiness(
    repair_order_id: UUID,
    context: Annotated[RequestContext, Depends(require_request_context)],
) -> SupplementAnalysisReadiness:
    record = await SupabaseGateway().get_supplement_analysis_readiness(
        context=context,
        repair_order_id=repair_order_id,
    )
    blockers: list[ReadinessBlocker] = []
    if record.verified_estimate_version_id is None:
        blockers.append(ReadinessBlocker.VERIFIED_ESTIMATE_REQUIRED)
    if record.photo_count == 0:
        blockers.append(ReadinessBlocker.PHOTO_EVIDENCE_REQUIRED)
    elif record.eligible_photo_count == 0:
        blockers.append(ReadinessBlocker.PRIVACY_ELIGIBLE_PHOTO_REQUIRED)
    if record.approved_provider_policy_count == 0:
        blockers.append(ReadinessBlocker.APPROVED_PROVIDER_POLICY_REQUIRED)
    if record.eligible_model_version_count == 0:
        blockers.append(ReadinessBlocker.EVALUATED_MODEL_REQUIRED)
    if not settings.supabase_secret_key:
        blockers.append(ReadinessBlocker.SERVER_SECRET_REQUIRED)
    if not settings.openai_api_key:
        blockers.append(ReadinessBlocker.PROVIDER_CREDENTIAL_REQUIRED)

    return SupplementAnalysisReadiness(
        organization_id=context.organization_id,
        repair_order_id=repair_order_id,
        ready=not blockers,
        blockers=blockers,
        verified_estimate_version_id=record.verified_estimate_version_id,
        photo_count=record.photo_count,
        eligible_photo_count=record.eligible_photo_count,
        withheld_photo_count=record.withheld_photo_count,
        voice_note_count=record.voice_note_count,
        approved_provider_policy_count=record.approved_provider_policy_count,
        eligible_model_version_count=record.eligible_model_version_count,
    )


@router.post(
    "/repair-orders/{repair_order_id}/runs",
    response_model=SupplementAnalysisRunResult,
)
async def create_analysis_run(
    repair_order_id: UUID,
    context: Annotated[RequestContext, Depends(require_request_context)],
    idempotency_key: Annotated[
        str | None,
        Header(alias="Idempotency-Key", min_length=8, max_length=200),
    ] = None,
) -> SupplementAnalysisRunResult:
    return await run_supplement_analysis(
        context=context,
        repair_order_id=repair_order_id,
        idempotency_key=idempotency_key or str(uuid4()),
    )
