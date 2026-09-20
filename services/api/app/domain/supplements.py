from enum import StrEnum
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ReadinessBlocker(StrEnum):
    VERIFIED_ESTIMATE_REQUIRED = "verified_estimate_required"
    PHOTO_EVIDENCE_REQUIRED = "photo_evidence_required"
    APPROVED_PROVIDER_POLICY_REQUIRED = "approved_provider_policy_required"
    EVALUATED_MODEL_REQUIRED = "evaluated_model_required"
    PRIVACY_ELIGIBLE_PHOTO_REQUIRED = "privacy_eligible_photo_required"
    SERVER_SECRET_REQUIRED = "server_secret_required"  # noqa: S105 - readiness code
    PROVIDER_CREDENTIAL_REQUIRED = "provider_credential_required"
    PAID_AI_DISABLED = "paid_ai_disabled"


class SupplementAnalysisReadiness(BaseModel):
    model_config = ConfigDict(extra="forbid")

    organization_id: UUID
    repair_order_id: UUID
    ready: bool
    blockers: list[ReadinessBlocker]
    verified_estimate_version_id: UUID | None
    photo_count: int = Field(ge=0)
    eligible_photo_count: int = Field(ge=0)
    withheld_photo_count: int = Field(ge=0)
    voice_note_count: int = Field(ge=0)
    approved_provider_policy_count: int = Field(ge=0)
    eligible_model_version_count: int = Field(ge=0)
    human_review_required: Literal[True] = True
    disclaimer: str = (
        "Readiness does not authorize automatic estimate changes or insurer submission. "
        "Every generated candidate requires estimator review."
    )


class SourceQuality(StrEnum):
    SOURCE_DOCUMENT = "source_document"
    CAMERA_ONLY = "camera_only"
    MIXED = "mixed"
    UNKNOWN = "unknown"


class ComparisonStatus(StrEnum):
    ALREADY_IN_VERIFIED_ESTIMATE = "already_in_verified_estimate"
    POSSIBLE_MISSING_OPERATION = "possible_missing_operation"
    AUTOMATIC_OPERATION_EXCLUDED = "automatic_operation_excluded"
    INSUFFICIENT_EVIDENCE = "insufficient_evidence"


class MatchMethod(StrEnum):
    NONE = "none"
    OPERATION_CODE_EXACT = "operation_code_exact"
    DESCRIPTION_EXACT = "description_exact"


class VerifiedEstimateLine(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    operation_code: str | None = Field(default=None, max_length=100)
    description: str = Field(min_length=1, max_length=500)


class VisionObservation(BaseModel):
    model_config = ConfigDict(extra="forbid")

    finding_type: str = Field(min_length=1, max_length=100)
    component: str | None = Field(default=None, max_length=200)
    condition: str | None = Field(default=None, max_length=200)
    proposed_operation: str = Field(min_length=1, max_length=500)
    operation_code: str | None = Field(default=None, max_length=100)
    confidence: float = Field(ge=0, le=1)
    source_quality: SourceQuality
    evidence_ids: list[UUID] = Field(min_length=1)
    reason: str = Field(min_length=1, max_length=2000)
    limitations: list[str]
    human_review_required: Literal[True] = True


class CandidateComparison(BaseModel):
    model_config = ConfigDict(extra="forbid")

    comparison_status: ComparisonStatus
    match_method: MatchMethod
    matched_estimate_line_id: UUID | None = None
    confidence: float = Field(ge=0, le=1)
    source_quality: SourceQuality
    evidence_ids: list[UUID]
    reason: str
    limitations: list[str]
    human_review_required: Literal[True] = True
    can_create_supplement_candidate: bool


class VisionAnalysisOutput(BaseModel):
    model_config = ConfigDict(extra="forbid")

    observations: list[VisionObservation] = Field(max_length=100)


class SupplementAnalysisRunResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    organization_id: UUID
    repair_order_id: UUID
    ai_job_id: UUID
    ai_result_id: UUID
    created_finding_count: int = Field(ge=0)
    status: Literal["completed"] = "completed"
    human_review_required: Literal[True] = True
    disclaimer: str = (
        "Generated records are possible supplement candidates only. They do not modify "
        "the estimate or submit a supplement."
    )


class SupplementReviewPackageCreateResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    package_id: UUID
    package_number: int = Field(gt=0)
    item_count: int = Field(gt=0)
    package_status: Literal["draft"] = "draft"


class SupplementReviewPackageDecisionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    decision: Literal["approved", "changes_requested"]
    note: str | None = Field(default=None, max_length=4000)
    attestation: str | None = Field(default=None, max_length=1000)


class SupplementReviewPackageDecisionResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    package_id: UUID
    package_status: Literal["approved", "changes_requested"]
    decided_at: str
