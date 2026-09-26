extends SceneTree
## test_spoke_fan.gd — Tarea 2 del plan JSAB (headless): abanico de rayos
## rotando con huecos legibles. DOS contratos:
## 1) Builder (PatternController._spoke_fan): fairness del spawn.
## 2) Motor (Gameplay): ciclo beat-derivado telegraph->active->fade,
##    colisión SOLO en active, y el hueco ROta con el abanico: un jugador
##    parado en el arco del hueco jamás recibe daño.

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var bl: float = song.beat_interval
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true

	# ============ 1) CONTRATO BUILDER ============
	var fan: Dictionary = {}
	if controller.has_method("_spoke_fan"):
		fan = controller._spoke_fan(chart.beat_times[64], 64)
	else:
		fails.append("RED: _spoke_fan no existe")
	if fan.is_empty():
		_finish(fails)
		return
	if str(fan.get("type", "")) != "spoke_fan":
		fails.append("type: %s" % str(fan.get("type", "")))
	# T9 (space-bunny): el piso de justicia del abanico es el ÁNGULO del
	# hueco, no la cantidad de radios. Con 6+ radios el hueco quedaba en
	# cúñetas discretas y el ojo leía "cobertura 360° sin salida". Ahora el
	# contrato es un sector libre continuo y ancho.
	var n_sp: int = int(fan.get("spokes", 0))
	var gap_sp: int = int(fan.get("gap_spokes", 0))
	var gap_deg: float = rad_to_deg(TAU * float(gap_sp) / maxf(float(n_sp), 1.0))
	if n_sp < 4:
		fails.append("spokes %d < 4 mínimo" % n_sp)
	if gap_deg < 75.0:
		fails.append("fairness: hueco %.0f° < 75° (no se lee como un passage)" % gap_deg)
	# y el hueco tiene que dejar RADIOS LETALES: si el hueco cubre todo,
	# el abanico no es un peligro.
	if gap_sp < 1 or gap_sp > n_sp - 2:
		fails.append("fairness: hueco de %d radios sobre %d deja hazards" % [gap_sp, n_sp])
	if int(fan.get("telegraph_beats", 0)) != 2 or int(fan.get("active_beats", 0)) != 9:
		fails.append("timing: telegraph=%s active=%s (esperaba 2/9)" % [str(fan.get("telegraph_beats")), str(fan.get("active_beats"))])
	if str(fan.get("state", "")) != "telegraph" or bool(fan.get("is_hazard", true)):
		fails.append("nace en telegraph inofensivo: state=%s is_hazard=%s" % [str(fan.get("state")), str(fan.get("is_hazard"))])
	var rev_beats: float = float(fan.get("beats_per_rev", 0.0))
	if rev_beats < 8.0:
		fails.append("fairness: rotación %.1f beats/giro < 8 (muy rápida)" % rev_beats)

	# ============ 2) CONTRATO MOTOR (Gameplay, sin escena) ============
	# El motor del abanico vive en Gameplay como métodos estáticos de spawn-dict
	# (el E2E headless no puede instanciar la escena): exponemos la física del
	# patrón en un script puro que Gameplay también usa — SpokeFanLogic.
	var logic_script: GDScript = load("res://scripts/SpokeFanLogic.gd")
	if logic_script == null:
		fails.append("RED: SpokeFanLogic.gd no existe")
		_finish(fails)
		return

	# --- 2a) Ciclo de estados en beats ---
	var f2: Dictionary = controller._spoke_fan(0.0, 0)
	var dt: float = 1.0 / 60.0
	var states_seen: Array[String] = []
	var guard: int = 0
	while guard < 2000:
		guard += 1
		f2 = logic_script.step(f2, dt, bl)
		if states_seen.is_empty() or states_seen[states_seen.size() - 1] != str(f2["state"]):
			states_seen.append(str(f2["state"]))
		if str(f2["state"]) == "done":
			break
	if states_seen != ["telegraph", "active", "fade", "done"]:
		fails.append("ciclo: %s (esperaba telegraph->active->fade->done)" % str(states_seen))
	# Transiciones caen EN beats: state_time cruza umbrales en múltiplos de bl.
	var f3: Dictionary = controller._spoke_fan(0.0, 0)
	var t_active: float = -1.0
	var t_fade: float = -1.0
	var elapsed: float = 0.0
	for i in range(600):
		f3 = logic_script.step(f3, dt, bl)
		elapsed += dt
		if t_active < 0.0 and str(f3["state"]) == "active":
			t_active = elapsed
		if t_fade < 0.0 and str(f3["state"]) == "fade":
			t_fade = elapsed
	# telegraph dura 2 beats => active arranca ~2*bl (tolerancia 1 frame)
	if absf(t_active - 2.0 * bl) > dt * 1.5:
		fails.append("active arranca a %.3fs, esperaba %.3fs" % [t_active, 2.0 * bl])
	if absf(t_fade - 11.0 * bl) > dt * 2.5:
		fails.append("fade arranca a %.3fs, esperaba ~%.3fs" % [t_fade, 11.0 * bl])

	# --- 2b) Colisión: el hueco es SEGURO aunque rote ---
	# El jugador VIAJA CON EL HUECO (lo persigue, como un humano): 90 frames
	# -> cero hits. Jugador sobre el CENTRO de un rayo sólido -> hit.
	var f4: Dictionary = controller._spoke_fan(0.0, 0)
	# forzar active ya
	for i in range(int(2.0 * bl / dt) + 2):
		f4 = logic_script.step(f4, dt, bl)
	if str(f4["state"]) != "active":
		fails.append("pre-active: estado %s" % str(f4["state"]))
		_finish(fails)
		return
	var hub: Vector2 = f4["pos"]
	var rad: float = float(f4["radius"]) * 0.6
	var hits_safe: int = 0
	for i in range(90):  # ~1.5s de active rotando
		f4 = logic_script.step(f4, dt, bl)
		# el jugador persigue el centro del hueco CADA FRAME:
		var g_now: float = logic_script.gap_start_angle(f4)
		var p_safe: Vector2 = hub + Vector2.from_angle(g_now) * rad
		if logic_script.hits_player(f4, p_safe):
			hits_safe += 1
	if hits_safe > 0:
		fails.append("fairness ROTA: jugador viajando en el hueco recibió %d hits" % hits_safe)
	# jugador SOBRE UN RAYO: centro exacto del rayo sólido 4 (hueco = rayos 0-1).
	var f5: Dictionary = controller._spoke_fan(0.0, 0)
	for i in range(int(2.0 * bl / dt) + 2):
		f5 = logic_script.step(f5, dt, bl)
	var rot5: float = logic_script.rotation_at(f5)
	var spoke4: float = rot5 + 4.0 * (TAU / 8.0)
	var p_hit: Vector2 = (f5["pos"] as Vector2) + Vector2.from_angle(spoke4) * rad
	if not logic_script.hits_player(f5, p_hit):
		fails.append("colisión: jugador sobre el rayo 4 NO recibe daño en active")

	# --- 2c) Sin daño fuera de active ---
	var f6: Dictionary = controller._spoke_fan(0.0, 0)
	var p_ray: Vector2 = hub + Vector2.from_angle(logic_script.gap_start_angle(f6) + PI) * rad
	var tele_hits: int = 0
	for i in range(int(1.9 * bl / dt)):
		f6 = logic_script.step(f6, dt, bl)
		if logic_script.hits_player(f6, p_ray):
			tele_hits += 1
	if tele_hits > 0:
		fails.append("telegraph daña (%d hits) — debe ser inofensivo" % tele_hits)

	_finish(fails)

func _finish(fails: Array[String]) -> void:
	if fails.is_empty():
		print("[SPOKE] PASS — builder + motor: ciclo on-beat, hueco seguro rotando, daño solo en active")
		quit(0)
	else:
		for f in fails:
			print("[SPOKE] FAIL: %s" % f)
		quit(1)
