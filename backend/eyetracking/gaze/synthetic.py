"""Development estimator: head position stands in for gaze. Never a measurement."""
from __future__ import annotations

import numpy as np

from .estimator import FaceDetector, RawEstimate


class SyntheticEstimator:
    model_id = "synthetic-head-proxy"
    model_version = "0"

    def __init__(self, detector: FaceDetector):
        self._detector = detector

    def info(self) -> dict:
        return {
            "model_id": self.model_id,
            "model_version": self.model_version,
            "synthetic": True,
            "face_detector": type(self._detector).__name__,
            "max_fps": 15,
        }

    def estimate(self, bgr: np.ndarray) -> RawEstimate:
        found = self._detector.detect(bgr)
        if found is None:
            return RawEstimate.no_face()
        (x, y, w, h), conf = found
        fh, fw = bgr.shape[:2]
        cx = (x + w / 2) / fw
        cy = (y + h / 2) / fh
        yaw = float((0.5 - cx) * 60.0)
        pitch = float((0.5 - cy) * 40.0)
        return RawEstimate(True, [x, y, w, h], conf, yaw, pitch, 0.6)
