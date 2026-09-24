extends SceneTree
## test_setpiece_director.gd — Tarea 1 del plan JSAB (headless): el
## SetpieceDirector agenda coreografías multi-beat. Contrato:
## - spawns_at_phrase en un phrase beat de sección con energía >= 0.5 agenda
##   el script (no spawnea nada ese beat) y setea _active_setpiece.
## - spawns_at en cada beat posterior emite las fases cuyo offset vence.
## - El setpiece se cierra solo tras la última fase + 2 beats.
## - Sección de baja energía (intro) NO agenda nada.
## - No doble-arranque si llega otro phrase con uno activo.
## - La emisión del beat ancla (fase 0) es un telegraph INOFENSIVO.

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true
	var color := Color(0.2, 0.8, 1, 1)

	# --- RED: el script/mapa del director aún no existe ---
	var active_probe: Variant = controller.get("_active_setpiece")
	if active_probe == null:
		fails.append("RED sanity: _active_setpiece no existe")

	# --- Beat 0 (intro, energía 0.35): NO agenda nada ---
	# (beat 0 es el ÚNICO phrase beat de la intro: bars 0-3)
	controller.wall_active = false
	controller.spawns_at(chart.beat_times[0], 0, color)
	var active_after_intro: Dictionary = controller.get("_active_setpiece") if controller.get("_active_setpiece") != null else {}
	if not active_after_intro.is_empty():
		fails.append("intro (energía<0.5) no debería agendar setpiece")

	# --- Beat 64 (bar 16, drop, energía 0.85): el DIRECTOR agenda vía
	# spawns_at y emite la fase 0 en el mismo beat. El DROP abre con el
	# abanico de rayos (drop_opener_v1, T2); el láser es del build.
	var sp_build: Array[Dictionary] = controller.spawns_at(chart.beat_times[64], 64, color)
	var active: Dictionary = controller.get("_active_setpiece") if controller.get("_active_setpiece") != null else {}
	if active.is_empty():
		fails.append("drop: phrase beat debería agendar setpiece")
	else:
		if str(active.get("script_key", "")) != "drop_opener_v1":
			fails.append("script elegido: %s, esperaba drop_opener_v1" % str(active.get("script_key", "")))
		if int(active.get("anchor_beat", -1)) != 64:
			fails.append("anchor_beat: %d, esperaba 64" % int(active.get("anchor_beat", -1)))
	if not sp_build.is_empty():
		var fan_in_build: int = 0
		for s in sp_build:
			if s.get("type", "") == "spoke_fan" and not bool(s.get("is_hazard", true)):
				fan_in_build += 1
		if fan_in_build == 0:
			fails.append("beat ancla: la fase 0 debe emitir el spoke_fan inofensivo en el mismo beat")

	# --- Beat 64 otra vez por spawns_at (el ancla): fase 0 = spoke_fan inofensivo ---
	controller.wall_active = false
	var at_anchor: Array[Dictionary] = controller.spawns_at(chart.beat_times[64], 64, color)
	var fans_at_anchor: int = 0
	for s in at_anchor:
		if s.get("type", "") == "spoke_fan" and not bool(s.get("is_hazard", true)):
			fans_at_anchor += 1
	if fans_at_anchor == 0:
		fails.append("beat ancla: esperaba >=1 spoke_fan inofensivo de la fase 0")

	# --- Beats +1/+2: sin fases (el script v1 solo tiene fase 0) ---
	for off in [1, 2]:
		controller.wall_active = false
		var at_off: Array[Dictionary] = controller.spawns_at(chart.beat_times[64 + off], 64 + off, color)
		var phase_spawns: int = 0
		for s in at_off:
			# el gate normal de easy_mode puede emitir encounters/acento: contamos
			# SOLO spawns marcados como fase de setpiece (clave setpiece_phase)
			if s.has("setpiece_phase"):
				phase_spawns += 1
		if phase_spawns != 0:
			fails.append("offset +%d: no debería emitir fases (hubo %d)" % [off, phase_spawns])

	# --- No re-agenda mientras vive: el setpiece de ancla 80 (drop_opener_v1,
	# fase única at=0) cierra a offset > 0+2 = beat 83. Mientras vive (81-82)
	# ningún pump lo re-ancla; a partir del cierre el anchor queda vacío (-1)
	# y un nuevo phrase beat puede agendar.
	controller.spawns_at(chart.beat_times[80], 80, color)   # phrase beat de drop: agenda
	for b in [81, 82]:
		controller.spawns_at(chart.beat_times[b], b, color)
		var a_mid: Dictionary = controller.get("_active_setpiece") if controller.get("_active_setpiece") != null else {}
		if not a_mid.is_empty() and int(a_mid.get("anchor_beat", -1)) != 80:
			fails.append("beat %d: no debe re-anclear (anchor=%d)" % [b, int(a_mid.get("anchor_beat", -1))])
			break

	# --- Cierre: offset > última fase + 2 => _active_setpiece se limpia ---
	var last_at: int = 0
	var script: Array = controller.get("SETPIECE_SCRIPTS").get("laser_sweep_v1", []) if controller.get("SETPIECE_SCRIPTS") != null else []
	for ph in script:
		last_at = maxi(last_at, int(ph.get("at", 0)))
	var clear_beat: int = 64 + last_at + 3
	controller.wall_active = false
	controller.spawns_at(chart.beat_times[clear_beat], clear_beat, color)
	var active_end: Dictionary = controller.get("_active_setpiece") if controller.get("_active_setpiece") != null else {}
	if not active_end.is_empty():
		fails.append("setpiece no se cerró tras offset > last_at+2 (beat %d)" % clear_beat)

	if fails.is_empty():
		print("[DIRECTOR] PASS — agenda, emite fases, no doble-arranca, se cierra solo")
		quit(0)
	else:
		for f in fails:
			print("[DIRECTOR] FAIL: %s" % f)
		quit(1)
