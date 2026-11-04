#!/usr/bin/env bash
# Builds offline-ready Linux (x86_64) and Windows (x86_64) release packages for
# Shapes & Beams, including the Godot 4.7 game binary + pre-bundled portable
# Python 3.12 + MediaPipe + OpenCV hand-tracking server.
#
# Usage:
#   ./scripts/build_release.sh [linux|windows|all]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TARGET="${1:-all}"
UV_PYTHON_DIR="${UV_PYTHON_INSTALL_DIR:-$HOME/.local/share/uv/python}"

echo "============================================================"
echo " Shapes & Beams — Offline Release Builder ($TARGET)"
echo "============================================================"

echo "[1/5] Running automated headless test suite..."
godot --headless --path juego -s res://tests/cli_test_runner.gd

echo "[2/5] Ensuring standalone Python 3.12 distributions (Linux & Windows)..."
uv python install cpython-3.12-linux-x86_64-gnu cpython-3.12-windows-x86_64-none

LINUX_PY_SRC="$(find "$UV_PYTHON_DIR" -maxdepth 1 -type d -name "cpython-3.12.*-linux-x86_64-gnu" | sort -V | tail -n 1)"
WIN_PY_SRC="$(find "$UV_PYTHON_DIR" -maxdepth 1 -type d -name "cpython-3.12.*-windows-x86_64-none" | sort -V | tail -n 1)"

if [[ -z "$LINUX_PY_SRC" || ! -d "$LINUX_PY_SRC" ]]; then
	echo "ERROR: Could not locate standalone Linux Python 3.12 in $UV_PYTHON_DIR" >&2
	exit 1
fi
if [[ -z "$WIN_PY_SRC" || ! -d "$WIN_PY_SRC" ]]; then
	echo "ERROR: Could not locate standalone Windows Python 3.12 in $UV_PYTHON_DIR" >&2
	exit 1
fi

REQ_FILE="$(mktemp)"
trap 'rm -f "$REQ_FILE"' EXIT
uv export --directory tracker_server --no-hashes --no-emit-project > "$REQ_FILE"

bundle_linux() {
	echo "------------------------------------------------------------"
	echo "[Linux] Exporting Godot 4.7 binary -> build-linux/..."
	rm -rf build-linux ShapesAndBeams-linux-x86_64.zip
	mkdir -p build-linux/tracker_server

	godot --headless --path juego --export-release "Linux"
	chmod +x build-linux/ShapesAndBeams.x86_64

	echo "[Linux] Copying tracker_server source & portable Python 3.12..."
	cp -a tracker_server/src tracker_server/pyproject.toml tracker_server/uv.lock tracker_server/README.md build-linux/tracker_server/
	mkdir -p build-linux/tracker_server/python
	cp -a "$LINUX_PY_SRC/bin" "$LINUX_PY_SRC/lib" build-linux/tracker_server/python/

	# Strip unneeded development/test/static files from portable Python
	rm -rf \
		build-linux/tracker_server/python/lib/pkgconfig \
		build-linux/tracker_server/python/lib/python3.12/test \
		build-linux/tracker_server/python/lib/python3.12/idlelib \
		build-linux/tracker_server/python/lib/python3.12/tkinter \
		build-linux/tracker_server/python/lib/python3.12/turtledemo \
		build-linux/tracker_server/python/lib/python3.12/config-* \
		build-linux/tracker_server/python/lib/tcl* \
		build-linux/tracker_server/python/lib/tk* \
		build-linux/tracker_server/python/lib/itcl* \
		build-linux/tracker_server/python/lib/thread* \
		build-linux/tracker_server/python/lib/libtcl*
	find build-linux/tracker_server/python -name "*.a" -delete

	local site_pkgs="build-linux/tracker_server/python/lib/python3.12/site-packages"
	echo "[Linux] Installing locked MediaPipe + OpenCV wheels into $site_pkgs..."
	uv pip install \
		--target "$site_pkgs" \
		--python-version 3.12 \
		--python-platform x86_64-unknown-linux-gnu \
		--quiet \
		-r "$REQ_FILE"

	cp -a tracker_server/src/mediapipe_py "$site_pkgs/"
	find build-linux/tracker_server -type d -name "__pycache__" -exec rm -rf {} +

	cat > build-linux/run_game.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
exec "./ShapesAndBeams.x86_64" "$@"
EOF
	chmod +x build-linux/run_game.sh

	cat > build-linux/LEEME.txt <<'EOF'
SHAPES & BEAMS — Feria de Ciencias (ETEC Mendoza)
=================================================

Ejecutar el juego:
  ./ShapesAndBeams.x86_64   (o ./run_game.sh)

Control híbrido (Mano / Teclado / Mouse):
- El juego incluye Python 3.12 + MediaPipe + OpenCV preinstalados en
  tracker_server/python/ (no requiere internet ni instalar nada).
- Al abrir el juego, el servicio de cámara arranca automáticamente en
  segundo plano (con barra de progreso en el menú principal) y se cierra
  solo al salir del juego.
- Con cámara: mové la palma abierta para desplazarte y cerrá el puño para
  mantener el escudo activo.
- Sin cámara: jugá con WASD / Flechas / Mouse y Espacio / Clic para escudo.
EOF

	echo "[Linux] Running isolated smoke test on bundled Python + MediaPipe + OpenCV..."
	env -i PATH="/usr/bin:/bin" HOME="$HOME" \
		build-linux/tracker_server/python/bin/python3 -c \
		"import cv2, mediapipe, mediapipe_py.main, mediapipe_py.landmarker; lm = mediapipe_py.landmarker.Landmarker(); lm.init(); lm.shutdown(); print('[Linux Smoke Test] MediaPipe Hands + OpenCV + mediapipe_py initialized OK!')"

	echo "[Linux] Creating ShapesAndBeams-linux-x86_64.zip..."
	zip -q -r -y ShapesAndBeams-linux-x86_64.zip build-linux
	echo "[Linux] Done! Folder: $(du -sh build-linux | cut -f1) | Zip: $(du -sh ShapesAndBeams-linux-x86_64.zip | cut -f1)"
}

