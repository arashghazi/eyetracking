"""Private file storage for approved content media. Files live outside the web root and are only
reachable through signed URLs."""
from __future__ import annotations

import os
import re

_SAFE = re.compile(r"^[A-Za-z0-9._-]{1,120}$")


def safe_key(key: str) -> str:
    if not _SAFE.match(key or "") or key.startswith("."):
        raise ValueError("media key may only contain letters, digits, dot, dash and underscore")
    return key


class LocalMediaStore:
    def __init__(self, root: str):
        self.root = os.path.abspath(root)

    def save(self, relative_path: str, data: bytes) -> str:
        full = self.absolute(relative_path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as fh:
            fh.write(data)
        return relative_path

    def absolute(self, relative_path: str) -> str:
        full = os.path.abspath(os.path.join(self.root, relative_path))
        if not full.startswith(self.root + os.sep):
            raise ValueError("invalid media path")
        return full
