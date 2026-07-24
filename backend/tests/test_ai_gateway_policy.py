from app.ai_gateway import (
    CanonicalAIRequest,
    DataClass,
    DeterministicGateway,
    GatewayPolicyError,
    SafeguardingDecision,
)


def test_restricted_data_is_denied_before_external_provider_call():
    gateway = DeterministicGateway()
    request = CanonicalAIRequest(
        task="diagnosis.evidence.extract",
        input={"text": "redacted"},
        response_schema_id="evidence.v1",
        data_class=DataClass.RESTRICTED,
        allowed_destination="OPENAI",
        safeguarding_decision=SafeguardingDecision.STANDARD,
    )

    try:
        gateway.generate(request)
    except GatewayPolicyError as error:
        assert error.code == "DATA_CLASS_DENIED"
    else:
        raise AssertionError("restricted external request must be denied")
    assert gateway.provider_calls == 0


def test_standard_internal_request_reaches_deterministic_provider():
    gateway = DeterministicGateway()
    request = CanonicalAIRequest(
        task="diagnosis.evidence.extract",
        input={"text": "redacted"},
        response_schema_id="evidence.v1",
        data_class=DataClass.INTERNAL,
        allowed_destination="DETERMINISTIC",
        safeguarding_decision=SafeguardingDecision.STANDARD,
    )

    response = gateway.generate(request)

    assert response["schema_version"] == "evidence.v1"
    assert gateway.provider_calls == 1


def test_safeguarding_route_blocks_normal_model_provider():
    gateway = DeterministicGateway()
    request = CanonicalAIRequest(
        task="diagnosis.evidence.extract",
        input={"text": "redacted"},
        response_schema_id="evidence.v1",
        data_class=DataClass.INTERNAL,
        allowed_destination="INTERNAL_SLLM",
        safeguarding_decision=SafeguardingDecision.CHILD_SAFEGUARDING,
    )

    try:
        gateway.generate(request)
    except GatewayPolicyError as error:
        assert error.code == "SAFEGUARDING_ROUTE_REQUIRED"
    else:
        raise AssertionError("safeguarding input must not reach a normal model provider")
    assert gateway.provider_calls == 0
