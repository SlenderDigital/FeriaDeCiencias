extends SceneTree
## Test headless del arranque del tracker: timeout a failed con pista (nunca
## "cargando" eterno) y auto-recuperación cuando llegan datagramas.

const HTC: GDScript = preload("res://scripts/HandTrackingClient.gd")

func _init() -> void:
	_run.call_deferred()

func _make_packet_21() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(4 + 21 * 12)
	bytes.encode_s32(0, 21)
	for i in range(21 * 12):
		bytes[4 + i] = 0
	return bytes

func _run() -> void:
	var fails: Array[String] = []
	# Sin add_child a propósito: _ready lanzaría un tracker real. Solo
	# probamos la máquina de estados (no necesita árbol).
	var htc: Node = HTC.new()
	# Sin status file ni paquetes: _tracker_live() false, _status_fresh() false.
	htc._status_path = "/tmp/definitivamente_no_existe_12345.status"

	# 1) Timeout: arranque viejo sin señal -> failed con hint.
	# (now explícito: en headless los ticks pueden ser <31s y boot quedaría <0.)
	htc._spawn_state = "spawned"
	htc._boot_start = 1000.0
	htc._last_packet_time = 0.0
	htc._check_boot_timeout(1031.0)
	if htc._spawn_state != "failed":
		fails.append("timeout no pasó a failed (estado=%s)" % htc._spawn_state)
	if htc._boot_fail_hint == "":
		fails.append("timeout sin hint para el banner")

	# 2) Arranque reciente: todavía esperando, NO falla.
	htc._spawn_state = "spawned"
	htc._boot_start = Time.get_ticks_msec() / 1000.0
	htc._boot_fail_hint = ""
	htc._check_boot_timeout()
	if htc._spawn_state != "spawned":
		fails.append("falló con arranque de 0s (falso positivo)")

	# 3) Habló después del arranque: vivo aunque pasen 30s.
	htc._spawn_state = "spawned"
	htc._boot_start = 1000.0
	htc._last_packet_time = 1001.0
	htc._boot_fail_hint = ""
	htc._check_boot_timeout(1061.0)
	if htc._spawn_state != "spawned":
		fails.append("falló con tracker hablando (falso positivo)")

	# 4) Auto-recuperación: datagrama válido tras failed -> running.
	htc._spawn_state = "failed"
	htc._parse(_make_packet_21())
	if htc._spawn_state != "running":
		fails.append("no se recuperó al llegar datagramas (estado=%s)" % htc._spawn_state)

	htc.free()
	if fails.is_empty():
		print("[TRACKERBOOT] PASS — timeout a failed con pista, sin falsos positivos, auto-recupera")
		quit(0)
	else:
		print("[TRACKERBOOT] FAIL: ", "; ".join(fails))
		quit(1)
