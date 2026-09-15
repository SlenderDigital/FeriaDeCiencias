extends Node2D
## Gameplay — Rhythm Action Gameplay Scene for Abstract Pulse
## Runs the procedural MVP level, handles arrow key movement, spawns algorithmic beats/hazards, tracks score/health, and manages game loop overlays.

@onready var bg_control: Control = $BackgroundLayer/Background
@onready var track_title_lbl: Label = $HUDLayer/HUD/TopBar/TrackTitle
@onready var score_lbl: Label = $HUDLayer/HUD/TopBar/ScoreLabel
@onready var progress_bar: ProgressBar = $HUDLayer/HUD/BottomBar/ProgressBar
@onready var pause_overlay: Control = $HUDLayer/PauseOverlay
@onready var results_overlay: Control = $HUDLayer/ResultsOverlay
@onready var results_title_lbl: Label = $HUDLayer/ResultsOverlay/Panel/VBox/Title
@onready var results_score_lbl: Label = $HUDLayer/ResultsOverlay/Panel/VBox/ScoreDetails
@onready var music: AudioStreamPlayer = $MusicPlayer

var generator: ProceduralLevelGenerator
var chart: ChartData
var controller: PatternController
var song: ProceduralSong
var next_beat_idx: int = 0
var track_data: Dictionary = {}
var bpm: float = 132.0
var song_time: float = 0.0
var total_song_duration: float = 60.0 # 60 seconds procedural MVP level
var beat_interval: float = 60.0 / 132.0
var beat_timer: float = 0.0

var player_pos: Vector2 = Vector2(640, 560)
var ship_rotation: float = 0.0    # grados; 0 = proa hacia +X (derecha)
# (player_pos se re-centra al área real en _ready())
var player_speed: float = 550.0
# Estela de la nave: última posición donde se soltó una chispa de motor.
var _trail_last: Vector2 = Vector2(-9999.0, -9999.0)

# Escudo: invulnerabilidad temporal (atraviesa todo sin colisionar) + delay de recarga
const SHIELD_TIME: float = 1.2
const SHIELD_COOLDOWN: float = 3.0
var _shield_active: float = 0.0
var _shield_cooldown: float = 0.0
# Invulnerabilidad post-golpe: maximo UN impacto cada HIT_IFRAMES segundos.
# Durante el lapso los peligros tocan la nave y se consumen sin drenar vida.
const HIT_IFRAMES: float = 1.5
var _hit_iframes: float = 0.0
# Juice de daño: flash rojo de pantalla + vibracion al recibir un golpe.
const SHAKE_TIME: float = 0.25
const SHAKE_AMP: float = 12.0
var _damage_flash: float = 0.0
var _shake_time: float = 0.0
var _damage_overlay: ColorRect
var _shield_was_ready: bool = true   # para sonido de "listo" al recargarse
var health: float = 100.0
var progress_pct: int = 0   # % de la canción sobrevivida: la métrica del nivel
var is_paused: bool = false
var is_game_over: bool = false
var _music_finished: bool = false

# Spawns (todo es peligro: hazards, muros, láseres) & Effects
var targets: Array[Dictionary] = []
var spark_effects: Array[Dictionary] = []

# --- Debug menu (F6) ---
var _debug_overlay: Control = null
var _debug_visible: bool = false

# Tamaño real del área de juego (pantalla completa con stretch=expand).
# Todo el spawn/movimiento/dibujo usa esto en vez de 1280x720 fijo.
func play_size() -> Vector2:
	var s: Vector2 = get_viewport_rect().size
	if s == Vector2.ZERO:
		return Vector2(1280, 720)
	return s

func _ready() -> void:
	var seed_val: int = 1337
	if GameManager:
		track_data = GameManager.get_current_track()
		seed_val = GameManager.procedural_seed
	else:
		track_data = {
			"name": "Nivel Procedural MVP",
			"bpm": 132,
			"color": Color(0, 0.94, 1, 1),
			"id": "procedural_mvp"
		}
		
	generator = ProceduralLevelGenerator.new(seed_val, play_size().x)
	bpm = track_data.get("bpm", 132.0)
	beat_interval = 60.0 / bpm

	_setup_neon_glow()
	
	# Real music + chart-driven path (when track_data carries chart files)
	if track_data.has("audio") and track_data.has("analysis") and track_data.has("level"):
		chart = ChartData.load_charts(track_data["analysis"], track_data["level"])
		if not chart.beat_times.is_empty():
			controller = PatternController.new(chart, play_size(), bpm, hash(str(track_data.get("id", "track"))))
			music.stream = load(track_data["audio"]) as AudioStream
			bpm = chart.bpm
			total_song_duration = chart.duration
			beat_interval = 60.0 / bpm
			music.play()
			music.finished.connect(func(): _music_finished = true)
	elif track_data.get("procedural", false) == true:
		# Canción COMPUESTA por el motor: audio y chart nacen de la misma fuente
		song = ProceduralSong.new(seed_val, track_data.get("bpm", 128.0))
		chart = song.build_chart()
		# Seed por id de track: mismo nivel para la misma cancion, siempre
		controller = PatternController.new(chart, play_size(), bpm, hash(str(track_data.get("id", "track"))))
		music.stream = song.render_audio()
		bpm = chart.bpm
		total_song_duration = chart.duration
		beat_interval = 60.0 / bpm
		music.play()
		music.finished.connect(func(): _music_finished = true)
	
	if track_title_lbl:
		track_title_lbl.text = "%s  |  BPM: %d" % [track_data.get("name", "Nivel Procedural"), int(bpm)]
		track_title_lbl.add_theme_color_override("font_color", track_data.get("color", Color(0, 0.94, 1, 1)))
		
	pause_overlay.visible = false
	results_overlay.visible = false
	# Overlay de daño: destello rojo full-screen sobre el mundo (bajo el HUD,
	# que vive en CanvasLayer layer=10).
	_damage_overlay = ColorRect.new()
	_damage_overlay.color = Color(1.0, 0.08, 0.14, 0.0)
	_damage_overlay.size = get_viewport_rect().size
	_damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_overlay)
	print("[Gameplay] Nivel iniciado: ", track_data.get("name", "Procedural MVP"), " (bpm=", bpm, ", chart=", chart != null, ")")
	player_pos = Vector2(play_size().x * 0.5, play_size().y * 0.78)  # nave arranca abajo-centro del área real

