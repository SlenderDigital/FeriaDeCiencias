@echo off
REM Abstract Pulse — instalacion unica del tracker en Windows.
REM Instala uv si falta (via winget) y sincroniza tracker_server/.venv.
setlocal
cd /d "%~dp0tracker_server"

where uv >nul 2>&1
if errorlevel 1 (
  echo [setup] uv no encontrado, instalando con winget...
  winget install --id=astral-sh.uv -e --accept-source-agreements --accept-package-agreements
  if errorlevel 1 (
    echo [setup] ERROR: instala uv a mano desde https://docs.astral.sh/uv/ y reintenta.
    pause
    exit /b 1
  )
  REM refrescar PATH de la sesion
  for /f "tokens=*" %%p in ('where uv') do set UVBIN=%%p
)

echo [setup] Sincronizando dependencias (MediaPipe + OpenCV, primera vez tarda)...
uv sync --python 3.12
if errorlevel 1 (
  echo [setup] ERROR en uv sync. Revisa tu conexion.
  pause
  exit /b 1
)
echo [setup] Listo: juga con AbstractPulse.exe (necesitas webcam).
pause
