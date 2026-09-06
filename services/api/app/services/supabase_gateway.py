import re
from dataclasses import dataclass
from urllib.parse import quote
from uuid import UUID, uuid4

import httpx
from fastapi import HTTPException

from app.core.auth import RequestContext
from app.core.config import settings
from app.domain.estimates import EstimateLineDraft, SourceProvenance

SAFE_FILENAME = re.compile(r"[^A-Za-z0-9._-]+")


@dataclass(frozen=True)
class PersistedEstimate:
    estimate_version_id: UUID
    source_media_id: UUID


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
