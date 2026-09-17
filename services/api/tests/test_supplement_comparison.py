from uuid import UUID

from app.domain.supplements import (
    ComparisonStatus,
    MatchMethod,
    SourceQuality,
    VerifiedEstimateLine,
    VisionObservation,
)
from app.services.supplement_comparison import compare_observation_to_estimate

EVIDENCE_ID = UUID("00000000-0000-0000-0000-000000000101")
LINE_ID = UUID("00000000-0000-0000-0000-000000000201")


def observation(**overrides: object) -> VisionObservation:
    values: dict[str, object] = {
        "finding_type": "possible_missing_operation",
        "component": "front bumper",
        "condition": "removed for inspection",
        "proposed_operation": "R&I front bumper cover",
        "operation_code": "R&I",
        "confidence": 0.84,
        "source_quality": SourceQuality.MIXED,
        "evidence_ids": [EVIDENCE_ID],
        "reason": "The teardown photo shows the cover removed.",
        "limitations": ["Fasteners are partially obscured."],
        "human_review_required": True,
    }
    values.update(overrides)
    return VisionObservation.model_validate(values)


def test_clear_coat_is_never_created_as_a_missing_supplement() -> None:
    result = compare_observation_to_estimate(
        observation(proposed_operation="Add clear-coat operation"),
        [],
    )

    assert result.comparison_status == ComparisonStatus.AUTOMATIC_OPERATION_EXCLUDED
    assert result.can_create_supplement_candidate is False
    assert result.human_review_required is True


def test_exact_operation_code_match_is_already_in_estimate() -> None:
    result = compare_observation_to_estimate(
        observation(operation_code="  R&I  "),
        [
            VerifiedEstimateLine(
                id=LINE_ID,
                operation_code="r&i",
                description="R&I front bumper cover",
            )
        ],
    )

    assert result.comparison_status == ComparisonStatus.ALREADY_IN_VERIFIED_ESTIMATE
    assert result.match_method == MatchMethod.OPERATION_CODE_EXACT
    assert result.matched_estimate_line_id == LINE_ID
    assert result.can_create_supplement_candidate is False


def test_generic_operation_code_alone_does_not_suppress_a_candidate() -> None:
    result = compare_observation_to_estimate(
        observation(operation_code="R&I"),
        [
            VerifiedEstimateLine(
                id=LINE_ID,
                operation_code="R&I",
                description="R&I rear bumper cover",
            )
        ],
    )

    assert result.comparison_status == ComparisonStatus.POSSIBLE_MISSING_OPERATION
    assert result.can_create_supplement_candidate is True


def test_low_confidence_observation_requires_more_evidence() -> None:
    result = compare_observation_to_estimate(observation(confidence=0.59), [])

    assert result.comparison_status == ComparisonStatus.INSUFFICIENT_EVIDENCE
    assert result.can_create_supplement_candidate is False
    assert "Confidence is below the candidate threshold." in result.limitations


def test_sourced_unmatched_observation_is_candidate_only() -> None:
    result = compare_observation_to_estimate(observation(operation_code="CAL"), [])

    assert result.comparison_status == ComparisonStatus.POSSIBLE_MISSING_OPERATION
    assert result.match_method == MatchMethod.NONE
    assert result.can_create_supplement_candidate is True
    assert result.human_review_required is True
