# -*- coding: utf-8 -*-
"""train_skin_yolo_colab.ipynb

# Entraînement YOLOv8 — conditions de peau (Phase 2 Lumina)

Ce notebook entraîne le détecteur de conditions de peau et exporte le modèle
ONNX attendu par le backend (`SKIN_YOLO_MODEL_PATH=models/best.onnx`).

## Amélioration 4 classes (sans blackheads) — ordre des étapes

1. **Step 0** — Lancer avec `MODEL=yolov8s.pt`, `IMGSZ=1024`, `EPOCHS=200`.
   Vérifier dans les logs ~11M paramètres (pas ~3M = nano).
2. **Step 1** — Roboflow : retirer/exclure `blackheads`, remap classes dans
   l'ordre ci-dessous, viser ≥300 images et ≥500 boxes / classe, nouvelle
   version avec augmentations légères.
3. **Step 2** — Mettre `VERSION` à la nouvelle version Roboflow, relancer.
4. **Step 3** — Lire `results.png`, `confusion_matrix.png`, `PR_curve.png`.
5. **Step 4** — Télécharger `best.onnx` → `backend/models/best.onnx`,
   redémarrer le backend.

Ordre des classes (doit matcher `CLASS_TO_CONDITION` dans `app/skin/local.py`) :

| id | classe |
|----|--------|
| 0 | acne |
| 1 | dark_spots |
| 2 | enlarged_pores |
| 3 | wrinkles |

**Avant de lancer :** Runtime → Change runtime type → **T4 GPU**, puis Run all.
"""

# Vérification du GPU (doit afficher une Tesla T4)
!nvidia-smi -L

# Configuration — clé API via Colab Secrets ou saisie (ne pas committer la clé)
import os

try:
    from google.colab import userdata

    ROBOFLOW_API_KEY = userdata.get("ROBOFLOW_API_KEY")
except Exception:
    ROBOFLOW_API_KEY = os.environ.get("ROBOFLOW_API_KEY", "").strip()

if not ROBOFLOW_API_KEY:
    from getpass import getpass

    ROBOFLOW_API_KEY = getpass("Roboflow API key: ").strip()

WORKSPACE = "hamoudas-workspace"
PROJECT = "face-skin-problems-e7y0m"
VERSION = 4  # 4-class export (sans blackheads) — bump après nouvelle version Roboflow
EPOCHS = 200
IMGSZ = 1024
MODEL = "yolov8s.pt"  # ~11M params — pas yolov8n (~3M)
# Floors Step 1 (diagnostic dataset) — acne / dark_spots en priorité
MIN_IMAGES_PER_CLASS = 300
MIN_BOXES_PER_CLASS = 500

# %pip install -q ultralytics roboflow pyyaml

# Téléchargement du dataset au format YOLOv8
from collections import Counter
from pathlib import Path

import yaml
from roboflow import Roboflow

dataset = (
    Roboflow(api_key=ROBOFLOW_API_KEY)
    .workspace(WORKSPACE)
    .project(PROJECT)
    .version(VERSION)
    .download("yolov8")
)
DATA_YAML = f"{dataset.location}/data.yaml"
ROOT = Path(dataset.location)

# Garde-fou : l'ordre des classes DOIT correspondre à CLASS_TO_CONDITION du backend.
names = yaml.safe_load(open(DATA_YAML))["names"]
if isinstance(names, dict):
    names = [names[i] for i in sorted(names)]
print("Classes du dataset :", names)
attendu = ["acne", "dark_spots", "enlarged_pores", "wrinkles"]
assert [n.lower().replace("-", "_") for n in names] == attendu, (
    f"Ordre des classes incorrect ! Attendu {attendu}, obtenu {names}. "
    "Corriger le projet Roboflow avant d'entraîner."
)
print("Ordre des classes OK ✔")

# Diagnostic équilibre (Step 1) — compte images + boxes par classe sur train+valid
box_counts: Counter[int] = Counter()
img_with_class: dict[int, set[str]] = {i: set() for i in range(len(attendu))}
for split in ("train", "valid", "test"):
    label_dir = ROOT / split / "labels"
    if not label_dir.is_dir():
        continue
    for label_path in label_dir.glob("*.txt"):
        for line in label_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            cls_id = int(float(line.split()[0]))
            box_counts[cls_id] += 1
            img_with_class[cls_id].add(label_path.stem)

