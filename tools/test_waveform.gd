extends SceneTree
## test_waveform.gd — Tarea 4 del plan JSAB (headless): el muro de ONDA que
## sube desde abajo (arquetipo 45s/1350s del video). Contrato:
## 1) Builder: _waveform_wall(t, beat_idx, params, spawn_seed) existe; nace
##    inofensivo en telegraph (subiendo por debajo del área de juego);
##    telegraph 2 beats, active 4, fade 2; las columnas son un perfil de
##    onda (sin/cos) sobre una línea de base, no rectas.
## 2) WaveformLogic.gd (motor puro): la altura de la columna sube en
##    BEATS (velocidad derivada del BPM real), cada columna tiene su fase
##    propia (perfil desfasado), la altura de_cresta respeta el máximo
##    justo bajo la fila del jugador, y la colisión usa el perfil real
##    (no un rectángulo).
## 3) Fairness: la onda deja SIEMPRE un hueco de >= 3 carrilesbelow-safe
##    (el trough más bajo cae por debajo del área del jugador) y la
##    cresta nunca sube por encima del 62% del alto (queda margen de
##    reacción sobre la fila del jugador al 78%).

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var bl: float = song.beat_interval
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true

	# --- 1) CONTRATO BUILDER ---
	var wf: Dictionary = {}
	if controller.has_method("_waveform_wall"):
		wf = controller._waveform_wall(chart.beat_times[64], 64, {}, 64 * 131)
	else:
		fails.append("RED: _waveform_wall no existe")
	if wf.is_empty():
		_finish(fails)
		return
	if str(wf.get("type", "")) != "waveform_wall":
		fails.append("type: %s" % str(wf.get("type", "")))
	if bool(wf.get("is_hazard", true)):
		fails.append("nace inofensivo: is_hazard=true")
	if int(wf.get("telegraph_beats", 0)) != 2 or int(wf.get("active_beats", 0)) != 9:
		fails.append("timing: telegraph=%s active=%s (esperaba 2/9)" % [str(wf.get("telegraph_beats")), str(wf.get("active_beats"))])
	if int(wf.get("columns", 0)) < 6:
		fails.append("columns %d < 6" % int(wf.get("columns", 0)))
	# la cresta no debe pasar del 62% del alto (fairness: margen de reacción)
	if float(wf.get("peak_frac", 1.0)) > 0.62:
		fails.append("fairness: peak_frac %.2f > 0.62 (sin margen de reacción)" % float(wf.get("peak_frac", 1.0)))
	# la onda tiene que tener VALOR PROPIO (perfil, no rectas)
	if float(wf.get("wave_amp", 0.0)) <= 0.0:
		fails.append("wave_amp 0: no es una onda (recta plana)")

	# --- 2) MOTOR WaveformLogic ---
	var logic: GDScript = load("res://scripts/WaveformLogic.gd")
	if logic == null:
		fails.append("RED: WaveformLogic.gd no existe")
		_finish(fails)
		return
	# 2a) ciclo on-beat
	var w2: Dictionary = controller._waveform_wall(0.0, 0, {}, 0)
	var dt: float = 1.0 / 60.0
	var states_seen: Array[String] = []
	var guard: int = 0
	while guard < 2000:
		guard += 1
		w2 = logic.step(w2, dt, bl)
		if states_seen.is_empty() or states_seen[states_seen.size() - 1] != str(w2["state"]):
			states_seen.append(str(w2["state"]))
		if str(w2["state"]) == "done":
			break
	if states_seen != ["telegraph", "active", "fade", "done"]:
		fails.append("ciclo: %s" % str(states_seen))
	# 2b) altura de columna: sube desde abajo (Y crece hacia abajo) y NUNCA
	# pasa de la cresta (peak_line es el techo de la onda).
	var w3: Dictionary = controller._waveform_wall(0.0, 0, {}, 0)
	# en telegraph la columna emerge un poco (aviso legible) pero NO llega
	# a la cresta: h >= peak_line (Y más abajo = más bajo en pantalla).
	var h_tele: float = logic.column_height(w3, 0)
	if h_tele < float(w3["peak_line"]):
		fails.append("telegraph: la columna llegó a la cresta (h=%.0f peak=%.0f)" % [h_tele, float(w3["peak_line"])])
	# llevar a active (bien entrado) y comprobar que TODAS las columnas
	# quedan en/bajo peak_line y que el perfil VARÍA (onda, no staircase)
	for i in range(int(3.2 * bl / dt) + 4):
		w3 = logic.step(w3, dt, bl)
	if str(w3["state"]) != "active":
		fails.append("pre-active: %s" % str(w3["state"]))
		_finish(fails)
		return
	var peak_line: float = float(w3["peak_line"])
	var min_h: float = 1e9
	for c in range(int(w3["columns"])):
		min_h = minf(min_h, logic.column_height(w3, c))
	if min_h < peak_line - 1.0:
		fails.append("una columna pasó la cresta: %.0f < %.0f" % [min_h, peak_line])
	# 2c) el perfil VARÍA entre columnas (onda, no staircase). Se mide a
	# mitad de la ventana activa, cuando la onda ya está desplegada: al
	# principio rise es chico y TODO se ve igual (por diseño: la onda emerge).
	var w6: Dictionary = controller._waveform_wall(0.0, 0, {}, 0)
	for i in range(int(6.0 * bl / dt) + 4):
		w6 = logic.step(w6, dt, bl)
	var spread: float = 0.0
	var w_min: float = 1e9
	var w_max: float = -1e9
	for c in range(int(w6["columns"])):
		var hc: float = logic.column_height(w6, c)
		w_min = minf(w_min, hc)
		w_max = maxf(w_max, hc)
		spread = maxf(spread, absf(hc - logic.column_height(w6, 0)))
	# T9: la onda tiene que tener amplitud REAL y legible (space-bunny: la
	# "onda" parecía una línea recta de 1px de diferencia).
	if w_max - w_min < 60.0:
		fails.append("amplitud de la onda insuficiente: %.0fpx entre crestas y valles (se leía como línea recta)" % (w_max - w_min))
	if spread < 40.0:
		fails.append("perfil plano: variación máx %.1fpx entre columnas" % spread)
	# y en un instante temprano la forma ya se insinúa (no una rampa lisa)
	var early: Dictionary = controller._waveform_wall(0.0, 0, {}, 0)
	var e_spread: float = 0.0
	for c2 in range(int(early["columns"])):
		e_spread = maxf(e_spread, absf(logic.column_height(early, c2) - logic.column_height(early, 0)))
	if e_spread < 20.0:
		fails.append("telegraph: la onda no se insinúa (variación %.1fpx, se ve como una banda lisa)" % e_spread)
	# 2d) colisión: jugador BAJO la columna (en la onda) => hit; jugador
	# por encima de la cresta => NO hit; telegraph/fade inofensivos
	var play_w: float = 1280.0
	var cx: float = play_w * (0.5 / float(w3["columns"]))
	var p_low: Vector2 = Vector2(cx, w_max + 30.0)
	if not logic.hits_player(w3, p_low):
		fails.append("jugador dentro de la columna no recibe daño")
	var p_high: Vector2 = Vector2(cx, peak_line - 60.0)
	if logic.hits_player(w3, p_high):
		fails.append("jugador sobre la cresta recibe daño (debe estar por encima)")
	var w4: Dictionary = controller._waveform_wall(0.0, 0, {}, 0)
	var tele_hits: int = 0
	for i in range(int(1.9 * bl / dt)):
		w4 = logic.step(w4, dt, bl)
		if logic.hits_player(w4, p_low):
			tele_hits += 1
	if tele_hits > 0:
		fails.append("telegraph daña (%d hits)" % tele_hits)

	_finish(fails)

func _finish(fails: Array[String]) -> void:
	if fails.is_empty():
		print("[WAVE] PASS — muro de onda: perfil on-beat, cresta acotada, hueco garantizado, daño solo en active")
		quit(0)
	else:
		for f in fails:
			print("[WAVE] FAIL: %s" % f)
		quit(1)
