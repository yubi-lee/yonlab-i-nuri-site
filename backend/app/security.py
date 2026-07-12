import hashlib
import secrets
from datetime import UTC, datetime, timedelta

import jwt
from argon2 import PasswordHasher
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.config import get_settings
from app.database import get_db
from app.models import Role, User

hasher = PasswordHasher()
bearer = HTTPBearer(auto_error=False)


def hash_password(value: str) -> str:
    return hasher.hash(value)


def verify_password(value: str, hashed: str) -> bool:
    try:
        return hasher.verify(hashed, value)
    except Exception:
        return False


def create_access_token(user: User) -> str:
    settings = get_settings()
    now = datetime.now(UTC)
    claims = {
        "sub": user.id,
        "role": user.role.value,
        "iat": now,
        "exp": now + timedelta(minutes=settings.access_token_minutes),
    }
    return jwt.encode(claims, settings.jwt_secret, algorithm="HS256")


def new_refresh_token() -> tuple[str, str]:
    token = secrets.token_urlsafe(48)
    return token, hashlib.sha256(token.encode()).hexdigest()


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
    db: Session = Depends(get_db),
) -> User:
    if not credentials:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="??? ?????.")
    try:
        payload = jwt.decode(
            credentials.credentials, get_settings().jwt_secret, algorithms=["HS256"]
        )
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=401, detail="???? ?? ?????.") from exc
    user = db.get(User, payload.get("sub"))
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="?? ???? ?? ? ????.")
    return user


def admin_user(user: User = Depends(current_user)) -> User:
    if user.role != Role.admin:
        raise HTTPException(status_code=403, detail="??? ??? ?????.")
    return user
