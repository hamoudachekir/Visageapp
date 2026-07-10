"""Validation qualité d'une photo avant analyse : lisibilité, luminosité, flou, visages.

Le comptage de visages réutilise InsightFace chargé au démarrage (vision.py) ;
si le modèle n'est pas disponible, cette vérification est sautée.
"""
from __future__ import annotations

import os

import cv2
import numpy as np

from .. import vision


class PhotoQualityError(ValueError):
    """Photo rejetée — porte un message FR affichable (préfixé du nom de la photo)."""

    def __init__(self, message_fr: str):
        super().__init__(message_fr)
        self.message_fr = message_fr


BRIGHTNESS_MIN = 40.0
BRIGHTNESS_MAX = 220.0


def _blur_threshold() -> float:
    return float(os.getenv("SKIN_BLUR_THRESHOLD", "60"))


def validate_photo(raw: bytes, photo_name: str) -> None:
    """Lève PhotoQualityError si la photo est inutilisable pour l'analyse."""
    arr = np.frombuffer(raw, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise PhotoQualityError(f"{photo_name} : image illisible.")

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    brightness = float(gray.mean())
    if brightness < BRIGHTNESS_MIN:
        raise PhotoQualityError(f"{photo_name} : photo trop sombre.")
    if brightness > BRIGHTNESS_MAX:
        raise PhotoQualityError(f"{photo_name} : photo surexposée.")

    blur = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    if blur < _blur_threshold():
        raise PhotoQualityError(f"{photo_name} : photo floue.")

    nb_faces = vision.count_faces(img)
    if nb_faces is None:
        return  # modèle CV non chargé : vérification visage sautée
    if nb_faces == 0:
        raise PhotoQualityError(f"{photo_name} : aucun visage détecté.")
    if nb_faces > 1:
        raise PhotoQualityError(f"{photo_name} : plusieurs visages détectés.")
