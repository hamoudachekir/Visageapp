"""Tests de l'estimation d'âge : parser Face++ Detect (Task 1) + moteurs (Task 2)."""
import pytest

from app.skin.age import AgeEstimate, parse_detect
from app.skin.analyzer import NoFaceError

DETECT_ONE_FACE = {
    "faces": [
        {
            "face_rectangle": {"width": 200, "height": 220, "top": 10, "left": 10},
            "attributes": {
                "age": {"value": 32},
                "gender": {"value": "Male"},
            },
        }
    ]
}

DETECT_TWO_FACES = {
    "faces": [
        {
            "face_rectangle": {"width": 80, "height": 90},
            "attributes": {"age": {"value": 60}, "gender": {"value": "Female"}},
        },
        {
            "face_rectangle": {"width": 300, "height": 320},
            "attributes": {"age": {"value": 25}, "gender": {"value": "Female"}},
        },
    ]
}


def test_parse_un_visage():
    estimate = parse_detect(DETECT_ONE_FACE)
    assert estimate == AgeEstimate(age=32, sexe="Homme")


def test_parse_plusieurs_visages_prend_le_plus_grand():
    estimate = parse_detect(DETECT_TWO_FACES)
    assert estimate.age == 25
    assert estimate.sexe == "Femme"


def test_parse_aucun_visage():
    with pytest.raises(NoFaceError):
        parse_detect({"faces": []})
    with pytest.raises(NoFaceError):
        parse_detect({})


def test_parse_attributs_absents():
    with pytest.raises(NoFaceError):
        parse_detect({"faces": [{"face_rectangle": {"width": 200, "height": 200}}]})


import httpx

from app.skin import age as age_mod
from app.skin.age import (
    FaceppAgeEstimator,
    LocalAgeEstimator,
    estimate_age,
)
from app.skin.analyzer import EngineUnavailableError, FaceppQuotaError


def _response(payload: dict, status: int = 200) -> httpx.Response:
    return httpx.Response(
        status, json=payload, request=httpx.Request("POST", "https://facepp.test")
    )


async def test_facepp_estimator_ok(monkeypatch):
    estimator = FaceppAgeEstimator(api_key="k", api_secret="s")

    async def fake_post(image_bytes):
        return _response(DETECT_ONE_FACE)

    monkeypatch.setattr(estimator, "_post", fake_post)
    estimate = await estimator.estimate(b"x")
    assert estimate.age == 32


async def test_facepp_estimator_quota(monkeypatch):
    estimator = FaceppAgeEstimator(api_key="k", api_secret="s")

    async def fake_post(image_bytes):
        return _response({"error_message": "CONCURRENCY_LIMIT_EXCEEDED"}, status=403)

    monkeypatch.setattr(estimator, "_post", fake_post)
    with pytest.raises(FaceppQuotaError):
        await estimator.estimate(b"x")


async def test_facepp_estimator_reseau_deux_tentatives(monkeypatch):
    estimator = FaceppAgeEstimator(api_key="k", api_secret="s")
    calls: list[int] = []

    async def fake_post(image_bytes):
        calls.append(1)
        raise httpx.ConnectTimeout("boom")

    monkeypatch.setattr(estimator, "_post", fake_post)
    with pytest.raises(Exception):
        await estimator.estimate(b"x")
    assert len(calls) == 2


async def test_local_estimator_ok(monkeypatch):
    monkeypatch.setattr(
        "app.skin.age.vision",
        type(
            "FakeVision",
            (),
            {
                "analyze_demographics": staticmethod(
                    lambda raw: {
                        "ok": True,
                        "demographics": {"age_estime": 41, "sexe": "Femme"},
                    }
                )
            },
        ),
    )
    estimate = await LocalAgeEstimator().estimate(b"x")
    assert estimate.age == 41
    assert estimate.sexe == "Femme"


async def test_local_estimator_modele_non_charge(monkeypatch):
    def boom(raw):
        raise RuntimeError("Modèle non chargé")

    monkeypatch.setattr(
        "app.skin.age.vision",
        type("FakeVision", (), {"analyze_demographics": staticmethod(boom)}),
    )
    with pytest.raises(EngineUnavailableError):
        await LocalAgeEstimator().estimate(b"x")


async def test_estimate_age_absorbe_les_echecs(monkeypatch):
    class FailingEstimator:
        name = "fake"

        async def estimate(self, image_bytes):
            raise FaceppQuotaError("quota")

    monkeypatch.setattr(age_mod, "_make_estimator", lambda name: FailingEstimator())
    estimate, engine = await estimate_age(b"x", mode="facepp")
    assert estimate is None and engine is None


async def test_estimate_age_auto_replie_sur_local(monkeypatch):
    class Quota:
        name = "facepp"

        async def estimate(self, image_bytes):
            raise FaceppQuotaError("quota")

    class Ok:
        name = "local"

        async def estimate(self, image_bytes):
            return AgeEstimate(age=30)

    monkeypatch.setattr(
        age_mod, "_make_estimator", lambda name: Quota() if name == "facepp" else Ok()
    )
    estimate, engine = await estimate_age(b"x", mode="auto")
    assert estimate.age == 30
    assert engine == "local"
