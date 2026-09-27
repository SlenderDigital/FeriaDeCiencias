#!/usr/bin/env bash
# Arma los paquetes jugables: binario + tracker al lado (sin .venv).
# Uso: ./tools/package_builds.sh [linux|windows|all]
set -euo pipefail
cd "$(dirname "$0")/.."

WHAT="${1:-all}"
mkdir -p build-linux build-win

pkg_tracker() {  # $1 = destino
  local dest="$1"
  mkdir -p "$dest/tracker_server"
  cp -r tracker_server/src "$dest/tracker_server/"
  cp tracker_server/pyproject.toml tracker_server/uv.lock tracker_server/hand_landmarker.task tracker_server/README.md "$dest/tracker_server/"
  echo "[pkg] tracker_server -> $dest (sin .venv: se instala con uv sync)"
}

if [ "$WHAT" = "linux" ] || [ "$WHAT" = "all" ]; then
  godot --headless --export-release "Linux/X11"
  chmod +x build-linux/game
  cp run_tracker.sh install_tracker.sh build-linux/
  chmod +x build-linux/run_tracker.sh build-linux/install_tracker.sh
  pkg_tracker build-linux
  cat > build-linux/LEEME.txt <<'EOF'
ABSTRACT PULSE — Feria de Ciencias
==================================
Doble clic en ./game (pantalla completa; SALIR cierra).
La PRIMERA vez el juego instala solo el control por mano (necesita
internet una vez, descarga ~900MB, varios minutos; después nunca más).
   - Sin cámara/webcam: flechas o WASD, ESPACIO = escudo.
   - Con mano: mostrá la palma (mueve), puño = escudo.
El juego levanta solo el tracker; al salir libera la cámara.
EOF
  echo "[pkg] build-linux OK: $(du -sh build-linux | cut -f1)"
fi

if [ "$WHAT" = "windows" ] || [ "$WHAT" = "all" ]; then
  godot --headless --export-release "Windows Desktop"
  cp run_tracker.bat setup_tracker.bat install_tracker.bat build-win/
  pkg_tracker build-win
  cat > build-win/LEEME.txt <<'EOF'
ABSTRACT PULSE — Feria de Ciencias
==================================
Doble clic en AbstractPulse.exe (pantalla completa; SALIR cierra).
La PRIMERA vez el juego instala solo el control por mano (necesita
internet una vez, descarga ~900MB, varios minutos; después nunca más).
   - Sin camara: flechas o WASD, ESPACIO = escudo.
   - Con mano: mostra la palma (mueve), puno = escudo.
El juego levanta solo el tracker; al salir libera la camara.
EOF
  echo "[pkg] build-win OK"
fi
