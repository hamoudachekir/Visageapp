"""Backend FastAPI — Lumina (analyse faciale + auth pharmacie multi-tenant).

Endpoints :
- `/v1/analyze`        : photo de face -> âge estimé + sexe (InsightFace).
- `/v1/auth/login`     : email + mot de passe -> JWT.
- `/v1/auth/me`        : pharmacie courante (protégé).
- `/v1/clients`        : recherche / création de clients, scopés par pharmacie.
"""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, File, HTTPException, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session

from . import auth as auth_module
from . import vision
from .db import Base, engine, get_db
from .models import Client, Diagnostic, Pharmacy
from .schemas import (
    AnalyzeResponse,
    ClientIn,
    ClientOut,
    DiagnosticIn,
    DiagnosticOut,
    LoginRequest,
    LoginResponse,
    PharmacyOut,
    PharmacyUpdate,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("api")

# Taille max acceptée pour une image (10 Mo) — garde-fou simple.
MAX_IMAGE_BYTES = 10 * 1024 * 1024
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Crée les tables et charge le modèle CV au démarrage.

    Le chargement du modèle est tolérant aux pannes : si InsightFace n'est pas
    disponible (poids absents en local), l'API démarre quand même pour servir
    l'authentification et la gestion des clients.
    """
    Base.metadata.create_all(bind=engine)
    if os.getenv("SKIP_VISION") == "1":
        logger.warning("SKIP_VISION=1 — modèle CV non chargé (auth/clients seuls).")
    else:
        try:
            vision.load_model()
        except Exception:  # pragma: no cover - dépend de l'environnement local
            logger.exception("Modèle CV indisponible — /v1/analyze sera dégradé.")
    yield


app = FastAPI(
    title="Lumina — analyse faciale & auth pharmacie",
    version="0.2.0",
    lifespan=lifespan,
)

# CORS large pour le dev mobile/web. À restreindre en production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health() -> dict:
    """Sonde de disponibilité."""
    return {"status": "ok"}


# ───────────────────────── Authentification ─────────────────────────


@app.post("/v1/auth/login", response_model=LoginResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)) -> LoginResponse:
    """Vérifie les identifiants et renvoie un JWT + l'identité de la pharmacie."""
    pharmacy = (
        db.query(Pharmacy).filter(Pharmacy.email == payload.email.strip()).first()
    )
    if pharmacy is None or not auth_module.verify_password(
        payload.password, pharmacy.password_hash
    ):
        raise HTTPException(status_code=401, detail="Email ou mot de passe incorrect")
    token = auth_module.create_token(pharmacy.id)
    return LoginResponse(token=token, pharmacy=PharmacyOut.from_pharmacy(pharmacy))


@app.get("/v1/auth/me", response_model=PharmacyOut)
def me(pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy)) -> PharmacyOut:
    """Renvoie la pharmacie associée au token (utile pour valider une session)."""
    return PharmacyOut.from_pharmacy(pharmacy)


