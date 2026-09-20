import re
from dataclasses import dataclass
from urllib.parse import quote
from uuid import NAMESPACE_URL, UUID, uuid4, uuid5

import httpx
from fastapi import HTTPException

from app.core.auth import RequestContext
from app.core.config import settings
from app.domain.estimates import EstimateLineDraft, SourceProvenance
from app.domain.evidence import CaptureKind
from app.services.evidence_validator import ValidatedCapture

SAFE_FILENAME = re.compile(r"[^A-Za-z0-9._-]+")
STORAGE_OBJECT_EXISTS_CODES = {
    "already_exists",
    "duplicate",
    "keyalreadyexists",
    "resourcealreadyexists",
}


def _storage_object_already_exists(response: httpx.Response) -> bool:
    if response.status_code not in {400, 409}:
        return False
    try:
        payload = response.json()
    except ValueError:
        return False
    if not isinstance(payload, dict):
        return False
    codes = {str(payload.get(field, "")).casefold() for field in ("code", "error")}
    return bool(codes & STORAGE_OBJECT_EXISTS_CODES)


@dataclass(frozen=True)
class PersistedEstimate:
    estimate_version_id: UUID
    source_media_id: UUID


@dataclass(frozen=True)
class PersistedCapture:
    scan_session_id: UUID
    scan_session_media_id: UUID
    media_id: UUID
    already_persisted: bool


@dataclass(frozen=True)
class SupplementAnalysisReadinessRecord:
    verified_estimate_version_id: UUID | None
    photo_count: int
    eligible_photo_count: int
    withheld_photo_count: int
    voice_note_count: int
    approved_provider_policy_count: int
    eligible_model_version_count: int


@dataclass(frozen=True)
class AnalysisEvidenceReference:
    media_id: UUID
    object_path: str
    mime_type: str
    content_sha256: str


@dataclass(frozen=True)
class SupplementAnalysisContext:
    ai_job_id: UUID
    job_status: str
    estimate_version_id: UUID
    provider_key: str
    model_name: str
    provider_model_version: str | None
    prompt_template_version: str
    schema_version: str
    estimate_lines: list[dict[str, object]]
    evidence: list[AnalysisEvidenceReference]


@dataclass(frozen=True)
class DownloadedEvidence:
    media_id: UUID
    mime_type: str
    content_sha256: str
    data: bytes


@dataclass(frozen=True)
class CompletedSupplementAnalysis:
    ai_result_id: UUID
    created_finding_count: int


@dataclass(frozen=True)
class CreatedSupplementReviewPackage:
    package_id: UUID
    package_number: int
    item_count: int
    package_status: str


@dataclass(frozen=True)
class RecordedSupplementReviewPackageDecision:
    package_id: UUID
    package_status: str
    decided_at: str


