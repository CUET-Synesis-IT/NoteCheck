import time
import os
from typing import Optional
from datetime import datetime
from fastapi import FastAPI, File, UploadFile, HTTPException, Depends, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy.orm import Session
from sqlalchemy import func
import torch

from model_loader import load_banknote_model, process_banknote_image, CLASS_NAMES
from database import init_db, get_db, User, Scan
from auth import (
    hash_password, verify_password, create_access_token,
    create_refresh_token, verify_refresh_token,
    get_current_user, require_admin,
)

app = FastAPI(
    title="Banknote Counterfeit Detection API",
    description="DeiT Vision Transformer serving counterfeit vs genuine banknote predictions with auto-cropping + JWT auth",
    version="2.0.0"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(BASE_DIR, "models", "best_deit.pth")
model = None


@app.on_event("startup")
def load_model_on_startup():
    global model
    init_db()
    # seed default admin: admin@jaaltaka.com / Admin123!
    from database import SessionLocal
    db = SessionLocal()
    try:
        if not db.query(User).filter(User.email == "admin@jaaltaka.com").first():
            db.add(User(name="Admin", email="admin@jaaltaka.com",
                        password_hash=hash_password("Admin123!"), role="admin"))
            db.commit()
            print("[INFO] Seeded admin: admin@jaaltaka.com / Admin123!")
    finally:
        db.close()
    try:
        model = load_banknote_model(MODEL_PATH)
        print(f"[INFO] Model successfully loaded from: {MODEL_PATH}")
    except Exception as e:
        print(f"[WARNING] Could not load model: {e}")


# ---------- schemas ----------
class RegisterIn(BaseModel):
    name: str = Field(min_length=2, max_length=100)
    email: EmailStr
    password: str = Field(min_length=6, max_length=72)


class LoginIn(BaseModel):
    email: EmailStr
    password: str


class TokenOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: dict


class RefreshIn(BaseModel):
    refresh_token: str


class RefreshOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class PredictionResponse(BaseModel):
    prediction: str
    confidence: float
    probabilities: dict
    inference_time_ms: float
    note_detected_and_cropped: bool
    cropped_banknote_base64: Optional[str] = None
    scan_id: Optional[int] = None


# ---------- auth routes ----------
@app.post("/auth/register", response_model=TokenOut)
def register(data: RegisterIn, db: Session = Depends(get_db)):
    email = data.email.lower().strip()
    if db.query(User).filter(User.email == email).first():
        raise HTTPException(status_code=400, detail="Email already registered.")
    user = User(name=data.name.strip(), email=email,
                password_hash=hash_password(data.password), role="user")
    db.add(user)
    db.commit()
    db.refresh(user)
    token = create_access_token(user.id, user.email, user.role)
    refresh_tok = create_refresh_token(user.id)
    return TokenOut(access_token=token, refresh_token=refresh_tok,
                    user={"id": user.id, "name": user.name, "email": user.email, "role": user.role})


@app.post("/auth/login", response_model=TokenOut)
def login(data: LoginIn, db: Session = Depends(get_db)):
    # Also accept OAuth2 form (for /docs "Authorize" button)
    user = db.query(User).filter(User.email == data.email.lower().strip()).first()
    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password.")
    token = create_access_token(user.id, user.email, user.role)
    refresh_tok = create_refresh_token(user.id)
    return TokenOut(access_token=token, refresh_token=refresh_tok,
                    user={"id": user.id, "name": user.name, "email": user.email, "role": user.role})


@app.post("/auth/token", response_model=TokenOut)
def login_form(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    """OAuth2 form variant so Swagger Authorize button works (username=email)."""
    user = db.query(User).filter(User.email == form.username.lower().strip()).first()
    if not user or not verify_password(form.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password.")
    token = create_access_token(user.id, user.email, user.role)
    refresh_tok = create_refresh_token(user.id)
    return TokenOut(access_token=token, refresh_token=refresh_tok,
                    user={"id": user.id, "name": user.name, "email": user.email, "role": user.role})


@app.post("/auth/refresh", response_model=RefreshOut)
def refresh_session(data: RefreshIn, db: Session = Depends(get_db)):
    """Exchanges a valid refresh token for a new access token and fresh refresh token."""
    user_id = verify_refresh_token(data.refresh_token)
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=401, detail="User account no longer exists.")
    new_token = create_access_token(user.id, user.email, user.role)
    new_refresh = create_refresh_token(user.id)
    return RefreshOut(access_token=new_token, refresh_token=new_refresh)


@app.get("/auth/me")
def me(current: User = Depends(get_current_user)):
    return {"id": current.id, "name": current.name, "email": current.email,
            "role": current.role, "created_at": current.created_at}


@app.get("/health")
def health():
    return {
        "status": "online",
        "model_loaded": model is not None,
        "model_path": MODEL_PATH
    }


# ---------- protected predict ----------
@app.post("/predict", response_model=PredictionResponse)
async def predict(file: UploadFile = File(...),
                  current: User = Depends(get_current_user),
                  db: Session = Depends(get_db)):
    if model is None:
        raise HTTPException(
            status_code=503,
            detail="Model is not loaded. Ensure best_deit.pth exists in backend/models/"
        )

    if not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Uploaded file is not a valid image.")

    try:
        contents = await file.read()
        start_time = time.time()

        # Isolate banknote from background/table & convert to tensor
        input_tensor, cropped_b64, was_cropped = process_banknote_image(contents)

        # Model Inference
        with torch.no_grad():
            outputs = model(input_tensor)
            probs = torch.softmax(outputs, dim=1)[0]
            pred_idx = torch.argmax(probs).item()

        elapsed_ms = (time.time() - start_time) * 1000

        counterfeit_prob = float(probs[0].item())
        genuine_prob = float(probs[1].item())
        predicted_class = CLASS_NAMES[pred_idx]
        confidence = genuine_prob if pred_idx == 1 else counterfeit_prob

        scan = Scan(user_id=current.id, prediction=predicted_class,
                    confidence=round(confidence, 4),
                    genuine_prob=round(genuine_prob, 4),
                    counterfeit_prob=round(counterfeit_prob, 4),
                    latency_ms=round(elapsed_ms, 2), was_cropped=was_cropped)
        db.add(scan)
        db.commit()
        db.refresh(scan)

        return PredictionResponse(
            prediction=predicted_class,
            confidence=round(confidence, 4),
            probabilities={
                "counterfeit": round(counterfeit_prob, 4),
                "genuine": round(genuine_prob, 4)
            },
            inference_time_ms=round(elapsed_ms, 2),
            note_detected_and_cropped=was_cropped,
            cropped_banknote_base64=cropped_b64,
            scan_id=scan.id,
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Inference error: {str(e)}")


# ---------- history ----------
@app.get("/history")
def history(limit: int = Query(20, le=100), current: User = Depends(get_current_user),
            db: Session = Depends(get_db)):
    q = db.query(Scan).filter(Scan.user_id == current.id).order_by(Scan.id.desc()).limit(limit)
    return [{"id": s.id, "prediction": s.prediction, "confidence": s.confidence,
             "genuine_prob": s.genuine_prob, "counterfeit_prob": s.counterfeit_prob,
             "latency_ms": s.latency_ms, "was_cropped": s.was_cropped,
             "created_at": s.created_at} for s in q.all()]


# ---------- admin ----------
@app.get("/admin/overview")
def admin_overview(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
    total = db.query(func.count(Scan.id)).scalar() or 0
    fakes = db.query(func.count(Scan.id)).filter(Scan.prediction == "counterfeit").scalar() or 0
    users = db.query(func.count(User.id)).scalar() or 0
    by_day = db.query(func.date(Scan.created_at).label("d"), func.count(Scan.id))\
               .group_by("d").order_by("d").limit(30).all()
    return {"total_scans": total, "fake_count": fakes,
            "fake_rate": round(fakes / total, 4) if total else 0,
            "total_users": users,
            "by_day": [{"date": str(d), "count": c} for d, c in by_day]}


@app.get("/admin/scans")
def admin_scans(limit: int = Query(50, le=200), admin: User = Depends(require_admin),
                db: Session = Depends(get_db)):
    rows = db.query(Scan).order_by(Scan.id.desc()).limit(limit).all()
    return [{"id": s.id, "user_id": s.user_id, "prediction": s.prediction,
             "confidence": s.confidence, "created_at": s.created_at} for s in rows]


@app.get("/admin/users")
def admin_users(admin: User = Depends(require_admin), db: Session = Depends(get_db)):
    return [{"id": u.id, "name": u.name, "email": u.email, "role": u.role,
             "created_at": u.created_at} for u in db.query(User).order_by(User.id).all()]


@app.patch("/admin/users/{user_id}/role")
def admin_set_role(user_id: int, role: str, admin: User = Depends(require_admin),
                   db: Session = Depends(get_db)):
    if role not in ("user", "staff", "admin"):
        raise HTTPException(status_code=400, detail="Role must be user|staff|admin.")
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        raise HTTPException(status_code=404, detail="User not found.")
    u.role = role
    db.commit()
    return {"id": u.id, "email": u.email, "role": u.role}
