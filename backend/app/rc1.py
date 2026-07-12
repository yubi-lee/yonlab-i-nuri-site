import hashlib
import json
import secrets
from datetime import UTC, datetime, timedelta
from pathlib import Path

from fastapi import APIRouter, Body, Depends, File, HTTPException, Query, Response, UploadFile
from fastapi.responses import Response as BinaryResponse
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from app.config import get_settings
from app.database import get_db
from app.models import (
    FAQ,
    Article,
    AuditLog,
    Category,
    Inquiry,
    Notice,
    PasswordResetToken,
    RefreshSession,
    Resource,
    ResourceAttachment,
    Role,
    Status,
    Tag,
    User,
)
from app.security import (
    admin_user,
    create_access_token,
    current_user,
    hash_password,
)
from app.storage import LocalStorageAdapter, validate_upload

router = APIRouter(prefix="/api/v1")
settings = get_settings()


def utcnow() -> datetime:
    return datetime.now(UTC)

def as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def digest(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def issue_tokens(db: Session, user: User) -> dict:
    refresh = secrets.token_urlsafe(48)
    db.add(
        RefreshSession(
            user_id=user.id,
            token_hash=digest(refresh),
            expires_at=utcnow() + timedelta(days=settings.refresh_token_days),
        )
    )
    db.commit()
    return {
        "access_token": create_access_token(user),
        "refresh_token": refresh,
        "token_type": "bearer",
        "user": user,
    }


def revoke_all(db: Session, user_id: str) -> None:
    now = utcnow()
    sessions = db.scalars(
        select(RefreshSession).where(
            RefreshSession.user_id == user_id, RefreshSession.revoked_at.is_(None)
        )
    ).all()
    for session in sessions:
        session.revoked_at = now
    db.commit()


@router.post("/auth/refresh")
def refresh(data: dict = Body(...), db: Session = Depends(get_db)):
    raw = str(data.get("refresh_token", ""))
    session = db.scalar(select(RefreshSession).where(RefreshSession.token_hash == digest(raw)))
    if not session or as_utc(session.expires_at) <= utcnow():
        raise HTTPException(401, "Invalid refresh token")
    if session.revoked_at:
        revoke_all(db, session.user_id)
        raise HTTPException(401, "Refresh token reuse detected")
    session.revoked_at = utcnow()
    user = db.get(User, session.user_id)
    if not user or not user.is_active:
        raise HTTPException(401, "Inactive user")
    return issue_tokens(db, user)


@router.post("/auth/logout", status_code=204)
def logout(data: dict = Body(...), db: Session = Depends(get_db)):
    session = db.scalar(
        select(RefreshSession).where(
            RefreshSession.token_hash == digest(str(data.get("refresh_token", "")))
        )
    )
    if session and not session.revoked_at:
        session.revoked_at = utcnow()
        db.commit()
    return Response(status_code=204)


@router.post("/auth/logout-all", status_code=204)
def logout_all(user: User = Depends(current_user), db: Session = Depends(get_db)):
    revoke_all(db, user.id)
    return Response(status_code=204)


@router.post("/auth/password-reset/request", status_code=202)
def request_reset(data: dict = Body(...), db: Session = Depends(get_db)):
    user = db.scalar(
        select(User).where(func.lower(User.email) == str(data.get("email", "")).lower())
    )
    result = {"message": "If the account exists, reset instructions were created."}
    if not user:
        return result
    raw = secrets.token_urlsafe(32)
    db.add(
        PasswordResetToken(
            user_id=user.id, token_hash=digest(raw), expires_at=utcnow() + timedelta(minutes=30)
        )
    )
    db.commit()
    if settings.environment == "development":
        result["development_token"] = raw
    return result


@router.post("/auth/password-reset/confirm", status_code=204)
def confirm_reset(data: dict = Body(...), db: Session = Depends(get_db)):
    token = db.scalar(
        select(PasswordResetToken).where(
            PasswordResetToken.token_hash == digest(str(data.get("token", "")))
        )
    )
    if not token or token.used_at or as_utc(token.expires_at) <= utcnow():
        raise HTTPException(400, "Invalid or expired reset token")
    password = str(data.get("password", ""))
    if len(password) < 10:
        raise HTTPException(422, "Password must be at least 10 characters")
    user = db.get(User, token.user_id)
    user.password_hash = hash_password(password)
    token.used_at = utcnow()
    revoke_all(db, user.id)
    db.commit()
    return Response(status_code=204)


def audit(
    db: Session,
    actor: User,
    action: str,
    entity: str,
    entity_id: str | None,
    detail: dict | None = None,
) -> None:
    db.add(
        AuditLog(
            actor_id=actor.id,
            action=action,
            entity_type=entity,
            entity_id=entity_id,
            detail=json.dumps(detail or {}, ensure_ascii=False),
        )
    )


def paginate(stmt, db: Session, page: int, page_size: int):
    total = db.scalar(select(func.count()).select_from(stmt.order_by(None).subquery())) or 0
    return db.scalars(stmt.offset((page - 1) * page_size).limit(page_size)).all(), total


def simple_dict(row) -> dict:
    output = {}
    for key in (
        "id",
        "name",
        "slug",
        "title",
        "body",
        "summary",
        "question",
        "answer",
        "order",
        "status",
        "email",
        "role",
        "is_active",
        "subject",
        "message",
        "admin_note",
    ):
        if hasattr(row, key):
            value = getattr(row, key)
            output[key] = value.value if hasattr(value, "value") else value
    return output


SIMPLE = {
    "categories": (Category, ("name", "slug"), "name"),
    "tags": (Tag, ("name", "slug"), "name"),
    "notices": (Notice, ("title", "body", "status"), "title"),
    "articles": (Article, ("title", "summary", "body", "status"), "title"),
    "faqs": (FAQ, ("question", "answer", "order", "status"), "question"),
}


def entity_name(kind: str) -> str:
    return {
        "categories": "category",
        "notices": "notice",
        "articles": "article",
        "faqs": "faq",
        "resources": "resource",
        "tags": "tag",
    }.get(kind, kind.rstrip("s"))


@router.get("/admin/audit-logs")
def audit_logs_explicit(_: User = Depends(admin_user), db: Session = Depends(get_db)):
    rows = db.scalars(select(AuditLog).order_by(AuditLog.created_at.desc()).limit(200)).all()
    return {
        "items": [
            {
                "id": x.id,
                "action": x.action,
                "entity_type": x.entity_type,
                "entity_id": x.entity_id,
                "detail": x.detail,
            }
            for x in rows
        ],
        "total": len(rows),
    }


@router.get("/admin/{kind}")
def admin_list(
    kind: str,
    q: str = "",
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    _: User = Depends(admin_user),
    db: Session = Depends(get_db),
):
    if kind == "users":
        stmt = select(User)
        if q:
            stmt = stmt.where(or_(User.email.ilike(f"%{q}%"), User.name.ilike(f"%{q}%")))
        rows, total = paginate(stmt.order_by(User.created_at.desc()), db, page, page_size)
        return {
            "items": [simple_dict(x) for x in rows],
            "total": total,
            "page": page,
            "page_size": page_size,
        }
    if kind == "inquiries":
        stmt = select(Inquiry)
        if q:
            stmt = stmt.where(or_(Inquiry.email.ilike(f"%{q}%"), Inquiry.subject.ilike(f"%{q}%")))
        rows, total = paginate(stmt.order_by(Inquiry.created_at.desc()), db, page, page_size)
        return {
            "items": [simple_dict(x) for x in rows],
            "total": total,
            "page": page,
            "page_size": page_size,
        }
    if kind == "resources":
        stmt = select(Resource).options(
            selectinload(Resource.category), selectinload(Resource.tags)
        )
        if q:
            stmt = stmt.where(Resource.title.ilike(f"%{q}%"))
        rows, total = paginate(stmt.order_by(Resource.created_at.desc()), db, page, page_size)
        return {
            "items": [
                simple_dict(x) | {"category_id": x.category_id, "tag_ids": [t.id for t in x.tags]}
                for x in rows
            ],
            "total": total,
            "page": page,
            "page_size": page_size,
        }
    if kind not in SIMPLE:
        raise HTTPException(404, "Unknown entity")
    model, _, search_field = SIMPLE[kind]
    stmt = select(model)
    if q:
        stmt = stmt.where(getattr(model, search_field).ilike(f"%{q}%"))
    rows, total = paginate(stmt.order_by(model.created_at.desc()), db, page, page_size)
    return {
        "items": [simple_dict(x) for x in rows],
        "total": total,
        "page": page,
        "page_size": page_size,
    }


@router.post("/admin/{kind}", status_code=201)
def admin_create(
    kind: str,
    data: dict = Body(...),
    admin: User = Depends(admin_user),
    db: Session = Depends(get_db),
):
    if kind not in SIMPLE:
        raise HTTPException(404, "Unknown entity")
    model, fields, _ = SIMPLE[kind]
    values = {field: data[field] for field in fields if field in data}
    if "status" in values:
        values["status"] = Status(values["status"])
        if values["status"] == Status.published and hasattr(model, "published_at"):
            values["published_at"] = utcnow()
    row = model(**values)
    db.add(row)
    try:
        db.flush()
        audit(db, admin, f"{entity_name(kind)}.create", entity_name(kind), row.id, values)
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(409, "Duplicate value") from exc
    return simple_dict(row)


@router.patch("/admin/{kind}/{entity_id}")
def admin_update(
    kind: str,
    entity_id: str,
    data: dict = Body(...),
    admin: User = Depends(admin_user),
    db: Session = Depends(get_db),
):
    if kind == "users":
        row = db.get(User, entity_id)
        if not row:
            raise HTTPException(404, "User not found")
        if data.get("role") == "user" and row.role == Role.admin:
            active_admins = (
                db.scalar(
                    select(func.count(User.id)).where(
                        User.role == Role.admin, User.is_active.is_(True)
                    )
                )
                or 0
            )
            if active_admins <= 1:
                raise HTTPException(409, "Cannot remove the last administrator")
        if "role" in data:
            row.role = Role(data["role"])
        if "is_active" in data:
            row.is_active = bool(data["is_active"])
        audit(db, admin, "user.update", "user", row.id, data)
        db.commit()
        return simple_dict(row)
    if kind == "inquiries":
        row = db.get(Inquiry, entity_id)
        if not row:
            raise HTTPException(404, "Inquiry not found")
        for field in ("status", "admin_note"):
            if field in data:
                setattr(row, field, data[field])
        audit(db, admin, "inquiry.update", "inquiry", row.id, data)
        db.commit()
        return simple_dict(row)
    if kind == "resources":
        row = db.scalar(
            select(Resource).options(selectinload(Resource.tags)).where(Resource.id == entity_id)
        )
        if not row:
            raise HTTPException(404, "Resource not found")
        for field in ("title", "summary", "body", "audience", "resource_type", "featured"):
            if field in data:
                setattr(row, field, data[field])
        if "status" in data:
            row.status = Status(data["status"])
            row.published_at = utcnow() if row.status == Status.published else None
        if "category_id" in data:
            row.category_id = data["category_id"]
        if "tag_ids" in data:
            row.tags = list(db.scalars(select(Tag).where(Tag.id.in_(data["tag_ids"]))).all())
        audit(db, admin, "resource.update", "resource", row.id, data)
        db.commit()
        return simple_dict(row)
    if kind not in SIMPLE:
        raise HTTPException(404, "Unknown entity")
    model, fields, _ = SIMPLE[kind]
    row = db.get(model, entity_id)
    if not row:
        raise HTTPException(404, "Entity not found")
    for field in fields:
        if field in data:
            setattr(row, field, Status(data[field]) if field == "status" else data[field])
    audit(db, admin, f"{entity_name(kind)}.update", entity_name(kind), row.id, data)
    db.commit()
    return simple_dict(row)


@router.delete("/admin/{kind}/{entity_id}", status_code=204)
def admin_delete(
    kind: str, entity_id: str, admin: User = Depends(admin_user), db: Session = Depends(get_db)
):
    if kind in ("users", "inquiries"):
        raise HTTPException(405, "Use safe status update")
    model = Resource if kind == "resources" else SIMPLE.get(kind, (None,))[0]
    if not model:
        raise HTTPException(404, "Unknown entity")
    row = db.get(model, entity_id)
    if not row:
        raise HTTPException(404, "Entity not found")
    if hasattr(row, "status"):
        row.status = Status.archived
    else:
        db.delete(row)
    audit(db, admin, f"{entity_name(kind)}.delete", entity_name(kind), entity_id)
    db.commit()
    return Response(status_code=204)


@router.get("/admin/audit-logs")
def audit_logs(_: User = Depends(admin_user), db: Session = Depends(get_db)):
    rows = db.scalars(select(AuditLog).order_by(AuditLog.created_at.desc()).limit(200)).all()
    return {
        "items": [
            {
                "id": x.id,
                "action": x.action,
                "entity_type": x.entity_type,
                "entity_id": x.entity_id,
                "detail": x.detail,
            }
            for x in rows
        ],
        "total": len(rows),
    }


def storage() -> LocalStorageAdapter:
    return LocalStorageAdapter(Path(settings.upload_dir))


@router.post("/admin/resources/{resource_id}/attachments", status_code=201)
async def upload_attachment(
    resource_id: str,
    file: UploadFile = File(...),
    admin: User = Depends(admin_user),
    db: Session = Depends(get_db),
):
    resource = db.get(Resource, resource_id)
    if not resource:
        raise HTTPException(404, "Resource not found")
    content = await file.read()
    original, stored = validate_upload(file, content)
    adapter = storage()
    adapter.save(stored, content)
    item = ResourceAttachment(
        resource_id=resource_id,
        original_name=original,
        stored_name=stored,
        mime_type=file.content_type or "application/octet-stream",
        size=len(content),
    )
    db.add(item)
    try:
        db.flush()
        audit(db, admin, "attachment.create", "resource_attachment", item.id, {"name": original})
        db.commit()
    except Exception:
        db.rollback()
        adapter.delete(stored)
        raise
    return {
        "id": item.id,
        "original_name": item.original_name,
        "mime_type": item.mime_type,
        "size": item.size,
    }


@router.get("/resources/{resource_id}/attachments")
def list_attachments(resource_id: str, db: Session = Depends(get_db)):
    resource = db.get(Resource, resource_id)
    if not resource or resource.status != Status.published:
        raise HTTPException(404, "Resource not found")
    rows = db.scalars(
        select(ResourceAttachment).where(ResourceAttachment.resource_id == resource_id)
    ).all()
    return [
        {"id": x.id, "original_name": x.original_name, "mime_type": x.mime_type, "size": x.size}
        for x in rows
    ]


@router.get("/resources/{resource_id}/attachments/{attachment_id}/download")
def download_attachment(resource_id: str, attachment_id: str, db: Session = Depends(get_db)):
    item = db.get(ResourceAttachment, attachment_id)
    resource = db.get(Resource, resource_id)
    if (
        not item
        or item.resource_id != resource_id
        or not resource
        or resource.status != Status.published
    ):
        raise HTTPException(404, "Attachment not found")
    try:
        content = storage().read(item.stored_name)
    except FileNotFoundError as exc:
        raise HTTPException(404, "Stored file not found") from exc
    return BinaryResponse(
        content=content,
        media_type=item.mime_type,
        headers={"Content-Disposition": f'attachment; filename="{item.original_name}"'},
    )


@router.delete("/admin/resources/{resource_id}/attachments/{attachment_id}", status_code=204)
def delete_attachment(
    resource_id: str,
    attachment_id: str,
    admin: User = Depends(admin_user),
    db: Session = Depends(get_db),
):
    item = db.get(ResourceAttachment, attachment_id)
    if not item or item.resource_id != resource_id:
        raise HTTPException(404, "Attachment not found")
    storage().delete(item.stored_name)
    db.delete(item)
    audit(db, admin, "attachment.delete", "resource_attachment", item.id)
    db.commit()
    return Response(status_code=204)
