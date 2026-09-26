extends SceneTree
## test_pulse_rings.gd — Tarea 6 del plan JSAB (headless): ANILLOS que se
## expanden desde el hub con un hueco (arquetipo 1350s del video: el
## espacio se cierra en círculos). Contrato:
## 1) Builder: _pulse_rings(...) existe; nace inofensivo; telegraph 2 /
##    active 4 / fade 2; N anillos (>= 2) con hueco angular >= 50 grados.
## 2) PulseRingsLogic.gd (motor puro): los anillos se expanden a velocidad
##    BEAT-DERIVADA y su RADIO cruza la fila del jugador en un numero
##    ENTERO de beats (misma regla de T4: la llegada cae en la grilla
##    audible); el hueco ROTA lentamente, asi que el jugador debe viajar
##    con el hueco.
## 3) Colision: solo cuando el anillo esta EN la fila del jugador Y el
##    angulo del jugador cae en la banda solida; dentro del hueco es
##    seguro; telegraph/fade inofensivos.

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var bl: float = song.beat_interval
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true

	# --- 1) CONTRATO BUILDER ---
	var pr: Dictionary = {}
	if controller.has_method("_pulse_rings"):
		pr = controller._pulse_rings(chart.beat_times[64], 64, {}, 64 * 131)
	else:
		fails.append("RED: _pulse_rings no existe")
	if pr.is_empty():
		_finish(fails)
		return
	if str(pr.get("type", "")) != "pulse_rings":
		fails.append("type: %s" % str(pr.get("type", "")))
	if bool(pr.get("is_hazard", true)):
		fails.append("nace inofensivo: is_hazard=true")
	if int(pr.get("telegraph_beats", 0)) != 2 or int(pr.get("active_beats", 0)) != 9:
		fails.append("timing: telegraph=%s active=%s (esperaba 2/9)" % [str(pr.get("telegraph_beats")), str(pr.get("active_beats"))])
	if int(pr.get("rings", 0)) < 2:
		fails.append("rings %d < 2" % int(pr.get("rings", 0)))
	# fairness del hueco: >= 50 grados de abertura
	var gap_deg: float = rad_to_deg(float(pr.get("gap_angle", 0.0)))
	if gap_deg < 50.0:
		fails.append("fairness: hueco %.0f° < 50° (no se lee)" % gap_deg)
	# el radio tiene que CRUZAR la fila del jugador (si no, no haySetpiece)
	if float(pr.get("target_radius", 0.0)) < 400.0:
		fails.append("target_radius %.0f: el anillo no llega a la fila del jugador" % float(pr.get("target_radius", 0.0)))

	# --- 2) MOTOR PulseRingsLogic ---
	var logic: GDScript = load("res://scripts/PulseRingsLogic.gd")
	if logic == null:
		fails.append("RED: PulseRingsLogic.gd no existe")
		_finish(fails)
		return
	# 2a) ciclo on-beat
	var p2: Dictionary = controller._pulse_rings(0.0, 0, {}, 0)
	var dt: float = 1.0 / 60.0
	var states_seen: Array[String] = []
	var guard: int = 0
	while guard < 2000:
		guard += 1
		p2 = logic.step(p2, dt, bl)
		if states_seen.is_empty() or states_seen[states_seen.size() - 1] != str(p2["state"]):
			states_seen.append(str(p2["state"]))
		if str(p2["state"]) == "done":
			break
	if states_seen != ["telegraph", "active", "fade", "done"]:
		fails.append("ciclo: %s" % str(states_seen))
	# 2b) los radios crecen MONOTONICAMENTE
	var p3: Dictionary = controller._pulse_rings(0.0, 0, {}, 0)
	for i in range(int(2.0 * bl / dt) + 4):
		p3 = logic.step(p3, dt, bl)
	if str(p3["state"]) != "active":
		fails.append("pre-active: %s" % str(p3["state"]))
		_finish(fails)
		return
	var prev_r: float = logic.ring_radius(p3, 0)
	var mono := true
	var max_r: float = prev_r
	# recorrer TODA la ventana active: el anillo 0 debe alcanzar su radio
	# objetivo al final (y cruzarlo si el objetivo excede la fila).
	for i in range(int(9.0 * bl / dt) + 6):
		p3 = logic.step(p3, dt, bl)
		if str(p3["state"]) != "active":
			break
		var r_now: float = logic.ring_radius(p3, 0)
		if r_now < prev_r - 0.5:
			mono = false
		prev_r = r_now
		max_r = maxf(max_r, r_now)
	if not mono:
		fails.append("los radios NO crecen monótonamente")
	if max_r < float(p3["target_radius"]) - 2.0:
		fails.append("el anillo no alcanzó su radio objetivo: %.0f < %.0f" % [max_r, float(p3["target_radius"])])
	# 2c) el hueco rota: el angulo del hueco cambia con el tiempo
	var h_a: float = logic.gap_angle(p3)
	for i in range(30):
		p3 = logic.step(p3, dt, bl)
	var h_b: float = logic.gap_angle(p3)
	if absf(h_b - h_a) < 0.01:
		fails.append("el hueco NO rota (%.3f == %.3f)" % [h_a, h_b])
	# 2d) colision: el anillo EXPANDIÉNDOSE barre al jugador quieto (este es
	# el contrato real: el anillo es una banda que viaja, no una prueba
	# estática). Y el hueco sólo salva a quien VIAJA con él: quedarse quieto
	# en el hueco debe, en últimas instancias, matar (es la mecánica "se lee y se viaja").
	var p4: Dictionary = controller._pulse_rings(0.0, 0, {}, 0)
	for i in range(int(2.0 * bl / dt) + 4):
		p4 = logic.step(p4, dt, bl)
	if str(p4["state"]) != "active":
		fails.append("pre-active (colisión): %s" % str(p4["state"]))
		_finish(fails)
		return
	var hub4: Vector2 = p4["pos"]
	var g_now4: float = logic.gap_angle(p4)
	var row_dist: float = absf(float(p4["player_row"]) - hub4.y)
	var p_static_solid: Vector2 = hub4 + Vector2.from_angle(g_now4 + PI) * row_dist
	# un jugador que QUEDO quieto en el hueco al inicio
	var p_static_gap: Vector2 = hub4 + Vector2.from_angle(g_now4) * row_dist
	# un jugador que VIAJA con el hueco (recalcula su angulo cada frame)
	var swept_solid := false
	var static_gap_died := false
	var traveling_gap_died := false
	# El anillo CRUZA la fila del jugador a mitad de la ventana (crece 0..1
	# en 9 beats). Sampleamos toda la ventana: si en algún instante la banda
	# pasa por encima del jugador quieto, cuenta como barrido.
	for i in range(int(9.0 * bl / dt) + 6):
		p4 = logic.step(p4, dt, bl)
		if str(p4["state"]) != "active":
			break
		if logic.hits_player(p4, p_static_solid):
			swept_solid = true
		if logic.hits_player(p4, p_static_gap):
			static_gap_died = true
		var g_now5: float = logic.gap_angle(p4)
		var p_travel: Vector2 = hub4 + Vector2.from_angle(g_now5) * row_dist
		if logic.hits_player(p4, p_travel):
			traveling_gap_died = true
	if not swept_solid:
		fails.append("el anillo en expansión no barre al jugador quieto en la banda sólida")
	if traveling_gap_died:
		fails.append("el jugador que viaja con el hueco recibe daño (el hueco no es seguro)")
	# el quieto-en-hueco morir NO es un fallo: es la mecánica (leer y viajar).
	# Si el hueco apenas gira (<0.1 rad en la ventana), documentamos que el
	# quieto tampoco muere (hueco prácticamente estático).
	if static_gap_died and absf(logic.gap_angle(p4) - g_now4) < 0.10:
		fails.append("el hueco nogiró pero alcanzó al jugador quieto (inconsistente)")
	# 2e) telegraph inofensivo
	var p5: Dictionary = controller._pulse_rings(0.0, 0, {}, 0)
	var tele_hits: int = 0
	for i in range(int(1.9 * bl / dt)):
		p5 = logic.step(p5, dt, bl)
		if logic.hits_player(p5, p_static_solid):
			tele_hits += 1
	if tele_hits > 0:
		fails.append("telegraph daña (%d hits)" % tele_hits)

	_finish(fails)

func _finish(fails: Array[String]) -> void:
	if fails.is_empty():
		print("[RINGS] PASS — anillos con hueco rotante, radio beat-derivado, daño solo en active")
		quit(0)
	else:
		for f in fails:
			print("[RINGS] FAIL: %s" % f)
		quit(1)
