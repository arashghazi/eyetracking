from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Protocol

import numpy as np


@dataclass(frozen=True)
class RawEstimate:
    face_detected: bool
    face_box: list[int] | None
    face_conf: float
    yaw_deg: float | None
    pitch_deg: float | None
    gaze_conf: float

    def to_dict(self) -> dict:
        return asdict(self)

    @staticmethod
    def no_face() -> "RawEstimate":
        return RawEstimate(False, None, 0.0, None, None, 0.0)


class FaceDetector(Protocol):
    def detect(self, bgr: np.ndarray) -> tuple[list[int], float] | None: ...


class GazeEstimator(Protocol):
    def info(self) -> dict: ...
    def estimate(self, bgr: np.ndarray) -> RawEstimate: ...
