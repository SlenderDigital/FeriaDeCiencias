extends Node
## HandTrackingClient — escucha landmarks de MediaPipe por UDP (127.0.0.1:5005)
## y expone: has_hand, get_palm_center() (normalizado 0-1, X espejada) y
## get_hand_angle_deg(). El emisor es tracker_server/ (dentro de este repo).
##
## Al abrir el juego, levanta automáticamente el tracker (run_tracker.sh) si el
## puerto está libre, y lo cierra al salir. No requiere que se corra a mano.

signal hand_updated

const UDP_PORT := 5005
const LANDMARK_COUNT := 21
const NO_HAND_TIMEOUT := 0.5   # segundos sin datagrama -> se corta el tracking
const TRACKER_SCRIPT := "res://run_tracker.sh"

var _udp := PacketPeerUDP.new()
var _points := PackedVector3Array()   # 21 landmarks normalizados (x,y,z)
var has_hand := false
var _last_packet_time := 0.0
var _tracker_pid := 0    # PID del tracker lanzado por el juego (0 = ninguno)

func _ready() -> void:
	var err := _udp.bind(UDP_PORT)
	if err != OK:
		push_warning("[HandTracking] No pudo bindear UDP %d: %s" % [UDP_PORT, err])
	else:
		# Puerto libre => nadie más lo usa; levantamos el tracker de mano de fondo.
		_start_tracker_server()

func _start_tracker_server() -> void:
	var script_path := ProjectSettings.globalize_path(TRACKER_SCRIPT)
	print("[HandTracking] Levantando tracker de mano (MediaPipe): ", script_path)
	_tracker_pid = OS.create_process(script_path, [])
	if _tracker_pid > 0:
		print("[HandTracking] Tracker lanzado (PID=%d). Esperando landmarks por UDP %d." % [_tracker_pid, UDP_PORT])
	else:
		push_warning("[HandTracking] No se pudo lanzar el tracker (código=%d). Control por teclado." % _tracker_pid)

func _exit_tree() -> void:
	# Al cerrar el juego, apagamos el tracker que levantamos para no dejar la cámara abierta.
	if _tracker_pid > 0:
		print("[HandTracking] Cerrando tracker (PID=%d)" % _tracker_pid)
		OS.kill(_tracker_pid)
		_tracker_pid = 0

func _process(_delta: float) -> void:
	# Timeout: si no llega datagrama, caer a teclado.
	if has_hand and Time.get_ticks_msec() / 1000.0 - _last_packet_time > NO_HAND_TIMEOUT:
		has_hand = false
	while _udp.get_available_packet_count() > 0:
		_parse(_udp.get_packet())

func _parse(data: PackedByteArray) -> void:
	if data.size() < 4:
		return
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