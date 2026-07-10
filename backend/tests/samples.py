"""Bloc `result` d'exemple de l'API Face++ Skin Analyze (format documenté v1)."""

FACEPP_SAMPLE_RESULT = {
    "skin_type": {
        "skin_type": 0,  # 0=grasse, 1=sèche, 2=normale, 3=mixte
        "details": {
            "0": {"value": 1, "confidence": 0.89},
            "1": {"value": 0, "confidence": 0.05},
            "2": {"value": 0, "confidence": 0.04},
            "3": {"value": 0, "confidence": 0.02},
        },
    },
    "acne": {"value": 1, "confidence": 0.62},
    "blackhead": {"value": 1, "confidence": 0.55},
    "skin_spot": {"value": 0, "confidence": 0.88},
    "dark_circle": {"value": 1, "confidence": 0.71},
    "forehead_wrinkle": {"value": 0, "confidence": 0.93},
    "crows_feet": {"value": 1, "confidence": 0.44},
    "eye_finelines": {"value": 0, "confidence": 0.80},
    "glabella_wrinkle": {"value": 0, "confidence": 0.85},
    "nasolabial_fold": {"value": 1, "confidence": 0.52},
    "pores_forehead": {"value": 1, "confidence": 0.66},
    "pores_left_cheek": {"value": 0, "confidence": 0.90},
    "pores_right_cheek": {"value": 0, "confidence": 0.84},
    "pores_jaw": {"value": 1, "confidence": 0.58},
}
