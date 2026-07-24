from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, StrictInt, StrictStr


class OrganizationCreate(BaseModel):
    name: str = Field(min_length=2, max_length=160)


class OrganizationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    slug: str
    owner_id: str
    status: str


class OrganizationMemberCreate(BaseModel):
    email: str
    role: Literal["teacher", "manager", "viewer"] = "teacher"


class MembershipOut(BaseModel):
    id: str
    user_id: str
    organization_id: str
    role: str
    status: str


class ConsentCreate(BaseModel):
    consent_type: str = Field(min_length=2, max_length=80)
    version: str = Field(min_length=1, max_length=40)
    granted: bool


class ConsentOut(ConsentCreate):
    id: str
    organization_id: str
    user_id: str
    granted_at: datetime | None
    revoked_at: datetime | None


class TeacherProfileWrite(BaseModel):
    organization_id: str
    years_experience: StrictInt = Field(default=0, ge=0, le=80)
    specialty: str = Field(default="", max_length=160)
    context: dict[str, str] = Field(default_factory=dict)


class TeacherProfileOut(BaseModel):
    id: str
    organization_id: str
    user_id: str
    years_experience: int
    specialty: str
    context: dict[str, str]


class DiagnosisSessionCreate(BaseModel):
    organization_id: str
    goal: str = Field(min_length=2, max_length=300)


class DiagnosisEvidenceInput(BaseModel):
    indicator_id: str = Field(min_length=1, max_length=100)
    anchor: StrictInt = Field(ge=0)
    anchor_count: StrictInt = Field(ge=2, le=10)
    confidence_decimal: StrictStr = Field(pattern=r"^(?:0|1)\.\d{6}$")
    quoted_span: str = Field(min_length=1, max_length=500)


class DiagnosisTurnCreate(BaseModel):
    content: str = Field(min_length=1, max_length=5000)
    evidence: list[DiagnosisEvidenceInput] = Field(default_factory=list, max_length=100)


class DiagnosisTurnOut(BaseModel):
    id: str
    sequence: int
    role: str
    content_length: int
    evidence_count: int
    created_at: datetime


class DiagnosisSessionOut(BaseModel):
    id: str
    organization_id: str
    goal: str
    status: str
    policy_version: str
    current_sequence: int
    turns: list[DiagnosisTurnOut]
    result: dict | None = None


class LearningPathOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    title: str
    description: str
    persona_code: str
    difficulty: str


class EnrollmentCreate(BaseModel):
    organization_id: str
    path_id: str


class EnrollmentOut(BaseModel):
    id: str
    organization_id: str
    user_id: str
    path_id: str
    status: str
    progress_microunit: int


class ActivityCreate(BaseModel):
    content_id: str = Field(min_length=1, max_length=120)
    activity_type: str = Field(min_length=1, max_length=40)
    status: Literal["started", "completed", "skipped"] = "started"
    score_microunit: int | None = Field(default=None, ge=0, le=1_000_000)


class DocumentCreate(BaseModel):
    organization_id: str
    title: str = Field(min_length=2, max_length=240)
    mime_type: str = Field(default="text/plain", max_length=120)
    content: str = Field(min_length=1, max_length=2_000_000)
    sensitivity: Literal["internal", "restricted"] = "internal"


class DocumentOut(BaseModel):
    id: str
    organization_id: str
    title: str
    mime_type: str
    sensitivity: str
    status: str
    latest_version_id: str | None


class KnowledgeSearchResult(BaseModel):
    node_id: str
    document_id: str
    document_title: str
    content: str
    citations: list[dict]
    score_microunit: int


class ReportCreate(BaseModel):
    organization_id: str
    report_type: Literal["diagnosis", "learning", "pilot"]
    session_id: str | None = None


class ReportOut(BaseModel):
    id: str
    organization_id: str
    user_id: str
    report_type: str
    status: str
    snapshot: dict


class PilotMetricCreate(BaseModel):
    organization_id: str
    metric_name: str = Field(min_length=2, max_length=100)
    value_microunit: StrictInt = Field(ge=0, le=1_000_000)
    period: str = Field(min_length=4, max_length=30)
