"""Tests des endpoints clients : birth_date à la création + PATCH partiel."""
from datetime import date

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app import auth as auth_module
from app.db import Base, get_db
from app.main import app
from app.models import Client, Pharmacy


@pytest.fixture()
def api():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(bind=engine)

    session = Session()
    pharmacy = Pharmacy(nom="Test", email="t@t.tn", password_hash="x")
    session.add(pharmacy)
    session.commit()
    pharmacy_id = pharmacy.id
    session.close()

    def override_db():
        s = Session()
        try:
            yield s
        finally:
            s.close()

    def override_pharmacy():
        s = Session()
        try:
            return s.get(Pharmacy, pharmacy_id)
        finally:
            s.close()

    app.dependency_overrides[get_db] = override_db
    app.dependency_overrides[auth_module.get_current_pharmacy] = override_pharmacy
    yield TestClient(app), Session
    app.dependency_overrides.clear()


def _payload(**extra):
    return {"prenom": "Amel", "nom": "Ben Ali", "telephone": "0612345678", **extra}


def test_creation_avec_birth_date(api):
    client, Session = api
    res = client.post("/v1/clients", json=_payload(birth_date="1998-08-15"))
    assert res.status_code == 201, res.text
    assert res.json()["birth_date"] == "1998-08-15"


def test_creation_birth_date_trop_recente(api):
    client, _ = api
    res = client.post(
        "/v1/clients", json=_payload(birth_date=str(date.today()))
    )
    assert res.status_code == 422
    assert "13 et 110 ans" in res.text


def test_creation_birth_date_trop_ancienne(api):
    client, _ = api
    res = client.post("/v1/clients", json=_payload(birth_date="1900-01-01"))
    assert res.status_code == 422


def test_patch_birth_date(api):
    client, _ = api
    created = client.post("/v1/clients", json=_payload()).json()
    res = client.patch(
        f"/v1/clients/{created['id']}", json={"birth_date": "1990-01-20"}
    )
    assert res.status_code == 200, res.text
    assert res.json()["birth_date"] == "1990-01-20"
    assert res.json()["prenom"] == "Amel"  # champs non fournis inchangés


def test_patch_client_autre_pharmacie_404(api):
    client, Session = api
    s = Session()
    autre = Pharmacy(nom="Autre", email="a@a.tn", password_hash="x")
    s.add(autre)
    s.commit()
    intrus = Client(pharmacy_id=autre.id, prenom="X", nom="Y", telephone="1")
    s.add(intrus)
    s.commit()
    intrus_id = intrus.id
    s.close()
    res = client.patch(f"/v1/clients/{intrus_id}", json={"birth_date": "1990-01-20"})
    assert res.status_code == 404


def test_patch_prenom_vide_rejete(api):
    client, _ = api
    created = client.post("/v1/clients", json=_payload()).json()
    res = client.patch(f"/v1/clients/{created['id']}", json={"prenom": "  "})
    assert res.status_code == 422


def test_client_out_tolere_une_date_hors_bornes():
    """La validation 13-110 ans ne s'applique qu'en entrée, jamais en sortie."""
    from datetime import date as date_type

    from app.schemas import ClientOut

    out = ClientOut(
        id=1, prenom="A", nom="B", telephone="1",
        birth_date=date_type(1900, 1, 1),
    )
    assert out.birth_date == date_type(1900, 1, 1)


def test_patch_peau_sensible_null_rejete(api):
    client, _ = api
    created = client.post("/v1/clients", json=_payload()).json()
    res = client.patch(f"/v1/clients/{created['id']}", json={"peau_sensible": None})
    assert res.status_code == 422
