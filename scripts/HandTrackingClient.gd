extends Node
## HandTrackingClient — escucha landmarks de MediaPipe por UDP (127.0.0.1:5005)
## y expone: has_hand, get_palm_center() (normalizado 0-1, X espejada) y
## get_hand_angle_deg(). El emisor es tracker_server/ (dentro de este repo).
##
## Al abrir el juego, levanta automáticamente el tracker (run_tracker.sh) si el
## puerto está libre, y muestra una barra de estado para que sepas cuándo el
## control por mano está listo (evita que parezca que no funciona durante la
## carga, sobre todo la primera vez que se descargan las dependencias).

signal hand_updated

const UDP_PORT := 5005
const LANDMARK_COUNT := 21
const NO_HAND_TIMEOUT := 0.5   # segundos sin datagrama -> se corta el tracking
const TRACKER_SCRIPT := "res://run_tracker.sh"
const STATUS_FILE := "res://tracker_server/.tracker.status"
const NO_DATA_WARN_SEC := 25.0   # si tras esto sigue sin llegar nada, algo falló

var _udp := PacketPeerUDP.new()
var _points := PackedVector3Array()   # 21 landmarks normalizados (x,y,z)
var has_hand := false
var _last_packet_time := 0.0
var _got_datagram := false   # el tracker ya está mandando datos
var _tracker_pid := 0        # PID del tracker lanzado por el juego (0 = ninguno)
var _spawn_time := 0.0

# --- UI de estado del tracker ---
var _panel: PanelContainer
var _lbl: Label
var _bar: ProgressBar
var _status_path := ""
var _cached_phase := ""
var _last_phase_read := 0.0
var _last_ui_update := 0.0

func _ready() -> void:
	var err := _udp.bind(UDP_PORT)
	if err != OK:
		push_warning("[HandTracking] No pudo bindear UDP %d: %s" % [UDP_PORT, err])
	else:
		# Puerto libre => nadie más lo usa; levantamos el tracker de mano de fondo.
		_start_tracker_server()

func _start_tracker_server() -> void:
	var script_path := ProjectSettings.globalize_path(TRACKER_SCRIPT)
	_status_path = ProjectSettings.globalize_path(STATUS_FILE)
	_spawn_time = Time.get_ticks_msec() / 1000.0
	print("[HandTracking] Levantando tracker de mano (MediaPipe): ", script_path)
	_tracker_pid = OS.create_process(script_path, [])
	if _tracker_pid > 0:
		print("[HandTracking] Tracker lanzado (PID=%d). Esperando landmarks por UDP %d." % [_tracker_pid, UDP_PORT])
	else:
		push_warning("[HandTracking] No se pudo lanzar el tracker (código=%d). Control por teclado." % _tracker_pid)
	_build_status_ui()
	_update_status_ui(true)

func _exit_tree() -> void:
	# Al cerrar el juego, apagamos el tracker que levantamos para no dejar la cámara abierta.
	if _tracker_pid > 0:
		print("[HandTracking] Cerrando tracker (PID=%d)" % _tracker_pid)
		OS.kill(_tracker_pid)
		_tracker_pid = 0
	if _panel:
		_panel.queue_free()

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
	_panel.offset_left = -190
	_panel.offset_right = 190
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
	if _got_datagram:
		_set_ui_visible(true)
		_set_bar_fill(Color(0.1, 1.0, 0.45, 1))
		_lbl.text = "Control por mano listo — mostrá la mano"
		_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.55, 1))
		_bar.value = 100.0
		return

	var f := _read_status_phase()
	_set_ui_visible(true)

	if _tracker_pid <= 0:
		_lbl.text = "Tracker no disponible — se usa el teclado"
		_lbl.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
		_set_bar_fill(Color(1, 0.3, 0.3, 1))
		_bar.value = 0.0
	elif f == "installing":
		_lbl.text = "Instalando control por mano (primera vez)…"
		_indeterminate_bar(now)
		_lbl.add_theme_color_override("font_color", Color(0.9, 0.35, 1, 1))
		_set_bar_fill(Color(0.9, 0.35, 1, 1))
	elif f.begins_with("error") or now - _spawn_time > NO_DATA_WARN_SEC:
		_lbl.text = "La cámara no responde — se usa el teclado"
		_lbl.add_theme_color_override("font_color", Color(1, 0.5, 0.5, 1))
		_set_bar_fill(Color(1, 0.3, 0.3, 1))
		_bar.value = 0.0
	else:
		_lbl.text = "Iniciando control por mano…"
		_indeterminate_bar(now)
		_lbl.add_theme_color_override("font_color", Color(0, 0.9, 1, 1))
		_set_bar_fill(Color(0, 0.9, 1, 1))

func _indeterminate_bar(now: float) -> void:
	# Barra "de descarga" animada mientras no sabemos cuándo termina.
	_bar.value = fmod(now * 38.0, 100.0)

func _set_bar_fill(c: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = c
	fill.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill)

func _read_status_phase() -> String:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_phase_read < 0.3:
		return _cached_phase
	_last_phase_read = now
	_cached_phase = ""
	if FileAccess.file_exists(_status_path):
		var f := FileAccess.open(_status_path, FileAccess.READ)
		if f:
			_cached_phase = f.get_as_text().strip_edges()
			f.close()
	return _cached_phase

func _set_ui_visible(v: bool) -> void:
	if _panel and _panel.visible != v:
		_panel.visible = v