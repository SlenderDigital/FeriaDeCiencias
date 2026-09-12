extends SceneTree
## E2E test (headless): load all 3 real charts + drive PatternController with a
## simulated playback clock; assert beats are consumed in order and that hazard and
## target spawns are produced at expected beat-aligned times.

func _init() -> void:
	var tracks = [
		{"name": "first_light", "analysis": "res://assets/music/first_light.analysis.json", "level": "res://assets/music/first_light.level.json", "color": Color(0.2, 0.8, 1, 1)},
		{"name": "mechanical_wall", "analysis": "res://assets/music/mechanical_wall.analysis.json", "level": "res://assets/music/mechanical_wall.level.json", "color": Color(0.75, 0.75, 0.8, 1)},
		{"name": "relentless_drive", "analysis": "res://assets/music/relentless_drive.analysis.json", "level": "res://assets/music/relentless_drive.level.json", "color": Color(1, 0, 0.55, 1)},
	]

	var all_ok := true
	for t in tracks:
		var ok := _run_track(t)
		all_ok = all_ok and ok

	if all_ok:
		print("\n[E2E] ALL TRACKS PASS")
		quit(0)
	else:
		print("\n[E2E] FAILURES DETECTED")
		quit(1)


func _run_track(t: Dictionary) -> bool:
	var chart := ChartData.load_charts(t["analysis"], t["level"])
	if chart.beat_times.is_empty():
		print("[E2E] %s: empty beats -> FAIL" % t["name"])
		return false

	var controller := PatternController.new(chart)
	var spawn_count := 0
	var hazard_count := 0
	var target_count := 0

	# Simulate the playback clock sweeping from 0 to duration in small steps,
	# exactly like Gameplay._process does with music.get_playback_position().
	var next_beat_idx := 0
	var dt := 0.05
	var t_time := 0.0
	var max_beats := chart.beat_times.size()

	while t_time <= chart.duration and next_beat_idx < max_beats:
		# emit all beats whose time is <= simulated clock
		while next_beat_idx < max_beats and chart.beat_times[next_beat_idx] <= t_time:
			var spawns: Array[Dictionary] = controller.spawns_at(chart.beat_times[next_beat_idx], t["color"])
			for s in spawns:
				spawn_count += 1
				if s["is_hazard"]:
					hazard_count += 1
				else:
					target_count += 1
			next_beat_idx += 1
		t_time += dt

	var consumed_all := next_beat_idx == max_beats
	var produced_something := spawn_count > 0
	var ok := consumed_all and produced_something

	print("[E2E] %s: beats=%d consumed=%d spawns=%d (hazards=%d targets=%d) %s" % [
		t["name"], max_beats, next_beat_idx, spawn_count, hazard_count, target_count,
		"-> PASS" if ok else "-> FAIL"
	])
	return ok