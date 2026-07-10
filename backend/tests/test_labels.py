"""Tests des libellés FR et des bandes de sévérité."""
from app.skin import labels
from app.skin.analyzer import CONDITION_CODES


def test_toutes_les_conditions_ont_un_libelle():
    assert set(labels.LABELS_FR) == set(CONDITION_CODES)


def test_bandes_de_severite():
    assert labels.severity(0) == "mild"
    assert labels.severity(29) == "mild"
    assert labels.severity(30) == "moderate"
    assert labels.severity(59) == "moderate"
    assert labels.severity(60) == "severe"
    assert labels.severity(100) == "severe"