func _notification(what: int) -> void:
	# Re-centrar la nave si el tamaño del viewport cambia (ej. entrar/salir de fullscreen)
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		var ps: Vector2 = play_size()
		if controller:
			controller.play_size = ps
		player_pos.x = clamp(player_pos.x, 50, ps.x - 50)
		player_pos.y = clamp(player_pos.y, 80, ps.y - 50)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F6:
		_toggle_debug_menu()
		return
	if event.is_action_pressed("ui_cancel"): # ESC key
		toggle_pause()
	elif not is_paused and not is_game_over:
		# Shield on Space, Enter, or Mouse Click
		if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
			_try_shield()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_try_shield()

func toggle_pause() -> void:
	if is_game_over:
		return
	is_paused = not is_paused
	pause_overlay.visible = is_paused
	get_tree().paused = is_paused
	if SoundManager: SoundManager.play_click()


# --- Debug: saltar entre niveles al instante (F6) ---
func _toggle_debug_menu() -> void:
	_debug_visible = not _debug_visible
	if _debug_overlay == null:
		_build_debug_overlay()
	_debug_overlay.visible = _debug_visible
	get_tree().paused = _debug_visible


func _build_debug_overlay() -> void:
	_debug_overlay = Control.new()
	_debug_overlay.name = "DebugMenu"
	_debug_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_debug_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_debug_overlay.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_debug_overlay.add_child(box)

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
			btn.pressed.connect(_restart_with_level.bind(i))
			box.add_child(btn)

	_debug_overlay.visible = false
	add_child(_debug_overlay)


func _restart_with_level(index: int) -> void:
	if GameManager and index >= 0 and index < GameManager.TRACKS.size():
		GameManager.select_track(index)
	get_tree().paused = false
	if GameManager:
		GameManager.change_scene("res://scenes/Gameplay.tscn")
	else:
		get_tree().reload_current_scene()


func _process(delta: float) -> void:
	# [VALIDACION] temporal
	if OS.get_environment("MCP_SHOTS") == "1" and not is_game_over:
		var spt: float = song_time
		if spt > 8.9 and spt < 9.2 and not get_meta("shot_act2", false):
			set_meta("shot_act2", true)
			get_viewport().get_texture().get_image().save_png("/tmp/shot_act2.png")
		if spt > 20.5 and spt < 20.8 and not get_meta("shot_act3", false):
			set_meta("shot_act3", true)
			get_viewport().get_texture().get_image().save_png("/tmp/shot_act3.png")
	if is_paused or is_game_over:
		return
		
	# Anchor game clock to real audio playback when chart-driven; otherwise fall
	# back to the procedural delta-accumulated clock.
	if chart != null and music.playing:
		song_time = music.get_playback_position()
	else:
		song_time += delta
	
	var progress: float = clamp(song_time / total_song_duration, 0.0, 1.0)
	
	# Update song progress & phase HUD
	if progress_bar:
		progress_bar.value = progress * 100.0
	_update_hud_progress(progress)
		
	if track_title_lbl:
		if chart != null:
			track_title_lbl.text = "%s  |  BPM: %d" % [track_data.get("name", "Nivel"), int(bpm)]
		elif generator:
			var phase_str: String = generator.get_phase_name(progress)
			track_title_lbl.text = "%s  |  %s" % [track_data.get("name", "Nivel Procedural"), phase_str]
		
	# Check level completion
	if chart != null:
		# Victory only when the music has genuinely reached the end of the
		# track, per the real playback clock. `music.finished` is a Signal
		# (always truthy if used as a bool), so we track actual completion
		# via a signal-connected flag and guard both paths with an elapsed
		# time margin to avoid an instant-win on the first frames.
		var reached_end: bool = song_time >= chart.duration and song_time > 1.0
		if reached_end or (_music_finished and song_time > 1.0):
			_trigger_victory()
			return
	else:
		if song_time >= total_song_duration:
			_trigger_victory()
			return
		
	# --- Spawning: chart-driven beats from the real playback pointer, else procedural waves
	if chart != null:
		var track_color: Color = track_data.get("color", Color(0, 0.94, 1, 1))
		while next_beat_idx < chart.beat_times.size() and chart.beat_times[next_beat_idx] <= song_time:
			var t: float = chart.beat_times[next_beat_idx]
			
			# Regular beat spawns
			var spawns: Array[Dictionary] = controller.spawns_at(t, next_beat_idx, track_color)
			for s in spawns:
				_notify_spawn(s)
				targets.append(s)
			
			# Downbeat patterns (every 4 beats) - big patterns
			if chart.downbeat[next_beat_idx]:
				# Gate: un solo stripe_wall a la vez (no se apilan muros)
				var has_wall := false
				for tg in targets:
					if tg.get("type", "") == "stripe_wall":
						has_wall = true
						break
				# El muro activo silencia los acentos rojos (PatternController)
				controller.wall_active = has_wall
				if not has_wall:
					for s in controller.spawns_at_downbeat(t, next_beat_idx, track_color):
						_notify_spawn(s)
						targets.append(s)
			
			# Bar patterns (every 4 beats = every downbeat) - variations
			if next_beat_idx % 4 == 0:
				for s in controller.spawns_at_bar(t, next_beat_idx, track_color):
					_notify_spawn(s)
					targets.append(s)
			
			# Phrase patterns (every 16 beats) - setpieces / new mechanics
			if next_beat_idx % 16 == 0:
				for s in controller.spawns_at_phrase(t, next_beat_idx, track_color):
					_notify_spawn(s)
					targets.append(s)
			
			next_beat_idx += 1
	else:
		beat_timer += delta
		if beat_timer >= beat_interval:
			beat_timer -= beat_interval
			_spawn_procedural_wave()
			if SoundManager: SoundManager.play_beat()
		
	_update_player_movement(delta)
	_update_targets(delta)
	_update_shield(delta)
	_update_sparks(delta)
	
	queue_redraw()

