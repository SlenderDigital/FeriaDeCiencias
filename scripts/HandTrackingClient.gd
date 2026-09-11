extends Node
## HandTrackingClient — escucha landmarks de MediaPipe por UDP (127.0.0.1:5005)
## y expone: has_hand, get_palm_center() (normalizado 0-1, X espejada) y
## get_hand_angle_deg().
##
## Al abrir el juego:
##  - Si el tracker (tracker_server/) no está corriendo y ya está instalado
##    (.venv existe), lo levanta solo (run_tracker.sh), sin reinstalar.
##  - Si no está instalado, avisa cómo hacerlo (instalación única, a mano).
##  - Si ya estaba corriendo, no duplica: solo se conecta.
## Muestra una barra de estado arriba para que sepas cuándo el control por mano
## está listo. Si el tracker no anda, queda el control por teclado.

signal hand_updated

const UDP_PORT := 5005
const LANDMARK_COUNT := 21
const NO_HAND_TIMEOUT := 0.5   # segundos sin datagrama -> se corta el tracking
const TRACKER_SCRIPT := "res://run_tracker.sh"
const TRACKER_DIR := "res://tracker_server/"

# --- Mapeo de coordenadas cámara -> viewport ---
# camera_aspect_ratio: aspect ratio de la cámara (ej. 4/3 = 1.333, 16/9 = 1.777)
# 0 = auto (usa 16/9 como fallback)
# mapping_mode: "stretch" | "fit" | "crop"
#   stretch = llena todo el viewport (distorsiona si aspect ratios difieren)
#   fit = mantiene aspect ratio cámara, puede haber barras negras
#   crop = llena viewport recortando cámara
@export var camera_aspect_ratio: float = 0.0
@export var mapping_mode: String = "fit"

var _udp := PacketPeerUDP.new()
var _points := PackedVector3Array()   # 21 landmarks normalizados (x,y,z)
var has_hand := false
var _last_packet_time := 0.0
var _got_datagram := false   # el tracker está mandando datos

# Estado del arranque: "spawned" | "running" | "failed" | "needs_install"
var _spawn_state := "spawned"
var _tracker_pid := 0          # PID del run_tracker.sh que lanzó el juego
var _tracker_started_here := false   # true si el juego lo levantó (y debe cerrarlo)

# --- UI de estado ---
var _panel: PanelContainer
var _lbl: Label
var _bar: ProgressBar
var _last_ui_update := 0.0
var _status_path := ""
var _cached_status := ""
var _last_status_read := 0.0

func _ready() -> void:
	var err := _udp.bind(UDP_PORT)
	if err != OK:
		push_warning("[HandTracking] No pudo bindear UDP %d: %s" % [UDP_PORT, err])
	else:
		_auto_start_tracker()
	_build_status_ui()
	_update_status_ui(true)

func _exit_tree() -> void:
	# Al cerrar el juego, escribir la bandera que le dice al tracker que
	# se cierre. El script (run_tracker.sh) tiene un WATCHDOG que monitorea
	# al padre del juego; si el juego muere (botón, Alt+F4, Win+W, crash) el
	# tracker se cierra solo. Este flag es respaldo por si el proceso bash se
	# muere antes de que el loop chequeé el PID (p.ej. a veces Win+W).
	if _status_path != "":
		var flag := ProjectSettings.globalize_path(TRACKER_DIR) + ".tracker.game_exit"
		var f := FileAccess.open(flag, FileAccess.WRITE)
		if f:
			f.store_string("1")
			f.close()
		print("[HandTracking] Bandera de salida escrita para el tracker.")

func _auto_start_tracker() -> void:
	_status_path = ProjectSettings.globalize_path(TRACKER_DIR) + ".tracker.status"
	var script_path := ProjectSettings.globalize_path(TRACKER_SCRIPT)

	# 1) Si ya había un tracker (instancia anterior / manual), no duplicar.
	if _lock_live():
		_spawn_state = "running"
		_tracker_started_here = false
		print("[HandTracking] Tracker ya corriendo. Solo me conecto por UDP ", UDP_PORT, ".")
		return

	# 2) Si no está instalado el .venv, no instalamos desde el juego: instalación única.
	if not FileAccess.file_exists(ProjectSettings.globalize_path(TRACKER_DIR) + ".venv/bin/python"):
		_spawn_state = "needs_install"
		_tracker_started_here = false
		print("[HandTracking] Tracker no instalado. Corré una vez: ./run_tracker.sh")
		return

	# 3) Levantar el tracker como HIJO de este juego (se cierra solo al salir).
	var pid := OS.create_process(script_path, [])
	if pid > 0:
		_spawn_state = "spawned"
		_tracker_pid = pid
		_tracker_started_here = true
		print("[HandTracking] Tracker lanzado (PID=%d). Esperando landmarks por UDP %d." % [pid, UDP_PORT])
	else:
		_spawn_state = "failed"
		_tracker_started_here = false
		push_warning("[HandTracking] No se pudo lanzar el tracker (código=%d). Teclado." % pid)

