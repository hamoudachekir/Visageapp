"""Crée (ou affiche) un compte pharmacie.

Usage, depuis le dossier `backend/` :

    python -m scripts.create_pharmacy --nom "Pharmacie Test" \
        --email "test@lumina.com" --password "lumina123"

Pas de signup public : les comptes sont provisionnés manuellement via ce script.
"""

from __future__ import annotations

import argparse

from app.auth import hash_password
from app.db import Base, SessionLocal, engine
from app.models import Pharmacy


def main() -> None:
    parser = argparse.ArgumentParser(description="Créer un compte pharmacie")
    parser.add_argument("--nom", required=True)
    parser.add_argument("--email", required=True)
    parser.add_argument("--password", required=True)
    args = parser.parse_args()

    Base.metadata.create_all(bind=engine)

    db = SessionLocal()
    try:
        existing = db.query(Pharmacy).filter(Pharmacy.email == args.email).first()
        if existing is not None:
            print(f"Déjà existant : {existing.email} (id={existing.id})")
            return
        pharmacy = Pharmacy(
            nom=args.nom,
            email=args.email,
            password_hash=hash_password(args.password),
        )
        db.add(pharmacy)
        db.commit()
        db.refresh(pharmacy)
        print(f"Créé : {pharmacy.nom} <{pharmacy.email}> (id={pharmacy.id})")
    finally:
        db.close()


if __name__ == "__main__":
    main()
