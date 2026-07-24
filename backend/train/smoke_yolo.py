"""Smoke-test LocalAnalyzer YOLO hook against models/best.onnx (Step 5).

Creates a blank BGR image and calls _yolo_scores so a bad ONNX fails loudly.
Does not require the full FastAPI stack.

Usage (from backend/)::

    python -m train.smoke_yolo
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import cv2
import numpy as np


def main() -> int:
    backend = Path(__file__).resolve().parents[1]
    os.chdir(backend)
    model = backend / "models" / "best.onnx"
    if not model.is_file():
        print(f"MISSING {model}")
        return 1

    os.environ["SKIN_YOLO_MODEL_PATH"] = str(model)

    # Import after env + cwd so local.py resolves relative paths if needed
    sys.path.insert(0, str(backend))
    from app.skin.local import CLASS_TO_CONDITION, LocalAnalyzer

    assert list(CLASS_TO_CONDITION.values()) == [
        "acne",
        "dark_spots",
        "enlarged_pores",
        "wrinkles",
    ], CLASS_TO_CONDITION

    img = np.zeros((640, 640, 3), dtype=np.uint8)
    # mild noise so the graph isn't a pure zero edge-case
    cv2.randn(img, 40, 15)

    analyzer = LocalAnalyzer()
    scores = analyzer._yolo_scores(img)
    print(f"CLASS_TO_CONDITION: {CLASS_TO_CONDITION}")
    print(f"_yolo_scores on blank image: {scores}")
    print(
        "OK - YOLO hook ran (empty/low scores on blank image are expected). "
        "Restart backend with ANALYSIS_ENGINE=auto for a real photo test."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
