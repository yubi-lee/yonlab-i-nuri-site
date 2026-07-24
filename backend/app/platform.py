import hashlib
import json
import re
import uuid
from datetime import UTC, datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import StreamingResponse
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.diagnosis import score_dimension
from app.document_ai import (
    DocumentProcessingError,
    checksum,
    extract_text,
    lexical_score,
    node_hash,
    to_nodes,
)
from app.models import User
from app.platform_models import (
    ConsentRecord,
    DiagnosisEvidenceRecord,
    DiagnosisResult,
    DiagnosisSession,
    DiagnosisTurn,
    DocumentNode,
    DocumentVersion,
    LearningActivity,
    LearningEnrollment,
    LearningPath,
    LearningReport,
    Organization,
    OrganizationMembership,
    PilotMetric,
    ProcessingJob,
    SourceDocument,
    TeacherProfile,
)
from app.platform_schemas import (
    ActivityCreate,
    ConsentCreate,
    ConsentOut,
    DiagnosisSessionCreate,
    DiagnosisSessionOut,
    DiagnosisTurnCreate,
    DiagnosisTurnOut,
    DocumentCreate,
    DocumentOut,
    EnrollmentCreate,
    EnrollmentOut,
    KnowledgeSearchResult,
    LearningPathOut,
    MembershipOut,
    OrganizationCreate,
    OrganizationMemberCreate,
    OrganizationOut,
    PilotMetricCreate,
    ReportCreate,
    ReportOut,
    TeacherProfileOut,
    TeacherProfileWrite,
)
from app.security import admin_user, current_user

router = APIRouter(prefix="/api/v1")


def utcnow() -> datetime:
    return datetime.now(UTC)


