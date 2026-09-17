from uuid import UUID

from fastapi import HTTPException

from app.core.auth import RequestContext
from app.domain.supplements import (
    SupplementAnalysisRunResult,
    VerifiedEstimateLine,
)
from app.services.supabase_gateway import SupabaseGateway
from app.services.supplement_comparison import compare_observation_to_estimate
from app.services.vision_provider import VisionProviderError, provider_for


async def run_supplement_analysis(
    *,
    context: RequestContext,
    repair_order_id: UUID,
    idempotency_key: str,
) -> SupplementAnalysisRunResult:
    """Run one governed analysis and persist only reviewable candidate records."""
    gateway = SupabaseGateway()
    analysis_context = await gateway.begin_supplement_analysis(
        context=context,
        repair_order_id=repair_order_id,
        idempotency_key=idempotency_key,
    )
    if analysis_context.job_status != "running":
        raise HTTPException(
            status_code=409,
            detail="This analysis request was already completed. Refresh to view its results.",
        )

    failure_code = "evidence_error"
    try:
        evidence = await gateway.download_analysis_evidence(analysis_context.evidence)
        failure_code = "provider_error"
        analysis = await provider_for(analysis_context.provider_key).analyze(
            analysis_context=analysis_context,
            evidence=evidence,
        )
        failure_code = "invalid_analysis_context"
        estimate_lines = [
            VerifiedEstimateLine.model_validate(
                {
                    "id": line.get("id"),
                    "operation_code": line.get("operation_code"),
                    "description": line.get("description"),
                }
            )
            for line in analysis_context.estimate_lines
        ]
        candidates: list[dict[str, object]] = []
        for observation in analysis.output.observations:
            comparison = compare_observation_to_estimate(observation, estimate_lines)
            candidate = observation.model_dump(mode="json")
            candidate.update(comparison.model_dump(mode="json"))
            candidate["observation_reason"] = observation.reason
            candidates.append(candidate)

        failure_code = "persistence_error"
        completed = await gateway.complete_supplement_analysis(
            context=context,
            ai_job_id=analysis_context.ai_job_id,
            provider_response_id=analysis.response_id,
            candidates=candidates,
            input_tokens=analysis.input_tokens,
            output_tokens=analysis.output_tokens,
            latency_ms=analysis.latency_ms,
        )
    except VisionProviderError as exc:
        await gateway.fail_supplement_analysis(
            context=context,
            ai_job_id=analysis_context.ai_job_id,
            failure_code="provider_error",
        )
        raise HTTPException(
            status_code=502,
            detail="The analysis provider could not complete this request. No findings were saved.",
        ) from exc
    except HTTPException:
        await gateway.fail_supplement_analysis(
            context=context,
            ai_job_id=analysis_context.ai_job_id,
            failure_code=failure_code,
        )
        raise
    except (TypeError, ValueError) as exc:
        await gateway.fail_supplement_analysis(
            context=context,
            ai_job_id=analysis_context.ai_job_id,
            failure_code="invalid_analysis_context",
        )
        raise HTTPException(
            status_code=502,
            detail="The analysis context was invalid. No findings were saved.",
        ) from exc

    return SupplementAnalysisRunResult(
        organization_id=context.organization_id,
        repair_order_id=repair_order_id,
        ai_job_id=analysis_context.ai_job_id,
        ai_result_id=completed.ai_result_id,
        created_finding_count=completed.created_finding_count,
    )
