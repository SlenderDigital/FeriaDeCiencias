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
const _DevTools: GDScript = preload("res://scripts/DevTools.gd")
const _SetpieceRenderer: GDScript = preload("res://scripts/SetpieceRenderer.gd")
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

var chart: ChartData
var controller: PatternController
var song: ProceduralSong
var next_beat_idx: int = 0
var track_data: Dictionary = {}
var bpm: float = 132.0
var song_time: float = 0.0
var total_song_duration: float = 60.0 # 60 seconds procedural MVP level
var beat_interval: float = 60.0 / 132.0

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
# Invulnerabilidad post-golpe: anti-multihit del MISMO frame, no perdón.
# Cada contacto con peligro activo DAÑA (se puede morir encadenando golpes);
# la ventana corta evita que 3 objetos el mismo frame instakilleen.
const HIT_IFRAMES: float = 0.5
const HIT_IFRAMES_EASY: float = 0.7
var _hit_iframes: float = 0.0
# easy_mode: nivel 1 (First Light) - mas margen. Niveles 2-3 intactos.
var easy_mode: bool = false
# Juice de daño: flash rojo de pantalla + vibracion al recibir un golpe.
const SHAKE_TIME: float = 0.25
const SHAKE_AMP: float = 12.0
# Antigüedad máxima de un paquete de landmarks para que la mano siga
# "guiando": más viejo que esto, el teclado recupera el control.
const _HAND_FRESH_SEC: float = 0.35
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
var max_health: float = 100.0
# Anillo de vida: solo visible unos segundos tras recibir daño. Fuera de eso,
# la vida se lee en el RELLENO de la flecha (más lleno = más vida).
const HP_RING_TIME: float = 3.0
var _hp_ring_timer: float = 0.0
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
		
	bpm = track_data.get("bpm", 132.0)
	beat_interval = 60.0 / bpm

	_setup_neon_glow()
	_setup_bursts()
	
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
			max_health = 125.0
			health = 125.0   # un golpe extra de margen en el tutorial
			print("[Gameplay] easy_mode ON (First Light): hazards x0.85, warn muros 2.5 beats, iframes 0.7s")
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
	# Pause-menu rework: the tree pause freezes every INHERIT node, including
	# Controls. Overlays + this script must be ALWAYS so ESC toggles and all
	# popup buttons stay clickable while paused. _process early-returns on
	# is_paused so gameplay logic still freezes; only input/UI keeps running.
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	results_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	results_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
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
	set_paused(not is_paused)


## Pause state single source of truth. All pause writes go through here so
## overlay visibility, tree pause, music pause and button focus stay in sync.
## Nodes use PROCESS_MODE_ALWAYS (set in _ready) so ESC + buttons work while
## get_tree().paused == true. Without that, Controls inherit INHERIT and
## freeze with the tree — the reported "ESC popup buttons dead" bug.
func set_paused(value: bool) -> void:
	if is_game_over and value:
		return
	is_paused = value
	pause_overlay.visible = is_paused
	get_tree().paused = is_paused or _debug_visible
	music.stream_paused = is_paused
	if is_paused:
		var resume_btn: Button = pause_overlay.get_node_or_null("Panel/VBox/BtnResume") as Button
		if resume_btn:
			resume_btn.grab_focus()
	if SoundManager: SoundManager.play_click()


# --- Debug: saltar entre niveles al instante (F6). UI y estado en DevTools.
func _toggle_debug_menu() -> void:
	_DevTools.toggle_debug(self)


func _restart_with_level(index: int) -> void:
	if GameManager and index >= 0 and index < GameManager.TRACKS.size():
		GameManager.select_track(index)
	get_tree().paused = false
	if GameManager:
		GameManager.change_scene("res://scenes/Gameplay.tscn")
	else:
		get_tree().reload_current_scene()


func _process(delta: float) -> void:
	# Capturas de verificación (piloto): solo con flags, nunca en partida real.
	_DevTools.capture_shots(self)
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
		_autoplay_target = _DevTools.pilot_desired(self, delta)
		player_pos = _PilotLogic.steer_step(player_pos, _autoplay_target, _DevTools.PILOT_SPEED, delta)

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
		track_title_lbl.text = "%s  |  BPM: %d" % [track_data.get("name", "Nivel"), int(bpm)]
		
	# Check level completion: victory only when the music has genuinely
	# reached the end of the track, per the real playback clock.
	# `music.finished` is a Signal (always truthy if used as a bool), so we
	# track actual completion via a signal-connected flag and guard both
	# paths with an elapsed time margin to avoid an instant-win.
	var reached_end: bool = chart != null and song_time >= chart.duration and song_time > 1.0
	if reached_end or (_music_finished and song_time > 1.0):
		_trigger_victory()
		return
		
	# --- Spawning: chart-driven beats from the real playback pointer.
	# chart siempre existe (nivel procedural con chart compuesto por el motor).
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
	# El abanico limpia su arena al anclar: las sierras sueltas que quedaron
	# dentro del rotor se expulsan fuera del aro (con anillo de aviso, como un
	# spawn). Sin esto una sierra vieja queda parada DENTRO del hueco o sobre
	# el hub y el jugador muere leyendo bien el pasillo. Solo reubica, no
	# elimina: el conteo de peligros no cambia.
	for s in spawns:
		if s.get("type", "") == "spoke_fan" and str(s.get("state", "")) == "telegraph":
			_expel_from_fan(s)
			break


