"""Entraînement YOLOv8 pour la détection de conditions de peau (Phase 2).

Conçu pour Google Colab (GPU T4 gratuit) :

    !pip install ultralytics roboflow pyyaml
    !python train_yolo.py --roboflow-api-key $RF_KEY \\
        --workspace hamoudas-workspace --project face-skin-problems-e7y0m \\
        --version 2 --epochs 200 --imgsz 1024 --model yolov8s.pt

Ou utiliser le notebook / script Colab :
    models/train_skin_yolo_colab.py  (copie des cellules dans Colab)

IMPORTANT — ordre des classes du dataset (data.yaml) : il doit suivre
CLASS_TO_CONDITION de app/skin/local.py :
    0: acne, 1: dark_spots, 2: enlarged_pores, 3: wrinkles

Datasets libres : https://universe.roboflow.com (rechercher « acne »,
« wrinkles », « dark spots », « pores ») ; fusionner les
exports dans un seul projet Roboflow à 4 classes avant l'entraînement.

Cibles data (Step 1) : ≥300 images et ≥500 boxes par classe.
Après export : copier best.onnx → backend/models/best.onnx
"""
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

EXPECTED = ["acne", "dark_spots", "enlarged_pores", "wrinkles"]


def download_from_roboflow(
    api_key: str, workspace: str, project: str, version: int
) -> str:
    """Télécharge le dataset Roboflow au format YOLOv8, renvoie le data.yaml."""
    from roboflow import Roboflow

    dataset = (
        Roboflow(api_key=api_key)
        .workspace(workspace)
        .project(project)
        .version(version)
        .download("yolov8")
    )
    return f"{dataset.location}/data.yaml"


def assert_class_order(data_yaml: str) -> None:
    import yaml

    names = yaml.safe_load(open(data_yaml, encoding="utf-8"))["names"]
    if isinstance(names, dict):
        names = [names[i] for i in sorted(names)]
    normalized = [n.lower().replace("-", "_") for n in names]
    if normalized != EXPECTED:
        raise SystemExit(
            f"Ordre des classes incorrect ! Attendu {EXPECTED}, obtenu {names}."
        )
    print("Ordre des classes OK:", normalized)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Entraînement YOLOv8 conditions de peau (Colab)"
    )
    parser.add_argument("--data", help="Chemin d'un data.yaml local (sinon Roboflow)")
    parser.add_argument("--roboflow-api-key")
    parser.add_argument("--workspace")
    parser.add_argument("--project")
    parser.add_argument("--version", type=int, default=2)
    parser.add_argument("--model", default="yolov8s.pt")
    parser.add_argument("--epochs", type=int, default=200)
    parser.add_argument("--imgsz", type=int, default=1024)
    parser.add_argument("--patience", type=int, default=50)
    args = parser.parse_args()

    data = args.data
    if not data:
        if not (args.roboflow_api_key and args.workspace and args.project):
            parser.error(
                "--data OU (--roboflow-api-key --workspace --project) requis"
            )
        data = download_from_roboflow(
            args.roboflow_api_key, args.workspace, args.project, args.version
        )

    assert_class_order(data)

    from ultralytics import YOLO

    model = YOLO(args.model)
    n_params = sum(p.numel() for p in model.model.parameters())
    print(f"Modèle {args.model}: {n_params:,} paramètres")
    if "yolov8s" in args.model and n_params < 8_000_000:
        raise SystemExit(
            f"Attendu yolov8s (~11M params), obtenu {n_params:,}."
        )

    results = model.train(
        data=data,
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=-1,
        patience=args.patience,
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
    best = results.save_dir / "weights" / "best.pt"

    # nms=True : sortie (N, 6) attendue par LocalAnalyzer._yolo_scores.
    onnx_path = YOLO(str(best)).export(
        format="onnx", nms=True, imgsz=args.imgsz
    )
    dest = Path(results.save_dir) / "weights" / "best.onnx"
    onnx_path = Path(onnx_path)
    if onnx_path.resolve() != dest.resolve():
        shutil.copy(onnx_path, dest)
    else:
        dest = onnx_path
    print(f"Modèle ONNX exporté : {dest}")
    print(
        "Copier ce fichier vers backend/models/best.onnx puis définir "
        "SKIN_YOLO_MODEL_PATH=models/best.onnx dans .env"
    )

    # Step 3 artefacts
    save_dir = Path(results.save_dir)
    print("\nÉvaluation — ouvrir :")
    for name in ("results.png", "confusion_matrix.png", "PR_curve.png"):
        print(f"  {save_dir / name}")


if __name__ == "__main__":
    main()
