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

    def __init__(self):
        """Initialize AuthService with cached Google auth request object."""
        from google.auth.transport import requests as google_requests
        import requests as urllib_requests

        # Create a requests session with timeout
        session = urllib_requests.Session()
        session.timeout = 5  # 5 second timeout for Google API calls

        # Cache the request object using our configured session
        self._google_request = google_requests.Request(session=session)

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
        import logging
        logger = logging.getLogger(__name__)

        logger.info("🔵 [AUTH_SERVICE] Starting authenticate_google")
        logger.info(f"🔵 [AUTH_SERVICE] Token length: {len(id_token)}")

        try:
            from google.oauth2 import id_token as google_id_token
            logger.info("✅ [AUTH_SERVICE] Google auth libraries imported successfully")
        except ImportError as exc:
            logger.error("❌ [AUTH_SERVICE] Failed to import google auth libraries", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Google auth not configured"
            ) from exc

        try:
            logger.info("🔵 [AUTH_SERVICE] Verifying Google ID token with Google servers...")
            logger.info(f"🔵 [AUTH_SERVICE] Configured client IDs: {self.GOOGLE_CLIENT_IDS}")

            # Verify the token with audience validation
            # Try each client ID until one works (supports multiple platforms)
            idinfo = None
            last_error = None

            for client_id in self.GOOGLE_CLIENT_IDS:
                try:
                    # Use cached request object with 5-second timeout
                    idinfo = google_id_token.verify_oauth2_token(
                        id_token,
                        self._google_request,
                        audience=client_id
                    )
                    logger.info(f"✅ [AUTH_SERVICE] Token verified successfully with client ID: {client_id}")
                    break
                except ValueError as e:
                    last_error = e
                    logger.debug(f"🔵 [AUTH_SERVICE] Token verification failed for client ID {client_id}: {str(e)}")
                    continue

            if not idinfo:
                logger.error(f"❌ [AUTH_SERVICE] Token verification failed for all client IDs. Last error: {last_error}")
                raise ValueError(f"Invalid token: token audience does not match any configured client IDs")

            logger.info(f"✅ [AUTH_SERVICE] Token verified successfully!")
            logger.info(f"🔵 [AUTH_SERVICE] Token info - Email: {idinfo.get('email')}, Sub: {idinfo.get('sub')}, Issuer: {idinfo.get('iss')}, Audience: {idinfo.get('aud')}")

            google_user_id = idinfo["sub"]
            email = idinfo.get("email")

            if not email:
                logger.error("❌ [AUTH_SERVICE] Email not provided by Google in token")
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Email not provided by Google"
                )

            logger.info(f"🔵 [AUTH_SERVICE] Checking if user exists with google_id: {google_user_id}")
            # Check if user exists with this google_id
            stmt = select(User).where(User.google_id == google_user_id)
            result = await session.execute(stmt)
            user = result.scalar_one_or_none()

            if user:
                logger.info(f"✅ [AUTH_SERVICE] Existing user found with google_id (ID: {user.id}, Email: {user.email})")
                return user

            logger.info(f"🔵 [AUTH_SERVICE] No user with google_id. Checking if email exists: {email}")
            # Check if email already exists (for linking accounts)
            stmt = select(User).where(User.email == email)
            result = await session.execute(stmt)
            existing_user = result.scalar_one_or_none()

            if existing_user:
                logger.info(f"🔵 [AUTH_SERVICE] Linking Google account to existing email user (ID: {existing_user.id})")
                # Link Google account to existing email account
                existing_user.google_id = google_user_id
                existing_user.provider = "google"
                session.add(existing_user)
                await session.commit()
                await session.refresh(existing_user)
                logger.info(f"✅ [AUTH_SERVICE] Account linked successfully")
                return existing_user

            logger.info(f"🔵 [AUTH_SERVICE] Creating new user with email: {email}")
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
            logger.info(f"✅ [AUTH_SERVICE] New user created successfully (ID: {user.id})")
            return user

        except ValueError as exc:
            logger.error(f"❌ [AUTH_SERVICE] ValueError - Invalid Google token: {str(exc)}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid Google token: {str(exc)}"
            ) from exc
        except HTTPException:
            # Re-raise HTTPExceptions as-is
            raise
        except Exception as exc:
            from sqlalchemy.exc import IntegrityError

            # Handle race condition where user was created between check and insert
            if isinstance(exc, IntegrityError) and "ix_users_email" in str(exc):
                logger.warning(f"⚠️ [AUTH_SERVICE] Race condition detected - user already exists: {email}")
                # Retry the lookup one more time
                stmt = select(User).where(User.email == email)
                result = await session.execute(stmt)
                existing_user = result.scalar_one_or_none()
                if existing_user:
                    logger.info(f"✅ [AUTH_SERVICE] Retrieved existing user after race condition (ID: {existing_user.id})")
                    return existing_user

            logger.error(f"❌ [AUTH_SERVICE] Unexpected error in authenticate_google: {str(exc)}", exc_info=True)
            logger.error(f"❌ [AUTH_SERVICE] Exception type: {type(exc).__name__}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Authentication failed: {str(exc)}"
            ) from exc
