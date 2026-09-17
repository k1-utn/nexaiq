import asyncio
from uuid import UUID

import pytest

from app.core.auth import RequestContext
from app.domain.supplements import SourceQuality, VisionAnalysisOutput, VisionObservation
from app.services import supplement_analysis as analysis_module
from app.services.supabase_gateway import (
    AnalysisEvidenceReference,
    CompletedSupplementAnalysis,
    DownloadedEvidence,
    SupplementAnalysisContext,
)
from app.services.vision_provider import ProviderAnalysis

ORG_ID = UUID("00000000-0000-0000-0000-000000000001")
ACTOR_ID = UUID("00000000-0000-0000-0000-000000000002")
RO_ID = UUID("00000000-0000-0000-0000-000000000003")
JOB_ID = UUID("00000000-0000-0000-0000-000000000004")
RESULT_ID = UUID("00000000-0000-0000-0000-000000000005")
EVIDENCE_ID = UUID("00000000-0000-0000-0000-000000000006")


class FakeGateway:
    candidates: list[dict[str, object]] | None = None
    failure_code: str | None = None

    async def begin_supplement_analysis(self, **kwargs: object) -> SupplementAnalysisContext:
        return SupplementAnalysisContext(
            ai_job_id=JOB_ID,
            job_status="running",
            estimate_version_id=UUID("00000000-0000-0000-0000-000000000007"),
            provider_key="openai",
            model_name="evaluated-model",
            provider_model_version=None,
            prompt_template_version="v1",
            schema_version="v1",
            estimate_lines=[
                {
                    "id": "00000000-0000-0000-0000-000000000008",
                    "operation_code": "RPR",
                    "description": "Repair hood",
                }
            ],
            evidence=[
                AnalysisEvidenceReference(
                    media_id=EVIDENCE_ID,
                    object_path=f"{ORG_ID}/{RO_ID}/photo.jpg",
                    mime_type="image/jpeg",
                    content_sha256="a" * 64,
                )
            ],
        )

    async def download_analysis_evidence(
        self, references: list[AnalysisEvidenceReference]
    ) -> list[DownloadedEvidence]:
        return [
            DownloadedEvidence(
                media_id=references[0].media_id,
                mime_type=references[0].mime_type,
                content_sha256=references[0].content_sha256,
                data=b"image",
            )
        ]

    async def complete_supplement_analysis(self, **kwargs: object) -> CompletedSupplementAnalysis:
        value = kwargs["candidates"]
        assert isinstance(value, list)
        type(self).candidates = value
        return CompletedSupplementAnalysis(ai_result_id=RESULT_ID, created_finding_count=1)

    async def fail_supplement_analysis(self, **kwargs: object) -> None:
        type(self).failure_code = str(kwargs["failure_code"])


class FakeProvider:
    async def analyze(self, **kwargs: object) -> ProviderAnalysis:
        observations = [
            VisionObservation(
                finding_type="possible_missing_operation",
                component="front bumper",
                condition="removed",
                proposed_operation="R&I front bumper cover",
                operation_code="R&I",
                confidence=0.85,
                source_quality=SourceQuality.CAMERA_ONLY,
                evidence_ids=[EVIDENCE_ID],
                reason="Visible in the supplied photo.",
                limitations=["Fasteners are obscured."],
                human_review_required=True,
            ),
            VisionObservation(
                finding_type="paint operation",
                component="front bumper",
                condition="refinished",
                proposed_operation="Add clear coat",
                confidence=0.9,
                source_quality=SourceQuality.CAMERA_ONLY,
                evidence_ids=[EVIDENCE_ID],
                reason="Paint is visible.",
                limitations=[],
                human_review_required=True,
            ),
        ]
        return ProviderAnalysis(
            response_id="resp_test",
            output=VisionAnalysisOutput(observations=observations),
            input_tokens=10,
            output_tokens=20,
            latency_ms=30,
        )


def test_analysis_compares_every_observation_and_excludes_clear_coat(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    FakeGateway.candidates = None
    monkeypatch.setattr(analysis_module, "SupabaseGateway", FakeGateway)
    monkeypatch.setattr(analysis_module, "provider_for", lambda provider_key: FakeProvider())
    result = asyncio.run(
        analysis_module.run_supplement_analysis(
            context=RequestContext(
                organization_id=ORG_ID,
                actor_id=ACTOR_ID,
                authentication_context="test",
                bearer_token="test-user-token",  # noqa: S106 - inert test value
            ),
            repair_order_id=RO_ID,
            idempotency_key="test-idempotency-key",
        )
    )

    assert result.ai_result_id == RESULT_ID
    assert result.human_review_required is True
    assert FakeGateway.candidates is not None
    assert FakeGateway.candidates[0]["comparison_status"] == "possible_missing_operation"
    assert FakeGateway.candidates[1]["comparison_status"] == "automatic_operation_excluded"
    assert FakeGateway.candidates[1]["can_create_supplement_candidate"] is False
