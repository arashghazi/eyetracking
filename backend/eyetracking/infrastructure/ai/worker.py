"""Background job runner: one thread, its own unit of work per pass, stops on shutdown."""
from __future__ import annotations

import logging
import threading

log = logging.getLogger("eyetracking.ai.worker")


class AiWorker:
    def __init__(self, session_factory, providers, store, clock, interval_s: int = 5):
        self._session_factory = session_factory
        self._providers = providers
        self._store = store
        self._clock = clock
        self._interval = max(1, int(interval_s))
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if self._thread is None:
            self._thread = threading.Thread(target=self._loop, name="ai-worker", daemon=True)
            self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=10)
            self._thread = None

    def run_once(self, max_jobs: int = 5) -> dict:
        from eyetracking.application.ai_use_cases import run_jobs
        from eyetracking.infrastructure.uow import SqlUnitOfWork

        uow = SqlUnitOfWork(self._session_factory)
        try:
            return run_jobs(uow, self._providers, self._store, self._clock, max_jobs=max_jobs)
        finally:
            uow.close()

    def _loop(self) -> None:
        while not self._stop.is_set():
            try:
                self.run_once()
            except Exception:  # noqa: BLE001
                log.exception("ai worker pass failed")
            self._stop.wait(self._interval)