## Expulsa proyectiles sueltos del disco del abanico recién anclado.
func _expel_from_fan(fan: Dictionary) -> void:
	var hub: Vector2 = fan.get("pos", play_size() * 0.5)
	var rim: float = float(fan.get("radius", 300.0)) + 70.0
	var ps: Vector2 = play_size()
	for t in targets:
		if t == fan:
			continue
		if str(t.get("type", "")) not in ["saw", "saw_pair", "saw_weave", "drifter", "drifter_swarm", "homing", "hazard"]:
			continue
		if not t.has("pos"):
			continue
		var d: Vector2 = (t["pos"] as Vector2) - hub
		if d.length() > rim:
			continue
		var dir: Vector2 = d.normalized() if d.length_squared() > 1.0 else Vector2.RIGHT
		var dest: Vector2 = hub + dir * rim
		dest.x = clampf(dest.x, 60.0, ps.x - 60.0)
		dest.y = clampf(dest.y, 90.0, ps.y - 60.0)
		t["pos"] = dest
		t["_age"] = 0.0

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

# --- Partículas GPU (requisito 17/09): dos emisores one-shot creados por
# código (como el overlay de daño): burst rojo al activarse cada setpiece y
# burst grande en la nave al morir. Nodos GPUParticles2D reales del motor
# (visibles en el árbol remoto), no solo chispas dibujadas.
var _setpiece_burst: GPUParticles2D
var _death_burst: GPUParticles2D

func _burst_texture() -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)

func _make_burst(amount: int, lifetime: float, color: Color, speed_min: float, speed_max: float, scale_min: float, scale_max: float) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.texture = _burst_texture()
	p.emitting = false
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 12.0
	m.direction = Vector3(0, 0, 0)
	m.spread = 180.0
	m.initial_velocity_min = speed_min
	m.initial_velocity_max = speed_max
	m.damping_min = 60.0
	m.damping_max = 140.0
	m.scale_min = scale_min
	m.scale_max = scale_max
	m.color = color
	p.process_material = m
	return p

func _setup_bursts() -> void:
	_setpiece_burst = _make_burst(48, 0.7, Color(1.0, 0.25, 0.35), 160.0, 340.0, 1.5, 3.0)
	_setpiece_burst.name = "SetpieceBurst"
	add_child(_setpiece_burst)
	_death_burst = _make_burst(90, 1.1, Color(0.6, 0.95, 1.0), 120.0, 420.0, 2.0, 4.5)
	_death_burst.name = "DeathBurst"
	add_child(_death_burst)

func _fire_burst(p: GPUParticles2D, at: Vector2) -> void:
	if p == null:
		return
	p.position = at
	p.restart()

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
	if _hp_ring_timer > 0.0:
		_hp_ring_timer = maxf(_hp_ring_timer - delta, 0.0)
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
			# Standard movement (sierras, derivas, misiles: proyectiles que
			# entran por arriba). "_age" alimenta su telegrafía de aparición.
			t["pos"] += t["vel"] * delta
			if ttype in ["saw", "saw_pair", "saw_weave", "drifter", "drifter_swarm", "homing", "hazard", "perimeter"]:
				t["_age"] = float(t.get("_age", 0.0)) + delta
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
			if _DevTools.pilot_hits(t, player_pos, player_pos) or ttype == "stripe_wall":
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
			# Cada contacto con peligro activo DAÑA (el jugador puede morir
			# encadenando golpes). El i-frame corto es solo anti-multihit del
			# mismo frame: el peligro se consume y el siguiente contacto tras
			# la ventana vuelve a doler. Sin perdón de 2s.
			if _hit_iframes <= 0.0:
				to_remove.append(i)
				var hpos: Vector2 = t.get("pos", player_pos)
				_on_hazard_hit(float(t.get("hit_health_bonus", -1.0)), ttype, hpos)
			continue

		# Fuera de pantalla (stripe_wall se autogestiona su ciclo)
		if ttype != "stripe_wall" and t["pos"].y > 740:
			to_remove.append(i)
				
	to_remove.reverse()
	for idx in to_remove:
		if idx < targets.size():
			targets.remove_at(idx)

