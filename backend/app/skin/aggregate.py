"""Agrégation des résultats par photo -> résultat global de l'analyse."""
from __future__ import annotations

from collections import Counter

from .analyzer import CONDITION_CODES, SkinPhotoResult

FRONT_KEY = "front"


def aggregate(
    results: dict[str, SkinPhotoResult],
) -> tuple[dict[str, int], str, dict[str, list[str]]]:
    """Max du score par condition, union des zones, vote majoritaire du type.

    `results` ne contient que les photos analysées avec succès ; la photo de
    face (`front`) est garantie présente par le moteur. En cas d'égalité au
    vote, le type de la photo de face l'emporte.
    """
    if not results:
        raise ValueError("aucun résultat photo à agréger")

    scores = {
        code: max(r.scores.get(code, 0) for r in results.values())
        for code in CONDITION_CODES
    }

    zones: dict[str, list[str]] = {}
    for result in results.values():
        for condition, zone_list in result.zones.items():
            bucket = zones.setdefault(condition, [])
            for zone in zone_list:
                if zone not in bucket:
                    bucket.append(zone)

    votes = Counter(r.skin_type for r in results.values()).most_common()
    if len(votes) > 1 and votes[0][1] == votes[1][1] and FRONT_KEY in results:
        skin_type = results[FRONT_KEY].skin_type
    else:
        skin_type = votes[0][0]

    return scores, skin_type, zones
