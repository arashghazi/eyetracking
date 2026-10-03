"""L2CS-Net adapter (ResNet-50 backbone, 90 yaw bins and 90 pitch bins over ±180°).

torch and torchvision are optional (`pip install -e ".[l2cs]"`). Without published weights the
adapter reports `synthetic: true`, so an untrained network can exercise the pipeline but never
produce a measurement claim. Weights load from the published `.pkl` or from a `.safetensors` file
with the same keys. Weight files are not part of the repository.
"""
from __future__ import annotations

import os

import numpy as np

from .estimator import FaceDetector, RawEstimate

IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


class L2CSEstimator:
    model_id = "l2cs-net-resnet50"

    def __init__(self, detector: FaceDetector, weights_path: str | None = None, device: str = "cpu", bins: int = 90, input_size: int = 448):
        import torch
        from torch import nn
        from torchvision.models import resnet50

        self._torch = torch
        self._detector = detector
        self._bins = bins
        self._input = input_size
        self._device = torch.device(device)
        backbone = resnet50(weights=None)
        features = backbone.fc.in_features
        backbone.fc = nn.Identity()
        self._backbone = backbone
        self._fc_yaw = nn.Linear(features, bins)
        self._fc_pitch = nn.Linear(features, bins)
        self.weights_loaded = False
        self.model_version = "untrained"
        if weights_path and os.path.exists(weights_path):
            self._load(weights_path)
        self._backbone.to(self._device).eval()
        self._fc_yaw.to(self._device).eval()
        self._fc_pitch.to(self._device).eval()
        self._idx = torch.arange(bins, dtype=torch.float32, device=self._device)

    def _load(self, path: str) -> None:
        if path.lower().endswith(".safetensors"):
            # Same keys as the published .pkl, in a format that cannot run code when read.
            from safetensors.torch import load_file

            state = load_file(path, device="cpu")
        else:
            state = self._torch.load(path, map_location="cpu")
        if isinstance(state, dict) and "state_dict" in state:
            state = state["state_dict"]
        backbone_state = {k: v for k, v in state.items() if not k.startswith(("fc_yaw_gaze", "fc_pitch_gaze", "fc_finetune", "fc."))}
        missing, unexpected = self._backbone.load_state_dict(backbone_state, strict=False)
        yaw = {k.replace("fc_yaw_gaze.", ""): v for k, v in state.items() if k.startswith("fc_yaw_gaze.")}
        pitch = {k.replace("fc_pitch_gaze.", ""): v for k, v in state.items() if k.startswith("fc_pitch_gaze.")}
        if not yaw or not pitch or any(k.startswith("layer") for k in missing):
            raise ValueError(f"unexpected L2CS weight layout in {path}: missing={list(missing)[:3]} unexpected={list(unexpected)[:3]}")
        self._fc_yaw.load_state_dict(yaw)
        self._fc_pitch.load_state_dict(pitch)
        self.weights_loaded = True
        self.model_version = os.path.basename(path)

    def info(self) -> dict:
        return {
            "model_id": self.model_id,
            "model_version": self.model_version,
            "synthetic": not self.weights_loaded,
            "face_detector": type(self._detector).__name__,
            "max_fps": 10,
        }

    def _preprocess(self, bgr: np.ndarray, box: list[int]) -> "np.ndarray":
        import cv2

        x, y, w, h = box
        fh, fw = bgr.shape[:2]
        pad_w, pad_h = int(w * 0.15), int(h * 0.15)
        x0, y0 = max(0, x - pad_w), max(0, y - pad_h)
        x1, y1 = min(fw, x + w + pad_w), min(fh, y + h + pad_h)
        crop = bgr[y0:y1, x0:x1]
        rgb = cv2.cvtColor(cv2.resize(crop, (self._input, self._input)), cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
        rgb = (rgb - np.array(IMAGENET_MEAN, dtype=np.float32)) / np.array(IMAGENET_STD, dtype=np.float32)
        return np.transpose(rgb, (2, 0, 1))

    def estimate(self, bgr: np.ndarray) -> RawEstimate:
        found = self._detector.detect(bgr)
        if found is None:
            return RawEstimate.no_face()
        box, face_conf = found
        torch = self._torch
        tensor = torch.from_numpy(self._preprocess(bgr, box)).unsqueeze(0).to(self._device)
        with torch.no_grad():
            feats = self._backbone(tensor)
            yaw_p = torch.softmax(self._fc_yaw(feats), dim=1)
            pitch_p = torch.softmax(self._fc_pitch(feats), dim=1)
            yaw = float((yaw_p * self._idx).sum(dim=1).item() * 4 - 180)
            pitch = float((pitch_p * self._idx).sum(dim=1).item() * 4 - 180)
            conf = float((yaw_p.max().item() + pitch_p.max().item()) / 2)
        return RawEstimate(True, list(box), face_conf, yaw, pitch, conf)
