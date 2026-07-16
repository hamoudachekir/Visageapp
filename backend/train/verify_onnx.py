"""Verify backend/models/best.onnx is loadable for LocalAnalyzer (Step 5).

Checks:
  - file exists
  - ONNX input spatial size (auto-detected by local engine)
  - session runs a dummy forward without crashing

Usage (from backend/)::

    python -m train.verify_onnx
    python -m train.verify_onnx --path models/best.onnx
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import numpy as np

# CLASS_TO_CONDITION order must stay in sync with the trained model.
EXPECTED_CLASSES = 5


def verify(path: Path) -> int:
    if not path.is_file():
        print(f"MISSING: {path}")
        print(
            "After Colab export, copy best.onnx here and set "
            "SKIN_YOLO_MODEL_PATH=models/best.onnx in .env"
        )
        return 1

    try:
        import onnxruntime as ort
    except ImportError:
        print("onnxruntime not installed - pip install onnxruntime")
        return 1

    session = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
    inp = session.get_inputs()[0]
    shape = inp.shape
    # NCHW — H/W may be dynamic (str) on some exports
    h = shape[2] if isinstance(shape[2], int) else 1024
    w = shape[3] if len(shape) > 3 and isinstance(shape[3], int) else h
    print(f"OK file: {path} ({path.stat().st_size / 1e6:.1f} MB)")
    print(f"OK input: name={inp.name} shape={shape} -> infer size {h}x{w}")

    blob = np.zeros((1, 3, h, w), dtype=np.float32)
    out = session.run(None, {inp.name: blob})[0]
    print(f"OK forward: output shape={getattr(out, 'shape', type(out))}")

    # LocalAnalyzer maps cls 0..4 → 5 conditions
    print(
        f"Expected class ids 0..{EXPECTED_CLASSES - 1} "
        "(acne, blackheads, dark_spots, enlarged_pores, wrinkles)"
    )

    env_path = os.getenv("SKIN_YOLO_MODEL_PATH", "").strip()
    if env_path:
        print(f"SKIN_YOLO_MODEL_PATH={env_path}")
        if not Path(env_path).is_file() and not (Path.cwd() / env_path).is_file():
            print(f"WARNING: env path not found from cwd={Path.cwd()}")
    else:
        print(
            "HINT: set SKIN_YOLO_MODEL_PATH=models/best.onnx and "
            "ANALYSIS_ENGINE=auto in backend/.env"
        )
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify skin YOLO ONNX for backend")
    parser.add_argument(
        "--path",
        type=Path,
        default=Path("models/best.onnx"),
        help="Path to best.onnx (default: models/best.onnx)",
    )
    args = parser.parse_args()
    # Allow running from repo root or backend/
    path = args.path
    if not path.is_file():
        alt = Path("backend") / path
        if alt.is_file():
            path = alt
    raise SystemExit(verify(path))


if __name__ == "__main__":
    main()
