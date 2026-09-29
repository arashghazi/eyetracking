"""HTTP surface of the gaze estimator: /info and /estimate. Frames never touch disk."""
from __future__ import annotations

import base64
import binascii
import os

import numpy as np
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from .estimator import GazeEstimator

MAX_IMAGE_BYTES = 2_000_000


class EstimateIn(BaseModel):
    image_b64: str = Field(min_length=16)
    t_ms: int
    frame_w: int = Field(gt=0)
    frame_h: int = Field(gt=0)


def decode_jpeg(image_b64: str) -> np.ndarray:
    import cv2

    try:
        data = base64.b64decode(image_b64, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise HTTPException(status_code=422, detail="image_b64 is not valid base64") from exc
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="image too large")
    arr = cv2.imdecode(np.frombuffer(data, dtype=np.uint8), cv2.IMREAD_COLOR)
    if arr is None:
        raise HTTPException(status_code=422, detail="image could not be decoded")
    return arr


def build_router(estimator: GazeEstimator) -> APIRouter:
    router = APIRouter(tags=["gaze"])

    @router.get("/info")
    def info():
        return estimator.info()

    @router.post("/estimate")
    def estimate(body: EstimateIn):
        bgr = decode_jpeg(body.image_b64)
        result = estimator.estimate(bgr)
        out = result.to_dict()
        out.update({"t_ms": body.t_ms, "frame_w": int(bgr.shape[1]), "frame_h": int(bgr.shape[0]), "model_id": estimator.info()["model_id"]})
        return out

    return router


def estimator_from_env() -> GazeEstimator:
    """EYETRACKING_GAZE_MODEL=synthetic|l2cs, EYETRACKING_GAZE_WEIGHTS=<path to L2CS weights>."""
    from .detector import HaarFaceDetector

    detector = HaarFaceDetector()
    model = os.environ.get("EYETRACKING_GAZE_MODEL", "synthetic").lower()
    if model == "l2cs":
        from .l2cs import L2CSEstimator

        return L2CSEstimator(detector, weights_path=os.environ.get("EYETRACKING_GAZE_WEIGHTS"), device=os.environ.get("EYETRACKING_GAZE_DEVICE", "cpu"))
    from .synthetic import SyntheticEstimator

    return SyntheticEstimator(detector)
