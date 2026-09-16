import hashlib
import json
from dataclasses import dataclass
from datetime import datetime

from fastapi import HTTPException, UploadFile, status

from app.core.config import settings
from app.domain.evidence import CaptureKind, CaptureProvenance

PHOTO_MIME_TYPES = {"image/jpeg", "image/png"}
VOICE_MIME_TYPES = {"audio/mp4", "audio/m4a", "audio/x-m4a", "audio/3gpp", "audio/webm"}


@dataclass(frozen=True)
class ValidatedCapture:
    data: bytes
    provenance: CaptureProvenance
    original_metadata: dict[str, object]


def _has_expected_magic(data: bytes, mime_type: str) -> bool:
    if mime_type == "image/jpeg":
        return data.startswith(b"\xff\xd8\xff")
    if mime_type == "image/png":
        return data.startswith(b"\x89PNG\r\n\x1a\n")
    if mime_type in {"audio/mp4", "audio/m4a", "audio/x-m4a", "audio/3gpp"}:
        return len(data) >= 12 and data[4:8] == b"ftyp"
    if mime_type == "audio/webm":
        return data.startswith(b"\x1a\x45\xdf\xa3")
    return False


def parse_json_object(value: str, *, field_name: str) -> dict[str, object]:
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=422, detail=f"{field_name} must be valid JSON") from exc
    if not isinstance(parsed, dict):
        raise HTTPException(status_code=422, detail=f"{field_name} must be a JSON object")
    return parsed


async def read_validated_capture(
    file: UploadFile,
    *,
    capture_kind: CaptureKind,
    captured_at: datetime,
    privacy_flags: dict[str, object],
    original_metadata: dict[str, object],
) -> ValidatedCapture:
    mime_type = (file.content_type or "").lower()
    allowed = PHOTO_MIME_TYPES if capture_kind == "photo" else VOICE_MIME_TYPES
    if mime_type not in allowed:
        raise HTTPException(status_code=415, detail="Unsupported capture MIME type")

    byte_limit = (
        settings.max_capture_photo_bytes
        if capture_kind == "photo"
        else settings.max_capture_voice_bytes
    )
    data = await file.read(byte_limit + 1)
    if not data:
        raise HTTPException(status_code=422, detail="Capture is empty")
    if len(data) > byte_limit:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Capture is too large",
        )
    if not _has_expected_magic(data, mime_type):
        raise HTTPException(status_code=415, detail="Capture content does not match its MIME type")

    bool_flags = {key: value for key, value in privacy_flags.items() if isinstance(value, bool)}
    if len(bool_flags) != len(privacy_flags):
        raise HTTPException(status_code=422, detail="Privacy flags must contain boolean values")

    return ValidatedCapture(
        data=data,
        provenance=CaptureProvenance(
            original_filename=file.filename
            or ("capture.jpg" if capture_kind == "photo" else "voice.m4a"),
            mime_type=mime_type,
            byte_size=len(data),
            content_sha256=hashlib.sha256(data).hexdigest(),
            captured_at=captured_at,
            privacy_flags=bool_flags,
        ),
        original_metadata=original_metadata,
    )
