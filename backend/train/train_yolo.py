"""Entraînement YOLOv8 pour la détection de conditions de peau (Phase 2).

Conçu pour Google Colab (GPU T4 gratuit) :

    !pip install ultralytics roboflow
    !python train_yolo.py --roboflow-api-key $RF_KEY \
        --workspace <workspace> --project <project> --version 1 --epochs 60

IMPORTANT — ordre des classes du dataset (data.yaml) : il doit suivre
CLASS_TO_CONDITION de app/skin/local.py :
    0: acne, 1: blackheads, 2: dark_spots, 3: enlarged_pores, 4: wrinkles

Datasets libres : https://universe.roboflow.com (rechercher « acne »,
« blackheads », « wrinkles », « dark spots », « pores ») ; fusionner les
exports dans un seul projet Roboflow à 5 classes avant l'entraînement.
"""
from __future__ import annotations

import argparse


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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Entraînement YOLOv8 conditions de peau (Colab)"
    )
    parser.add_argument("--data", help="Chemin d'un data.yaml local (sinon Roboflow)")
    parser.add_argument("--roboflow-api-key")
    parser.add_argument("--workspace")
    parser.add_argument("--project")
    parser.add_argument("--version", type=int, default=1)
    parser.add_argument("--model", default="yolov8n.pt")
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--imgsz", type=int, default=640)
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

    from ultralytics import YOLO

    model = YOLO(args.model)
    results = model.train(data=data, epochs=args.epochs, imgsz=args.imgsz)
    best = results.save_dir / "weights" / "best.pt"

    # nms=True : sortie (N, 6) attendue par LocalAnalyzer._yolo_scores.
    onnx_path = YOLO(str(best)).export(format="onnx", nms=True, imgsz=args.imgsz)
    print(f"Modèle ONNX exporté : {onnx_path}")
    print("Copier ce fichier sur le serveur puis définir SKIN_YOLO_MODEL_PATH dans .env")


if __name__ == "__main__":
    main()
