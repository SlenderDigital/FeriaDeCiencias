extends Node2D
## Gameplay — Rhythm Action Gameplay Scene for Abstract Pulse
## Runs the selected track, controls player ship, spawns rhythm beat targets, handles score/health, and pause overlay.

@onready var track_title_lbl: Label = $CanvasLayer/HUD/TopRail/TrackTitle
@onready var score_lbl: Label = $CanvasLayer/HUD/TopRail/ScoreLabel
@onready var health_bar: ProgressBar = $CanvasLayer/HUD/BottomRail/HealthBar
@onready var progress_bar: ProgressBar = $CanvasLayer/HUD/BottomRail/ProgressBar
@onready var pause_overlay: Control = $CanvasLayer/PauseOverlay
@onready var results_overlay: Control = $CanvasLayer/ResultsOverlay
@onready var results_title_lbl: Label = $CanvasLayer/ResultsOverlay/Panel/VBox/Title
@onready var results_score_lbl: Label = $CanvasLayer/ResultsOverlay/Panel/VBox/ScoreDetails

var track_data: Dictionary = {}
var bpm: float = 128.0
var song_time: float = 0.0
var total_song_duration: float = 60.0 # 60 seconds level prototype
var beat_interval: float = 60.0 / 128.0
var beat_timer: float = 0.0

var player_pos: Vector2 = Vector2(640, 550)
var player_speed: float = 450.0
var health: float = 100.0
var score: int = 0
var combo: int = 0
var is_paused: bool = false
var is_game_over: bool = false

# Targets & Projectiles
var targets: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []

func _ready() -> void:
	if GameManager:
		track_data = GameManager.get_current_track()
	else:
		track_data = {
			"name": "Cyber Genesis",
			"bpm": 128,
			"color": Color(0, 0.94, 1, 1),
			"id": "track_1"
		}
		
	bpm = track_data.get("bpm", 128.0)
	beat_interval = 60.0 / bpm
	
	if track_title_lbl:
		track_title_lbl.text = "CANCIÓN: %s  |  BPM: %d" % [track_data.get("name", "Track"), int(bpm)]
		track_title_lbl.add_theme_color_override("font_color", track_data.get("color", Color(0, 0.94, 1, 1)))
		
	pause_overlay.visible = false
	results_overlay.visible = false
	print("[Gameplay] Nivel iniciado: ", track_data.get("name"))

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"): # ESC key
		toggle_pause()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not is_paused and not is_game_over:
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
	
	# Update song progress HUD
	if progress_bar:
		progress_bar.value = (song_time / total_song_duration) * 100.0
		
	# Check level completion
	if song_time >= total_song_duration:
		_trigger_victory()
		return
		
	# Beat Spawner
	if beat_timer >= beat_interval:
		beat_timer -= beat_interval
		_spawn_rhythm_target()
		
	_update_player_movement(delta)
	_update_targets(delta)
	_update_projectiles(delta)
	
	queue_redraw()

func _update_player_movement(delta: float) -> void:
	var move_dir: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move_dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move_dir.y += 1
		
	# Follow mouse position if mouse is active
	var target_pos: Vector2 = get_global_mouse_position()
	if move_dir != Vector2.ZERO:
		player_pos += move_dir.normalized() * player_speed * delta
	else:
		player_pos = player_pos.lerp(target_pos, delta * 8.0)
		
	# Clamp player inside screen view
	player_pos.x = clamp(player_pos.x, 40, 1240)
	player_pos.y = clamp(player_pos.y, 100, 680)

func _spawn_rhythm_target() -> void:
	var spawn_x: float = randf_range(100, 1180)
	targets.append({
		"pos": Vector2(spawn_x, -30),
		"vel": Vector2(randf_range(-20, 20), randf_range(160, 260)),
		"radius": randf_range(16, 24),
		"color": track_data.get("color", Color(0, 0.94, 1, 1))
	})

