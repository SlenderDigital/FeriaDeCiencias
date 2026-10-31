# tracker_server — MediaPipe Hand Tracker (UDP)

Servicio Python que captura video desde la webcam con **OpenCV**, detecta los **21 landmarks 3D** de la mano mediante **MediaPipe Hands** y los transmite en tiempo real por **UDP a `127.0.0.1:5005`**.

## Integración con el juego (`juego/`)

- El autoload `juego/scripts/hand_tracking_client.gd` (`HandTrackingClient`) inicia automáticamente este servidor en segundo plano (`--headless`) al abrir el juego y cierra el subproceso al salir.
- **Protocolo binario UDP (`127.0.0.1:5005`, little-endian)**:
  - Con mano detectada (`256 bytes`, formato `<i63f`): entero `21` seguido de 21 ternas `(x, y, z)` de floats normalizados.
  - Sin mano en cámara (`4 bytes`, formato `<i`): entero `0`.
- **Heartbeat (`.tracker.status`)**: `main.py` escribe `"ready"` cada 2 segundos cuando la cámara está activa (o `"error:camera"` si no se pudo abrir la webcam). El HUD del juego refleja el estado en vivo (`HAND: TRACKING`, `HAND: NO HAND` o `HAND: OFFLINE`).
- **Controles derivados en el juego**:
  - **Posición**: centro de la palma espejado horizontalmente (`1.0 - x`, promedio de los landmarks `#0, #5, #9, #13, #17`).
  - **Escudo**: puño cerrado (cuando al menos 3 de los 4 dedos `#8, #12, #16, #20` están flexionados hacia la palma/muñeca).

## Instalación única

Requiere **Python 3.12** y **[uv](https://docs.astral.sh/uv/)**:

```bash
cd tracker_server
uv sync
```

## Ejecución manual (debug con ventana OpenCV)

Si querés probar la cámara y ver los landmarks dibujados en pantalla fuera del juego:

```bash
cd tracker_server
uv run mediapipe-py
```

Para correrlo sin ventana (igual que lo lanza el juego):

```bash
cd tracker_server
uv run mediapipe-py --headless
```

## Variables de entorno opcionales

| Variable | Valor por defecto | Descripción |
| :--- | :--- | :--- |
| `TRACKER_CAM_INDEX` | `0` | Índice de la cámara (`/dev/video0` en Linux) |
| `TRACKER_CAM_WIDTH` | `1280` | Ancho de captura solicitado |
| `TRACKER_CAM_HEIGHT` | `720` | Alto de captura solicitado |
| `TRACKER_CAM_FPS` | `30` | Cuadros por segundo solicitados |
| `TRACKER_HEADLESS` | `0` | `1` para desactivar la ventana de debug OpenCV |
