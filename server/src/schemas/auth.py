from __future__ import annotations

from datetime import datetime

from pydantic import EmailStr, Field

from .base import CamelModel


class SignUpRequest(CamelModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class LoginRequest(CamelModel):
    email: EmailStr
    password: str


class TokenPair(CamelModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshRequest(CamelModel):
    refresh_token: str


class GoogleAuthRequest(CamelModel):
    id_token: str


class UserRead(CamelModel):
    id: int
    email: EmailStr
    provider: str
    created_at: datetime
