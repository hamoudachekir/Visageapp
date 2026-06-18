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
