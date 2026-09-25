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
		var danger_soft := false
		for tg in targets:
			var ty: String = tg.get("type", "target")
			if ty == "pulse_rings":
				# El anillo barre radialmente: quedarse en el ARCO del hueco
				# (viajar con el hueco) y, si el anillo ya pasó el radio del
				# jugador, no volver atrás (el anillo viene de adentro).
				if str(tg.get("state", "")) == "telegraph" or str(tg.get("state", "")) == "active":
					var hub_pr: Vector2 = tg["pos"]
					var g_pr: float = PulseRingsLogic.gap_angle(tg)
					var row_pr: float = float(tg.get("player_row", 560.0))
					var to_me: Vector2 = player - hub_pr
					var ang_me: float = to_me.angle()
					var d_ang_pr: float = fposmod(g_pr - ang_me + PI, TAU) - PI
					if absf(d_ang_pr) > float(tg.get("gap_angle", 1.0)) * 0.5:
						# fuera del arco: moverse hacia el hueco
						var tgt_pr: Vector2 = hub_pr + Vector2.from_angle(g_pr) * to_me.length()
						steer += (tgt_pr - player).normalized() * 1.3 if (tgt_pr - player).length() > 18.0 else Vector2.ZERO
					else:
						# en el arco: mantener la distancia al hub (radial)
						var r_now: float = PulseRingsLogic.ring_radius(tg, 0)
						if absf(to_me.length() - r_now) < 90.0:
							# el anillo está encima: correr a una banda segura
							var alt_r: float = maxf(to_me.length() - 150.0, 40.0)
							var tgt2_pr: Vector2 = hub_pr + Vector2.from_angle(g_pr) * alt_r
							steer += (tgt2_pr - player).normalized() * 1.1
					if str(tg.get("state", "")) == "active" and PulseRingsLogic.hits_player(tg, player):
						danger_close = true
			elif ty == "squeeze_corridor":
				# El corredor se cierra: quedarse en el CENTRO del bolsillo
				# (leer el telegraph y estar ahí cuando aprieta).
				if str(tg.get("state", "")) == "telegraph" or str(tg.get("state", "")) == "active":
					var tgt_c: Vector2 = Vector2(SqueezeLogic.gap_center(tg), player.y)
					steer += (tgt_c - player).normalized() * 1.5 if absf(tgt_c.x - player.x) > 12.0 else Vector2.ZERO
					if str(tg.get("state", "")) == "active" and SqueezeLogic.hits_player(tg, player):
						danger_close = true
			elif ty == "waveform_wall":
				# La onda sube desde abajo: quedarse ARRIBA de la cresta más
				# alta en su X (y si el techo está cerca de la fila del
				# jugador, moverse al trough más bajo más cercano).
				if str(tg.get("state", "")) == "telegraph" or str(tg.get("state", "")) == "active":
					var wf_state: String = str(tg.get("state", ""))
					var cols_f: int = int(tg.get("columns", 8))
					var colw_f: float = float(tg.get("col_w", 100.0))
					var my_idx: int = clampi(int(player.x / maxf(colw_f, 1.0)), 0, cols_f - 1)
					# buscar el trough más cercano (columna más baja)
					var best_i: int = my_idx
					var best_h: float = WaveformLogic.column_height(tg, my_idx)
					for o in range(-4, 5):
						var ci: int = clampi(my_idx + o, 0, cols_f - 1)
						var ch: float = WaveformLogic.column_height(tg, ci)
						if ch > best_h:
							best_h = ch
							best_i = ci
					var target_x: float = (float(best_i) + 0.5) * colw_f
					# arriba del hueco, en la fila de juego
					var safe_y: float = minf(player.y, float(tg.get("peak_line", 400.0)) - 70.0)
					var tgt: Vector2 = Vector2(target_x, safe_y)
					steer += (tgt - player).normalized() * 1.3 if (tgt - player).length() > 18.0 else Vector2.ZERO
					if wf_state == "active" and WaveformLogic.hits_player(tg, player):
						danger_close = true
			elif ty == "laser_sweep":
				# LECTURA HUMANA del arco: durante telegraph el arco completo
				# está dibujado — si el ángulo del jugador cae DENTRO de la
				# cuña del barrido, salir TANGENCIALMENTE por el extremo más
				# cercano (más allá de a1 el haz jamás pasa). Correr en línea
				# no sirve: el borde del haz a radio 800px va a 660px/s.
				if str(tg.get("state", "")) == "telegraph" or str(tg.get("state", "")) == "active":
					var sw_hub: Vector2 = tg["pos"]
					var to_sw: Vector2 = player - sw_hub
					var phi: float = to_sw.angle()
					var a0_s: float = float(tg.get("ang_start", 0.0))
					var a1_s: float = float(tg.get("ang_end", 0.0))
					var span: float = fposmod(a1_s - a0_s + PI, TAU) - PI
					var frac: float = fposmod(phi - a0_s + PI, TAU) - PI
					var in_arc: bool = absf(frac) <= absf(span) and signf(frac) == signf(span)
					if in_arc:
						var b_now: float = SweepLogic.beam_angle(tg)
						var d_to_beam: float = absf(fposmod(phi - b_now + PI, TAU) - PI)
						var beam_heading_toward: bool = signf(fposmod(b_now - phi + PI, TAU) - PI) == signf(span)
						if str(tg.get("state", "")) == "active" and d_to_beam < deg_to_rad(12.0) and beam_heading_toward:
							danger_close = true   # cruce inevitable => escudo
						var d_end: float = absf(frac) / maxf(absf(span), 0.001)
						var target_ang: float = a1_s if d_end > 0.5 else a0_s
						var d_phi: float = fposmod(target_ang - phi + PI, TAU) - PI
						var tangent_s := Vector2.from_angle(phi + (PI * 0.5 if d_phi >= 0.0 else -PI * 0.5))
						steer += tangent_s * 1.6
			elif ty == "spoke_fan":
				# Se reacciona desde el TELEGRAPH (un humano lee el aviso
				# granate y se pre-posiciona en el hueco ANTES del active).
				if str(tg.get("state", "")) == "active" or str(tg.get("state", "")) == "telegraph":
					fan_live = true
					fan_ref = tg
					fan_hub = tg["pos"]
					var g_mid: float = SpokeFanLogic.gap_start_angle(tg)
					fan_target = fan_hub + Vector2.from_angle(g_mid) * (float(tg["radius"]) * 0.6)
					if str(tg.get("state", "")) == "active" and SpokeFanLogic.hits_player(tg, player):
						danger_close = true
			elif ty == "stripe_wall" and tg.get("state", "fade") != "fade":
				# El hueco vive en el FRAME del muro (t_dir × n), no en X cruda.
				# Jugada humana: ALINEARSE TANGENCIALMENTE al hueco y NO cruzar
				# la banda — el muro barre y pasa; el jugador queda en su lado
				# con la coordenada normal intacta. PERO si el muro está ACTIVO
				# y el jugador está FUERA de la banda, el hueco es inalcanzable
				# sin cruzar rojo: QUEDARSE quieto (fuera de banda es seguro)
				# y esperar el fade — perseguir el hueco por afuera no sirve.
				var w_t: Vector2 = tg.get("wall_t", Vector2.RIGHT)
				var w_n: Vector2 = tg.get("wall_n", Vector2.DOWN)
				var my_s: float = player.dot(w_n)
				var in_band: bool = my_s > float(tg["s0"]) - 40.0 and my_s < float(tg["s1"]) + 40.0
				var w_active: bool = tg.get("state", "active") == "active"
				if not in_band or not w_active:
					# fuera de banda (o warning): alinearse al hueco por el eje
					var target_p: Vector2 = w_t * float(tg["gap_center"]) + w_n * my_s
					steer += (target_p - player).normalized() * 1.3 if (target_p - player).length() > 20.0 else Vector2.ZERO
				elif in_band and w_active:
					# DENTRO de la banda activa (en el hueco): el muro avanza
					# 64px/s — quedarse quieto lo hace que la banda te alcance
					# por detrás. MOVERSE CON el hueco (misma velocidad, mismo
					# eje): la coordenada del hueco avanza y el jugador con ella.
					var gap_p: Vector2 = w_t * float(tg["gap_center"]) + w_n * my_s
					steer += (gap_p - player).normalized() * 1.3 if (gap_p - player).length() > 14.0 else Vector2(w_t.x, w_t.y) * 0.4
				# si está EN la banda activa: danger_close (el escudo salva o
				# la alineación previa falló — cruzar no es opción)
				wall_live = true
				gap_x = w_t.x * float(tg["gap_center"]) + w_n.x * my_s
				if w_active:
					if my_s > float(tg["s0"]) - 60.0 and my_s < float(tg["s1"]) + 60.0:
						danger_close = true
			elif ty == "saw" or ty == "homing" or ty == "drifter":
				var d: Vector2 = player - (tg["pos"] as Vector2)
				var dist: float = d.length()
				if dist < 170.0 and dist > 0.01:
					steer += d.normalized() * (170.0 - dist) / 170.0
					if dist < 60.0:
						danger_soft = true   # NO consume el escudo: se esquivan
			elif ty == "perimeter":
				# Las bolas del perímetro convergen al centro cruzando la
				# fila del jugador: se esquivan como cualquier proyectil
				# (punto ciego del bot — las esquivaba el step, no el steer).
				var d: Vector2 = player - (tg["pos"] as Vector2)
				var dist: float = d.length()
				if dist < 200.0 and dist > 0.01:
					steer += d.normalized() * (200.0 - dist) / 200.0 * 1.2
					if dist < 70.0:
						danger_soft = true
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
			# ESTRATEGIA REAL: el giro puede ser MÁS RÁPIDO que el jugador en
			# su radio (1.92 rad/s del gap vs 2.1 rad/s del bot a 260px) —
			# perseguir el hueco CONTRA el giro es imposible. Dos salidas
			# honestas: (a) el OJO del hub (dist < 34 es seguro SIEMPRE, sin
			# importar el ángulo); (b) el hueco FUTURO si la carrera se puede
			# ganar. Un humano lee el telegraph y elige.
			var my_ang: float = hub_v.angle()
			var t_active_in: float = maxf(float(fan_ref.get("telegraph_beats", 2)) * bl - float(fan_ref.get("state_time", 0.0)), 0.0)
			var gap_ang_future: float = SpokeFanLogic.gap_start_angle(fan_ref) + float(fan_ref.get("rot_speed", 0.0)) * t_active_in
			if dist_hub > float(fan_ref["radius"]) * 0.95:
				# fuera: ir al punto del hueco FUTURO en el borde del radio
				var ring_p: Vector2 = fan_hub + Vector2.from_angle(gap_ang_future) * (float(fan_ref["radius"]) * 1.05)
				steer += (ring_p - player).normalized() * 1.4
			else:
				# dentro: ¿la carrera al hueco se puede ganar? El gap avanza a
				# |rot_speed| rad/s; el bot a 550/dist rad/s. Si el gap se
				# ALEJA del bot más rápido de lo que el bot puede cerrar, no:
				# ir al OJO del hub (seguro absoluto). Si se puede ganar (el
				# hueco viene hacia el bot o el bot es más rápido), alinear.
				var d_ang: float = fposmod(gap_ang_future - my_ang + PI, TAU) - PI
				var spin_dir: float = signf(float(fan_ref.get("rot_speed", 1.0)))
				var gap_coming: bool = d_ang * spin_dir < 0.0   # el hueco viene hacia mí
				var bot_ang_speed: float = 550.0 / maxf(dist_hub, 60.0)
				var can_win: bool = gap_coming or absf(d_ang) * 0.5 < bot_ang_speed * t_active_in + 0.3
				if can_win:
					if gap_coming:
						# el hueco llega solo: acercarse al centro del ojo
						steer += -hub_v.normalized() * 1.2
					else:
						var tangent := Vector2.from_angle(my_ang + (PI * 0.5 if d_ang >= 0.0 else -PI * 0.5))
						steer += tangent * 1.6
						if absf(d_ang) < 0.15:
							steer += (fan_target - player).normalized() * 0.8
				else:
					# carrera perdida: OJO del hub (dist < 90 = seguro del fan)
					steer += -hub_v.normalized() * 1.6
				# El ojo es REFUGIO TEMPORAL, no estacionamiento: si el jugador
				# ya está dentro del ojo y el fan está en fade/done cercano,
				# SALIR (los homings convergen al punto donde te escondiste).
				if dist_hub < SpokeFanLogic.EYE_RADIUS * 0.8:
					# dentro del ojo: empujar SUAVE hacia el hueco por donde
					# saldrá (el arco del hueco al radio del ojo + margen)
					var exit_ang: float = SpokeFanLogic.gap_start_angle(fan_ref)
					var exit_p: Vector2 = fan_hub + Vector2.from_angle(exit_ang) * (SpokeFanLogic.EYE_RADIUS + 40.0)
					steer += (exit_p - player).normalized() * 1.1
			# ANTI-TRAMPA DE BORDE: si la deriva tangencial empuja contra un
			# borde, sumar componente hacia el centro (un humano nunca se deja
			# acorar contra la pared por un abanico que rota lento).
			var next_p: Vector2 = player + steer.normalized() * 24.0
			if next_p.x < 90.0 or next_p.x > W - 90.0 or next_p.y < 140.0 or next_p.y > H - 70.0:
				steer += (Vector2(W * 0.5, H * 0.55) - player).normalized() * 1.2
		if wall_live and not fan_live and steer.length() < 0.05:
			# Refuerzo suave SOLO si ninguna otra fuerza pidió movimiento: el
			# steering por-frame del muro ya apunta al hueco en SU eje.
			if absf(gap_x - player.x) > 30.0:
				steer += (Vector2(gap_x, player.y) - player).normalized() * 0.6
		if danger_close and shield <= 0.0 and cooldown <= 0.0:
			shield = 1.2
			cooldown = 3.0
			shields_used += 1
		# CAPA FINAL anti-acorralamiento (global, tras todo el steering): si
		# la deriva total empuja contra un borde de la zona segura, sumar
		# componente hacia el centro — PERO mientras un setpiece ACTIVO vive,
		# su steering tiene prioridad (la alineación al hueco manda; pelearla
		# mete al jugador entre rayos).
		if steer.length() > 0.05 and not fan_live and not wall_live:
			var next_p2: Vector2 = player + steer.normalized() * 40.0
			if next_p2.x < 100.0 or next_p2.x > W - 100.0:
				steer.x += (W * 0.5 - player.x) * 0.08
			if next_p2.y < 150.0 or next_p2.y > H - 80.0:
				steer.y += (H * 0.55 - player.y) * 0.08
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
			elif ty == "laser_sweep":
				var sw_f: Dictionary = SweepLogic.step(tg, dt, bl)
				tg["state"] = sw_f["state"]
				tg["state_time"] = sw_f["state_time"]
				tg["is_hazard"] = sw_f["is_hazard"]
			elif ty == "waveform_wall":
				var wf_f: Dictionary = WaveformLogic.step(tg, dt, bl)
				tg["state"] = wf_f["state"]
				tg["state_time"] = wf_f["state_time"]
				tg["is_hazard"] = wf_f["is_hazard"]
			elif ty == "squeeze_corridor":
				var sq_f: Dictionary = SqueezeLogic.step(tg, dt, bl)
				tg["state"] = sq_f["state"]
				tg["state_time"] = sq_f["state_time"]
				tg["is_hazard"] = sq_f["is_hazard"]
			elif ty == "pulse_rings":
				var pr_f: Dictionary = PulseRingsLogic.step(tg, dt, bl)
				tg["state"] = pr_f["state"]
				tg["state_time"] = pr_f["state_time"]
				tg["is_hazard"] = pr_f["is_hazard"]
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
			if ty2 == "pulse_rings":
				if str(tg2.get("state", "")) == "done":
					rem.append(i)
					continue
				if PulseRingsLogic.hits_player(tg2, player):
					rem.append(i)
					if shield <= 0.0 and iframes <= 0.0:
						hp -= 18.0
						iframes = 2.0
						hits += 1
				continue
			if ty2 == "squeeze_corridor":
				if str(tg2.get("state", "")) == "done":
					rem.append(i)
					continue
				if SqueezeLogic.hits_player(tg2, player):
					rem.append(i)
					if shield <= 0.0 and iframes <= 0.0:
						hp -= 18.0
						iframes = 2.0
						hits += 1
				continue
			if ty2 == "waveform_wall":
				if str(tg2.get("state", "")) == "done":
					rem.append(i)
					continue
				if WaveformLogic.hits_player(tg2, player):
					rem.append(i)
					if shield <= 0.0 and iframes <= 0.0:
						hp -= 18.0
						iframes = 2.0
						hits += 1
				continue
			if ty2 == "laser_sweep":
				if str(tg2.get("state", "")) == "done":
					rem.append(i)
					continue
				if SweepLogic.hits_player(tg2, player):
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
