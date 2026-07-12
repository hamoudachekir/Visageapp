# Backend — MVP analyse faciale (âge & sexe)

Backend FastAPI minimal du projet. Pour l'instant, **un seul rôle** : recevoir la
photo de face capturée par l'app Flutter et renvoyer l'**âge estimé** + le **sexe**,
via InsightFace (`buffalo_l`), exactement comme la fonction `analyze_demographics()`
du notebook `tier1_detection_age_sexe_kaggle.ipynb`.

## Installation

```bash
cd backend
python -m venv .venv
# Windows PowerShell :
.venv\Scripts\Activate.ps1
# Linux/Mac :
# source .venv/bin/activate

pip install -r requirements.txt
```

> Sur machine GPU, remplacez `onnxruntime` par `onnxruntime-gpu` dans
> `requirements.txt` (cf. note du notebook Tier 1).

## Lancer le serveur

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Au **premier démarrage**, InsightFace télécharge les poids `buffalo_l`
(connexion Internet requise). Documentation interactive : http://localhost:8000/docs

## Endpoints

| Méthode | Route          | Rôle                                              |
|---------|----------------|---------------------------------------------------|
| `GET`   | `/health`      | Sonde de disponibilité.                           |
| `POST`  | `/v1/analyze`  | `multipart/form-data`, champ `image` → âge + sexe |

### Exemple

```bash
curl -X POST http://localhost:8000/v1/analyze \
  -F "image=@visage.jpg"
```

Réponse :

```json
{
  "ok": true,
  "moteur": "insightface",
  "nb_visages": 1,
  "confiance": 0.87,
  "demographics": { "age_estime": 34, "sexe": "Femme" }
}
```

Si aucun visage n'est détecté :

```json
{ "ok": false, "raison": "aucun_visage_detecte", "nb_visages": 0, "moteur": "insightface" }
```

## Confidentialité (plan §8.2)

L'image n'est **jamais écrite sur disque** : elle reste en mémoire le temps de la
requête, puis est libérée. Seul le résultat structuré est renvoyé.

## Analyse de peau (module `app/skin/`)

`POST /v1/skin/analyze` (JWT pharmacie) reçoit 4 photos (`front`, `left`,
`right`, `closeup`) + `client_id` optionnel et renvoie : type de peau,
7 conditions notées 0–100, recommandations produits et disclaimer médical.
Les photos sont traitées en mémoire et jamais stockées.

### Âge de la peau (estimation)

La réponse contient un bloc `age` : `estimated_age` (**estimation** IA via
Face++ Detect, repli InsightFace local selon `ANALYSIS_ENGINE`), `real_age`
(calculé depuis `clients.birth_date` si l'analyse est rattachée à un client),
`skin_age_delta` et `message_fr` (« Votre peau paraît X ans… »). Si les deux
moteurs échouent, `age` vaut `null` sans casser l'analyse. La date de
naissance se renseigne à la création du client (`POST /v1/clients`, champ
`birth_date`, âge 13–110 ans) ou via `PATCH /v1/clients/{id}`.

Migration à exécuter une fois :

```bash
python -m scripts.migrate_age_columns
```

L'âge influe sur les recommandations : filtres `min_age`/`max_age` du mapping,
produits anti-rides seulement si âge ≥ 35 ou score rides ≥ 40, et boost des
produits rides/taches si la peau paraît 3 ans de plus que l'âge réel.

### Phase 1 — Face++ (moteur par défaut)

1. Créer un compte gratuit sur <https://console.faceplusplus.com>.
2. Créer une application API → récupérer **API Key** et **API Secret**.
3. Compléter `backend/.env` :

   ```env
   FACEPP_API_KEY=...
   FACEPP_API_SECRET=...
   FACEPP_ENDPOINT=https://api-us.faceplusplus.com/facepp/v1/skinanalyze
   FACEPP_DETECT_ENDPOINT=https://api-us.faceplusplus.com/facepp/v3/detect
   ANALYSIS_ENGINE=facepp      # facepp | local | auto
   SKIN_BLUR_THRESHOLD=60
   SKIN_YOLO_MODEL_PATH=       # Phase 2, vide = hooks YOLO inactifs
   ```

### Recommandations produits

Le mapping condition → produits est dérivé des sous-catégories (`sub`) de
`visage_products` :

```bash
python -m scripts.seed_condition_map
```

Relançable à volonté (idempotent). Ajuster ensuite les priorités directement
dans la table `condition_product_map` si besoin.

### Tests

```bash
pip install -r requirements-dev.txt
python -m pytest tests -v
```

Test manuel (après login pour obtenir un token) :

```bash
TOKEN=$(curl -s -X POST http://127.0.0.1:8000/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@lumina.com","password":"lumina123"}' | python -c "import sys,json;print(json.load(sys.stdin)['token'])")
curl -X POST http://127.0.0.1:8000/v1/skin/analyze \
  -H "Authorization: Bearer $TOKEN" \
  -F front=@face.jpg -F left=@gauche.jpg -F right=@droit.jpg -F closeup=@front.jpg
```

### Phase 2 — moteur local gratuit

```bash
pip install -r requirements-phase2.txt
```

- Au premier usage, le moteur local télécharge automatiquement le modèle
  FaceLandmarker de mediapipe (~4 Mo) dans `backend/models/` (gitignoré).
- Rougeurs (OpenCV, CIELAB) et type de peau (HF
  `dima806/skin_types_image_detection` + logique T-zone) fonctionnent sans
  entraînement.
- Conditions (acné, points noirs, taches, pores, rides) : entraîner YOLOv8
  sur Google Colab avec `train/train_yolo.py` (datasets gratuits sur
  <https://universe.roboflow.com> — fusionner en un projet à 5 classes dans
  l'ordre de `CLASS_TO_CONDITION` de `app/skin/local.py`), puis copier
  l'export ONNX sur le serveur et renseigner `SKIN_YOLO_MODEL_PATH`.
- Une fois validé, passer `ANALYSIS_ENGINE=auto` (Face++ avec repli local)
  ou `local`.

> ⚠️ Les résultats (acné, rougeurs/rosacée…) sont une aide cosmétique, pas un
> diagnostic médical : le disclaimer doit rester visible partout où ils sont
> affichés.
