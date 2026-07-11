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


async def test_erreur_reseau_deux_tentatives(monkeypatch):
    analyzer = _analyzer()
    calls: list[int] = []

    async def fake_post(image_bytes):
        calls.append(1)
        raise httpx.ConnectError("dns")

    monkeypatch.setattr(analyzer, "_post", fake_post)
    with pytest.raises(FaceppUnavailableError):
        await analyzer.analyze_photo(b"x")
    assert len(calls) == 2  # les erreurs réseau sont retentées comme les timeouts


async def test_corps_non_json(monkeypatch):
    analyzer = _analyzer()

    async def fake_post(image_bytes):
        return httpx.Response(
            200, content=b"<html>proxy error</html>",
            request=httpx.Request("POST", "https://facepp.test"),
        )

    monkeypatch.setattr(analyzer, "_post", fake_post)
    with pytest.raises(FaceppUnavailableError):
        await analyzer.analyze_photo(b"x")


def _jpeg(width: int, height: int) -> bytes:
    import cv2
    import numpy as np

    rng = np.random.default_rng(7)
    img = rng.integers(0, 256, size=(height, width, 3)).astype(np.uint8)
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return buf.tobytes()


def _decoded_size(raw: bytes) -> tuple[int, int]:
    import cv2
    import numpy as np

    img = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)
    assert img is not None
    return img.shape[1], img.shape[0]  # (largeur, hauteur)


def test_downscale_reduit_les_grandes_photos():
    from app.skin.facepp import FACEPP_MAX_SIDE, downscale_for_facepp

    raw = _jpeg(3000, 2000)
    reduced = downscale_for_facepp(raw)
    width, height = _decoded_size(reduced)
    assert max(width, height) == FACEPP_MAX_SIDE
    assert width == FACEPP_MAX_SIDE and height == 720  # ratio préservé


def test_downscale_laisse_les_petites_photos_intactes():
    from app.skin.facepp import downscale_for_facepp

    raw = _jpeg(640, 480)
    assert downscale_for_facepp(raw) is raw


def test_downscale_tolere_les_octets_illisibles():
    from app.skin.facepp import downscale_for_facepp

    raw = b"pas-une-image"
    assert downscale_for_facepp(raw) is raw


async def test_analyze_photo_envoie_la_version_reduite(monkeypatch):
    analyzer = _analyzer()
    sent: list[bytes] = []

    async def fake_post(image_bytes):
        sent.append(image_bytes)
        return _response({"result": FACEPP_SAMPLE_RESULT})

    monkeypatch.setattr(analyzer, "_post", fake_post)
    await analyzer.analyze_photo(_jpeg(4000, 3000))
    width, height = _decoded_size(sent[0])
    assert max(width, height) <= 1080
