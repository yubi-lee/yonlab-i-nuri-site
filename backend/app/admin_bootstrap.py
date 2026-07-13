from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.models import Role, User
from app.security import hash_password

PASSWORD_MIN_LENGTH = 14
PASSWORD_MAX_LENGTH = 128
DEFAULT_ADMIN_NAME = "Production Administrator"


class AdminBootstrapError(ValueError):
    """Raised when production administrator bootstrap input is unsafe."""


@dataclass(frozen=True)
class AdminBootstrapResult:
    created: bool
    email: str | None
    reason: str
    message: str


def normalize_email(email: str) -> str:
    normalized = email.strip().lower()
    if not normalized or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", normalized):
        raise AdminBootstrapError("Production admin email must be a valid email address.")
    return normalized


def validate_admin_password(password: str) -> None:
    if len(password) < PASSWORD_MIN_LENGTH:
        raise AdminBootstrapError(
            f"Production admin password must be at least {PASSWORD_MIN_LENGTH} characters."
        )
    if len(password) > PASSWORD_MAX_LENGTH:
        raise AdminBootstrapError(
            f"Production admin password must be at most {PASSWORD_MAX_LENGTH} characters."
        )
    checks = (
        (any(char.islower() for char in password), "lowercase letter"),
        (any(char.isupper() for char in password), "uppercase letter"),
        (any(char.isdigit() for char in password), "digit"),
        (any(not char.isalnum() for char in password), "symbol"),
    )
    missing = [label for passed, label in checks if not passed]
    if missing:
        raise AdminBootstrapError(
            "Production admin password must include at least one " + ", ".join(missing) + "."
        )
    lowered = password.lower()
    if any(term in lowered for term in ("password", "admin", "yonlearn", "yonlab")):
        raise AdminBootstrapError("Production admin password must not contain common product or role words.")


def bootstrap_admin(
    db: Session,
    *,
    email: str,
    password: str,
    name: str = DEFAULT_ADMIN_NAME,
) -> AdminBootstrapResult:
    normalized_email = normalize_email(email)
    validate_admin_password(password)
    clean_name = name.strip() or DEFAULT_ADMIN_NAME

    active_admin_count = db.scalar(
        select(func.count(User.id)).where(User.role == Role.admin, User.is_active.is_(True))
    ) or 0
    existing = db.scalar(select(User).where(func.lower(User.email) == normalized_email))

    if active_admin_count > 0:
        if existing and existing.role == Role.admin and existing.is_active:
            existing.name = clean_name
            existing.password_hash = hash_password(password)
            db.commit()
            return AdminBootstrapResult(
                created=False,
                email=normalized_email,
                reason="admin_rotated",
                message="Existing production administrator credentials were rotated.",
            )
        return AdminBootstrapResult(
            created=False,
            email=None,
            reason="admin_exists",
            message="An active administrator already exists; no account was created.",
        )

    if existing:
        existing.name = clean_name
        existing.password_hash = hash_password(password)
        existing.role = Role.admin
        existing.is_active = True
        db.commit()
        return AdminBootstrapResult(
            created=False,
            email=normalized_email,
            reason="promoted_existing_user",
            message="Existing user was promoted to production administrator.",
        )

    db.add(
        User(
            email=normalized_email,
            name=clean_name,
            password_hash=hash_password(password),
            role=Role.admin,
            is_active=True,
        )
    )
    db.commit()
    return AdminBootstrapResult(
        created=True,
        email=normalized_email,
        reason="created",
        message="Production administrator account was created.",
    )


def bootstrap_admin_from_env() -> AdminBootstrapResult:
    email = os.getenv("PRODUCTION_ADMIN_EMAIL", "")
    password = os.getenv("PRODUCTION_ADMIN_INITIAL_PASSWORD", "")
    name = os.getenv("PRODUCTION_ADMIN_NAME") or DEFAULT_ADMIN_NAME
    if not email:
        raise AdminBootstrapError("PRODUCTION_ADMIN_EMAIL is required.")
    if not password:
        raise AdminBootstrapError("PRODUCTION_ADMIN_INITIAL_PASSWORD is required.")
    with SessionLocal() as db:
        return bootstrap_admin(db, email=email, password=password, name=name)


def main() -> int:
    try:
        result = bootstrap_admin_from_env()
    except AdminBootstrapError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"FAIL: production admin bootstrap failed: {exc}", file=sys.stderr)
        return 1

    email_suffix = f" email={result.email}" if result.email else ""
    print(f"PASS: {result.message} reason={result.reason}{email_suffix}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
