"""Route POST /v1/skin/analyze — analyse de peau 4 photos + recommandations.

Conformité RGPD : les photos sont traitées en mémoire et jamais persistées ;
seuls les résultats JSON sont stockés dans skin_analyses.
"""
from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from .. import auth as auth_module
from ..db import get_db
from ..models import Client, Pharmacy, SkinAnalysis
from . import engine as engine_mod
from . import quality
from .aggregate import aggregate
from .analyzer import (
    EngineUnavailableError,
    FaceppQuotaError,
    FrontPhotoFailedError,
)
from .labels import DISCLAIMER_FR, LABELS_FR, severity
from .recommend import build_recommendations, fetch_mappings, fetch_products
from .schemas import ConditionOut, RecommendationOut, SkinAnalyzeResponse

logger = logging.getLogger("skin")

router = APIRouter(tags=["skin"])

MAX_IMAGE_BYTES = 10 * 1024 * 1024
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}


@router.post("/v1/skin/analyze", response_model=SkinAnalyzeResponse)
async def analyze_skin(
    front: UploadFile = File(...),
    left: UploadFile = File(...),
    right: UploadFile = File(...),
    closeup: UploadFile = File(...),
    client_id: int | None = Form(default=None),
    pharmacy: Pharmacy = Depends(auth_module.get_current_pharmacy),
    db: Session = Depends(get_db),
) -> SkinAnalyzeResponse:
    """Analyse les 4 photos et renvoie conditions + recommandations produits."""
    if client_id is not None:
        client = db.get(Client, client_id)
        if client is None or client.pharmacy_id != pharmacy.id:
            raise HTTPException(status_code=404, detail="Client introuvable")

    photos: dict[str, bytes] = {}
    uploads = {"front": front, "left": left, "right": right, "closeup": closeup}
    for name, upload in uploads.items():
        if upload.content_type not in ALLOWED_CONTENT_TYPES:
            raise HTTPException(
                status_code=415,
                detail=f"{name} : type non supporté ({upload.content_type}).",
            )
        raw = await upload.read()
        if not raw:
            raise HTTPException(status_code=400, detail=f"{name} : image vide.")
        if len(raw) > MAX_IMAGE_BYTES:
            raise HTTPException(
                status_code=413, detail=f"{name} : image trop volumineuse (max 10 Mo)."
            )
        try:
            quality.validate_photo(raw, name)
        except quality.PhotoQualityError as exc:
            raise HTTPException(status_code=422, detail=exc.message_fr) from exc
        photos[name] = raw

    try:
        run = await engine_mod.run_analysis(photos)
    except FrontPhotoFailedError as exc:
        raise HTTPException(status_code=422, detail=exc.message_fr) from exc
    except FaceppQuotaError as exc:
        raise HTTPException(status_code=502, detail=exc.message_fr) from exc
    except EngineUnavailableError as exc:
        raise HTTPException(status_code=502, detail=exc.message_fr) from exc

    scores, skin_type, zones = aggregate(run.results)

    mappings = fetch_mappings(db, list(scores) + [f"skin_type_{skin_type}"])
    products = fetch_products(db, [m["product_id"] for m in mappings])
    recommendations = build_recommendations(scores, skin_type, mappings, products)

    analysis = SkinAnalysis(
        pharmacy_id=pharmacy.id,
        client_id=client_id,
        skin_type=skin_type,
        results_json={
            "scores": scores,
            "zones": zones,
            "engine": run.engine,
            "photo_status": run.photo_status,
        },
    )
    db.add(analysis)
    db.commit()
    db.refresh(analysis)

    conditions = [
        ConditionOut(
            code=code,
            label_fr=LABELS_FR[code],
            score=score,
            severity=severity(score),
            zones=zones.get(code, []),
        )
        for code, score in sorted(scores.items(), key=lambda kv: -kv[1])
    ]
    recs = [
        RecommendationOut(
            product_id=r.product_id,
            name=r.name,
            brand=r.brand,
            price=r.price,
            image_url=r.image_url,
            reason_fr=r.reason_fr,
            matched_conditions=r.matched_conditions,
        )
        for r in recommendations
    ]
    return SkinAnalyzeResponse(
        analysis_id=analysis.id,
        skin_type=skin_type,
        conditions=conditions,
        recommendations=recs,
        disclaimer_fr=DISCLAIMER_FR,
    )
