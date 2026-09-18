"""JWT auth + bcrypt password hashing + role guards."""
import os
from datetime import datetime, timedelta
from typing import Optional

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from database import SessionLocal, User

SECRET_KEY = os.getenv("JWT_SECRET", "jaaltaka-dev-secret-change-me")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30
REFRESH_TOKEN_EXPIRE_DAYS = 7

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


# --- password helpers ---
def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))
    except Exception:
        return False


# --- token helpers ---
def create_access_token(user_id: int, email: str, role: str) -> str:
    payload = {
        "sub": str(user_id),
        "email": email,
        "role": role,
        "type": "access",
        "exp": datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
        "iat": datetime.utcnow(),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def create_refresh_token(user_id: int) -> str:
    payload = {
        "sub": str(user_id),
        "type": "refresh",
        "exp": datetime.utcnow() + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
        "iat": datetime.utcnow(),
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def verify_refresh_token(token: str) -> int:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("type") != "refresh":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token type. Refresh token required."
            )
        return int(payload.get("sub"))
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token has expired. Please login again."
        )
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token."
        )


def get_db_session() -> Session:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_current_user(token: str = Depends(oauth2_scheme)) -> User:
    err = HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                        detail="Not authenticated. Please login.",
                        headers={"WWW-Authenticate": "Bearer"})
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("type") not in (None, "access"):
            raise err
        user_id = int(payload.get("sub"))
    except Exception:
        raise err
    db = SessionLocal()
    try:
        user = db.query(User).filter(User.id == user_id).first()
    finally:
        db.close()
    if user is None:
        raise err
    return user


def require_admin(current: User = Depends(get_current_user)) -> User:
    if current.role != "admin":
        raise HTTPException(status_code=403, detail="Admin only.")
    return current
