# Module d'analyse de peau (Face++ + recommandations produits) — design spec

**Date** : 2026-07-10
**Statut** : Approuvé par l'utilisateur en conversation.

## Contexte

L'app capture déjà 4 photos guidées (`CapturePose` : face, profil gauche 45°,
profil droit 45°, front en gros plan) mais n'envoie que la vue de face à
`/v1/analyze` (âge + sexe via InsightFace). La base `ismouda` contient
`visage_products` (2832 produits) avec des slugs `sub` bien remplis
(`soins-anti-age-rides`, `soins-peau-grasse-mixte-acne`, …) ; ses colonnes
`skin_type[]` et `concern[]` sont vides.

Objectif : un module d'analyse de peau qui note 7 conditions (0–100), classe le
type de peau, agrège les 4 photos et renvoie des recommandations produits
classées, le tout affiché dans l'app Flutter.

Décisions actées en conversation :

- **SQLAlchemy synchrone** (cohérent avec le backend existant) ; seul l'appel
  HTTP Face++ est async (`httpx`) dans l'endpoint.
- **JWT pharmacie requis** + champ optionnel `client_id` pour rattacher
  l'analyse à l'historique d'un client.
- **Seed automatique** de `condition_product_map` depuis les slugs `sub`.
- **Flutter inclus** dans le périmètre (envoi des 4 photos + écran résultat).

## Scope

**Inclus :**

- Package backend `app/skin/` : interface `SkinAnalyzer`, moteur Face++
  (Phase 1, fonctionnel), moteur local (Phase 2, scaffold), validation qualité,
  agrégation, moteur de recommandation, libellés FR.
- Tables `skin_analyses` et `condition_product_map` + mapping lecture seule de
  `visage_products` ; script de seed.
- `POST /v1/skin/analyze` (multipart 4 photos + `client_id` optionnel).
- Flutter : client API, modèles, envoi des 4 photos, écran résultat
  (type de peau, conditions, produits recommandés, disclaimer).
- Tests unitaires backend (parser Face++ mocké, recommandation, agrégation).
- Script d'entraînement YOLOv8 prêt pour Colab (Phase 2).
- README backend mis à jour (clés Face++, seed, Phase 2).

**Exclus (hors scope) :**

- Entraînement effectif des modèles YOLOv8 (l'utilisateur le lancera sur Colab).
- Moteur local complet en production (scaffold + rougeurs OpenCV + type de peau
  HF seulement ; les détections YOLO attendent les poids entraînés).
- Démographie (âge/sexe) dans le nouvel endpoint — `/v1/analyze` reste tel quel.
- Historique des analyses dans l'app (l'API stocke ; l'UI d'historique viendra
  plus tard).

## Architecture backend — `backend/app/skin/`

- `analyzer.py` — contrat commun :
  - `SkinPhotoResult` : dict `{condition_code: score 0–100}` pour les 7
    conditions (`wrinkles`, `dark_circles`, `blackheads`, `enlarged_pores`,
    `dark_spots`, `redness`, `acne`), `skin_type`
    (`oily|dry|combination|normal`), `zones` par condition (ex. `forehead`,
    `eyes`, `cheeks`, `chin`, `nose`), et drapeaux d'échec par photo.
  - `SkinAnalyzer` (ABC) : `async analyze_photo(image_bytes) -> SkinPhotoResult`.
