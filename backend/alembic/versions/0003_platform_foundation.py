"""Create the multi-tenant learning-platform foundation tables."""

from alembic import op
from app import models as _models  # noqa: F401
from app import platform_models as _platform_models  # noqa: F401
from app.database import Base

revision = "0003"
down_revision = "0002"


def upgrade() -> None:
    Base.metadata.create_all(bind=op.get_bind())


def downgrade() -> None:
    for table_name in (
        "pilot_metrics",
        "learning_reports",
        "processing_jobs",
        "document_nodes",
        "document_versions",
        "source_documents",
        "learning_activities",
        "learning_enrollments",
        "learning_paths",
        "diagnosis_results",
        "diagnosis_evidence_records",
        "diagnosis_turns",
        "diagnosis_sessions",
        "teacher_profiles",
        "consent_records",
        "organization_memberships",
        "organizations",
    ):
        op.drop_table(table_name, if_exists=True)
