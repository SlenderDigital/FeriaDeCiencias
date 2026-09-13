extends Node2D
## Gameplay — Rhythm Action Gameplay Scene for Abstract Pulse
## Runs the procedural MVP level, handles arrow key movement, spawns algorithmic beats/hazards, tracks score/health, and manages game loop overlays.

@onready var bg_control: Control = $BackgroundLayer/Background
@onready var track_title_lbl: Label = $HUDLayer/HUD/TopBar/TrackTitle
@onready var score_lbl: Label = $HUDLayer/HUD/TopBar/ScoreLabel
@onready var health_bar: TextureProgressBar = $HUDLayer/HUD/BottomBar/HealthBar
@onready var progress_bar: ProgressBar = $HUDLayer/HUD/BottomBar/ProgressBar
@onready var pause_overlay: Control = $HUDLayer/PauseOverlay
@onready var results_overlay: Control = $HUDLayer/ResultsOverlay
@onready var results_title_lbl: Label = $HUDLayer/ResultsOverlay/Panel/VBox/Title
@onready var results_score_lbl: Label = $HUDLayer/ResultsOverlay/Panel/VBox/ScoreDetails
@onready var music: AudioStreamPlayer = $MusicPlayer

var generator: ProceduralLevelGenerator
var chart: ChartData
var controller: PatternController
var next_beat_idx: int = 0
var track_data: Dictionary = {}
var bpm: float = 132.0
var song_time: float = 0.0
var total_song_duration: float = 60.0 # 60 seconds procedural MVP level
var beat_interval: float = 60.0 / 132.0
var beat_timer: float = 0.0

var player_pos: Vector2 = Vector2(640, 560)
var ship_rotation: float = 0.0    # grados; 0 = proa hacia +X (derecha)
var player_speed: float = 550.0
var health: float = 100.0
var score: int = 0
var combo: int = 0
var max_combo: int = 0
var is_paused: bool = false
var is_game_over: bool = false
var _music_finished: bool = false

# Targets, Hazards & Projectiles
var targets: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var spark_effects: Array[Dictionary] = []

# --- Debug menu (F6) ---
var _debug_overlay: Control = null
var _debug_visible: bool = false

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
		
	generator = ProceduralLevelGenerator.new(seed_val)
	bpm = track_data.get("bpm", 132.0)
	beat_interval = 60.0 / bpm
	
	# Real music + chart-driven path (when track_data carries chart files)
	if track_data.has("audio") and track_data.has("analysis") and track_data.has("level"):
		chart = ChartData.load_charts(track_data["analysis"], track_data["level"])
		if not chart.beat_times.is_empty():
			controller = PatternController.new(chart)
			music.stream = load(track_data["audio"]) as AudioStream
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
	print("[Gameplay] Nivel iniciado: ", track_data.get("name", "Procedural MVP"), " (bpm=", bpm, ", chart=", chart != null, ")")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F6:
		_toggle_debug_menu()
		return
	if event.is_action_pressed("ui_cancel"): # ESC key
		toggle_pause()
	elif not is_paused and not is_game_over:
		# Shoot on Space, Enter, or Mouse Click
		if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
			_shoot_laser()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_shoot_laser()

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
			var spawns: Array[Dictionary] = controller.spawns_at(t, track_color)
			for s in spawns:
				targets.append(s)
			
			# Downbeat patterns (every 4 beats) - big patterns
			if chart.downbeat[next_beat_idx]:
				var downbeat_spawns: Array[Dictionary] = controller.spawns_at_downbeat(t, next_beat_idx, track_color)
				for s in controller.spawns_at_downbeat(t, next_beat_idx, track_color):
					targets.append(s)
			
			# Bar patterns (every 4 beats = every downbeat) - variations
			if next_beat_idx % 4 == 0:
				for s in controller.spawns_at_bar(t, next_beat_idx, track_color):
					targets.append(s)
			
			# Phrase patterns (every 16 beats) - setpieces / new mechanics
			if next_beat_idx % 16 == 0:
				for s in controller.spawns_at_phrase(t, next_beat_idx, track_color):
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
	_update_projectiles(delta)
	_update_sparks(delta)
	
	queue_redraw()

