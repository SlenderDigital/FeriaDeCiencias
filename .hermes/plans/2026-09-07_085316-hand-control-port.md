# Port de Control por Mano (C++ → Godot) — Abstract Pulse

> **Para Hermes:** implementar tarea por tarea con el skill `subagent-driven-development`, con revisión en dos etapas (cumplimiento de spec + calidad de código) después de cada tarea.

**Goal:** Portar el control por mano del repo C++ `hand_tracking_space_game` al juego Godot **Abstract Pulse** para jugarlo moviendo y rotando la nave con la mano.

**Architecture:** El control por mano ya está resuelto en Python (MediaPipe), y el repo C++ **solo recibe datos por UDP y los mapea a movimiento/rotación**. Nosotros portamos la parte de recepción/mapeo a GDScript, reutilizando el `tracker_server/` Python sin cambios. Se agrega un autoload `HandTrackingClient` que escucha UDP en `127.0.0.1:5005`, decodifica los 21 landmarks y expone palma (posición) y ángulo pulgar→índice (rotación). `Gameplay.gd` pasa a usar esos datos; si no hay mano, cae al control por flechas actual.

**Tech Stack:** Godot 4.7 · GDScript (`PacketPeerUDP`) · Python 3.12+ · uv · MediaPipe (`mp.solutions.hands`) · OpenCV.

---

## Contexto y contrato (portado de `hand_tracking_space_game`)

**Protocolo UDP** (emitido por `tracker_server/src/mediapipe_py/main.py`):
- Destino `127.0.0.1:5005`, datagrama **little-endian**.
- Primer valor `int32` = cantidad de landmarks (normalmente **21**).
- Luego `count × (float32 x, y, z)`, coordenadas **normalizadas 0–1**.
- Si no se detecta mano: datagrama de solo `int32 = 0`.

**Índices de landmarks** (estándar MediaPipe):
- `WRIST=0`, `THUMB_CMC=1`, `INDEX_MCP=5`, `INDEX_TIP=8`, `MIDDLE_MCP=9`, `PINKY_MCP=17`.

**Mapeo de control** (portado de `Player.cpp`):
- **Posición**: centro de palma = promedio de `(WRIST, INDEX_MCP, MIDDLE_MCP, PINKY_MCP)`. → `target = ((1 - palm.x) * viewport_w, palm.y * viewport_h)`. (X reflejada, Y ya es top-down como Godot.)
- **Suavizado de posición**: exponencial `alpha = 1 - exp(-25*dt)`, `pos += (target - pos) * alpha`.
- **Rotación**: ángulo del segmento `THUMB_CMC → INDEX_TIP` (ambas X reflejadas). Umbral de longitud mínima antes de aplicar. Suavizado exponencial `alpha = 1 - exp(-22*dt)` por el arco más corto.
- **Fallback teclado** cuando no hay mano (mover + rotar con Q/E en el original).

**Pantalla del juego:** viewport 1280×720 (`project.godot`). Límites actuales de la nave: `x ∈ [50,1230]`, `y ∈ [80,670]`.

---

## Tareas

### Task 1: Copiar `tracker_server/` al repo Godot

**Objective:** Dejar el proyecto de juego autocontenido con el detector de mano Python adentro.

**Files:**
- Create: `tracker_server/pyproject.toml`, `.python-version`, `uv.lock`
- Create: `tracker_server/src/mediapipe_py/__init__.py`, `landmarker.py`, `main.py`
- Create: `tracker_server/hand_landmarker.task` (si existe/hay que conservarlo)

**Step 1:** Copiar recursivo desde el repo C++:

```bash
cd /home/slender/Projects/FeriaDeCiencias
cp -r /home/slender/Projects/hand_tracking_space_game/tracker_server/. tracker_server/
```

**Step 2 (verificación):** Confirmar que el copiado preservó la carpeta y los archivos clave:

