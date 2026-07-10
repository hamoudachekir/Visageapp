"""Tests de la validation qualité (images synthétiques, modèle CV non chargé)."""
import cv2
import numpy as np
import pytest

from app.skin.quality import PhotoQualityError, validate_photo


def _jpeg(img: np.ndarray) -> bytes:
    ok, buf = cv2.imencode(".jpg", img)
    assert ok
    return buf.tobytes()


def test_octets_invalides_rejetes():
    with pytest.raises(PhotoQualityError, match="illisible"):
        validate_photo(b"pas-une-image", "front")


def test_photo_noire_rejetee():
    raw = _jpeg(np.zeros((300, 300, 3), np.uint8))
    with pytest.raises(PhotoQualityError, match="sombre"):
        validate_photo(raw, "front")


def test_photo_uniforme_rejetee_car_floue():
    raw = _jpeg(np.full((300, 300, 3), 128, np.uint8))
    with pytest.raises(PhotoQualityError, match="floue"):
        validate_photo(raw, "left")


def test_photo_contrastee_acceptee():
    # Bruit aléatoire : luminosité moyenne ~127, forte variance Laplacienne.
    # Le comptage de visages est sauté car le modèle CV n'est pas chargé en test.
    rng = np.random.default_rng(42)
    img = rng.integers(0, 256, size=(300, 300, 3)).astype(np.uint8)
    validate_photo(_jpeg(img), "front")  # ne doit pas lever
