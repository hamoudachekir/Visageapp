"""Tests de la façade moteur : tolérance par photo, repli auto, erreurs."""
import pytest

from app.skin import engine
from app.skin.analyzer import (
    CONDITION_CODES,
    FaceppQuotaError,
    FrontPhotoFailedError,
    NoFaceError,
    SkinAnalyzer,
    SkinPhotoResult,
)

PHOTOS = {name: name.encode() for name in ["front", "left", "right", "closeup"]}


def _result(skin_type: str = "oily") -> SkinPhotoResult:
    return SkinPhotoResult(
        scores={c: 10 for c in CONDITION_CODES}, skin_type=skin_type
    )


class FakeAnalyzer(SkinAnalyzer):
    name = "fake"

    def __init__(self, no_face: set[str] = frozenset(), fatal: Exception | None = None):
        self.no_face = set(no_face)
        self.fatal = fatal

    async def analyze_photo(self, image_bytes: bytes) -> SkinPhotoResult:
        if self.fatal is not None:
            raise self.fatal
        key = image_bytes.decode()
        if key in self.no_face:
            raise NoFaceError(f"{key} : visage non exploitable.")
        return _result()


async def test_profil_echoue_tolere(monkeypatch):
    monkeypatch.setattr(engine, "_make", lambda name: FakeAnalyzer(no_face={"left"}))
    run = await engine.run_analysis(PHOTOS, mode="facepp")
    assert "left" not in run.results
    assert len(run.results) == 3
    assert "visage non exploitable" in run.photo_status["left"]
    assert run.photo_status["front"] == "ok"


async def test_front_echoue_erreur(monkeypatch):
    monkeypatch.setattr(engine, "_make", lambda name: FakeAnalyzer(no_face={"front"}))
    with pytest.raises(FrontPhotoFailedError):
        await engine.run_analysis(PHOTOS, mode="facepp")


async def test_auto_replie_sur_le_second_moteur(monkeypatch):
    def make(name: str):
        if name == "facepp":
            return FakeAnalyzer(fatal=FaceppQuotaError("quota épuisé"))
        return FakeAnalyzer()

    monkeypatch.setattr(engine, "_make", make)
    run = await engine.run_analysis(PHOTOS, mode="auto")
    assert run.engine == "fake"
    assert len(run.results) == 4


async def test_facepp_seul_remonte_le_quota(monkeypatch):
    monkeypatch.setattr(
        engine, "_make", lambda name: FakeAnalyzer(fatal=FaceppQuotaError("quota"))
    )
    with pytest.raises(FaceppQuotaError):
        await engine.run_analysis(PHOTOS, mode="facepp")