print("\n=== Dataset health (Step 1 targets) ===")
print(f"{'class':<16} {'images':>8} {'boxes':>8}  status")
weak = []
for i, name in enumerate(attendu):
    n_img = len(img_with_class[i])
    n_box = box_counts[i]
    ok_img = n_img >= MIN_IMAGES_PER_CLASS
    ok_box = n_box >= MIN_BOXES_PER_CLASS
    status = "OK" if (ok_img and ok_box) else "WEAK — add/fix labels in Roboflow"
    if not (ok_img and ok_box):
        weak.append(name)
    print(f"{name:<16} {n_img:>8} {n_box:>8}  {status}")
if weak:
    print(
        f"\n⚠ Classes under target ({MIN_IMAGES_PER_CLASS}+ imgs, "
        f"{MIN_BOXES_PER_CLASS}+ boxes): {weak}"
    )
    print(
        "Roboflow Universe: search acne / dark spots / "
        "enlarged pores / wrinkles → clone → merge (keep class order) → new version."
    )
else:
    print("\n✔ All classes meet minimum image/box targets.")

# Entraînement — hyperparams Step 0 (petits objets + déséquilibre)
from ultralytics import YOLO

model = YOLO(MODEL)
n_params = sum(p.numel() for p in model.model.parameters())
print(f"Modèle chargé : {MODEL} — {n_params:,} paramètres")
assert n_params > 8_000_000, (
    f"Attendu yolov8s (~11M params), obtenu {n_params:,}. "
    "Vérifier MODEL = 'yolov8s.pt' (pas yolov8n.pt)."
)
print("Taille modèle OK ✔ (yolov8s-scale)")

results = model.train(
    data=DATA_YAML,
    epochs=EPOCHS,
    imgsz=IMGSZ,
    batch=-1,  # auto-batch T4
    patience=50,
    cos_lr=True,
    close_mosaic=10,
    hsv_h=0.015,
    hsv_s=0.7,
    hsv_v=0.4,
    degrees=5.0,
    scale=0.5,
    fliplr=0.5,
    mixup=0.1,
    copy_paste=0.1,
)
BEST = str(results.save_dir / "weights" / "best.pt")
print("Meilleurs poids :", BEST)

# Évaluation (Step 3) — chemins des artefacts
save_dir = Path(results.save_dir)
print("\n=== Step 3 — lire ces fichiers ===")
for name in (
    "results.png",
    "confusion_matrix.png",
    "PR_curve.png",
    "results.csv",
):
    path = save_dir / name
    print(f"  {'✔' if path.exists() else '·'} {path}")

# Export ONNX — nms=True obligatoire (LocalAnalyzer._yolo_scores)
onnx_path = Path(YOLO(BEST).export(format="onnx", nms=True, imgsz=IMGSZ))
print("Modèle ONNX exporté :", onnx_path)

# Copie locale Colab sous le nom attendu par le backend (skip if already there)
import shutil

best_onnx = save_dir / "weights" / "best.onnx"
if onnx_path.resolve() != best_onnx.resolve():
    shutil.copy(onnx_path, best_onnx)
else:
    best_onnx = onnx_path
print(f"ONNX prêt : {best_onnx}")

from google.colab import files

files.download(str(best_onnx))

"""## Après le téléchargement (Step 4 / export backend)

1. Remplacer `backend/models/best.onnx` par le fichier téléchargé.
2. Dans `backend/.env` :
   ```
   SKIN_YOLO_MODEL_PATH=models/best.onnx
   ANALYSIS_ENGINE=auto
   ```
3. Redémarrer le backend, lancer une analyse réelle.
4. Si CPU trop lent à 1024 → retrain/export avec `IMGSZ = 768`.

Cible réaliste après plusieurs boucles data : mAP50 ~0.3–0.5 (pas ~0.8).
"""