func _update_player_movement(delta: float) -> void:
	# Con mano: posicion absoluta de la palma + rotacion pulgar->indice (port de Player.cpp)
	if HandTrackingClient and HandTrackingClient.has_hand:
		var target: Vector2 = HandTrackingClient.get_palm_center() * Vector2(1280, 720)
		var alpha: float = 1.0 - exp(-25.0 * delta)
		player_pos = player_pos.lerp(target, alpha)
		var ang := HandTrackingClient.get_hand_angle_deg()
		if ang < 9990.0:
			_smooth_rotation_toward(ang, delta)
		player_pos.x = clamp(player_pos.x, 50, 1230)
		player_pos.y = clamp(player_pos.y, 80, 670)
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
	player_pos.x = clamp(player_pos.x, 50, 1230)
	player_pos.y = clamp(player_pos.y, 80, 670)

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

func _shoot_laser() -> void:
	# Doble pulso de laser en la direccion en que apunta la nave
	var dir: Vector2 = Vector2.from_angle(deg_to_rad(ship_rotation))
	var perp := Vector2(-dir.y, dir.x)
	projectiles.append({
		"pos": player_pos + dir * 22.0 + perp * 12.0,
		"vel": dir * 850.0,
		"color": Color(1.0, 0.0, 0.55, 1.0)
	})
	projectiles.append({
		"pos": player_pos + dir * 22.0 - perp * 12.0,
		"vel": dir * 850.0,
		"color": Color(1.0, 0.0, 0.55, 1.0)
	})
	if SoundManager: SoundManager.play_hover()

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
				# Fire the laser - create a vertical laser beam
				t["fired"] = true
				t["type"] = "laser_beam"
				t["vel"] = Vector2(0, 0)  # Laser beam is instant, drawn as line
				t["radius"] = 12
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
			if t["pos"].distance_to(Vector2(640, 360)) < 50:
				to_remove.append(i)
				continue
		else:
			# Standard movement
			t["pos"] += t["vel"] * delta
		
		# Check collision with player ship
		if player_pos.distance_to(t["pos"]) < (t["radius"] + 16.0):
			to_remove.append(i)
			if t.get("is_hazard", false):
				_on_hazard_hit()
			else:
				_on_target_hit(t["pos"], t.get("points", 100))
			continue
			
		# Target reaches screen bottom
		if t["pos"].y > 740:
			to_remove.append(i)
			if not t.get("is_hazard", false):
				_on_target_missed()
				
	to_remove.reverse()
	for idx in to_remove:
		if idx < targets.size():
			targets.remove_at(idx)

func _update_projectiles(delta: float) -> void:
	var rem_proj: Array[int] = []
	var rem_targ: Array[int] = []
	
	for p_i in range(projectiles.size()):
		var proj: Dictionary = projectiles[p_i]
		proj["pos"] += proj["vel"] * delta
		
		if proj["pos"].y < -30:
			rem_proj.append(p_i)
			continue
			
		# Collision check with targets & hazards
		for t_i in range(targets.size()):
			if rem_targ.has(t_i):
				continue
			var target: Dictionary = targets[t_i]
			if proj["pos"].distance_to(target["pos"]) < (target["radius"] + 12.0):
				rem_proj.append(p_i)
				rem_targ.append(t_i)
				_on_target_hit(target["pos"], target.get("points", 150))
				_add_sparks(target["pos"], target["color"])
				break
				
	rem_proj.reverse()
	for p_idx in rem_proj:
		if p_idx < projectiles.size():
			projectiles.remove_at(p_idx)
		
	rem_targ.reverse()
	for t_idx in rem_targ:
		if t_idx < targets.size():
			targets.remove_at(t_idx)

func _on_target_hit(pos: Vector2, pts: int) -> void:
	combo += 1
	if combo > max_combo:
		max_combo = combo
	score += pts + combo * 15
	_update_hud_score()
	if SoundManager: SoundManager.play_click()

func _on_hazard_hit() -> void:
	combo = 0
	health -= 18.0
	_update_hud_score()
	if health_bar: health_bar.value = health
	if SoundManager: SoundManager.play_back()
	
	if health <= 0:
		_trigger_game_over()

func _on_target_missed() -> void:
	combo = 0
	health -= 6.0
	_update_hud_score()
	if health_bar: health_bar.value = health
	
	if health <= 0:
		_trigger_game_over()

func _update_hud_score() -> void:
	if score_lbl:
		score_lbl.text = "PUNTAJE: %d  |  COMBO: x%d" % [score, combo]

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
		is_new_hs = GameManager.save_score(track_data.get("id", "procedural_mvp"), score)
		
	results_title_lbl.text = "¡NIVEL PROCEDURAL COMPLETADO!"
	results_title_lbl.add_theme_color_override("font_color", Color(0, 1, 0.5, 1))
	results_score_lbl.text = "Puntaje Final: %d\nCombo Máximo: x%d\n%s" % [score, max_combo, ("¡NUEVO RÉCORD PROCEDURAL!" if is_new_hs else "")]
	results_overlay.visible = true

