import os
from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.database import Base, SessionLocal, engine
from app.models import FAQ, Article, Category, Notice, Resource, Role, Status, Tag, User
from app.security import hash_password

CATEGORIES = [
    "AI 수업 설계",
    "온디바이스 AI",
    "디지털 리터러시",
    "교사 지원",
    "안전·윤리",
    "YOnLab 소식",
]
TAGS = [
    "초급",
    "실습",
    "교사용",
    "학습자용",
    "생성형 AI",
    "프롬프트",
    "개인정보",
    "저작권",
    "평가",
    "수업안",
    "모바일",
    "가이드",
]


def seed() -> None:
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        if db.scalar(select(Category)):
            print("Seed data already exists.")
            return
        categories = [
            Category(name=name, slug=f"category-{i + 1}") for i, name in enumerate(CATEGORIES)
        ]
        tags = [Tag(name=name, slug=f"tag-{i + 1}") for i, name in enumerate(TAGS)]
        db.add_all(categories + tags)
        db.flush()
        for i in range(20):
            db.add(
                Resource(
                    title=f"가상 AI 교육 자료 {i + 1}",
                    summary="교실과 일상에서 안전하게 AI를 활용하기 위한 YOnLab 가상 예시 자료입니다.",
                    body="제품 시연을 위해 새로 작성한 가상 자료입니다. 학습 목표, 실습 질문, 성찰 항목으로 구성됩니다.",
                    audience="교사" if i % 2 == 0 else "학습자",
                    resource_type=["가이드", "수업안", "체크리스트"][i % 3],
                    category=categories[i % len(categories)],
                    tags=[tags[i % len(tags)], tags[(i + 3) % len(tags)]],
                    status=Status.published,
                    featured=i < 4,
                    published_at=datetime.now(UTC) - timedelta(days=i),
                )
            )
        for i in range(6):
            db.add(
                Notice(
                    title=f"YOnLearn Hub 가상 공지 {i + 1}",
                    body="서비스 시연을 위한 가상 공지입니다.",
                    status=Status.published,
                    published_at=datetime.now(UTC) - timedelta(days=i),
                )
            )
        for i in range(8):
            db.add(
                Article(
                    title=f"AI 교육 인사이트 {i + 1}",
                    summary="현장 중심의 가상 인사이트",
                    body="YOnLab이 새로 작성한 교육·AI 가상 인사이트입니다.",
                    status=Status.published,
                    published_at=datetime.now(UTC) - timedelta(days=i),
                )
            )
        for i in range(10):
            db.add(
                FAQ(
                    question=f"서비스 이용 질문 {i + 1}",
                    answer="가상 서비스 이용 안내입니다. 운영 전 실제 정책으로 교체해 주세요.",
                    order=i,
                    status=Status.published,
                )
            )
        db.add(
            User(
                email="learner@example.com",
                name="가상 학습자",
                password_hash=hash_password("DemoUser!234"),
                role=Role.user,
            )
        )
        admin_email, admin_password = os.getenv("ADMIN_EMAIL"), os.getenv("ADMIN_PASSWORD")
        if admin_email and admin_password:
            db.add(
                User(
                    email=admin_email.lower(),
                    name="관리자",
                    password_hash=hash_password(admin_password),
                    role=Role.admin,
                )
            )
        db.commit()
        print("Seed complete: 6 categories, 12 tags, 20 resources, 6 notices, 8 articles, 10 FAQs.")


if __name__ == "__main__":
    seed()
