from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.core.auth import RequestContext, require_request_context
from app.domain.estimates import EstimateParseResult
from app.services.estimate_parser import extract_pdf, parse_estimate_lines, read_validated_pdf
from app.services.supabase_gateway import SupabaseGateway

router = APIRouter(tags=["estimate ingestion"])


@router.post("/parse", response_model=EstimateParseResult)
async def parse_estimate(
    file: Annotated[UploadFile, File(description="Original Mitchell estimate PDF")],
    repair_order_id: Annotated[UUID, Form()],
    context: Annotated[RequestContext, Depends(require_request_context)],
) -> EstimateParseResult:
    data = await read_validated_pdf(file)
    provenance, pages = extract_pdf(
        data, file.filename or "estimate.pdf", file.content_type or "application/pdf"
    )
    lines, warnings = parse_estimate_lines(pages)
    persisted = await SupabaseGateway().persist_estimate(
        context=context,
        repair_order_id=repair_order_id,
        data=data,
        source=provenance,
        lines=lines,
    )
    return EstimateParseResult(
        repair_order_id=repair_order_id,
        organization_id=context.organization_id,
        source=provenance,
        lines=lines,
        warnings=warnings,
        persistence_status="persisted" if persisted else "development_not_persisted",
        estimate_version_id=persisted.estimate_version_id if persisted else None,
        source_media_id=persisted.source_media_id if persisted else None,
    )
