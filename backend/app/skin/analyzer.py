"""Contrat commun des moteurs d'analyse de peau (Phase 1 Face++, Phase 2 local)."""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field

# Les 7 conditions analysées, scores 0-100.
CONDITION_CODES = [
    "wrinkles",
    "dark_circles",
    "blackheads",
    "enlarged_pores",
    "dark_spots",
    "redness",
    "acne",
]

SKIN_TYPES = ["oily", "dry", "combination", "normal"]


class SkinEngineError(Exception):
    """Erreur moteur porteuse d'un message FR affichable."""

    def __init__(self, message_fr: str):
        super().__init__(message_fr)
        self.message_fr = message_fr


class EngineUnavailableError(SkinEngineError):
    """Le moteur ne peut pas fonctionner (quota, clés, dépendances) -> repli/502."""


class FaceppQuotaError(EngineUnavailableError):
    """Quota / authentification Face++ épuisés ou invalides."""


class FaceppUnavailableError(EngineUnavailableError):
    """Face++ injoignable (timeout, 5xx, réponse invalide)."""


class NoFaceError(SkinEngineError):
    """La photo n'est pas exploitable (pas de visage frontal, image invalide)."""


class FrontPhotoFailedError(SkinEngineError):
    """La photo de face (obligatoire) n'a pas pu être analysée -> 422."""


@dataclass
class SkinPhotoResult:
    """Résultat unifié pour UNE photo."""

    scores: dict[str, int]  # condition_code -> 0..100
    skin_type: str  # oily | dry | combination | normal
    zones: dict[str, list[str]] = field(default_factory=dict)


class SkinAnalyzer(ABC):
    """Interface commune aux moteurs (Face++ / local)."""

    name: str = "abstract"

    @abstractmethod
    async def analyze_photo(self, image_bytes: bytes) -> SkinPhotoResult:
        """Analyse une photo. Lève NoFaceError ou EngineUnavailableError."""
