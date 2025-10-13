from __future__ import annotations

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.security import create_access_token, create_refresh_token, hash_password, verify_password
from ..models.user import User


class AuthService:
    GOOGLE_CLIENT_IDS = [
        # Android debug client ID (SHA-1: 91:DF:84:ED:A2:18:CE:68:27:F8:20:E0:41:33:A6:33:3A:C3:76:2C)
        "264393041730-mummto7guqk8a7ch01gbuqr8eknpq6c1.apps.googleusercontent.com",
        # Android release client ID (SHA-1: F9:6F:72:75:52:32:CB:39:30:96:B1:2E:61:5A:08:16:3C:92:54:C2)
        "264393041730-roogacpd3cliau8pniulkn2i0ju7nlal.apps.googleusercontent.com",
        # Web client ID
        "264393041730-ppuvv0kdvt02anp25nppoi9ff6f6rafn.apps.googleusercontent.com",
    ]
    async def register(self, session: AsyncSession, email: str, password: str) -> User:
        existing_stmt = select(User).where(User.email == email)
        existing = await session.execute(existing_stmt)
        if existing.scalar_one_or_none():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")

        user = User(email=email, password_hash=hash_password(password))
        session.add(user)
        await session.commit()
        await session.refresh(user)
        return user

    async def authenticate(self, session: AsyncSession, email: str, password: str) -> User:
        stmt = select(User).where(User.email == email)
        result = await session.execute(stmt)
        user = result.scalar_one_or_none()
        if not user or not verify_password(password, user.password_hash):
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
        return user

    def issue_tokens(self, user: User) -> tuple[str, str]:
        subject = str(user.id)
        return create_access_token(subject), create_refresh_token(subject)

    def issue_tokens_for_subject(self, subject: str) -> tuple[str, str]:
        return create_access_token(subject), create_refresh_token(subject)

    async def authenticate_google(self, session: AsyncSession, id_token: str) -> User:
        """Authenticate user via Google OAuth ID token."""
        try:
            from google.oauth2 import id_token as google_id_token
            from google.auth.transport import requests
        except ImportError as exc:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Google auth not configured"
            ) from exc

        try:
            # Verify the token
            idinfo = google_id_token.verify_oauth2_token(
                id_token,
                requests.Request(),
                # audience=self.GOOGLE_CLIENT_IDS[0] if self.GOOGLE_CLIENT_IDS else None
            )

            google_user_id = idinfo["sub"]
            email = idinfo.get("email")

            if not email:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Email not provided by Google"
                )

            # Check if user exists with this google_id
            stmt = select(User).where(User.google_id == google_user_id)
            result = await session.execute(stmt)
            user = result.scalar_one_or_none()

            if user:
                return user

            # Check if email already exists (for linking accounts)
            stmt = select(User).where(User.email == email)
            result = await session.execute(stmt)
            existing_user = result.scalar_one_or_none()

            if existing_user:
                # Link Google account to existing email account
                existing_user.google_id = google_user_id
                existing_user.provider = "google"
                session.add(existing_user)
                await session.commit()
                await session.refresh(existing_user)
                return existing_user

            # Create new user
            user = User(
                email=email,
                provider="google",
                google_id=google_user_id,
                password_hash=None,
            )
            session.add(user)
            await session.commit()
            await session.refresh(user)
            return user

        except ValueError as exc:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid Google token"
            ) from exc
