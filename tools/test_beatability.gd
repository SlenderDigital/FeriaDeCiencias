extends SceneTree
## test_beatability.gd — gate R4 del plan JSAB: un bot competente CON escudo
## (1.2s invuln / 3s cooldown, como el juego real) debe sobrevivir el nivel
## completo con TODOS los patrones vivos (incluido spoke_fan desde T2).
## El bot: repulsión de peligros, atracción al hueco del muro, VIAJA CON el
## hueco del abanico, escudo si no puede escapar. Métrica: HP nadir.

func _initialize() -> void:
	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var bl: float = song.beat_interval
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true
	var W := 1280.0
	var H := 720.0
	var player := Vector2(W * 0.5, H * 0.78)
	var hp := 125.0
	var hp_nadir := hp
	var iframes := 0.0
	var shield := 0.0
	var cooldown := 0.0
	var next_beat := 0
	var dt := 1.0 / 60.0
	var t := 0.0
	var targets: Array[Dictionary] = []
	var wall_until_beat := -1
	var hits: int = 0
	var shields_used: int = 0
	var fans_seen: int = 0
	var total_beats := chart.beat_times.size()
	while t <= chart.duration and next_beat < total_beats:
		while next_beat < total_beats and chart.beat_times[next_beat] <= t:
			controller.wall_active = next_beat < wall_until_beat
			var had_wall := controller.wall_active
			var sp: Array[Dictionary] = []
			sp.append_array(controller.spawns_at(chart.beat_times[next_beat], next_beat, Color.WHITE))
			if chart.downbeat[next_beat] and not had_wall:
				sp.append_array(controller.spawns_at_downbeat(chart.beat_times[next_beat], next_beat, Color.WHITE))
			if next_beat % 4 == 0:
				sp.append_array(controller.spawns_at_bar(chart.beat_times[next_beat], next_beat, Color.WHITE))
			if next_beat % 16 == 0:
				sp.append_array(controller.spawns_at_phrase(chart.beat_times[next_beat], next_beat, Color.WHITE))
			for s in sp:
				targets.append(s)
				if s.get("type", "") == "spoke_fan":
					fans_seen += 1
				if s.get("type", "") == "stripe_wall":
					controller.wall_active = true
					wall_until_beat = next_beat + 5
			next_beat += 1
		if shield > 0.0:
			shield -= dt
		if cooldown > 0.0:
			cooldown -= dt
		# --- bot: steering ---
		var steer := Vector2.ZERO
		var wall_live := false
		var gap_x := player.x
		var fan_live := false
		var fan_target := player
		var fan_hub := player
		var fan_ref: Dictionary = {}
		var danger_close := false
		for tg in targets:
			var ty: String = tg.get("type", "target")
			if ty == "spoke_fan":
				# Se reacciona desde el TELEGRAPH (un humano lee el aviso
				# granate y se pre-posiciona en el hueco ANTES del active).
				if str(tg.get("state", "")) == "active" or str(tg.get("state", "")) == "telegraph":
					fan_live = true
					fan_ref = tg
					fan_hub = tg["pos"]
					# viaja con el hueco: punto medio del arco seguro
					var g_mid: float = SpokeFanLogic.gap_start_angle(tg)
					fan_target = fan_hub + Vector2.from_angle(g_mid) * (float(tg["radius"]) * 0.6)
					if str(tg.get("state", "")) == "active" and SpokeFanLogic.hits_player(tg, player):
						danger_close = true
			elif ty == "stripe_wall" and tg.get("state", "fade") != "fade":
				wall_live = true
				gap_x = tg["gap_center"]
				if tg.get("state", "active") == "active":
					var sp3: float = player.dot(tg["wall_n"])
					if sp3 > tg["s0"] - 60.0 and sp3 < tg["s1"] + 60.0:
						danger_close = true
			elif ty == "saw" or ty == "homing" or ty == "drifter":
				var d: Vector2 = player - (tg["pos"] as Vector2)
				var dist: float = d.length()
				if dist < 170.0 and dist > 0.01:
					steer += d.normalized() * (170.0 - dist) / 170.0
					if dist < 60.0:
						danger_close = true
			elif ty == "laser_beam":
				var bdir := (tg["beam_dir"] as Vector2).normalized()
				var perp := absf((player - (tg["pos"] as Vector2)).dot(Vector2(-bdir.y, bdir.x)))
				if perp < 90.0:
					var away := (player - (tg["pos"] as Vector2)).slide(bdir)
					if away.length() > 0.01:
						steer += away.normalized() * 0.8
				if perp < 35.0:
					danger_close = true
		if fan_live:
			# Estrategia de hueco HONESTA: si el jugador está DENTRO del radio
			# del abanico, perseguir el punto del arco lo cruza por los rayos.
			# En su lugar: (a) fuera de radio => orbita hacia el ángulo del
			# hueco ANTES de acercarse; (b) dentro => se alinea al hueco
			# moviéndose TANGENCIALMENTE (perpendicular al radio), nunca
			# hacia adentro/afuera por un rayo.
			var hub_v: Vector2 = player - fan_hub
			var dist_hub: float = hub_v.length()
			var g_now: float = SpokeFanLogic.gap_start_angle(fan_ref)
			if dist_hub > float(fan_ref["radius"]) * 0.95:
				# fuera: ir hacia el punto del hueco en el borde del radio
				var ring_p: Vector2 = fan_hub + Vector2.from_angle(g_now) * (float(fan_ref["radius"]) * 1.05)
				steer += (ring_p - player).normalized() * 1.4
			else:
				# dentro: moverse TANGENCIALMENTE hacia el ángulo del hueco
				var my_ang: float = hub_v.angle()
				var d_ang: float = fposmod(g_now - my_ang + PI, TAU) - PI
				var tangent := Vector2.from_angle(my_ang + (PI * 0.5 if d_ang >= 0.0 else -PI * 0.5))
				steer += tangent * 1.6
				if absf(d_ang) < 0.15:
					# ya alineado al hueco: quedarse en su banda de radio
					steer += (fan_target - player).normalized() * 0.8
			# ANTI-TRAMPA DE BORDE: si la deriva tangencial empuja contra un
			# borde, sumar componente hacia el centro (un humano nunca se deja
			# acorar contra la pared por un abanico que rota lento).
			var next_p: Vector2 = player + steer.normalized() * 24.0
			if next_p.x < 90.0 or next_p.x > W - 90.0 or next_p.y < 140.0 or next_p.y > H - 70.0:
				steer += (Vector2(W * 0.5, H * 0.55) - player).normalized() * 1.2
		if wall_live and not fan_live:
			steer += (Vector2(gap_x, player.y) - player).normalized() * 1.2 if absf(gap_x - player.x) > 30.0 else Vector2.ZERO
		if danger_close and shield <= 0.0 and cooldown <= 0.0:
			shield = 1.2
			cooldown = 3.0
			shields_used += 1
		player += steer.normalized() * 550.0 * dt if steer.length() > 0.05 else Vector2.ZERO
		player.x = clampf(player.x, 50.0, W - 50.0)
		player.y = clampf(player.y, 80.0, H - 50.0)
		# --- step targets (motor real: SpokeFanLogic para el abanico) ---
		for tg in targets:
			var ty: String = tg.get("type", "target")
			if ty == "laser_telegraph":
				tg["telegraph_time"] = tg.get("telegraph_time", 1.0) - dt
				if tg["telegraph_time"] <= 0.0 and not tg.get("fired", false):
					tg["fired"] = true
					tg["type"] = "laser_beam"
					tg["lifetime"] = 0.45
			elif ty == "laser_beam":
				tg["lifetime"] = tg.get("lifetime", 0.45) - dt
			elif ty == "spoke_fan":
				var st_f: Dictionary = SpokeFanLogic.step(tg, dt, bl)
				tg["state"] = st_f["state"]
				tg["state_time"] = st_f["state_time"]
				tg["is_hazard"] = st_f["is_hazard"]
			elif ty == "homing":
				var dir: Vector2 = (player - (tg["pos"] as Vector2)).normalized()
				tg["vel"] = (tg["vel"] as Vector2).lerp(dir * 250.0, 0.1)
				tg["pos"] = (tg["pos"] as Vector2) + (tg["vel"] as Vector2) * dt
			elif ty == "perimeter":
				tg["pos"] = (tg["pos"] as Vector2) + (tg["vel"] as Vector2) * dt
			elif ty == "stripe_wall":
				tg["age"] = tg.get("age", 0.0) + dt
				var wst: String = tg.get("state", "active")
				if wst == "warning":
					tg["warn_time"] = tg.get("warn_time", 1.2) - dt
					if tg["warn_time"] <= 0.0:
						tg["state"] = "active"
				elif wst == "active":
					var step := 64.0 * dt / bl
					tg["pos"] = (tg["pos"] as Vector2) + (tg["wall_n"] as Vector2) * step
					tg["s0"] = tg["s0"] + step
					tg["s1"] = tg["s1"] + step
					tg["gap_center"] = tg["gap_center"] + step
					tg["active_time"] = tg.get("active_time", 1.6) - dt
					if tg["active_time"] <= 0.0:
						tg["state"] = "fade"
				else:
					tg["fade_time"] = tg.get("fade_time", 0.4) - dt
			else:
				tg["pos"] = (tg["pos"] as Vector2) + (tg["vel"] as Vector2) * dt
		# --- colisiones (motor real para el abanico) ---
		if iframes > 0.0:
			iframes -= dt
		var rem: Array[int] = []
		for i in range(targets.size()):
			var tg2: Dictionary = targets[i]
			var ty2: String = tg2.get("type", "target")
			if ty2 == "laser_telegraph":
				continue
			if ty2 == "spoke_fan":
				if str(tg2.get("state", "")) == "done":
					rem.append(i)
					continue
				if SpokeFanLogic.hits_player(tg2, player):
					rem.append(i)
					if shield <= 0.0 and iframes <= 0.0:
						hp -= 18.0
						iframes = 2.0
						hits += 1
				continue
			var hit := false
			if ty2 == "stripe_wall":
				var sp2: float = player.dot(tg2["wall_n"])
				hit = tg2.get("state", "active") == "active" and sp2 > tg2["s0"] - 16.0 and sp2 < tg2["s1"] + 16.0
			elif ty2 == "laser_beam":
				var bdir2 := (tg2["beam_dir"] as Vector2).normalized()
				var perp2 := absf((player - (tg2["pos"] as Vector2)).dot(Vector2(-bdir2.y, bdir2.x)))
				hit = perp2 < 12.0 + 16.0
			else:
				hit = player.distance_to(tg2["pos"]) < tg2.get("radius", 24.0) + 16.0
			if hit:
				rem.append(i)
				if shield <= 0.0 and iframes <= 0.0:
					hp -= 18.0
					iframes = 2.0
					hits += 1
		rem.reverse()
		for i2 in rem:
			if i2 < targets.size():
				targets.remove_at(i2)
		hp_nadir = minf(hp_nadir, hp)
		if hp <= 0.0:
			print("[BEAT] FAIL — bot murió t=%.1fs (%.0f%%), hits=%d, abanicos=%d" % [t, 100.0 * t / chart.duration, hits, fans_seen])
			quit(1)
			return
		t += dt
	print("[BEAT] PASS — bot+escudo sobrevive; hits=%d, escudos=%d, HP nadir=%.0f/125, abanicos=%d" % [hits, shields_used, hp_nadir, fans_seen])
	quit(0)
