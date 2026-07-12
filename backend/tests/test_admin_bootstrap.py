from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session

from app.admin_bootstrap import AdminBootstrapError, bootstrap_admin
from app.models import Base, Role, User
from app.security import hash_password, verify_password


def make_session() -> Session:
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    return Session(engine)


def count_admins(db: Session) -> int:
    return db.scalar(select(func.count(User.id)).where(User.role == Role.admin)) or 0


def test_bootstrap_admin_creates_first_active_admin_without_logging_password():
    with make_session() as db:
        result = bootstrap_admin(
            db,
            email="Owner@Example.Test",
            password="Str0ng!Bootstrap2026",
            name="Production Owner",
        )

        user = db.scalar(select(User).where(User.email == "owner@example.test"))
        assert result.created is True
        assert result.reason == "created"
        assert result.email == "owner@example.test"
        assert count_admins(db) == 1
        assert user is not None
        assert user.role == Role.admin
        assert user.is_active is True
        assert user.password_hash != "Str0ng!Bootstrap2026"
        assert verify_password("Str0ng!Bootstrap2026", user.password_hash)
        assert "Str0ng!Bootstrap2026" not in result.message


def test_bootstrap_admin_is_idempotent_when_active_admin_exists():
    with make_session() as db:
        db.add(
            User(
                email="existing-admin@example.test",
                name="Existing Admin",
                password_hash=hash_password("ExistingAdmin!2345"),
                role=Role.admin,
            )
        )
        db.commit()

        result = bootstrap_admin(
            db,
            email="new-admin@example.test",
            password="Str0ng!Bootstrap2026",
            name="New Admin",
        )

        assert result.created is False
        assert result.reason == "admin_exists"
        assert count_admins(db) == 1
        assert db.scalar(select(User).where(User.email == "new-admin@example.test")) is None


def test_bootstrap_admin_rejects_weak_password():
    with make_session() as db:
        try:
            bootstrap_admin(
                db,
                email="owner@example.test",
                password="weak-password",
                name="Production Owner",
            )
        except AdminBootstrapError as exc:
            assert "password" in str(exc).lower()
        else:
            raise AssertionError("weak password was accepted")

        assert count_admins(db) == 0
