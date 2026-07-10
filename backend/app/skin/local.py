"""Moteur local (Phase 2) — zones MediaPipe, rougeurs OpenCV, type de peau HF.

État actuel :
- rougeurs (canal a* CIELAB sur joues/nez) : fonctionnel ;
- type de peau : HF `dima806/skin_types_image_detection` + logique T-zone
  pour détecter `combination` ;
- autres conditions : hooks YOLOv8-ONNX, actifs uniquement si
  SKIN_YOLO_MODEL_PATH pointe vers un modèle exporté (train/train_yolo.py) ;
  sinon leurs scores restent à 0.

Les dépendances lourdes (mediapipe, transformers, torch) sont importées
paresseusement : requirements-phase2.txt.
"""
from __future__ import annotations

import logging
import os

import cv2
import numpy as np

from .analyzer import (
    CONDITION_CODES,
    EngineUnavailableError,
    NoFaceError,
    SkinAnalyzer,
    SkinPhotoResult,
)

logger = logging.getLogger("skin.local")

# Ordre des classes du modèle YOLO (doit correspondre au data.yaml d'entraînement).
CLASS_TO_CONDITION = {
    0: "acne",
    1: "blackheads",
    2: "dark_spots",
    3: "enlarged_pores",
    4: "wrinkles",
}

# Indices de landmarks FaceMesh (468 points) approximant chaque zone.
ZONE_LANDMARKS = {
    "forehead": [10, 67, 69, 104, 108, 151, 297, 299, 333, 337],
    "nose": [1, 4, 5, 6, 19, 44, 45, 51, 274, 275, 281],
    "left_cheek": [50, 101, 118, 123, 187, 205, 207],
    "right_cheek": [280, 330, 347, 352, 411, 425, 427],
    "chin": [18, 32, 148, 152, 175, 199, 262, 377],
}

# Seuils de la logique « peau mixte » (fractions de pixels spéculaires).
T_ZONE_OILY_MIN = 0.08
CHEEK_MATTE_MAX = 0.02


def redness_score(img_bgr: np.ndarray, mask: np.ndarray | None = None) -> int:
    """Rougeur 0-100 depuis le canal a* CIELAB (128 = neutre en OpenCV)."""
    lab = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2LAB)
    a_channel = lab[:, :, 1].astype(np.float32)
    if mask is not None:
        values = a_channel[mask > 0]
        if values.size == 0:
            values = a_channel.reshape(-1)
    else:
        values = a_channel.reshape(-1)
    mean_a = float(values.mean())
    # ~132 = teint neutre ; chaque point au-dessus compte pour 6 points de score.
    return int(np.clip((mean_a - 132.0) * 6.0, 0.0, 100.0))


def oiliness_proxy(gray_values: np.ndarray) -> float:
    """Fraction de pixels spéculaires (>230) — proxy simple de brillance/séborrhée."""
    if gray_values.size == 0:
        return 0.0
    return float((gray_values > 230).mean())


def combine_skin_type(
    base_type: str, t_zone_oiliness: float, cheek_oiliness: float
) -> str:
    """`combination` si la T-zone brille alors que les joues sont mates."""
    if t_zone_oiliness >= T_ZONE_OILY_MIN and cheek_oiliness <= CHEEK_MATTE_MAX:
        return "combination"
    return base_type


