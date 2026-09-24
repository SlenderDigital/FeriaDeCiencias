extends SceneTree
## test_laser_beat.gd — Tarea 2 (headless): el láser dispara SOBRE un beat de
## la canción. El telegraph dura 3 beats (derivado del BPM real), y los
## telegraphs nacen en beats del chart (frases), así que fire_time = beat del
## spawn + 3 beats debe caer exactamente en la grilla de beats del chart.

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true
	var beat_len: float = chart.beat_times[1] - chart.beat_times[0]

	# Recorrer TODOS los beats del chart y recolectar cada telegraph spawn.
	# Reproducir el gate de wall_active igual que el E2E (los muros silencian
	# los spawns regulares) para ejercitar el camino real de emisión.
	var telegraph_count: int = 0
	var next_beat_idx: int = 0
	var t_time: float = 0.0
	var dt: float = 0.05
	var max_beats := chart.beat_times.size()
	var wall_until_beat: int = -1
	var fire_times: Array[float] = []

	while t_time <= chart.duration and next_beat_idx < max_beats:
		while next_beat_idx < max_beats and chart.beat_times[next_beat_idx] <= t_time:
			controller.wall_active = next_beat_idx < wall_until_beat
			var had_wall: bool = controller.wall_active
			var spawns: Array[Dictionary] = []
			spawns.append_array(controller.spawns_at(chart.beat_times[next_beat_idx], next_beat_idx, Color.WHITE))
			if chart.downbeat[next_beat_idx] and not had_wall:
				spawns.append_array(controller.spawns_at_downbeat(chart.beat_times[next_beat_idx], next_beat_idx, Color.WHITE))
			if next_beat_idx % 4 == 0:
				spawns.append_array(controller.spawns_at_bar(chart.beat_times[next_beat_idx], next_beat_idx, Color.WHITE))
			if next_beat_idx % 16 == 0:
				spawns.append_array(controller.spawns_at_phrase(chart.beat_times[next_beat_idx], next_beat_idx, Color.WHITE))
			for s in spawns:
				if s.get("type", "") == "laser_telegraph":
					telegraph_count += 1
					# fire_time = momento del spawn + duración del telegraph
					fire_times.append(chart.beat_times[next_beat_idx] + float(s["telegraph_time"]))
				elif s.get("type", "") == "stripe_wall":
					controller.wall_active = true
					wall_until_beat = next_beat_idx + 5
			next_beat_idx += 1
		t_time += dt

	if telegraph_count == 0:
		fails.append("no se generó ningún telegraph — el E2E esperaría >0")
	# Cotejar cada fire_time contra la grilla de beats del chart: debe caer a
	# <= 1 frame (dt) de un beat. fire_time = beat_k + 3*beat_len → es el beat
	# k+3 de la grilla (la grilla es uniforme: t = i*beat_len desde 0).
	for ft in fire_times:
		var grid_pos: float = fposmod(ft, beat_len)
		var off: float = minf(grid_pos, beat_len - grid_pos)
		if off > dt:
			fails.append("fire_time %.4fs no está en la grilla (off=%.4fs > frame)" % [ft, off])

	if fails.is_empty():
		print("[LASER-BEAT] PASS — %d telegraphs, todos disparan sobre un beat del chart" % telegraph_count)
		quit(0)
	else:
		for f in fails:
			print("[LASER-BEAT] FAIL: %s" % f)
		quit(1)
