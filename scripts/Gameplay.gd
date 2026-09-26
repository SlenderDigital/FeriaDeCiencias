extends Node2D

# T9: PRELOADS EXPLÍCITOS de los motores puros. Godot 4.7 + el editor del MCP
# pierden la tabla global de class_name al reescanear (3 veces en esta tarea:
# "Identifier PilotLogic not declared"). Con preload, la dependencia es
# explícita y ningún re-scan puede romperla.
const _SpokeFanLogic: GDScript = preload("res://scripts/SpokeFanLogic.gd")
const _SweepLogic: GDScript = preload("res://scripts/SweepLogic.gd")
const _WaveformLogic: GDScript = preload("res://scripts/WaveformLogic.gd")
const _SqueezeLogic: GDScript = preload("res://scripts/SqueezeLogic.gd")
const _PulseRingsLogic: GDScript = preload("res://scripts/PulseRingsLogic.gd")
const _ImpactFeel: GDScript = preload("res://scripts/ImpactFeel.gd")
const _PilotLogic: GDScript = preload("res://scripts/PilotLogic.gd")
const _PatternLanguage: GDScript = preload("res://scripts/PatternLanguage.gd")
## Gameplay — Rhythm Action Gameplay Scene for Abstract Pulse
## Runs the procedural MVP level, handles arrow key movement, spawns algorithmic beats/hazards, tracks health/progress, and manages game loop overlays.

@onready var bg_control: Control = $BackgroundLayer/Background
@onready var track_title_lbl: Label = $HUDLayer/HUD/TopBar/TrackTitle
@onready var progress_lbl: Label = $HUDLayer/HUD/TopBar/ProgressLabel
@onready var progress_bar: ProgressBar = $HUDLayer/HUD/BottomBar/ProgressBar
@onready var pause_overlay: Control = $HUDLayer/PauseOverlay
@onready var results_overlay: Control = $HUDLayer/ResultsOverlay
@onready var results_title_lbl: Label = $HUDLayer/ResultsOverlay/Panel/VBox/Title
@onready var results_details_lbl: Label = $HUDLayer/ResultsOverlay/Panel/VBox/ResultsDetails
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
# Energía de la sección activa (0..1) y su nombre — la leen los visuales
# (T5): flash de beat, glow del fondo y tinte del breakdown escalan con la
# música. La actualiza _process desde controller._section_intent.
var section_energy: float = 0.5
var section_name: String = ""
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
const HIT_IFRAMES_EASY: float = 2.0
var _hit_iframes: float = 0.0
# easy_mode: nivel 1 (First Light) - mas margen. Niveles 2-3 intactos.
var easy_mode: bool = false
# Juice de daño: flash rojo de pantalla + vibracion al recibir un golpe.
const SHAKE_TIME: float = 0.25
const SHAKE_AMP: float = 12.0
# Antigüedad máxima de un paquete de landmarks para que la mano siga
# "guiando": más viejo que esto, el teclado recupera el control.
const _HAND_FRESH_SEC: float = 0.35
# T9: velocidad del piloto automático (px/s). Un humano con la mano es más
# rápido en 有些 tramos; el piloto se limita a lo que una esquiva justa permite.
const _PILOT_SPEED: float = 520.0
var _damage_flash: float = 0.0
var _shake_time: float = 0.0
var _damage_overlay: ColorRect
# T8 IMPACTO: el golpe se siente. Trauma de cámara + flash blanco, ambos en
# ImpactFeel (motor puro, el mismo que testea tools/test_impact.gd). El
# hit-stop congela la ESCENA, nunca el reloj de audio (FREEZES_MUSIC_CLOCK).
var _impact: Dictionary = {}
# T8 HIT-STOP: se mide contra el RELOJ REAL (no contra delta): si se
# contara con delta, el propio freeze pondría delta=0 y el contador nunca
# llegaría a cero — el juego se congelaría para siempre. Un hit contra
# _hitstop_until (timestamp) no puede hacer eso.
var _hitstop_until: float = 0.0
# T9: destello cuando el escudo BLOQUEA un peligro (feedback honesto)
var _shield_block_flash: float = 0.0
# T9 AUTOPLAY: el piloto conduce la nave cuando MCP_AUTOPLAY=1, para poder
# verificar el juego real (grabarlo y evaluarlo) sin jugador humano.
var _autoplay: bool = false
var _autoplay_target: Vector2 = Vector2(640, 560)
var _shield_was_ready: bool = true   # para sonido de "listo" al recargarse
var _fist_was_closed: bool = false   # edge-trigger: un escudo por puno (requiere abrir para re-armar)
var health: float = 100.0
var progress_pct: int = 0   # % de la canción sobrevivida: la métrica del nivel
var is_paused: bool = false
var is_game_over: bool = false
var _music_finished: bool = false
var _waiting_for_control: bool = false
var _manual_control: bool = false

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
	# T9 AUTOPLAY: el piloto conduce (para verificación grabada, no para jugar).
	# El MCP arranca el juego desde el EDITOR, que no hereda mi shell: por eso
	# MCP_AUTOPLAY=1 también se puede activar con un archivo bandera.
	_autoplay = OS.get_environment("MCP_AUTOPLAY") == "1" \
		or FileAccess.file_exists("/tmp/jsab_autoplay.flag")
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
		easy_mode = str(track_data.get("id", "")) == "level_first_light"
		controller.easy_mode = easy_mode
		if easy_mode:
			health = 125.0   # un golpe extra de margen en el tutorial
			print("[Gameplay] easy_mode ON (First Light): hazards x0.85, warn muros 2.5 beats, iframes 2.0s")
		bpm = chart.bpm
		music.stream = song.render_audio_cached(seed_val, bpm)
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
	elif what == NOTIFICATION_EXIT_TREE:
		# Al salir del nivel: liberar el fondo para que el menú vuelva a su
		# propio metrónomo (el reloj de la canción ya no se alimenta).
		if bg_control and bg_control.has_method("clear_song_clock"):
			bg_control.clear_song_clock()

