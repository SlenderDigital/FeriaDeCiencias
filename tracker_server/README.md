# tracker_server — MediaPipe hand tracker (UDP)

Servicio Python que captura la cámara, detecta los 21 landmarks de la mano
con MediaPipe + OpenCV y los envía por **UDP a `127.0.0.1:5005`**.

- Lo consume `scripts/HandTrackingClient.gd` (autoload de Godot), que expone
  `has_hand`, `get_palm_center()` y `get_hand_angle_deg()` para mover y rotar
  la nave. Puño cerrado = escudo.
- Sin datos del tracker, el juego cae automáticamente a teclado (flechas /
  WASD): siempre jugable, con mano o sin ella.
- El juego lo levanta solo al abrirse (`run_tracker.sh --detach`, sin
  duplicarlo si ya corre) y lo apaga al cerrarse.

## Instalación única

```bash
cd tracker_server && uv sync   # descarga mediapipe y opencv (Python ≥ 3.12, uv)
```

## Correr a mano

```bash
./run_tracker.sh            # primer plano (ventana de tracking visible)
./run_tracker.sh --detach   # segundo plano (como lo levanta el juego)
```

Requiere webcam (`/dev/video0`). Solo habla con esta máquina (`127.0.0.1`).
