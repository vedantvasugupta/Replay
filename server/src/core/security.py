from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Literal, TypedDict

from jose import JWTError, jwt
from passlib.context import CryptContext

from .config import get_settings


pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


class TokenPayload(TypedDict):
    sub: str
    type: Literal["access", "refresh"]
    exp: int


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    return pwd_context.verify(password, password_hash)


def _create_token(subject: str, token_type: Literal["access", "refresh"], expires_delta: timedelta) -> str:
    settings = get_settings().jwt()
    expire = datetime.now(timezone.utc) + expires_delta
    to_encode: dict[str, Any] = {"sub": subject, "type": token_type, "exp": int(expire.timestamp())}
    return jwt.encode(to_encode, settings.secret_key, algorithm=settings.algorithm)


def create_access_token(subject: str) -> str:
    settings = get_settings().jwt()
    return _create_token(subject, "access", timedelta(minutes=settings.access_expires_minutes))


def create_refresh_token(subject: str) -> str:
    settings = get_settings().jwt()
    return _create_token(subject, "refresh", timedelta(days=settings.refresh_expires_days))


def decode_token(token: str, expected_type: Literal["access", "refresh"]) -> TokenPayload:
    settings = get_settings().jwt()
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
    except JWTError as exc:
        raise ValueError("Invalid token") from exc

    token_type = payload.get("type")
    if token_type != expected_type:
        raise ValueError("Invalid token type")

    subject = payload.get("sub")
    if subject is None:
        raise ValueError("Invalid token payload")

    exp = payload.get("exp")
    if exp is None:
        raise ValueError("Invalid token expiry")

    return TokenPayload(sub=str(subject), type=expected_type, exp=int(exp))
