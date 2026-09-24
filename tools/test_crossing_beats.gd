extends SceneTree
## test_crossing_beats.gd — Tarea 4 (headless): los peligros caen y llegan a
## la zona del jugador en un número ENTERO de beats. La velocidad vertical
## se deriva del BPM real y del alto real de pantalla (helpers _crossing_beats
## y _quantized_vy), así que la llegada cae sobre un golpe audible.

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true
	var bl: float = chart.beat_times[1] - chart.beat_times[0]
	var screen_h: float = 720.0
	var player_zone_y: float = screen_h * 0.78

	# Helper puro en tiempos representativos de cada sección:
	# intro t=1s (energy 0.35 -> 8 beats), build t=15s (0.6 -> 6),
	# drop t=30s (0.85 -> 6), breakdown t=70s (0.5 -> 6), drop2 t=80s (0.9 -> 6),
	# outro t=100s (0.3 -> 8).
	var expect := [[1.0, 8], [15.0, 6], [30.0, 6], [70.0, 6], [80.0, 6], [100.0, 8]]
	for e in expect:
		var n: int = controller._crossing_beats(e[0])
		if n != e[1]:
			fails.append("_crossing_beats(%.0fs)=%d, esperaba %d" % [e[0], n, e[1]])
	# La velocidad cuantizada debe llegar EXACTO: travel = vy * n * bl.
	for e in expect:
		var n2: int = controller._crossing_beats(e[0])
		var vy: float = controller._quantized_vy_from(e[0], -50.0)
		var travel: float = vy * float(n2) * bl
		var target: float = player_zone_y + 50.0
		if absf(travel - target) > 0.5:
			fails.append("vy@%.0fs: recorre %.1fpx en %d beats, esperaba %.1fpx" % [e[0], travel, n2, target])

	# Spawns reales: cada saw/lane_saw/drifter emitido debe tener vy tal que
	# la llegada a la zona del jugador (desde su y de spawn) cae en un beat.
	# Recorrer beats del chart vía spawns_at (sin muros, igual que cadence).
	var next_beat_idx := 0
	var t_time := 0.0
	var dt := 0.05
	var max_beats := chart.beat_times.size()
	var checked: int = 0
	while next_beat_idx < max_beats and t_time <= chart.duration:
		while next_beat_idx < max_beats and chart.beat_times[next_beat_idx] <= t_time:
			controller.wall_active = false
			var s: Array[Dictionary] = controller.spawns_at(chart.beat_times[next_beat_idx], next_beat_idx, Color.WHITE)
			for one in s:
				var ty: String = str(one.get("type", ""))
				if ty != "saw" and ty != "drifter":
					continue
				var spawn_y: float = (one["pos"] as Vector2).y
				var vy2: float = (one["vel"] as Vector2).y
				if vy2 <= 0.0:
					continue  # lane_saw puede traer vy mixta; solo caídas
				var dist: float = player_zone_y - spawn_y
				var n_float: float = dist / (vy2 * bl)
				var n_int: int = int(round(n_float))
				if absf(n_float - float(n_int)) > 0.02:
					fails.append("beat %d (%s): llegada %.3f beats (no entera)" % [next_beat_idx, ty, n_float])
				checked += 1
			next_beat_idx += 1
		t_time += dt
	if checked < 10:
		fails.append("muy pocos spawns verificados (%d)" % checked)

	if fails.is_empty():
		print("[CROSS] PASS — %d caídas on-beat; helper exacto en 6 secciones" % checked)
		quit(0)
	else:
		for f in fails:
			print("[CROSS] FAIL: %s" % f)
		quit(1)