func _update_control_gate() -> void:
	## El juego corre SIEMPRE (teclado disponible de base). La mano es un
	# PLUS: si aparece, toma el control; si desaparece, la nave queda donde
	# está y el jugador sigue con teclado. Nada de pausar esperando cámara.
	return

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var is_move_key: bool = event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT \
			or event.keycode == KEY_UP or event.keycode == KEY_DOWN \
			or event.keycode == KEY_A or event.keycode == KEY_D \
			or event.keycode == KEY_W or event.keycode == KEY_S
		if is_move_key:
			_manual_control = true
			if _waiting_for_control:
				_waiting_for_control = false
				music.stream_paused = false
	if event is InputEventKey and event.pressed and event.keycode == KEY_F6:
		_toggle_debug_menu()
		return
	if event.is_action_pressed("ui_cancel"): # ESC key
		toggle_pause()
	elif not is_paused and not is_game_over:
		# Shield on Space, Enter, or Mouse Click.
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
	var shots_on: bool = OS.get_environment("MCP_SHOTS") == "1" \
		or FileAccess.file_exists("/tmp/jsab_autoplay.flag")
	if shots_on and not is_game_over:
		var spt: float = song_time
		if OS.get_environment("MCP_SHOT_DEBUG") == "1" and fmod(float(Time.get_ticks_msec()), 2000.0) < 20.0:
			print("[CLOCK] song_time=%.2f playing=%s paused=%s" % [spt, str(music.playing), str(music.stream_paused)])
		if spt > 8.9 and spt < 9.2 and not get_meta("shot_act2", false):
			set_meta("shot_act2", true)
			get_viewport().get_texture().get_image().save_png("/tmp/shot_act2.png")
		if spt > 20.5 and spt < 20.8 and not get_meta("shot_act3", false):
			set_meta("shot_act3", true)
			get_viewport().get_texture().get_image().save_png("/tmp/shot_act3.png")
		# T5: lista genérica "t=name" separada por comas (ej.
		# MCP_SHOT_LIST="5=intro,30=drop,55=breakdown,80=drop2").
		# T9: el MCP arranca el juego desde el EDITOR, que no hereda el entorno
		# de mi shell — por eso la lista también se puede leer de un archivo.
		# /tmp/jsab_shot_list.txt tiene precedencia si existe.
		var shot_list: String = OS.get_environment("MCP_SHOT_LIST")
		if FileAccess.file_exists("/tmp/jsab_shot_list.txt"):
			var f := FileAccess.open("/tmp/jsab_shot_list.txt", FileAccess.READ)
			if f:
				var from_file: String = f.get_as_text().strip_edges()
				f.close()
				if not from_file.is_empty():
					shot_list = from_file
		if not shot_list.is_empty():
			for entry in shot_list.split(","):
				var parts: PackedStringArray = entry.split("=")
				if parts.size() != 2:
					continue
				var want_t: float = parts[0].to_float()
				var tag: String = parts[1]
				var meta_key: String = "shot_%s" % tag
				if spt > want_t and spt < want_t + 0.35 and not get_meta(meta_key, false):
					set_meta(meta_key, true)
					var img: Image = get_viewport().get_texture().get_image()
					img.save_png("/tmp/shot_%s.png" % tag)
					print("[SHOT] %s @ %.2fs -> /tmp/shot_%s.png" % [tag, spt, tag])
	if is_paused or is_game_over:
		return
	_update_control_gate()
	if _waiting_for_control:
		queue_redraw()
		return
		
	# Anchor game clock to real audio playback when chart-driven; otherwise fall
	# back to the procedural delta-accumulated clock.
	if chart != null and music.playing:
		song_time = music.get_playback_position()
	else:
		song_time += delta

	# T8 HIT-STOP: a partir de acá, el mundo se congela con delta=0 durante
	# 50ms. song_time ya se leyó del AUDIO (arriba), así que la canción sigue
	# sonando y el reloj del nivel no se mueve: el freeze es 100% visual y
	# no puede desincronizar el chart.
	# El RELOJ REAL (no delta) decide si seguimos congelados — ver la nota
	# de _hitstop_until: contar con delta nunca terminaría.
	if Time.get_ticks_msec() / 1000.0 < _hitstop_until:
		delta = 0.0

	# T9 AUTOPLAY: con MCP_AUTOPLAY=1 el piloto conduce la nave. Es lo que
	# permite verificar el juego de verdad (grabarlo, mirarlo, evaluarlo con
	# space-bunny) sin que la partida muera sola al 49%. El piloto elige
	# puntos validados por tools/test_pilot.gd contra la colisión real.
	if _autoplay:
		_autoplay_target = _pilot_desired(delta)
		player_pos = _PilotLogic.steer_step(player_pos, _autoplay_target, _PILOT_SPEED, delta)

	# El fondo late con la canción REAL: sin metrónomo propio ni doble golpe.
	if bg_control and bg_control.has_method("set_song_clock"):
		bg_control.set_song_clock(song_time, beat_interval)
	# Energía de la sección activa -> visuales (T5) y fondo.
	if controller:
		var intent: Dictionary = controller._section_intent(song_time)
		section_energy = float(intent["energy"])
		section_name = str(intent["name"])
		if bg_control and bg_control.has_method("set_section_mood"):
			bg_control.set_section_mood(section_energy, section_name)
	
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
			
			# Gate: un solo stripe_wall a la vez (no se apilan muros).
			# Se calcula ANTES de spawns_at: el pool regular tambien puede
			# traer stripe_wall y debe ver el flag fresco, no el del downbeat
			# anterior.
			var has_wall := false
			for tg in targets:
				if tg.get("type", "") == "stripe_wall":
					has_wall = true
					break
			# El muro activo silencia los acentos rojos (PatternController)
			controller.wall_active = has_wall

			# Regular beat spawns
			var spawns: Array[Dictionary] = controller.spawns_at(t, next_beat_idx, track_color)
			_append_spawns(spawns)
			
			# Downbeat patterns (every 4 beats) - big patterns
			if chart.downbeat[next_beat_idx]:
				if not has_wall:
					_append_spawns(controller.spawns_at_downbeat(t, next_beat_idx, track_color))
			
			# Bar patterns (every 4 beats = every downbeat) - variations
			if next_beat_idx % 4 == 0:
				_append_spawns(controller.spawns_at_bar(t, next_beat_idx, track_color))
			
			# Phrase patterns (every 16 beats) - setpieces / new mechanics
			if next_beat_idx % 16 == 0:
				_append_spawns(controller.spawns_at_phrase(t, next_beat_idx, track_color))
			
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

func _append_spawns(spawns: Array[Dictionary]) -> void:
	# Centraliza la Incorporacion de spawns y actualiza el gate en el mismo
	# instante en que aparece un muro. Asi los patrones de bar/phrase del mismo
	# beat no agregan una sierra despues de que el muro ya esta en pantalla.
	for s in spawns:
		_notify_spawn(s)
		targets.append(s)
		if s.get("type", "") == "stripe_wall" and controller:
			controller.wall_active = true

func _notify_spawn(s: Dictionary) -> void:
	# Avisos sonoros al nacer un spawn que lo requiera.
	# Vive en Gameplay (no en PatternController) para que el E2E headless
	# pueda instanciar el controller sin autoloads de escena.
	if s.get("type", "") == "laser_telegraph" and SoundManager:
		SoundManager.play_warning()

func _update_player_movement(delta: float) -> void:
	# Con mano: posicion absoluta de la palma + rotacion pulgar->indice (port de Player.cpp)
	# ARBITRAJE: la mano manda SOLO si está realmente guiando. Antes la mano
	# tomaba el control exclusivo apenas HandTrackingClient.has_hand era true,
	# y con landmarks ruidosos (o una mano a medio cuadro) la nave se iba
	# mientras el teclado no hacía NADA — el jugador quedaba fuera del juego.
	# Ahora: si el jugador toca una tecla, el teclado manda; si la mano lleva
	# un tiempo sin landmarks fresco, el teclado vuelve a estar disponible.
	var hand_guiding: bool = false
	if HandTrackingClient:
		hand_guiding = HandTrackingClient.has_hand and HandTrackingClient.is_fresh(_HAND_FRESH_SEC)
	if hand_guiding and not _manual_control:
		var ps: Vector2 = play_size()
		var target: Vector2 = HandTrackingClient.get_palm_center() * ps
		var alpha: float = 1.0 - exp(-25.0 * delta)
		player_pos = player_pos.lerp(target, alpha)
		var ang := HandTrackingClient.get_hand_angle_deg()
		if ang < 9990.0:
			_smooth_rotation_toward(ang, delta)
		_update_fist_shield()
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

## Arco neón de un sector (start..end): el hueco de los anillos se dibuja
## literalmente como el espacio que falta del arco.
func _neon_arc_full(center: Vector2, r: float, from_a: float, to_a: float, c: Color, w: float) -> void:
	draw_arc(center, r, from_a, to_a, 40, Color(c.r, c.g, c.b, 0.18), w * 3.2)
	draw_arc(center, r, from_a, to_a, 40, Color(c.r, c.g, c.b, 0.5), w * 1.7)
	draw_arc(center, r, from_a, to_a, 40, Color(minf(c.r * 1.7, 4.0), minf(c.g * 1.7, 4.0), minf(c.b * 1.7, 4.0), 1.0), w)

