extends SceneTree
## test_sweep.gd — Tarea 3 del plan JSAB (headless): el láser que BARRE la
## pantalla. Contrato:
## 1) Builder: _laser_sweep(t, beat_idx, params, spawn_seed) existe; nace
##    inofensivo en telegraph; telegraph 2 beats, active 4, fade 2.
## 2) SweepLogic.gd (motor puro): el haz BARRE de ang_start a ang_end en la
##    ventana active (velocidad <= 90°/beat, plan fairness), colisión solo
##    en active, y el jugador DELANTE del haz nunca es tocado retroactivamente.
## 3) El barrido cae en beats: ang(t) es función del tiempo de vida; en los
##    límites de la ventana active el haz está en ang_start/ang_end exactos.

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var bl: float = song.beat_interval
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true

	# --- 1) CONTRATO BUILDER ---
	var sweep: Dictionary = {}
	if controller.has_method("_laser_sweep"):
		sweep = controller._laser_sweep(chart.beat_times[64], 64, {}, 64 * 131)
	else:
		fails.append("RED: _laser_sweep no existe")
	if sweep.is_empty():
		_finish(fails)
		return
	if str(sweep.get("type", "")) != "laser_sweep":
		fails.append("type: %s" % str(sweep.get("type", "")))
	if bool(sweep.get("is_hazard", true)):
		fails.append("nace inofensivo: is_hazard=true")
	if int(sweep.get("telegraph_beats", 0)) != 2 or int(sweep.get("active_beats", 0)) != 4:
		fails.append("timing: telegraph=%s active=%s (esperaba 2/9)" % [str(sweep.get("telegraph_beats")), str(sweep.get("active_beats"))])
	var sweep_rate: float = absf(float(sweep.get("sweep_deg_per_beat", 999.0)))
	if sweep_rate > 90.0:
		fails.append("fairness: barrido %.0f°/beat > 90° (ilegible)" % sweep_rate)

	# --- 2) MOTOR SweepLogic ---
	var logic: GDScript = load("res://scripts/SweepLogic.gd")
	if logic == null:
		fails.append("RED: SweepLogic.gd no existe")
		_finish(fails)
		return
	# 2a) ciclo de estados on-beat
	var sw: Dictionary = controller._laser_sweep(0.0, 0, {}, 0)
	var dt: float = 1.0 / 60.0
	var states_seen: Array[String] = []
	var guard: int = 0
	while guard < 2000:
		guard += 1
		sw = logic.step(sw, dt, bl)
		if states_seen.is_empty() or states_seen[states_seen.size() - 1] != str(sw["state"]):
			states_seen.append(str(sw["state"]))
		if str(sw["state"]) == "done":
			break
	if states_seen != ["telegraph", "active", "fade", "done"]:
		fails.append("ciclo: %s" % str(states_seen))
	# 2b) ángulo exacto en los bordes de la ventana active
	var sw2: Dictionary = controller._laser_sweep(0.0, 0, {}, 0)
	var ang_start: float = float(sw2.get("ang_start", 0.0))
	var ang_end: float = float(sw2.get("ang_end", 0.0))
	var a_at_active: float = -1.0
	var a_at_fade: float = -1.0
	var active_seen := false
	for i in range(900):
		sw2 = logic.step(sw2, dt, bl)
		if str(sw2["state"]) == "active" and not active_seen:
			active_seen = true
			a_at_active = logic.beam_angle(sw2)
		if str(sw2["state"]) == "fade" and a_at_fade < 0.0:
			a_at_fade = logic.beam_angle(sw2)
			break
	# al ENTRAR en active el haz está en ang_start (±1 frame de tolerancia)
	var total_sweep: float = absf(ang_end - ang_start)
	var tol: float = total_sweep * dt / (4.0 * bl) + 0.02
	if absf(a_at_active - ang_start) > tol:
		fails.append("al entrar active: ang=%.3f esperaba ang_start=%.3f" % [a_at_active, ang_start])
	if absf(a_at_fade - ang_end) > tol:
		fails.append("al salir de active: ang=%.3f esperaba ang_end=%.3f" % [a_at_fade, ang_end])
	# 2c) colisión: jugador en el ángulo DEL haz en active => hit; jugador
	# a 25° del haz => NO hit (el haz tiene ancho finito ~12px)
	var sw3: Dictionary = controller._laser_sweep(0.0, 0, {}, 0)
	for i in range(int(2.0 * bl / dt) + 2):
		sw3 = logic.step(sw3, dt, bl)
	if str(sw3["state"]) != "active":
		fails.append("pre-active: %s" % str(sw3["state"]))
		_finish(fails)
		return
	var hub: Vector2 = sw3["pos"]
	var rad: float = 1400.0   # beam largo: cruza la pantalla
	var b_ang: float = logic.beam_angle(sw3)
	var p_on: Vector2 = hub + Vector2.from_angle(b_ang) * 500.0
	if not logic.hits_player(sw3, p_on):
		fails.append("jugador SOBRE el haz no recibe daño")
	var p_off: Vector2 = hub + Vector2.from_angle(b_ang + 0.44) * 500.0   # ~25°
	if logic.hits_player(sw3, p_off):
		fails.append("jugador a 25° del haz recibe daño (ancho excesivo)")
	# 2d) telegraph inofensivo
	var sw4: Dictionary = controller._laser_sweep(0.0, 0, {}, 0)
	var p_ray2: Vector2 = hub + Vector2.from_angle(float(sw4.get("ang_start", 0.0))) * 500.0
	var tele_hits: int = 0
	for i in range(int(1.9 * bl / dt)):
		sw4 = logic.step(sw4, dt, bl)
		if logic.hits_player(sw4, p_ray2):
			tele_hits += 1
	if tele_hits > 0:
		fails.append("telegraph daña (%d)" % tele_hits)

	_finish(fails)

func _finish(fails: Array[String]) -> void:
	if fails.is_empty():
		print("[SWEEP] PASS — barrido on-beat, 60°/beat, daño solo en active, ancho finito")
		quit(0)
	else:
		for f in fails:
			print("[SWEEP] FAIL: %s" % f)
		quit(1)
