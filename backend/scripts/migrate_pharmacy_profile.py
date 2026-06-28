"""Migration idempotente : ajoute les colonnes de profil à `pharmacies`.

`Base.metadata.create_all` ne modifie pas les tables existantes ; ce script
ajoute les colonnes manquantes (sans risque s'il est relancé).

Usage (depuis backend/) : python -m scripts.migrate_pharmacy_profile
"""

from __future__ import annotations

from sqlalchemy import text

from app.db import engine

STATEMENTS = [
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS telephone VARCHAR",
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS adresse VARCHAR",
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS ville VARCHAR",
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS description VARCHAR",
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS logo_bytes BYTEA",
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS logo_mime VARCHAR",
    "ALTER TABLE pharmacies ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ",
]


def main() -> None:
    with engine.begin() as conn:
        for stmt in STATEMENTS:
            conn.execute(text(stmt))
    print("Migration profil pharmacie appliquée.")


if __name__ == "__main__":
    main()
