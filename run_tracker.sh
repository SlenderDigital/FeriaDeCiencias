#!/usr/bin/env bash
# Abstract Pulse — MediaPipe hand tracker.
#
# Captures the webcam and streams the 21 hand landmarks over UDP to
# 127.0.0.1:5005.  The Godot game (HandTrackingClient autoload) listens on that
# socket and uses the landmarks to move and rotate the ship.
#
# The tracking logic lives entirely inside this repo under tracker_server/
# (a port of the original Player.cpp). No external C++ project is required.
#
# Normalmente lo levanta el propio juego al abrirse (HandTrackingClient.gd).
# También se puede correr a mano:  ./run_tracker.sh   (desde la raíz del repo)
set -euo pipefail
cd "$(dirname "$0")/tracker_server"

LOCK=".tracker.pid"

# Idempotente: si ya hay una instancia viva (la levantó el juego o corriste este
# script antes), no duplicar la cámara ni el proceso.
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
    echo "[tracker] Ya hay un tracker corriendo (PID $(cat "$LOCK")). No levanto otro."
    exit 0
fi

if ! command -v uv >/dev/null 2>&1; then
    echo "[tracker] ERROR: 'uv' no está instalado (Arch: sudo pacman -S uv)." >&2
    exit 1
fi

# Crea/sincroniza el .venv con mediapipe + opencv la primera vez (o tras un pull).
if [ ! -d ".venv" ]; then
    echo "[tracker] Creando .venv y descargando dependencias (mediapipe, opencv)..."
    uv sync
fi

echo $$ > "$LOCK"

child_pid=""
_cleanup() {
    rm -f "$LOCK"
    # Baja también al hijo (uv → python/mediapipe) para no dejar la cámara abierta.
    if [ -n "$child_pid" ]; then
        kill "$child_pid" 2>/dev/null || true
    fi
    exit 0
}
# Cuando el juego cierra (OS.kill → SIGTERM) o Ctrl-C, apaga todo y limpia el lock.
trap '_cleanup' INT TERM EXIT

echo "[tracker] MediaPipe hand tracker → UDP 127.0.0.1:5005 (cámara 0)."
echo "[tracker] Cerrar: 'q' o ESC en la ventana de tracking."
uv run mediapipe-py &
child_pid=$!
wait "$child_pid"