class SupabaseGateway:
    def __init__(self) -> None:
        self.url = settings.supabase_url
        self.key = settings.supabase_publishable_key

    @property
    def configured(self) -> bool:
        return bool(self.url and self.key)

    @property
    def server_configured(self) -> bool:
        return bool(self.url and settings.supabase_secret_key)

    def _server_headers(self, *, content_type: bool = False) -> dict[str, str]:
        secret = settings.supabase_secret_key
        if not self.url or not secret:
            raise HTTPException(status_code=503, detail="Server persistence is not configured")
        headers = {"apikey": secret}
        if not secret.startswith("sb_secret_"):
            headers["Authorization"] = f"Bearer {secret}"
        if content_type:
            headers["Content-Type"] = "application/json"
        return headers

    async def persist_estimate(
        self,
        *,
        context: RequestContext,
        repair_order_id: UUID,
        data: bytes,
        source: SourceProvenance,
        lines: list[EstimateLineDraft],
    ) -> PersistedEstimate | None:
        if not self.configured or not context.bearer_token:
            return None

        safe_name = SAFE_FILENAME.sub("_", source.original_filename).strip("._")
        safe_name = safe_name[:180] or "estimate.pdf"
        media_id = uuid4()
        object_path = f"{context.organization_id}/{repair_order_id}/{media_id}/{safe_name}"
        headers = {
            "apikey": str(self.key),
            "Authorization": f"Bearer {context.bearer_token}",
        }
        object_url = f"{self.url}/storage/v1/object/repair-evidence/{quote(object_path, safe='/')}"

        async with httpx.AsyncClient(timeout=30) as client:
            upload_response = await client.post(
                object_url,
                headers={**headers, "Content-Type": source.mime_type, "x-upsert": "false"},
                content=data,
            )
            if upload_response.status_code not in {200, 201}:
                raise HTTPException(status_code=502, detail="Private source preservation failed")

            rpc_response = await client.post(
                f"{self.url}/rest/v1/rpc/persist_estimate_parse",
                headers={**headers, "Content-Type": "application/json"},
                json={
                    "p_organization_id": str(context.organization_id),
                    "p_repair_order_id": str(repair_order_id),
                    "p_source_media_id": str(media_id),
                    "p_object_path": object_path,
                    "p_original_filename": source.original_filename,
                    "p_mime_type": source.mime_type,
                    "p_byte_size": len(data),
                    "p_content_sha256": source.content_sha256,
                    "p_parser_name": source.parser_name,
                    "p_parser_version": source.parser_version,
                    "p_lines": [line.model_dump(mode="json") for line in lines],
                },
            )
            if rpc_response.status_code not in {200, 201}:
                await client.delete(object_url, headers=headers)
                raise HTTPException(status_code=502, detail="Estimate record persistence failed")
            payload = rpc_response.json()
            row = payload[0] if isinstance(payload, list) else payload
            return PersistedEstimate(
                estimate_version_id=UUID(row["estimate_version_id"]),
                source_media_id=UUID(row["source_media_id"]),
            )

    async def persist_capture(
        self,
        *,
        context: RequestContext,
        repair_order_id: UUID,
        client_session_id: UUID,
        client_capture_id: UUID,
        capture_kind: CaptureKind,
        sequence_number: int,
        capture: ValidatedCapture,
    ) -> PersistedCapture:
        if not self.configured or not context.bearer_token:
            raise HTTPException(status_code=503, detail="Evidence persistence is not configured")

        safe_name = SAFE_FILENAME.sub("_", capture.provenance.original_filename).strip("._")
        fallback = "capture.jpg" if capture_kind == "photo" else "voice.m4a"
        safe_name = safe_name[:180] or fallback
        media_id = uuid5(
            NAMESPACE_URL,
            f"nexaiq:{context.organization_id}:scan-capture:{client_capture_id}",
        )
        object_path = (
            f"{context.organization_id}/{repair_order_id}/scans/{client_session_id}/"
            f"{client_capture_id}/{media_id}/{safe_name}"
        )
        headers = {
            "apikey": str(self.key),
            "Authorization": f"Bearer {context.bearer_token}",
        }
        object_url = f"{self.url}/storage/v1/object/repair-evidence/{quote(object_path, safe='/')}"

        async with httpx.AsyncClient(timeout=45) as client:
            upload_response = await client.post(
                object_url,
                headers={
                    **headers,
                    "Content-Type": capture.provenance.mime_type,
                    "x-upsert": "false",
                },
                content=capture.data,
            )
            uploaded_now = upload_response.status_code in {200, 201}
            if not uploaded_now and not _storage_object_already_exists(upload_response):
                raise HTTPException(status_code=502, detail="Private evidence upload failed")

            rpc_response = await client.post(
                f"{self.url}/rest/v1/rpc/persist_scan_capture",
                headers={**headers, "Content-Type": "application/json"},
                json={
                    "p_organization_id": str(context.organization_id),
                    "p_repair_order_id": str(repair_order_id),
                    "p_client_session_id": str(client_session_id),
                    "p_client_capture_id": str(client_capture_id),
                    "p_media_id": str(media_id),
                    "p_object_path": object_path,
                    "p_original_filename": capture.provenance.original_filename,
                    "p_mime_type": capture.provenance.mime_type,
                    "p_byte_size": capture.provenance.byte_size,
                    "p_content_sha256": capture.provenance.content_sha256,
                    "p_capture_kind": capture_kind,
                    "p_sequence_number": sequence_number,
                    "p_captured_at": capture.provenance.captured_at.isoformat(),
                    "p_privacy_flags": capture.provenance.privacy_flags,
                    "p_original_metadata": capture.original_metadata,
                },
            )
            if rpc_response.status_code not in {200, 201}:
                if uploaded_now:
                    await client.delete(object_url, headers=headers)
                raise HTTPException(status_code=502, detail="Evidence record persistence failed")

            payload = rpc_response.json()
            row = payload[0] if isinstance(payload, list) else payload
            return PersistedCapture(
                scan_session_id=UUID(row["scan_session_id"]),
                scan_session_media_id=UUID(row["scan_session_media_id"]),
                media_id=UUID(row["media_id"]),
                already_persisted=bool(row["already_persisted"]),
            )

    async def get_supplement_analysis_readiness(
        self,
        *,
        context: RequestContext,
        repair_order_id: UUID,
    ) -> SupplementAnalysisReadinessRecord:
        if not self.configured or not context.bearer_token:
            raise HTTPException(status_code=503, detail="Supplement analysis is not configured")

        headers = {
            "apikey": str(self.key),
            "Authorization": f"Bearer {context.bearer_token}",
            "Content-Type": "application/json",
        }
        async with httpx.AsyncClient(timeout=15) as client:
            response = await client.post(
                f"{self.url}/rest/v1/rpc/get_supplement_analysis_readiness",
                headers=headers,
                json={
                    "p_organization_id": str(context.organization_id),
                    "p_repair_order_id": str(repair_order_id),
                    "p_environment": settings.environment,
                },
            )
        if response.status_code not in {200, 201}:
            raise HTTPException(status_code=502, detail="Supplement readiness check failed")

        payload = response.json()
        row = payload[0] if isinstance(payload, list) and payload else payload
        if not isinstance(row, dict):
            raise HTTPException(status_code=502, detail="Supplement readiness response was invalid")
        version_id = row.get("verified_estimate_version_id")
        return SupplementAnalysisReadinessRecord(
            verified_estimate_version_id=UUID(version_id) if version_id else None,
            photo_count=int(row.get("photo_count", 0)),
            eligible_photo_count=int(row.get("eligible_photo_count", 0)),
            withheld_photo_count=int(row.get("withheld_photo_count", 0)),
            voice_note_count=int(row.get("voice_note_count", 0)),
            approved_provider_policy_count=int(row.get("approved_provider_policy_count", 0)),
            eligible_model_version_count=int(row.get("eligible_model_version_count", 0)),
        )

    async def begin_supplement_analysis(
        self,
        *,
        context: RequestContext,
        repair_order_id: UUID,
        idempotency_key: str,
    ) -> SupplementAnalysisContext:
        if context.actor_id is None:
            raise HTTPException(status_code=401, detail="Authenticated user identity required")
        headers = self._server_headers(content_type=True)
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.post(
                f"{self.url}/rest/v1/rpc/begin_supplement_analysis",
                headers=headers,
                json={
                    "p_actor_id": str(context.actor_id),
                    "p_organization_id": str(context.organization_id),
                    "p_repair_order_id": str(repair_order_id),
                    "p_environment": settings.environment,
                    "p_idempotency_key": idempotency_key,
                },
            )
        if response.status_code not in {200, 201}:
            raise HTTPException(status_code=409, detail="Supplement analysis prerequisites changed")
        payload = response.json()
        row = payload[0] if isinstance(payload, list) and payload else payload
        if not isinstance(row, dict):
            raise HTTPException(status_code=502, detail="Analysis context response was invalid")
        evidence_payload = row.get("evidence")
        lines_payload = row.get("estimate_lines")
        if not isinstance(evidence_payload, list) or not isinstance(lines_payload, list):
            raise HTTPException(status_code=502, detail="Analysis context was incomplete")
        return SupplementAnalysisContext(
            ai_job_id=UUID(row["ai_job_id"]),
            job_status=str(row["job_status"]),
            estimate_version_id=UUID(row["estimate_version_id"]),
            provider_key=str(row["provider_key"]),
            model_name=str(row["model_name"]),
            provider_model_version=(
                str(row["provider_model_version"]) if row.get("provider_model_version") else None
            ),
            prompt_template_version=str(row["prompt_template_version"]),
            schema_version=str(row["schema_version"]),
            estimate_lines=[dict(item) for item in lines_payload if isinstance(item, dict)],
            evidence=[
                AnalysisEvidenceReference(
                    media_id=UUID(item["media_id"]),
                    object_path=str(item["object_path"]),
                    mime_type=str(item["mime_type"]),
                    content_sha256=str(item["content_sha256"]),
                )
                for item in evidence_payload
                if isinstance(item, dict)
            ],
        )

    async def download_analysis_evidence(
        self,
        references: list[AnalysisEvidenceReference],
    ) -> list[DownloadedEvidence]:
        headers = self._server_headers()
        downloaded: list[DownloadedEvidence] = []
        total_bytes = 0
        async with httpx.AsyncClient(timeout=45) as client:
            for reference in references[: settings.max_analysis_photos]:
                object_url = (
                    f"{self.url}/storage/v1/object/repair-evidence/"
                    f"{quote(reference.object_path, safe='/')}"
                )
                response = await client.get(object_url, headers=headers)
                if response.status_code != 200:
                    raise HTTPException(status_code=502, detail="Private evidence retrieval failed")
                total_bytes += len(response.content)
                if total_bytes > settings.max_analysis_photo_bytes:
                    raise HTTPException(
                        status_code=413,
                        detail="Analysis evidence batch is too large",
                    )
                downloaded.append(
                    DownloadedEvidence(
                        media_id=reference.media_id,
                        mime_type=reference.mime_type,
                        content_sha256=reference.content_sha256,
                        data=response.content,
                    )
                )
        return downloaded

    async def complete_supplement_analysis(
        self,
        *,
        context: RequestContext,
        ai_job_id: UUID,
        provider_response_id: str,
        candidates: list[dict[str, object]],
        input_tokens: int,
        output_tokens: int,
        latency_ms: int,
    ) -> CompletedSupplementAnalysis:
        if context.actor_id is None:
            raise HTTPException(status_code=401, detail="Authenticated user identity required")
        headers = self._server_headers(content_type=True)
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(
                f"{self.url}/rest/v1/rpc/complete_supplement_analysis",
                headers=headers,
                json={
                    "p_ai_job_id": str(ai_job_id),
                    "p_actor_id": str(context.actor_id),
                    "p_provider_response_id": provider_response_id,
                    "p_candidates": candidates,
                    "p_input_tokens": input_tokens,
                    "p_output_tokens": output_tokens,
                    "p_latency_ms": latency_ms,
                },
            )
        if response.status_code not in {200, 201}:
            raise HTTPException(status_code=502, detail="Analysis result persistence failed")
        payload = response.json()
        row = payload[0] if isinstance(payload, list) and payload else payload
        if not isinstance(row, dict):
            raise HTTPException(status_code=502, detail="Analysis completion response was invalid")
        return CompletedSupplementAnalysis(
            ai_result_id=UUID(row["ai_result_id"]),
            created_finding_count=int(row["created_finding_count"]),
        )

    async def fail_supplement_analysis(
        self,
        *,
        context: RequestContext,
        ai_job_id: UUID,
        failure_code: str,
    ) -> None:
        if context.actor_id is None or not self.server_configured:
            return
        async with httpx.AsyncClient(timeout=15) as client:
            await client.post(
                f"{self.url}/rest/v1/rpc/fail_supplement_analysis",
                headers=self._server_headers(content_type=True),
                json={
                    "p_ai_job_id": str(ai_job_id),
                    "p_actor_id": str(context.actor_id),
                    "p_failure_code": failure_code[:100],
                },
            )

    async def create_supplement_review_package(
        self,
        *,
        context: RequestContext,
        repair_order_id: UUID,
    ) -> CreatedSupplementReviewPackage:
        if context.actor_id is None:
            raise HTTPException(status_code=401, detail="Authenticated user identity required")
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.post(
                f"{self.url}/rest/v1/rpc/create_supplement_review_package",
                headers=self._server_headers(content_type=True),
                json={
                    "p_actor_id": str(context.actor_id),
                    "p_organization_id": str(context.organization_id),
                    "p_repair_order_id": str(repair_order_id),
                },
            )
        if response.status_code not in {200, 201}:
            raise HTTPException(
                status_code=409,
                detail=(
                    "The review package could not be created. "
                    "Confirm at least one candidate is ready."
                ),
            )
        payload = response.json()
        row = payload[0] if isinstance(payload, list) and payload else payload
        if not isinstance(row, dict):
            raise HTTPException(status_code=502, detail="Review package response was invalid")
        return CreatedSupplementReviewPackage(
            package_id=UUID(row["package_id"]),
            package_number=int(row["package_number"]),
            item_count=int(row["item_count"]),
            package_status=str(row["package_status"]),
        )

    async def record_supplement_review_package_decision(
        self,
        *,
        context: RequestContext,
        package_id: UUID,
        decision: str,
        note: str | None,
        attestation: str | None,
    ) -> RecordedSupplementReviewPackageDecision:
        if context.actor_id is None:
            raise HTTPException(status_code=401, detail="Authenticated user identity required")
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.post(
                f"{self.url}/rest/v1/rpc/record_supplement_review_package_decision",
                headers=self._server_headers(content_type=True),
                json={
                    "p_actor_id": str(context.actor_id),
                    "p_organization_id": str(context.organization_id),
                    "p_package_id": str(package_id),
                    "p_decision": decision,
                    "p_note": note,
                    "p_attestation": attestation,
                },
            )
        if response.status_code not in {200, 201}:
            raise HTTPException(
                status_code=409,
                detail="The package decision could not be recorded. Refresh and retry.",
            )
        payload = response.json()
        row = payload[0] if isinstance(payload, list) and payload else payload
        if not isinstance(row, dict):
            raise HTTPException(status_code=502, detail="Package decision response was invalid")
        return RecordedSupplementReviewPackageDecision(
            package_id=UUID(row["package_id"]),
            package_status=str(row["package_status"]),
            decided_at=str(row["decided_at"]),
        )
