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
# Usage:  ./run_tracker.sh   (from the repo root)
set -euo pipefail
cd "$(dirname "$0")/tracker_server"

if ! command -v uv >/dev/null 2>&1; then
    echo "[tracker] ERROR: 'uv' no está instalado." >&2
    echo "[tracker] Instalalo (Arch: pacman -S uv) y volvé a correr ./run_tracker.sh" >&2
    exit 1
fi

# Crea/sincroniza el .venv con mediapipe + opencv la primera vez (o tras un pull).
if [ ! -d ".venv" ]; then
    echo "[tracker] Creando .venv y descargando dependencias (mediapipe, opencv)..."
    uv sync
fi

echo "[tracker] Levantando MediaPipe hand tracker → UDP 127.0.0.1:5005 (cámara 0)."
echo "[tracker] Cerrá con la tecla 'q' o ESC en la ventana de tracking."
exec uv run mediapipe-py