func _lock_pid() -> int:
	# Lee tracker_server/.tracker.pid y devuelve el PID del tracker (0 si no hay).
	var lock := ProjectSettings.globalize_path(TRACKER_DIR) + ".tracker.pid"
	if not FileAccess.file_exists(lock):
		return 0
	var f := FileAccess.open(lock, FileAccess.READ)
	if not f:
		return 0
	var pid_str := f.get_as_text().strip_edges()
	f.close()
	if pid_str.is_empty() or not pid_str.is_valid_int():
		return 0
	return int(pid_str)

func _lock_live() -> bool:
	# ¿Hay un proceso tracker vivo (el del lock)? kill -0 no mata, solo chequea.
	var p := _lock_pid()
	return p > 0 and OS.execute("kill", ["-0", str(p)]) == 0

func _process(_delta: float) -> void:
	# Timeout: si no llega datagrama, caer a teclado.
	if has_hand and Time.get_ticks_msec() / 1000.0 - _last_packet_time > NO_HAND_TIMEOUT:
		has_hand = false
	while _udp.get_available_packet_count() > 0:
		_parse(_udp.get_packet())
	_update_status_ui()

func _parse(data: PackedByteArray) -> void:
	if data.size() < 4:
		return
	_got_datagram = true   # llegó algo del tracker -> está arriba
	var count: int = data.decode_s32(0)   # little-endian (struct.pack "<i...f")
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
	if Vector2(dx, dy).length() < 0.006:   # umbral normalizado (equiv. len>8px en 1280)
		return 9999.0   # valor invalido -> no aplicar
	return rad_to_deg(atan2(dy, dx))

# ---------------------------------------------------------------- UI de estado

func _build_status_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HandStatusLayer"
	layer.layer = 100
	add_child(layer)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.06, 0.85)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(0, 0.88, 1, 0.5)
	_panel.add_theme_stylebox_override("panel", sb)

	# Anclado arriba-centro.
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -215
	_panel.offset_right = 215
	_panel.offset_top = 18
	_panel.offset_bottom = 92

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	_panel.add_child(vb)

	_lbl = Label.new()
	_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl.add_theme_font_size_override("font_size", 15)
	_lbl.add_theme_color_override("font_color", Color(0, 0.9, 1, 1))
	vb.add_child(_lbl)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 6)
	vb.add_child(_bar)

	layer.add_child(_panel)
	_panel.visible = false

func _update_status_ui(_force := false) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not _panel:
		return
	if not _force and now - _last_ui_update < 0.12:
		return
	_last_ui_update = now

	# Ya estamos controlando con la mano -> ocultar la barra.
	if has_hand:
		_set_ui_visible(false)
		return

	# El tracker está mandando datos -> listo, solo falta la mano.
	if _got_datagram or _tracker_status() == "ready":
		_set_ui_visible(true)
		_set_bar_fill(Color(0.1, 1.0, 0.45, 1))
		_lbl.text = "Control por mano listo — mostrá la mano"
		_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.55, 1))
		_bar.value = 100.0
		return

	var st := _tracker_status()
	if _spawn_state == "needs_install":
		_set_ui_visible(true)
		_lbl.text = "Tracker no instalado — corré ./run_tracker.sh una vez"
		_lbl.add_theme_color_override("font_color", Color(1, 0.78, 0.25, 1))
		_set_bar_fill(Color(1, 0.6, 0.2, 1))
		_bar.value = 0.0
	elif _spawn_state == "failed" or st.begins_with("error"):
		_set_ui_visible(true)
		_lbl.text = "No se pudo iniciar el tracker — se usa el teclado"
		_lbl.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
		_set_bar_fill(Color(1, 0.3, 0.3, 1))
		_bar.value = 0.0
	else:
		# "spawned" / "running": arrancando (Primera vez mediapipe carga ~5-10s).
		_set_ui_visible(true)
		_lbl.text = "Iniciando control por mano…"
		_lbl.add_theme_color_override("font_color", Color(0, 0.9, 1, 1))
		_set_bar_fill(Color(0, 0.9, 1, 1))
		_bar.value = fmod(now * 38.0, 100.0)

func _tracker_status() -> String:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_status_read < 0.3:
		return _cached_status
	_last_status_read = now
	_cached_status = ""
	if FileAccess.file_exists(_status_path):
		var f := FileAccess.open(_status_path, FileAccess.READ)
		if f:
			_cached_status = f.get_as_text().strip_edges()
			f.close()
	return _cached_status

func _set_bar_fill(c: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = c
	fill.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill)

func _set_ui_visible(v: bool) -> void:
	if _panel and _panel.visible != v:
		_panel.visible = v