func _notify_spawn(s: Dictionary) -> void:
	# Avisos sonoros al nacer un spawn que lo requiera.
	# Vive en Gameplay (no en PatternController) para que el E2E headless
	# pueda instanciar el controller sin autoloads de escena.
	if s.get("type", "") == "laser_telegraph" and SoundManager:
		SoundManager.play_warning()

func _update_player_movement(delta: float) -> void:
	# Con mano: posicion absoluta de la palma + rotacion pulgar->indice (port de Player.cpp)
	if HandTrackingClient and HandTrackingClient.has_hand:
		var ps: Vector2 = play_size()
		var target: Vector2 = HandTrackingClient.get_palm_center() * ps
		var alpha: float = 1.0 - exp(-25.0 * delta)
		player_pos = player_pos.lerp(target, alpha)
		var ang := HandTrackingClient.get_hand_angle_deg()
		if ang < 9990.0:
			_smooth_rotation_toward(ang, delta)
		player_pos.x = clamp(player_pos.x, 50, ps.x - 50)
		player_pos.y = clamp(player_pos.y, 80, ps.y - 50)
		return

	# Fallback sin mano: flechas / WASD (movimiento por velocidad)
	var move_dir: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		move_dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		move_dir.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		move_dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		move_dir.y += 1.0
		
	if move_dir != Vector2.ZERO:
		player_pos += move_dir.normalized() * player_speed * delta
	
	# Keep ship safely inside screen bounds
	var ps2: Vector2 = play_size()
	player_pos.x = clamp(player_pos.x, 50, ps2.x - 50)
	player_pos.y = clamp(player_pos.y, 80, ps2.y - 50)

func _setup_neon_glow() -> void:
	# Bloom neon REAL del motor: requiere project setting
	# rendering/viewport/hdr_2d=true + Environment con glow aditivo.
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# Niveles de glow: medios para las luces grandes, chico para núcleos finos
	env.set_glow_level(2, 1.0)
	env.set_glow_level(4, 0.8)
	env.set_glow_level(5, 0.6)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _neon_polyline(points: PackedVector2Array, c: Color, w: float) -> void:
	# Trazo neón: halo ancho translúcido + capa media + núcleo HDR (>1.0
	# dispara el bloom del Environment glow).
	draw_polyline(points, Color(c.r, c.g, c.b, 0.20), w * 3.4)
	draw_polyline(points, Color(c.r, c.g, c.b, 0.5), w * 1.9)
	draw_polyline(points, Color(minf(c.r * 1.7, 4.0), minf(c.g * 1.7, 4.0), minf(c.b * 1.7, 4.0), 1.0), w)

