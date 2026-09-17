import asyncio
import json
from uuid import UUID

import pytest

from app.services import vision_provider as provider_module
from app.services.supabase_gateway import (
    DownloadedEvidence,
    SupplementAnalysisContext,
)
from app.services.vision_provider import OpenAIVisionProvider, VisionProviderError

EVIDENCE_ID = UUID("00000000-0000-0000-0000-000000000101")


class FakeResponse:
    status_code = 200

    def json(self) -> object:
        return {
            "id": "resp_test",
            "status": "completed",
            "output_text": json.dumps(
                {
                    "observations": [
                        {
                            "finding_type": "possible_missing_operation",
                            "component": "front bumper",
                            "condition": "removed",
                            "proposed_operation": "R&I front bumper cover",
                            "operation_code": "R&I",
                            "confidence": 0.82,
                            "source_quality": "camera_only",
                            "evidence_ids": [str(EVIDENCE_ID)],
                            "reason": "The bumper cover is visibly removed.",
                            "limitations": ["Fasteners are not fully visible."],
                            "human_review_required": True,
                        }
                    ]
                }
            ),
            "usage": {"input_tokens": 100, "output_tokens": 40},
        }


class FakeClient:
    request: dict[str, object] | None = None

    async def __aenter__(self) -> "FakeClient":
        return self

    async def __aexit__(self, *args: object) -> None:
        return None

    async def post(self, url: str, **kwargs: object) -> FakeResponse:
        assert url == "https://api.openai.com/v1/responses"
        type(self).request = kwargs
        return FakeResponse()


def analysis_context() -> SupplementAnalysisContext:
    return SupplementAnalysisContext(
        ai_job_id=UUID("00000000-0000-0000-0000-000000000001"),
        job_status="running",
        estimate_version_id=UUID("00000000-0000-0000-0000-000000000002"),
        provider_key="openai",
        model_name="evaluated-model",
        provider_model_version="pinned-version",
        prompt_template_version="v1",
        schema_version="v1",
        estimate_lines=[
            {
                "id": "00000000-0000-0000-0000-000000000201",
                "operation_code": "RPR",
                "description": "Repair hood",
            }
        ],
        evidence=[],
    )


def test_openai_request_disables_storage_and_uses_strict_structured_output(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(provider_module.settings, "openai_api_key", "test-provider-key")
    monkeypatch.setattr(provider_module.settings, "openai_base_url", "https://api.openai.com/v1")
    monkeypatch.setattr(provider_module.httpx, "AsyncClient", lambda **kwargs: FakeClient())
    result = asyncio.run(
        OpenAIVisionProvider().analyze(
            analysis_context=analysis_context(),
            evidence=[
                DownloadedEvidence(
                    media_id=EVIDENCE_ID,
                    mime_type="image/jpeg",
                    content_sha256="a" * 64,
                    data=b"safe-image-bytes",
                )
            ],
        )
    )

    assert result.response_id == "resp_test"
    assert result.output.observations[0].human_review_required is True
    request = FakeClient.request
    assert request is not None
    body = request["json"]
    assert isinstance(body, dict)
    assert body["store"] is False
    assert body["model"] == "evaluated-model"
    assert body["text"]["format"]["strict"] is True
    assert "Never propose clear coat" in body["instructions"]


def test_openai_output_cannot_reference_unprovided_evidence(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(provider_module.settings, "openai_api_key", "test-provider-key")
    monkeypatch.setattr(provider_module.httpx, "AsyncClient", lambda **kwargs: FakeClient())

    with pytest.raises(VisionProviderError, match="unknown evidence"):
        asyncio.run(
            OpenAIVisionProvider().analyze(
                analysis_context=analysis_context(),
                evidence=[
                    DownloadedEvidence(
                        media_id=UUID("00000000-0000-0000-0000-000000000999"),
                        mime_type="image/jpeg",
                        content_sha256="b" * 64,
                        data=b"different-image",
                    )
                ],
            )
        )
