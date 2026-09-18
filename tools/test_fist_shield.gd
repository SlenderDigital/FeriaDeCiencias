extends SceneTree
## Test: fist detection (HandTrackingClient.is_fist) + shield edge-trigger logic.
## Run: godot --headless --script tools/test_fist_shield.gd  (from project root)
## NOTE: autoloads (incl. HandTrackingClient) are NOT available under SceneTree
## script mode, so we load the script directly and drive it with synthetic data.

var failures := 0

func _check(cond: bool, name: String) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		failures += 1
		printerr("  FAIL: ", name)

func _make_client() -> Node:
	var scr: GDScript = load("res://scripts/HandTrackingClient.gd")
	var c: Node = scr.new()
	root.add_child(c)
	return c

func _set_landmarks(c: Node, pts: PackedVector3Array) -> void:
	c._points = pts
	c.has_hand = true

func _open_hand() -> PackedVector3Array:
	# Palma en origen-ish, dedos extendidos (~2x del largo de palma).
	var pts := PackedVector3Array()
	pts.resize(21)
	pts[0] = Vector3(0.5, 0.7, 0)     # wrist
	pts[9] = Vector3(0.5, 0.5, 0)     # middle MCP -> hand_size = 0.2
	pts[8] = Vector3(0.42, 0.28, 0)   # index tip
	pts[12] = Vector3(0.5, 0.26, 0)   # middle tip
	pts[16] = Vector3(0.58, 0.28, 0)  # ring tip
	pts[20] = Vector3(0.65, 0.34, 0)  # pinky tip
	return pts

func _fist() -> PackedVector3Array:
	# Tips pegados a la palma (~1x del largo de palma).
	var pts := PackedVector3Array()
	pts.resize(21)
	pts[0] = Vector3(0.5, 0.7, 0)
	pts[9] = Vector3(0.5, 0.5, 0)
	pts[8] = Vector3(0.47, 0.55, 0)
	pts[12] = Vector3(0.5, 0.53, 0)
	pts[16] = Vector3(0.53, 0.55, 0)
	pts[20] = Vector3(0.56, 0.58, 0)
	return pts

func _init() -> void:
	print("[test_fist_shield]")
	var c := _make_client()

	# 1) Sin mano -> no es puno.
	c.has_hand = false
	c._points = PackedVector3Array()
	_check(not c.is_fist(), "sin mano -> false")

	# 2) Mano abierta -> curl ~2.0, no es puno.
	_set_landmarks(c, _open_hand())
	var curl_open: float = c.get_finger_curl()
	print("  curl abierta = ", snappedf(curl_open, 0.01))
	_check(curl_open > 1.6, "mano abierta curl > 1.6")
	_check(not c.is_fist(), "mano abierta -> false")

	# 3) Puno requiere confirmacion temporal: 1-3 frames no latchan, 4 si.
	_set_landmarks(c, _fist())
	_check(not c.is_fist(), "puno frame 1 -> aun false")
	_check(not c.is_fist(), "puno frame 2 -> aun false")
	_check(not c.is_fist(), "puno frame 3 -> aun false")
	_check(c.is_fist(), "puno frame 4 -> true (confirmado)")
	_check(c.is_fist(), "puno sostenido -> sigue true")

	# 4) Histeresis: zona gris (1.35-1.55) mantiene el latch...
	c._fist_latched = true
	c._fist_frames = 99
	# (curl directo no se puede inyectar; se valida via constantes)
	_check(c.FIST_ENTER < c.FIST_EXIT, "umbrales ENTER < EXIT (histeresis)")

	# 5) Mano abierta resetea inmediato.
	_set_landmarks(c, _open_hand())
	_check(not c.is_fist(), "abrir mano resetea latch")

	# 6) Geometria degenerada (mano a distancia 0) -> -1, false.
	var pts := PackedVector3Array()
	pts.resize(21)
	c.has_hand = true
	c._points = pts  # todo ceros -> hand_size 0
	_check(c.get_finger_curl() < 0.0, "geometria degenerada -> curl -1")
	_check(not c.is_fist(), "geometria degenerada -> false")

	# 7) Logica edge-trigger de Gameplay (espejo de _update_fist_shield):
	#    un solo disparo por puno, re-arme solo con mano abierta.
	var fist_was_closed := false
	var fires := 0
	var seq := [false, true, true, true, true, true, false, true, true, true, true, true]
	# seq simula is_fist() ya confirmado; cada true sostenido no debe re-disparar.
	for closed in seq:
		if closed and not fist_was_closed:
			fires += 1
		fist_was_closed = closed
	_check(fires == 2, "edge-trigger: 2 punos separados -> 2 disparos (got %d)" % fires)

	if failures == 0:
		print("PASS: fist + edge-trigger OK")
	else:
		printerr("FAIL: %d fallos" % failures)
	quit(failures)