```bash
ls tracker_server/src/mediapipe_py/ && cat tracker_server/pyproject.toml | head -5
```

**Step 3:** Commit:

```bash
git add tracker_server/
git commit -m "feat(hand): copy python mediapipe tracker server into project"
```

---

### Task 2: Crear y verificar el venv del tracker

**Objective:** El servidor Python instala sus dependencias y corre localmente (PEP 668 → usar `uv`).

**Files:**
- Create: `run_tracker.sh` (raíz del repo Godot)
- None modificado en el código del tracker.

**Step 1:** Escribir `run_tracker.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/tracker_server"
if [ ! -d .venv ]; then uv venv --python 3.12 --seed; fi
uv pip install --python .venv/bin/python -e "."
PYTHON=./.venv/bin/python
echo "[tracker] Arrancando MediaPipe + envio UDP 127.0.0.1:5005 (q/ESC para salir)"
exec "$PYTHON" -m mediapipe_py.main
```

(Alternativa sin script: `cd tracker_server && uv sync && uv run python -m mediapipe_py.main`.)

**Step 2:** Marcar ejecutable e instalar deps (verificación de que resuelve):

```bash
chmod +x run_tracker.sh
cd tracker_server && uv sync --frozen 2>&1 | tail -15
```

Esperado: sincronización exitosa de `mediapipe<=0.10.21` (y opencv). Si falla por red/modelo, dilo y probá `uv sync` sin `--frozen`.

**Step 3 (verificación de que el detector cargó el modelo):** correr el tracker en segundo plano:

```bash
cd /home/slender/Projects/FeriaDeCiencias && ./run_tracker.sh
```

Esperado: ventana `Landmark Tracking` abierta con la cámara. Dejar corriendo para la verificación final.

**Step 4:** Commit:

```bash
git add run_tracker.sh
git commit -m "chore(hand): add run_tracker.sh launcher (uv venv + mediapipe)"
```

> Nota: no committear `.venv/` (agregar a `.gitignore` si falta).

---

### Task 3: Crear el autoload `HandTrackingClient.gd` (receptor UDP + decoder)

**Objective:** GDScript que escucha UDP 5005, decodifica el datagrama y expone palma y ángulo de rotación.

**Files:**
- Create: `scripts/HandTrackingClient.gd` (+ `.uid` generado por el editor)
- Modify: `project.godot` (registrar autoload)

**Step 1:** Escribir `scripts/HandTrackingClient.gd`:

