import json
import uuid
from contextlib import asynccontextmanager
from dataclasses import asdict
from datetime import UTC, datetime

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import func, or_, select, text
from sqlalchemy.orm import Session, selectinload

from app.config import get_settings
from app.database import Base, engine, get_db
from app.diagnosis import POLICY_VERSION, score_dimension
from app.models import (
    FAQ,
    Article,
    AuditLog,
    Bookmark,
    Category,
    Inquiry,
    Notice,
    Resource,
    Status,
    Tag,
    User,
)
from app.rc1 import issue_tokens
from app.rc1 import router as rc1_router
from app.schemas import (
    DiagnosisScoreRequest,
    DiagnosisScoreResponse,
    InquiryCreate,
    InquiryOut,
    LoginRequest,
    ResourceWrite,
    TokenOut,
    UserCreate,
    UserOut,
)
from app.security import (
    admin_user,
    current_user,
    hash_password,
    optional_current_user,
    verify_password,
)

settings = get_settings()

def isoformat_utc(value: datetime) -> str:
    normalized = value if value.tzinfo else value.replace(tzinfo=UTC)
    return normalized.astimezone(UTC).isoformat()

@asynccontextmanager
async def lifespan(application: FastAPI):
    Base.metadata.create_all(engine)
    application.state.startup_runs = getattr(application.state, "startup_runs", 0) + 1
    yield
app = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan, openapi_url="/api/v1/openapi.json")
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def request_context(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["X-Request-ID"] = request_id
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    return response


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, _: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "validation_error",
                "message": "요청 형식이 올바르지 않습니다.",
                "request_id": request.state.request_id,
            }
        },
    )


@app.exception_handler(Exception)
async def safe_error(request: Request, exc: Exception):
    if isinstance(exc, HTTPException):
        raise exc
    return JSONResponse(
        status_code=500,
        content={
            "error": {
                "code": "internal_error",
                "message": "??? ???? ?????.",
                "request_id": request.state.request_id,
            }
        },
    )




@app.get("/health", tags=["health"])
@app.get("/health/live", tags=["health"])
def live():
    return {"status": "ok"}


@app.get("/ready", tags=["health"])
@app.get("/health/ready", tags=["health"])
def ready(db: Session = Depends(get_db)):
    db.execute(text("SELECT 1"))
    return {"status": "ready"}


@app.post(
    "/api/v1/diagnosis/score",
    response_model=DiagnosisScoreResponse,
    tags=["diagnosis"],
)
def diagnosis_score(data: DiagnosisScoreRequest, request: Request):
    result = score_dimension(data.model_dump(mode="json"))
    return {
        "policy_version": POLICY_VERSION,
        **asdict(result),
        "request_id": request.state.request_id,
        "persisted": False,
    }