func _neon_line(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	draw_line(a, b, Color(c.r, c.g, c.b, 0.20), w * 3.4)
	draw_line(a, b, Color(c.r, c.g, c.b, 0.5), w * 1.9)
	draw_line(a, b, Color(minf(c.r * 1.7, 4.0), minf(c.g * 1.7, 4.0), minf(c.b * 1.7, 4.0), 1.0), w)

func _neon_arc(center: Vector2, r: float, c: Color, w: float) -> void:
	draw_arc(center, r, 0, TAU, 32, Color(c.r, c.g, c.b, 0.18), w * 3.2)
	draw_arc(center, r, 0, TAU, 32, Color(c.r, c.g, c.b, 0.5), w * 1.7)
	draw_arc(center, r, 0, TAU, 32, Color(minf(c.r * 1.7, 4.0), minf(c.g * 1.7, 4.0), minf(c.b * 1.7, 4.0), 1.0), w)

func _smooth_rotation_toward(target_deg: float, delta: float) -> void:
	var diff := wrapf(target_deg - ship_rotation, -180.0, 180.0)
	var alpha: float = 1.0 - exp(-22.0 * delta)
	ship_rotation += diff * alpha

func _spawn_procedural_wave() -> void:
	if not generator:
		return
		
	var base_col: Color = track_data.get("color", Color(0, 0.94, 1, 1))
	var new_items: Array[Dictionary] = generator.generate_beat_spawn(song_time, total_song_duration, base_col)
	for item in new_items:
		targets.append(item)

func _try_shield() -> void:
	# Delay: bloqueado mientras el escudo activo corre o la recarga no termino
	if _shield_active > 0.0 or _shield_cooldown > 0.0:
		return
	_shield_active = SHIELD_TIME
	_shield_cooldown = SHIELD_COOLDOWN
	if SoundManager: SoundManager.play_beat()

func _update_shield(delta: float) -> void:
	if _shield_active > 0.0:
		_shield_active = maxf(_shield_active - delta, 0.0)
	if _shield_cooldown > 0.0:
		_shield_cooldown = maxf(_shield_cooldown - delta, 0.0)
		if _shield_cooldown == 0.0:
			if not _shield_was_ready and SoundManager:
				SoundManager.play_click()
			_shield_was_ready = true
	else:
		_shield_was_ready = false
	# Invulnerabilidad post-golpe y decay del juice de daño
	if _hit_iframes > 0.0:
		_hit_iframes = maxf(_hit_iframes - delta, 0.0)
	if _damage_flash > 0.0:
		_damage_flash = maxf(_damage_flash - delta * 3.5, 0.0)
	if _shake_time > 0.0:
		_shake_time = maxf(_shake_time - delta, 0.0)
	if _damage_overlay:
		_damage_overlay.color.a = _damage_flash * 0.35

func is_shielded() -> bool:
	return _shield_active > 0.0

func _update_targets(delta: float) -> void:
	var to_remove: Array[int] = []
	for i in range(targets.size()):
		var t: Dictionary = targets[i]
		
		# Handle movement based on type
		var ttype: String = t.get("type", "target")
		if ttype == "homing":
			# Homing projectile chases player
			var dir = (player_pos - t["pos"]).normalized()
			t["vel"] = t["vel"].lerp(dir * 250.0, 0.1)
		elif ttype == "laser_telegraph":
			# Telegraph counts down, then fires
			var telegraph_time: float = t.get("telegraph_time", 1.0)
			telegraph_time -= delta
			t["telegraph_time"] = telegraph_time
			if telegraph_time <= 0.0 and not t.get("fired", false):
				# Fire the laser - beam instantáneo a lo largo de su dirección
				t["fired"] = true
				t["type"] = "laser_beam"
				t["is_hazard"] = true
				t["lifetime"] = 0.45
				print("[LASER] beam FIRED dir=%s anchor=%s" % [t.get("beam_dir", Vector2.UP), t["pos"]])
		elif ttype == "laser_beam":
			# Laser beam persists for a short duration then removes
			var lifetime: float = t.get("lifetime", 0.5)
			lifetime -= delta
			if lifetime <= 0.0:
				to_remove.append(i)
				continue
			t["lifetime"] = lifetime
		elif ttype == "perimeter":
			# Perimeter balls move toward center
			t["pos"] += t["vel"] * delta
			# Check if reached center
			if t["pos"].distance_to(play_size() * 0.5) < 50:
				to_remove.append(i)
				continue
		elif ttype == "stripe_wall":
			# Ciclo de vida musical: warning (aviso, quieto) -> active (barrido
			# sincronizado) -> fade. "age" marca el compas del muro: como nace en
			# un downbeat, los pulsos visuales caen en los acentos de la cancion.
			t["age"] = float(t.get("age", 0.0)) + delta
			var wstate: String = t.get("state", "active")
			if wstate == "warning":
				var wt: float = t.get("warn_time", 1.2) - delta
				t["warn_time"] = wt
				if wt <= 0.0:
					t["state"] = "active"
					t["age"] = 0.0  # el compas del barrido arranca en el acento musical
			elif wstate == "active":
				var wn: Vector2 = t["wall_n"]
				# Velocidad MUSICAL LENTA: medio carril (64px de la grilla) por
				# beat, o sea 2 carriles por compas: entra en un downbeat y da
				# el doble de tiempo de reaccion para cruzar el hueco.
				var step: float = 64.0 * delta / beat_interval
				t["pos"] = (t["pos"] as Vector2) + wn * step
				t["s0"] = float(t["s0"]) + step
				t["s1"] = float(t["s1"]) + step
				# El hueco (y sus marcadores) barre junto con el muro.
				t["gap_center"] = float(t["gap_center"]) + step
				var at: float = t.get("active_time", 1.6) - delta
				t["active_time"] = at
				if at <= 0.0:
					t["state"] = "fade"
			else:
				var ft: float = t.get("fade_time", 0.4) - delta
				t["fade_time"] = ft
				t["alpha"] = clampf(ft / maxf(t.get("fade_total", 0.4), 0.001), 0.0, 1.0)
				if ft <= 0.0:
					to_remove.append(i)
					continue
		else:
			# Standard movement
			t["pos"] += t["vel"] * delta
		
		# Telegraph inofensivo: es solo el aviso; el daño lo hace el beam.
		if ttype == "laser_telegraph":
			continue

		# Check collision with player ship (con escudo activo: atravesar todo,
		# sin recibir daño)
		if _shield_active > 0.0:
			continue
		var hit: bool = false
		if ttype == "stripe_wall":
			# Rect-based orientado: proyecta el player en el eje de avance n.
			# Solo daña en fase active (en warning/fade es inofensivo).
			var s_p: float = player_pos.dot(t["wall_n"])
			hit = t.get("state", "active") == "active" \
					and s_p > float(t["s0"]) - 16.0 and s_p < float(t["s1"]) + 16.0
		elif ttype == "laser_beam":
			# Line-based: distancia del player a la línea infinita del beam
			var bdir: Vector2 = (t.get("beam_dir", Vector2.UP) as Vector2).normalized()
			var to_p: Vector2 = player_pos - (t["pos"] as Vector2)
			var perp: float = absf(to_p.dot(Vector2(-bdir.y, bdir.x)))
			hit = perp < float(t["radius"]) + 16.0
		else:
			hit = player_pos.distance_to(t["pos"]) < (t["radius"] + 16.0)
		if hit:
			to_remove.append(i)
			# I-frames: durante el lapso post-golpe el peligro se consume sin drenar vida
			if _hit_iframes <= 0.0:
				_on_hazard_hit()
			continue

		# Fuera de pantalla (stripe_wall se autogestiona su ciclo)
		if ttype != "stripe_wall" and t["pos"].y > 740:
			to_remove.append(i)
				
	to_remove.reverse()
	for idx in to_remove:
		if idx < targets.size():
			targets.remove_at(idx)

func _on_hazard_hit() -> void:
	_hit_iframes = HIT_IFRAMES
	_damage_flash = 1.0
	_shake_time = SHAKE_TIME
	health -= 18.0
	if SoundManager: SoundManager.play_back()
	
	if health <= 0:
		_trigger_game_over()

func _health_color() -> Color:
	## Color de vida compartido: lo usan el anillo de la nave y (antes) la
	## barra. Verde >60, ambar >30, rojo pulsante en critico.
	if health > 60.0:
		return Color(0.2, 1.0, 0.45)
	elif health > 30.0:
		return Color(1.0, 0.85, 0.1)
	# Pulso critico: el alpha del rojo oscila ~2.5 veces por segundo
	return Color(1.0, 0.15, 0.2, 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.016)))

