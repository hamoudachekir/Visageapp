"""Moteur Face++ Skin Analyze : parser vers le schéma unifié + client HTTP."""
from __future__ import annotations

import os

import cv2
import httpx
import numpy as np

from .analyzer import (
    FaceppQuotaError,
    FaceppUnavailableError,
    NoFaceError,
    SkinAnalyzer,
    SkinPhotoResult,
)

FACEPP_ENDPOINT_DEFAULT = "https://api-us.faceplusplus.com/facepp/v1/skinanalyze"

# Face++ skinanalyze rejette les photos haute résolution (INVALID_IMAGE_FACE
# constaté sur un portrait 3356 px alors que 1080 px passe) : les photos de
# téléphone (12 Mpx) échoueraient toutes. On plafonne donc le plus grand côté
# avant l'envoi — valeur validée empiriquement le 2026-07-11.
FACEPP_MAX_SIDE = 1080


def downscale_for_facepp(image_bytes: bytes, max_side: int = FACEPP_MAX_SIDE) -> bytes:
    """Réduit la photo sous `max_side` px (plus grand côté) pour Face++.

    Renvoie les octets d'origine si la photo est déjà assez petite, ou si elle
    n'est pas décodable (la validation qualité en amont — ou Face++ lui-même —
    classifie alors l'erreur).
    """
    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        return image_bytes
    height, width = img.shape[:2]
    longest = max(height, width)
    if longest <= max_side:
        return image_bytes
    scale = max_side / longest
    resized = cv2.resize(img, (round(width * scale), round(height * scale)))
    ok, buf = cv2.imencode(".jpg", resized, [cv2.IMWRITE_JPEG_QUALITY, 92])
    if not ok:
        return image_bytes
    return buf.tobytes()

# Sous-indicateurs de rides -> zone du visage.
WRINKLE_FIELDS = {
    "forehead_wrinkle": "forehead",
    "crows_feet": "eyes",
    "eye_finelines": "eyes",
    "glabella_wrinkle": "glabella",
    "nasolabial_fold": "nasolabial",
}

# Pores par zone.
PORE_FIELDS = {
    "pores_forehead": "forehead",
    "pores_left_cheek": "left_cheek",
    "pores_right_cheek": "right_cheek",
    "pores_jaw": "chin",
}

SKIN_TYPE_MAP = {0: "oily", 1: "dry", 2: "normal", 3: "combination"}


def _indicator_score(field: dict | None) -> int:
    """`{'value': 0|1, 'confidence': c}` -> score 0-100.

    Présent : la confiance devient le score ; absent : plus la confiance est
    haute, plus le score est bas.
    """
    if not field:
        return 0
    confidence = float(field.get("confidence", 0.0))
    present = int(field.get("value", 0)) == 1
    return round(confidence * 100) if present else round((1 - confidence) * 100)


def _present(field: dict | None) -> bool:
    return bool(field) and int(field.get("value", 0)) == 1


def parse_skinanalyze(result: dict) -> SkinPhotoResult:
    """Convertit le bloc `result` de Face++ vers le schéma unifié."""
    scores: dict[str, int] = {}
    zones: dict[str, list[str]] = {}

    scores["wrinkles"] = max(_indicator_score(result.get(f)) for f in WRINKLE_FIELDS)
    wrinkle_zones = [z for f, z in WRINKLE_FIELDS.items() if _present(result.get(f))]
    if wrinkle_zones:
        zones["wrinkles"] = list(dict.fromkeys(wrinkle_zones))

    pore_scores = [_indicator_score(result.get(f)) for f in PORE_FIELDS]
    scores["enlarged_pores"] = round(sum(pore_scores) / len(pore_scores))
    pore_zones = [z for f, z in PORE_FIELDS.items() if _present(result.get(f))]
    if pore_zones:
        zones["enlarged_pores"] = pore_zones

    scores["acne"] = _indicator_score(result.get("acne"))
    scores["blackheads"] = _indicator_score(result.get("blackhead"))
    scores["dark_spots"] = _indicator_score(result.get("skin_spot"))
    scores["dark_circles"] = _indicator_score(result.get("dark_circle"))
    if _present(result.get("dark_circle")):
        zones["dark_circles"] = ["eyes"]

    # Face++ ne renvoie pas les rougeurs : calculées par le moteur local (Phase 2).
    scores["redness"] = 0

    raw_type = (result.get("skin_type") or {}).get("skin_type", 2)
    skin_type = SKIN_TYPE_MAP.get(int(raw_type), "normal")

    return SkinPhotoResult(scores=scores, skin_type=skin_type, zones=zones)


_QUOTA_KEYWORDS = ("LIMIT", "BALANCE", "AUTH")


def _raise_for_facepp_error(error_message: str) -> None:
    """Classe l'erreur Face++ : quota/clés, photo inexploitable, ou autre."""
    upper = error_message.upper()
    if any(keyword in upper for keyword in _QUOTA_KEYWORDS):
        raise FaceppQuotaError(
            "Service d'analyse temporairement indisponible (quota Face++)."
        )
    if "FACE" in upper or "IMAGE" in upper:
        raise NoFaceError("visage non exploitable par le service d'analyse.")
    raise FaceppUnavailableError(f"Erreur du service d'analyse : {error_message}")


class FaceppAnalyzer(SkinAnalyzer):
    """Moteur Phase 1 : API Face++ Skin Analyze (visage frontal requis)."""

    name = "facepp"

    def __init__(
        self,
        api_key: str | None = None,
        api_secret: str | None = None,
        endpoint: str | None = None,
        timeout: float = 10.0,
    ):
        self.api_key = api_key if api_key is not None else os.getenv("FACEPP_API_KEY", "")
        self.api_secret = (
            api_secret if api_secret is not None else os.getenv("FACEPP_API_SECRET", "")
        )
        self.endpoint = endpoint or os.getenv("FACEPP_ENDPOINT", FACEPP_ENDPOINT_DEFAULT)
        self.timeout = timeout

    async def _post(self, image_bytes: bytes) -> httpx.Response:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            return await client.post(
                self.endpoint,
                data={"api_key": self.api_key, "api_secret": self.api_secret},
                files={"image_file": ("photo.jpg", image_bytes, "image/jpeg")},
            )

    async def analyze_photo(self, image_bytes: bytes) -> SkinPhotoResult:
        if not self.api_key or not self.api_secret:
            raise FaceppUnavailableError(
                "Clés Face++ manquantes (FACEPP_API_KEY / FACEPP_API_SECRET)."
            )
        image_bytes = downscale_for_facepp(image_bytes)
        for _attempt in (1, 2):  # 1 essai + 1 retry sur timeout / erreur réseau / 5xx
            try:
                response = await self._post(image_bytes)
            except httpx.TransportError:
                continue
            if response.status_code >= 500:
                continue
            try:
                payload = response.json()
            except ValueError as exc:
                raise FaceppUnavailableError(
                    "Réponse du service d'analyse illisible (corps non JSON)."
                ) from exc
            error_message = payload.get("error_message")
            if error_message:
                _raise_for_facepp_error(error_message)
            result = payload.get("result")
            if result is None:
                raise FaceppUnavailableError("Réponse Face++ sans bloc result.")
            return parse_skinanalyze(result)
        raise FaceppUnavailableError(
            "Service d'analyse injoignable (réseau ou délai, 2 tentatives)."
        )
