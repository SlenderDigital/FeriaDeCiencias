#!/usr/bin/env bash
# Abstract Pulse — MediaPipe hand tracker.
#
# Captures the webcam and streams the 21 hand landmarks over UDP to
# 127.0.0.1:5005. The Godot game (HandTrackingClient autoload) listens on that
# socket and uses the landmarks to move and rotate the ship.
#
# The tracking lives inside this repo in tracker_server/. No external deps.
# Runs the REAL tracker (python -m mediapipe_py.main) — NOT the __init__.py stub.
#
# Usage:
#   ./run_tracker.sh              # foreground (manual)
#   ./run_tracker.sh --detach    # background, detached from caller
#
# WATCHDOG: when launched BY THE GAME, this script monitors its PARENT (the
# game process). As soon as the game dies — for any reason (Quit button, Alt+F4,
# crash, SIGKILL) — the watchdog tears down the camera. The game does NOT need
# to clean up anything: when the game process ends, the tracker ends with it.
#
# This is bulletproof against the Godot `_exit_tree` not firing on every close
# (Alt+F4 / Win+W), and against `OS.kill()` being async/unreliable in Godot 4.x.
#
# IMPORTANT: do NOT use `uv run mediapipe-py` — that entrypoint points at the
# __init__.py stub ("Hello from mediapipe-py!") and never starts the camera.
set -euo pipefail

# Absolute path of THIS script (needed for --detach self-relaunch).
SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$SCRIPT")/tracker_server"

LOCK=".tracker.pid"
STATUS=".tracker.status"
LOG=".tracker.log"
GAME_EXIT_FLAG=".tracker.game_exit"

# --detach: relaunch detached (PPID becomes init, so watchdog won't kill it:
#          it runs until you close with q/ESC).
if [ "${1:-}" = "--detach" ]; then
    nohup setsid "$SCRIPT" >/dev/null 2>&1 </dev/null &
    exit 0
fi

# Idempotent: if a live instance already exists (from the game or manual), don't duplicate.
if [ -f "$LOCK" ] && [ -n "$(cat "$LOCK" 2>/dev/null)" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
    echo "[tracker] Already running (PID $(cat "$LOCK")). Not starting another."
    exit 0
fi

# Deps already installed in the venv. If missing, tell the user once.
if [ ! -x ".venv/bin/python" ]; then
    echo "[tracker] ERROR: .venv missing. Install once: cd tracker_server && uv sync" >&2
    echo "error:noinst" > "$STATUS"
    exit 1
fi

# ---- Bulletproof watchdog: capture the ORIGINAL parent PID once, upfront. ----
# $PPID is dynamic and changes when we get adopted by init after the game dies.
# We must snapshot it NOW so the watchdog loop always checks the REAL game PID.
WATCH_PARENT="$PPID"
echo "[tracker] Watching parent PID $WATCH_PARENT (game)."
echo $$ > "$LOCK"

child=""
_cleanup() {
    rm -f "$LOCK" "$STATUS" "$GAME_EXIT_FLAG"
    if [ -n "$child" ]; then
        kill "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
    fi
}
trap '_cleanup; exit 0' INT TERM EXIT

echo "[tracker] MediaPipe hand tracker -> UDP 127.0.0.1:5005 (camera 0)."
echo "[tracker] Close via 'q' or ESC in the tracker window."
".venv/bin/python" -m mediapipe_py.main > "$LOG" 2>&1 &
child=$!

# ---- Watchdog loop: keep running while BOTH the tracker AND the game are alive. ----
# If the game dies (for whatever reason), break and clean up the camera ourselves.
while kill -0 "$child" 2>/dev/null && kill -0 "$WATCH_PARENT" 2>/dev/null; do
    # Backup signal: the game may have written a "game exit" flag (see HandTrackingClient.gd).
    if [ -f "$GAME_EXIT_FLAG" ] && [ -s "$GAME_EXIT_FLAG" ]; then
        break
    fi
    sleep 0.5
done

if ! kill -0 "$WATCH_PARENT" 2>/dev/null; then
    echo "[tracker] Parent process (game) ended. Closing tracker."
elif [ -f "$GAME_EXIT_FLAG" ] && [ -s "$GAME_EXIT_FLAG" ]; then
    echo "[tracker] Game-exit flag detected. Closing tracker."
fi
_cleanup
exit 0
