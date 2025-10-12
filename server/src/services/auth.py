from typing import Optional

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.security import create_access_token, create_refresh_token, hash_password, verify_password
from ..models.entities import User


class AuthService:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def register_user(self, email: str, password: str) -> User:
        user = User(email=email.lower(), password_hash=hash_password(password))
        self.db.add(user)
        try:
            await self.db.commit()
        except IntegrityError:
            await self.db.rollback()
            raise ValueError("Email already registered")
        await self.db.refresh(user)
        return user

    async def authenticate(self, email: str, password: str) -> Optional[User]:
        result = await self.db.execute(select(User).where(User.email == email.lower()))
        user = result.scalar_one_or_none()
        if user and verify_password(password, user.password_hash):
            return user
        return None

    def generate_tokens(self, user: User) -> dict[str, str]:
        subject = user.id
        return {
            "access": create_access_token(subject),
            "refresh": create_refresh_token(subject),
        }

    async def get_user_by_id(self, user_id: str) -> Optional[User]:
        result = await self.db.execute(select(User).where(User.id == user_id))
        return result.scalar_one_or_none()
