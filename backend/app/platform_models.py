"""Core multi-tenant learning-platform persistence models.

The models in this module are deliberately independent from the public portal
content models.  They keep tenant, diagnosis, learning, and document concerns
behind replaceable service boundaries while sharing the application's SQLAlchemy
metadata and transaction lifecycle.
"""

from datetime import UTC, datetime

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models import TimestampMixin, uid


class Organization(TimestampMixin, Base):
    __tablename__ = "organizations"
    __table_args__ = (UniqueConstraint("slug", name="uq_organizations_slug"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    name: Mapped[str] = mapped_column(String(160))
    slug: Mapped[str] = mapped_column(String(160), index=True)
    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="RESTRICT"), index=True)
    status: Mapped[str] = mapped_column(String(30), default="active", index=True)

    memberships: Mapped[list["OrganizationMembership"]] = relationship(
        cascade="all, delete-orphan", back_populates="organization"
    )


class OrganizationMembership(TimestampMixin, Base):
    __tablename__ = "organization_memberships"
    __table_args__ = (
        UniqueConstraint("organization_id", "user_id", name="uq_org_membership_user"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    organization_id: Mapped[str] = mapped_column(
        ForeignKey("organizations.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    role: Mapped[str] = mapped_column(String(30), default="teacher", index=True)
    status: Mapped[str] = mapped_column(String(30), default="active", index=True)
    joined_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(UTC)
    )

    organization: Mapped[Organization] = relationship(back_populates="memberships")


class ConsentRecord(TimestampMixin, Base):
    __tablename__ = "consent_records"
    __table_args__ = (
        UniqueConstraint(
            "organization_id", "user_id", "consent_type", "version", name="uq_consent_version"
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    organization_id: Mapped[str] = mapped_column(
        ForeignKey("organizations.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    consent_type: Mapped[str] = mapped_column(String(80), index=True)
    version: Mapped[str] = mapped_column(String(40))
    granted: Mapped[bool] = mapped_column(Boolean, default=False)
    granted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class TeacherProfile(TimestampMixin, Base):
    __tablename__ = "teacher_profiles"
    __table_args__ = (
        UniqueConstraint("organization_id", "user_id", name="uq_teacher_profile_org_user"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    organization_id: Mapped[str] = mapped_column(
        ForeignKey("organizations.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    years_experience: Mapped[int] = mapped_column(Integer, default=0)
    specialty: Mapped[str] = mapped_column(String(160), default="")
    context_json: Mapped[str] = mapped_column(Text, default="{}")


class DiagnosisSession(TimestampMixin, Base):
    __tablename__ = "diagnosis_sessions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    organization_id: Mapped[str] = mapped_column(
        ForeignKey("organizations.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    goal: Mapped[str] = mapped_column(String(300))
    status: Mapped[str] = mapped_column(String(30), default="in_progress", index=True)
    policy_version: Mapped[str] = mapped_column(String(80), default="diagnosis-scoring.v1")
    current_sequence: Mapped[int] = mapped_column(Integer, default=0)
    result_json: Mapped[str] = mapped_column(Text, default="{}")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    turns: Mapped[list["DiagnosisTurn"]] = relationship(
        cascade="all, delete-orphan", back_populates="session", order_by="DiagnosisTurn.sequence"
    )
    result: Mapped["DiagnosisResult | None"] = relationship(
        cascade="all, delete-orphan", back_populates="session", uselist=False
    )


class DiagnosisTurn(TimestampMixin, Base):
    __tablename__ = "diagnosis_turns"
    __table_args__ = (UniqueConstraint("session_id", "sequence", name="uq_diagnosis_turn_sequence"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    session_id: Mapped[str] = mapped_column(
        ForeignKey("diagnosis_sessions.id", ondelete="CASCADE"), index=True
    )
    sequence: Mapped[int] = mapped_column(Integer)
    role: Mapped[str] = mapped_column(String(30), default="teacher")
    content_hash: Mapped[str] = mapped_column(String(64))
    content_length: Mapped[int] = mapped_column(Integer, default=0)
    request_id: Mapped[str] = mapped_column(String(100), default="")

    session: Mapped[DiagnosisSession] = relationship(back_populates="turns")
    evidence: Mapped[list["DiagnosisEvidenceRecord"]] = relationship(
        cascade="all, delete-orphan", back_populates="turn"
    )


class DiagnosisEvidenceRecord(TimestampMixin, Base):
    __tablename__ = "diagnosis_evidence_records"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    turn_id: Mapped[str] = mapped_column(
        ForeignKey("diagnosis_turns.id", ondelete="CASCADE"), index=True
    )
    evidence_id: Mapped[str] = mapped_column(String(36), index=True)
    indicator_id: Mapped[str] = mapped_column(String(100), index=True)
    anchor: Mapped[int] = mapped_column(Integer)
    anchor_count: Mapped[int] = mapped_column(Integer)
    confidence_microunit: Mapped[int] = mapped_column(Integer)
    quoted_span_hash: Mapped[str] = mapped_column(String(64))

    turn: Mapped[DiagnosisTurn] = relationship(back_populates="evidence")


class DiagnosisResult(TimestampMixin, Base):
    __tablename__ = "diagnosis_results"
    __table_args__ = (UniqueConstraint("session_id", name="uq_diagnosis_result_session"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    session_id: Mapped[str] = mapped_column(
        ForeignKey("diagnosis_sessions.id", ondelete="CASCADE"), index=True
    )
    status: Mapped[str] = mapped_column(String(50), index=True)
    level: Mapped[str | None] = mapped_column(String(30), nullable=True)
    score_microunit: Mapped[int | None] = mapped_column(Integer, nullable=True)
    confidence_microunit: Mapped[int | None] = mapped_column(Integer, nullable=True)
    conflict_microunit: Mapped[int] = mapped_column(Integer, default=0)
    persona_code: Mapped[str | None] = mapped_column(String(80), nullable=True)
    result_json: Mapped[str] = mapped_column(Text, default="{}")

    session: Mapped[DiagnosisSession] = relationship(back_populates="result")


class LearningPath(TimestampMixin, Base):
    __tablename__ = "learning_paths"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    title: Mapped[str] = mapped_column(String(180))
    description: Mapped[str] = mapped_column(Text, default="")
    persona_code: Mapped[str] = mapped_column(String(80), default="general", index=True)
    difficulty: Mapped[str] = mapped_column(String(30), default="starter")
    active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)


class LearningEnrollment(TimestampMixin, Base):
    __tablename__ = "learning_enrollments"
    __table_args__ = (
        UniqueConstraint("organization_id", "user_id", "path_id", name="uq_learning_enrollment"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    organization_id: Mapped[str] = mapped_column(
        ForeignKey("organizations.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    path_id: Mapped[str] = mapped_column(ForeignKey("learning_paths.id", ondelete="CASCADE"), index=True)
    status: Mapped[str] = mapped_column(String(30), default="active", index=True)
    progress_microunit: Mapped[int] = mapped_column(Integer, default=0)


class LearningActivity(TimestampMixin, Base):
    __tablename__ = "learning_activities"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    enrollment_id: Mapped[str] = mapped_column(
        ForeignKey("learning_enrollments.id", ondelete="CASCADE"), index=True
    )
    content_id: Mapped[str] = mapped_column(String(120), index=True)
    activity_type: Mapped[str] = mapped_column(String(40))
    status: Mapped[str] = mapped_column(String(30), default="started")
    score_microunit: Mapped[int | None] = mapped_column(Integer, nullable=True)


class SourceDocument(TimestampMixin, Base):
    __tablename__ = "source_documents"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    organization_id: Mapped[str] = mapped_column(
        ForeignKey("organizations.id", ondelete="CASCADE"), index=True
    )
    owner_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    title: Mapped[str] = mapped_column(String(240))
    mime_type: Mapped[str] = mapped_column(String(120))
    sensitivity: Mapped[str] = mapped_column(String(30), default="internal")
    status: Mapped[str] = mapped_column(String(30), default="uploaded", index=True)

    versions: Mapped[list["DocumentVersion"]] = relationship(
        cascade="all, delete-orphan", back_populates="document", order_by="DocumentVersion.version"
    )


class DocumentVersion(TimestampMixin, Base):
    __tablename__ = "document_versions"
    __table_args__ = (UniqueConstraint("document_id", "version", name="uq_document_version"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    document_id: Mapped[str] = mapped_column(
        ForeignKey("source_documents.id", ondelete="CASCADE"), index=True
    )
    version: Mapped[int] = mapped_column(Integer, default=1)
    storage_key: Mapped[str] = mapped_column(String(255), default="")
    checksum: Mapped[str] = mapped_column(String(64))
    extracted_text: Mapped[str] = mapped_column(Text, default="")
    parser_name: Mapped[str] = mapped_column(String(100), default="pending")
    quality_score: Mapped[float | None] = mapped_column(Float, nullable=True)

    document: Mapped[SourceDocument] = relationship(back_populates="versions")
    nodes: Mapped[list["DocumentNode"]] = relationship(
        cascade="all, delete-orphan", back_populates="version", order_by="DocumentNode.ordinal"
    )


class DocumentNode(TimestampMixin, Base):
    __tablename__ = "document_nodes"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    version_id: Mapped[str] = mapped_column(
        ForeignKey("document_versions.id", ondelete="CASCADE"), index=True
    )
    node_type: Mapped[str] = mapped_column(String(40), default="paragraph")
    ordinal: Mapped[int] = mapped_column(Integer)
    heading: Mapped[str] = mapped_column(String(240), default="")
    content: Mapped[str] = mapped_column(Text)
    locator: Mapped[str] = mapped_column(String(120), default="")
    content_hash: Mapped[str] = mapped_column(String(64))

    version: Mapped[DocumentVersion] = relationship(back_populates="nodes")


class ProcessingJob(TimestampMixin, Base):
    __tablename__ = "processing_jobs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    document_id: Mapped[str] = mapped_column(
        ForeignKey("source_documents.id", ondelete="CASCADE"), index=True
    )
    version_id: Mapped[str] = mapped_column(
        ForeignKey("document_versions.id", ondelete="CASCADE"), index=True
    )
    job_type: Mapped[str] = mapped_column(String(50), default="parse")
    status: Mapped[str] = mapped_column(String(30), default="queued", index=True)
    error_code: Mapped[str] = mapped_column(String(100), default="")
    started_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class LearningReport(TimestampMixin, Base):
    __tablename__ = "learning_reports"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    organization_id: Mapped[str] = mapped_column(
        ForeignKey("organizations.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    report_type: Mapped[str] = mapped_column(String(50), index=True)
    session_id: Mapped[str | None] = mapped_column(
        ForeignKey("diagnosis_sessions.id", ondelete="SET NULL"), nullable=True, index=True
    )
    status: Mapped[str] = mapped_column(String(30), default="ready", index=True)
    snapshot_json: Mapped[str] = mapped_column(Text, default="{}")


class PilotMetric(TimestampMixin, Base):
    __tablename__ = "pilot_metrics"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    organization_id: Mapped[str] = mapped_column(
        ForeignKey("organizations.id", ondelete="CASCADE"), index=True
    )
    metric_name: Mapped[str] = mapped_column(String(100), index=True)
    value_microunit: Mapped[int] = mapped_column(Integer, default=0)
    period: Mapped[str] = mapped_column(String(30), index=True)
