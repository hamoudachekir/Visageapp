"""Post-train evaluation helper for Ultralytics runs (Step 3).

Reads results.csv from a detect/train* folder and prints per-class hints.
Also lists the key PNG artefacts to open.

Usage::

    python -m train.evaluate_run --run runs/detect/train
    python -m train.evaluate_run --run path/to/results.csv
"""
from __future__ import annotations

import argparse
import csv
from pathlib import Path

# Realistic destination after solid data work (not 0.8).
TARGET_MAP50 = 0.35
WEAK_CLASS_MAP50 = 0.10


def _find_results_csv(run: Path) -> Path:
    if run.is_file() and run.name == "results.csv":
        return run
    csv_path = run / "results.csv"
    if not csv_path.is_file():
        raise SystemExit(f"results.csv not found under {run}")
    return csv_path


def evaluate(run: Path) -> int:
    csv_path = _find_results_csv(run)
    root = csv_path.parent

    print("=== Step 3 artefacts ===")
    for name in (
        "results.png",
        "confusion_matrix.png",
        "PR_curve.png",
        "results.csv",
    ):
        path = root / name
        print(f"  {'OK' if path.exists() else '-'} {path}")

    rows: list[dict[str, str]] = []
    with csv_path.open(encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print("results.csv is empty")
        return 1

    # Ultralytics columns vary slightly by version; pick last epoch.
    last = {k.strip(): v.strip() for k, v in rows[-1].items()}
    map_key = next(
        (k for k in last if "mAP50" in k and "mAP50-95" not in k.replace(" ", "")),
        None,
    )
    # Prefer metrics/mAP50(B)
    candidates = [k for k in last if "map50" in k.lower().replace(" ", "")]
    map50_keys = [k for k in candidates if "95" not in k]
    map_key = map50_keys[0] if map50_keys else map_key

    print("\n=== Last epoch summary ===")
    for k, v in last.items():
        if any(s in k.lower() for s in ("map", "precision", "recall")):
            print(f"  {k}: {v}")

    if map_key:
        try:
            map50 = float(last[map_key])
        except ValueError:
            map50 = None
        if map50 is not None:
            print(f"\nmAP50 ({map_key}) = {map50:.4f}")
            if map50 < TARGET_MAP50:
                print(
                    f"Below ~{TARGET_MAP50} target -> more/cleaner Roboflow data "
                    "(Step 1), then bump VERSION and retrain."
                )
            else:
                print(f"At/above ~{TARGET_MAP50} interim target - export ONNX next.")
            # Rising curve heuristic: compare first half vs last epoch
            mid = rows[len(rows) // 2]
            mid_val = mid.get(map_key, "").strip()
            try:
                mid_map = float(mid_val)
                if map50 > mid_map + 0.02 and abs(map50 - float(rows[-2].get(map_key, map50))) < 0.005:
                    print(
                        "Curve may still be rising near the end -> try more epochs "
                        "or more data before concluding."
                    )
            except ValueError:
                pass

    print(
        "\nPer-class: open confusion_matrix.png / PR_curve.png. "
        f"Any class stuck near 0 (<{WEAK_CLASS_MAP50}) after a real data fix "
        "-> tighten labels and add domain photos (keep 5 classes)."
    )
    print(
        "\nExport: copy weights/best.onnx -> backend/models/best.onnx "
        "(SKIN_YOLO_MODEL_PATH=models/best.onnx)."
    )
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate a YOLO train run (Step 3)")
    parser.add_argument(
        "--run",
        type=Path,
        required=True,
        help="runs/detect/train* directory or path to results.csv",
    )
    args = parser.parse_args()
    raise SystemExit(evaluate(args.run))


if __name__ == "__main__":
    main()
