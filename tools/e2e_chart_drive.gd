extends SceneTree
## E2E test (headless): single-level MVP. Drive PatternController with the
## procedural First Light chart (ProceduralSong.build_chart, same source as
## Gameplay) + a simulated playback clock; assert beats are consumed in order
## and hazard spawns are produced at beat-aligned times. Sin targets: TODO
## spawn de juego es peligro (los únicos no-hazard permitidos son los
## telegraphs de láser, que son avisos inofensivos).

func _init() -> void:
	var ok := _run_first_light()
	if ok:
		print("\n[E2E] SINGLE LEVEL PASS")
		quit(0)
	else:
		print("\n[E2E] FAILURES DETECTED")
		quit(1)


func _run_first_light() -> bool:
	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	if chart.beat_times.is_empty():
		print("[E2E] first_light: empty beats -> FAIL")
		return false

	var color := Color(0.2, 0.8, 1, 1)
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true
	var spawn_count := 0
	var hazard_count := 0
	var target_count := 0  # DEBE ser 0: los targets (azules) ya no existen
	var telegraph_count := 0

	# Simulate the playback clock sweeping from 0 to duration in small steps,
	# exactly like Gameplay._process does with music.get_playback_position().
	var next_beat_idx := 0
	var dt := 0.05
	var t_time := 0.0
	var max_beats := chart.beat_times.size()

	while t_time <= chart.duration and next_beat_idx < max_beats:
		# emit all beats whose time is <= simulated clock
		while next_beat_idx < max_beats and chart.beat_times[next_beat_idx] <= t_time:
			var spawns: Array[Dictionary] = controller.spawns_at(chart.beat_times[next_beat_idx], next_beat_idx, color)
			for s in spawns:
				spawn_count += 1
				if s.get("type", "") == "laser_telegraph":
					telegraph_count += 1
				elif s.get("is_hazard", false):
					hazard_count += 1
				else:
					target_count += 1
			next_beat_idx += 1
		t_time += dt

	var consumed_all := next_beat_idx == max_beats
	var produced_something := spawn_count > 0
	var no_targets := target_count == 0
	var ok := consumed_all and produced_something and no_targets

	print("[E2E] first_light: beats=%d consumed=%d spawns=%d (hazards=%d telegraphs=%d targets=%d) %s" % [
		max_beats, next_beat_idx, spawn_count, hazard_count, telegraph_count, target_count,
		"-> PASS" if ok else "-> FAIL"
	])
	return ok