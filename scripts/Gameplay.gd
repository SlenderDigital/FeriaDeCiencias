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

var generator: ProceduralLevelGenerator
var track_data: Dictionary = {}
var bpm: float = 132.0
var song_time: float = 0.0
var total_song_duration: float = 60.0 # 60 seconds procedural MVP level
var beat_interval: float = 60.0 / 132.0
var beat_timer: float = 0.0

var player_pos: Vector2 = Vector2(640, 560)
var player_speed: float = 550.0
var health: float = 100.0
var score: int = 0
var combo: int = 0
var max_combo: int = 0
var is_paused: bool = false
var is_game_over: bool = false

# Targets, Hazards & Projectiles
var targets: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var spark_effects: Array[Dictionary] = []

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
	
	if track_title_lbl:
		track_title_lbl.text = "NIVEL PROCEDURAL MVP  |  BPM: %d" % int(bpm)
		track_title_lbl.add_theme_color_override("font_color", track_data.get("color", Color(0, 0.94, 1, 1)))
		
	pause_overlay.visible = false
	results_overlay.visible = false
	print("[Gameplay] Nivel Procedural MVP iniciado con Semilla: ", seed_val)

func _input(event: InputEvent) -> void:
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

func _process(delta: float) -> void:
	if is_paused or is_game_over:
		return
		
	song_time += delta
	beat_timer += delta
	
	var progress: float = clamp(song_time / total_song_duration, 0.0, 1.0)
	
	# Update song progress & phase HUD
	if progress_bar:
		progress_bar.value = progress * 100.0
		
	if track_title_lbl and generator:
		var phase_str: String = generator.get_phase_name(progress)
		track_title_lbl.text = "%s  |  %s" % [track_data.get("name", "Nivel Procedural"), phase_str]
		
	# Check level completion
	if song_time >= total_song_duration:
		_trigger_victory()
		return
		
	# Procedural Beat Spawner
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
	var move_dir: Vector2 = Vector2.ZERO
	
	# Arrow Keys & WASD input handling
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

func _spawn_procedural_wave() -> void:
	if not generator:
		return
		
	var base_col: Color = track_data.get("color", Color(0, 0.94, 1, 1))
	var new_items: Array[Dictionary] = generator.generate_beat_spawn(song_time, total_song_duration, base_col)
	for item in new_items:
		targets.append(item)

func _shoot_laser() -> void:
	# Double laser pulse
	projectiles.append({
		"pos": player_pos + Vector2(-12, -22),
		"vel": Vector2(0, -850),
		"color": Color(1.0, 0.0, 0.55, 1.0)
	})
	projectiles.append({
		"pos": player_pos + Vector2(12, -22),
		"vel": Vector2(0, -850),
		"color": Color(1.0, 0.0, 0.55, 1.0)
	})
	if SoundManager: SoundManager.play_hover()

func _update_targets(delta: float) -> void:
	var to_remove: Array[int] = []
	for i in range(targets.size()):
		var t: Dictionary = targets[i]
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
	# Draw player ship (Glowing neon ship)
	var ship_col: Color = track_data.get("color", Color(0, 0.94, 1, 1))
	var p1: Vector2 = player_pos + Vector2(0, -20)
	var p2: Vector2 = player_pos + Vector2(-18, 16)
	var p3: Vector2 = player_pos + Vector2(18, 16)
	draw_polyline(PackedVector2Array([p1, p2, p3, p1]), ship_col, 3.5)
	draw_circle(player_pos, 4.0, Color.WHITE)
	
	# Draw spark particles
	for s in spark_effects:
		var alpha: float = clamp(s["life"] / 0.3, 0.0, 1.0)
		var c: Color = s["color"]
		c.a = alpha
		draw_circle(s["pos"], 2.5, c)
		
	# Draw projectiles
	for proj in projectiles:
		draw_line(proj["pos"], proj["pos"] + Vector2(0, 18), proj["color"], 4.0)
		
	# Draw targets & hazards
	for t in targets:
		if t.get("is_hazard", false):
			# Red pulsing danger hazard
			draw_circle(t["pos"], t["radius"], Color(1.0, 0.2, 0.3, 0.35))
			draw_arc(t["pos"], t["radius"], 0, TAU, 28, Color(1.0, 0.1, 0.2, 1.0), 3.5)
		else:
			# Normal rhythm target
			draw_arc(t["pos"], t["radius"], 0, TAU, 24, t["color"], 2.5)
			draw_circle(t["pos"], t["radius"] * 0.4, Color(1, 1, 1, 0.85))
