class_name SetpieceRenderer
extends RefCounted
## SetpieceRenderer — dibujo de todos los peligros (abanico, anillos, muros,
## sierras, laser): funciones estaticas puras. Lo que se DIBUJA es lo que MATA
## (ver SpokeFanLogic.hits_player). Mudado verbatim desde Gameplay (Fase A3):
## misma geometria, mismos colores; solo cambian beat_interval/song_time/
## play_size, que llegan por parametro en vez de por miembro.

const _SpokeFanLogic: GDScript = preload("res://scripts/SpokeFanLogic.gd")
const _SweepLogic: GDScript = preload("res://scripts/SweepLogic.gd")
const _WaveformLogic: GDScript = preload("res://scripts/WaveformLogic.gd")
const _SqueezeLogic: GDScript = preload("res://scripts/SqueezeLogic.gd")
const _PulseRingsLogic: GDScript = preload("res://scripts/PulseRingsLogic.gd")
const _PatternLanguage: GDScript = preload("res://scripts/PatternLanguage.gd")

static func neon_polyline(canvas: CanvasItem, points: PackedVector2Array, c: Color, w: float) -> void:
	# Trazo neón: halo ancho translúcido + capa media + núcleo HDR (>1.0
	# dispara el bloom del Environment glow).
	canvas.draw_polyline(points, Color(c.r, c.g, c.b, 0.20), w * 3.4)
	canvas.draw_polyline(points, Color(c.r, c.g, c.b, 0.5), w * 1.9)
	canvas.draw_polyline(points, Color(minf(c.r * 1.7, 4.0), minf(c.g * 1.7, 4.0), minf(c.b * 1.7, 4.0), 1.0), w)

static func neon_line(canvas: CanvasItem, a: Vector2, b: Vector2, c: Color, w: float) -> void:
	canvas.draw_line(a, b, Color(c.r, c.g, c.b, 0.20), w * 3.4)
	canvas.draw_line(a, b, Color(c.r, c.g, c.b, 0.5), w * 1.9)
	canvas.draw_line(a, b, Color(minf(c.r * 1.7, 4.0), minf(c.g * 1.7, 4.0), minf(c.b * 1.7, 4.0), 1.0), w)

static func neon_arc(canvas: CanvasItem, center: Vector2, r: float, c: Color, w: float) -> void:
	canvas.draw_arc(center, r, 0, TAU, 32, Color(c.r, c.g, c.b, 0.18), w * 3.2)
	canvas.draw_arc(center, r, 0, TAU, 32, Color(c.r, c.g, c.b, 0.5), w * 1.7)
	canvas.draw_arc(center, r, 0, TAU, 32, Color(minf(c.r * 1.7, 4.0), minf(c.g * 1.7, 4.0), minf(c.b * 1.7, 4.0), 1.0), w)

## Arco neón de un sector (start..end): el hueco de los anillos se dibuja
## literalmente como el espacio que falta del arco.
static func neon_arc_full(canvas: CanvasItem, center: Vector2, r: float, from_a: float, to_a: float, c: Color, w: float) -> void:
	canvas.draw_arc(center, r, from_a, to_a, 40, Color(c.r, c.g, c.b, 0.18), w * 3.2)
	canvas.draw_arc(center, r, from_a, to_a, 40, Color(c.r, c.g, c.b, 0.5), w * 1.7)
	canvas.draw_arc(center, r, from_a, to_a, 40, Color(minf(c.r * 1.7, 4.0), minf(c.g * 1.7, 4.0), minf(c.b * 1.7, 4.0), 1.0), w)

## Telegrafía de aparición de proyectiles (sierras, derivas, misiles): anillo
## que colapsa sobre el objeto en sus primeros 0.5s + marca parpadeante en el
## borde superior mientras entra (y<80). Nada aparece de golpe: la entrada por
## arriba se anuncia en su carril.
static func draw_spawn_warning(canvas: CanvasItem, pos: Vector2, radius: float, age: float, view: Vector2) -> void:
	if age < 0.5:
		var k: float = clampf(age / 0.5, 0.0, 1.0)
		var wr: float = radius * (2.4 - 1.4 * k)
		canvas.draw_arc(pos, wr, 0, TAU, 32, Color(1.0, 0.25, 0.32, 0.55 * (1.0 - k * 0.5)), 2.0)
	if pos.y < 80.0:
		var blink: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
		var tx: float = clampf(pos.x, 20.0, view.x - 20.0)
		canvas.draw_colored_polygon(PackedVector2Array([
				Vector2(tx, 6.0), Vector2(tx - 7.0, 18.0), Vector2(tx + 7.0, 18.0)]),
			Color(1.0, 0.25, 0.3, 0.35 + 0.45 * blink))