func _update_hud_progress(p: float) -> void:
	## Progreso del nivel: % de la canción sobrevivida (métrica principal).
	progress_pct = int(clampf(p, 0.0, 1.0) * 100.0)
	if score_lbl:
		score_lbl.text = "PROGRESO: %d%%" % progress_pct

func _add_sparks(pos: Vector2, col: Color) -> void:
	for i in range(8):
		var ang: float = randf_range(0, TAU)
		var spd: float = randf_range(120, 280)
		spark_effects.append({
			"pos": pos,
			"vel": Vector2(cos(ang), sin(ang)) * spd,
			"color": col,
			"life": 0.3
		})

func _update_sparks(delta: float) -> void:
	var rem: Array[int] = []
	for i in range(spark_effects.size()):
		var s: Dictionary = spark_effects[i]
		s["pos"] += s["vel"] * delta
		s["life"] -= delta
		if s["life"] <= 0:
			rem.append(i)
			
	rem.reverse()
	for idx in rem:
		spark_effects.remove_at(idx)

func _trigger_victory() -> void:
	is_game_over = true
	var is_new_hs: bool = false
	if GameManager:
		is_new_hs = GameManager.save_score(track_data.get("id", "procedural_mvp"), 100)

	results_title_lbl.text = "¡NIVEL PROCEDURAL COMPLETADO!"
	results_title_lbl.add_theme_color_override("font_color", Color(0, 1, 0.5, 1))
	results_score_lbl.text = "Progreso Final: 100%%\n%s" % ("¡NUEVO RÉCORD DE PROGRESO!" if is_new_hs else "")
	results_overlay.visible = true

func _trigger_game_over() -> void:
	is_game_over = true
	var is_new_hs: bool = false
	if GameManager:
		is_new_hs = GameManager.save_score(track_data.get("id", "procedural_mvp"), progress_pct)
	results_title_lbl.text = "MISIÓN FALLIDA"
	results_title_lbl.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 1))
	results_score_lbl.text = "Progreso Logrado: %d%%\n%s" % [progress_pct, ("¡NUEVO RÉCORD DE PROGRESO!" if is_new_hs else "")]
	results_overlay.visible = true

# --- Pause & Results Overlay Signals ---

func _on_btn_resume_pressed() -> void:
	toggle_pause()