def slug_for(name: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return f"{normalized or 'organization'}-{uuid.uuid4().hex[:8]}"


def membership_for(db: Session, organization_id: str, user_id: str) -> OrganizationMembership | None:
    return db.scalar(
        select(OrganizationMembership).where(
            OrganizationMembership.organization_id == organization_id,
            OrganizationMembership.user_id == user_id,
            OrganizationMembership.status == "active",
        )
    )


def require_membership(db: Session, organization_id: str, user: User) -> OrganizationMembership:
    membership = membership_for(db, organization_id, user.id)
    if not membership:
        raise HTTPException(status_code=403, detail="Organization membership required")
    return membership


def require_manager(db: Session, organization_id: str, user: User) -> OrganizationMembership:
    membership = require_membership(db, organization_id, user)
    if membership.role not in {"owner", "manager"} and user.role != "admin":
        raise HTTPException(status_code=403, detail="Organization manager role required")
    return membership


def ensure_default_paths(db: Session) -> None:
    if db.scalar(select(func.count(LearningPath.id))) != 0:
        return
    db.add_all(
        [
            LearningPath(
                title="AI 수업 설계 기초",
                description="교사의 목표와 현장 제약을 반영해 안전한 AI 활동을 설계합니다.",
                persona_code="general",
                difficulty="starter",
            ),
            LearningPath(
                title="근거 기반 AI 활용",
                description="문서 근거와 인용을 확인하며 교육 자료를 활용합니다.",
                persona_code="P-01",
                difficulty="intermediate",
            ),
        ]
    )
    db.commit()


def organization_out(item: Organization) -> dict:
    return {
        "id": item.id,
        "name": item.name,
        "slug": item.slug,
        "owner_id": item.owner_id,
        "status": item.status,
    }


@router.post("/organizations", response_model=OrganizationOut, status_code=201, tags=["organizations"])
def create_organization(
    data: OrganizationCreate, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    organization = Organization(name=data.name, slug=slug_for(data.name), owner_id=user.id)
    db.add(organization)
    db.flush()
    db.add(
        OrganizationMembership(
            organization_id=organization.id, user_id=user.id, role="owner", status="active"
        )
    )
    db.commit()
    db.refresh(organization)
    return organization_out(organization)


@router.get("/organizations", response_model=list[OrganizationOut], tags=["organizations"])
def list_organizations(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.scalars(
        select(Organization)
        .join(OrganizationMembership, OrganizationMembership.organization_id == Organization.id)
        .where(OrganizationMembership.user_id == user.id, OrganizationMembership.status == "active")
        .order_by(Organization.created_at.desc())
    ).all()
    return [organization_out(row) for row in rows]


@router.get("/organizations/{organization_id}/members", response_model=list[MembershipOut], tags=["organizations"])
def list_members(
    organization_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_membership(db, organization_id, user)
    return db.scalars(
        select(OrganizationMembership).where(
            OrganizationMembership.organization_id == organization_id,
            OrganizationMembership.status == "active",
        )
    ).all()


@router.post("/organizations/{organization_id}/members", response_model=MembershipOut, status_code=201, tags=["organizations"])
def add_member(
    organization_id: str,
    data: OrganizationMemberCreate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    require_manager(db, organization_id, user)
    member = db.scalar(select(User).where(func.lower(User.email) == data.email.lower()))
    if not member:
        raise HTTPException(status_code=404, detail="User not found; registration is required first")
    if membership_for(db, organization_id, member.id):
        raise HTTPException(status_code=409, detail="User is already a member")
    membership = OrganizationMembership(
        organization_id=organization_id, user_id=member.id, role=data.role, status="active"
    )
    db.add(membership)
    db.commit()
    db.refresh(membership)
    return membership


@router.post("/organizations/{organization_id}/consents", response_model=ConsentOut, tags=["privacy"])
def record_consent(
    organization_id: str,
    data: ConsentCreate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    require_membership(db, organization_id, user)
    existing = db.scalar(
        select(ConsentRecord).where(
            ConsentRecord.organization_id == organization_id,
            ConsentRecord.user_id == user.id,
            ConsentRecord.consent_type == data.consent_type,
            ConsentRecord.version == data.version,
        )
    )
    if existing:
        existing.granted = data.granted
        existing.granted_at = utcnow() if data.granted else existing.granted_at
        existing.revoked_at = None if data.granted else utcnow()
        db.commit()
        db.refresh(existing)
        return existing
    item = ConsentRecord(
        organization_id=organization_id,
        user_id=user.id,
        consent_type=data.consent_type,
        version=data.version,
        granted=data.granted,
        granted_at=utcnow() if data.granted else None,
        revoked_at=None if data.granted else utcnow(),
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@router.put("/me/teacher-profile", response_model=TeacherProfileOut, tags=["members"])
def save_teacher_profile(
    data: TeacherProfileWrite, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_membership(db, data.organization_id, user)
    item = db.scalar(
        select(TeacherProfile).where(
            TeacherProfile.organization_id == data.organization_id, TeacherProfile.user_id == user.id
        )
    )
    if not item:
        item = TeacherProfile(organization_id=data.organization_id, user_id=user.id)
        db.add(item)
    item.years_experience = data.years_experience
    item.specialty = data.specialty
    item.context_json = json.dumps(data.context, ensure_ascii=False, sort_keys=True)
    db.commit()
    db.refresh(item)
    return {
        "id": item.id,
        "organization_id": item.organization_id,
        "user_id": item.user_id,
        "years_experience": item.years_experience,
        "specialty": item.specialty,
        "context": data.context,
    }


def session_payload(db: Session, session: DiagnosisSession) -> dict:
    turns = db.scalars(
        select(DiagnosisTurn).where(DiagnosisTurn.session_id == session.id).order_by(DiagnosisTurn.sequence)
    ).all()
    result = db.scalar(select(DiagnosisResult).where(DiagnosisResult.session_id == session.id))
    return {
        "id": session.id,
        "organization_id": session.organization_id,
        "goal": session.goal,
        "status": session.status,
        "policy_version": session.policy_version,
        "current_sequence": session.current_sequence,
        "turns": [
            {
                "id": turn.id,
                "sequence": turn.sequence,
                "role": turn.role,
                "content_length": turn.content_length,
                "evidence_count": db.scalar(
                    select(func.count(DiagnosisEvidenceRecord.id)).where(
                        DiagnosisEvidenceRecord.turn_id == turn.id
                    )
                )
                or 0,
                "created_at": turn.created_at,
            }
            for turn in turns
        ],
        "result": json.loads(result.result_json) if result else None,
    }


def get_session(db: Session, session_id: str, user: User) -> DiagnosisSession:
    session = db.get(DiagnosisSession, session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Diagnosis session not found")
    require_membership(db, session.organization_id, user)
    if session.user_id != user.id and user.role != "admin":
        raise HTTPException(status_code=403, detail="Diagnosis session access denied")
    return session


@router.post("/diagnosis/sessions", response_model=DiagnosisSessionOut, status_code=201, tags=["diagnosis"])
def create_diagnosis_session(
    data: DiagnosisSessionCreate, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_membership(db, data.organization_id, user)
    item = DiagnosisSession(organization_id=data.organization_id, user_id=user.id, goal=data.goal)
    db.add(item)
    db.commit()
    db.refresh(item)
    return session_payload(db, item)


@router.get("/diagnosis/sessions/{session_id}", response_model=DiagnosisSessionOut, tags=["diagnosis"])
def get_diagnosis_session(
    session_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    return session_payload(db, get_session(db, session_id, user))


@router.post("/diagnosis/sessions/{session_id}/turns", response_model=DiagnosisTurnOut, status_code=201, tags=["diagnosis"])
def add_diagnosis_turn(
    session_id: str,
    data: DiagnosisTurnCreate,
    request: Request,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    session = get_session(db, session_id, user)
    if session.status != "in_progress":
        raise HTTPException(status_code=409, detail="Diagnosis session is not writable")
    if data.evidence and len({item.anchor_count for item in data.evidence}) != 1:
        raise HTTPException(status_code=422, detail="Evidence anchor_count must be consistent")
    session.current_sequence += 1
    turn = DiagnosisTurn(
        session_id=session.id,
        sequence=session.current_sequence,
        role="teacher",
        content_hash=hashlib.sha256(data.content.encode("utf-8")).hexdigest(),
        content_length=len(data.content),
        request_id=request.state.request_id,
    )
    db.add(turn)
    db.flush()
    for evidence in data.evidence:
        confidence = int(Decimal(evidence.confidence_decimal) * 1_000_000)
        db.add(
            DiagnosisEvidenceRecord(
                turn_id=turn.id,
                evidence_id=str(uuid.uuid4()),
                indicator_id=evidence.indicator_id,
                anchor=evidence.anchor,
                anchor_count=evidence.anchor_count,
                confidence_microunit=confidence,
                quoted_span_hash=hashlib.sha256(evidence.quoted_span.encode("utf-8")).hexdigest(),
            )
        )
    db.commit()
    db.refresh(turn)
    return {
        "id": turn.id,
        "sequence": turn.sequence,
        "role": turn.role,
        "content_length": turn.content_length,
        "evidence_count": len(data.evidence),
        "created_at": turn.created_at,
    }


@router.get("/diagnosis/sessions/{session_id}/events", tags=["diagnosis"])
def diagnosis_events(session_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    session = get_session(db, session_id, user)
    payload = session_payload(db, session)

    def stream():
        yield f"event: session\ndata: {json.dumps(payload, ensure_ascii=False, default=str)}\n\n"
        yield "event: end\ndata: {}\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


@router.post("/diagnosis/sessions/{session_id}/complete", response_model=DiagnosisSessionOut, tags=["diagnosis"])
def complete_diagnosis_session(
    session_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    session = get_session(db, session_id, user)
    if session.status == "completed":
        return session_payload(db, session)
    rows = db.execute(
        select(DiagnosisEvidenceRecord, DiagnosisTurn)
        .join(DiagnosisTurn, DiagnosisTurn.id == DiagnosisEvidenceRecord.turn_id)
        .where(DiagnosisTurn.session_id == session.id)
    ).all()
    anchor_count = rows[0][0].anchor_count if rows else 5
    evidence = [
        {
            "evidence_id": item.evidence_id,
            "turn_id": turn.id,
            "turn_sequence": turn.sequence,
            "indicator_id": item.indicator_id,
            "anchor": item.anchor,
            "anchor_count": item.anchor_count,
            "confidence_decimal": f"{item.confidence_microunit / 1_000_000:.6f}",
            "span_start_codepoint": 0,
            "span_end_codepoint": 1,
            "quoted_span": "[redacted]",
            "schema_version": "evidence.v1",
        }
        for item, turn in rows
    ]
    score = score_dimension({"anchor_count": anchor_count, "evidence": evidence})
    result_payload = {
        "status": score.status,
        "dimension_score_microunit": score.dimension_score_microunit,
        "overall_score_microunit": score.overall_score_microunit,
        "confidence_microunit": score.confidence_microunit,
        "conflict_microunit": score.conflict_microunit,
        "selected_evidence_id": score.selected_evidence_id,
    }
    session.status = "completed"
    session.completed_at = utcnow()
    session.result_json = json.dumps(result_payload, ensure_ascii=False)
    db.add(
        DiagnosisResult(
            session_id=session.id,
            status=score.status,
            score_microunit=score.overall_score_microunit,
            confidence_microunit=score.confidence_microunit,
            conflict_microunit=score.conflict_microunit,
            result_json=json.dumps(result_payload, ensure_ascii=False),
        )
    )
    db.commit()
    return session_payload(db, session)


@router.get("/learning/paths", response_model=dict, tags=["learning"])
def learning_paths(db: Session = Depends(get_db)):
    ensure_default_paths(db)
    rows = db.scalars(select(LearningPath).where(LearningPath.active.is_(True)).order_by(LearningPath.created_at)).all()
    return {"items": [LearningPathOut.model_validate(row).model_dump() for row in rows], "total": len(rows)}


@router.post("/learning/enrollments", response_model=EnrollmentOut, status_code=201, tags=["learning"])
def enroll(
    data: EnrollmentCreate, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_membership(db, data.organization_id, user)
    if not db.get(LearningPath, data.path_id):
        raise HTTPException(status_code=404, detail="Learning path not found")
    existing = db.scalar(
        select(LearningEnrollment).where(
            LearningEnrollment.organization_id == data.organization_id,
            LearningEnrollment.user_id == user.id,
            LearningEnrollment.path_id == data.path_id,
        )
    )
    if existing:
        return existing
    item = LearningEnrollment(
        organization_id=data.organization_id, user_id=user.id, path_id=data.path_id
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@router.post("/learning/enrollments/{enrollment_id}/activities", status_code=201, tags=["learning"])
def add_activity(
    enrollment_id: str,
    data: ActivityCreate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    enrollment = db.get(LearningEnrollment, enrollment_id)
    if not enrollment or enrollment.user_id != user.id:
        raise HTTPException(status_code=404, detail="Learning enrollment not found")
    activity = LearningActivity(enrollment_id=enrollment.id, **data.model_dump())
    db.add(activity)
    if data.status == "completed":
        enrollment.progress_microunit = min(1_000_000, enrollment.progress_microunit + 250_000)
    db.commit()
    db.refresh(activity)
    return {
        "id": activity.id,
        "enrollment_id": enrollment.id,
        "content_id": activity.content_id,
        "status": activity.status,
        "progress_microunit": enrollment.progress_microunit,
    }


@router.get("/me/learning", tags=["learning"])
def my_learning(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.scalars(
        select(LearningEnrollment).where(LearningEnrollment.user_id == user.id).order_by(LearningEnrollment.created_at.desc())
    ).all()
    return {
        "items": [
            {
                "id": row.id,
                "organization_id": row.organization_id,
                "path_id": row.path_id,
                "status": row.status,
                "progress_microunit": row.progress_microunit,
            }
            for row in rows
        ],
        "total": len(rows),
    }


def document_out(item: SourceDocument) -> dict:
    latest = max(item.versions, key=lambda version: version.version, default=None)
    return {
        "id": item.id,
        "organization_id": item.organization_id,
        "title": item.title,
        "mime_type": item.mime_type,
        "sensitivity": item.sensitivity,
        "status": item.status,
        "latest_version_id": latest.id if latest else None,
    }


@router.post("/documents", response_model=DocumentOut, status_code=201, tags=["documents"])
def create_document(
    data: DocumentCreate, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_membership(db, data.organization_id, user)
    raw = data.content.encode("utf-8")
    document = SourceDocument(
        organization_id=data.organization_id,
        owner_id=user.id,
        title=data.title,
        mime_type=data.mime_type,
        sensitivity=data.sensitivity,
    )
    db.add(document)
    db.flush()
    version = DocumentVersion(
        document_id=document.id,
        version=1,
        checksum=checksum(raw),
        extracted_text=data.content,
    )
    document.versions.append(version)
    db.commit()
    db.refresh(document)
    return document_out(document)


@router.get("/documents", tags=["documents"])
def list_documents(
    organization_id: str = Query(...), user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_membership(db, organization_id, user)
    rows = db.scalars(
        select(SourceDocument).where(SourceDocument.organization_id == organization_id).order_by(SourceDocument.created_at.desc())
    ).all()
    return {"items": [document_out(row) for row in rows], "total": len(rows)}


@router.post("/documents/{document_id}/process", tags=["documents"])
def process_document(document_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    document = db.get(SourceDocument, document_id)
    if not document:
        raise HTTPException(status_code=404, detail="Document not found")
    require_membership(db, document.organization_id, user)
    version = db.scalar(
        select(DocumentVersion).where(DocumentVersion.document_id == document.id).order_by(DocumentVersion.version.desc())
    )
    if not version:
        raise HTTPException(status_code=409, detail="Document version not found")
    job = ProcessingJob(document_id=document.id, version_id=version.id, status="running", started_at=utcnow())
    db.add(job)
    db.flush()
    try:
        raw = version.extracted_text.encode("utf-8")
        text, parser_name = extract_text(raw, document.mime_type, document.title)
        parsed_nodes = to_nodes(text)
        db.execute(delete(DocumentNode).where(DocumentNode.version_id == version.id))
        for node in parsed_nodes:
            db.add(
                DocumentNode(
                    version_id=version.id,
                    node_type=node.node_type,
                    ordinal=node.ordinal,
                    heading=node.heading,
                    content=node.content,
                    locator=node.locator,
                    content_hash=node_hash(node.content),
                )
            )
        version.extracted_text = text
        version.parser_name = parser_name
        version.quality_score = 1.0 if parsed_nodes else 0.0
        document.status = "processed"
        job.status = "completed"
        job.finished_at = utcnow()
        db.commit()
        return {"id": job.id, "document_id": document.id, "status": job.status, "nodes": len(parsed_nodes)}
    except DocumentProcessingError as exc:
        document.status = "failed"
        job.status = "failed"
        job.error_code = exc.code
        job.finished_at = utcnow()
        db.commit()
        return {"id": job.id, "document_id": document.id, "status": job.status, "error_code": job.error_code}


@router.get("/documents/{document_id}/jobs", tags=["documents"])
def document_jobs(document_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    document = db.get(SourceDocument, document_id)
    if not document:
        raise HTTPException(status_code=404, detail="Document not found")
    require_membership(db, document.organization_id, user)
    return {"items": db.scalars(select(ProcessingJob).where(ProcessingJob.document_id == document_id)).all()}


@router.get("/knowledge/search", response_model=dict, tags=["knowledge"])
def knowledge_search(
    organization_id: str,
    q: str = Query(min_length=1, max_length=200),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    require_membership(db, organization_id, user)
    rows = db.execute(
        select(DocumentNode, DocumentVersion, SourceDocument)
        .join(DocumentVersion, DocumentVersion.id == DocumentNode.version_id)
        .join(SourceDocument, SourceDocument.id == DocumentVersion.document_id)
        .where(SourceDocument.organization_id == organization_id, SourceDocument.status == "processed")
    ).all()
    ranked = sorted(
        ((lexical_score(q, node.content), node, document) for node, _version, document in rows),
        key=lambda item: (-item[0], item[1].ordinal),
    )
    items = [
        KnowledgeSearchResult(
            node_id=node.id,
            document_id=document.id,
            document_title=document.title,
            content=node.content,
            score_microunit=score,
            citations=[
                {"document_id": document.id, "node_id": node.id, "locator": node.locator, "grounded": True}
            ],
        ).model_dump()
        for score, node, document in ranked[:10]
        if score > 0
    ]
    return {"query": q, "items": items, "total": len(items), "no_answer": not items}


def report_snapshot(db: Session, data: ReportCreate, user: User) -> dict:
    snapshot: dict = {"generated_at": utcnow().isoformat(), "report_type": data.report_type}
    if data.session_id:
        session = db.get(DiagnosisSession, data.session_id)
        if not session or session.organization_id != data.organization_id or session.user_id != user.id:
            raise HTTPException(status_code=404, detail="Diagnosis session not found")
        result = db.scalar(select(DiagnosisResult).where(DiagnosisResult.session_id == session.id))
        snapshot["diagnosis"] = {
            "session_id": session.id,
            "status": session.status,
            "result": json.loads(result.result_json) if result else None,
            "turn_count": session.current_sequence,
        }
    if data.report_type == "learning":
        snapshot["enrollments"] = db.scalar(
            select(func.count(LearningEnrollment.id)).where(
                LearningEnrollment.organization_id == data.organization_id,
                LearningEnrollment.user_id == user.id,
            )
        ) or 0
    if data.report_type == "pilot":
        snapshot["metrics"] = db.scalar(
            select(func.count(PilotMetric.id)).where(PilotMetric.organization_id == data.organization_id)
        ) or 0
    return snapshot


@router.post("/reports", response_model=ReportOut, status_code=201, tags=["reports"])
def create_report(
    data: ReportCreate, user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_membership(db, data.organization_id, user)
    item = LearningReport(
        organization_id=data.organization_id,
        user_id=user.id,
        report_type=data.report_type,
        session_id=data.session_id,
        snapshot_json=json.dumps(report_snapshot(db, data, user), ensure_ascii=False),
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return {**item.__dict__, "snapshot": json.loads(item.snapshot_json)}


@router.get("/reports", response_model=dict, tags=["reports"])
def list_reports(
    organization_id: str = Query(...), user: User = Depends(current_user), db: Session = Depends(get_db)
):
    require_membership(db, organization_id, user)
    rows = db.scalars(
        select(LearningReport).where(
            LearningReport.organization_id == organization_id, LearningReport.user_id == user.id
        ).order_by(LearningReport.created_at.desc())
    ).all()
    return {
        "items": [
            {
                "id": row.id,
                "organization_id": row.organization_id,
                "user_id": row.user_id,
                "report_type": row.report_type,
                "status": row.status,
                "snapshot": json.loads(row.snapshot_json),
            }
            for row in rows
        ],
        "total": len(rows),
    }


@router.post("/admin/pilot-metrics", status_code=201, tags=["admin"])
def create_pilot_metric(
    data: PilotMetricCreate, admin: User = Depends(admin_user), db: Session = Depends(get_db)
):
    require_membership(db, data.organization_id, admin)
    item = PilotMetric(**data.model_dump())
    db.add(item)
    db.commit()
    db.refresh(item)
    return {"id": item.id, "metric_name": item.metric_name, "value_microunit": item.value_microunit, "period": item.period}


@router.get("/admin/platform-metrics", tags=["admin"])
def platform_metrics(_: User = Depends(admin_user), db: Session = Depends(get_db)):
    return {
        "organizations": db.scalar(select(func.count(Organization.id))) or 0,
        "memberships": db.scalar(select(func.count(OrganizationMembership.id))) or 0,
        "diagnosis_sessions": db.scalar(select(func.count(DiagnosisSession.id))) or 0,
        "completed_diagnoses": db.scalar(
            select(func.count(DiagnosisSession.id)).where(DiagnosisSession.status == "completed")
        )
        or 0,
        "documents": db.scalar(select(func.count(SourceDocument.id))) or 0,
        "processed_documents": db.scalar(
            select(func.count(SourceDocument.id)).where(SourceDocument.status == "processed")
        )
        or 0,
        "reports": db.scalar(select(func.count(LearningReport.id))) or 0,
    }
