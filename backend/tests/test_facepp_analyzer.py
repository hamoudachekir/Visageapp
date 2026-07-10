"""Tests du client Face++ (API mockée via _post, aucun appel réseau)."""
import httpx
import pytest

from app.skin.analyzer import FaceppQuotaError, FaceppUnavailableError, NoFaceError
from app.skin.facepp import FaceppAnalyzer
from samples import FACEPP_SAMPLE_RESULT


def _response(payload: dict, status: int = 200) -> httpx.Response:
    return httpx.Response(
        status, json=payload, request=httpx.Request("POST", "https://facepp.test")
    )


def _analyzer() -> FaceppAnalyzer:
    return FaceppAnalyzer(api_key="k", api_secret="s")


async def test_cles_absentes():
    analyzer = FaceppAnalyzer(api_key="", api_secret="")
    with pytest.raises(FaceppUnavailableError):
        await analyzer.analyze_photo(b"x")


async def test_quota_epuise(monkeypatch):
    analyzer = _analyzer()

    async def fake_post(image_bytes):
        return _response({"error_message": "CONCURRENCY_LIMIT_EXCEEDED"}, status=403)

    monkeypatch.setattr(analyzer, "_post", fake_post)
    with pytest.raises(FaceppQuotaError):
        await analyzer.analyze_photo(b"x")


async def test_pas_de_visage(monkeypatch):
    analyzer = _analyzer()

    async def fake_post(image_bytes):
        return _response({"error_message": "NO_FACE_FOUND"}, status=400)

    monkeypatch.setattr(analyzer, "_post", fake_post)
    with pytest.raises(NoFaceError):
        await analyzer.analyze_photo(b"x")


async def test_reponse_valide(monkeypatch):
    analyzer = _analyzer()

    async def fake_post(image_bytes):
        return _response({"result": FACEPP_SAMPLE_RESULT})

    monkeypatch.setattr(analyzer, "_post", fake_post)
    result = await analyzer.analyze_photo(b"x")
    assert result.scores["acne"] == 62
    assert result.skin_type == "oily"


async def test_timeout_deux_tentatives(monkeypatch):
    analyzer = _analyzer()
    calls: list[int] = []

    async def fake_post(image_bytes):
        calls.append(1)
        raise httpx.ConnectTimeout("boom")

    monkeypatch.setattr(analyzer, "_post", fake_post)
    with pytest.raises(FaceppUnavailableError):
        await analyzer.analyze_photo(b"x")
    assert len(calls) == 2  # 1 essai + 1 retry
