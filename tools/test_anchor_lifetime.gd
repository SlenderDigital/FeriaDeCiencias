extends SceneTree
## test_anchor_lifetime.gd — T10: la VIDA de un ancla es una decisión de
## justicia, no un número arbitrario.
##
## Bug real encontrado en la corrida instrumentada: al subir la vida de las
## anclas de 4 a 9 beats para que la pantalla no estuviera vacía, el laser_sweep
## golpeó 4 veces seguidas (10.7, 14.4, 18.2, 21.9s) y luego el spoke_fan 3
## veces (68.5, 73.3, 78.3). Un patrón que barre TODO el radio no se puede
## esquivar dos veces: la pantalla se llena de UN golpe legible, no de varios
## imposibles.
##
## Regla que este test fija:
##   - las anclas de BARRIDO (sweep, fan) duran <= 5 beats: es una pasada.
##   - las anclas de CIERRE (waveform, corridor) pueden durar más, porque
##     ocupan un borde fijo y su grosor crece de forma monotónica: se leen
##     de una vez y el jugador sólo tiene que juntar de un lado.
## Y en cualquier caso: la ventana activa tiene que ser <= la cadencia de
## anclas (cada 8 beats), o se encadenan dos antes de que termine la primera.

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var bl: float = song.beat_interval
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true

	# 1) Las anclas de BARRIDO no pueden durar más de 5 beats.
	const MAX_SWEEP_ACTIVE: int = 5
	for key in ["spoke_fan", "laser_sweep"]:
		var sp: Array[Dictionary] = controller._build_pattern(key, chart.beat_times[64], Color.WHITE, 64, {}, 64 * 131)
		if sp.is_empty():
			fails.append("%s: no se pudo construir" % key)
			continue
		var ab: int = int(sp[0].get("active_beats", 0))
		if ab > MAX_SWEEP_ACTIVE:
			fails.append("%s: active %d beats > %d — barre el radio entero y no se puede esquivar dos veces (pasó en la corrida real: 3-4 golpes seguidos del mismo patrón)" % [key, ab, MAX_SWEEP_ACTIVE])
		if ab < 2:
			fails.append("%s: active %d beats — demasiado rápido para leerlo" % [key, ab])

	# 2) Las anclas de CIERRE pueden durar más, pero no encadenarse: su
	#    ventana tiene que caber en la cadencia de anclas (8 beats).
	const ANCHOR_CADENCE: int = 8
	for key2 in ["waveform_wall", "squeeze_corridor", "pulse_rings"]:
		var sp2: Array[Dictionary] = controller._build_pattern(key2, chart.beat_times[64], Color.WHITE, 64, {}, 64 * 131)
		if sp2.is_empty():
			fails.append("%s: no se pudo construir" % key2)
			continue
		var ab2: int = int(sp2[0].get("active_beats", 0))
		var tele2: int = int(sp2[0].get("telegraph_beats", 0))
		var total2: int = ab2 + tele2
		if total2 > ANCHOR_CADENCE:
			fails.append("%s: telegraph+active = %d beats > cadencia %d — la siguiente ancla arranca antes de que termine esta" % [key2, total2, ANCHOR_CADENCE])

	# 3) La cadencia real del director: tiene que agendar más seguido que la
	#    vida del ancla más larga, o la pantalla vuelve a quedar muda entre
	#    anclas (que es el problema original).
	var counts: Dictionary = {}
	var anchors: int = 0
	for b in range(0, chart.beat_times.size()):
		controller.wall_active = false
		for s in controller.spawns_at(chart.beat_times[b], b, Color.WHITE):
			if bool(s.get("setpiece_phase", false)):
				anchors += 1
				counts[b] = true
	# en las secciones de alta energía (build/drop/drop2) no puede haber más de
	# 8 beats consecutivos sin ancla
	var last_anchor: int = -99
	var worst_gap: int = 0
	for b2 in range(16, 200):
		if counts.has(b2):
			last_anchor = b2
		else:
			worst_gap = maxi(worst_gap, b2 - last_anchor)
	if worst_gap > ANCHOR_CADENCE:
		fails.append("hueco máximo sin ancla: %d beats (límite %d) — la pantalla se queda muda" % [worst_gap, ANCHOR_CADENCE])

	_finish(fails)

func _finish(fails: Array[String]) -> void:
	if fails.is_empty():
		print("[LIFE] PASS — barridos <=5 beats (una pasada), cierres caben en la cadencia, sin huecos mudos")
		quit(0)
	else:
		for f in fails:
			print("[LIFE] FAIL: %s" % f)
		quit(1)
