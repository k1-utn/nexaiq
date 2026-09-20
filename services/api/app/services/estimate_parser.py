import hashlib
import io
import re
from decimal import Decimal, InvalidOperation

from fastapi import HTTPException, UploadFile, status
from pypdf import PdfReader
from pypdf.errors import PdfReadError

from app.core.config import settings
from app.domain.estimates import EstimateLineDraft, SourceProvenance

PARSER_NAME = "nexaiq_deterministic_pdf"
PARSER_VERSION = "0.1.0"
PDF_MAGIC = b"%PDF-"
LINE_PATTERN = re.compile(
    r"^\s*(?P<number>\d{1,4})\s+(?:(?P<operation>[A-Z&/]{1,8})\s+)?(?P<description>.{3,}?)\s+(?P<amount>-?\$?[\d,]+\.\d{2})\s*$"
)
CLEAR_COAT_PATTERN = re.compile(r"\bclear\s*-?\s*coat\b", re.IGNORECASE)


async def read_validated_pdf(upload: UploadFile) -> bytes:
    if upload.content_type not in {"application/pdf", "application/x-pdf"}:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Only PDF estimates are accepted",
        )
    data = await upload.read(settings.max_estimate_bytes + 1)
    if len(data) > settings.max_estimate_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Estimate exceeds configured size limit",
        )
    if not data.startswith(PDF_MAGIC):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="File content is not a valid PDF",
        )
    return data


def extract_pdf(data: bytes, filename: str, mime_type: str) -> tuple[SourceProvenance, list[str]]:
    try:
        reader = PdfReader(io.BytesIO(data), strict=True)
    except (PdfReadError, ValueError) as exc:
        raise HTTPException(status_code=422, detail="PDF could not be safely parsed") from exc
    if reader.is_encrypted:
        raise HTTPException(status_code=422, detail="Encrypted PDFs require manual preprocessing")
    if not reader.pages or len(reader.pages) > settings.max_pdf_pages:
        raise HTTPException(status_code=422, detail="PDF page count is outside the accepted range")
    text: list[str] = []
    for page in reader.pages:
        try:
            text.append(page.extract_text(extraction_mode="layout") or "")
        except KeyError:
            text.append("")
    provenance = SourceProvenance(
        original_filename=filename,
        mime_type=mime_type,
        content_sha256=hashlib.sha256(data).hexdigest(),
        page_count=len(reader.pages),
        parser_name=PARSER_NAME,
        parser_version=PARSER_VERSION,
    )
    return provenance, text


def parse_estimate_lines(pages: list[str]) -> tuple[list[EstimateLineDraft], list[str]]:
    """Parse common estimate-line shapes without executing or obeying document text."""
    lines: list[EstimateLineDraft] = []
    for page in pages:
        for raw_line in page.splitlines():
            compact = " ".join(raw_line.split())
            match = LINE_PATTERN.match(compact)
            if not match:
                continue
            amount_text = match.group("amount").replace("$", "").replace(",", "")
            try:
                amount = Decimal(amount_text)
            except InvalidOperation:
                amount = None
            lines.append(
                EstimateLineDraft(
                    source_line_number=int(match.group("number")),
                    operation_code=match.group("operation"),
                    description=match.group("description"),
                    amount=amount,
                    raw_text=compact,
                    confidence=0.72,
                    human_review_required=not bool(
                        CLEAR_COAT_PATTERN.search(match.group("description"))
                    ),
                    line_role=(
                        "automatic_refinish_calculation"
                        if CLEAR_COAT_PATTERN.search(match.group("description"))
                        else "estimate_operation"
                    ),
                )
            )
    warnings = ["Document content was treated as untrusted data and was not executed."]
    if not lines:
        warnings.append(
            "No estimate lines matched deterministic patterns; manual review is required."
        )
    return lines, warnings
