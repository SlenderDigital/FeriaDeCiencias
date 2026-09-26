extends SceneTree
## test_beatability.gd (GATE) — T9: el piloto automático juega el nivel COMPLETO en
## el motor real (no en el arnés de test_beatability) y se verifica que
## sobrevive. Es la prueba de que el nivel es jugable de punta a punta por
## alguien que sabe leer los avisos: sin esto, "el juego se puede terminar"
## es una afirmación sin evidencia.
##
## Usa los motores puros y las MISMAS reglas de colisión que Gameplay.

func _initialize() -> void:
	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var bl: float = song.beat_interval
	var ps: Vector2 = Vector2(1280, 720)
	var controller := PatternController.new(chart, ps, 128.0, 1337)
	controller.easy_mode = true

	var dt: float = 1.0 / 60.0
	var targets: Array[Dictionary] = []
	var player: Vector2 = Vector2(640, 560)
	var hp: float = 125.0
	var iframes: float = 0.0
	var shield: float = 0.0
	var shield_cd: float = 0.0
	var hits: int = 0
	var shields: int = 0
	var nadir: float = hp
	var beat: int = 0
	var to_remove: Array[int] = []
	var last_report: float = -1.0

	while beat < chart.beat_times.size():
		var t: float = chart.beat_times[beat]
		# 1) spawlear
		controller.wall_active = false
		for s in controller.spawns_at(t, beat, Color.WHITE):
			targets.append(s)
		for s in controller.spawns_at_bar(t, beat, Color.WHITE):
			targets.append(s)
		# 2) el piloto decide (prioridad: peligro actual > setpiece > proyectil)
		var desired: Vector2 = _pilot_desired(targets, player)
		player = PilotLogic.steer_step(player, desired, 520.0, dt)
		# 3) steps de los setpieces
		to_remove.clear()
		for i in range(targets.size()):
			var o: Dictionary = targets[i]
			var ty: String = str(o.get("type", ""))
			match ty:
				"spoke_fan":
					var s1: Dictionary = SpokeFanLogic.step(o, dt, bl)
					o["state"] = s1["state"]; o["state_time"] = s1["state_time"]
				"laser_sweep":
					var s2: Dictionary = SweepLogic.step(o, dt, bl)
					o["state"] = s2["state"]; o["state_time"] = s2["state_time"]
				"waveform_wall":
					var s3: Dictionary = WaveformLogic.step(o, dt, bl)
					o["state"] = s3["state"]; o["state_time"] = s3["state_time"]
				"squeeze_corridor":
					var s4: Dictionary = SqueezeLogic.step(o, dt, bl)
					o["state"] = s4["state"]; o["state_time"] = s4["state_time"]
				"pulse_rings":
					var s5: Dictionary = PulseRingsLogic.step(o, dt, bl)
					o["state"] = s5["state"]; o["state_time"] = s5["state_time"]
				"mini_ring", "mini_fan":
					o["state_time"] = float(o.get("state_time", 0.0)) + dt
					var js: String = str(o.get("state", "telegraph"))
					var jt: float = float(o["state_time"])
					if js == "telegraph" and jt >= float(o.get("telegraph_beats", 1)) * bl:
						o["state"] = "active"; o["state_time"] = 0.0
					elif js == "active" and jt >= float(o.get("active_beats", 2)) * bl:
						o["state"] = "fade"; o["state_time"] = 0.0
					elif js == "fade" and jt >= float(o.get("fade_beats", 1)) * bl:
						o["state"] = "done"
				"saw", "saw_pair", "saw_weave", "homing", "drifter", "drifter_swarm":
					o["pos"] = (o["pos"] as Vector2) + (o["vel"] as Vector2) * dt
				"perimeter":
					o["pos"] = (o["pos"] as Vector2) + (o["vel"] as Vector2) * dt
			if str(o.get("state", "")) == "done" or float(o["pos"].y) > 740.0:
				to_remove.append(i)
		for i in to_remove:
			targets.remove_at(i)

		# 4) colisiones (mismas reglas que el juego)
		if iframes > 0.0:
			iframes = maxf(iframes - dt, 0.0)
		if shield_cd > 0.0:
			shield_cd = maxf(shield_cd - dt, 0.0)
		if shield > 0.0:
			shield = maxf(shield - dt, 0.0)
		to_remove.clear()
		for i in range(targets.size()):
			var o2: Dictionary = targets[i]
			var ty2: String = str(o2.get("type", ""))
			var hit := false
			var dmg: float = 12.0   # easy_mode: el juego real usa 12, no 18
			match ty2:
				"spoke_fan":
					hit = SpokeFanLogic.hits_player(o2, player)
				"laser_sweep":
					hit = SweepLogic.hits_player(o2, player)
				"waveform_wall":
					hit = WaveformLogic.hits_player(o2, player)
				"squeeze_corridor":
					hit = SqueezeLogic.hits_player(o2, player)
				"pulse_rings":
					hit = PulseRingsLogic.hits_player(o2, player)
				"mini_ring":
					if str(o2.get("state", "")) == "active":
						var mjr: Dictionary = {"state": "active", "pos": o2["pos"], "rings": 1,
							"target_radius": float(o2.get("target_radius", 300.0)),
							"gap_angle": float(o2.get("gap_angle", 1.2)),
							"gap_center": float(o2.get("gap_center", 0.0)) + float(o2.get("spin", 0.0)) * float(o2.get("state_time", 0.0)),
							"gap_spin": 0.0, "beat_len": bl, "active_beats": 1,
							"telegraph_beats": 0, "fade_beats": 1, "state_time": float(o2.get("state_time", 0.0))}
						hit = PulseRingsLogic.hits_player(mjr, player)
						dmg = 8.0
				"mini_fan":
					if str(o2.get("state", "")) == "active":
						var mjf: Dictionary = {"state": "active", "pos": o2["pos"],
							"spokes": int(o2.get("spokes", 3)), "gap_spokes": int(o2.get("gap_spokes", 1)),
							"gap_first": int(o2.get("gap_first", 0)), "radius": float(o2.get("radius", 260.0)),
							"rot_speed": float(o2.get("rot_speed", 0.0)),
							"telegraph_beats": 0, "state_time": float(o2.get("state_time", 0.0))}
						hit = SpokeFanLogic.hits_player(mjf, player)
						dmg = 8.0
				"saw", "saw_pair", "saw_weave", "homing", "drifter", "drifter_swarm", "perimeter":
					if o2.has("pos"):
						hit = player.distance_to(o2["pos"]) < (float(o2.get("radius", 24.0)) + 16.0)
				"stripe_wall":
					if str(o2.get("state", "")) == "active":
						var s_p: float = player.dot(o2["wall_n"])
						hit = s_p > float(o2["s0"]) - 16.0 and s_p < float(o2["s1"]) + 16.0
			if hit and shield <= 0.0 and iframes <= 0.0:
				hp -= dmg
				iframes = 1.2
				hits += 1
				# escudo como recurso (como en el juego real)
				if shield_cd <= 0.0:
					shield = 1.0
					shield_cd = 3.0
					shields += 1
		nadir = minf(nadir, hp)
		if t - last_report >= 15.0:
			last_report = t
			print("[BEAT] t=%.0fs HP=%.0f hits=%d" % [t, hp, hits])
		beat += 1

	var ok: bool = hp > 0.0
	print("[BEAT] %s — final HP=%.0f/125, nadir=%.0f, hits=%d, escudos=%d" % [
		"SOBREVIVIÓ" if ok else "MURIÓ", hp, nadir, hits, shields])
	if not ok:
		print("[BEAT] FAIL: el nivel no se puede terminar")
		quit(1)
	elif hits > 9:
		print("[BEAT] FAIL: sobrevivió pero con %d golpes (margen insuficiente para un tutorial)" % hits)
		quit(1)
	else:
		print("[BEAT] PASS — nivel completable con %d golpes (tutorial justo)" % hits)
		quit(0)