@app.post("/api/v1/auth/register", response_model=TokenOut, status_code=201, tags=["auth"])
def register(data: UserCreate, db: Session = Depends(get_db)):
    if db.scalar(select(User).where(func.lower(User.email) == data.email.lower())):
        raise HTTPException(409, "?? ??? ??????.")
    user = User(
        email=data.email.lower(), name=data.name, password_hash=hash_password(data.password)
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return issue_tokens(db, user)


@app.post("/api/v1/auth/login", response_model=TokenOut, tags=["auth"])
def login(data: LoginRequest, response: Response, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(func.lower(User.email) == data.email.lower()))
    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(401, "??? ?? ????? ??? ???.")
    tokens = issue_tokens(db, user)
    response.set_cookie(
        "refresh_token",
        tokens["refresh_token"],
        httponly=True,
        secure=settings.environment == "production",
        samesite="lax",
        max_age=604800,
    )
    return tokens


@app.get("/api/v1/me", response_model=UserOut, tags=["members"])
def me(user: User = Depends(current_user)):
    return user


def resource_dict(item: Resource) -> dict:
    return {
        "id": item.id,
        "title": item.title,
        "summary": item.summary,
        "body": item.body,
        "audience": item.audience,
        "resource_type": item.resource_type,
        "status": item.status.value,
        "featured": item.featured,
        "published_at": isoformat_utc(item.published_at) if item.published_at else None,
        "created_at": isoformat_utc(item.created_at),
        "category": {
            "id": item.category.id,
            "name": item.category.name,
            "slug": item.category.slug,
        },
        "tags": [{"id": tag.id, "name": tag.name, "slug": tag.slug} for tag in item.tags],
    }


@app.get("/api/v1/resources", tags=["resources"])
def resources(
    q: str = "",
    category: str = "",
    audience: str = "",
    resource_type: str = "",
    page: int = Query(1, ge=1),
    page_size: int = Query(12, ge=1, le=50),
    db: Session = Depends(get_db),
):
    stmt = (
        select(Resource)
        .options(selectinload(Resource.category), selectinload(Resource.tags))
        .where(Resource.status == Status.published)
    )
    if q:
        stmt = stmt.where(or_(Resource.title.ilike(f"%{q}%"), Resource.summary.ilike(f"%{q}%")))
    if category:
        stmt = stmt.join(Category).where(Category.slug == category)
    if audience:
        stmt = stmt.where(Resource.audience == audience)
    if resource_type:
        stmt = stmt.where(Resource.resource_type == resource_type)
    total = db.scalar(select(func.count()).select_from(stmt.subquery())) or 0
    items = (
        db.scalars(
            stmt.order_by(Resource.featured.desc(), Resource.published_at.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        .unique()
        .all()
    )
    return {
        "items": [resource_dict(x) for x in items],
        "total": total,
        "page": page,
        "page_size": page_size,
    }


@app.get("/api/v1/resources/{resource_id}", tags=["resources"])
def resource_detail(resource_id: str, db: Session = Depends(get_db)):
    item = db.scalar(
        select(Resource)
        .options(selectinload(Resource.category), selectinload(Resource.tags))
        .where(Resource.id == resource_id, Resource.status == Status.published)
    )
    if not item:
        raise HTTPException(404, "??? ?? ? ????.")
    return resource_dict(item)


@app.get("/api/v1/content/{kind}", tags=["content"])
def content(kind: str, db: Session = Depends(get_db)):
    model = {"notices": Notice, "articles": Article, "faqs": FAQ}.get(kind)
    if not model:
        raise HTTPException(404, "??? ??? ?? ? ????.")
    stmt = select(model).where(model.status == Status.published)
    if model is FAQ:
        stmt = stmt.order_by(FAQ.order)
    else:
        stmt = stmt.order_by(model.published_at.desc())
    rows = db.scalars(stmt).all()
    return [
        {
            "id": x.id,
            "title": getattr(x, "title", getattr(x, "question", "")),
            "body": getattr(x, "body", getattr(x, "answer", "")),
            "created_at": isoformat_utc(x.created_at),
        }
        for x in rows
    ]


@app.get("/api/v1/search", tags=["search"])
def search(q: str = Query(min_length=1), db: Session = Depends(get_db)):
    like = f"%{q}%"
    output = []
    for model, kind, title_col, body_col in [
        (Resource, "resource", Resource.title, Resource.summary),
        (Notice, "notice", Notice.title, Notice.body),
        (Article, "article", Article.title, Article.body),
        (FAQ, "faq", FAQ.question, FAQ.answer),
    ]:
        rows = db.scalars(
            select(model)
            .where(
                model.status == Status.published, or_(title_col.ilike(like), body_col.ilike(like))
            )
            .limit(20)
        ).all()
        for row in rows:
            output.append(
                {
                    "id": row.id,
                    "type": kind,
                    "title": getattr(row, "title", getattr(row, "question", "")),
                    "excerpt": getattr(
                        row, "summary", getattr(row, "body", getattr(row, "answer", ""))
                    )[:180],
                }
            )
    return {"query": q, "total": len(output), "items": output}


@app.post("/api/v1/inquiries", response_model=InquiryOut, status_code=201, tags=["inquiries"])
def create_inquiry(
    data: InquiryCreate,
    user: User | None = Depends(optional_current_user),
    db: Session = Depends(get_db),
):
    if not data.privacy_agreed:
        raise HTTPException(422, "???? ?? ??? ?????.")
    values = data.model_dump()
    values["user_id"] = user.id if user else None
    item = Inquiry(**values)
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@app.get("/api/v1/me/inquiries", response_model=list[InquiryOut], tags=["members"])
def my_inquiries(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return db.scalars(
        select(Inquiry)
        .where(or_(Inquiry.user_id == user.id, Inquiry.email == user.email))
        .order_by(Inquiry.created_at.desc())
    ).all()


@app.post("/api/v1/me/bookmarks/{resource_id}", status_code=201, tags=["members"])
def bookmark(resource_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    if not db.get(Resource, resource_id):
        raise HTTPException(404, "??? ?? ? ????.")
    existing = db.scalar(
        select(Bookmark).where(Bookmark.user_id == user.id, Bookmark.resource_id == resource_id)
    )
    if existing:
        return {"id": existing.id, "created": False}
    item = Bookmark(user_id=user.id, resource_id=resource_id)
    db.add(item)
    db.commit()
    return {"id": item.id, "created": True}


@app.get("/api/v1/me/bookmarks", tags=["members"])
def bookmarks(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.scalars(
        select(Bookmark).options(selectinload(Bookmark.resource)).where(Bookmark.user_id == user.id)
    ).all()
    return [
        {
            "id": row.id,
            "resource": {
                "id": row.resource.id,
                "title": row.resource.title,
                "summary": row.resource.summary,
            },
        }
        for row in rows
    ]


@app.get("/api/v1/admin/dashboard", tags=["admin"])
def dashboard(_: User = Depends(admin_user), db: Session = Depends(get_db)):
    return {
        "resources": db.scalar(select(func.count(Resource.id))),
        "users": db.scalar(select(func.count(User.id))),
        "inquiries": db.scalar(select(func.count(Inquiry.id))),
        "published": db.scalar(
            select(func.count(Resource.id)).where(Resource.status == Status.published)
        ),
    }


@app.post("/api/v1/admin/resources", status_code=201, tags=["admin"])
def admin_resource(
    data: ResourceWrite, admin: User = Depends(admin_user), db: Session = Depends(get_db)
):
    category = db.get(Category, data.category_id)
    if not category:
        raise HTTPException(422, "????? ?? ? ????.")
    values = data.model_dump(exclude={"tag_ids"})
    values["status"] = Status(values["status"])
    if values["status"] == Status.published:
        values["published_at"] = datetime.now(UTC)
    item = Resource(
        **values, tags=list(db.scalars(select(Tag).where(Tag.id.in_(data.tag_ids))).all())
    )
    db.add(item)
    db.flush()
    db.add(
        AuditLog(
            actor_id=admin.id,
            action="resource.create",
            entity_type="resource",
            entity_id=item.id,
            detail=json.dumps({"title": item.title}, ensure_ascii=False),
        )
    )
    db.commit()
    return {"id": item.id}


@app.patch("/api/v1/admin/inquiries/{inquiry_id}", tags=["admin"])
def admin_inquiry(
    inquiry_id: str,
    status: str,
    note: str = "",
    admin: User = Depends(admin_user),
    db: Session = Depends(get_db),
):
    item = db.get(Inquiry, inquiry_id)
    if not item:
        raise HTTPException(404, "??? ?? ? ????.")
    item.status, item.admin_note = status, note
    db.add(
        AuditLog(
            actor_id=admin.id, action="inquiry.update", entity_type="inquiry", entity_id=item.id
        )
    )
    db.commit()
    return {"id": item.id, "status": item.status}


app.include_router(rc1_router)
