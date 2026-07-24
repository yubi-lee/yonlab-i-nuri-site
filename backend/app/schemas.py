from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, StrictInt, StrictStr, model_validator


class UserCreate(BaseModel):
    email: EmailStr
    name: str = Field(min_length=2, max_length=80)
    password: str = Field(min_length=10, max_length=128)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    email: EmailStr
    name: str
    role: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    refresh_token: str
    user: UserOut


class ResourceWrite(BaseModel):
    title: str = Field(min_length=2, max_length=180)
    summary: str = Field(min_length=2, max_length=500)
    body: str = Field(min_length=2)
    audience: str = Field(min_length=2, max_length=60)
    resource_type: str = Field(min_length=2, max_length=60)
    category_id: str
    status: str = "draft"
    featured: bool = False
    tag_ids: list[str] = []


class InquiryCreate(BaseModel):
    email: EmailStr
    subject: str = Field(min_length=2, max_length=180)
    message: str = Field(min_length=10, max_length=5000)
    privacy_agreed: bool


class InquiryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    email: EmailStr
    subject: str
    message: str
    status: str
    admin_note: str
    created_at: datetime

_FIXED_SIX_PATTERN = r"^(?:0|1)\.\d{6}$"


class DiagnosisEvidence(BaseModel):
    model_config = ConfigDict(extra="forbid")

    evidence_id: UUID
    turn_id: UUID
    turn_sequence: StrictInt = Field(ge=1)
    indicator_id: StrictStr = Field(min_length=1, max_length=100)
    anchor: StrictInt = Field(ge=0)
    anchor_count: StrictInt = Field(ge=2, le=10)
    confidence_decimal: StrictStr = Field(pattern=_FIXED_SIX_PATTERN)
    span_start_codepoint: StrictInt = Field(ge=0)
    span_end_codepoint: StrictInt = Field(ge=0)
    quoted_span: StrictStr = Field(min_length=1, max_length=500)
    schema_version: Literal["evidence.v1"]

    @model_validator(mode="after")
    def validate_span(self) -> "DiagnosisEvidence":
        if self.span_end_codepoint < self.span_start_codepoint:
            raise ValueError("span_end_codepoint must not precede span_start_codepoint")
        return self


class DiagnosisScoreRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    anchor_count: StrictInt = Field(ge=2, le=10)
    evidence: list[DiagnosisEvidence] = Field(min_length=1, max_length=100)
    dimension_weight_decimal: StrictStr = Field(
        default="1.000000", pattern=_FIXED_SIX_PATTERN
    )
    indicator_weight_decimal: StrictStr = Field(
        default="1.000000", pattern=_FIXED_SIX_PATTERN
    )

    @model_validator(mode="after")
    def validate_evidence_anchor_count(self) -> "DiagnosisScoreRequest":
        if any(item.anchor_count != self.anchor_count for item in self.evidence):
            raise ValueError("evidence anchor_count must match request anchor_count")
        return self


class DiagnosisScoreResponse(BaseModel):
    policy_version: Literal["diagnosis-scoring.v1"]
    status: Literal["OK", "INVALID_EVIDENCE", "INSUFFICIENT_EVIDENCE"]
    dimension_score_microunit: int | None
    overall_score_microunit: int | None
    confidence_microunit: int | None
    conflict_microunit: int
    selected_evidence_id: StrictStr | None
    request_id: StrictStr
    persisted: Literal[False] = False