static func draw_target(canvas: CanvasItem, t: Dictionary, beat_interval: float, song_time: float, view: Vector2) -> void:
	# Dibujo de un spawn. _draw lo invoca en 3 pasadas: hazards comunes,
	# stripe_wall translúcido encima (deja ver las sierras atrapadas en la
	# banda) y lasers al final (el telegraph jamas queda tapado).
	var ttype_d: String = t.get("type", "target")
	if ttype_d == "spoke_fan":
		# Abanico de rayos: lo que se DIBUJA es lo que MATA (ver
		# SpokeFanLogic.hits_player). Solo los rayos son letales, solo en
		# active: no hay rellenos de territorio (el disco rojo y el sector
		# cian no mataban a nadie y se eliminaron). El hueco se marca con
		# rieles cian positivos + chevron; el ojo del hub (r=90, seguro
		# siempre por EYE_RADIUS) se dibuja tenue.
		var hub_d: Vector2 = t["pos"]
		var rad_d: float = float(t["radius"])
		var n_sp: int = int(t.get("spokes", 8))
		var gap_sp: int = int(t.get("gap_spokes", 2))
		var gap_first_d: int = int(t.get("gap_first", 0))
		var rot_d: float = _SpokeFanLogic.rotation_at(t)
		var st_d: String = str(t.get("state", "telegraph"))
		var alpha_d: float = 1.0
		if st_d == "fade":
			alpha_d = clampf(1.0 - float(t.get("state_time", 0.0)) / maxf(float(t.get("fade_beats", 2)) * beat_interval, 0.001), 0.0, 1.0)
		var pulse_d: float = maxf(0.0, 1.0 - fposmod(float(t.get("state_time", 0.0)) / maxf(beat_interval, 0.001), 1.0))
		var eye_d: float = _SpokeFanLogic.EYE_RADIUS
		var rim_d: float = minf(rad_d, view.length() * 0.5)
		var sector_from: float = rot_d + TAU * float(gap_first_d) / float(n_sp)
		var sector_to: float = sector_from + TAU * float(gap_sp) / float(n_sp)
		var rim_col := Color(0.55, 0.30, 0.42, 0.35 if st_d != "telegraph" else 0.3)
		# Aro = frontera letal exacta (colisión: dist > radius es seguro).
		canvas.draw_arc(hub_d, rim_d, 0.0, TAU, 64, rim_col * Color(1, 1, 1, alpha_d), 2.0)
		# Ojo seguro del hub: dentro de r=90 nunca duele, en ningún estado.
		canvas.draw_arc(hub_d, eye_d, 0.0, TAU, 48, Color(0.7, 0.85, 0.9, 0.16 * alpha_d), 1.5)
		# Rieles del pasillo seguro: marcan la SALIDA cerca del aro (tramo
		# exterior), no una línea cruzando toda la pantalla. Es lo ÚNICO cian
		# del setpiece y lo único que hay que alcanzar.
		for b_i in range(2):
			var b_ang: float = sector_from if b_i == 0 else sector_to
			var b_dir := Vector2.from_angle(b_ang)
			var rail_a: Vector2 = hub_d + b_dir * rim_d * 0.7
			var b_tip: Vector2 = hub_d + b_dir * rim_d
			var mark_a: float = (0.8 if st_d != "telegraph" else 0.6) * alpha_d
			canvas.draw_line(rail_a, b_tip, Color(0.45, 0.95, 1.0, 0.25 * mark_a), 7.0)
			canvas.draw_line(rail_a, b_tip, Color(0.45, 0.95, 1.0, mark_a), 3.0)
			# punta de flecha en el aro: DÓNDE termina el pasillo
			var perp := b_dir.rotated(PI * 0.5)
			canvas.draw_colored_polygon(PackedVector2Array([
					b_tip + b_dir * 12.0, b_tip + perp * 8.0, b_tip - perp * 8.0]),
				Color(0.45, 0.95, 1.0, 0.8 * alpha_d))
		for k in range(n_sp):
			var in_gap_d: bool = false
			for g in range(gap_sp):
				if (gap_first_d + g) % n_sp == k:
					in_gap_d = true
					break
			if in_gap_d:
				continue
			var ang_d: float = rot_d + TAU * float(k) / float(n_sp)
			var dir_d := Vector2.from_angle(ang_d)
			var base_d: Vector2 = hub_d + dir_d * eye_d
			var tip_d: Vector2 = hub_d + dir_d * rim_d
			if st_d == "telegraph":
				# Aviso: misma forma del rayo, tenue y sin núcleo caliente.
				var warn_a: float = (0.55 + 0.25 * pulse_d) * alpha_d
				canvas.draw_line(base_d, tip_d, Color(0.9, 0.22, 0.32, 0.18 * warn_a), 26.0)
				canvas.draw_line(base_d, tip_d, Color(0.9, 0.22, 0.32, 0.55 * warn_a), 12.0)
				canvas.draw_line(base_d, tip_d, Color(1.2, 0.35, 0.42, 0.8 * warn_a), 5.0)
				canvas.draw_circle(tip_d, 6.0, Color(0.9, 0.25, 0.32, 0.5 * warn_a))
			else:
				# Rayo neón de calidad: halo + cuerpo + núcleo casi blanco +
				# extremos redondeados. Ancho total ~26px = ancho letal real
				# (halfwidth 13px en hits_player): el brillo no miente.
				var body_a: float = (0.85 + 0.15 * pulse_d) * alpha_d
				canvas.draw_line(base_d, tip_d, Color(1.0, 0.2, 0.3, 0.16 * body_a), 30.0)
				canvas.draw_line(base_d, tip_d, Color(1.0, 0.2, 0.3, 0.5 * body_a), 20.0)
				canvas.draw_line(base_d, tip_d, Color(1.9, 0.45, 0.55, 0.95 * body_a), 12.0)
				canvas.draw_line(base_d, tip_d, Color(2.4, 2.0, 2.1, 0.9 * body_a), 5.0)
				canvas.draw_circle(base_d, 15.0, Color(1.0, 0.2, 0.3, 0.16 * body_a))
				canvas.draw_circle(tip_d, 15.0, Color(1.0, 0.2, 0.3, 0.16 * body_a))
				canvas.draw_circle(tip_d, 6.0, Color(2.4, 1.8, 1.9, 0.9 * body_a))
		# Sentido de giro: dos puntas de flecha en rayos opuestos, tangentes a la
		# rotación real (signo de rot_speed). En telegraph enseña hacia dónde
		# va a barrer; en active confirma. Así los "palos de reloj" se leen
		# como máquina girando, no como decoración.
		var spin_sign: float = signf(float(t.get("rot_speed", 0.0)))
		if spin_sign == 0.0:
			spin_sign = 1.0
		var spin_mid: int = n_sp / 2
		for spin_k in [0, spin_mid]:
			var in_gap_s: bool = false
			for g in range(gap_sp):
				if (gap_first_d + g) % n_sp == spin_k:
					in_gap_s = true
					break
			if in_gap_s:
				continue
			var s_ang: float = rot_d + TAU * float(spin_k) / float(n_sp)
			var s_dir := Vector2.from_angle(s_ang)
			var s_tip: Vector2 = hub_d + s_dir * rim_d * 0.8
			var tangent := s_dir.rotated(spin_sign * PI * 0.5)
			var tri_col := Color(1.0, 0.45, 0.5, 0.75 * alpha_d) if st_d != "telegraph" else Color(0.95, 0.4, 0.45, 0.6 * alpha_d)
			canvas.draw_colored_polygon(PackedVector2Array([
					s_tip + tangent * 10.0, s_tip + s_dir * 7.0 - tangent * 4.0, s_tip - s_dir * 7.0 - tangent * 4.0]),
				tri_col)
		# Hub: aro del tamaño del "ojo" seguro + núcleo
		if st_d == "telegraph":
			canvas.draw_arc(hub_d, 24.0, 0, TAU, 24, Color(0.7, 0.25, 0.3, 0.4 * alpha_d), 2.5)
			canvas.draw_circle(hub_d, 7.0, Color(0.7, 0.25, 0.3, 0.6 * alpha_d))
		else:
			neon_arc(canvas, hub_d, 24.0, Color(1.0, 0.2, 0.3), 3.0)
			canvas.draw_circle(hub_d, 8.0, Color(2.4, 2.4, 2.4, 0.85 * alpha_d))  # blanco impacto
			canvas.draw_circle(hub_d, 4.0, Color(1.0, 0.25, 0.35, alpha_d))
		# Chevrons del hueco: marcan el pasillo seguro. En telegraph van tenues
		# (el refugio se aprende antes del golpe), en active plenos.
		var g_mid: float = _SpokeFanLogic.gap_start_angle(t)
		var gdir := Vector2.from_angle(g_mid)
		var chev := hub_d + gdir * rim_d * 0.55
		var chev_a: float = 0.35 * alpha_d if st_d != "telegraph" else 0.22 * alpha_d
		canvas.draw_colored_polygon(PackedVector2Array([
				chev + gdir * 12.0, chev + gdir.rotated(2.5) * -9.0, chev + gdir.rotated(-2.5) * -9.0]),
				Color(0.4, 0.95, 1.0, chev_a))
		return
	if ttype_d == "mini_ring":
		# T7 mini-jab: arco SENCILLO, más fino y translúcido que un setpiece
		# (es puntuación, no un momento). Telegraph = arco tenue; active =
		# arco hot-pink fino con el hueco visible.
		var mj_hub: Vector2 = t["pos"]
		var mj_st_d: String = str(t.get("state", "telegraph"))
		var mj_gc: float = float(t.get("gap_center", 0.0)) + float(t.get("spin", 0.0)) * float(t.get("state_time", 0.0))
		var mj_ga: float = float(t.get("gap_angle", 1.2))
		var mj_a0: float = mj_gc + mj_ga * 0.5
		var mj_a1: float = mj_gc - mj_ga * 0.5 + TAU
		var mj_tgt: float = float(t.get("target_radius", 300.0))
		var mj_al: float = 0.75 if mj_st_d != "telegraph" else 0.45
		if mj_st_d == "fade":
			mj_al = clampf(1.0 - float(t.get("state_time", 0.0)) / maxf(float(t.get("fade_beats", 1)) * beat_interval, 0.001), 0.0, 1.0) * 0.75
		var mj_r: float = mj_tgt
		if mj_st_d == "telegraph":
			mj_r = mj_tgt * 0.35
			canvas.draw_arc(mj_hub, mj_tgt, mj_a0, mj_a1, 32, Color(0.6, 0.18, 0.24, 0.3 * mj_al), 2.0)
		canvas.draw_arc(mj_hub, mj_r, mj_a0, mj_a1, 32, Color(0.95, 0.25, 0.32, 0.55 * mj_al), 3.5)
		canvas.draw_arc(mj_hub, mj_r, mj_a0, mj_a1, 32, Color(1.6, 0.5, 0.6, 0.8 * mj_al), 1.6)
		# Extremos del hueco marcados: el mini-arco también es puerta con salida.
		canvas.draw_circle(mj_hub + Vector2.from_angle(mj_a0) * mj_r, 3.5, Color(0.45, 0.95, 1.0, 0.55 * mj_al))
		canvas.draw_circle(mj_hub + Vector2.from_angle(mj_a1) * mj_r, 3.5, Color(0.45, 0.95, 1.0, 0.55 * mj_al))
		return
	if ttype_d == "mini_fan":
		# T7 mini-jab abanico: 3 rayos finos desde el hub, hueco amplio.
		var mf_hub: Vector2 = t["pos"]
		var mf_st_d: String = str(t.get("state", "telegraph"))
		var mf_al: float = 0.8 if mf_st_d != "telegraph" else 0.5
		if mf_st_d == "fade":
			mf_al = clampf(1.0 - float(t.get("state_time", 0.0)) / maxf(float(t.get("fade_beats", 1)) * beat_interval, 0.001), 0.0, 1.0) * 0.8
		var mf_gf: int = int(t.get("gap_first", 0))
		var mf_gap: int = int(t.get("gap_spokes", 1))
		var mf_n: int = int(t.get("spokes", 3))
		var mf_r: float = float(t.get("radius", 260.0))
		var mf_rot: float = float(t.get("rot_speed", 0.0)) * float(t.get("state_time", 0.0))
		var mf_r_eff: float = mf_r * (0.7 if mf_st_d == "telegraph" else 1.0)
		for k in range(mf_n):
			var kk: int = fposmod(k - mf_gf, mf_n)
			if kk < mf_gap:
				continue   # hueco
			var ang: float = TAU * float(k) / float(mf_n) + mf_rot
			neon_line(canvas, mf_hub, mf_hub + Vector2.from_angle(ang) * mf_r_eff, Color(1.0, 0.28, 0.35), 3.5 * mf_al)
		# Bordes del hueco marcados en cian: el mini-abanico también es puerta.
		for gb in [mf_gf, mf_gf + mf_gap]:
			var ga: float = TAU * float(fposmod(gb - 0.5, mf_n)) / float(mf_n) + mf_rot
			canvas.draw_circle(mf_hub + Vector2.from_angle(ga) * mf_r_eff, 4.0, Color(0.45, 0.95, 1.0, 0.6 * mf_al))
		canvas.draw_circle(mf_hub, 4.0, Color(1.4, 0.6, 0.7, 0.6 * mf_al))
		return
	if ttype_d == "pulse_rings":
		# JSAB anillos expansivos: se dibujan como ARCOS (no círculos
		# completos) — el hueco es literalmente el espacio que falta. Telegraph
		# = arcos tenues del tamaño final (se lee DÓNDE va a cerrar); active =
		# arcos hot-pink con núcleo blanco; fade decae.
		var hub_r: Vector2 = t["pos"]
		var n_r: int = int(t.get("rings", 2))
		var g_ang_r: float = _PulseRingsLogic.gap_angle(t)
		var gap_r: float = float(t.get("gap_angle", 1.0))
		var st_r: String = str(t.get("state", "telegraph"))
		var alpha_r: float = 1.0
		if st_r == "fade":
			alpha_r = clampf(1.0 - float(t.get("state_time", 0.0)) / maxf(float(t.get("fade_beats", 2)) * beat_interval, 0.001), 0.0, 1.0)
		var pulse_r: float = maxf(0.0, 1.0 - fposmod(float(t.get("state_time", 0.0)) / maxf(beat_interval, 0.001), 1.0))
		for i_r in range(n_r):
			var r_r: float = _PulseRingsLogic.ring_radius(t, i_r)
			if r_r < 8.0:
				continue
			# el arco va del final del hueco al principio (el hueco queda abierto)
			var a_start: float = g_ang_r + gap_r * 0.5
			var a_end: float = g_ang_r - gap_r * 0.5 + TAU
			if st_r == "telegraph":
				var ghost_r: float = float(t.get("target_radius", 460.0)) * (1.0 + 0.30 * float(i_r))
				canvas.draw_arc(hub_r, ghost_r, a_start, a_end, 40, Color(0.95, 0.3, 0.38, (0.58 + 0.22 * pulse_r) * alpha_r), 4.0)
			else:
				neon_arc_full(canvas, hub_r, r_r, a_start, a_end, Color(1.0, 0.2, 0.3), 6.0 * (0.85 + 0.15 * pulse_r))
		# Baliza del hueco: guía cian del hub hacia la salida + puntos en los
		# extremos del arco. El "círculo incompleto" se lee como puerta con
		# salida marcada, en telegraph tenue y en active plena.
		var gap_dir := Vector2.from_angle(g_ang_r)
		var beacon_a: float = 0.5 * alpha_r if st_r != "telegraph" else 0.3 * alpha_r
		var beacon_r: float = _PulseRingsLogic.ring_radius(t, 0)
		if beacon_r > 8.0:
			var b0: Vector2 = hub_r + gap_dir * 18.0
			var b1: Vector2 = hub_r + gap_dir * beacon_r
			var steps: int = 6
			for bs in range(steps):
				var p0: Vector2 = b0.lerp(b1, float(bs) / float(steps))
				var p1: Vector2 = b0.lerp(b1, (float(bs) + 0.55) / float(steps))
				canvas.draw_line(p0, p1, Color(0.4, 0.95, 1.0, beacon_a), 2.5)
		var end_a0 := Vector2.from_angle(g_ang_r + gap_r * 0.5)
		var end_a1 := Vector2.from_angle(g_ang_r - gap_r * 0.5)
		canvas.draw_circle(hub_r + end_a0 * beacon_r, 4.5, Color(0.45, 0.95, 1.0, beacon_a))
		canvas.draw_circle(hub_r + end_a1 * beacon_r, 4.5, Color(0.45, 0.95, 1.0, beacon_a))
		# hub: núcleo blanco de impacto
		if st_r != "telegraph":
			canvas.draw_circle(hub_r, 7.0, Color(2.3, 2.3, 2.3, 0.8 * alpha_r))
		# chevrons en el hueco: el pasillo seguro, marcado
		if st_r != "telegraph":
			var chev_r: Vector2 = hub_r + Vector2.from_angle(g_ang_r) * (_PulseRingsLogic.ring_radius(t, 0) * 0.5)
			var d_r: Vector2 = (chev_r - hub_r).normalized()
			canvas.draw_colored_polygon(PackedVector2Array([
					chev_r + d_r * 13.0, chev_r + d_r.rotated(2.5) * -9.0, chev_r + d_r.rotated(-2.5) * -9.0]),
				Color(0.4, 0.95, 1.0, 0.34 * alpha_r))
		return
	if ttype_d == "squeeze_corridor":
		# JSAB corredor bilateral: dos paredes squeezing el espacio. Telegraph =
		# contornos tenues marcando DÓNDE va a apretar (leer el bolsillo antes);
		# active = paredes hot-pink macizas con borde neón y chevrons apuntando
		# al pasillo; fade decae.
		var ps_s: Vector2 = view
		var edges_s: Vector2 = _SqueezeLogic.band_inner_edges(t)
		var half_s: float = float(t.get("band_half", 46.0))
		var st_s2: String = str(t.get("state", "telegraph"))
		var alpha_s2: float = 1.0
		if st_s2 == "fade":
			alpha_s2 = clampf(1.0 - float(t.get("state_time", 0.0)) / maxf(float(t.get("fade_beats", 2)) * beat_interval, 0.001), 0.0, 1.0)
		var pulse_s2: float = maxf(0.0, 1.0 - fposmod(float(t.get("state_time", 0.0)) / maxf(beat_interval, 0.001), 1.0))
		for side_i in range(2):
			var inner_x: float = edges_s.x if side_i == 0 else edges_s.y
			var outer_x: float = 0.0 if side_i == 0 else ps_s.x
			var r := Rect2(
				Vector2(outer_x, 0.0) if side_i == 0 else Vector2(inner_x, 0.0),
				Vector2(inner_x - outer_x, ps_s.y) if side_i == 0 else Vector2(ps_s.x - inner_x, ps_s.y))
			if st_s2 == "telegraph":
				# aviso: relleno granate muy tenue + borde interior pulsante
				canvas.draw_rect(r, Color(0.45, 0.08, 0.14, 0.46 * alpha_s2))
				canvas.draw_line(Vector2(inner_x, 0.0), Vector2(inner_x, ps_s.y),
					Color(0.75, 0.22, 0.3, (0.45 + 0.3 * pulse_s2) * alpha_s2), 2.5)
			else:
				canvas.draw_rect(r, Color(0.5, 0.05, 0.12, 0.6 * alpha_s2))
				neon_line(canvas, Vector2(inner_x, 0.0), Vector2(inner_x, ps_s.y), Color(1.0, 0.2, 0.3), 6.0)
				# franjas internas: la textura hace legible la presión
				var stripe_sp: float = 74.0
				var sx: float = outer_x + stripe_sp * 0.5
				while sx < inner_x:
					canvas.draw_line(Vector2(sx, 0.0), Vector2(sx, ps_s.y), Color(0.2, 0.05, 0.08, 0.4 * alpha_s2), 1.5)
					sx += stripe_sp
			# chevrons apuntando al pasillo (le say "aquí adentro")
			var dir_c: float = 1.0 if side_i == 0 else -1.0
			for cy_s in range(3):
				var cyy: float = ps_s.y * (0.3 + 0.2 * float(cy_s))
				var cxp: float = inner_x + dir_c * 26.0
				canvas.draw_colored_polygon(PackedVector2Array([
						Vector2(cxp + dir_c * 14.0, cyy),
						Vector2(cxp - dir_c * 8.0, cyy - 11.0),
						Vector2(cxp - dir_c * 8.0, cyy + 11.0)]),
					Color(0.4, 0.95, 1.0, 0.30 * alpha_s2))
		return
	if ttype_d == "waveform_wall":
		# JSAB muro de ONDA: columnas que emergen desde abajo siguiendo el
		# perfil. Telegraph = columnas tenues que ya insinúan la forma (se lee
		# POR DÓNDE pasa la onda antes de que llegue); active = columnas
		# hot-pink con borde neón y cresta blanca; fade decae.
		var cols_w: int = int(t.get("columns", 8))
		var colw_w: float = float(t.get("col_w", 160.0))
		var st_w: String = str(t.get("state", "telegraph"))
		var alpha_w: float = 1.0
		if st_w == "fade":
			alpha_w = clampf(1.0 - float(t.get("state_time", 0.0)) / maxf(float(t.get("fade_beats", 2)) * beat_interval, 0.001), 0.0, 1.0)
		var play_w0: Vector2 = view
		for c in range(cols_w):
			var h_w: float = _WaveformLogic.column_height(t, c)
			var x0_w: float = float(c) * colw_w
			var x1_w: float = x0_w + colw_w
			var bottom_w: float = play_w0.y
			if st_w == "telegraph":
				# aviso: relleno granate translúcido + borde superior tenue
				canvas.draw_rect(Rect2(Vector2(x0_w + 1.0, h_w), Vector2(colw_w - 2.0, bottom_w - h_w)),
					Color(0.52, 0.09, 0.16, 0.50 * alpha_w))
				canvas.draw_line(Vector2(x0_w, h_w), Vector2(x1_w, h_w), Color(0.7, 0.2, 0.28, 0.55 * alpha_w), 2.0)
			else:
				# active: columna llena con neón, cresta con brillo
				canvas.draw_rect(Rect2(Vector2(x0_w + 1.0, h_w), Vector2(colw_w - 2.0, bottom_w - h_w)),
					Color(0.55, 0.06, 0.14, 0.62 * alpha_w))
				neon_line(canvas, Vector2(x0_w, h_w), Vector2(x1_w, h_w), Color(1.0, 0.2, 0.3), 5.0)
				# crestas más altas: remate blanco de impacto
				if h_w < float(t.get("peak_line", 400.0)) + 6.0:
					canvas.draw_line(Vector2(x0_w, h_w), Vector2(x1_w, h_w), Color(2.0, 0.6, 0.7, 0.85 * alpha_w), 2.0)
			# separadores verticales tenues: la retícula hace legible la onda
			canvas.draw_line(Vector2(x0_w, h_w), Vector2(x0_w, bottom_w), Color(0.3, 0.1, 0.16, 0.3 * alpha_w), 1.0)
		return
	if ttype_d == "laser_sweep":
		# JSAB láser que barre: telegraph = ARCO completo del recorrido con
		# haz fantasma en ang_start (el jugador lee HACIA dónde viene); active
		# = haz rosa HDR barriendo con estela en el arco; fade decae.
		var hub_s: Vector2 = t["pos"]
		var a0: float = float(t.get("ang_start", 0.0))
		var a1: float = float(t.get("ang_end", 0.0))
		var blen: float = float(t.get("beam_len", 1700.0))
		var st_s: String = str(t.get("state", "telegraph"))
		var alpha_s: float = 1.0
		if st_s == "fade":
			alpha_s = clampf(1.0 - float(t.get("state_time", 0.0)) / maxf(float(t.get("fade_beats", 2)) * beat_interval, 0.001), 0.0, 1.0)
		var pulse_s: float = maxf(0.0, 1.0 - fposmod(float(t.get("state_time", 0.0)) / maxf(beat_interval, 0.001), 1.0))
		# Arco del recorrido (siempre visible mientras vive)
		var arc_from: float = minf(a0, a1)
		var arc_to: float = maxf(a0, a1)
		var arc_col: Color = Color(0.88, 0.22, 0.32, (0.48 + 0.22 * pulse_s) * alpha_s)
		if st_s == "telegraph":
			arc_col = Color(0.95, 0.30, 0.42, (0.55 + 0.28 * pulse_s) * alpha_s)
		canvas.draw_arc(hub_s, 46.0, arc_from, arc_to, 28, arc_col, 2.5)
		if st_s == "telegraph":
			# haz fantasma en ang_start: por dónde ENTRARÁ
			var ghost := Vector2.from_angle(a0)
			canvas.draw_line(hub_s, hub_s + ghost * blen, Color(0.75, 0.2, 0.28, (0.3 + 0.2 * pulse_s) * alpha_s), 3.0)
			var tip_g: Vector2 = hub_s + ghost * blen
			canvas.draw_circle(tip_g, 6.0, Color(0.8, 0.25, 0.3, 0.6 * alpha_s))
		else:
			# haz activo barriendo (easeInOut — arranca y frena en el beat)
			var bdir_s := Vector2.from_angle(_SweepLogic.beam_angle(t))
			neon_line(canvas, hub_s, hub_s + bdir_s * blen, Color(1.0, 0.2, 0.3), 8.0 * (0.85 + 0.15 * pulse_s))
			canvas.draw_line(hub_s, hub_s + bdir_s * blen, Color(2.2, 0.5, 0.6, 0.95 * alpha_s), 3.0)
			# hub con núcleo blanco (impacto)
			neon_arc(canvas, hub_s, 20.0, Color(1.0, 0.2, 0.3, 0.9 * alpha_s), 3.0)
			canvas.draw_circle(hub_s, 7.0, Color(2.4, 2.4, 2.4, 0.85 * alpha_s))
		return
	if ttype_d == "laser_telegraph":
		# Aviso de laser: IMPOSIBLE de ignorar. Línea de peligro que
		# parpadea cada vez más rápido + anillos de alarma en el ancla.
		var bdir: Vector2 = (t.get("beam_dir", Vector2.UP) as Vector2).normalized()
		var c: Vector2 = t["pos"] as Vector2
		var h: float = t.get("telegraph_time", 1.3)
		var total_t: float = t.get("telegraph_total", 1.3)
		var urg: float = clampf(1.0 - h / total_t, 0.0, 1.0)
		var now_s: float = Time.get_ticks_msec() * 0.001
		# Parpadeo: arranca lento (5Hz) y acelera hasta ~13Hz cerca del disparo
		var blink: float = 0.5 + 0.5 * sin(now_s * TAU * (5.0 + 8.0 * urg))
		# Línea de peligro: halo rojo grueso + núcleo amarillo parpadeante
		var lw: float = 5.0 + 7.0 * urg
		# Largo = diagonal completa + margen: el ancla vive al borde y el
		# beam debe cruzar TODA la pantalla en esa dirección, no medio.
		var beam_len: float = view.length() + 100.0
		canvas.draw_line(c - bdir * beam_len, c + bdir * beam_len, Color(1.0, 0.15, 0.15, 0.30), lw + 7.0)
		canvas.draw_line(c - bdir * beam_len, c + bdir * beam_len, Color(1.0, 0.85, 0.1, 0.35 + 0.6 * blink), lw)
		# Anillos de alarma expandiéndose desde el ancla
		var ring_t: float = fmod(now_s * 2.2, 1.0)
		var ring_r: float = 8.0 + ring_t * 40.0
		canvas.draw_arc(c, ring_r, 0, TAU, 24, Color(1.0, 0.3, 0.2, 0.8 * (1.0 - ring_t)), 3.0)
		var ring2_t: float = fmod(now_s * 2.2 + 0.5, 1.0)
		canvas.draw_arc(c, 8.0 + ring2_t * 40.0, 0, TAU, 24, Color(1.0, 0.5, 0.1, 0.7 * (1.0 - ring2_t)), 2.0)
		canvas.draw_circle(c, 7.0, Color(1.0, 0.2, 0.2, 0.9))
	elif ttype_d == "laser_beam":
		# Beam flash: núcleo blanco HDR + halo rosa que parpadea su vida corta
		var bdir: Vector2 = (t.get("beam_dir", Vector2.UP) as Vector2).normalized()
		var c: Vector2 = t["pos"] as Vector2
		var lt: float = t.get("lifetime", 0.5)
		var flash: float = 0.5 + 0.5 * sin(lt * 80.0)
		# Igual que el telegraph: diagonal completa + margen.
		var beam_len2: float = view.length() + 100.0
		neon_line(canvas, c - bdir * beam_len2, c + bdir * beam_len2, Color(1.0, 0.0, 0.55), 7.0)
		canvas.draw_line(c - bdir * beam_len2, c + bdir * beam_len2, Color(2.0, 2.0, 2.0, 0.85), 4 + 3 * flash)
	elif t.get("is_hazard", false):
		match ttype_d:
			"stripe_wall":
				# Muro orientado: warning (RELLENO letal visible pulsando al beat +
				# corredor del hueco delimitado + chevrons en fase), active (solido,
				# franjas que desfilan al compas, borde HDR) y fade (alpha).
				var w_alpha: float = t.get("alpha", 1.0)
				var w_size: Vector2 = t["size"]
				var w_state: String = t.get("state", "active")
				var w_half: Vector2 = w_size * 0.5
				canvas.draw_set_transform(t["pos"], t["rot"], Vector2.ONE)
				# Fase musical: el muro nace en un downbeat (age=0 ahi), asi que el
				# pulso visual cae exactamente en los acentos de la cancion.
				var w_beat_len: float = maxf(beat_interval, 0.001)
				var w_age: float = float(t.get("age", 0.0))
				var wpulse: float = maxf(0.0, 1.0 - fposmod(w_age / w_beat_len, 1.0))
				var w_smid: float = (float(t["s0"]) + float(t["s1"])) * 0.5
				var w_gc: float = float(t["gap_center"])
				var gap_ly: float = -(w_gc - w_smid)
				if w_state == "warning":
					# 1) RELLENO translúcido: TODO el area letal se ve roja desde el
					#    primer frame, pero las sierras y el fondo siguen siendo
					#    visibles a traves de la banda (no se pueden esconder).
					#    El pulso vive en el alpha de este overlay, nunca en la
					#    cobertura: no hay una ventana de peligro invisible.
					var fill_a: float = 0.10 + 0.13 * wpulse
					canvas.draw_rect(Rect2(-w_half, w_size), Color(1.0, 0.2, 0.3, fill_a * w_alpha))
					# 2) Contorno punteado de cada banda
					var warn_col := Color(1.0, 0.25, 0.35, 0.55)
					canvas.draw_dashed_line(Vector2(-w_half.x, -w_half.y), Vector2(w_half.x, -w_half.y), warn_col, 3.0, 16.0)
					canvas.draw_dashed_line(Vector2(-w_half.x, w_half.y), Vector2(w_half.x, w_half.y), warn_col, 3.0, 16.0)
					canvas.draw_dashed_line(Vector2(-w_half.x, -w_half.y), Vector2(-w_half.x, w_half.y), warn_col, 3.0, 16.0)
					canvas.draw_dashed_line(Vector2(w_half.x, -w_half.y), Vector2(w_half.x, w_half.y), warn_col, 3.0, 16.0)
					# 3) Canto del corredor: borde rojo vivo del lado que mira al hueco
					var corridor_col := Color(2.0, 0.6, 0.6, 0.5 + 0.4 * wpulse)
					canvas.draw_line(Vector2(-w_half.x, -w_half.y), Vector2(-w_half.x, w_half.y), corridor_col, 2.0 + 2.0 * wpulse)
					# 4) Linea segura punteada + chevrons que desfilan al compas
					var edge_ly: float = -w_half.y
					if (float(t["s1"]) - w_gc) > (w_gc - float(t["s0"])):
						edge_ly = w_half.y
					var safe_col := Color(1.5, 1.5, 1.5, 0.5)
					var arrow_gap: float = 150.0
					var march: float = fposmod(w_age / (4.0 * w_beat_len), 1.0) * arrow_gap
					canvas.draw_dashed_line(Vector2(-w_half.x + 60.0, gap_ly), Vector2(w_half.x - 60.0, gap_ly), safe_col, 2.5, 22.0)
					var ax0: float = -w_half.x + 60.0 - march
					while ax0 < w_half.x - 60.0:
						if ax0 >= -w_half.x + 60.0:
							var mc := Vector2(ax0, gap_ly)
							canvas.draw_colored_polygon(PackedVector2Array([
								mc + Vector2(0, -15.0), mc + Vector2(-9.0, 6.0), mc + Vector2(9.0, 6.0)]), safe_col)
						ax0 += arrow_gap
					# 5) Borde letal: linea gruesa pulsante al beat por donde entra el golpe
					canvas.draw_line(Vector2(-w_half.x, edge_ly), Vector2(w_half.x, edge_ly),
						Color(2.0, 0.5, 0.55, 0.35 + 0.5 * wpulse), 4.0 + 2.0 * wpulse)
				else:
					# Active / fade: muro translúcido con franjas que desfilan al compas.
					# La banda deja ver las sierras y el fondo; el hueco (entre
					# bandas) sigue descubierto y es el unico corredor seguro.
					canvas.draw_rect(Rect2(-w_half, w_size), Color(1.0, 0.2, 0.3, 0.30 * w_alpha))
					var stripe_n: int = maxi(6, int(w_size.x / 110.0))
					var stripe_w: float = w_size.x / float(stripe_n)
					# Las franjas avanzan 1 paso por beat, en fase con la musica
					var stripe_off: float = fposmod(w_age / w_beat_len, 1.0) * stripe_w
					for si in range(stripe_n + 1):
						var lx: float = -w_half.x - stripe_w + si * stripe_w + stripe_off
						canvas.draw_line(Vector2(lx, -w_half.y), Vector2(lx + stripe_w * 1.6, w_half.y),
							Color(0, 0, 0, 0.6 * w_alpha), 3.0)
					# Bordes HDR brillantes (largo y corto)
					canvas.draw_line(Vector2(-w_half.x, -w_half.y), Vector2(w_half.x, -w_half.y),
						Color(1.8, 0.45, 0.55, 0.9 * w_alpha), 4.0)
					canvas.draw_line(Vector2(-w_half.x, w_half.y), Vector2(w_half.x, w_half.y),
						Color(1.8, 0.45, 0.55, 0.7 * w_alpha), 3.0)
				# Esquinas: remache neón en cada vértice para que el marco
				# del muro lea bien también en diagonal.
					for wcx in [-w_half.x, w_half.x]:
						for wcy in [-w_half.y, w_half.y]:
							var wcp := Vector2(wcx, wcy)
							canvas.draw_line(wcp + Vector2(-9.0, 0.0), wcp + Vector2(9.0, 0.0), Color(2.0, 0.7, 0.8, 0.85 * w_alpha), 2.5)
							canvas.draw_line(wcp + Vector2(0.0, -9.0), wcp + Vector2(0.0, 9.0), Color(2.0, 0.7, 0.8, 0.85 * w_alpha), 2.5)
					# Canto seguro del corredor: el borde de cada banda que mira
					# al hueco se marca cian (color de carril) unos px dentro
					# del pasillo, para que siga legible mientras el muro
					# barre; pulso al beat.
					var safe_ly: float = w_half.y
					if absf(float(t["s1"]) - w_gc) < absf(float(t["s0"]) - w_gc):
						safe_ly = -w_half.y
					var safe_off: float = 10.0 if safe_ly > 0.0 else -10.0
					canvas.draw_line(Vector2(-w_half.x, safe_ly + safe_off),
						Vector2(w_half.x, safe_ly + safe_off),
						Color(0.0, 0.94, 1.0, (0.45 + 0.45 * wpulse) * w_alpha), 3.0)
					# Linea central del pasillo (punteada, tenue): el objetivo
					# visible del hueco durante el barrido.
					canvas.draw_dashed_line(Vector2(-w_half.x + 60.0, gap_ly),
						Vector2(w_half.x - 60.0, gap_ly),
						Color(1.5, 1.5, 1.5, 0.30 * w_alpha), 2.0, 26.0)
				canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"saw":
				# Sierra giratoria: disco oscuro + 8 dientes rojos que rotan
				# con el reloj real + aro neon + nucleo pulsante.
				# T9 (coherencia): lethality >= 0.75 = LETAL CON NÚCLEO
				# BLANCO HDR. Las sierras del tutorial (0.5) quedan en rojo
				# simple: se leen como "proyectil", no como "momento". Antes
				# todo era el mismo rojo saturado y el jugador no distinguía
				# un saw de un fan (space-bunny: "dos lenguajes en un frame").
				var saw_c: Vector2 = t["pos"]
				var saw_r: float = t["radius"]
				var saw_lethal: bool = _PatternLanguage.lethality_of(ttype_d) >= 0.75
				var saw_spin: float = Time.get_ticks_msec() * 0.004
				draw_spawn_warning(canvas, saw_c, saw_r, float(t.get("_age", 9.0)), view)
				# T10 (space-bunny 4a): la sierra comparte forma con el haz del
				# abanico y la onda, así que no se sabía si mataba. Ahora
				# tiene un halo tenue que la marca como PROYECTIL (se mueve
				# solo) y no como geometría del nivel (que tiene borde duro
				# y sector). El halo es la diferencia de vocabulario.
				canvas.draw_circle(saw_c, saw_r * 1.75, Color(1.0, 0.10, 0.20, 0.07))
				canvas.draw_circle(saw_c, saw_r * 1.35, Color(1.0, 0.10, 0.20, 0.05))
				canvas.draw_circle(saw_c, saw_r, Color(0.45, 0.03, 0.08, 1.0))
				for si in range(8):
					var sang: float = saw_spin + TAU * float(si) / 8.0
					var sdir := Vector2(cos(sang), sin(sang))
					canvas.draw_line(saw_c + sdir * saw_r * 0.75, saw_c + sdir * saw_r * 1.28, Color(1.0, 0.13, 0.22, 1.0), 6.0)
				neon_arc(canvas, saw_c, saw_r * 0.92, Color(1.0, 0.13, 0.22), 3.0)
				var saw_pulse: float = 0.55 + 0.08 * sin(saw_spin * 0.5)
				canvas.draw_circle(saw_c, saw_r * 0.34, Color(1.3, 0.22, 0.3, saw_pulse))
				if saw_lethal:
					# remate blanco: este saw mata y hay que leerlo como tal
					canvas.draw_circle(saw_c, saw_r * 0.16, Color(2.4, 2.0, 2.0, 0.9))
				canvas.draw_circle(saw_c, saw_r * 0.13, Color(1.6, 0.6, 0.7, 1.0))
			"drifter":
				# Mina de puas: casco oscuro + 8 puas neon + nucleo.
				var dri_c: Vector2 = t["pos"]
				var dri_r: float = t["radius"]
				var dri_bp: float = fmod(song_time / maxf(beat_interval, 0.001), 1.0)
				var dri_len: float = dri_r * (1.25 + 0.25 * clampf(1.0 - dri_bp * 5.0, 0.0, 1.0))
				draw_spawn_warning(canvas, dri_c, dri_r, float(t.get("_age", 9.0)), view)
				canvas.draw_circle(dri_c, dri_r, Color(0.38, 0.03, 0.07, 1.0))
				for di in range(8):
					var ddir := Vector2.from_angle(TAU * float(di) / 8.0 + song_time * 0.6)
					neon_line(canvas, dri_c + ddir * dri_r * 0.7, dri_c + ddir * dri_len, Color(1.0, 0.16, 0.25), 3.0)
				neon_arc(canvas, dri_c, dri_r, Color(1.0, 0.16, 0.25), 3.0)
				canvas.draw_circle(dri_c, dri_r * 0.22, Color(1.5, 0.35, 0.4, 0.9))
			"homing":
				# Misil: dardo que apunta a su velocidad + estela incandescente.
				var hom_c: Vector2 = t["pos"]
				var hom_r: float = t["radius"]
				var hom_v: Vector2 = t["vel"]
				var hom_dir := Vector2.DOWN
				if hom_v.length_squared() > 1.0:
					hom_dir = hom_v.normalized()
				var hom_perp := Vector2(-hom_dir.y, hom_dir.x)
				draw_spawn_warning(canvas, hom_c, hom_r, float(t.get("_age", 9.0)), view)
				canvas.draw_line(hom_c - hom_dir * hom_r * 0.8, hom_c - hom_dir * hom_r * 1.9, Color(1.0, 0.45, 0.1, 0.55), 7.0)
				canvas.draw_colored_polygon(PackedVector2Array([hom_c + hom_dir * hom_r * 1.1, hom_c - hom_dir * hom_r * 0.8 + hom_perp * hom_r * 0.75, hom_c, hom_c - hom_dir * hom_r * 0.8 - hom_perp * hom_r * 0.75]), Color(0.55, 0.05, 0.1, 1.0))
				neon_polyline(canvas, PackedVector2Array([hom_c + hom_dir * hom_r * 1.1, hom_c - hom_dir * hom_r * 0.8 + hom_perp * hom_r * 0.75, hom_c - hom_dir * hom_r * 0.8 - hom_perp * hom_r * 0.75, hom_c + hom_dir * hom_r * 1.1]), Color(1.0, 0.16, 0.25), 2.5)
				canvas.draw_circle(hom_c, hom_r * 0.26, Color(1.0, 0.85, 0.4, 1.0))
			"perimeter":
				# Centinela: hexagono neon que rota lento + nucleo.
				var per_c: Vector2 = t["pos"]
				var per_r: float = t["radius"]
				var per_spin: float = Time.get_ticks_msec() * 0.0012
				var per_pts := PackedVector2Array()
				for pi in range(6):
					per_pts.append(per_c + Vector2.from_angle(per_spin + TAU * float(pi) / 6.0) * per_r * 1.1)
				per_pts.append(per_pts[0])
				canvas.draw_circle(per_c, per_r * 1.1, Color(0.35, 0.03, 0.07, 1.0))
				neon_polyline(canvas, per_pts, Color(1.0, 0.16, 0.25), 3.0)
				var per_core: float = 0.5 + 0.5 * sin(per_spin * 6.0)
				canvas.draw_circle(per_c, per_r * (0.20 + 0.12 * per_core), Color(1.4, 0.3, 0.38, 0.95))
			_:
				# Default hazard: disco rojo neon con nucleo.
				var hz_c: Vector2 = t["pos"]
				var hz_r: float = t["radius"]
				draw_spawn_warning(canvas, hz_c, hz_r, float(t.get("_age", 9.0)), view)
				canvas.draw_circle(hz_c, hz_r, Color(0.5, 0.04, 0.09, 0.95))
				neon_arc(canvas, hz_c, hz_r, Color(1.0, 0.13, 0.22), 3.5)
				canvas.draw_circle(hz_c, hz_r * 0.30, Color(1.0, 0.2, 0.3, 0.9))