bundle_windows() {
	echo "------------------------------------------------------------"
	echo "[Windows] Exporting Godot 4.7 binary -> build-win/..."
	rm -rf build-win ShapesAndBeams-windows-x86_64.zip
	mkdir -p build-win/tracker_server

	godot --headless --path juego --export-release "Windows Desktop"

	echo "[Windows] Copying tracker_server source & portable Windows Python 3.12..."
	cp -a tracker_server/src tracker_server/pyproject.toml tracker_server/uv.lock tracker_server/README.md build-win/tracker_server/
	mkdir -p build-win/tracker_server/python
	cp -a \
		"$WIN_PY_SRC/DLLs" \
		"$WIN_PY_SRC/Lib" \
		"$WIN_PY_SRC/python.exe" \
		"$WIN_PY_SRC/pythonw.exe" \
		"$WIN_PY_SRC/python3.dll" \
		"$WIN_PY_SRC/python312.dll" \
		"$WIN_PY_SRC/vcruntime140.dll" \
		"$WIN_PY_SRC/vcruntime140_1.dll" \
		"$WIN_PY_SRC/LICENSE.txt" \
		build-win/tracker_server/python/

	# Remove any host symlinks or unneeded stdlib test/gui modules
	find build-win/tracker_server/python -type l -delete
	rm -rf \
		build-win/tracker_server/python/Lib/test \
		build-win/tracker_server/python/Lib/idlelib \
		build-win/tracker_server/python/Lib/tkinter \
		build-win/tracker_server/python/Lib/turtledemo \
		build-win/tracker_server/python/Lib/ensurepip

	local site_pkgs="build-win/tracker_server/python/Lib/site-packages"
	mkdir -p "$site_pkgs"
	echo "[Windows] Installing locked win_amd64 MediaPipe + OpenCV wheels into $site_pkgs..."
	uv pip install \
		--target "$site_pkgs" \
		--python-version 3.12 \
		--python-platform x86_64-pc-windows-msvc \
		--quiet \
		-r "$REQ_FILE"

	cp -a tracker_server/src/mediapipe_py "$site_pkgs/"
	find build-win/tracker_server -type d -name "__pycache__" -exec rm -rf {} +

	cat > build-win/LEEME.txt <<'EOF'
SHAPES & BEAMS — Feria de Ciencias (ETEC Mendoza)
=================================================

Ejecutar el juego:
  Doble clic en ShapesAndBeams.exe

Control hibrido (Mano / Teclado / Mouse):
- El juego ya incluye Python 3.12 + MediaPipe + OpenCV preinstalados en
  tracker_server\python\ (no requiere internet ni instalar nada).
- Al abrir ShapesAndBeams.exe, el servicio de camara arranca solo en
  segundo plano (con barra de progreso en el menu principal) y libera la
  camara automaticamente al cerrar el juego.
- Con camara: move la palma abierta para desplazarte y cerra el puno para
  mantener el escudo activo.
- Sin camara: juga con WASD / Flechas / Mouse y Espacio / Clic para escudo.
EOF

	echo "[Windows] Verifying bundled Windows binaries and native extensions (.pyd)..."
	test -f build-win/ShapesAndBeams.exe
	test -f build-win/ShapesAndBeams.pck
	test -f build-win/tracker_server/python/pythonw.exe
	test -f build-win/tracker_server/python/python312.dll
	test -f "$site_pkgs/mediapipe/python/_framework_bindings.cp312-win_amd64.pyd"
	test -f "$site_pkgs/cv2/cv2.pyd"
	test -f "$site_pkgs/mediapipe_py/main.py"
	echo "[Windows Verification] pythonw.exe, _framework_bindings.cp312-win_amd64.pyd, cv2.pyd, and mediapipe_py verified OK!"

	echo "[Windows] Creating ShapesAndBeams-windows-x86_64.zip..."
	zip -q -r ShapesAndBeams-windows-x86_64.zip build-win
	echo "[Windows] Done! Folder: $(du -sh build-win | cut -f1) | Zip: $(du -sh ShapesAndBeams-windows-x86_64.zip | cut -f1)"
}

case "$TARGET" in
	linux)
		bundle_linux
		;;
	windows|win)
		bundle_windows
		;;
	all)
		bundle_linux
		bundle_windows
		;;
	*)
		echo "Usage: $0 [linux|windows|all]" >&2
		exit 1
		;;
esac

echo "============================================================"
echo " ALL REQUESTED BUILDS COMPLETED SUCCESSFULLY!"
echo "============================================================"