- `facepp.py` — `FaceppAnalyzer` :
  - POST `https://api-us.faceplusplus.com/facepp/v1/skinanalyze` (`httpx`,
    timeout 15 s, **1 retry** sur timeout/5xx, backoff court).
  - Erreurs propres : quota (`CONCURRENCY_LIMIT_EXCEEDED`,
    `AUTHORIZATION_ERROR`, quota épuisé) → `FaceppQuotaError` ;
    autres → `FaceppUnavailableError`. Clés absentes → erreur explicite au
    premier appel, pas au démarrage.
  - Parser → schéma unifié. Les indicateurs binaires + confiance deviennent
    des scores : `présent → conf×100`, `absent → (1−conf)×100`.
    - `wrinkles` = max des sous-indicateurs (front, pattes d'oie, ridules
      yeux, glabelle, sillons nasogéniens) ; zones = sous-types présents.
    - `enlarged_pores` = moyenne des 4 zones (front, joues ×2, menton) ;
      zones = celles présentes.
    - `dark_circles`, `acne`, `blackheads` (`blackhead`), `dark_spots`
      (`skin_spot`) : score direct présence×confiance.
    - `redness` : Face++ ne le renvoie pas → 0 en Phase 1 (le moteur local
      Phase 2 le calcule) ; jamais « recommandé pour vos rougeurs » sans signal.
    - `skin_type` : 0→oily, 1→dry, 2→normal, 3→combination.
- `local.py` — `LocalAnalyzer` (Phase 2, scaffold fonctionnel partiel) :
  - Zones via MediaPipe FaceMesh (468 landmarks) : T-zone, joues, sous-œil,
    front, menton.
  - `redness` : canal a* CIELAB (OpenCV) sur joues/nez, normalisé 0–100.
  - Type de peau : HF `dima806/skin_types_image_detection` (dry/normal/oily) ;
    `combination` si brillance/oiliness haute en T-zone et basse sur joues.
  - Conditions : hooks d'inférence ONNX (YOLOv8) — actifs seulement si les
    poids exportés existent (`SKIN_YOLO_MODEL_PATH`).
  - **Imports paresseux** ; dépendances lourdes dans
    `requirements-phase2.txt` (mediapipe, transformers, torch, ultralytics).
- `engine.py` — façade : `ANALYSIS_ENGINE=facepp|local|auto`. `auto` = Face++
  d'abord, repli local si échec/quota/clés absentes. **Défaut Phase 1 :
  `facepp`** — tant que les poids YOLO ne sont pas entraînés, le repli local ne
  sait noter que rougeurs + type de peau, et un résultat quasi vide serait
  trompeur ; `auto` deviendra le défaut recommandé après la Phase 2.
- `quality.py` — validation par photo, **avant** tout appel API :
  - exactement 1 visage (InsightFace déjà chargé via `vision.py` ; si modèle
    CV indisponible, la validation visage est sautée avec un warning) ;
  - flou : variance Laplacienne < seuil (défaut 60, configurable) → rejet ;
  - luminosité moyenne hors bornes (défaut 40–220) → rejet.
- `aggregate.py` — sur les photos **réussies** : max du score par condition,
  union des zones, vote majoritaire du type de peau (égalité → type de la
  photo de face). Face++ exige un visage frontal : les profils 45° peuvent
  échouer → toléré ; **la photo de face doit réussir**, sinon 422.
- `recommend.py` — cœur en **fonctions pures** (listes de dicts en entrée,
  testables sans DB) :
  1. conditions avec score ≥ 30 ;
  2. produits mappés via `condition_product_map`, filtrés
     `skin_type IS NULL OR skin_type = détecté` ;
  3. rang = sévérité × priorité (somme si un produit couvre plusieurs
     conditions) ; dédup par `product_id` ; top 6 ;
  4. le type de peau ajoute des produits de base (score fixe 40) via des
     lignes `condition_code='skin_type_dry'` / `'skin_type_oily'` ;
  5. `reason_fr` généré : « Recommandé pour votre acné modérée et peau
     grasse ».
- `labels.py` — libellés FR des conditions, bandes de sévérité
  (`<30 faible`, `30–59 modérée`, `≥60 marquée` → `mild|moderate|severe`),
  disclaimer : « Cette analyse est indicative et ne remplace pas un avis
  dermatologique. »
- `schemas.py` (dans `app/skin/`) — Pydantic v2 : `SkinAnalyzeResponse`,
  `ConditionOut`, `RecommendationOut`.

