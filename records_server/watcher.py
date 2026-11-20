"""Read-only SaveData file resolver, polling watcher, and SSE pub/sub broadcaster."""

from __future__ import annotations

import json
import os
from pathlib import Path
import queue
import sys
import threading
import time
from typing import Any

try:
    from .leaderboard import build_snapshot
    from .tres_parser import TresParseError, parse_tres_file
except ImportError:
    from leaderboard import build_snapshot
    from tres_parser import TresParseError, parse_tres_file

_EMPTY_PARSED: dict[str, Any] = {
    "player_name": "PLAYER",
    "records": {},
    "player_profiles": {},
}


def default_godot_user_save_path() -> Path:
    """Return Godot's OS-specific `user://save_data.tres` path for project `Juego`."""
    if sys.platform.startswith("win"):
        base = Path(os.environ.get("APPDATA", str(Path.home())))
        return base / "Godot" / "app_userdata" / "Juego" / "save_data.tres"
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Godot" / "app_userdata" / "Juego" / "save_data.tres"
    xdg_data = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(xdg_data) / "godot" / "app_userdata" / "Juego" / "save_data.tres"


def resolve_active_save_path(
    explicit_path: Path | None,
    repo_root: Path,
) -> tuple[Path, bool]:
    """Resolve the active `save_data.tres` path without modifying any game files."""
    if explicit_path is not None:
        resolved = explicit_path.expanduser()
        return resolved, resolved.is_file()

    candidates = [
        default_godot_user_save_path(),
        repo_root / "juego" / "data" / "save_data.tres",
    ]
    best_path: Path | None = None
    best_mtime_ns = -1

    for candidate in candidates:
        try:
            st = candidate.stat()
        except OSError:
            continue
        if not candidate.is_file():
            continue
        if st.st_mtime_ns > best_mtime_ns:
            best_mtime_ns = st.st_mtime_ns
            best_path = candidate

    if best_path is not None:
        return best_path, True
    return candidates[0], False


