@echo off
REM Abstract Pulse — MediaPipe hand tracker (Windows).
REM Levanta tracker_server con su .venv y lo cierra cuando muere el juego.
REM Uso: run_tracker.bat [GAMEPID]   (el juego pasa su PID; sin arg corre suelto)
setlocal EnableDelayedExpansion

REM --- Auto-minimizar la consola (un flash breve, queda en la barra) ---
if not defined APT_MIN (
  set APT_MIN=1
  start "" /MIN "%~f0" %*
  exit /b 0
)
title AbstractPulseTracker
set GAMEPID=%~1
REM --headless como %2: sin ventana OpenCV (el juego es fullscreen).
if "%~2"=="--headless" set TRACKER_HEADLESS=1
cd /d "%~dp0tracker_server"

REM --- Idempotencia: si ya hay un tracker vivo (heartbeat fresco), no duplicar ---
powershell -noprofile -command "if (Test-Path '.tracker.status') { if (((Get-Date).ToUniversalTime() - (Get-Item '.tracker.status').LastWriteTimeUtc).TotalSeconds -lt 5) { exit 0 } else { exit 1 } } else { exit 1 }" >nul 2>&1
if %errorlevel%==0 (
  echo [tracker] Already running (fresh heartbeat). Not starting another.
  exit /b 0
)

REM --- Deps instaladas? Si no, avisar una vez (el juego muestra el banner) ---
if not exist ".venv\Scripts\python.exe" (
  echo [tracker] ERROR: .venv missing. Run once: setup_tracker.bat
  echo error:noinst> ".tracker.status"
  pause
  exit /b 1
)

echo [tracker] MediaPipe hand tracker -^> UDP 127.0.0.1:5005
echo [tracker] Watching game PID %GAMEPID%. Close this window to stop tracking.
start "AbstractPulseTracker" /MIN .venv\Scripts\python.exe -m mediapipe_py.main

REM --- Watchdog: mientras el juego viva, quedarse. Sin PID = modo manual ---
if "%GAMEPID%"=="" (
  echo [tracker] No game PID: manual mode, close window to stop.
  pause >nul
  goto :cleanup
)
:watch
timeout /t 1 /nobreak >nul
tasklist /FI "PID eq %GAMEPID%" 2>nul | find "%GAMEPID%" >nul
if errorlevel 1 goto :gameover
if exist ".tracker.game_exit" goto :gameover
goto :watch

:gameover
echo [tracker] Game ended. Closing tracker.
taskkill /FI "WINDOWTITLE eq AbstractPulseTracker*" /IM python.exe >nul 2>&1
:cleanup
del .tracker.pid .tracker.status .tracker.game_exit 2>nul
exit /b 0
