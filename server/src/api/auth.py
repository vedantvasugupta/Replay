from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.security import decode_token
from ..schemas.auth import LoginRequest, RefreshRequest, SignupRequest, TokenResponse
from ..services.auth import AuthService
from .deps import get_auth_service

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/signup", status_code=status.HTTP_201_CREATED)
async def signup(payload: SignupRequest, auth: AuthService = Depends(get_auth_service)) -> None:
    try:
        await auth.register_user(payload.email, payload.password)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


@router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, auth: AuthService = Depends(get_auth_service)) -> TokenResponse:
    user = await auth.authenticate(payload.email, payload.password)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    tokens = auth.generate_tokens(user)
    return TokenResponse(**tokens)


@router.post("/refresh", response_model=TokenResponse)
async def refresh(payload: RefreshRequest, auth: AuthService = Depends(get_auth_service)) -> TokenResponse:
    data = decode_token(payload.refresh)
    if not data or data.get("type") != "refresh":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token")
    user = await auth.get_user_by_id(data["sub"])
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return TokenResponse(**auth.generate_tokens(user))