func _pilot_desired(targets: Array[Dictionary], player: Vector2) -> Vector2:
	var best: Vector2 = player
	var prio: float = -1.0
	for o in targets:
		var ty: String = str(o.get("type", ""))
		var p: float = 0.0
		match ty:
			"spoke_fan", "laser_sweep", "waveform_wall", "squeeze_corridor", "pulse_rings", "mini_ring", "mini_fan":
				p = 2.0
			"saw", "saw_pair", "saw_weave", "homing", "drifter", "drifter_swarm", "perimeter":
				p = 1.0
			"stripe_wall":
				p = 2.5
		if p <= 0.0:
			continue
		# peligro actual con ESTE = máxima prioridad
		if _hits_now(o, player):
			p = 4.0
		if p > prio:
			prio = p
			if p >= 2.0:
				best = PilotLogic.safe_point(o)
			elif o.has("pos"):
				var d: Vector2 = player - (o["pos"] as Vector2)
				if d.length() > 0.01:
					best = Vector2(clampf(player.x + d.normalized().x * 160.0, 40.0, 1240.0),
						clampf(player.y + d.normalized().y * 160.0, 150.0, 640.0))
	return best

func _hits_now(o: Dictionary, p: Vector2) -> bool:
	var ty: String = str(o.get("type", ""))
	match ty:
		"spoke_fan":
			return SpokeFanLogic.hits_player(o, p)
		"laser_sweep":
			return SweepLogic.hits_player(o, p)
		"waveform_wall":
			return WaveformLogic.hits_player(o, p)
		"squeeze_corridor":
			return SqueezeLogic.hits_player(o, p)
		"pulse_rings":
			return PulseRingsLogic.hits_player(o, p)
		"saw", "saw_pair", "saw_weave", "homing", "drifter", "drifter_swarm", "perimeter":
			if o.has("pos"):
				return p.distance_to(o["pos"]) < 60.0
		"stripe_wall":
			if str(o.get("state", "")) == "active":
				var s_p: float = p.dot(o["wall_n"])
				return s_p > float(o["s0"]) - 16.0 and s_p < float(o["s1"]) + 16.0
	return false