func _on_hazard_hit(source_bonus: float = -1.0, _source_type: String = "", _source_pos: Vector2 = Vector2(1.0e9, 1.0e9)) -> void:
	_hit_iframes = HIT_IFRAMES_EASY if easy_mode else HIT_IFRAMES
	_damage_flash = 1.0
	_shake_time = SHAKE_TIME
	_hp_ring_timer = HP_RING_TIME
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
	# health += dmg (dmg negativo resta vida; el -= anterior CURABA).
	var dmg: float = source_bonus if source_bonus != 0.0 else (-12.0 if easy_mode else -18.0)
	# Los mini-jabs (puntuales) no pegan igual que un setpiece (un momento):
	# mantienen su -8 explícito. Un setpiece en easy sigue siendo el tope
	# cómodo del tutorial.
	health = clampf(health + dmg, 0.0, max_health)
	# T9: diagnóstico de por qué murió el piloto (qué peligro lo tomó y a qué
	# hora de la canción). Sólo con el flag, para no ensuciar la corrida real.
	if OS.get_environment("MCP_HITLOG") == "1" or FileAccess.file_exists("/tmp/jsab_hitlog.flag"):
		print("[HIT] t=%.1f %s dmg=%.0f hp=%.0f" % [song_time, _source_type, -dmg, health])
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
	# Burst GPU en el setpiece que se activó (partículas reales del motor).
	var at: Vector2 = player_pos
	var maybe = t.get("pos", null)
	if maybe is Vector2:
		at = maybe
	_fire_burst(_setpiece_burst, at)

func _health_color() -> Color:
	## Color de vida compartido: lo usa el anillo de la nave. Verde >60%,
	## ambar >30%, rojo pulsante en critico (fracción de max_health).
	var frac: float = clampf(health / maxf(max_health, 1.0), 0.0, 1.0)
	if frac > 0.6:
		return Color(0.2, 1.0, 0.45)
	elif frac > 0.3:
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
	is_paused = false
	get_tree().paused = false
	music.stop()   # la cancion termino: cortar antes de resultados
	music.stream_paused = false
	var is_new_hs: bool = false
	if GameManager:
		is_new_hs = GameManager.save_score(track_data.get("id", "procedural_mvp"), 100)

	results_title_lbl.text = "¡NIVEL PROCEDURAL COMPLETADO!"
	results_title_lbl.add_theme_color_override("font_color", Color(0, 1, 0.5, 1))
	results_details_lbl.text = "Progreso Final: 100%%\n%s" % ("¡NUEVO RÉCORD DE PROGRESO!" if is_new_hs else "")
	results_overlay.visible = true

func _trigger_game_over() -> void:
	is_game_over = true
	is_paused = false
	get_tree().paused = false
	music.stop()   # cortar la musica al instante: la derrota se escucha
	music.stream_paused = false
	_fire_burst(_death_burst, player_pos)
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
	set_paused(false)

func _on_btn_restart_pressed() -> void:
	is_paused = false
	_debug_visible = false
	if _debug_overlay:
		_debug_overlay.visible = false
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
	next_beat_idx = 0
	max_health = 125.0 if easy_mode else 100.0
	health = max_health
	is_game_over = false
	progress_pct = 0
	_music_finished = false
	_damage_flash = 0.0
	_hp_ring_timer = 0.0
	_shake_time = 0.0
	_hit_iframes = 0.0
	_shield_active = 0.0
	_shield_cooldown = 0.0
	_shield_block_flash = 0.0
	_shield_was_ready = true
	_fist_was_closed = false
	_impact = {}
	_hitstop_until = 0.0
	_waiting_for_control = false
	_manual_control = false
	section_energy = 0.5
	section_name = ""
	player_pos = play_size() * Vector2(0.5, 0.78)
	_autoplay_target = player_pos
	_trail_last = Vector2(-9999.0, -9999.0)
	targets.clear()
	spark_effects.clear()
	if _damage_overlay:
		_damage_overlay.color = Color(1.0, 0.08, 0.14, 0.0)
	if controller:
		controller.play_size = play_size()
		controller.reset_level()
	if bg_control and bg_control.has_method("set_song_clock"):
		bg_control.set_song_clock(0.0, beat_interval)
	music.stop()
	music.stream_paused = false
	music.play()
	if results_overlay:
		results_overlay.visible = false
	if pause_overlay:
		pause_overlay.visible = false
	queue_redraw()

