from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

CaptureKind = Literal["photo", "voice_note"]


class CaptureProvenance(BaseModel):
    original_filename: str
    mime_type: str
    byte_size: int
    content_sha256: str
    captured_at: datetime
    privacy_flags: dict[str, bool] = Field(default_factory=dict)


class EvidenceCaptureResult(BaseModel):
    repair_order_id: UUID
    organization_id: UUID
    scan_session_id: UUID
    scan_session_media_id: UUID
    media_id: UUID
    capture_kind: CaptureKind
    sequence_number: int
    provenance: CaptureProvenance
    persistence_status: Literal["persisted", "already_persisted"]
