extends SceneTree
## dbg_states.gd — ¿por qué hay golpes que no dañan y patrones que no
## activan? Volca los ESTADOS REALES que ve el motor durante una pasada.
func _initialize() -> void:
	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var bl: float = song.beat_interval
	var c := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	c.easy_mode = true
	var targets: Array[Dictionary] = []
	var player: Vector2 = Vector2(640, 560)
	var dt: float = 1.0 / 60.0
	var seen_states: Dictionary = {}
	var spawn_log: Array[String] = []
	for beat in range(chart.beat_times.size()):
		var t: float = chart.beat_times[beat]
		c.wall_active = false
		for s in c.spawns_at(t, beat, Color.WHITE):
			targets.append(s)
			spawn_log.append("b%d %s" % [beat, str(s.get("type", "?"))])
		if beat % 4 == 0:
			for s in c.spawns_at_bar(t, beat, Color.WHITE):
				targets.append(s)
				spawn_log.append("b%d %s(jab)" % [beat, str(s.get("type", "?"))])
		var to_rem: Array[int] = []
		for i in range(targets.size()):
			var o: Dictionary = targets[i]
			var ty: String = str(o.get("type", ""))
			var before: String = str(o.get("state", "?"))
			match ty:
				"spoke_fan":
					var s1: Dictionary = SpokeFanLogic.step(o, dt, bl); o["state"] = s1["state"]; o["state_time"] = s1["state_time"]
				"laser_sweep":
					var s2: Dictionary = SweepLogic.step(o, dt, bl); o["state"] = s2["state"]; o["state_time"] = s2["state_time"]
				"waveform_wall":
					var s3: Dictionary = WaveformLogic.step(o, dt, bl); o["state"] = s3["state"]; o["state_time"] = s3["state_time"]
				"squeeze_corridor":
					var s4: Dictionary = SqueezeLogic.step(o, dt, bl); o["state"] = s4["state"]; o["state_time"] = s4["state_time"]
				"pulse_rings":
					var s5: Dictionary = PulseRingsLogic.step(o, dt, bl); o["state"] = s5["state"]; o["state_time"] = s5["state_time"]
			var after: String = str(o.get("state", "?"))
			if after != before:
				var key: String = "%s:%s->%s" % [ty, before, after]
				if not seen_states.has(key):
					seen_states[key] = [0, float(o.get("state_time", 0.0))]
				seen_states[key][0] = int(seen_states[key][0]) + 1
			if str(o.get("state", "")) == "done":
				to_rem.append(i)
		for i in to_rem:
			targets.remove_at(i)
		# 240 steps por beat = 4s por beat es demasiado; 60fps -> 0.0167*60=1s
	print("=== TRANSICIONES DE ESTADO ===")
	for k in seen_states.keys():
		print("  %s  x%d" % [k, int(seen_states[k][0])])
	print("=== SPAWNS (primeros 30) ===")
	for i in range(mini(30, spawn_log.size())):
		print("  ", spawn_log[i])
	quit(0)
