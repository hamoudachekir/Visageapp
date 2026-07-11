"""Vérifie que les nouvelles colonnes existent et persistent (sqlite create_all)."""
from datetime import date

from app.models import Client, ConditionProductMap, Pharmacy, SkinAnalysis


def test_birth_date_persiste(db_session):
    pharmacy = Pharmacy(nom="P", email="p@p.tn", password_hash="x")
    db_session.add(pharmacy)
    db_session.commit()
    client = Client(
        pharmacy_id=pharmacy.id,
        prenom="A",
        nom="B",
        telephone="1",
        birth_date=date(1998, 8, 15),
    )
    db_session.add(client)
    db_session.commit()
    assert db_session.get(Client, client.id).birth_date == date(1998, 8, 15)


def test_colonnes_age_analyse(db_session):
    pharmacy = Pharmacy(nom="P", email="p2@p.tn", password_hash="x")
    db_session.add(pharmacy)
    db_session.commit()
    analysis = SkinAnalysis(
        pharmacy_id=pharmacy.id,
        skin_type="oily",
        results_json={},
        estimated_age=32,
        real_age=28,
        skin_age_delta=4,
    )
    db_session.add(analysis)
    db_session.commit()
    saved = db_session.get(SkinAnalysis, analysis.id)
    assert (saved.estimated_age, saved.real_age, saved.skin_age_delta) == (32, 28, 4)


def test_colonnes_age_mapping():
    assert hasattr(ConditionProductMap, "min_age")
    assert hasattr(ConditionProductMap, "max_age")