func _trigger_game_over() -> void:
	is_game_over = true
	results_title_lbl.text = "MISIÓN FALLIDA"
	results_title_lbl.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 1))
	results_score_lbl.text = "Puntaje Logrado: %d\nCombo Máximo: x%d" % [score, max_combo]
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
	# Draw player ship (neon, rotada por la mano; 0deg = derecha)
	var ship_col: Color = track_data.get("color", Color(0, 0.94, 1, 1))
	var rad: float = deg_to_rad(ship_rotation)
	var fwd := Vector2.from_angle(rad)          # linea de proa
	var perp := Vector2(-fwd.y, fwd.x)          # perpendicular
	var nose: Vector2 = player_pos + fwd * 20.0
	var p2: Vector2 = player_pos + (-fwd * 9.0 + perp * 15.0)
	var p3: Vector2 = player_pos + (-fwd * 9.0 - perp * 15.0)
	draw_polyline(PackedVector2Array([nose, p2, p3, nose]), ship_col, 3.5)
	draw_line(player_pos, player_pos + fwd * 24.0, Color(1, 1, 1, 0.25), 1.5)
	draw_circle(player_pos, 4.0, Color.WHITE)
	
	# Draw spark particles
	for s in spark_effects:
		var alpha: float = clamp(s["life"] / 0.3, 0.0, 1.0)
		var c: Color = s["color"]
		c.a = alpha
		draw_circle(s["pos"], 2.5, c)
		
	# Draw projectiles
	for proj in projectiles:
		var pdir := (proj["vel"] as Vector2).normalized()
		draw_line(proj["pos"], proj["pos"] + pdir * 18.0, proj["color"], 4.0)
		
	# Draw targets & hazards
	for t in targets:
		if t.get("is_hazard", false):
			match t.get("type", "hazard"):
				"stripe_wall":
					# Draw diagonal stripe wall
					draw_rect(t["pos"], Vector2(1280, t["radius"] * 2), Color(1.0, 0.2, 0.3, 0.4))
					# Diagonal stripes
					for i in range(12):
						var x = t["pos"].x + (i * 120 - 240)
						draw_line(Vector2(x, t["pos"].y), Vector2(x + 200, t["pos"].y + t["radius"] * 2), Color(0, 0, 0, 0.6), 3)
				"saw":
					# Draw rotating saw
					draw_polygon(PackedVector2Array([t["pos"], t["pos"] + Vector2(-t["radius"], -t["radius"]), t["pos"] + Vector2(t["radius"], -t["radius"]), t["pos"] + Vector2(t["radius"], t["radius"]), t["pos"] + Vector2(-t["radius"], t["radius"]), t["pos"] + Vector2(-t["radius"], -t["radius"])]), t["color"], true)
				"drifter":
					# Spiked ring
					draw_circle(t["pos"], t["radius"], t["color"])
					for i in range(8):
						var ang = TAU * i / 8.0
						var spike = Vector2(cos(ang), sin(ang)) * t["radius"] * 1.3
						draw_line(t["pos"], t["pos"] + spike, t["color"], 3)
				"laser_telegraph":
					# Telegraph line
					var h = t.get("telegraph_time", 1.0)
					var alpha = 0.3 + 0.7 * (1.0 - h)
					draw_line(Vector2(t["pos"].x, 0), Vector2(t["pos"].x, 720), Color(1, 0.8, 0, alpha), 4)
				"homing":
					draw_circle(t["pos"], t["radius"], t["color"])
					# Direction indicator
					var dir = t["vel"].normalized()
					draw_line(t["pos"], t["pos"] + dir * t["radius"] * 1.5, Color(1, 1, 1, 0.8), 2)
				"perimeter":
					draw_circle(t["pos"], t["radius"], t["color"])
					for i in range(6):
						var ang = TAU * i / 6.0
						var spike = Vector2(cos(ang), sin(ang)) * t["radius"] * 1.2
						draw_line(t["pos"], t["pos"] + spike, t["color"], 2)
				_:
					# Default hazard
					draw_circle(t["pos"], t["radius"], Color(1.0, 0.2, 0.3, 0.35))
					draw_arc(t["pos"], t["radius"], 0, TAU, 28, Color(1.0, 0.1, 0.2, 1.0), 3.5)
			else:
				# Normal rhythm target
				draw_arc(t["pos"], t["radius"], 0, TAU, 24, t["color"], 2.5)
				draw_circle(t["pos"], t["radius"] * 0.4, Color(1, 1, 1, 0.85))
