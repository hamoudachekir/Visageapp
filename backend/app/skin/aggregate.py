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
    vote, le type de la photo de face l'emporte s'il fait partie des ex æquo.
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

    votes = Counter(r.skin_type for r in results.values())
    max_count = max(votes.values())
    leaders = [t for t, c in votes.items() if c == max_count]
    if (
        len(leaders) > 1
        and FRONT_KEY in results
        and results[FRONT_KEY].skin_type in leaders
    ):
        skin_type = results[FRONT_KEY].skin_type
    else:
        skin_type = leaders[0]

    return scores, skin_type, zones