func _on_btn_main_menu_pressed() -> void:
	is_paused = false
	_debug_visible = false
	get_tree().paused = false
	music.stream_paused = false
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
	_SetpieceRenderer.neon_polyline(self, PackedVector2Array([nose, p2, p3, nose]), ship_col, 4.0)
	_SetpieceRenderer.neon_line(self, player_pos, player_pos + fwd * 28.0, Color(1, 1, 1, ship_blink), 2.0)
	draw_circle(player_pos, 5.0, Color(1.0, 1.0, 1.0, ship_blink))
	# VIDA EN LA NAVE: anillo concentrico r=27 (nave r~24, escudo r=34: no se
	# pisan). Solo visible HP_RING_TIME tras cada golpe: lo perdido en ROJO,
	# lo que queda en el color de vida. El resto del tiempo la vida se lee en
	# el RELLENO de la flecha. El parpadeo de i-frames NO toca el anillo.
	var hp_frac: float = clampf(health / maxf(max_health, 1.0), 0.0, 1.0)
	var hp_col: Color = _health_color()
	var hp_dim: float = 0.7 if _shield_active > 0.0 else 1.0  # la burbuja manda
	if _hp_ring_timer > 0.0:
		var ring_a: float = clampf(_hp_ring_timer / 1.0, 0.0, 1.0) * hp_dim
		# Base: pista oscura completa para que el anillo se lea sobre cualquier fondo.
		draw_arc(player_pos, 27.0, 0, TAU, 48, Color(0.1, 0.1, 0.14, 0.75 * ring_a), 7.0)
		# Faltante en rojo: del fin de la vida hasta el círculo completo.
		if hp_frac < 1.0:
			var miss_from: float = -PI / 2.0 + TAU * hp_frac
			var miss_to: float = -PI / 2.0 + TAU
			var miss_a: float = ring_a
			if hp_frac <= 0.3:
				miss_a *= 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.016))
			draw_arc(player_pos, 27.0, miss_from, miss_to, 48, Color(1.0, 0.15, 0.2, 0.9 * miss_a), 7.0)
			draw_arc(player_pos, 27.0, miss_from, miss_to, 48, Color(1.8, 0.4, 0.45, 0.9 * miss_a), 2.5)
		if hp_frac > 0.0:
			var hp_soft := Color(hp_col.r, hp_col.g, hp_col.b, 0.9 * ring_a)
			draw_arc(player_pos, 27.0, -PI / 2.0, -PI / 2.0 + TAU * hp_frac, 48, hp_soft, 7.0)
			var hp_hot := Color(minf(hp_col.r + 0.6, 2.0), minf(hp_col.g + 0.6, 2.0), minf(hp_col.b + 0.6, 2.0), ring_a)
			draw_arc(player_pos, 27.0, -PI / 2.0, -PI / 2.0 + TAU * hp_frac, 48, hp_hot, 2.5)
	# Relleno de la flecha: el medidor SIEMPRE visible de vida (el anillo solo
	# sale tras cada golpe). Más opaco = más vida; al vaciarse la nave se ve
	# hueca. El contorno neon queda intacto.
	var hp_fill := hp_col
	if hp_frac > 0.3:
		hp_fill.a = (0.12 + 0.68 * hp_frac) * ship_blink * hp_dim
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
		_SetpieceRenderer.neon_polyline(self, pts, Color(0.55, 1.0, 1.0, 0.35 + 0.55 * life), 2.5)
		draw_circle(player_pos, 30.0 + wob, Color(0.55, 1.0, 1.0, 0.07 * life))
		# Aviso de fin: parpadea mas rapido cuanto menos vida le queda
		if life < 0.35 and fposmod(tnow * (4.0 + 20.0 * (0.35 - life)), 1.0) < 0.5:
			_SetpieceRenderer.neon_arc(self, player_pos, 30.0, Color(0.4, 0.9, 1.0, 0.4), 1.5)
		# T9: destello de BLOQUEO — el escudo acaba de comerse un peligro.
		# Sin esto el jugador atravesaba un abanico entero sin ninguna señal
		# de que su escudo lo había salvado.
		if _shield_block_flash > 0.0:
			var b: float = _shield_block_flash / 0.12
			_SetpieceRenderer.neon_arc(self, player_pos, 38.0 + 10.0 * (1.0 - b), Color(1.4, 1.4, 1.4, 0.9 * b), 3.5)
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
		_SetpieceRenderer.draw_target(self, t, beat_interval, song_time, play_size())
	for t in targets:
		if t.get("type", "target") != "stripe_wall":
			continue
		_SetpieceRenderer.draw_target(self, t, beat_interval, song_time, play_size())
	for t in targets:
		var tt2: String = t.get("type", "target")
		if tt2 != "laser_telegraph" and tt2 != "laser_beam":
			continue
		_SetpieceRenderer.draw_target(self, t, beat_interval, song_time, play_size())
