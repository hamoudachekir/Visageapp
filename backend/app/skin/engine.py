"""Façade des moteurs : sélection ANALYSIS_ENGINE (facepp | local | auto).

`auto` essaie Face++ puis se replie sur le moteur local si Face++ est
indisponible (quota, clés, réseau). Défaut Phase 1 : `facepp` — le repli
local ne sait noter que rougeurs + type de peau tant que les poids YOLO ne
sont pas entraînés.
"""
from __future__ import annotations

import os
from dataclasses import dataclass

from .analyzer import (
    EngineUnavailableError,
    FrontPhotoFailedError,
    NoFaceError,
    SkinAnalyzer,
    SkinPhotoResult,
)
from .facepp import FaceppAnalyzer

FRONT_KEY = "front"

_MODES = {"facepp": ["facepp"], "local": ["local"], "auto": ["facepp", "local"]}


@dataclass
class EngineRunResult:
    """Résultats par photo + statut par photo + moteur effectivement utilisé."""

    results: dict[str, SkinPhotoResult]
    photo_status: dict[str, str]  # "ok" ou message FR d'échec
    engine: str


def _make(name: str) -> SkinAnalyzer:
    if name == "facepp":
        return FaceppAnalyzer()
    if name == "local":
        try:
            from .local import LocalAnalyzer  # import paresseux (deps Phase 2)
        except ImportError as exc:
            raise EngineUnavailableError(
                "Moteur local indisponible (installer requirements-phase2.txt)."
            ) from exc
        return LocalAnalyzer()
    raise EngineUnavailableError(f"Moteur inconnu : {name}")


async def _run_with(
    analyzer: SkinAnalyzer, photos: dict[str, bytes]
) -> EngineRunResult:
    """Analyse chaque photo ; seule l'échec de la photo de face est bloquant."""
    results: dict[str, SkinPhotoResult] = {}
    status: dict[str, str] = {}
    for name, raw in photos.items():
        try:
            results[name] = await analyzer.analyze_photo(raw)
            status[name] = "ok"
        except NoFaceError as exc:
            if name == FRONT_KEY:
                raise FrontPhotoFailedError(exc.message_fr) from exc
            status[name] = exc.message_fr
    if FRONT_KEY not in results:
        raise FrontPhotoFailedError("front : photo de face manquante.")
    return EngineRunResult(results=results, photo_status=status, engine=analyzer.name)


async def run_analysis(
    photos: dict[str, bytes], mode: str | None = None
) -> EngineRunResult:
    """Point d'entrée du module : applique ANALYSIS_ENGINE et le repli éventuel."""
    mode = mode or os.getenv("ANALYSIS_ENGINE", "facepp")
    if mode not in _MODES:
        raise EngineUnavailableError(f"ANALYSIS_ENGINE invalide : {mode}")
    last_error: EngineUnavailableError | None = None
    for engine_name in _MODES[mode]:
        try:
            return await _run_with(_make(engine_name), photos)
        except EngineUnavailableError as exc:
            last_error = exc
    assert last_error is not None
    raise last_error
