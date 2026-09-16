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
    codes = {
        str(payload.get(field, "")).casefold()
        for field in ("code", "error")
    }
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


class SupabaseGateway:
    def __init__(self) -> None:
        self.url = settings.supabase_url
        self.key = settings.supabase_publishable_key

    @property
    def configured(self) -> bool:
        return bool(self.url and self.key)

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