func _draw_one_target(t: Dictionary) -> void:
	# Dibujo de un spawn. _draw lo invoca en 3 pasadas: hazards comunes,
	# stripe_wall translúcido encima (deja ver las sierras atrapadas en la
	# banda) y lasers al final (el telegraph jamas queda tapado).
	var ttype_d: String = t.get("type", "target")
	if ttype_d == "spoke_fan":
		# JSAB abanico de rayos: telegraph = rayos granate tenues que YA rotan
		# (se lee la dirección); active = rayos rosa HDR + núcleo blanco; fade
		# decae. El hueco es visible por AUSENCIA de rayo — el borde del hub
		# marca los extremos del pasillo.
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
		# T10 — CUERPO DEL ROTOR. space-bunny, 4a/5a pasada: "the gap is a hole
		# in the render" y luego "the annulus is the same maroon as the beams, so
		# there is zero figure/ground between the lethal container and the lethal
		# content". Ahora el anillo tiene ARO (rim) y va un paso hacia neutral:
		# el rojo se reserva para los RAYOS, y el contenedor es vino desaturado
		# con borde visible, para que los rayos se lean como contenido DENTRO
		# de algo. El sector seguro conserva el cian (único color frío del set).
		var sector_from: float = rot_d + TAU * float(gap_first_d) / float(n_sp)
		var sector_to: float = sector_from + TAU * float(gap_sp) / float(n_sp)
		var body_col := Color(0.20, 0.08, 0.14, 0.26 if st_d != "telegraph" else 0.14)
		var rim_col := Color(0.55, 0.30, 0.42, 0.45 if st_d != "telegraph" else 0.28)
		var safe_col := Color(0.30, 0.92, 1.0, 0.20 if st_d != "telegraph" else 0.14)
		# territories: dos polígonos anulares (sector lethal + sector seguro)
		var lethal_pts := PackedVector2Array()
		var safe_pts := PackedVector2Array()
		var seg: int = 26
		# el rotor se dibuja acotado a la arena (min con el radio pedido): el
		# disco entero cruzando el borde se leia como un viñeteado, no como
		# una maquina (5a pasada).
		var body_r: float = minf(rad_d, play_size().length() * 0.5)
		for a_i in range(seg + 1):
			var aa: float = sector_from + (sector_to - sector_from) * float(a_i) / float(seg)
			safe_pts.append(hub_d + Vector2.from_angle(aa) * body_r)
			var ab: float = sector_to + (sector_from + TAU - sector_to) * float(a_i) / float(seg)
			lethal_pts.append(hub_d + Vector2.from_angle(ab) * body_r)
		lethal_pts.append(hub_d)
		safe_pts.append(hub_d)
		draw_colored_polygon(lethal_pts, body_col)
		draw_colored_polygon(safe_pts, safe_col)
		# T10: el aro se dibuja hasta el borde de la ventana de juego, no
		# como un círculo completo que se sale del área (se veía el disco
		# entero cruzando el borde en 72%). El rotor pertenece a la ARENA.
		var rim_max: float = body_r
		draw_arc(hub_d, rim_max, 0.0, TAU, 64, rim_col, 3.0)
		# los dos radios del sector SEGURO como marcadores duros
		for b_i in range(2):
			var b_ang: float = sector_from if b_i == 0 else sector_to
			var b_dir := Vector2.from_angle(b_ang)
			var b_tip: Vector2 = hub_d + b_dir * rim_max
			draw_line(hub_d + b_dir * 26.0, b_tip,
				Color(0.45, 0.95, 1.0, 0.45 * alpha_d), 3.0)
			# marcador de flecha en el borde: hace visible DÓNDE termina el
			# pasillo, que es lo que el jugador tiene que alcanzar
			var perp := b_dir.rotated(PI * 0.5)
			draw_colored_polygon(PackedVector2Array([
					b_tip + b_dir * 11.0, b_tip + perp * 8.0, b_tip - perp * 8.0]),
				Color(0.45, 0.95, 1.0, 0.55 * alpha_d))
		# marca interior del borde: un anillo fino claro, para que el rotor se
		# lea como una MÁQUINA y no como un viñeteado
		draw_arc(hub_d, rim_max * 0.94, 0.0, TAU, 64, Color(0.45, 0.30, 0.38, 0.18 * alpha_d), 1.5)
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
			var tip_d: Vector2 = hub_d + dir_d * rad_d
			if st_d == "telegraph":
				# granate tenue, pulsa al beat, finito y delgado: AVISO legible
				# T10: el ancho del rayo escala con el RADIO del rotor (no un
				# fijo en px): un rotor grande no puede dibujar sus rayos como
				# hairlines de 2px, porque entonces el hueco se lee como
				# "aún no spamearon rayos" y no como "acá se puede estar".
				var spoke_w: float = maxf(3.0, rad_d * 0.022)
				var warn_col: Color = Color(0.85, 0.20, 0.30, (0.46 + 0.22 * pulse_d) * alpha_d)
				draw_line(hub_d + dir_d * 24.0, tip_d, warn_col, spoke_w)
				draw_line(tip_d - dir_d * 14.0, tip_d, Color(0.75, 0.2, 0.28, 0.5 * alpha_d), spoke_w * 1.8)
			else:
				# active/fade: rosa neón pleno (el peligro ES la geometría)
				# T10: mismo piso de grosor, para que el peligro tenga la misma
				# masa visual en cualquier tamaño de rotor.
				var spoke_w2: float = maxf(6.0, rad_d * 0.042)
				_neon_line(hub_d + dir_d * 20.0, tip_d, Color(1.0, 0.2, 0.3), spoke_w2 * (0.8 + 0.2 * pulse_d))
				draw_line(hub_d + dir_d * 20.0, tip_d, Color(2.2, 0.5, 0.6, 0.9 * alpha_d), spoke_w2 * 0.36)
		# Hub: aro del tamaño del "ojo" seguro + núcleo
		if st_d == "telegraph":
			draw_arc(hub_d, 24.0, 0, TAU, 24, Color(0.7, 0.25, 0.3, 0.4 * alpha_d), 2.5)
			draw_circle(hub_d, 7.0, Color(0.7, 0.25, 0.3, 0.6 * alpha_d))
		else:
			_neon_arc(hub_d, 24.0, Color(1.0, 0.2, 0.3), 3.0)
			draw_circle(hub_d, 8.0, Color(2.4, 2.4, 2.4, 0.85 * alpha_d))  # blanco impacto
			draw_circle(hub_d, 4.0, Color(1.0, 0.25, 0.35, alpha_d))
		# Chevrons del hueco: marcan el pasillo seguro en active
		if st_d != "telegraph":
			var g_mid: float = _SpokeFanLogic.gap_start_angle(t)
			var gdir := Vector2.from_angle(g_mid)
			var chev := hub_d + gdir * rad_d * 0.55
			draw_colored_polygon(PackedVector2Array([
					chev + gdir * 12.0, chev + gdir.rotated(2.5) * -9.0, chev + gdir.rotated(-2.5) * -9.0]),
					Color(0.4, 0.95, 1.0, 0.35 * alpha_d))
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
			draw_arc(mj_hub, mj_tgt, mj_a0, mj_a1, 32, Color(0.55, 0.15, 0.2, 0.22 * mj_al), 1.5)
		draw_arc(mj_hub, mj_r, mj_a0, mj_a1, 32, Color(0.95, 0.25, 0.32, 0.45 * mj_al), 3.0)
		draw_arc(mj_hub, mj_r, mj_a0, mj_a1, 32, Color(1.6, 0.5, 0.6, 0.75 * mj_al), 1.6)
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
			_neon_line(mf_hub, mf_hub + Vector2.from_angle(ang) * mf_r_eff, Color(0.95, 0.25, 0.32), 3.0 * mf_al)
		draw_circle(mf_hub, 4.0, Color(1.4, 0.6, 0.7, 0.6 * mf_al))
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
				draw_arc(hub_r, ghost_r, a_start, a_end, 40, Color(0.9, 0.25, 0.34, (0.44 + 0.20 * pulse_r) * alpha_r), 3.0)
			else:
				_neon_arc_full(hub_r, r_r, a_start, a_end, Color(1.0, 0.2, 0.3), 6.0 * (0.85 + 0.15 * pulse_r))
		# hub: núcleo blanco de impacto
		if st_r != "telegraph":
			draw_circle(hub_r, 7.0, Color(2.3, 2.3, 2.3, 0.8 * alpha_r))
		# chevrons en el hueco: el pasillo seguro, marcado
		if st_r != "telegraph":
			var chev_r: Vector2 = hub_r + Vector2.from_angle(g_ang_r) * (_PulseRingsLogic.ring_radius(t, 0) * 0.5)
			var d_r: Vector2 = (chev_r - hub_r).normalized()
			draw_colored_polygon(PackedVector2Array([
					chev_r + d_r * 13.0, chev_r + d_r.rotated(2.5) * -9.0, chev_r + d_r.rotated(-2.5) * -9.0]),
				Color(0.4, 0.95, 1.0, 0.34 * alpha_r))
		return
	if ttype_d == "squeeze_corridor":
		# JSAB corredor bilateral: dos paredes squeezing el espacio. Telegraph =
		# contornos tenues marcando DÓNDE va a apretar (leer el bolsillo antes);
		# active = paredes hot-pink macizas con borde neón y chevrons apuntando
		# al pasillo; fade decae.
		var ps_s: Vector2 = play_size()
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
				draw_rect(r, Color(0.45, 0.08, 0.14, 0.46 * alpha_s2))
				draw_line(Vector2(inner_x, 0.0), Vector2(inner_x, ps_s.y),
					Color(0.75, 0.22, 0.3, (0.45 + 0.3 * pulse_s2) * alpha_s2), 2.5)
			else:
				draw_rect(r, Color(0.5, 0.05, 0.12, 0.6 * alpha_s2))
				_neon_line(Vector2(inner_x, 0.0), Vector2(inner_x, ps_s.y), Color(1.0, 0.2, 0.3), 6.0)
				# franjas internas: la textura hace legible la presión
				var stripe_sp: float = 74.0
				var sx: float = outer_x + stripe_sp * 0.5
				while sx < inner_x:
					draw_line(Vector2(sx, 0.0), Vector2(sx, ps_s.y), Color(0.2, 0.05, 0.08, 0.4 * alpha_s2), 1.5)
					sx += stripe_sp
			# chevrons apuntando al pasillo (le say "aquí adentro")
			var dir_c: float = 1.0 if side_i == 0 else -1.0
			for cy_s in range(3):
				var cyy: float = ps_s.y * (0.3 + 0.2 * float(cy_s))
				var cxp: float = inner_x + dir_c * 26.0
				draw_colored_polygon(PackedVector2Array([
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
		var play_w0: Vector2 = play_size()
		for c in range(cols_w):
			var h_w: float = _WaveformLogic.column_height(t, c)
			var x0_w: float = float(c) * colw_w
			var x1_w: float = x0_w + colw_w
			var bottom_w: float = play_w0.y
			if st_w == "telegraph":
				# aviso: relleno granate translúcido + borde superior tenue
				draw_rect(Rect2(Vector2(x0_w + 1.0, h_w), Vector2(colw_w - 2.0, bottom_w - h_w)),
					Color(0.52, 0.09, 0.16, 0.50 * alpha_w))
				draw_line(Vector2(x0_w, h_w), Vector2(x1_w, h_w), Color(0.7, 0.2, 0.28, 0.55 * alpha_w), 2.0)
			else:
				# active: columna llena con neón, cresta con brillo
				draw_rect(Rect2(Vector2(x0_w + 1.0, h_w), Vector2(colw_w - 2.0, bottom_w - h_w)),
					Color(0.55, 0.06, 0.14, 0.62 * alpha_w))
				_neon_line(Vector2(x0_w, h_w), Vector2(x1_w, h_w), Color(1.0, 0.2, 0.3), 5.0)
				# crestas más altas: remate blanco de impacto
				if h_w < float(t.get("peak_line", 400.0)) + 6.0:
					draw_line(Vector2(x0_w, h_w), Vector2(x1_w, h_w), Color(2.0, 0.6, 0.7, 0.85 * alpha_w), 2.0)
			# separadores verticales tenues: la retícula hace legible la onda
			draw_line(Vector2(x0_w, h_w), Vector2(x0_w, bottom_w), Color(0.3, 0.1, 0.16, 0.3 * alpha_w), 1.0)
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
		draw_arc(hub_s, 46.0, arc_from, arc_to, 28, arc_col, 2.5)
		if st_s == "telegraph":
			# haz fantasma en ang_start: por dónde ENTRARÁ
			var ghost := Vector2.from_angle(a0)
			draw_line(hub_s, hub_s + ghost * blen, Color(0.75, 0.2, 0.28, (0.3 + 0.2 * pulse_s) * alpha_s), 3.0)
			var tip_g: Vector2 = hub_s + ghost * blen
			draw_circle(tip_g, 6.0, Color(0.8, 0.25, 0.3, 0.6 * alpha_s))
		else:
			# haz activo barriendo (easeInOut — arranca y frena en el beat)
			var bdir_s := Vector2.from_angle(_SweepLogic.beam_angle(t))
			_neon_line(hub_s, hub_s + bdir_s * blen, Color(1.0, 0.2, 0.3), 8.0 * (0.85 + 0.15 * pulse_s))
			draw_line(hub_s, hub_s + bdir_s * blen, Color(2.2, 0.5, 0.6, 0.95 * alpha_s), 3.0)
			# hub con núcleo blanco (impacto)
			_neon_arc(hub_s, 20.0, Color(1.0, 0.2, 0.3, 0.9 * alpha_s), 3.0)
			draw_circle(hub_s, 7.0, Color(2.4, 2.4, 2.4, 0.85 * alpha_s))
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
		var beam_len: float = play_size().length() + 100.0
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
		# Igual que el telegraph: diagonal completa + margen.
		var beam_len2: float = play_size().length() + 100.0
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
					# 1) RELLENO translúcido: TODO el area letal se ve roja desde el
					#    primer frame, pero las sierras y el fondo siguen siendo
					#    visibles a traves de la banda (no se pueden esconder).
					#    El pulso vive en el alpha de este overlay, nunca en la
					#    cobertura: no hay una ventana de peligro invisible.
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
					# Active / fade: muro translúcido con franjas que desfilan al compas.
					# La banda deja ver las sierras y el fondo; el hueco (entre
					# bandas) sigue descubierto y es el unico corredor seguro.
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
				# T9 (coherencia): lethality >= 0.75 = LETAL CON NÚCLEO
				# BLANCO HDR. Las sierras del tutorial (0.5) quedan en rojo
				# simple: se leen como "proyectil", no como "momento". Antes
				# todo era el mismo rojo saturado y el jugador no distinguía
				# un saw de un fan (space-bunny: "dos lenguajes en un frame").
				var saw_c: Vector2 = t["pos"]
				var saw_r: float = t["radius"]
				var saw_lethal: bool = _PatternLanguage.lethality_of(ttype_d) >= 0.75
				var saw_spin: float = Time.get_ticks_msec() * 0.004
				# T10 (space-bunny 4a): la sierra comparte forma con el haz del
				# abanico y la onda, así que no se sabía si mataba. Ahora
				# tiene un halo tenue que la marca como PROYECTIL (se mueve
				# solo) y no como geometría del nivel (que tiene borde duro
				# y sector). El halo es la diferencia de vocabulario.
				draw_circle(saw_c, saw_r * 1.75, Color(1.0, 0.10, 0.20, 0.07))
				draw_circle(saw_c, saw_r * 1.35, Color(1.0, 0.10, 0.20, 0.05))
				draw_circle(saw_c, saw_r, Color(0.45, 0.03, 0.08, 1.0))
				for si in range(8):
					var sang: float = saw_spin + TAU * float(si) / 8.0
					var sdir := Vector2(cos(sang), sin(sang))
					draw_line(saw_c + sdir * saw_r * 0.75, saw_c + sdir * saw_r * 1.28, Color(1.0, 0.13, 0.22, 1.0), 6.0)
				_neon_arc(saw_c, saw_r * 0.92, Color(1.0, 0.13, 0.22), 3.0)
				var saw_pulse: float = 0.55 + 0.08 * sin(saw_spin * 0.5)
				draw_circle(saw_c, saw_r * 0.34, Color(1.3, 0.22, 0.3, saw_pulse))
				if saw_lethal:
					# remate blanco: este saw mata y hay que leerlo como tal
					draw_circle(saw_c, saw_r * 0.16, Color(2.4, 2.0, 2.0, 0.9))
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

func _update_fist_shield() -> void:
	if is_paused or is_game_over:
		_fist_was_closed = false
		return
	var closed: bool = HandTrackingClient.is_fist()
	if closed and not _fist_was_closed:
		_try_shield()
	_fist_was_closed = closed

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
	if _shield_block_flash > 0.0:
		_shield_block_flash = maxf(_shield_block_flash - delta, 0.0)
	if _shake_time > 0.0:
		_shake_time = maxf(_shake_time - delta, 0.0)
	# T8: impacto (trauma + flash) decae en 2 beats. El hit-stop NO se cuenta
	# acá: su reloj es real (ver _hitstop_until), no el delta del mundo.
	if not _impact.is_empty():
		_ImpactFeel.step(_impact, delta, beat_interval)
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
		elif ttype == "spoke_fan":
			# JSAB abanico de rayos: la física vive en SpokeFanLogic (pura);
			# Gameplay solo hace step + muerte por estado done.
			t["state_time"] = float(t.get("state_time", 0.0))
			var stepped: Dictionary = _SpokeFanLogic.step(t, delta, beat_interval)
			t["state"] = stepped["state"]
			t["state_time"] = stepped["state_time"]
			t["is_hazard"] = stepped["is_hazard"]
			if str(stepped["state"]) == "done":
				to_remove.append(i)
				continue
		elif ttype == "laser_sweep":
			# JSAB láser que barre: motor puro _SweepLogic.
			var sw_step: Dictionary = _SweepLogic.step(t, delta, beat_interval)
			t["state"] = sw_step["state"]
			t["state_time"] = sw_step["state_time"]
			t["is_hazard"] = sw_step["is_hazard"]
			if str(sw_step["state"]) == "done":
				to_remove.append(i)
				continue
		elif ttype == "waveform_wall":
			# JSAB muro de onda: motor puro _WaveformLogic.
			var wf_step: Dictionary = _WaveformLogic.step(t, delta, beat_interval)
			t["state"] = wf_step["state"]
			t["state_time"] = wf_step["state_time"]
			t["is_hazard"] = wf_step["is_hazard"]
			if str(wf_step["state"]) == "done":
				to_remove.append(i)
				continue
		elif ttype == "squeeze_corridor":
			# JSAB corredor bilateral: motor puro _SqueezeLogic.
			var sq_step: Dictionary = _SqueezeLogic.step(t, delta, beat_interval)
			t["state"] = sq_step["state"]
			t["state_time"] = sq_step["state_time"]
			t["is_hazard"] = sq_step["is_hazard"]
			if str(sq_step["state"]) == "done":
				to_remove.append(i)
				continue
		elif ttype == "pulse_rings":
			# JSAB anillos expansivos: motor puro _PulseRingsLogic.
			var pr_step: Dictionary = _PulseRingsLogic.step(t, delta, beat_interval)
			t["state"] = pr_step["state"]
			t["state_time"] = pr_step["state_time"]
			t["is_hazard"] = pr_step["is_hazard"]
			if str(pr_step["state"]) == "done":
				to_remove.append(i)
				continue
		elif ttype == "mini_ring":
			# T7 mini-jab: anillo de un compás. Mismo motor que los anillos
			# grandes (el jab ES un anillo, con otro tempo).
			var mj_prev: String = str(t.get("state", "telegraph"))
			t["state_time"] = float(t.get("state_time", 0.0)) + delta
			var mj_st: String = str(t.get("state", "telegraph"))
			var mj_t: float = float(t["state_time"])
			if mj_st == "telegraph" and mj_t >= float(t.get("telegraph_beats", 1)) * beat_interval:
				t["state"] = "active"
				t["state_time"] = 0.0
				t["is_hazard"] = true
			elif mj_st == "active" and mj_t >= float(t.get("active_beats", 2)) * beat_interval:
				t["state"] = "fade"
				t["state_time"] = 0.0
				t["is_hazard"] = false
			elif mj_st == "fade" and mj_t >= float(t.get("fade_beats", 1)) * beat_interval:
				t["state"] = "done"
			# T8: el impacto es al ACTIVAR (telegraph -> active)
			if mj_prev == "telegraph" and str(t["state"]) == "active":
				_impact_on_activation(t)
			if str(t["state"]) == "done":
				to_remove.append(i)
				continue
		elif ttype == "mini_fan":
			# T7 mini-jab: abanico de 3 rayos, un compás. Reusa el hueco y la
			# rotación de SpokeFanLogic pero con su propia vida corta.
			t["state_time"] = float(t.get("state_time", 0.0)) + delta
			var mf_st: String = str(t.get("state", "telegraph"))
			var mf_t: float = float(t["state_time"])
			if mf_st == "telegraph" and mf_t >= float(t.get("telegraph_beats", 1)) * beat_interval:
				t["state"] = "active"
				t["state_time"] = 0.0
				t["is_hazard"] = true
			elif mf_st == "active" and mf_t >= float(t.get("active_beats", 2)) * beat_interval:
				t["state"] = "fade"
				t["state_time"] = 0.0
				t["is_hazard"] = false
			elif mf_st == "fade" and mf_t >= float(t.get("fade_beats", 1)) * beat_interval:
				t["state"] = "done"
			if str(t["state"]) == "done":
				to_remove.append(i)
				continue
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
			# T9: el muro sólo hace daño en active. Un "golpe que no daña"
			# venía de que la fase warning se dibujaba casi idéntica a la
			# letal: el jugador veía un muro rojo y no pasaba nada. Ahora la
			# diferencia visual es explícita (línea de borde fina, sin
			# relleno letal) y el daño empieza exactamente cuando el muro
			# se vuelve macizo.
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
		# T8 IMPACTO: un setpiece/jab que ACABÓ de activarse (telegraph ->
		# active) es el momento que se siente: trauma + flash. Se detecta acá,
		# una sola vez para todos los tipos (los Logic ya resolvieron su state).
		if t.get("just_activated", false) and str(t.get("state", "")) == "active" and not bool(t.get("_impact_done", false)):
			t["_impact_done"] = true
			_impact_on_activation(t)
		
		# Telegraph inofensivo: es solo el aviso; el daño lo hace el beam.
		if ttype == "laser_telegraph":
			continue

		# Check collision with player ship (con escudo activo: atravesar todo,
		# sin recibir daño)
		# T9: antes el escudo hacía `continue` y ya: el peligro NI se dañaba
		# NI se consumía NI daba feedback. El jugador atravesaba un abanico
		# entero creyendo que no había nada ("golpea y no daña"). Ahora el
		# escudo consume el peligro (es lo que ES) y deja un destello de
		# bloqueo: ves que tu escudo te salvó, que es información honesta.
		if _shield_active > 0.0:
			if _pilot_hits(t, player_pos) or ttype == "stripe_wall":
				to_remove.append(i)
				_shield_block_flash = 0.12
			continue
		var hit: bool = false
		if ttype == "stripe_wall":
			# Rect-based orientado: proyecta el player en el eje de avance n.
			# Solo daña en fase active (en warning/fade es inofensivo).
			var s_p: float = player_pos.dot(t["wall_n"])
			hit = t.get("state", "active") == "active" \
					and s_p > float(t["s0"]) - 16.0 and s_p < float(t["s1"]) + 16.0
		elif ttype == "spoke_fan":
			# Abanico de rayos: colisión polar vía la lógica pura (hueco seguro).
			hit = _SpokeFanLogic.hits_player(t, player_pos)
		elif ttype == "laser_sweep":
			# Láser que barre: colisión del motor puro.
			hit = _SweepLogic.hits_player(t, player_pos)
		elif ttype == "waveform_wall":
			# Muro de onda: colisión del motor puro (perfil por columna).
			hit = _WaveformLogic.hits_player(t, player_pos)
		elif ttype == "squeeze_corridor":
			# Corredor bilateral: franja izquierda/derecha (motor puro).
			hit = _SqueezeLogic.hits_player(t, player_pos)
		elif ttype == "pulse_rings":
			# Anillos expansivos: banda radial (motor puro).
			hit = _PulseRingsLogic.hits_player(t, player_pos)
		elif ttype == "mini_ring":
			# Mini-jab anillo: banda radial como los anillos grandes, pero con
			# la ventana corta del jab. Reusa el motor construyendo un dict
			# equivalente (mismos keys: state/target_radius/gap_*).
			if str(t.get("state", "")) == "active":
				var mjr: Dictionary = {
					"state": "active", "pos": t["pos"],
					"rings": 1, "target_radius": float(t.get("target_radius", 300.0)),
					"gap_angle": float(t.get("gap_angle", 1.2)),
					"gap_center": float(t.get("gap_center", 0.0)) + float(t.get("spin", 0.0)) * float(t.get("state_time", 0.0)),
					"gap_spin": 0.0, "beat_len": beat_interval,
					"active_beats": 1, "telegraph_beats": 0, "fade_beats": 1,
					"state_time": float(t.get("state_time", 0.0)),
				}
				hit = _PulseRingsLogic.hits_player(mjr, player_pos)
		elif ttype == "mini_fan":
			# Mini-jab abanico: 3 rayos con hueco, en su ventana corta.
			if str(t.get("state", "")) == "active":
				var mjf: Dictionary = {
					"state": "active", "pos": t["pos"],
					"spokes": int(t.get("spokes", 3)), "gap_spokes": int(t.get("gap_spokes", 1)),
					"gap_first": int(t.get("gap_first", 0)), "radius": float(t.get("radius", 260.0)),
					"rot_speed": float(t.get("rot_speed", 0.0)),
					"telegraph_beats": 0, "state_time": float(t.get("state_time", 0.0)),
				}
				hit = _SpokeFanLogic.hits_player(mjf, player_pos)
		elif ttype == "laser_beam":
			# Line-based: distancia del player a la línea infinita del beam
			var bdir: Vector2 = (t.get("beam_dir", Vector2.UP) as Vector2).normalized()
			var to_p: Vector2 = player_pos - (t["pos"] as Vector2)
			var perp: float = absf(to_p.dot(Vector2(-bdir.y, bdir.x)))
			hit = perp < float(t["radius"]) + 16.0
		else:
			hit = player_pos.distance_to(t["pos"]) < (float(t.get("radius", 24.0)) + 16.0)
		if hit:
			# T9: el I-frame protege SOLO al jugador, no al peligro. Antes
			# el objeto se consumía igual: el jugador cruzaba el abanico o
			# el muro durante los 2s de invulnerabilidad y se lo comía sin
			# ver nada ("golpea y no daña"). Ahora el peligro SIGUE VIVO y el
			# jugador lo atraviesa protegido; si vuelve a tocarlo cuando ya
			# no tiene iframes, ahí sí duele (que es lo justo: el aviso se
			# sintió, el golpe se cuenta una vez).
			if _hit_iframes <= 0.0:
				to_remove.append(i)
				_on_hazard_hit(float(t.get("hit_health_bonus", -1.0)), ttype)
			continue

		# Fuera de pantalla (stripe_wall se autogestiona su ciclo)
		if ttype != "stripe_wall" and t["pos"].y > 740:
			to_remove.append(i)
				
	to_remove.reverse()
	for idx in to_remove:
		if idx < targets.size():
			targets.remove_at(idx)

func _on_hazard_hit(source_bonus: float = -1.0, source_type: String = "") -> void:
	_hit_iframes = HIT_IFRAMES_EASY if easy_mode else HIT_IFRAMES
	_damage_flash = 1.0
	_shake_time = SHAKE_TIME
	# T8: hit-stop — la escena congela 50ms, la CANCIÓN SIGUE (por eso el
	# reloj del nivel no se desincroniza). Nunca se apila (el motor devuelve
	# la pausa viva) y nunca durante un telegraph (sólo con iframes).
	var still_frozen: bool = Time.get_ticks_msec() / 1000.0 < _hitstop_until
	var hs: Dictionary = _ImpactFeel.request_hitstop(0.05, true, 0.05 if still_frozen else 0.0)
	var applied: float = float(hs["applied"])
	if applied > 0.0:
		_hitstop_until = Time.get_ticks_msec() / 1000.0 + applied
	# Daño por golpe.
	#
	# BUG (T10, reportado por el usuario: "toco algo y la vida no baja" y
	# "algunos enemigos hacen menos daño que otros"). El código anterior
	# trataba hit_health_bonus como MULTIPLICADOR:
	#     dmg = 12 (easy) * abs(bonus) / 18
	# o sea que el número del enemigo se dividía y el resultado siempre
	# terminaba cerca de 12: un setpiece que pedía 18 clavaba 12, y una
	# sierra que pedía 15 clavaba 10. El daño no venía del enemigo, venía
	# de una división accidental — de ahí que algunos "enemigos" pegaran
	# menos y otros parecieran no pegar.
	#
	# La semántica correcta es la obvious: hit_health_bonus ES el daño.
	# Negativo = daño, positivo = curación (ningún enemigo la usa hoy).
	var dmg: float = source_bonus if source_bonus != 0.0 else (12.0 if easy_mode else 18.0)
	# Los mini-jabs (puntuales) no pegan igual que un setpiece (un momento):
	# mantienen su -8 explícito. Un setpiece en easy sigue siendo el tope
	# cómodo del tutorial.
	health -= dmg
	# T9: diagnóstico de por qué murió el piloto (qué peligro lo tomó y a qué
	# hora de la canción). Sólo con el flag, para no ensuciar la corrida real.
	if OS.get_environment("MCP_HITLOG") == "1" or FileAccess.file_exists("/tmp/jsab_hitlog.flag"):
		print("[HIT] t=%.1f %s dmg=%.0f hp=%.0f" % [song_time, source_type, dmg, health])
	if SoundManager: SoundManager.play_back()

	if health <= 0.0:
		_trigger_game_over()

## T8: un setpiece/jab se activó. Trauma de cámara + flash blanco, escalados
## por la energía de la sección (un golpe en el breakdown no se siente como
## uno en el drop) y por el tipo (ancla vs punctuación de jab).
func _impact_on_activation(t: Dictionary) -> void:
	var sec_energy: float = 0.6
	if controller and controller.has_method("_current_section"):
		var sec: Dictionary = controller._current_section(song_time)
		if not sec.is_empty():
			sec_energy = float(sec.get("energy", 0.6))
	var is_anchor: bool = bool(t.get("setpiece_phase", false))
	var kind_scale: float = 1.0 if is_anchor else 0.45
	_impact = _ImpactFeel.new_impact(1.0, sec_energy, kind_scale)
	# el temblor de daño (rojo) y el de impacto (blanco) se suman: el golpe
	# feels distinto al de un setpiece activándose.
	_shake_time = maxf(_shake_time, _ImpactFeel.DECAY_BEATS * beat_interval)

## T9: el punto que el piloto quiere alcanzar este frame. El setpiece (o jab)
## vivo MANDA —es el momento del nivel— y sólo si no hay ninguno se esquivan
## los proyectiles sueltos. La decisión es la misma que test_pilot valida
## contra la colisión real.
func _pilot_desired(frame_dt: float) -> Vector2:
	var best_target: Vector2 = player_pos
	var best_priority: float = -1.0
	# 1) Si hay un setpiece/jab VIVO, él manda: es el momento del nivel.
	for t in targets:
		var ty_sp: String = str(t.get("type", ""))
		if ty_sp not in ["spoke_fan", "laser_sweep", "waveform_wall", "squeeze_corridor",
				"pulse_rings", "mini_ring", "mini_fan", "stripe_wall"]:
			continue
		# ¿estamos en peligro AHORA con este? -> máxima prioridad, y el punto
		# tiene que seguir libre al llegar (predicción).
		if _pilot_hits(t, player_pos):
			return _pilot_safe_in_field(t, player_pos, frame_dt)
		# si no hay peligro inmediato, un punto seguro de este setpiece sirve
		# como destino — PERO un setpiece no es el único peligro: la sierra
		# que cayó dentro de su hueco igual mata (el panel 06_fan_d.png de la
		# revisión visual). Buscamos el punto que sea seguro para el setpiece
		# Y para todo lo demás que esté vivo.
		if str(t.get("state", "")) in ["telegraph", "active"]:
			return _pilot_safe_in_field(t, player_pos, frame_dt)
	# 2) Sólo proyectiles sueltos: elegir el punto LIBRE más cercano (el piloto
	#    barre la pantalla como un humano, no huye de un saw y se mete en otro).
	return _best_free_spot(frame_dt)

## ¿el punto está dentro de este objetivo? Usa la MISMA colisión del juego.
func _pilot_hits(t: Dictionary, p: Vector2) -> bool:
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
## La revisión visual (space-bunny, 06_fan_d.png) encontró una sierra parada
## DENTRO del hueco del abanico: el jugador leía bien el hueco y moría igual,
## porque "el hueco es seguro" era una promesa falsa. Ahora el destino tiene
## que estar libre para el setpiece Y para todo lo demás que esté en pantalla,
## y seguir libre al llegar.
func _pilot_safe_in_field(anchor: Dictionary, from: Vector2, frame_dt: float) -> Vector2:
	var base: Vector2 = _PilotLogic.safe_point_eta(anchor, from, _PILOT_SPEED, frame_dt)
	if not _field_blocks(base):
		return base
	# el punto del setpiece está tapado por otra cosa: buscamos alrededor
	var hub: Vector2 = anchor.get("pos", Vector2(640, 400))
	for r_i in range(7):
		for a_i in range(20):
			var rr: float = lerpf(110.0, 430.0, float(r_i) / 6.0)
			var aa: float = TAU * float(a_i) / 20.0
			var c: Vector2 = Vector2(clampf(hub.x + cos(aa) * rr, 90.0, 1190.0),
				clampf(hub.y + sin(aa) * rr, 200.0, 630.0))
			if not _field_blocks(c) and not _pilot_hits(anchor, c):
				return c
	for gx in [160.0, 380.0, 640.0, 900.0, 1120.0]:
		for gy in [220.0, 400.0, 560.0]:
			var g: Vector2 = Vector2(gx, gy)
			if not _field_blocks(g) and not _pilot_hits(anchor, g):
				return g
	# todo tapado: nos alejamos del hub, que es lo menos malo
	return Vector2(clampf(from.x, 120.0, 1160.0), clampf(from.y - 200.0, 200.0, 600.0))

## ¿Algún peligro (de cualquier tipo) ocupa este punto?
func _field_blocks(p: Vector2) -> bool:
	for t in targets:
		if _pilot_hits(t, p):
			return true
	return false

## El punto LIBRE más cercano. El piloto anterior huía de UN saw y se
## metía en el siguiente (5 de los 10 golpes de la corrida instrumentada
## fueron saws). Esto puntúa una rejilla de candidatos contra TODA la
## geometría viva y elige el más seguro y alcanzable — que es lo que hace un
## jugador que mira la pantalla en vez de reaccionar a un solo objeto.
func _best_free_spot(frame_dt: float) -> Vector2:
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
			for t in targets:
				if _pilot_hits(t, c):
					clear_now = false
					break
			if not clear_now:
				continue
			# ¿libre al llegar? (el juego sigue corriendo mientras viaja)
			var clear_eta: bool = true
			var dist: float = c.distance_to(player_pos)
			var n_steps: int = clampi(int(ceil(dist / maxf(_PILOT_SPEED * frame_dt, 1.0))) + 1, 1, 24)
			for s in range(1, n_steps + 1):
				var p: Vector2 = player_pos.lerp(c, float(s) / float(n_steps))
				for t2 in targets:
					if _pilot_hits(t2, p):
						clear_eta = false
						break
				if not clear_eta:
					break
			if not clear_eta:
				continue
			# Puntaje: seguridad (ya filtrada) + preferencia por el centro
			# preferencia por la fila del jugador (y media) y por no movernos mucho
			var score: float = 200.0
			score -= dist * 0.35
			score -= absf(c.y - 470.0) * 0.25
			for t3 in targets:
				if t3.has("pos"):
					score += minf(c.distance_to(t3["pos"]), 400.0) * 0.18
			if score > best_score:
				best_score = score
				best = c
	return best

## Huir de un proyectil suelto: alejarse en la dirección opuesta.
func _flee_from(t: Dictionary) -> Vector2:
	if not t.has("pos"):
		return player_pos
	var d: Vector2 = player_pos - (t["pos"] as Vector2)
	if d.length() < 0.01:
		return Vector2(640, 300)
	return Vector2(clampf(player_pos.x + d.normalized().x * 150.0, 40.0, 1240.0),
		clampf(player_pos.y + d.normalized().y * 150.0, 150.0, 640.0))

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
	if progress_lbl:
		progress_lbl.text = "PROGRESO: %d%%" % progress_pct

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
	music.stop()   # la cancion termino: cortar antes de resultados
	var is_new_hs: bool = false
	if GameManager:
		is_new_hs = GameManager.save_score(track_data.get("id", "procedural_mvp"), 100)

	results_title_lbl.text = "¡NIVEL PROCEDURAL COMPLETADO!"
	results_title_lbl.add_theme_color_override("font_color", Color(0, 1, 0.5, 1))
	results_details_lbl.text = "Progreso Final: 100%%\n%s" % ("¡NUEVO RÉCORD DE PROGRESO!" if is_new_hs else "")
	results_overlay.visible = true

func _trigger_game_over() -> void:
	is_game_over = true
	music.stop()   # cortar la musica al instante: la derrota se escucha
	SoundManager.play_defeat()
	var is_new_hs: bool = false
	if GameManager:
		is_new_hs = GameManager.save_score(track_data.get("id", "procedural_mvp"), progress_pct)
	results_title_lbl.text = "MISIÓN FALLIDA"
	results_title_lbl.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 1))
	results_details_lbl.text = "Progreso Logrado: %d%%\n%s" % [progress_pct, ("¡NUEVO RÉCORD DE PROGRESO!" if is_new_hs else "")]
	results_overlay.visible = true

# --- Pause & Results Overlay Signals ---

func _on_btn_resume_pressed() -> void:
	toggle_pause()

func _on_btn_restart_pressed() -> void:
	get_tree().paused = false
	# T9: reiniciar recargaba la ESCENA completa (nodos, chart, audio, HUD).
	# Con el audio cacheado el audio es instantáneo, pero el resto de la
	# reconstrucción seguía costando. Ahora reiniciamos el ESTADO del nivel
	# sin reconstruir la escena: el jugador vuelve a jugar de inmediato.
	# _restart_level() deja todo como _ready() lo dejó, pero con el chart y
	# el audio ya en memoria.
	_restart_level()

## Reinicio en caliente: mismo estado inicial, sin reconstruir la escena.
func _restart_level() -> void:
	song_time = 0.0
	health = 125.0 if easy_mode else 100.0
	is_game_over = false
	progress_pct = 0
	_music_finished = false
	_damage_flash = 0.0
	_shake_time = 0.0
	_hit_iframes = 0.0
	_shield_active = 0.0
	_shield_cooldown = 0.0
	_impact = {}
	_hitstop_until = 0.0
	_waiting_for_control = false
	_manual_control = false
	player_pos = play_size() * Vector2(0.5, 0.78)
	targets.clear()
	if controller:
		controller.reset_level()
	music.stop()
	music.play()
	if results_overlay:
		results_overlay.visible = false
	if pause_overlay:
		pause_overlay.visible = false
	queue_redraw()

func _on_btn_main_menu_pressed() -> void:
	get_tree().paused = false
	if GameManager:
		GameManager.change_scene("res://scenes/MainMenu.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _draw() -> void:
	# T8: el trauma de impacto se SUMA al temblor de daño (un solo
	# draw_set_transform: el segundo sobrescribiría al primero). El temblor
	# de impacto es determinista (dos senos), el de daño aleatorio.
	var world_offset: Vector2 = Vector2.ZERO
	if _shake_time > 0.0:
		var sk: float = pow(_shake_time / SHAKE_TIME, 2.0) * SHAKE_AMP
		world_offset += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * sk
	if not _impact.is_empty() and float(_impact.get("trauma", 0.0)) > 0.001:
		world_offset += _ImpactFeel.shake_offset(_impact, 26.0)
	if world_offset != Vector2.ZERO:
		draw_set_transform(world_offset, 0.0, Vector2.ONE)
	# T8 FLASH BLANCO de impacto: cubre TODO, sin temblor (el blanco es la
	# luz, no el golpe). Sólo cuando un setpiece/jab se activa; decae antes
	# que el trauma y dura 2 beats como máximo.
	var impact_flash: float = float(_impact.get("flash", 0.0)) if not _impact.is_empty() else 0.0
	if impact_flash > 0.002:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(Vector2.ZERO, play_size()), Color(1.0, 1.0, 1.0, impact_flash * 0.22))
	# Pulso visual sincronizado con la música: flash de kick en cada beat,
	# anillo expansivo en los hits de snare (beats 2 y 4 del compás).
	# T5: la INTENSIDAD escala con la energía de la sección — el drop se VE
	# más intenso que la intro; el clímax (drop2) es el pico visual.
	if song_time > 0.0 and not is_game_over and beat_interval > 0.0:
		var bn: float = song_time / beat_interval
		var in_bar: float = fmod(bn, 4.0)
		var bp: float = fmod(bn, 1.0)
		var kick: float = clampf(1.0 - bp * 6.0, 0.0, 1.0)
		# Energía 0.3 (intro/outro) -> flash tenue; 0.9 (drop2) -> flash pleno.
		var energy_gain: float = clampf(0.35 + 0.65 * section_energy, 0.0, 1.0)
		if kick > 0.0:
			draw_rect(Rect2(Vector2.ZERO, play_size()),
					Color(0.35, 0.55, 1.0, 0.03 * energy_gain * kick))
		if (in_bar >= 1.0 and in_bar < 1.25) or (in_bar >= 3.0 and in_bar < 3.25):
			var sr: float = clampf(fmod(in_bar, 1.0) * 4.0, 0.0, 1.0)
			draw_arc(play_size() * 0.5, 40.0 + sr * 90.0, 0, TAU, 44,
					Color(0.5, 0.8, 1.0, 0.11 * energy_gain * (1.0 - sr)), 3.0)

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
	# Fondo: oscuro normal, pero en critico pulsa rojo para avisar aunque el
	# arco sea chico (25% o menos apenas ocupa un cuadrante).
	var hp_bg := Color(0.1, 0.1, 0.14, 0.75 * hp_dim)
	if health <= 30.0:
		var crit_pulse: float = 0.5 + 0.5 * absf(sin(Time.get_ticks_msec() * 0.016))
		hp_bg = Color(1.0, 0.15, 0.2, (0.25 + 0.45 * crit_pulse) * hp_dim)
	draw_arc(player_pos, 27.0, 0, TAU, 48, hp_bg, 7.0)
	if hp_frac > 0.0:
		var hp_soft := Color(hp_col.r, hp_col.g, hp_col.b, 0.9 * hp_dim)
		draw_arc(player_pos, 27.0, -PI / 2.0, -PI / 2.0 + TAU * hp_frac, 48, hp_soft, 7.0)
		var hp_hot := Color(minf(hp_col.r + 0.6, 2.0), minf(hp_col.g + 0.6, 2.0), minf(hp_col.b + 0.6, 2.0), hp_dim)
		draw_arc(player_pos, 27.0, -PI / 2.0, -PI / 2.0 + TAU * hp_frac, 48, hp_hot, 2.5)
	# Relleno de la flecha: la nave "se vacia" al perder vida (redundancia
	# cercana al anillo; el contorno neon queda intacto). En critico el
	# relleno hereda el alpha pulsante del color para no pelear con el anillo.
	var hp_fill := hp_col
	if health > 30.0:
		hp_fill.a = (0.25 + 0.55 * hp_frac) * ship_blink * hp_dim
	else:
		hp_fill.a *= ship_blink * hp_dim
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
		# T9: destello de BLOQUEO — el escudo acaba de comerse un peligro.
		# Sin esto el jugador atravesaba un abanico entero sin ninguna señal
		# de que su escudo lo había salvado.
		if _shield_block_flash > 0.0:
			var b: float = _shield_block_flash / 0.12
			_neon_arc(player_pos, 38.0 + 10.0 * (1.0 - b), Color(1.4, 1.4, 1.4, 0.9 * b), 3.5)
			draw_circle(player_pos, 34.0 + 12.0 * (1.0 - b), Color(0.8, 1.0, 1.0, 0.10 * b))

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

	# Draw targets & hazards — tres pasadas: el muro se dibuja DESPUES de los
	# hazards, por lo que los deja ver a traves de la banda sin que una sierra
	# se pinte encima del rojo. Los lasers van al final para no quedar tapados.
	#   1) hazards comunes, 2) stripe_wall translúcido encima, 3) lasers arriba
	#    (el telegraph debe ser imposible de ignorar, jamas tapado).
	#
	# T9: la pasada 1 se ORDENA por lethality (PatternLanguage.draw_sort):
	# lo que más mata se dibuja ENCIMA. Antes el orden era el de aparición y
	# un fan podía quedar tapado por un saw que pasó después — el jugador
	# veía un peligro tapado por decoración y no sabía cuál esquivar.
	var layer1: Array[Dictionary] = []
	for t in targets:
		var tt: String = t.get("type", "target")
		if tt == "stripe_wall" or tt == "laser_telegraph" or tt == "laser_beam":
			continue
		layer1.append(t)
	layer1.sort_custom(_PatternLanguage.draw_sort)
	for t in layer1:
		_draw_one_target(t)
	for t in targets:
		if t.get("type", "target") != "stripe_wall":
			continue
		_draw_one_target(t)
	for t in targets:
		var tt2: String = t.get("type", "target")
		if tt2 != "laser_telegraph" and tt2 != "laser_beam":
			continue
		_draw_one_target(t)
