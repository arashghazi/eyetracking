"""Face detection adapters. The Haar cascade ships with OpenCV and needs no download."""
from __future__ import annotations

import numpy as np


class HaarFaceDetector:
    def __init__(self, min_size: int = 60):
        import cv2

        self._cv2 = cv2
        self._cascade = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
        self._min_size = min_size

    def detect(self, bgr: np.ndarray) -> tuple[list[int], float] | None:
        gray = self._cv2.cvtColor(bgr, self._cv2.COLOR_BGR2GRAY)
        faces, _, weights = self._cascade.detectMultiScale3(
            gray, scaleFactor=1.1, minNeighbors=5, minSize=(self._min_size, self._min_size), outputRejectLevels=True
        )
        if len(faces) == 0:
            return None
        best = int(np.argmax([w * h for (_, _, w, h) in faces]))
        x, y, w, h = (int(v) for v in faces[best])
        weight = float(np.ravel(weights)[best]) if len(weights) else 3.0
        conf = max(0.0, min(1.0, weight / 8.0))
        return [x, y, w, h], conf


class FixedBoxDetector:
    """Test double: always reports one face box."""

    def __init__(self, box: list[int] | None, conf: float = 0.9):
        self.box = box
        self.conf = conf

    def detect(self, bgr: np.ndarray) -> tuple[list[int], float] | None:
        return (list(self.box), self.conf) if self.box else None
