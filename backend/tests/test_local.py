"""Tests des parties pures du moteur local (sans mediapipe/transformers)."""
import numpy as np

from app.skin.local import combine_skin_type, oiliness_proxy, redness_score


def test_rouge_pur_score_maximal():
    img = np.zeros((100, 100, 3), np.uint8)
    img[:, :, 2] = 255  # BGR : canal rouge saturé
    assert redness_score(img) == 100


def test_gris_neutre_score_nul():
    img = np.full((100, 100, 3), 128, np.uint8)
    assert redness_score(img) <= 5


def test_redness_respecte_le_masque():
    img = np.full((100, 100, 3), 128, np.uint8)
    img[:50, :, 2] = 255  # moitié haute rouge
    mask_bas = np.zeros((100, 100), np.uint8)
    mask_bas[50:, :] = 255
    assert redness_score(img, mask_bas) <= 5
    mask_haut = np.zeros((100, 100), np.uint8)
    mask_haut[:50, :] = 255
    assert redness_score(img, mask_haut) >= 60


def test_oiliness_proxy():
    values = np.zeros(100, np.uint8)
    values[:10] = 255  # 10 % de pixels spéculaires
    assert abs(oiliness_proxy(values) - 0.10) < 1e-6
    assert oiliness_proxy(np.array([], np.uint8)) == 0.0


def test_combination_si_tzone_brillante_et_joues_mates():
    assert combine_skin_type("normal", 0.20, 0.00) == "combination"
    assert combine_skin_type("dry", 0.00, 0.00) == "dry"
    # joues brillantes aussi -> pas mixte, on garde le type de base
    assert combine_skin_type("oily", 0.09, 0.05) == "oily"
