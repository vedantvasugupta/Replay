from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.deps import get_db_session
from ..core.security import decode_token
from ..schemas.auth import GoogleAuthRequest, LoginRequest, RefreshRequest, SignUpRequest, TokenPair, UserRead
from ..services.auth_service import AuthService


def get_auth_service() -> AuthService:
    from ..app import get_app_state

    return get_app_state().auth_service


router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/signup", response_model=UserRead, status_code=201)
async def signup(
    payload: SignUpRequest,
    db: AsyncSession = Depends(get_db_session),
    auth_service: AuthService = Depends(get_auth_service),
) -> UserRead:
    user = await auth_service.register(db, payload.email, payload.password)
    return UserRead.model_validate(user)


@router.post("/login", response_model=TokenPair)
async def login(
    payload: LoginRequest,
    db: AsyncSession = Depends(get_db_session),
    auth_service: AuthService = Depends(get_auth_service),
) -> TokenPair:
    user = await auth_service.authenticate(db, payload.email, payload.password)
    access, refresh = auth_service.issue_tokens(user)
    return TokenPair(access_token=access, refresh_token=refresh)


@router.post("/refresh", response_model=TokenPair)
async def refresh(
    payload: RefreshRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> TokenPair:
    try:
        decoded = decode_token(payload.refresh_token, expected_type="refresh")
    except ValueError as exc:
        raise HTTPException(status_code=401, detail="Invalid refresh token") from exc
    access, refresh_token = auth_service.issue_tokens_for_subject(decoded["sub"])
    return TokenPair(access_token=access, refresh_token=refresh_token)


@router.post("/google", response_model=TokenPair)
async def google_auth(
    payload: GoogleAuthRequest,
    db: AsyncSession = Depends(get_db_session),
    auth_service: AuthService = Depends(get_auth_service),
) -> TokenPair:
    """Authenticate with Google OAuth ID token."""
    import logging
    logger = logging.getLogger(__name__)

    logger.info("=" * 80)
    logger.info("🔵 [ENDPOINT] Received POST /auth/google request")
    logger.info(f"🔵 [ENDPOINT] ID token length: {len(payload.id_token)}")
    logger.info(f"🔵 [ENDPOINT] ID token preview: {payload.id_token[:50]}...")

    try:
        logger.info("🔵 [ENDPOINT] Calling auth_service.authenticate_google...")
        user = await auth_service.authenticate_google(db, payload.id_token)

        logger.info(f"✅ [ENDPOINT] User authenticated: {user.email} (ID: {user.id})")
        logger.info("🔵 [ENDPOINT] Issuing tokens...")

        access, refresh = auth_service.issue_tokens(user)

        logger.info(f"✅ [ENDPOINT] Tokens issued successfully (access length: {len(access)}, refresh length: {len(refresh)})")
        logger.info("=" * 80)

        return TokenPair(access_token=access, refresh_token=refresh)
    except HTTPException as e:
        logger.error(f"❌ [ENDPOINT] HTTPException: {e.status_code} - {e.detail}")
        logger.error("=" * 80)
        raise
    except Exception as e:
        logger.error(f"❌ [ENDPOINT] Unexpected error: {str(e)}", exc_info=True)
        logger.error("=" * 80)
        raise
