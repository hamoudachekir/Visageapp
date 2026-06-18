"""Backend FastAPI — MVP analyse faciale (âge + sexe).

Périmètre actuel : un seul endpoint `/v1/analyze` qui reçoit la photo de face
capturée par l'app Flutter et renvoie l'âge estimé + le sexe, via InsightFace.

Le reste du plan (profil LLM, RAG, recommandation) viendra plus tard.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from . import vision
from .schemas import AnalyzeResponse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("api")

# Taille max acceptée pour une image (10 Mo) — garde-fou simple.
MAX_IMAGE_BYTES = 10 * 1024 * 1024
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Charge le modèle CV une fois au démarrage (et non par requête)."""
    vision.load_model()
    yield


app = FastAPI(
    title="Analyse faciale — MVP âge & sexe",
    version="0.1.0",
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


@app.post("/v1/analyze", response_model=AnalyzeResponse)
async def analyze(image: UploadFile = File(...)) -> AnalyzeResponse:
    """Reçoit une image (vue de face) -> âge estimé + sexe.

    Côté MVP, seule la vue de face est analysée (choix produit). L'app Flutter
    capture les 4 vues mais n'envoie ici que la photo de face.
    """
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
    # `raw` est en mémoire le temps de la requête puis libéré ; rien n'est écrit sur disque.
    return AnalyzeResponse(**result)
