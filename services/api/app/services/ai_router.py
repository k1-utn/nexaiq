from dataclasses import dataclass
from enum import StrEnum


class Provider(StrEnum):
    OPENAI = "openai"
    ANTHROPIC = "anthropic"
    GOOGLE = "google"
    NEXAIQ = "nexaiq"


@dataclass(frozen=True)
class ProviderPolicy:
    provider: Provider
    enabled: bool
    approved_purposes: frozenset[str]
    allowed_data_categories: frozenset[str]
    required_region: str | None = None
    training_allowed: bool = False


class ProviderNotAllowedError(PermissionError):
    pass


class AiProviderRouter:
    """Deterministic policy gate. Provider calls belong behind this boundary."""

    def select(
        self, policies: list[ProviderPolicy], purpose: str, data_categories: set[str]
    ) -> Provider:
        for policy in policies:
            if not policy.enabled or purpose not in policy.approved_purposes:
                continue
            if data_categories.issubset(policy.allowed_data_categories):
                return policy.provider
        raise ProviderNotAllowedError(
            "No organization-approved AI provider can process this request"
        )
