#!/usr/bin/env bash
# Abstract Pulse — instalador automático del tracker (primera vez).
# Lo lanza el juego cuando no existe tracker_server/.venv. Escribe su
# progreso en tracker_server/.tracker.install: "run" | "done" | "error:<msg>".
# Log completo en tracker_server/.tracker_install.log. Idempotente y silencioso
# si ya está instalado. Nunca toca la cámara ni la red salvo para instalar.
set -uo pipefail

# lock de instancia (no duplicar): si otro instalador corre, salir.
HERE="$(cd "$(dirname "$0")" && pwd)"
TS="$HERE/tracker_server"
FLAG="$TS/.tracker.install"
LOG="$TS/.tracker_install.log"

if [ -x "$TS/.venv/bin/python" ]; then
  echo "done" > "$FLAG"
  exit 0
fi
if [ -f "$FLAG" ] && [ "$(cat "$FLAG" 2>/dev/null)" = "run" ]; then
  # ¿sigue vivo el otro instalador? (marca con su PID)
  OTHER="$(cat "$TS/.tracker.install.pid" 2>/dev/null || echo 0)"
  if [ "$OTHER" != "0" ] && kill -0 "$OTHER" 2>/dev/null; then
    exit 0
  fi
fi
echo $$ > "$TS/.tracker.install.pid"
echo "run" > "$FLAG"
{
  echo "[install] $(date -u +%FT%TZ) starting"

  # 1) uv disponible? Si no, instalarlo a nivel usuario (sin sudo).
  if ! command -v uv >/dev/null 2>&1; then
    echo "[install] uv no encontrado, instalando..."
    if ! curl -LsSf --max-time 60 https://astral.sh/uv/install.sh | sh >>"$LOG" 2>&1; then
      echo "error:uv-install" > "$FLAG"
      echo "[install] ERROR instalando uv" | tee -a "$LOG"
      exit 1
    fi
    export PATH="$HOME/.local/bin:$PATH"
  fi
  if ! command -v uv >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/uv" ]; then
    echo "error:uv-missing" > "$FLAG"
    exit 1
  fi
  export PATH="$HOME/.local/bin:$PATH"

  # 2) Python + deps del tracker (primera vez descarga ~900MB, varios minutos).
  # --python 3.12: mediapipe 0.10.21 solo tiene wheels cp312 (uv solo
  # descargaría 3.14 y fallaría). uv baja el 3.12 standalone si falta.
  echo "[install] uv sync (puede tardar varios minutos la primera vez)..."
  if ! (cd "$TS" && uv sync --python 3.12 >>"$LOG" 2>&1); then
    echo "error:sync" > "$FLAG"
    echo "[install] ERROR en uv sync (¿sin internet?). Ver $LOG"
    exit 1
  fi

  if [ -x "$TS/.venv/bin/python" ]; then
    echo "done" > "$FLAG"
    echo "[install] OK"
  else
    echo "error:no-venv" > "$FLAG"
    echo "[install] ERROR: sync terminó sin .venv"
    exit 1
  fi
} >>"$LOG" 2>&1
