from datetime import UTC, datetime
from decimal import Decimal
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class VerificationStatus(StrEnum):
    REQUIRES_HUMAN_VERIFICATION = "requires_human_verification"
    VERIFIED = "verified"
    REJECTED = "rejected"


class EstimateLineDraft(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source_line_number: int | None = None
    operation_code: str | None = None
    description: str = Field(min_length=1, max_length=500)
    amount: Decimal | None = None
    raw_text: str = Field(min_length=1, max_length=2000)
    confidence: float = Field(ge=0, le=1)
    human_review_required: bool = True


class SourceProvenance(BaseModel):
    original_filename: str
    mime_type: str
    content_sha256: str = Field(pattern=r"^[a-f0-9]{64}$")
    uploaded_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    page_count: int = Field(ge=1)
    parser_name: str
    parser_version: str


class EstimateParseResult(BaseModel):
    repair_order_id: UUID
    organization_id: UUID
    verification_status: VerificationStatus = VerificationStatus.REQUIRES_HUMAN_VERIFICATION
    source: SourceProvenance
    lines: list[EstimateLineDraft]
    warnings: list[str]
    persistence_status: str = "development_not_persisted"
    estimate_version_id: UUID | None = None
    source_media_id: UUID | None = None
    disclaimer: str = (
        "Parsed estimate draft. A qualified estimator must verify every line "
        "against the original source."
    )
