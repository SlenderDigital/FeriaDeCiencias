class_name DevTools
extends RefCounted
## DevTools — todo lo que es solo-desarrollo, fuera de Gameplay.
## Menú F6, piloto autoplay (verificación grabada), capturas por tag.
## Nada de esto corre en la partida real: vive tras flags (/tmp/jsab_*,
## MCP_SHOTS) o la tecla F6. Funciones estáticas que operan sobre el
## Gameplay pasado como `g` (sin tipar, a propósito: acceso dinámico).
## La colisión que usa el piloto es la MISMA de los *Logic (ver test_pilot).

const _SpokeFanLogic: GDScript = preload("res://scripts/SpokeFanLogic.gd")
const _SweepLogic: GDScript = preload("res://scripts/SweepLogic.gd")
const _WaveformLogic: GDScript = preload("res://scripts/WaveformLogic.gd")
const _SqueezeLogic: GDScript = preload("res://scripts/SqueezeLogic.gd")
const _PulseRingsLogic: GDScript = preload("res://scripts/PulseRingsLogic.gd")
const _PilotLogic: GDScript = preload("res://scripts/PilotLogic.gd")

# Velocidad del piloto automático (px/s). Un humano con la mano es más
# rápido en algunos tramos; el piloto se limita a lo que una esquiva justa
# permite. ÚNICO lugar donde vive este número (Gameplay lo referencia).
const PILOT_SPEED: float = 520.0

# ------------------------------------------------------------------ F6
static func toggle_debug(g) -> void:
	g._debug_visible = not g._debug_visible
	if g._debug_overlay == null:
		build_debug_overlay(g)
	g._debug_overlay.visible = g._debug_visible
	# Coexist with pause: tree stays paused if EITHER wants it.
	g.get_tree().paused = g._debug_visible or g.is_paused

static func build_debug_overlay(g) -> void:
	var overlay := Control.new()
	overlay.name = "DebugMenu"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(box)

	var title := Label.new()
	title.text = "DEBUG — SALTO DE NIVEL (F6 para cerrar)"
	title.add_theme_color_override("font_color", Color(0, 0.94, 1, 1))
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	if GameManager:
		for i in range(GameManager.TRACKS.size()):
			var t: Dictionary = GameManager.TRACKS[i]
			var btn := Button.new()
			btn.text = "%d. %s  (%s)" % [i + 1, t["name"], t["difficulty"]]
			btn.custom_minimum_size = Vector2(0, 40)
			btn.pressed.connect(g._restart_with_level.bind(i))
			box.add_child(btn)

	overlay.visible = false
	g.add_child(overlay)
	g._debug_overlay = overlay

# ------------------------------------------------------------------ capturas
static func capture_shots(g) -> void:
	# [VALIDACION] temporal: graba PNGs por tag cuando el piloto verifica.
	var shots_on: bool = OS.get_environment("MCP_SHOTS") == "1" \
		or FileAccess.file_exists("/tmp/jsab_autoplay.flag")
	if not shots_on or g.is_game_over:
		return
	var spt: float = g.song_time
	if OS.get_environment("MCP_SHOT_DEBUG") == "1" and fmod(float(Time.get_ticks_msec()), 2000.0) < 20.0:
		print("[CLOCK] song_time=%.2f playing=%s paused=%s" % [spt, str(g.music.playing), str(g.music.stream_paused)])
	if spt > 8.9 and spt < 9.2 and not g.get_meta("shot_act2", false):
		g.set_meta("shot_act2", true)
		g.get_viewport().get_texture().get_image().save_png("/tmp/shot_act2.png")
	if spt > 20.5 and spt < 20.8 and not g.get_meta("shot_act3", false):
		g.set_meta("shot_act3", true)
		g.get_viewport().get_texture().get_image().save_png("/tmp/shot_act3.png")
	# Lista genérica "t=name" separada por comas (MCP_SHOT_LIST o archivo).
	var shot_list: String = OS.get_environment("MCP_SHOT_LIST")
	if FileAccess.file_exists("/tmp/jsab_shot_list.txt"):
		var f := FileAccess.open("/tmp/jsab_shot_list.txt", FileAccess.READ)
		if f:
			var from_file: String = f.get_as_text().strip_edges()
			f.close()
			if not from_file.is_empty():
				shot_list = from_file
	if shot_list.is_empty():
		return
	for entry in shot_list.split(","):
		var parts: PackedStringArray = entry.split("=")
		if parts.size() != 2:
			continue
		var want_t: float = parts[0].to_float()
		var tag: String = parts[1]
		var meta_key: String = "shot_%s" % tag
		if spt > want_t and spt < want_t + 0.35 and not g.get_meta(meta_key, false):
			g.set_meta(meta_key, true)
			var img: Image = g.get_viewport().get_texture().get_image()
			img.save_png("/tmp/shot_%s.png" % tag)
			print("[SHOT] %s @ %.2fs -> /tmp/shot_%s.png" % [tag, spt, tag])