```gdscript
extends Node
## HandTrackingClient — escucha landmarks de MediaPipe por UDP (127.0.0.1:5005)
## y expone: has_hand, get_palm_center() (normalizado 0-1, X espejada) y
## get_hand_angle_deg(). Puertos directo de Player.cpp del repo C++.

signal hand_updated

const UDP_PORT := 5005
const LANDMARK_COUNT := 21
const NO_HAND_TIMEOUT := 0.5   # segundos sin datagrama -> se corta el tracking

var _udp := PacketPeerUDP.new()
var _points := PackedVector3Array()   # 21 landmarks normalizados (x,y,z)
var has_hand := false
var _last_packet_time := 0.0

func _ready() -> void:
	var err := _udp.bind(UDP_PORT)
	if err != OK:
		push_warning("[HandTracking] No pudo bindear UDP %d: %s" % [UDP_PORT, err])

func _process(_delta: float) -> void:
	# Timeout: si no llega datagrama, caer a teclado.
	if has_hand and Time.get_ticks_msec() / 1000.0 - _last_packet_time > NO_HAND_TIMEOUT:
		has_hand = false
	while _udp.get_available_packet_count() > 0:
		_parse(_udp.get_packet())

func _parse(data: PackedByteArray) -> void:
	if data.size() < 4:
		return
	var count: int = data.decode_s32(0, false)   # little-endian
	_points = PackedVector3Array()
	if count == LANDMARK_COUNT and data.size() >= 4 + count * 12:
		for i in count:
			var o := 4 + i * 12
			_points.push_back(Vector3(
				data.decode_float(o),
				data.decode_float(o + 4),
				data.decode_float(o + 8)
			))
		has_hand = true
		_last_packet_time = Time.get_ticks_msec() / 1000.0
		hand_updated.emit()
	else:
		has_hand = false   # datagrama con count != 21 o sin mano

func get_landmark(idx: int) -> Vector3:
	return _points[idx] if idx >= 0 and idx < _points.size() else Vector3.ZERO

func get_palm_center() -> Vector2:
	# promedio de WRIST(0), INDEX_MCP(5), MIDDLE_MCP(9), PINKY_MCP(17) — X espejada
	var w := get_landmark(0)
	var im := get_landmark(5)
	var mm := get_landmark(9)
	var pm := get_landmark(17)
	var px: float = (w.x + im.x + mm.x + pm.x) * 0.25
	var py: float = (w.y + im.y + mm.y + pm.y) * 0.25
	return Vector2(1.0 - px, py)

func get_hand_angle_deg() -> float:
	# rotacion por segmento THUMB_CMC(1) -> INDEX_TIP(8), ambas X espejadas
	var thumb := get_landmark(1)
	var tip := get_landmark(8)
	var dx := (1.0 - tip.x) - (1.0 - thumb.x)
	var dy := tip.y - thumb.y
	if Vector2(dx, dy).length() < 0.006:   # umbral normalizado (equivalente a len>8px)
		return 9999.0   # valor invalido -> no aplicar
	return rad_to_deg(atan2(dy, dx))
```

**Step 2:** Registrar autoload en `project.godot` (sección `[autoload]`, al final):

```ini
HandTrackingClient="*res://scripts/HandTrackingClient.gd"
```

**Step 3 (test del decoder):** Abrir el proyecto en Godot, correr con el tracker activo (Task 2) y confirmar el print en la consola de Godot (agregar temporalmente en `_process` un `print(has_hand, get_palm_center())` si hace falta). Esperado: `has_hand=true` y palma variando al mover la mano frente a la cámara.

**Step 4:** Commit:

```bash
git add scripts/HandTrackingClient.gd project.godot
git commit -m "feat(hand): HandTrackingClient autoload (UDP 5005 + decoder)"
```

---

### Task 4: Integrar control por mano en `Gameplay.gd` (posición)

**Objective:** La nave sigue la palma de la mano como posición absoluta (suavizada), con fallback a flechas cuando no hay mano.

**Files:**
- Modify: `scripts/Gameplay.gd` (`_update_player_movement`)

**Step 1:** Reemplazar `_update_player_movement` por esta versión (mantiene el bloque de teclado como fallback):

```gdscript
func _update_player_movement(delta: float) -> void:
	if HandTrackingClient and HandTrackingClient.has_hand:
		# Con mano: posicion absoluta de la palma (port de Player.cpp)
		var target: Vector2 = HandTrackingClient.get_palm_center() * Vector2(1280, 720)
		var alpha: float = 1.0 - exp(-25.0 * delta)
		player_pos = player_pos.lerp(target, alpha)
		# rotacion por segmento pulgar->indice
		var ang := HandTrackingClient.get_hand_angle_deg()
		if ang < 9990.0:
			_smooth_rotation_toward(ang, delta)
		player_pos.x = clamp(player_pos.x, 50, 1230)
		player_pos.y = clamp(player_pos.y, 80, 670)
		return

	# Fallback: flechas / WASD (movimiento por velocidad, igual que hoy)
	var move_dir: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		move_dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		move_dir.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		move_dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		move_dir.y += 1.0

	if move_dir != Vector2.ZERO:
		player_pos += move_dir.normalized() * player_speed * delta

	player_pos.x = clamp(player_pos.x, 50, 1230)
	player_pos.y = clamp(player_pos.y, 80, 670)
```

**Step 2:** Declarar estado de rotación y el suavizador. Agregar al tope (junto a `var player_pos`):