## Modèle de données (PostgreSQL `ismouda`)

```sql
CREATE TABLE skin_analyses (
    id           SERIAL PRIMARY KEY,
    pharmacy_id  INTEGER NOT NULL REFERENCES pharmacies(id),
    client_id    INTEGER REFERENCES clients(id),   -- NULL = non rattachée
    skin_type    TEXT NOT NULL,
    results_json JSON NOT NULL,                    -- conditions + zones + moteur utilisé
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE condition_product_map (
    id             SERIAL PRIMARY KEY,
    condition_code VARCHAR(30) NOT NULL,   -- 'acne', 'wrinkles', 'skin_type_dry', ...
    skin_type      VARCHAR(15),            -- NULL = tout type de peau
    product_id     INTEGER REFERENCES visage_products(id),
    priority       INTEGER DEFAULT 0
);
```

- Tables créées au démarrage via `Base.metadata.create_all` (comme l'existant).
- `visage_products` : mappé en lecture seule dans `models.py` (`create_all` ne
  modifie pas une table existante). Aucune photo stockée — traitement en
  mémoire uniquement (RGPD, comme `/v1/analyze`).
- `backend/scripts/seed_condition_map.py` (idempotent : purge + réinsère) :

| condition_code   | slugs `sub`                                                       | priorité |
|------------------|-------------------------------------------------------------------|----------|
| wrinkles         | soins-anti-age-rides                                              | 10       |
| dark_spots       | soins-anti-taches-depigmentants (10), soins-eclaircissants (5)    | 10/5     |
| acne             | soins-peau-grasse-mixte-acne                                      | 10       |
| redness          | soins-anti-rougeurs-sensible (10), soins-apaisants (7), eaux-thermales (4) | 10/7/4 |
| dark_circles     | yeux-levres                                                       | 10       |
| blackheads       | masques-gommages (8), soins-peau-grasse-mixte-acne (6)            | 8/6      |
| enlarged_pores   | masques-gommages (8), soins-peau-grasse-mixte-acne (6)            | 8/6      |
| skin_type_dry    | peaux-seches (10), soins-hydratants-nourrissants (6)              | 10/6     |
| skin_type_oily   | demaquillants-nettoyants (5)                                      | 5        |

Seuls les produits `active = true AND in_stock = true` sont recommandés
(filtre à la requête, pas au seed).

## API — `POST /v1/skin/analyze`

- Multipart : `front`, `left`, `right`, `closeup` (JPEG/PNG/WebP, ≤ 10 Mo
  chacun) + champ formulaire optionnel `client_id`.
- JWT pharmacie requis (`get_current_pharmacy`). Si `client_id` fourni, il doit
  appartenir à la pharmacie (réutilise `_owned_client_or_404`).
- Réponse (contrat validé) :

```json
{
  "analysis_id": 123,
  "skin_type": "combination",
  "conditions": [
    {"code": "acne", "label_fr": "Acné / boutons", "score": 62,
     "severity": "moderate", "zones": ["chin", "forehead"]}
  ],
  "recommendations": [
    {"product_id": 45, "name": "...", "brand": "...", "price": 12.9,
     "image_url": "...", "reason_fr": "Recommandé pour votre acné modérée et peau grasse",
     "matched_conditions": ["acne"]}
  ],
  "disclaimer_fr": "Cette analyse est indicative et ne remplace pas un avis dermatologique."
}
```

- `conditions` liste les 7 conditions triées par score décroissant (y compris
  faibles — l'UI décide quoi mettre en avant).

## Gestion des erreurs

| Cas | Réponse |
|-----|---------|
| Photo invalide (pas de visage / >1 visage / floue / trop sombre) | 422, détail FR nommant la photo (`"front: aucun visage détecté"`) |
| Photo de face échoue à l'analyse Face++ | 422, détail FR |
| Profils/closeup échouent à l'analyse | Tolérés — agrégation sur les photos réussies |
| Quota Face++ épuisé / clés invalides | `auto` → repli local ; sinon 502 « Service d'analyse temporairement indisponible (quota). » |
| Face++ timeout ×2 / 5xx | idem 502 (ou repli en `auto`) |
| `client_id` d'une autre pharmacie | 404 (isolation multi-tenant) |

## Config (`.env`)

```env
FACEPP_API_KEY=...
FACEPP_API_SECRET=...
FACEPP_ENDPOINT=https://api-us.faceplusplus.com/facepp/v1/skinanalyze
ANALYSIS_ENGINE=facepp      # facepp | local | auto (auto recommandé après Phase 2)
SKIN_BLUR_THRESHOLD=60
SKIN_YOLO_MODEL_PATH=       # Phase 2, vide = hooks YOLO inactifs
```

## Frontend (Flutter)

- `lib/models/skin_analysis.dart` : `SkinAnalysisResult`, `SkinCondition`,
  `ProductRecommendation` (+ `fromJson`).
- `lib/services/skin_api.dart` : `SkinApi.analyze({required Map<CapturePose,
  File> photos, int? clientId})` → multipart vers `/v1/skin/analyze` avec
  `Authorization: Bearer <token>` (token injecté comme `ApiClientRepository`),
  timeout 90 s (4 photos + API externe).
- `capture_flow.dart` : devient `ConsumerWidget` ; envoie **les 4 photos**
  (mapping `face→front`, `profilGauche→left`, `profilDroit→right`,
  `front→closeup`) + `client_id` depuis `sessionFlowProvider`.
  `AnalyzingScreen` réutilisé (callback générique).
- `lib/screens/skin_result_screen.dart` (nouveau, thème Lumina existant) :
  1. carte type de peau ;
  2. conditions détectées (score ≥ 30) avec barre de sévérité + libellé FR ;
  3. produits recommandés : image (réseau, placeholder si absente), nom,
     marque, prix, `reason_fr` ;
  4. disclaimer médical toujours visible en bas ;
  5. bouton « Refaire la capture ».
- L'ancien `result_screen.dart` (âge/sexe) reste pour `/v1/analyze` mais n'est
  plus la cible du flux de capture.

## Tests

- Backend (`backend/tests/`, pytest) :
  - `test_facepp_parser.py` : JSON Face++ d'exemple (fixture) → scores/zones
    attendus ; erreurs quota/timeout → exceptions dédiées (API mockée via
    `respx` ou monkeypatch, aucun appel réseau).
  - `test_recommend.py` : seuil 30, filtre type de peau, rang
    sévérité×priorité, dédup multi-conditions, top 6, `reason_fr`.
  - `test_aggregate.py` : max par condition, vote majoritaire, égalité → face,
    échec des profils toléré, échec de la face → erreur.
  - `test_quality.py` : image floue rejetée, image noire rejetée.
- Manuel : `curl` avec 4 photos réelles + clés Face++ ; app sur appareil →
  capture → résultat → vérifier le rattachement client en base.

## Phase 2 — livré en scaffold

- `backend/train/train_yolo.py` : Colab-ready — téléchargement datasets
  Roboflow (clé API en variable), entraînement YOLOv8n par condition,
  export ONNX, chemin de sortie compatible `SKIN_YOLO_MODEL_PATH`.
- `requirements-phase2.txt` séparé pour ne pas alourdir l'install Phase 1.
- Bascule prévue : quand les poids YOLO sont entraînés et validés,
  `ANALYSIS_ENGINE=local` devient le mode principal (Face++ en secours).

## Disclaimer médical

Le texte « Cette analyse est indicative et ne remplace pas un avis
dermatologique. » figure dans **chaque** réponse API et en bas de l'écran
résultat — obligatoire partout où rosacée/acné sont affichées (guidance
cosmétique, pas un diagnostic).
