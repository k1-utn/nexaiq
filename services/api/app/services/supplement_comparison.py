import re
import unicodedata

from app.domain.supplements import (
    CandidateComparison,
    ComparisonStatus,
    MatchMethod,
    SourceQuality,
    VerifiedEstimateLine,
    VisionObservation,
)

MINIMUM_CANDIDATE_CONFIDENCE = 0.60
AUTOMATIC_CLEAR_COAT_PATTERN = re.compile(r"\bclear\s*-?\s*coat\b", re.IGNORECASE)
NON_ALPHANUMERIC = re.compile(r"[^a-z0-9]+")


def _normalize(value: str | None) -> str:
    if not value:
        return ""
    ascii_value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    return NON_ALPHANUMERIC.sub(" ", ascii_value.casefold()).strip()


def _is_automatic_clear_coat(observation: VisionObservation) -> bool:
    return bool(
        AUTOMATIC_CLEAR_COAT_PATTERN.search(observation.proposed_operation)
        or AUTOMATIC_CLEAR_COAT_PATTERN.search(observation.finding_type)
    )


def compare_observation_to_estimate(
    observation: VisionObservation,
    estimate_lines: list[VerifiedEstimateLine],
) -> CandidateComparison:
    """Compare a sourced observation without making a fuzzy or autonomous decision."""
    if _is_automatic_clear_coat(observation):
        return CandidateComparison(
            comparison_status=ComparisonStatus.AUTOMATIC_OPERATION_EXCLUDED,
            match_method=MatchMethod.NONE,
            confidence=observation.confidence,
            source_quality=observation.source_quality,
            evidence_ids=observation.evidence_ids,
            reason="Clear coat is automatically included and is not a missing supplement item.",
            limitations=observation.limitations,
            can_create_supplement_candidate=False,
        )

    normalized_code = _normalize(observation.operation_code)
    normalized_description = _normalize(observation.proposed_operation)
    for line in estimate_lines:
        line_description = _normalize(line.description)
        if (
            normalized_code
            and normalized_code == _normalize(line.operation_code)
            and normalized_description
            and normalized_description == line_description
        ):
            return CandidateComparison(
                comparison_status=ComparisonStatus.ALREADY_IN_VERIFIED_ESTIMATE,
                match_method=MatchMethod.OPERATION_CODE_EXACT,
                matched_estimate_line_id=line.id,
                confidence=observation.confidence,
                source_quality=observation.source_quality,
                evidence_ids=observation.evidence_ids,
                reason=(
                    "An exact operation-code and description match exists in the verified estimate."
                ),
                limitations=observation.limitations,
                can_create_supplement_candidate=False,
            )
        if normalized_description and normalized_description == line_description:
            return CandidateComparison(
                comparison_status=ComparisonStatus.ALREADY_IN_VERIFIED_ESTIMATE,
                match_method=MatchMethod.DESCRIPTION_EXACT,
                matched_estimate_line_id=line.id,
                confidence=observation.confidence,
                source_quality=observation.source_quality,
                evidence_ids=observation.evidence_ids,
                reason="An exact description match exists in the verified estimate.",
                limitations=observation.limitations,
                can_create_supplement_candidate=False,
            )

    if (
        observation.confidence < MINIMUM_CANDIDATE_CONFIDENCE
        or observation.source_quality == SourceQuality.UNKNOWN
    ):
        limitations = list(observation.limitations)
        if observation.confidence < MINIMUM_CANDIDATE_CONFIDENCE:
            limitations.append("Confidence is below the candidate threshold.")
        if observation.source_quality == SourceQuality.UNKNOWN:
            limitations.append("Source quality is unknown.")
        return CandidateComparison(
            comparison_status=ComparisonStatus.INSUFFICIENT_EVIDENCE,
            match_method=MatchMethod.NONE,
            confidence=observation.confidence,
            source_quality=observation.source_quality,
            evidence_ids=observation.evidence_ids,
            reason="The observation needs more evidence before estimator consideration.",
            limitations=limitations,
            can_create_supplement_candidate=False,
        )

    return CandidateComparison(
        comparison_status=ComparisonStatus.POSSIBLE_MISSING_OPERATION,
        match_method=MatchMethod.NONE,
        confidence=observation.confidence,
        source_quality=observation.source_quality,
        evidence_ids=observation.evidence_ids,
        reason=(
            "No exact match was found in the verified estimate. This is a possible "
            "supplement candidate, not an approved estimate change."
        ),
        limitations=[
            *observation.limitations,
            "Only exact operation-code and description matches are automated.",
        ],
        can_create_supplement_candidate=True,
    )