class SaveWatcher:
    """Polls `save_data.tres` read-only and broadcasts snapshot updates to subscribers."""

    def __init__(
        self,
        explicit_save_file: Path | None = None,
        repo_root: Path | None = None,
        poll_interval: float = 0.4,
        max_parse_retries: int = 3,
        retry_delay: float = 0.03,
    ) -> None:
        self._explicit_path = explicit_save_file
        self._repo_root = repo_root or Path(__file__).resolve().parent.parent
        self._poll_interval = max(0.05, float(poll_interval))
        self._max_parse_retries = max(1, int(max_parse_retries))
        self._retry_delay = max(0.0, float(retry_delay))

        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._subscribers: set[queue.Queue[str | None]] = set()

        self._profiles: dict[str, dict[str, Any]] | None = None
        self._snapshot: dict[str, Any] = {}
        self._snapshot_json: str = "{}"
        self._last_signature: tuple[str, bool, int | None, int | None] | None = None
        self._last_failed_signature: tuple[str, bool, int | None, int | None] | None = None
        self._thread: threading.Thread | None = None

        self._poll_once(initial=True)

    def start(self) -> None:
        """Start the background polling daemon thread."""
        with self._lock:
            if self._thread is not None and self._thread.is_alive():
                return
            self._stop_event.clear()
            self._thread = threading.Thread(
                target=self._run_loop,
                name="SaveWatcherThread",
                daemon=True,
            )
            self._thread.start()

    def stop(self) -> None:
        """Stop the polling thread and unblock any waiting SSE subscriber queues."""
        self._stop_event.set()
        with self._lock:
            subscribers = list(self._subscribers)
        for sub_q in subscribers:
            self._put_latest(sub_q, None)
        thread = self._thread
        if thread is not None and thread.is_alive():
            thread.join(timeout=2.0)

    def get_snapshot(self) -> dict[str, Any]:
        """Return a copy of the latest leaderboard snapshot."""
        with self._lock:
            return dict(self._snapshot)

    def get_snapshot_json(self) -> str:
        """Return the pre-serialized JSON string of the latest leaderboard snapshot."""
        with self._lock:
            return self._snapshot_json

    def subscribe(self) -> queue.Queue[str | None]:
        """Register an SSE subscriber queue for live snapshot JSON broadcasts."""
        sub_q: queue.Queue[str | None] = queue.Queue(maxsize=16)
        with self._lock:
            self._subscribers.add(sub_q)
        return sub_q

    def unsubscribe(self, sub_q: queue.Queue[str | None]) -> None:
        """Remove an SSE subscriber queue."""
        with self._lock:
            self._subscribers.discard(sub_q)

    def _run_loop(self) -> None:
        while not self._stop_event.wait(self._poll_interval):
            try:
                self._poll_once(initial=False)
            except Exception as exc:  # pragma: no cover - defensive guard for background thread
                print(f"[watcher] Unexpected polling error: {exc}", file=sys.stderr, flush=True)

    def _read_signature(self, path: Path) -> tuple[bool, int | None, int | None]:
        try:
            st = path.stat()
            if path.is_file():
                return True, st.st_mtime_ns, st.st_size
        except OSError:
            pass
        return False, None, None

    def _poll_once(self, initial: bool) -> None:
        active_path, exists = resolve_active_save_path(self._explicit_path, self._repo_root)
        if not exists and not initial and self._last_signature is not None and self._last_signature[1]:
            # Give an in-flight atomic file replacement a brief moment to settle.
            time.sleep(self._retry_delay)
            active_path, exists = resolve_active_save_path(self._explicit_path, self._repo_root)

        file_exists, mtime_ns, size = self._read_signature(active_path)
        sig = (str(active_path), file_exists, mtime_ns, size)

        if not initial and sig == self._last_signature:
            return
        if not initial and sig == self._last_failed_signature:
            return

        if not file_exists:
            snapshot, new_profiles = build_snapshot(
                _EMPTY_PARSED,
                source_path=str(active_path),
                source_exists=False,
                mtime=None,
                previous_profiles=None if initial else self._profiles,
            )
            self._commit_snapshot(sig, snapshot, new_profiles, broadcast=not initial)
            return

        parsed: dict[str, Any] | None = None
        last_err: Exception | None = None
        latest_mtime: float | None = (mtime_ns / 1_000_000_000.0) if mtime_ns is not None else None

        for attempt in range(self._max_parse_retries):
            try:
                st = active_path.stat()
                latest_mtime = st.st_mtime
                sig = (str(active_path), True, st.st_mtime_ns, st.st_size)
                parsed = parse_tres_file(active_path)
                break
            except (OSError, TresParseError, UnicodeDecodeError) as exc:
                last_err = exc
                if attempt + 1 < self._max_parse_retries and not self._stop_event.is_set():
                    time.sleep(self._retry_delay)

        if parsed is None:
            if sig != self._last_failed_signature:
                print(
                    f"[watcher] Warning: failed to parse {active_path} ({last_err}); keeping last valid snapshot.",
                    file=sys.stderr,
                    flush=True,
                )
                self._last_failed_signature = sig
            if initial and not self._snapshot:
                snapshot, new_profiles = build_snapshot(
                    _EMPTY_PARSED,
                    source_path=str(active_path),
                    source_exists=True,
                    mtime=latest_mtime,
                    previous_profiles=None,
                )
                self._commit_snapshot(None, snapshot, new_profiles, broadcast=False)
            return

        self._last_failed_signature = None
        snapshot, new_profiles = build_snapshot(
            parsed,
            source_path=str(active_path),
            source_exists=True,
            mtime=latest_mtime,
            previous_profiles=None if initial else self._profiles,
        )
        self._commit_snapshot(sig, snapshot, new_profiles, broadcast=not initial)

    def _commit_snapshot(
        self,
        sig: tuple[str, bool, int | None, int | None] | None,
        snapshot: dict[str, Any],
        new_profiles: dict[str, dict[str, Any]],
        broadcast: bool,
    ) -> None:
        payload_json = json.dumps(snapshot, ensure_ascii=False, separators=(",", ":"))
        with self._lock:
            changed = payload_json != self._snapshot_json
            if sig is not None:
                self._last_signature = sig
            self._profiles = new_profiles
            self._snapshot = snapshot
            self._snapshot_json = payload_json
            subscribers = list(self._subscribers) if (broadcast and changed) else []

        for sub_q in subscribers:
            self._put_latest(sub_q, payload_json)

    @staticmethod
    def _put_latest(sub_q: queue.Queue[str | None], item: str | None) -> None:
        while True:
            try:
                sub_q.put_nowait(item)
                return
            except queue.Full:
                try:
                    sub_q.get_nowait()
                except queue.Empty:
                    return
