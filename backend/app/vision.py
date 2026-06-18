"""Couche Vision — détection visage + âge + sexe (Tier 1).

Port direct de la fonction `analyze_demographics()` du notebook
`tier1_detection_age_sexe_kaggle.ipynb`. Différence clé côté serveur :
le modèle InsightFace `buffalo_l` est chargé **une seule fois** au démarrage
de l'application (cf. note finale du notebook), pas à chaque requête.
"""

from __future__ import annotations

import logging

import cv2
import numpy as np
import onnxruntime as ort
from insightface.app import FaceAnalysis

logger = logging.getLogger("vision")

# Analyseur partagé, initialisé par load_model() au démarrage.
_face_app: FaceAnalysis | None = None


def load_model() -> None:
    """Charge InsightFace buffalo_l une fois pour toute la durée de vie du process."""
    global _face_app
    if _face_app is not None:
        return

    use_gpu = "CUDAExecutionProvider" in ort.get_available_providers()
    providers = (
        ["CUDAExecutionProvider", "CPUExecutionProvider"]
        if use_gpu
        else ["CPUExecutionProvider"]
    )
    logger.info("Chargement InsightFace buffalo_l (GPU=%s)…", use_gpu)

    app = FaceAnalysis(name="buffalo_l", providers=providers)
    app.prepare(ctx_id=0 if use_gpu else -1, det_size=(640, 640))
    _face_app = app
    logger.info("InsightFace prêt.")


def _decode_image(raw: bytes) -> np.ndarray:
    """Décode des octets d'image en BGR (format attendu par InsightFace)."""
    arr = np.frombuffer(raw, dtype=np.uint8)
    img_bgr = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img_bgr is None:
        raise ValueError("image_illisible")
    return img_bgr


def analyze_demographics(raw: bytes) -> dict:
    """Analyse une image (octets) -> dict structuré (1er visage = principal).

    Reprend la sortie de la fonction homonyme du notebook, en y ajoutant le
    score de confiance du visage principal.
    """
    if _face_app is None:
        raise RuntimeError("Modèle non chargé : appeler load_model() au démarrage.")

    img_bgr = _decode_image(raw)
    faces = _face_app.get(img_bgr)

    if not faces:
        return {"ok": False, "raison": "aucun_visage_detecte", "nb_visages": 0}

    # Visage principal = le plus grand (le plus proche de la caméra).
    def _area(f) -> float:
        x1, y1, x2, y2 = f.bbox
        return float((x2 - x1) * (y2 - y1))

    principal = max(faces, key=_area)
    # f.gender : 1 = homme, 0 = femme ; f.age : entier
    sexe = "Homme" if int(principal.gender) == 1 else "Femme"

    return {
        "ok": True,
        "moteur": "insightface",
        "nb_visages": len(faces),
        "confiance": float(principal.det_score),
        "demographics": {
            "age_estime": int(principal.age),
            "sexe": sexe,
        },
    }
