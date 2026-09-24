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

	# Helper puro en tiempos representativos de cada sección (bar_len=1.875s:
	# build 4-12 = 7.5-22.5s, drop 12-28 = 22.5-52.5s, breakdown 28-36 =
	# 52.5-67.5s, drop2 36-52 = 67.5-97.5s, outro 52-56 = 97.5-105s):
	# intro 1s -> 8 beats, build 15s -> 6, drop 30s -> 6, breakdown 55s -> 6,
	# drop2 80s -> 5.5 (+8.5% clímax, grilla audible de corcheas), outro 100s -> 8.
	var expect := [[1.0, 8.0], [15.0, 6.0], [30.0, 6.0], [55.0, 6.0], [80.0, 5.5], [100.0, 8.0]]
	for e in expect:
		var n: float = controller._crossing_beats(e[0])
		if n != e[1]:
			fails.append("_crossing_beats(%.0fs)=%.1f, esperaba %.1f" % [e[0], n, e[1]])
	# La velocidad cuantizada debe llegar EXACTO: travel = vy * n * bl.
	for e in expect:
		var n2: float = controller._crossing_beats(e[0])
		var vy: float = controller._quantized_vy_from(e[0], -50.0)
		var travel: float = vy * n2 * bl
		var target: float = player_zone_y + 50.0
		if absf(travel - target) > 0.5:
			fails.append("vy@%.0fs: recorre %.1fpx en %.1f beats, esperaba %.1fpx" % [e[0], travel, n2, target])

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
				# Grilla audible: beat entero, o medio beat (drop2 aprieta al
				# contratiempo de corchea). Tolerancia 2%.
				var frac: float = n_float - floor(n_float)
				var snap: float = minf(frac, 1.0 - frac)  # distancia al entero
				var snap_half: float = absf(frac - 0.5)    # distancia al medio
				if snap > 0.02 and snap_half > 0.02:
					fails.append("beat %d (%s): llegada %.3f beats (no en grilla entera/media)" % [next_beat_idx, ty, n_float])
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