# ------------------------------------------------------------------ piloto
## El punto que el piloto quiere alcanzar este frame. El setpiece (o jab)
## vivo MANDA —es el momento del nivel— y sólo si no hay ninguno se esquivan
## los proyectiles sueltos. La decisión es la misma que test_pilot valida
## contra la colisión real.
static func pilot_desired(g, frame_dt: float) -> Vector2:
	var player_pos: Vector2 = g.player_pos
	# 1) Si hay un setpiece/jab VIVO, él manda: es el momento del nivel.
	for t in g.targets:
		var ty_sp: String = str(t.get("type", ""))
		if ty_sp not in ["spoke_fan", "laser_sweep", "waveform_wall", "squeeze_corridor",
				"pulse_rings", "mini_ring", "mini_fan", "stripe_wall"]:
			continue
		# ¿estamos en peligro AHORA con este? -> máxima prioridad, y el punto
		# tiene que seguir libre al llegar (predicción).
		if pilot_hits(t, player_pos, player_pos):
			return pilot_safe_in_field(g, t, player_pos, frame_dt)
		# si no hay peligro inmediato, un punto seguro de este setpiece sirve
		# como destino — PERO un setpiece no es el único peligro: la sierra
		# que cayó dentro de su hueco igual mata. Buscamos el punto que sea
		# seguro para el setpiece Y para todo lo demás que esté en pantalla.
		if str(t.get("state", "")) in ["telegraph", "active"]:
			return pilot_safe_in_field(g, t, player_pos, frame_dt)
	# 2) Sólo proyectiles sueltos: el punto LIBRE más cercano.
	return best_free_spot(g, frame_dt)

## ¿el punto está dentro de este objetivo? Usa la MISMA colisión del juego.
static func pilot_hits(t: Dictionary, p: Vector2, player_pos: Vector2) -> bool:
	var ty: String = str(t.get("type", ""))
	match ty:
		"spoke_fan":
			return _SpokeFanLogic.hits_player(t, p)
		"laser_sweep":
			return _SweepLogic.hits_player(t, p)
		"waveform_wall":
			return _WaveformLogic.hits_player(t, p)
		"squeeze_corridor":
			return _SqueezeLogic.hits_player(t, p)
		"pulse_rings":
			return _PulseRingsLogic.hits_player(t, p)
		"saw", "homing", "drifter", "saw_pair", "saw_weave", "drifter_swarm":
			if t.has("pos"):
				return player_pos.distance_to(t["pos"]) < 90.0
	return false

## El punto de refugio del setpiece, VERIFICADO contra TODA la geometría viva.
static func pilot_safe_in_field(g, anchor: Dictionary, from: Vector2, frame_dt: float) -> Vector2:
	var base: Vector2 = _PilotLogic.safe_point_eta(anchor, from, PILOT_SPEED, frame_dt)
	if not field_blocks(g, base):
		return base
	# el punto del setpiece está tapado por otra cosa: buscamos alrededor
	var hub: Vector2 = anchor.get("pos", Vector2(640, 400))
	for r_i in range(7):
		for a_i in range(20):
			var rr: float = lerpf(110.0, 430.0, float(r_i) / 6.0)
			var aa: float = TAU * float(a_i) / 20.0
			var c: Vector2 = Vector2(clampf(hub.x + cos(aa) * rr, 90.0, 1190.0),
				clampf(hub.y + sin(aa) * rr, 200.0, 630.0))
			if not field_blocks(g, c) and not pilot_hits(anchor, c, from):
				return c
	for gx in [160.0, 380.0, 640.0, 900.0, 1120.0]:
		for gy in [220.0, 400.0, 560.0]:
			var gp: Vector2 = Vector2(gx, gy)
			if not field_blocks(g, gp) and not pilot_hits(anchor, gp, from):
				return gp
	# todo tapado: nos alejamos del hub, que es lo menos malo
	return Vector2(clampf(from.x, 120.0, 1160.0), clampf(from.y - 200.0, 200.0, 600.0))

## ¿Algún peligro (de cualquier tipo) ocupa este punto?
static func field_blocks(g, p: Vector2) -> bool:
	for t in g.targets:
		if pilot_hits(t, p, g.player_pos):
			return true
	return false

## El punto LIBRE más cercano: puntúa una rejilla de candidatos contra TODA
## la geometría viva y elige el más seguro y alcanzable.
static func best_free_spot(g, frame_dt: float) -> Vector2:
	var player_pos: Vector2 = g.player_pos
	var best: Vector2 = player_pos
	var best_score: float = -1.0e9
	var steps_x: int = 8
	var steps_y: int = 5
	for ix in range(steps_x + 1):
		for iy in range(steps_y + 1):
			var c: Vector2 = Vector2(lerpf(90.0, 1190.0, float(ix) / float(steps_x)),
				lerpf(200.0, 630.0, float(iy) / float(steps_y)))
			# ¿libre ahora?
			var clear_now: bool = true
			for t in g.targets:
				if pilot_hits(t, c, player_pos):
					clear_now = false
					break
			if not clear_now:
				continue
			# ¿libre al llegar? (el juego sigue corriendo mientras viaja)
			var clear_eta: bool = true
			var dist: float = c.distance_to(player_pos)
			var n_steps: int = clampi(int(ceil(dist / maxf(PILOT_SPEED * frame_dt, 1.0))) + 1, 1, 24)
			for s in range(1, n_steps + 1):
				var p: Vector2 = player_pos.lerp(c, float(s) / float(n_steps))
				for t2 in g.targets:
					if pilot_hits(t2, p, player_pos):
						clear_eta = false
						break
				if not clear_eta:
					break
			if not clear_eta:
				continue
			# Puntaje: seguridad (ya filtrada) + centro + fila del jugador + cercanía
			var score: float = 200.0
			score -= dist * 0.35
			score -= absf(c.y - 470.0) * 0.25
			for t3 in g.targets:
				if t3.has("pos"):
					score += minf(c.distance_to(t3["pos"]), 400.0) * 0.18
			if score > best_score:
				best_score = score
				best = c
	return best
