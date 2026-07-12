import os

os.environ["DATABASE_URL"] = "sqlite:///./test-seed-content-pack.db"
os.environ["JWT_SECRET"] = "test-secret-at-least-thirty-two-characters"
os.environ["ADMIN_EMAIL"] = "admin@example.com"
os.environ["ADMIN_PASSWORD"] = "AdminPass!123"

from sqlalchemy import func, or_, select

from app.database import Base, SessionLocal, engine
from app.models import (
    FAQ,
    Article,
    Category,
    Inquiry,
    Notice,
    Resource,
    ResourceAttachment,
    Role,
    Tag,
    User,
)
from app.seed import seed


def reset_db() -> None:
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)


def count(model) -> int:
    with SessionLocal() as db:
        return db.scalar(select(func.count(model.id))) or 0


def test_yonlab_content_pack_v1_populates_rich_clean_room_seed_data_idempotently():
    reset_db()

    seed()
    first_counts = {
        "categories": count(Category),
        "tags": count(Tag),
        "resources": count(Resource),
        "notices": count(Notice),
        "articles": count(Article),
        "faqs": count(FAQ),
        "inquiries": count(Inquiry),
        "users": count(User),
        "attachments": count(ResourceAttachment),
    }

    assert first_counts == {
        "categories": 10,
        "tags": 45,
        "resources": 100,
        "notices": 18,
        "articles": 28,
        "faqs": 45,
        "inquiries": 15,
        "users": 4,
        "attachments": 0,
    }

    seed()
    assert {
        "categories": count(Category),
        "tags": count(Tag),
        "resources": count(Resource),
        "notices": count(Notice),
        "articles": count(Article),
        "faqs": count(FAQ),
        "inquiries": count(Inquiry),
        "users": count(User),
        "attachments": count(ResourceAttachment),
    } == first_counts

    with SessionLocal() as db:
        category_names = {row.name for row in db.scalars(select(Category)).all()}
        assert {"\ub180\uc774 \ud65c\ub3d9", "\uad00\ucc30\u00b7\uae30\ub85d", "\uac00\uc815 \uc5f0\uacc4", "\ub514\uc9c0\ud138 \ud65c\uc6a9", "\uad50\uc0ac \uc131\uc7a5"} <= category_names

        admin_count = db.scalar(select(func.count(User.id)).where(User.role == Role.admin)) or 0
        assert admin_count == 1

        forbidden = ["i-\ub204\ub9ac", "\uc544\uc774\ub204\ub9ac", "\ub204\ub9ac\uacfc\uc815 \ud574\uc124\uc11c", "\uad50\uc721\ubd80 \uace0\uc2dc"]
        corpus_rows = []
        corpus_rows += [r.title + r.summary + r.body for r in db.scalars(select(Resource)).all()]
        corpus_rows += [n.title + n.body for n in db.scalars(select(Notice)).all()]
        corpus_rows += [a.title + a.summary + a.body for a in db.scalars(select(Article)).all()]
        corpus_rows += [f.question + f.answer for f in db.scalars(select(FAQ)).all()]
        corpus = "\n".join(corpus_rows)
        assert not any(term in corpus for term in forbidden)
        assert "YOnLab \uc790\uccb4 \uc791\uc131 \uc0d8\ud50c" in corpus

        for keyword in ["\ub180\uc774", "\uad00\ucc30", "\uac00\uc815", "\uc548\uc804", "\ub514\uc9c0\ud138"]:
            like = f"%{keyword}%"
            matches = db.scalar(
                select(func.count(Resource.id)).where(
                    or_(Resource.title.ilike(like), Resource.summary.ilike(like), Resource.body.ilike(like))
                )
            )
            assert matches >= 10, keyword
