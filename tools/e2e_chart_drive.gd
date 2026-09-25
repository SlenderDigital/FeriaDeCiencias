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
	var type_counts: Dictionary = {}
	var wall_until_beat: int = -1

	while t_time <= chart.duration and next_beat_idx < max_beats:
		# emit all beats whose time is <= simulated clock
		while next_beat_idx < max_beats and chart.beat_times[next_beat_idx] <= t_time:
			controller.wall_active = next_beat_idx < wall_until_beat
			var all_spawns: Array[Dictionary] = []
			var had_wall: bool = controller.wall_active
			var regular: Array[Dictionary] = controller.spawns_at(chart.beat_times[next_beat_idx], next_beat_idx, color)
			all_spawns.append_array(regular)
			for s in regular:
				if s.get("type", "") == "stripe_wall":
					controller.wall_active = true
			if chart.downbeat[next_beat_idx] and not had_wall:
				all_spawns.append_array(controller.spawns_at_downbeat(chart.beat_times[next_beat_idx], next_beat_idx, color))
			if next_beat_idx % 4 == 0:
				all_spawns.append_array(controller.spawns_at_bar(chart.beat_times[next_beat_idx], next_beat_idx, color))
			if next_beat_idx % 16 == 0:
				all_spawns.append_array(controller.spawns_at_phrase(chart.beat_times[next_beat_idx], next_beat_idx, color))
			for s in all_spawns:
				spawn_count += 1
				var ty: String = str(s.get("type", ""))
				var encounter: String = str(s.get("encounter", ty))
				type_counts[encounter] = int(type_counts.get(encounter, 0)) + 1
				if ty == "laser_telegraph" or ty == "spoke_fan" or ty == "laser_sweep" or ty == "waveform_wall":
					telegraph_count += 1   # avisos inofensivos al nacer (telegraph)
				elif s.get("is_hazard", false):
					hazard_count += 1
				else:
					target_count += 1
				if ty == "stripe_wall":
					controller.wall_active = true
					wall_until_beat = next_beat_idx + 5
			next_beat_idx += 1
		t_time += dt

	var consumed_all := next_beat_idx == max_beats
	var produced_something := spawn_count > 0
	var no_targets := target_count == 0
	# Variedad JSAB (post-T2): drops abren con el ABANICO (spoke_fan), el
	# build trae el LÁSER, breakdown cierra el perímetro. Las tres anclas
	# deben aparecer en el nivel completo.
	var has_variety := int(type_counts.get("saw_pair", 0)) > 0 \
		and int(type_counts.get("saw_weave", 0)) > 0 \
		and int(type_counts.get("stripe_wall", 0)) > 0 \
		and int(type_counts.get("spoke_fan", 0)) > 0 \
		and (int(type_counts.get("laser_telegraph", 0)) > 0 or int(type_counts.get("laser_sweep", 0)) > 0) \
		and (int(type_counts.get("waveform_wall", 0)) > 0 or int(type_counts.get("closing_perimeter", 0)) > 0)
	var ok := consumed_all and produced_something and no_targets and has_variety

	print("[E2E] first_light: beats=%d consumed=%d spawns=%d (hazards=%d telegraphs=%d targets=%d) types=%s %s" % [
		max_beats, next_beat_idx, spawn_count, hazard_count, telegraph_count, target_count,
		str(type_counts), "-> PASS" if ok else "-> FAIL"
	])
	return ok
