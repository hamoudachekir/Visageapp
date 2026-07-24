"""Diagnose a YOLOv8 skin dataset (local folder or Roboflow download).

Reports per-class image/box counts against the Step 1 floors used to improve
the 4-class skin detector (acne, dark_spots, enlarged_pores, wrinkles).

Usage (from backend/)::

    python -m train.diagnose_dataset --data path/to/data.yaml
    python -m train.diagnose_dataset \\
        --roboflow-api-key $ROBOFLOW_API_KEY \\
        --workspace hamoudas-workspace \\
        --project face-skin-problems-e7y0m \\
        --version 2
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

import yaml

EXPECTED = ["acne", "dark_spots", "enlarged_pores", "wrinkles"]
MIN_IMAGES = 300
MIN_BOXES = 500


def _normalize_names(names: list | dict) -> list[str]:
    if isinstance(names, dict):
        return [str(names[i]) for i in sorted(names)]
    return [str(n) for n in names]


def count_split(root: Path) -> tuple[Counter[int], dict[int, set[str]]]:
    box_counts: Counter[int] = Counter()
    img_with_class: dict[int, set[str]] = {i: set() for i in range(len(EXPECTED))}
    for split in ("train", "valid", "val", "test"):
        label_dir = root / split / "labels"
        if not label_dir.is_dir():
            continue
        for label_path in label_dir.glob("*.txt"):
            for line in label_path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line:
                    continue
                cls_id = int(float(line.split()[0]))
                if cls_id not in img_with_class:
                    img_with_class[cls_id] = set()
                box_counts[cls_id] += 1
                img_with_class[cls_id].add(label_path.stem)
    return box_counts, img_with_class


def diagnose(data_yaml: Path, min_images: int, min_boxes: int) -> int:
    meta = yaml.safe_load(data_yaml.read_text(encoding="utf-8"))
    names = _normalize_names(meta["names"])
    normalized = [n.lower().replace("-", "_") for n in names]
    print("Classes:", names)
    if normalized != EXPECTED:
        print(f"ERROR: expected order {EXPECTED}, got {normalized}")
        return 2

    root = data_yaml.parent
    box_counts, img_with_class = count_split(root)
    print(f"\n{'class':<16} {'images':>8} {'boxes':>8}  status")
    weak: list[str] = []
    for i, name in enumerate(EXPECTED):
        n_img = len(img_with_class.get(i, ()))
        n_box = box_counts.get(i, 0)
        ok = n_img >= min_images and n_box >= min_boxes
        status = "OK" if ok else "WEAK"
        if not ok:
            weak.append(name)
        print(f"{name:<16} {n_img:>8} {n_box:>8}  {status}")

    print(f"\nTargets: >={min_images} images and >={min_boxes} boxes per class.")
    if weak:
        print(f"Priority to fix/grow in Roboflow: {', '.join(weak)}")
        print(
            "Universe searches: acne, dark spots, "
            "enlarged pores, wrinkles — clone, map names, merge, new version + aug."
        )
        return 1
    print("All classes meet targets.")
    return 0


def download_roboflow(
    api_key: str, workspace: str, project: str, version: int
) -> Path:
    from roboflow import Roboflow

    dataset = (
        Roboflow(api_key=api_key)
        .workspace(workspace)
        .project(project)
        .version(version)
        .download("yolov8")
    )
    return Path(dataset.location) / "data.yaml"


def main() -> None:
    parser = argparse.ArgumentParser(description="Diagnose 4-class skin YOLO dataset")
    parser.add_argument("--data", type=Path, help="Path to data.yaml")
    parser.add_argument("--roboflow-api-key")
    parser.add_argument("--workspace", default="hamoudas-workspace")
    parser.add_argument("--project", default="face-skin-problems-e7y0m")
    parser.add_argument("--version", type=int, default=2)
    parser.add_argument("--min-images", type=int, default=MIN_IMAGES)
    parser.add_argument("--min-boxes", type=int, default=MIN_BOXES)
    args = parser.parse_args()

    data = args.data
    if data is None:
        if not args.roboflow_api_key:
            parser.error("--data or --roboflow-api-key required")
        data = download_roboflow(
            args.roboflow_api_key, args.workspace, args.project, args.version
        )
    raise SystemExit(diagnose(data, args.min_images, args.min_boxes))


if __name__ == "__main__":
    main()