```gdscript
var ship_rotation: float = 0.0    # grados, 0 = apuntando a +X (derecha)

func _smooth_rotation_toward(target_deg: float, delta: float) -> void:
	var diff := wrapf(target_deg - ship_rotation, -180.0, 180.0)
	var alpha: float = 1.0 - exp(-22.0 * delta)
	ship_rotation += diff * alpha
```

**Step 3:** Reemplazar el bloque de dibujo de la nave en `_draw()` para que rote con `ship_rotation`:

```gdscript
	# Draw player ship (neon, con rotacion por mano; 0deg = derecha)
	var ship_col: Color = track_data.get("color", Color(0, 0.94, 1, 1))
	var rad: float = deg_to_rad(ship_rotation)
	var fwd := Vector2.from_angle(rad)          # linea de proa
	var perp := Vector2(-fwd.y, fwd.x)          # perpendicular
	var nose: Vector2 = player_pos + fwd * 20.0
	var p2: Vector2 = player_pos + (-fwd * 9.0 + perp * 15.0)
	var p3: Vector2 = player_pos + (-fwd * 9.0 - perp * 15.0)
	draw_polyline(PackedVector2Array([nose, p2, p3, nose]), ship_col, 3.5)
	draw_line(player_pos, player_pos + fwd * 24.0, Color(1, 1, 1, 0.25), 1.5)
	draw_circle(player_pos, 4.0, Color.WHITE)
```

**Step 4 (verificación):** Correr el juego con el tracker activo: la nave debe **seguir la palma** (movimiento suavizado) y **rotar** al inclinar pulgar↔índice. Sin mano, debe seguir respondiendo a las flechas.

**Step 5:** Commit:

```bash
git add scripts/Gameplay.gd
git commit -m "feat(hand): drive player pos/rotation from hand landmarks, keyboard fallback"
```

---

## Verificación end-to-end

1. `./run_tracker.sh` deja el tracker emitiendo en `127.0.0.1:5005`.
2. Abrir `Abstract Pulse` en Godot 4.7 (F6 en `Gameplay.tscn`, o desde `MainMenu`).
3. Poner la mano frente a la cámara: la nave **se mueve** con la palma y **rota** con la línea pulgar→índice, de forma suave.
4. Ocultar la mano ~0.5s: cae a control por flechas; reaparece y vuelve el control por mano.
5. La colisión/recompensas no cambian (solo cambió el input de movimiento).

## Archivos que cambian

- Crear: `tracker_server/*` (copia), `run_tracker.sh`, `scripts/HandTrackingClient.gd`
- Modificar: `project.godot` (autoload), `scripts/Gameplay.gd` (movimiento + rotación + dibujo)
- `.gitignore`: agregar `tracker_server/.venv/` si falta.

## Riesgos, tradeoffs y preguntas abiertas

- **Dependencia Python**: `mediapipe<=0.10.21` y `uv` deben estar disponibles/probados (Task 2 lo valida). Si tu máquina ya tiene otro flujo, ajustar el venv.
- **Webcam única**: el tracker usa `cv2.VideoCapture(0)`; si hay cámara distinta, ajustar índice.
- **Solo una mano** (usa `multi_hand_landmarks[0]`), igual que el original.
- **Rotación en solitario**: el juego Godot original no rotaba la nave; el dibujo rotado es **nuevo** (fiel al C++). El offset (`0° = derecha`) evita depender de la proa vertical previa.
- `hand_landmarker.task` parece ser un artefacto sin uso en `main.py` (usa `mp.solutions.hands`, no la task API). Se copia por fidelidad pero no es necesario para correr.
- **Pregunta abierta**: ¿integrar el disparo (espacio/click) también a un gesto de la mano (p.ej. cerrar puño / juntar índices), o lo dejamos en teclado/click como está? Aportar esto pide definir un gesto; es iteración posterior recomendada.