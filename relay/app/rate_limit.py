from __future__ import annotations

from collections import defaultdict, deque
from dataclasses import dataclass
import threading
import time


@dataclass
class PhonePairingRateLimiter:
    max_attempts: int
    window_seconds: int

    def __post_init__(self) -> None:
        self._attempts: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def _prune(self, key: str, *, now: float) -> deque[float]:
        attempts = self._attempts[key]
        cutoff = now - self.window_seconds
        while attempts and attempts[0] < cutoff:
            attempts.popleft()
        return attempts

    def is_limited(self, key: str) -> bool:
        if not key:
            return False

        now = time.monotonic()
        with self._lock:
            attempts = self._prune(key, now=now)
            return len(attempts) >= self.max_attempts

    def register_failure(self, key: str) -> None:
        if not key:
            return

        now = time.monotonic()
        with self._lock:
            attempts = self._prune(key, now=now)
            attempts.append(now)