@app.patch("/v1/pharmacy", response_model=PharmacyOut)
def update_pharmacy(
    payload: PharmacyUpdate,
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> PharmacyOut:
    """Met à jour les champs de profil fournis (les autres restent inchangés)."""
    data = payload.model_dump(exclude_unset=True)
    if "nom" in data and (data["nom"] is None or not data["nom"].strip()):
        raise HTTPException(status_code=422, detail="Le nom ne peut pas être vide.")
    for field, value in data.items():
        setattr(pharmacy, field, value.strip() if isinstance(value, str) else value)
    db.commit()
    db.refresh(pharmacy)
    return PharmacyOut.from_pharmacy(pharmacy)


MAX_LOGO_BYTES = 2 * 1024 * 1024  # 2 Mo — garde-fou logo


@app.post("/v1/pharmacy/logo", response_model=PharmacyOut)
async def upload_logo(
    image: UploadFile = File(...),
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> PharmacyOut:
    """Téléverse / remplace le logo (stocké en octets dans la base)."""
    if image.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=415,
            detail=f"Type non supporté : {image.content_type}.",
        )
    raw = await image.read()
    if not raw:
        raise HTTPException(status_code=400, detail="Image vide.")
    if len(raw) > MAX_LOGO_BYTES:
        raise HTTPException(status_code=413, detail="Logo trop volumineux (max 2 Mo).")
    pharmacy.logo_bytes = raw
    pharmacy.logo_mime = image.content_type
    db.commit()
    db.refresh(pharmacy)
    return PharmacyOut.from_pharmacy(pharmacy)


@app.get("/v1/pharmacy/logo")
def get_logo(
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
) -> Response:
    """Renvoie les octets du logo de la pharmacie courante (404 si absent)."""
    if pharmacy.logo_bytes is None:
        raise HTTPException(status_code=404, detail="Aucun logo.")
    return Response(
        content=pharmacy.logo_bytes,
        media_type=pharmacy.logo_mime or "image/png",
    )


@app.delete("/v1/pharmacy/logo", response_model=PharmacyOut)
def delete_logo(
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> PharmacyOut:
    """Supprime le logo."""
    pharmacy.logo_bytes = None
    pharmacy.logo_mime = None
    db.commit()
    db.refresh(pharmacy)
    return PharmacyOut.from_pharmacy(pharmacy)


# ───────────────────────── Clients (scopés par pharmacie) ─────────────────────────


@app.get("/v1/clients", response_model=list[ClientOut])
def list_clients(
    telephone: str | None = None,
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> list[Client]:
    """Liste / recherche les clients de LA pharmacie courante uniquement."""
    query = db.query(Client).filter(Client.pharmacy_id == pharmacy.id)
    if telephone:
        query = query.filter(Client.telephone == telephone.strip())
    return query.order_by(Client.created_at.desc()).all()


@app.post("/v1/clients", response_model=ClientOut, status_code=201)
def create_client(
    payload: ClientIn,
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> Client:
    """Crée un client rattaché à la pharmacie courante (jamais à une autre)."""
    client = Client(
        pharmacy_id=pharmacy.id,
        prenom=payload.prenom.strip(),
        nom=payload.nom.strip(),
        telephone=payload.telephone.strip(),
        email=payload.email,
        peau_sensible=payload.peau_sensible,
    )
    db.add(client)
    db.commit()
    db.refresh(client)
    return client


# ───────────────────────── Diagnostics (questionnaire + analyse) ─────────────────────────


def _owned_client_or_404(client_id: int, pharmacy: Pharmacy, db: Session) -> Client:
    """Renvoie le client s'il appartient à la pharmacie du token, sinon 404."""
    client = db.get(Client, client_id)
    if client is None or client.pharmacy_id != pharmacy.id:
        raise HTTPException(status_code=404, detail="Client introuvable")
    return client


@app.post("/v1/diagnostics", response_model=DiagnosticOut, status_code=201)
def create_diagnostic(
    payload: DiagnosticIn,
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> Diagnostic:
    """Enregistre les réponses du questionnaire pour un client de la pharmacie."""
    _owned_client_or_404(payload.client_id, pharmacy, db)
    diagnostic = Diagnostic(
        client_id=payload.client_id,
        pharmacy_id=pharmacy.id,
        type_peau=payload.type_peau,
        tendance_acneique=payload.tendance_acneique,
        sensibilite_cutanee=payload.sensibilite_cutanee,
    )
    db.add(diagnostic)
    db.commit()
    db.refresh(diagnostic)
    return diagnostic


@app.get("/v1/clients/{client_id}/diagnostics", response_model=list[DiagnosticOut])
def list_diagnostics(
    client_id: int,
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> list[Diagnostic]:
    """Historique des visites d'un client (le plus récent d'abord)."""
    _owned_client_or_404(client_id, pharmacy, db)
    return (
        db.query(Diagnostic)
        .filter(Diagnostic.client_id == client_id)
        .order_by(Diagnostic.created_at.desc())
        .all()
    )


# ───────────────────────── Analyse faciale ─────────────────────────


@app.post("/v1/analyze", response_model=AnalyzeResponse)
async def analyze(image: UploadFile = File(...)) -> AnalyzeResponse:
    """Reçoit une image (vue de face) -> âge estimé + sexe."""
    if image.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=415,
            detail=f"Type non supporté : {image.content_type}. "
            f"Attendu : {sorted(ALLOWED_CONTENT_TYPES)}.",
        )

    raw = await image.read()
    if not raw:
        raise HTTPException(status_code=400, detail="Image vide.")
    if len(raw) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Image trop volumineuse (max 10 Mo).")

    try:
        result = vision.analyze_demographics(raw)
    except ValueError as exc:  # image illisible / corrompue
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:  # pragma: no cover - garde-fou inférence
        logger.exception("Échec de l'analyse")
        raise HTTPException(status_code=500, detail="Échec de l'analyse.") from exc

    # Conformité RGPD (plan §8.2) : on ne conserve jamais l'image brute.
    return AnalyzeResponse(**result)