func _shoot_laser() -> void:
	projectiles.append({
		"pos": player_pos + Vector2(0, -20),
		"vel": Vector2(0, -700),
		"color": Color(1.0, 0.0, 0.55, 1.0)
	})
	if SoundManager: SoundManager.play_hover()

func _update_targets(delta: float) -> void:
	var to_remove: Array[int] = []
	for i in range(targets.size()):
		var t: Dictionary = targets[i]
		t["pos"] += t["vel"] * delta
		
		# Miss target -> player loses health
		if t["pos"].y > 740:
			to_remove.append(i)
			_on_target_missed()
			
	to_remove.reverse()
	for idx in to_remove:
		targets.remove_at(idx)

func _update_projectiles(delta: float) -> void:
	var rem_proj: Array[int] = []
	var rem_targ: Array[int] = []
	
	for p_i in range(projectiles.size()):
		var proj: Dictionary = projectiles[p_i]
		proj["pos"] += proj["vel"] * delta
		
		if proj["pos"].y < -20:
			rem_proj.append(p_i)
			continue
			
		# Collision check with rhythm targets
		for t_i in range(targets.size()):
			if rem_targ.has(t_i):
				continue
			var target: Dictionary = targets[t_i]
			if proj["pos"].distance_to(target["pos"]) < (target["radius"] + 10):
				rem_proj.append(p_i)
				rem_targ.append(t_i)
				_on_target_hit(target["pos"])
				break
				
	rem_proj.reverse()
	for p_idx in rem_proj:
		projectiles.remove_at(p_idx)
		
	rem_targ.reverse()
	for t_idx in rem_targ:
		targets.remove_at(t_idx)

func _on_target_hit(pos: Vector2) -> void:
	combo += 1
	score += 150 + combo * 10
	if score_lbl: score_lbl.text = "PUNTAJE: %d  |  COMBO: x%d" % [score, combo]
	if SoundManager: SoundManager.play_click()

func _on_target_missed() -> void:
	combo = 0
	health -= 8.0
	if score_lbl: score_lbl.text = "PUNTAJE: %d  |  COMBO: x%d" % [score, combo]
	if health_bar: health_bar.value = health
	
	if health <= 0:
		_trigger_game_over()

func _trigger_victory() -> void:
	is_game_over = true
	var is_new_hs: bool = false
	if GameManager:
		is_new_hs = GameManager.save_score(track_data.get("id", "track_1"), score)
		
	results_title_lbl.text = "¡CANCIÓN COMPLETADA!"
	results_title_lbl.add_theme_color_override("font_color", Color(0, 1, 0.5, 1))
	results_score_lbl.text = "Puntaje Final: %d\nCombo Máximo: x%d\n%s" % [score, combo, ("¡NUEVO RÉCORD!" if is_new_hs else "")]
	results_overlay.visible = true

func _trigger_game_over() -> void:
	is_game_over = true
	results_title_lbl.text = "MISIÓN FALLIDA"
	results_title_lbl.add_theme_color_override("font_color", Color(1, 0.2, 0.2, 1))
	results_score_lbl.text = "Puntaje Logrado: %d" % score
	results_overlay.visible = true

# --- Pause & Results Overlay Button Signals ---

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
	# Draw player ship (Glowing neon triangle/ship)
	var ship_col: Color = track_data.get("color", Color(0, 0.94, 1, 1))
	var p1: Vector2 = player_pos + Vector2(0, -18)
	var p2: Vector2 = player_pos + Vector2(-16, 14)
	var p3: Vector2 = player_pos + Vector2(16, 14)
	draw_polyline(PackedVector2Array([p1, p2, p3, p1]), ship_col, 3.0)
	draw_circle(player_pos, 4.0, Color.WHITE)
	
	# Draw projectiles
	for proj in projectiles:
		draw_line(proj["pos"], proj["pos"] + Vector2(0, 15), proj["color"], 3.5)
		
	# Draw rhythm targets
	for t in targets:
		draw_arc(t["pos"], t["radius"], 0, TAU, 24, t["color"], 2.5)
		draw_circle(t["pos"], t["radius"] * 0.4, Color(1, 1, 1, 0.8))