func _on_btn_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_btn_main_menu_pressed() -> void:
	get_tree().paused = false
	if GameManager:
		GameManager.change_scene("res://scenes/MainMenu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _draw() -> void:
	# Vibracion de pantalla (juice): offset aleatorio decreciente mientras
	# _shake_time corre. Afecta TODO el mundo dibujado, no el HUD.
	if _shake_time > 0.0:
		var sk: float = pow(_shake_time / SHAKE_TIME, 2.0) * SHAKE_AMP
		draw_set_transform(Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * sk, 0.0, Vector2.ONE)
	# Pulso visual sincronizado con la música: flash de kick en cada beat,
	# anillo expansivo en los hits de snare (beats 2 y 4 del compás).
	if song_time > 0.0 and not is_game_over and beat_interval > 0.0:
		var bn: float = song_time / beat_interval
		var in_bar: float = fmod(bn, 4.0)
		var bp: float = fmod(bn, 1.0)
		var kick: float = clampf(1.0 - bp * 6.0, 0.0, 1.0)
		if kick > 0.0:
			draw_rect(Rect2(Vector2.ZERO, play_size()),
					Color(0.35, 0.55, 1.0, 0.03 * kick))
		if (in_bar >= 1.0 and in_bar < 1.25) or (in_bar >= 3.0 and in_bar < 3.25):
			var sr: float = clampf(fmod(in_bar, 1.0) * 4.0, 0.0, 1.0)
			draw_arc(play_size() * 0.5, 40.0 + sr * 90.0, 0, TAU, 44,
					Color(0.5, 0.8, 1.0, 0.11 * (1.0 - sr)), 3.0)

	# Draw player ship (neon, rotada por la mano; 0deg = derecha)
	var ship_col: Color = track_data.get("color", Color(0, 0.94, 1, 1))
	# Parpadeo de la nave durante la invulnerabilidad post-golpe
	var ship_blink: float = 1.0
	if _hit_iframes > 0.0:
		ship_blink = 0.35 + 0.65 * absf(sin(Time.get_ticks_msec() * 0.022))
		ship_col.a *= ship_blink
	var rad: float = deg_to_rad(ship_rotation)
	var fwd := Vector2.from_angle(rad)          # linea de proa
	var perp := Vector2(-fwd.y, fwd.x)          # perpendicular
	var nose: Vector2 = player_pos + fwd * 24.0
	var p2: Vector2 = player_pos + (-fwd * 11.0 + perp * 18.0)
	var p3: Vector2 = player_pos + (-fwd * 11.0 - perp * 18.0)
	_neon_polyline(PackedVector2Array([nose, p2, p3, nose]), ship_col, 4.0)
	_neon_line(player_pos, player_pos + fwd * 28.0, Color(1, 1, 1, ship_blink), 2.0)
	draw_circle(player_pos, 5.0, Color(1.0, 1.0, 1.0, ship_blink))
	# VIDA EN LA NAVE: anillo concentrico r=27 (nave r~24, escudo r=34: no se
	# pisan). Fondo tenue + frente con el color de vida (verde/ambar/rojo
	# pulsante). El parpadeo de i-frames NO lo toca: la vida sigue legible.
	var hp_frac: float = clampf(health / 100.0, 0.0, 1.0)
	var hp_col: Color = _health_color()
	var hp_dim: float = 0.7 if _shield_active > 0.0 else 1.0  # la burbuja manda
	draw_arc(player_pos, 27.0, 0, TAU, 48, Color(0.1, 0.1, 0.14, 0.75 * hp_dim), 7.0)
	if hp_frac > 0.0:
		var hp_soft := Color(hp_col.r, hp_col.g, hp_col.b, 0.9 * hp_dim)
		draw_arc(player_pos, 27.0, -PI / 2.0, -PI / 2.0 + TAU * hp_frac, 48, hp_soft, 7.0)
		var hp_hot := Color(minf(hp_col.r + 0.6, 2.0), minf(hp_col.g + 0.6, 2.0), minf(hp_col.b + 0.6, 2.0), hp_dim)
		draw_arc(player_pos, 27.0, -PI / 2.0, -PI / 2.0 + TAU * hp_frac, 48, hp_hot, 2.5)
	# Relleno de la flecha: la nave "se vacia" al perder vida (redundancia
	# cercana al anillo; el contorno neon queda intacto).
	var hp_fill := hp_col
	hp_fill.a = (0.10 + 0.35 * hp_frac) * ship_blink * hp_dim
	draw_colored_polygon(PackedVector2Array([nose, p2, p3]), hp_fill)
	# Estela del motor: chispa color carril en la popa cada 14px de viaje.
	if _trail_last.distance_to(player_pos) > 14.0:
		_trail_last = player_pos
		spark_effects.append({
			"pos": player_pos - fwd * 12.0,
			"vel": -fwd * 60.0 + Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0)),
			"color": Color(ship_col.r, ship_col.g, ship_col.b, 1.0),
			"life": 0.3})
	
	# Draw spark particles
	for s in spark_effects:
		var alpha: float = clamp(s["life"] / 0.3, 0.0, 1.0)
		var c: Color = s["color"]
		c.a = alpha
		draw_circle(s["pos"], 2.5, c)
		
	# Escudo: burbuja hexagonal-neon alrededor de la nave mientras activo
	if _shield_active > 0.0:
		var life: float = clampf(_shield_active / SHIELD_TIME, 0.0, 1.0)
		var tnow: float = Time.get_ticks_msec() * 0.001
		var wob: float = sin(tnow * 14.0) * 1.5
		# Burbuja: hexagono con vertices que respiran
		var pts := PackedVector2Array()
		for vi in range(6):
			var va: float = TAU * float(vi) / 6.0 + tnow * 1.2
			pts.append(player_pos + Vector2.from_angle(va) * (30.0 + wob + 4.0 * life))
		pts.append(pts[0])
		_neon_polyline(pts, Color(0.55, 1.0, 1.0, 0.35 + 0.55 * life), 2.5)
		draw_circle(player_pos, 30.0 + wob, Color(0.55, 1.0, 1.0, 0.07 * life))
		# Aviso de fin: parpadea mas rapido cuanto menos vida le queda
		if life < 0.35 and fposmod(tnow * (4.0 + 20.0 * (0.35 - life)), 1.0) < 0.5:
			_neon_arc(player_pos, 30.0, Color(0.4, 0.9, 1.0, 0.4), 1.5)

	# Cooldown del escudo: anillo de recarga alrededor de la nave
	if _shield_cooldown > 0.0:
		var frac: float = 1.0 - clampf(_shield_cooldown / SHIELD_COOLDOWN, 0.0, 1.0)
		draw_arc(player_pos, 34.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 24,
				Color(0.5, 0.95, 1.0, 0.4 + 0.4 * frac), 4.0)
	else:
		# listo: pulso tenue para avisar que el escudo volvio a cargar
		var tnow2: float = Time.get_ticks_msec() * 0.001
		var pulse: float = 0.5 + 0.5 * sin(tnow2 * 6.0)
		draw_arc(player_pos, 34.0 + 2.0 * pulse, 0, TAU, 28,
				Color(0.5, 0.95, 1.0, 0.28 + 0.20 * pulse), 2.5)

	# Draw targets & hazards
	for t in targets:
		var ttype_d: String = t.get("type", "target")
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
			var beam_len: float = (play_size().x + play_size().y) * 0.5
			draw_line(c - bdir * beam_len, c + bdir * beam_len, Color(1.0, 0.15, 0.15, 0.30), lw + 7.0)
			draw_line(c - bdir * beam_len, c + bdir * beam_len, Color(1.0, 0.85, 0.1, 0.35 + 0.6 * blink), lw)
			# Anillos de alarma expandiéndose desde el ancla
			var ring_t: float = fmod(now_s * 2.2, 1.0)
			var ring_r: float = 8.0 + ring_t * 40.0
			draw_arc(c, ring_r, 0, TAU, 24, Color(1.0, 0.3, 0.2, 0.8 * (1.0 - ring_t)), 3.0)
			var ring2_t: float = fmod(now_s * 2.2 + 0.5, 1.0)
			draw_arc(c, 8.0 + ring2_t * 40.0, 0, TAU, 24, Color(1.0, 0.5, 0.1, 0.7 * (1.0 - ring2_t)), 2.0)
			draw_circle(c, 7.0, Color(1.0, 0.2, 0.2, 0.9))
		elif ttype_d == "laser_beam":
			# Beam flash: núcleo blanco HDR + halo rosa que parpadea su vida corta
			var bdir: Vector2 = (t.get("beam_dir", Vector2.UP) as Vector2).normalized()
			var c: Vector2 = t["pos"] as Vector2
			var lt: float = t.get("lifetime", 0.5)
			var flash: float = 0.5 + 0.5 * sin(lt * 80.0)
			var beam_len2: float = (play_size().x + play_size().y) * 0.5
			_neon_line(c - bdir * beam_len2, c + bdir * beam_len2, Color(1.0, 0.0, 0.55), 7.0)
			draw_line(c - bdir * beam_len2, c + bdir * beam_len2, Color(2.0, 2.0, 2.0, 0.85), 4 + 3 * flash)
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
					draw_set_transform(t["pos"], t["rot"], Vector2.ONE)
					# Fase musical: el muro nace en un downbeat (age=0 ahi), asi que el
					# pulso visual cae exactamente en los acentos de la cancion.
					var w_beat_len: float = maxf(beat_interval, 0.001)
					var w_age: float = float(t.get("age", 0.0))
					var wpulse: float = maxf(0.0, 1.0 - fposmod(w_age / w_beat_len, 1.0))
					var w_smid: float = (float(t["s0"]) + float(t["s1"])) * 0.5
					var w_gc: float = float(t["gap_center"])
					var gap_ly: float = -(w_gc - w_smid)
					if w_state == "warning":
						# 1) RELLENO tenue: TODO el area letal se ve roja desde el primer
						#    frame; el corredor entre bandas queda oscuro = el hueco.
						var fill_a: float = 0.10 + 0.13 * wpulse
						draw_rect(Rect2(-w_half, w_size), Color(1.0, 0.2, 0.3, fill_a * w_alpha))
						# 2) Contorno punteado de cada banda
						var warn_col := Color(1.0, 0.25, 0.35, 0.55)
						draw_dashed_line(Vector2(-w_half.x, -w_half.y), Vector2(w_half.x, -w_half.y), warn_col, 3.0, 16.0)
						draw_dashed_line(Vector2(-w_half.x, w_half.y), Vector2(w_half.x, w_half.y), warn_col, 3.0, 16.0)
						draw_dashed_line(Vector2(-w_half.x, -w_half.y), Vector2(-w_half.x, w_half.y), warn_col, 3.0, 16.0)
						draw_dashed_line(Vector2(w_half.x, -w_half.y), Vector2(w_half.x, w_half.y), warn_col, 3.0, 16.0)
						# 3) Canto del corredor: borde rojo vivo del lado que mira al hueco
						var corridor_col := Color(2.0, 0.6, 0.6, 0.5 + 0.4 * wpulse)
						draw_line(Vector2(-w_half.x, -w_half.y), Vector2(-w_half.x, w_half.y), corridor_col, 2.0 + 2.0 * wpulse)
						# 4) Linea segura punteada + chevrons que desfilan al compas
						var edge_ly: float = -w_half.y
						if (float(t["s1"]) - w_gc) > (w_gc - float(t["s0"])):
							edge_ly = w_half.y
						var safe_col := Color(1.5, 1.5, 1.5, 0.5)
						var arrow_gap: float = 150.0
						var march: float = fposmod(w_age / (4.0 * w_beat_len), 1.0) * arrow_gap
						draw_dashed_line(Vector2(-w_half.x + 60.0, gap_ly), Vector2(w_half.x - 60.0, gap_ly), safe_col, 2.5, 22.0)
						var ax0: float = -w_half.x + 60.0 - march
						while ax0 < w_half.x - 60.0:
							if ax0 >= -w_half.x + 60.0:
								var mc := Vector2(ax0, gap_ly)
								draw_colored_polygon(PackedVector2Array([
									mc + Vector2(0, -15.0), mc + Vector2(-9.0, 6.0), mc + Vector2(9.0, 6.0)]), safe_col)
							ax0 += arrow_gap
						# 5) Borde letal: linea gruesa pulsante al beat por donde entra el golpe
						draw_line(Vector2(-w_half.x, edge_ly), Vector2(w_half.x, edge_ly),
							Color(2.0, 0.5, 0.55, 0.35 + 0.5 * wpulse), 4.0 + 2.0 * wpulse)
					else:
						# Active / fade: muro solido con franjas que desfilan al compas
						draw_rect(Rect2(-w_half, w_size), Color(1.0, 0.2, 0.3, 0.30 * w_alpha))
						var stripe_n: int = maxi(6, int(w_size.x / 110.0))
						var stripe_w: float = w_size.x / float(stripe_n)
						# Las franjas avanzan 1 paso por beat, en fase con la musica
						var stripe_off: float = fposmod(w_age / w_beat_len, 1.0) * stripe_w
						for si in range(stripe_n + 1):
							var lx: float = -w_half.x - stripe_w + si * stripe_w + stripe_off
							draw_line(Vector2(lx, -w_half.y), Vector2(lx + stripe_w * 1.6, w_half.y),
								Color(0, 0, 0, 0.6 * w_alpha), 3.0)
						# Bordes HDR brillantes (largo y corto)
						draw_line(Vector2(-w_half.x, -w_half.y), Vector2(w_half.x, -w_half.y),
							Color(1.8, 0.45, 0.55, 0.9 * w_alpha), 4.0)
						draw_line(Vector2(-w_half.x, w_half.y), Vector2(w_half.x, w_half.y),
							Color(1.8, 0.45, 0.55, 0.7 * w_alpha), 3.0)
					# Esquinas: remache neón en cada vértice para que el marco
					# del muro lea bien también en diagonal.
						for wcx in [-w_half.x, w_half.x]:
							for wcy in [-w_half.y, w_half.y]:
								var wcp := Vector2(wcx, wcy)
								draw_line(wcp + Vector2(-9.0, 0.0), wcp + Vector2(9.0, 0.0), Color(2.0, 0.7, 0.8, 0.85 * w_alpha), 2.5)
								draw_line(wcp + Vector2(0.0, -9.0), wcp + Vector2(0.0, 9.0), Color(2.0, 0.7, 0.8, 0.85 * w_alpha), 2.5)
						# Canto seguro del corredor: el borde de cada banda que mira
						# al hueco se marca cian (color de carril) unos px dentro
						# del pasillo, para que siga legible mientras el muro
						# barre; pulso al beat.
						var safe_ly: float = w_half.y
						if absf(float(t["s1"]) - w_gc) < absf(float(t["s0"]) - w_gc):
							safe_ly = -w_half.y
						var safe_off: float = 10.0 if safe_ly > 0.0 else -10.0
						draw_line(Vector2(-w_half.x, safe_ly + safe_off),
							Vector2(w_half.x, safe_ly + safe_off),
							Color(0.0, 0.94, 1.0, (0.45 + 0.45 * wpulse) * w_alpha), 3.0)
						# Linea central del pasillo (punteada, tenue): el objetivo
						# visible del hueco durante el barrido.
						draw_dashed_line(Vector2(-w_half.x + 60.0, gap_ly),
							Vector2(w_half.x - 60.0, gap_ly),
							Color(1.5, 1.5, 1.5, 0.30 * w_alpha), 2.0, 26.0)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				"saw":
					# Sierra giratoria: disco oscuro + 8 dientes rojos que rotan
					# con el reloj real + aro neon + nucleo pulsante.
					var saw_c: Vector2 = t["pos"]
					var saw_r: float = t["radius"]
					var saw_spin: float = Time.get_ticks_msec() * 0.004
					draw_circle(saw_c, saw_r, Color(0.45, 0.03, 0.08, 1.0))
					for si in range(8):
						var sang: float = saw_spin + TAU * float(si) / 8.0
						var sdir := Vector2(cos(sang), sin(sang))
						draw_line(saw_c + sdir * saw_r * 0.75, saw_c + sdir * saw_r * 1.28, Color(1.0, 0.13, 0.22, 1.0), 6.0)
					_neon_arc(saw_c, saw_r * 0.92, Color(1.0, 0.13, 0.22), 3.0)
					var saw_pulse: float = 0.55 + 0.08 * sin(saw_spin * 0.5)
					draw_circle(saw_c, saw_r * 0.34, Color(1.3, 0.22, 0.3, saw_pulse))
					draw_circle(saw_c, saw_r * 0.13, Color(1.6, 0.6, 0.7, 1.0))
				"drifter":
					# Mina de puas: casco oscuro + 8 puas neon + nucleo.
					var dri_c: Vector2 = t["pos"]
					var dri_r: float = t["radius"]
					var dri_bp: float = fmod(song_time / maxf(beat_interval, 0.001), 1.0)
					var dri_len: float = dri_r * (1.25 + 0.25 * clampf(1.0 - dri_bp * 5.0, 0.0, 1.0))
					draw_circle(dri_c, dri_r, Color(0.38, 0.03, 0.07, 1.0))
					for di in range(8):
						var ddir := Vector2.from_angle(TAU * float(di) / 8.0 + song_time * 0.6)
						_neon_line(dri_c + ddir * dri_r * 0.7, dri_c + ddir * dri_len, Color(1.0, 0.16, 0.25), 3.0)
					_neon_arc(dri_c, dri_r, Color(1.0, 0.16, 0.25), 3.0)
					draw_circle(dri_c, dri_r * 0.22, Color(1.5, 0.35, 0.4, 0.9))
				"homing":
					# Misil: dardo que apunta a su velocidad + estela incandescente.
					var hom_c: Vector2 = t["pos"]
					var hom_r: float = t["radius"]
					var hom_v: Vector2 = t["vel"]
					var hom_dir := Vector2.DOWN
					if hom_v.length_squared() > 1.0:
						hom_dir = hom_v.normalized()
					var hom_perp := Vector2(-hom_dir.y, hom_dir.x)
					draw_line(hom_c - hom_dir * hom_r * 0.8, hom_c - hom_dir * hom_r * 1.9, Color(1.0, 0.45, 0.1, 0.55), 7.0)
					draw_colored_polygon(PackedVector2Array([hom_c + hom_dir * hom_r * 1.1, hom_c - hom_dir * hom_r * 0.8 + hom_perp * hom_r * 0.75, hom_c, hom_c - hom_dir * hom_r * 0.8 - hom_perp * hom_r * 0.75]), Color(0.55, 0.05, 0.1, 1.0))
					_neon_polyline(PackedVector2Array([hom_c + hom_dir * hom_r * 1.1, hom_c - hom_dir * hom_r * 0.8 + hom_perp * hom_r * 0.75, hom_c - hom_dir * hom_r * 0.8 - hom_perp * hom_r * 0.75, hom_c + hom_dir * hom_r * 1.1]), Color(1.0, 0.16, 0.25), 2.5)
					draw_circle(hom_c, hom_r * 0.26, Color(1.0, 0.85, 0.4, 1.0))
				"perimeter":
					# Centinela: hexagono neon que rota lento + nucleo.
					var per_c: Vector2 = t["pos"]
					var per_r: float = t["radius"]
					var per_spin: float = Time.get_ticks_msec() * 0.0012
					var per_pts := PackedVector2Array()
					for pi in range(6):
						per_pts.append(per_c + Vector2.from_angle(per_spin + TAU * float(pi) / 6.0) * per_r * 1.1)
					per_pts.append(per_pts[0])
					draw_circle(per_c, per_r * 1.1, Color(0.35, 0.03, 0.07, 1.0))
					_neon_polyline(per_pts, Color(1.0, 0.16, 0.25), 3.0)
					var per_core: float = 0.5 + 0.5 * sin(per_spin * 6.0)
					draw_circle(per_c, per_r * (0.20 + 0.12 * per_core), Color(1.4, 0.3, 0.38, 0.95))
				_:
					# Default hazard: disco rojo neon con nucleo.
					var hz_c: Vector2 = t["pos"]
					var hz_r: float = t["radius"]
					draw_circle(hz_c, hz_r, Color(0.5, 0.04, 0.09, 0.95))
					_neon_arc(hz_c, hz_r, Color(1.0, 0.13, 0.22), 3.5)
					draw_circle(hz_c, hz_r * 0.30, Color(1.0, 0.2, 0.3, 0.9))
