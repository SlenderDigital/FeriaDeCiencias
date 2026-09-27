@echo off
REM Abstract Pulse — instalador automatico del tracker (primera vez, no interactivo).
REM Lo lanza el juego cuando no existe tracker_server\.venv. Progreso en
REM tracker_server\.tracker.install: "run" | "done" | "error:<msg>".
REM Log en tracker_server\.tracker_install.log.
setlocal
cd /d "%~dp0tracker_server"
set FLAG=.tracker.install
set LOG=.tracker_install.log

if exist ".venv\Scripts\python.exe" (
  echo done> "%FLAG%"
  exit /b 0
)
echo run> "%FLAG%"
echo [%date% %time%] starting>> "%LOG%"

where uv >nul 2>&1
if errorlevel 1 (
  echo [install] instalando uv con winget...>> "%LOG%"
  winget install --id=astral-sh.uv -e --accept-source-agreements --accept-package-agreements >> "%LOG%" 2>&1
  if errorlevel 1 (
    echo error:uv-install> "%FLAG%"
    exit /b 1
  )
  for /f "tokens=*" %%p in ('where uv 2^>nul') do set "PATH=%%~dpp;%PATH%"
)
where uv >nul 2>&1
if errorlevel 1 (
  echo error:uv-missing> "%FLAG%"
  exit /b 1
)

echo [install] uv sync (la primera vez tarda varios minutos)...>> "%LOG%"
REM --python 3.12: mediapipe solo tiene wheels cp312.
call uv sync --python 3.12 >> "%LOG%" 2>&1
if errorlevel 1 (
  echo error:sync> "%FLAG%"
  exit /b 1
)
if not exist ".venv\Scripts\python.exe" (
  echo error:no-venv> "%FLAG%"
  exit /b 1
)
REM Smoke test: el sync puede "pasar" dejando un entorno que no importa
REM (pasó en Linux con Python 3.14). Sin esto el juego quedaba "cargando"
REM para siempre; con esto falla ya con error:broken-env.
".venv\Scripts\python.exe" -c "import mediapipe, cv2" >> "%LOG%" 2>&1
if errorlevel 1 (
  echo error:broken-env> "%FLAG%"
  exit /b 1
)
echo done> "%FLAG%"
exit /b 0