class LocalAnalyzer(SkinAnalyzer):
    """Moteur local gratuit — remplacera Face++ une fois les poids YOLO entraînés."""

    name = "local"

    def __init__(self):
        self._face_mesh = None
        self._skin_type_pipe = None
        self._yolo_session = None

    # ---------- chargements paresseux ----------

    def _get_face_mesh(self):
        if self._face_mesh is None:
            try:
                import mediapipe as mp
            except ImportError as exc:
                raise EngineUnavailableError(
                    "Moteur local : installer requirements-phase2.txt (mediapipe)."
                ) from exc
            self._face_mesh = mp.solutions.face_mesh.FaceMesh(
                static_image_mode=True, max_num_faces=1, refine_landmarks=False
            )
        return self._face_mesh

    def _get_skin_type_pipe(self):
        if self._skin_type_pipe is None:
            try:
                from transformers import pipeline
            except ImportError as exc:
                raise EngineUnavailableError(
                    "Moteur local : installer requirements-phase2.txt (transformers)."
                ) from exc
            self._skin_type_pipe = pipeline(
                "image-classification", model="dima806/skin_types_image_detection"
            )
        return self._skin_type_pipe

    # ---------- étapes d'analyse ----------

    def _landmarks(self, img_bgr: np.ndarray) -> np.ndarray:
        mesh = self._get_face_mesh()
        result = mesh.process(cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB))
        if not result.multi_face_landmarks:
            raise NoFaceError("aucun visage détecté (moteur local).")
        height, width = img_bgr.shape[:2]
        landmarks = result.multi_face_landmarks[0].landmark
        return np.array(
            [[p.x * width, p.y * height] for p in landmarks], dtype=np.int32
        )

    def _zone_mask(
        self, shape: tuple, points: np.ndarray, indices: list[int]
    ) -> np.ndarray:
        mask = np.zeros(shape[:2], np.uint8)
        hull = cv2.convexHull(points[indices])
        cv2.fillConvexPoly(mask, hull, 255)
        return mask

    def _classify_skin_type(self, img_bgr: np.ndarray) -> str:
        try:
            from PIL import Image
        except ImportError as exc:
            raise EngineUnavailableError(
                "Moteur local : installer requirements-phase2.txt (pillow)."
            ) from exc

        pipe = self._get_skin_type_pipe()
        rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
        predictions = pipe(Image.fromarray(rgb))
        label = max(predictions, key=lambda p: p["score"])["label"].lower()
        if "dry" in label:
            return "dry"
        if "oily" in label:
            return "oily"
        return "normal"

    def _yolo_scores(self, img_bgr: np.ndarray) -> dict[str, int]:
        """Inférence ONNX (export ultralytics nms=True). {} si pas de modèle."""
        model_path = os.getenv("SKIN_YOLO_MODEL_PATH", "").strip()
        if not model_path or not os.path.exists(model_path):
            return {}
        # onnxruntime est déjà dans requirements.txt (InsightFace) — pas une dep Phase 2.
        try:
            import onnxruntime as ort

            if self._yolo_session is None:
                self._yolo_session = ort.InferenceSession(
                    model_path, providers=["CPUExecutionProvider"]
                )
            model_input = self._yolo_session.get_inputs()[0]
            size = model_input.shape[2] if isinstance(model_input.shape[2], int) else 640
            resized = cv2.resize(img_bgr, (size, size))
            blob = cv2.cvtColor(resized, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
            blob = blob.transpose(2, 0, 1)[None]
            detections = self._yolo_session.run(None, {model_input.name: blob})[0][0]
            best: dict[str, float] = {}
            for det in detections:  # (x1, y1, x2, y2, conf, cls)
                confidence, cls = float(det[4]), int(det[5])
                condition = CLASS_TO_CONDITION.get(cls)
                if condition and confidence > best.get(condition, 0.0):
                    best[condition] = confidence
            return {c: round(v * 100) for c, v in best.items()}
        except Exception:  # modèle invalide/sortie inattendue : on dégrade sans bloquer
            logger.warning("Hooks YOLO ignorés (modèle ou sortie ONNX invalide).", exc_info=True)
            return {}

    async def analyze_photo(self, image_bytes: bytes) -> SkinPhotoResult:
        arr = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is None:
            raise NoFaceError("image illisible (moteur local).")

        points = self._landmarks(img)
        masks = {
            zone: self._zone_mask(img.shape, points, indices)
            for zone, indices in ZONE_LANDMARKS.items()
        }

        scores = {condition: 0 for condition in CONDITION_CODES}
        cheeks_nose = cv2.bitwise_or(
            cv2.bitwise_or(masks["left_cheek"], masks["right_cheek"]), masks["nose"]
        )
        scores["redness"] = redness_score(img, cheeks_nose)
        scores.update(self._yolo_scores(img))

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        t_zone = cv2.bitwise_or(masks["forehead"], masks["nose"])
        cheeks = cv2.bitwise_or(masks["left_cheek"], masks["right_cheek"])
        base_type = self._classify_skin_type(img)
        skin_type = combine_skin_type(
            base_type,
            oiliness_proxy(gray[t_zone > 0]),
            oiliness_proxy(gray[cheeks > 0]),
        )

        zones: dict[str, list[str]] = {}
        if scores["redness"] >= 30:
            zones["redness"] = ["left_cheek", "right_cheek", "nose"]
        return SkinPhotoResult(scores=scores, skin_type=skin_type, zones=zones)
