extends SceneTree
## test_corridor.gd — Tarea 5 del plan JSAB (headless): el CORREDOR que
## se cierra desde los costados (arquetipo 225s del video: dos paredes que
## aprietan el espacio jugable). Contrato:
## 1) Builder: _squeeze_corridor(...) existe; nace inofensivo; telegraph 2 /
##    active 4 / fade 2.
## 2) SqueezeLogic.gd (motor puro): dos paredes que avanzan desde los
##    bordes hacia el centro a velocidad BEAT-DERIVADA; el pasillo
##    disponible se reduce de forma MONÓTONA y NUNCA por debajo de
##    min_gap (fairness dura: siempre hay un bolsillo comodo).
## 3) Colisión por FRANJA (banda vertical): jugador dentro de la banda
##    izquierda/derecha => hit; en el pasillo => NO hit; telegraph/fade
##    inofensivos.

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var bl: float = song.beat_interval
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true

	# --- 1) CONTRATO BUILDER ---
	var sq: Dictionary = {}
	if controller.has_method("_squeeze_corridor"):
		sq = controller._squeeze_corridor(chart.beat_times[64], 64, {}, 64 * 131)
	else:
		fails.append("RED: _squeeze_corridor no existe")
	if sq.is_empty():
		_finish(fails)
		return
	if str(sq.get("type", "")) != "squeeze_corridor":
		fails.append("type: %s" % str(sq.get("type", "")))
	if bool(sq.get("is_hazard", true)):
		fails.append("nace inofensivo: is_hazard=true")
	if int(sq.get("telegraph_beats", 0)) != 2 or int(sq.get("active_beats", 0)) != 4:
		fails.append("timing: telegraph=%s active=%s (esperaba 2/4)" % [str(sq.get("telegraph_beats")), str(sq.get("active_beats"))])
	if float(sq.get("min_gap", 0.0)) <= 0.0:
		fails.append("min_gap 0: sin bolsillo garantizado (fairness)")
	# el pasillo inicial no puede ser el mínimo (aprieta, no empieza cerrado)
	if float(sq.get("start_gap", 0.0)) <= float(sq.get("min_gap", 0.0)):
		fails.append("start_gap <= min_gap: el corredor no se cierra de verdad")

	# --- 2) MOTOR SqueezeLogic ---
	var logic: GDScript = load("res://scripts/SqueezeLogic.gd")
	if logic == null:
		fails.append("RED: SqueezeLogic.gd no existe")
		_finish(fails)
		return
	# 2a) ciclo on-beat
	var s2: Dictionary = controller._squeeze_corridor(0.0, 0, {}, 0)
	var dt: float = 1.0 / 60.0
	var states_seen: Array[String] = []
	var guard: int = 0
	while guard < 2000:
		guard += 1
		s2 = logic.step(s2, dt, bl)
		if states_seen.is_empty() or states_seen[states_seen.size() - 1] != str(s2["state"]):
			states_seen.append(str(s2["state"]))
		if str(s2["state"]) == "done":
			break
	if states_seen != ["telegraph", "active", "fade", "done"]:
		fails.append("ciclo: %s" % str(states_seen))
	# 2b) el pasillo se cierra MONOTÓNICAMENTE y respeta min_gap, y LLEGA al
	# bolsillo mínimo al final de la ventana active (easeInOut incluido).
	var s3: Dictionary = controller._squeeze_corridor(0.0, 0, {}, 0)
	for i in range(int(2.0 * bl / dt) + 4):
		s3 = logic.step(s3, dt, bl)
	if str(s3["state"]) != "active":
		fails.append("pre-active: %s" % str(s3["state"]))
		_finish(fails)
		return
	var min_gap: float = float(s3["min_gap"])
	var prev_gap: float = logic.gap_size(s3)
	var monotonic := true
	var respected := true
	var play_w: float = 1280.0
	# recorrer TODA la ventana active
	for i in range(int(4.0 * bl / dt) + 4):
		s3 = logic.step(s3, dt, bl)
		if str(s3["state"]) != "active":
			break
		var g_now: float = logic.gap_size(s3)
		if g_now > prev_gap + 0.5:
			monotonic = false
		if g_now < min_gap - 0.5:
			respected = false
		prev_gap = g_now
	if not monotonic:
		fails.append("el pasillo NO se cierra monótonamente (se abre a %.0f)" % prev_gap)
	if not respected:
		fails.append("el pasillo bajó de min_gap (%.0f < %.0f)" % [prev_gap, min_gap])
	if prev_gap > min_gap + 2.0:
		fails.append("el pasillo no llegó al bolsillo mínimo: %.0f (min %.0f)" % [prev_gap, min_gap])
	# 2c) colisión por franja — a mitad de la ventana active (no al final,
	# cuando ya está en fade y no hace daño por contrato).
	var s5: Dictionary = controller._squeeze_corridor(0.0, 0, {}, 0)
	for i in range(int(2.0 * bl / dt) + 4):
		s5 = logic.step(s5, dt, bl)
	if str(s5["state"]) != "active":
		fails.append("pre-active (colisión): %s" % str(s5["state"]))
		_finish(fails)
		return
	var edges_c: Vector2 = logic.band_inner_edges(s5)
	var p_left: Vector2 = Vector2(edges_c.x - 40.0, 560.0)
	var p_mid: Vector2 = Vector2(logic.gap_center(s5), 560.0)
	if not logic.hits_player(s5, p_left):
		fails.append("jugador en la banda izquierda no recibe daño")
	if logic.hits_player(s5, p_mid):
		fails.append("jugador en el pasillo recibe daño (el bolsillo debe ser seguro)")
	# 2d) telegraph/fade inofensivos
	var s4: Dictionary = controller._squeeze_corridor(0.0, 0, {}, 0)
	var tele_hits: int = 0
	for i in range(int(1.9 * bl / dt)):
		s4 = logic.step(s4, dt, bl)
		if logic.hits_player(s4, p_left):
			tele_hits += 1
	if tele_hits > 0:
		fails.append("telegraph daña (%d hits)" % tele_hits)

	_finish(fails)

func _finish(fails: Array[String]) -> void:
	if fails.is_empty():
		print("[CORRIDOR] PASS — cierre bilateral monótono, min_gap respetado, pasillo seguro, daño solo en active")
		quit(0)
	else:
		for f in fails:
			print("[CORRIDOR] FAIL: %s" % f)
		quit(1)
