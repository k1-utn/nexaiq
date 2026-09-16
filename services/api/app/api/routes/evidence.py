from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.core.auth import RequestContext, require_request_context
from app.domain.evidence import CaptureKind, EvidenceCaptureResult
from app.services.evidence_validator import parse_json_object, read_validated_capture
from app.services.supabase_gateway import SupabaseGateway

router = APIRouter(tags=["mobile evidence"])


@router.post("/captures", response_model=EvidenceCaptureResult)
async def upload_capture(
    file: Annotated[UploadFile, File(description="Compressed teardown photo or voice note")],
    repair_order_id: Annotated[UUID, Form()],
    client_session_id: Annotated[UUID, Form()],
    client_capture_id: Annotated[UUID, Form()],
    capture_kind: Annotated[CaptureKind, Form()],
    sequence_number: Annotated[int, Form(ge=0)],
    captured_at: Annotated[datetime, Form()],
    context: Annotated[RequestContext, Depends(require_request_context)],
    privacy_flags: Annotated[str, Form()] = "{}",
    original_metadata: Annotated[str, Form()] = "{}",
) -> EvidenceCaptureResult:
    parsed_privacy_flags = parse_json_object(privacy_flags, field_name="privacy_flags")
    parsed_original_metadata = parse_json_object(original_metadata, field_name="original_metadata")
    capture = await read_validated_capture(
        file,
        capture_kind=capture_kind,
        captured_at=captured_at,
        privacy_flags=parsed_privacy_flags,
        original_metadata=parsed_original_metadata,
    )
    persisted = await SupabaseGateway().persist_capture(
        context=context,
        repair_order_id=repair_order_id,
        client_session_id=client_session_id,
        client_capture_id=client_capture_id,
        capture_kind=capture_kind,
        sequence_number=sequence_number,
        capture=capture,
    )
    return EvidenceCaptureResult(
        repair_order_id=repair_order_id,
        organization_id=context.organization_id,
        scan_session_id=persisted.scan_session_id,
        scan_session_media_id=persisted.scan_session_media_id,
        media_id=persisted.media_id,
        capture_kind=capture_kind,
        sequence_number=sequence_number,
        provenance=capture.provenance,
        persistence_status="already_persisted" if persisted.already_persisted else "persisted",
    )
