"""A small, provider-neutral AI Gateway policy boundary.

Application code must submit canonical requests here instead of importing a
provider SDK.  The production deployment can replace the deterministic stub
with an independently deployed gateway without changing the caller contract.
"""

from collections.abc import Mapping
from dataclasses import dataclass
from enum import Enum
from typing import Any


class DataClass(str, Enum):
    PUBLIC = "PUBLIC"
    INTERNAL = "INTERNAL"
    RESTRICTED = "RESTRICTED"
    UNKNOWN = "UNKNOWN"


class SafeguardingDecision(str, Enum):
    STANDARD = "STANDARD"
    CHILD_SAFEGUARDING = "CHILD_SAFEGUARDING"
    IMMINENT_DANGER = "IMMINENT_DANGER"
    SECURITY_EXFILTRATION = "SECURITY_EXFILTRATION"
    POLICY_BLOCK = "POLICY_BLOCK"


@dataclass(frozen=True)
class CanonicalAIRequest:
    task: str
    input: Mapping[str, Any]
    response_schema_id: str
    data_class: DataClass
    allowed_destination: str
    safeguarding_decision: SafeguardingDecision


class GatewayPolicyError(RuntimeError):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


class DeterministicGateway:
    """Local provider stub used by tests and development environments."""

    _DESTINATIONS = {"DETERMINISTIC", "INTERNAL_SLLM", "OPENAI"}
    _RESTRICTED_DESTINATIONS = {"DETERMINISTIC", "INTERNAL_SLLM"}

    def __init__(self) -> None:
        self.provider_calls = 0

    def _authorize(self, request: CanonicalAIRequest) -> None:
        if request.data_class is DataClass.UNKNOWN:
            raise GatewayPolicyError("DATA_CLASS_DENIED")
        if request.data_class not in {
            DataClass.PUBLIC,
            DataClass.INTERNAL,
            DataClass.RESTRICTED,
        }:
            raise GatewayPolicyError("DATA_CLASS_DENIED")
        if request.safeguarding_decision is not SafeguardingDecision.STANDARD:
            raise GatewayPolicyError("SAFEGUARDING_ROUTE_REQUIRED")
        if request.allowed_destination not in self._DESTINATIONS:
            raise GatewayPolicyError("DATA_CLASS_DENIED")
        if (
            request.data_class is DataClass.RESTRICTED
            and request.allowed_destination not in self._RESTRICTED_DESTINATIONS
        ):
            raise GatewayPolicyError("DATA_CLASS_DENIED")
        if not request.task or not request.response_schema_id or not request.input:
            raise GatewayPolicyError("INVALID_CANONICAL_REQUEST")

    def generate(self, request: CanonicalAIRequest) -> dict[str, Any]:
        self._authorize(request)
        self.provider_calls += 1
        # A stub response is deliberately independent of the input body.  This
        # keeps development tests deterministic and prevents accidental logging
        # or persistence of restricted source text.
        return {
            "schema_version": request.response_schema_id,
            "task": request.task,
            "output": {"status": "deterministic_stub"},
            "destination": request.allowed_destination,
        }
