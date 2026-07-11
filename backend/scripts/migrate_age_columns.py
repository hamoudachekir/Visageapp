"""Migration idempotente : colonnes âge (clients, skin_analyses, condition_product_map).

`Base.metadata.create_all` ne modifie pas les tables existantes ; ce script
ajoute les colonnes manquantes (sans risque s'il est relancé).

Usage (depuis backend/) : python -m scripts.migrate_age_columns
"""

from __future__ import annotations

from sqlalchemy import text

from app.db import engine

STATEMENTS = [
    "ALTER TABLE clients ADD COLUMN IF NOT EXISTS birth_date DATE",
    "ALTER TABLE skin_analyses ADD COLUMN IF NOT EXISTS estimated_age INTEGER",
    "ALTER TABLE skin_analyses ADD COLUMN IF NOT EXISTS real_age INTEGER",
    "ALTER TABLE skin_analyses ADD COLUMN IF NOT EXISTS skin_age_delta INTEGER",
    "ALTER TABLE condition_product_map ADD COLUMN IF NOT EXISTS min_age INTEGER",
    "ALTER TABLE condition_product_map ADD COLUMN IF NOT EXISTS max_age INTEGER",
]


def main() -> None:
    with engine.begin() as conn:
        for stmt in STATEMENTS:
            conn.execute(text(stmt))
    print("Migration colonnes âge appliquée.")


if __name__ == "__main__":
    main()
