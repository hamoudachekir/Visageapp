"""Tests des fonctions pures : âge réel depuis la date de naissance, messages FR."""
from datetime import date

from app.skin.age import real_age_from_birth_date, skin_age_message_fr


def test_age_reel_avant_anniversaire():
    # Né le 15/08/1998, on est le 11/07/2026 -> 27 ans (anniversaire pas passé).
    assert real_age_from_birth_date(date(1998, 8, 15), today=date(2026, 7, 11)) == 27


def test_age_reel_apres_anniversaire():
    assert real_age_from_birth_date(date(1998, 6, 15), today=date(2026, 7, 11)) == 28


def test_age_reel_jour_anniversaire():
    assert real_age_from_birth_date(date(1998, 7, 11), today=date(2026, 7, 11)) == 28


def test_message_peau_plus_jeune():
    assert (
        skin_age_message_fr(-4)
        == "Votre peau paraît 4 ans plus jeune que votre âge !"
    )
    assert skin_age_message_fr(-3).startswith("Votre peau paraît 3 ans plus jeune")


def test_message_peau_conforme():
    for delta in (-2, -1, 0, 1, 2):
        assert skin_age_message_fr(delta) == "Votre peau correspond à votre âge."


def test_message_peau_plus_agee():
    assert (
        skin_age_message_fr(3)
        == "Votre peau paraît 3 ans de plus — voici des soins ciblés."
    )
    assert "5 ans de plus" in skin_age_message_fr(5)
