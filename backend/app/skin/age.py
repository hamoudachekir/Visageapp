"""Estimation d'âge & « âge de la peau ».

Partie pure (Task 1) : parser Face++ Detect, âge réel depuis la date de
naissance, messages FR. Les estimateurs (Face++ / InsightFace) et la façade
`estimate_age` arrivent en Task 2 dans ce même fichier.

`estimated_age` est une **estimation** IA — jamais présentée comme exacte.
"""
from __future__ import annotations

import logging
import os
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import date

import httpx

from .. import vision
from .analyzer import (
    EngineUnavailableError,
    FaceppUnavailableError,
    NoFaceError,
    SkinEngineError,
)
from .facepp import _raise_for_facepp_error, downscale_for_facepp

logger = logging.getLogger("skin.age")

FACEPP_DETECT_ENDPOINT_DEFAULT = "https://api-us.faceplusplus.com/facepp/v3/detect"

GENDER_FR = {"Male": "Homme", "Female": "Femme"}


@dataclass
class AgeEstimate:
    """Résultat d'un estimateur : âge (estimation) + sexe éventuel."""

    age: int
    sexe: str | None = None


def parse_detect(payload: dict) -> AgeEstimate:
    """Convertit la réponse Face++ Detect (v3) en AgeEstimate.

    Plusieurs visages : on prend le plus grand (la validation qualité amont
    rejette déjà le multi-visages quand le modèle CV local est chargé).
    """
    faces = payload.get("faces") or []
    if not faces:
        raise NoFaceError("aucun visage détecté (estimation d'âge).")

    def _area(face: dict) -> int:
        rect = face.get("face_rectangle") or {}
        return int(rect.get("width", 0)) * int(rect.get("height", 0))

    face = max(faces, key=_area)
    attributes = face.get("attributes") or {}
    age_value = (attributes.get("age") or {}).get("value")
    if age_value is None:
        raise NoFaceError("attributs d'âge absents (estimation d'âge).")
    gender_value = (attributes.get("gender") or {}).get("value")
    return AgeEstimate(age=int(age_value), sexe=GENDER_FR.get(gender_value))


def real_age_from_birth_date(birth_date: date, today: date | None = None) -> int:
    """Âge révolu à la date du jour (anniversaire pris en compte)."""
    today = today or date.today()
    return (
        today.year
        - birth_date.year
        - ((today.month, today.day) < (birth_date.month, birth_date.day))
    )


def skin_age_message_fr(delta: int) -> str:
    """Message marketing selon l'écart âge estimé − âge réel."""
    if delta <= -3:
        return f"Votre peau paraît {abs(delta)} ans plus jeune que votre âge !"
    if delta >= 3:
        return f"Votre peau paraît {delta} ans de plus — voici des soins ciblés."
    return "Votre peau correspond à votre âge."


class AgeEstimator(ABC):
    """Interface commune des estimateurs d'âge (Face++ / local)."""

    name: str = "abstract"

    @abstractmethod
    async def estimate(self, image_bytes: bytes) -> AgeEstimate:
        """Estime l'âge. Lève NoFaceError ou EngineUnavailableError."""


class FaceppAgeEstimator(AgeEstimator):
    """Primaire : Face++ Detect v3 avec return_attributes=age,gender."""

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
        self.endpoint = endpoint or os.getenv(
            "FACEPP_DETECT_ENDPOINT", FACEPP_DETECT_ENDPOINT_DEFAULT
        )
        self.timeout = timeout

    async def _post(self, image_bytes: bytes) -> httpx.Response:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            return await client.post(
                self.endpoint,
                data={
                    "api_key": self.api_key,
                    "api_secret": self.api_secret,
                    "return_attributes": "age,gender",
                },
                files={"image_file": ("photo.jpg", image_bytes, "image/jpeg")},
            )

    async def estimate(self, image_bytes: bytes) -> AgeEstimate:
        if not self.api_key or not self.api_secret:
            raise FaceppUnavailableError(
                "Clés Face++ manquantes (FACEPP_API_KEY / FACEPP_API_SECRET)."
            )
        image_bytes = downscale_for_facepp(image_bytes)
        for _attempt in (1, 2):  # même politique de retry que le module peau
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
            return parse_detect(payload)
        raise FaceppUnavailableError(
            "Service d'estimation d'âge injoignable (réseau ou délai, 2 tentatives)."
        )


class LocalAgeEstimator(AgeEstimator):
    """Repli : InsightFace déjà chargé (vision.analyze_demographics)."""

    name = "local"

    async def estimate(self, image_bytes: bytes) -> AgeEstimate:
        try:
            result = vision.analyze_demographics(image_bytes)
        except RuntimeError as exc:  # modèle CV non chargé
            raise EngineUnavailableError(
                "Estimation d'âge locale indisponible (modèle CV non chargé)."
            ) from exc
        except ValueError as exc:  # image illisible
            raise NoFaceError("image illisible (estimation d'âge locale).") from exc
        if not result.get("ok"):
            raise NoFaceError("aucun visage détecté (estimation d'âge locale).")
        demographics = result.get("demographics") or {}
        return AgeEstimate(
            age=int(demographics.get("age_estime", 0)),
            sexe=demographics.get("sexe"),
        )


_MODES = {"facepp": ["facepp"], "local": ["local"], "auto": ["facepp", "local"]}


def _make_estimator(name: str) -> AgeEstimator:
    if name == "facepp":
        return FaceppAgeEstimator()
    if name == "local":
        return LocalAgeEstimator()
    raise EngineUnavailableError(f"Moteur d'âge inconnu : {name}")


async def estimate_age(
    front_bytes: bytes, mode: str | None = None
) -> tuple[AgeEstimate | None, str | None]:
    """Estime l'âge sur la photo de face. N'échoue jamais : (None, None) au pire."""
    mode = mode or os.getenv("ANALYSIS_ENGINE", "facepp")
    for engine_name in _MODES.get(mode, ["facepp"]):
        try:
            estimator = _make_estimator(engine_name)
            return await estimator.estimate(front_bytes), estimator.name
        except SkinEngineError as exc:
            logger.warning(
                "Estimation d'âge (%s) échouée : %s", engine_name, exc.message_fr
            )
        except Exception:  # garde-fou : l'âge ne doit jamais casser l'analyse peau
            logger.exception("Estimation d'âge (%s) : erreur inattendue", engine_name)
    return None, None
