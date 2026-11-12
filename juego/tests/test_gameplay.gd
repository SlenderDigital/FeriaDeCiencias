extends McpTestSuite

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const CREDITS_SCENE: PackedScene = preload("res://scenes/credits.tscn")
const LEVEL_SCENE: PackedScene = preload("res://scenes/level.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const LIGHT_BEAM_SCENE: PackedScene = preload("res://scenes/light_beam.tscn")
const FILLING_CIRCLE_SCENE: PackedScene = preload("res://scenes/filling_circle.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")
const EXPLODER_SCENE: PackedScene = preload("res://scenes/exploder.tscn")
const SAW_SCENE: PackedScene = preload("res://scenes/saw.tscn")
const CLOSING_WALL_SCENE: PackedScene = preload("res://scenes/closing_wall.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")
const HAND_TRACKING_CLIENT_SCRIPT: GDScript = preload("res://scripts/hand_tracking_client.gd")


func suite_name() -> String:
	return "gameplay"


func _tree_root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _spawn(scene: PackedScene) -> Node:
	var inst: Node = track(scene.instantiate()) as Node
	_tree_root().add_child(inst)
	return inst


func _add_node(node: Node) -> Node:
	track(node)
	_tree_root().add_child(node)
	return node


func setup() -> void:
	_tree_root().size = Vector2i(1152, 648)
	GameManager.selected_difficulty = GameManager.Difficulty.NORMAL
	HandTrackingClient.reset_state()


func test_ac1_and_ac2_main_menu_structure_and_actions() -> void:
	var main_scene_setting: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	assert_eq(main_scene_setting, "res://scenes/main_menu.tscn", "Main scene should be main_menu.tscn")

	var menu: Control = _spawn(MAIN_MENU_SCENE) as Control

	var title_label: Label = menu.get_node_or_null("CenterContainer/MenuBox/TitleLabel") as Label
	var difficulty_button: Button = menu.get_node_or_null("CenterContainer/MenuBox/DifficultyButton") as Button
	var play_button: Button = menu.get_node_or_null("CenterContainer/MenuBox/PlayButton") as Button
	var quit_button: Button = menu.get_node_or_null("CenterContainer/MenuBox/QuitButton") as Button

	assert_true(title_label != null, "TitleLabel must exist")
	assert_gt(title_label.text.length(), 0, "TitleLabel must display game title")
	assert_true(difficulty_button != null, "DifficultyButton must exist")
	assert_eq(difficulty_button.text, "Difficulty: Normal", "DifficultyButton should default to Normal")
	assert_true(play_button != null, "PlayButton must exist")
	assert_eq(play_button.text, "Play", "PlayButton text must be 'Play'")
	assert_true(quit_button != null, "QuitButton must exist")
	assert_eq(quit_button.text, "Quit", "QuitButton text must be 'Quit'")
	assert_true(difficulty_button.pressed.is_connected(menu._on_difficulty_pressed), "DifficultyButton must connect to _on_difficulty_pressed")
	assert_true(play_button.pressed.is_connected(menu._on_play_pressed), "PlayButton must connect to _on_play_pressed")
	assert_true(quit_button.pressed.is_connected(menu._on_quit_pressed), "QuitButton must connect to _on_quit_pressed")

	menu._on_difficulty_pressed()
	assert_eq(menu.selected_difficulty, 2, "First press should select Hard (2)")
	assert_eq(difficulty_button.text, "Difficulty: Hard", "DifficultyButton should display Hard")

	menu._on_difficulty_pressed()
	assert_eq(menu.selected_difficulty, 0, "Second press should select Easy (0)")
	assert_eq(difficulty_button.text, "Difficulty: Easy", "DifficultyButton should display Easy")

	menu._on_difficulty_pressed()
	assert_eq(menu.selected_difficulty, 1, "Third press should select Normal (1)")
	assert_eq(difficulty_button.text, "Difficulty: Normal", "DifficultyButton should display Normal")


func test_ac3_and_ac4_player_movement_and_target_following() -> void:
	var player: CharacterBody2D = _spawn(PLAYER_SCENE) as CharacterBody2D
	player.global_position = Vector2(576.0, 324.0)

	for action: String in ["move_left", "move_right", "move_up", "move_down", "shield"]:
		assert_true(InputMap.has_action(action), "InputMap must have action: " + action)

	var target: Vector2 = Vector2(700.0, 250.0)
	player.set_target_position(target, true)
	assert_true(player.use_target_position, "use_target_position should be enabled")
	assert_true(player.external_tracking_active, "external_tracking_active should be enabled")

	for _i: int in range(20):
		player._physics_process(0.016)

	var dist: float = player.global_position.distance_to(target)
	assert_true(dist < 5.0, "Player should reach target position (dist=%f)" % dist)

	player.set_target_position(Vector2(-500.0, 9999.0), true)
	for _i: int in range(30):
		player._physics_process(0.05)
	assert_true(player.global_position.x >= 14.0, "Player X must be clamped within left screen bound")
	assert_true(player.global_position.y <= 648.0 - 14.0, "Player Y must be clamped within bottom screen bound")


func test_ac5_player_shield_energy_and_blocking() -> void:
	var player: CharacterBody2D = _spawn(PLAYER_SCENE) as CharacterBody2D
	player.global_position = Vector2(300.0, 300.0)

	assert_false(player.is_shielding, "Player must start with the shield down")
	assert_eq(player.get_shield_energy_ratio(), 1.0, "Shield must start fully charged")

	player.set_shield_held(true)
	player._physics_process(0.016)
	assert_true(player.is_shielding, "Holding the shield input must raise the shield")
	assert_true(player.is_invincible(), "Shield must grant damage immunity while active")

	var energy_before: float = player.shield_energy
	var blocked_count: Array[int] = [0]
	var broken_count: Array[int] = [0]
	player.shield_blocked.connect(func() -> void: blocked_count[0] += 1)
	player.shield_broken.connect(func() -> void: broken_count[0] += 1)

	player.take_damage(1)
	assert_eq(player.current_hp, 3, "Shield must block all incoming damage")
	assert_eq(blocked_count[0], 1, "Shield block must emit shield_blocked signal")

	player._physics_process(0.5)
	assert_true(player.shield_energy < energy_before, "Holding the shield must drain energy")

	for _i: int in range(40):
		player._physics_process(0.05)
	assert_false(player.is_shielding, "Empty shield must drop automatically")
	assert_true(player.shield_exhausted, "Shield must enter the exhausted state")
	assert_eq(player.shield_energy, 0.0, "Exhausted shield must report zero energy")
	assert_eq(broken_count[0], 1, "Shield depletion must emit shield_broken signal")

	player.set_shield_held(false)
	player._physics_process(0.5)
	player.take_damage(1)
	assert_eq(player.current_hp, 2, "Unshielded damage must reduce HP after the break grace")

	for _i: int in range(40):
		player._physics_process(0.05)
	assert_true(player.get_shield_energy_ratio() > 0.95, "Released shield must recharge")
	player.set_shield_held(true)
	player._physics_process(0.016)
	assert_true(player.is_shielding, "Recharged shield must be usable again")


func test_ac6_and_ac7_light_beam_phases_and_collision() -> void:
	var beam: Area2D = _spawn(LIGHT_BEAM_SCENE) as Area2D
	beam.configure(Vector2(576.0, 324.0), 0.4, 44.0, 1.0, 0.35)

	var col: CollisionShape2D = beam.get_node("CollisionShape2D") as CollisionShape2D
	var vis: Polygon2D = beam.get_node("BeamVisual") as Polygon2D

	assert_eq(beam.current_phase, 0, "Beam should start in TELEGRAPH phase")
	assert_false(beam.is_hazard_active, "Telegraph phase must have no active hazard")
	assert_true(col.disabled, "CollisionShape2D must be disabled during telegraph")
	assert_true(vis.color.r < 0.8, "Telegraph visual must be dim gray")

	beam._physics_process(0.5)
	assert_eq(beam.current_phase, 0, "Beam should still be in TELEGRAPH at 0.5s")
	assert_false(beam.is_hazard_active, "Still no hazard at 0.5s")

	beam._physics_process(0.55)
	assert_eq(beam.current_phase, 1, "Beam should transition to ACTIVE phase after 1.0s")
	assert_true(beam.is_hazard_active, "ACTIVE phase must enable hazard")
	assert_false(col.disabled, "CollisionShape2D must be enabled during ACTIVE phase")
	assert_eq(vis.color, Color.WHITE, "ACTIVE beam visual must be solid white")

	beam._physics_process(0.4)
	assert_eq(beam.current_phase, 2, "Beam should transition to FADE_OUT phase")
	assert_false(beam.is_hazard_active, "FADE_OUT phase must disable hazard")
	assert_true(col.disabled, "CollisionShape2D must be disabled during FADE_OUT")


func test_ac8_and_ac9_hp_damage_iframes_and_game_over() -> void:
	var level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	var game_over_panel: Control = level.get_node("HUD/HUDRoot/GameOverPanel") as Control
	var retry_btn: Button = level.get_node("HUD/HUDRoot/GameOverPanel/VBoxContainer/RetryButton") as Button
	var menu_btn: Button = level.get_node("HUD/HUDRoot/GameOverPanel/VBoxContainer/GameOverMainMenuButton") as Button

	assert_eq(player.current_hp, 3, "Player must start with 3 HP")
	assert_false(game_over_panel.visible, "GameOverPanel must be hidden initially")
	assert_eq(retry_btn.text, "Retry", "Retry button text must be 'Retry'")
	assert_eq(menu_btn.text, "Main Menu", "Main Menu button text must be 'Main Menu'")

	player.take_damage(1)
	assert_eq(player.current_hp, 2, "HP should drop to 2")
	assert_true(player.is_invincible(), "Player must gain post-hit invincibility frames")

	player.take_damage(1)
	assert_eq(player.current_hp, 2, "Post-hit i-frames must block immediate damage")

	player._physics_process(1.3)
	assert_false(player.is_invincible(), "Post-hit i-frames should expire after 1.2s")
	player.take_damage(1)
	assert_eq(player.current_hp, 1, "HP should drop to 1")

	player._physics_process(1.3)
	player.take_damage(1)
	assert_eq(player.current_hp, 0, "HP should reach 0")
	assert_false(level.is_level_running, "Level must stop at 0 HP")
	assert_true(game_over_panel.visible, "GameOverPanel must be displayed at 0 HP")

	level._on_retry_pressed()
	assert_true(level.is_level_running, "Retry must restart level")
	assert_eq(player.current_hp, 3, "Retry must restore 3 HP")
	assert_false(game_over_panel.visible, "Retry must hide GameOverPanel")


func test_ac10_level_survival_45_seconds_and_replay() -> void:
	var level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	var complete_panel: Control = level.get_node("HUD/HUDRoot/LevelCompletePanel") as Control
	var replay_btn: Button = level.get_node("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/ReplayButton") as Button
	var menu_btn: Button = level.get_node("HUD/HUDRoot/LevelCompletePanel/VBoxContainer/CompleteMainMenuButton") as Button
	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D

	assert_eq(level.level_duration, 45.0, "Level duration must be 45 seconds")
	assert_false(complete_panel.visible, "LevelCompletePanel must be hidden initially")
	assert_eq(replay_btn.text, "Replay", "Replay button text must be 'Replay'")
	assert_eq(menu_btn.text, "Main Menu", "Main Menu button text must be 'Main Menu'")

	level.simulate_physics(0.6)
	assert_gt(beam_container.get_child_count(), 0, "Level must spawn obstacles")

	for _i: int in range(90):
		level.simulate_physics(0.5)

	assert_false(level.is_level_running, "Level must stop after surviving 45 seconds")
	assert_true(complete_panel.visible, "LevelCompletePanel must be displayed after 45 seconds")

	level._on_retry_pressed()
	assert_true(level.is_level_running, "Replay must restart level")
	assert_eq(level.elapsed_time, 0.0, "Replay must reset elapsed_time to 0")
	assert_false(complete_panel.visible, "Replay must hide LevelCompletePanel")


func test_ac11_monochrome_primitives_only() -> void:
	var scenes: Array[PackedScene] = [
		MAIN_MENU_SCENE,
		CREDITS_SCENE,
		LEVEL_SCENE,
		PLAYER_SCENE,
		LIGHT_BEAM_SCENE,
		FILLING_CIRCLE_SCENE,
		PROJECTILE_SCENE,
		EXPLODER_SCENE,
		SAW_SCENE,
		CLOSING_WALL_SCENE,
		ENEMY_SCENE,
	]
	for packed: PackedScene in scenes:
		var root: Node = _spawn(packed)
		_assert_subtree_monochrome_and_primitive(root)


func test_difficulty_modes_scaling_and_persistence() -> void:
	GameManager.selected_difficulty = GameManager.Difficulty.NORMAL
	var standalone_level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	assert_eq(standalone_level.difficulty_mode, 1, "Standalone level must default to Normal (1)")

	var menu: Control = _spawn(MAIN_MENU_SCENE) as Control
	menu.set_difficulty(2)

	var hard_level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	assert_eq(hard_level.difficulty_mode, 2, "Level should initialize with Hard difficulty selected on MainMenu")

	hard_level._on_retry_pressed()
	assert_eq(hard_level.difficulty_mode, 2, "Retry must preserve Hard difficulty")

	var counts_by_mode: Dictionary = {}
	for mode: int in [0, 1, 2]:
		var lvl: Node2D = _spawn(LEVEL_SCENE) as Node2D
		lvl.set_difficulty(mode)
		lvl.restart_level()

		var p: CharacterBody2D = lvl.get_node("Player") as CharacterBody2D
		assert_eq(p.current_hp, 3, "Player HP must be 3 in difficulty mode %d" % mode)
		assert_eq(lvl.level_duration, 45.0, "Level duration must be 45s in difficulty mode %d" % mode)

		for _step: int in range(60):
			lvl.simulate_physics(0.2)
		counts_by_mode[mode] = lvl.wave_index

	assert_gt(int(counts_by_mode[1]), int(counts_by_mode[0]), "Normal must spawn more waves than Easy")
	assert_gt(int(counts_by_mode[2]), int(counts_by_mode[1]), "Hard must spawn more waves than Normal")


func test_filling_circle_patterns_and_phases() -> void:
	for fill_mode: int in [0, 1, 2]:
		var circle: Area2D = _spawn(FILLING_CIRCLE_SCENE) as Area2D
		circle.configure(Vector2(400.0, 300.0), 80.0, fill_mode, 1.0, 0.35)

		var col: CollisionShape2D = circle.get_node("CollisionShape2D") as CollisionShape2D
		var shadow_vis: Polygon2D = circle.get_node("ShadowVisual") as Polygon2D
		var fill_vis: Polygon2D = circle.get_node("FillVisual") as Polygon2D

		assert_eq(int(circle.fill_mode), fill_mode, "Circle fill mode must match configured pattern")
		assert_eq(circle.current_phase, 0, "Circle must start in TELEGRAPH phase")
		assert_false(circle.is_hazard_active, "Circle must not deal damage while filling")
		assert_true(col.disabled, "Circle collision must be disabled while filling")
		assert_true(col.shape is CircleShape2D, "Circle collision shape must be CircleShape2D")
		assert_eq((col.shape as CircleShape2D).radius, 80.0, "Circle collision radius must match full radius")
		assert_gt(shadow_vis.polygon.size(), 8, "Shadow visual must be a circular polygon")

		circle._physics_process(0.5)
		assert_eq(circle.current_phase, 0, "Circle must still be filling at 0.5s")
		assert_false(circle.is_hazard_active, "Circle collision must remain inactive at 50% fill")
		assert_true(col.disabled, "CollisionShape2D must remain disabled at 50% fill")
		assert_true(fill_vis.visible, "Fill progress visual must be visible while filling")
		assert_gt(fill_vis.polygon.size(), 2, "Fill polygon must have vertices for mode %d" % fill_mode)

		circle._physics_process(0.55)
		assert_eq(circle.current_phase, 1, "Circle must enter ACTIVE phase at 100% fill")
		assert_true(circle.is_hazard_active, "Circle must activate hazard at 100% fill")
		assert_false(col.disabled, "Circle collision must be enabled at 100% fill")
		assert_eq(shadow_vis.color, Color.WHITE, "Active circle burst must be solid white")

		circle._physics_process(0.4)
		assert_eq(circle.current_phase, 2, "Circle must enter FADE_OUT after ~0.35s active burst")
		assert_false(circle.is_hazard_active, "Circle hazard must deactivate during FADE_OUT")
		assert_true(col.disabled, "Circle collision must disable during FADE_OUT")


func test_edge_projectiles_and_offscreen_despawn() -> void:
	var level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	var arena: Vector2 = Vector2(1152.0, 648.0)

	for edge: int in range(4):
		var proj: Area2D = level.spawn_edge_projectile(edge, 400.0, 10.0)
		var col: CollisionShape2D = proj.get_node("CollisionShape2D") as CollisionShape2D
		var vis: Polygon2D = proj.get_node("BodyVisual") as Polygon2D

		assert_true(proj.is_hazard_active, "Un-telegraphed projectile must have immediate active hazard")
		assert_false(col.disabled, "Un-telegraphed projectile must have immediate active collision")
		assert_eq(vis.color, Color.WHITE, "Un-telegraphed projectile body must be solid white")

		match edge:
			0:
				assert_eq(proj.global_position.y, 0.0, "Edge 0 projectile must spawn on top edge")
			1:
				assert_eq(proj.global_position.x, arena.x, "Edge 1 projectile must spawn on right edge")
			2:
				assert_eq(proj.global_position.y, arena.y, "Edge 2 projectile must spawn on bottom edge")
			3:
				assert_eq(proj.global_position.x, 0.0, "Edge 3 projectile must spawn on left edge")

	var fast_proj: Area2D = level.spawn_projectile(Vector2(1140.0, 324.0), Vector2.RIGHT, 500.0, 10.0)
	var start_pos: Vector2 = fast_proj.global_position
	fast_proj._physics_process(0.05)
	assert_gt(fast_proj.global_position.x, start_pos.x, "Projectile must move in straight line along direction")

	fast_proj._physics_process(0.5)
	assert_true(fast_proj.is_queued_for_deletion(), "Projectile must queue_free after exiting viewport bounds")


func test_exploding_object_telegraph_and_radial_burst() -> void:
	var level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D
	var spawn_pos: Vector2 = Vector2(576.0, 324.0)
	var exploder: Area2D = level.spawn_exploder(spawn_pos, 1.0, 8, 380.0)
	var col: CollisionShape2D = exploder.get_node("CollisionShape2D") as CollisionShape2D

	assert_false(exploder.is_hazard_active, "Exploder must be non-damaging during telegraph")
	assert_true(col.disabled, "Exploder collision must be disabled during telegraph")

	exploder._physics_process(0.5)
	assert_eq(exploder.global_position, spawn_pos, "Exploder must remain stationary during telegraph")
	assert_false(exploder.has_detonated, "Exploder must not detonate before 1.0s")

	var before_count: int = beam_container.get_child_count()
	exploder._physics_process(0.55)
	assert_true(exploder.has_detonated, "Exploder must detonate at 1.0s")
	assert_eq(beam_container.get_child_count(), before_count + 8, "Exploder must spawn 8 radial projectiles in BeamContainer")


func test_audio_and_sound_manager_playback() -> void:
	var music_stream: AudioStreamWAV = SoundManager.MUSIC_STREAM
	assert_true(music_stream != null, "Music stream must exist")
	assert_eq(music_stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "Music stream must loop forward")
	var total_samples: int = music_stream.data.size() / 2
	var duration_sec: float = float(total_samples) / float(SoundManager.MIX_RATE)
	assert_true(absf(duration_sec - 45.0) < 0.05, "Music composition must span the full 45-second level arc (24 bars at 128 BPM)")

	for sfx_key: StringName in [
		&"menu", &"hit", &"laser", &"explosion",
		&"shield_on", &"shield_block", &"shield_break",
		&"enemy_fire", &"enemy_lunge", &"wall_slam",
		&"saw_bounce", &"victory", &"game_over"
	]:
		var stream: AudioStreamWAV = SoundManager.SFX_STREAMS.get(sfx_key) as AudioStreamWAV
		assert_true(stream != null, "SFX stream must exist: " + String(sfx_key))
		assert_gt(stream.data.size(), 500, "SFX stream must contain PCM data: " + String(sfx_key))

	assert_eq(SoundManager.get_music_section(1.0), 0, "1.0s must be INTRO (0)")
	assert_eq(SoundManager.get_music_section(9.0), 1, "9.0s must be VERSE (1)")
	assert_eq(SoundManager.get_music_section(17.0), 2, "17.0s must be CHORUS (2)")
	assert_eq(SoundManager.get_music_section(24.0), 3, "24.0s must be BREAKDOWN (3)")
	assert_eq(SoundManager.get_music_section(34.0), 4, "34.0s must be CLIMAX (4)")
	assert_eq(SoundManager.get_music_section(43.0), 5, "43.0s must be FINALE (5)")

	var level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	assert_true(SoundManager.is_music_playing(), "Music must start when Level starts")
	assert_eq(level.current_music_section, 0, "Level must start in MusicSection.INTRO (0)")
	for _i: int in range(20):
		level.simulate_physics(0.5)
	assert_eq(level.current_music_section, 1, "Level at 10.0s must transition to MusicSection.VERSE (1)")
	var grid: Node2D = level.get_node("ArenaGrid") as Node2D
	assert_gt(float(grid.beat_energy), 0.1, "ArenaGrid must receive active beat_energy from Level")

	level._on_player_died()
	assert_false(SoundManager.is_music_playing(), "Music must stop on Game Over")
	level._on_retry_pressed()
	assert_true(SoundManager.is_music_playing(), "Music must restart on Retry")


func test_hand_tracker_process_lifecycle_and_single_instance() -> void:
	var autoload_setting: String = str(ProjectSettings.get_setting("autoload/HandTrackingClient", ""))
	assert_eq(
		autoload_setting,
		"*res://scripts/hand_tracking_client.gd",
		"HandTrackingClient must be registered as an autoload singleton in project.godot"
	)

	var client: Node = track(HAND_TRACKING_CLIENT_SCRIPT.new()) as Node
	var cmd: Dictionary = client.resolve_tracker_launch_command()
	var args: PackedStringArray = cmd.get("args", PackedStringArray()) as PackedStringArray
	assert_gt(str(cmd.get("executable", "")).length(), 0, "Tracker launch executable must resolve")
	assert_true(args.has("--headless"), "Tracker launch args must include --headless")
	assert_true(args.has("--parent-pid"), "Tracker launch args must include --parent-pid for watchdog cleanup")

	var temp_status_path: String = ProjectSettings.globalize_path("user://test_tracker.status")
	var f_ready: FileAccess = FileAccess.open(temp_status_path, FileAccess.WRITE)
	if f_ready != null:
		f_ready.store_string("ready")
		f_ready.close()
	client.set_status_file_override(temp_status_path)
	client.poll_and_update(0.016)
	assert_eq(client.get_status_label_text(), "HAND: NO HAND", "Fresh 'ready' heartbeat with 0 landmarks must report HAND: NO HAND")

	var f_err: FileAccess = FileAccess.open(temp_status_path, FileAccess.WRITE)
	if f_err != null:
		f_err.store_string("error:camera")
		f_err.close()
	client.set_status_file_override(temp_status_path)
	client.poll_and_update(0.016)
	assert_eq(client.get_status_label_text(), "HAND: OFFLINE", "'error:camera' status must report HAND: OFFLINE")

	var menu: Control = _spawn(MAIN_MENU_SCENE) as Control
	var prog_box: Control = menu.get_node_or_null("TrackerProgressBox") as Control
	var prog_lbl: Label = menu.get_node_or_null("TrackerProgressBox/TrackerStatusLabel") as Label
	var prog_bg: ColorRect = menu.get_node_or_null("TrackerProgressBox/TrackerBarBg") as ColorRect
	var prog_fill: ColorRect = menu.get_node_or_null("TrackerProgressBox/TrackerBarBg/TrackerBarFill") as ColorRect
	assert_true(prog_box != null and prog_lbl != null and prog_bg != null and prog_fill != null, "MainMenu must have TrackerProgressBox with label and bar")

	for phase_pair: Array in [
		["loading_model", "HAND TRACKER: LOADING MODEL...", 0.42],
		["opening_camera", "HAND TRACKER: OPENING CAMERA...", 0.72],
		["ready", "HAND TRACKER: READY", 1.0],
	]:
		var f_phase: FileAccess = FileAccess.open(temp_status_path, FileAccess.WRITE)
		if f_phase != null:
			f_phase.store_string(str(phase_pair[0]))
			f_phase.close()
		HandTrackingClient.set_status_file_override(temp_status_path)
		HandTrackingClient.poll_and_update(0.016)
		menu._update_tracker_progress(0.0)
		assert_eq(prog_lbl.text, str(phase_pair[1]), "Progress label must match startup phase")
		assert_true(absf(prog_fill.size.x - prog_bg.size.x * float(phase_pair[2])) < 1.0, "Progress bar fill width must match phase ratio")
		assert_true(prog_box.visible, "Progress box must be visible before auto-fade")

	for _i: int in range(25):
		menu._update_tracker_progress(0.1)
	assert_false(prog_box.visible, "Progress box must auto-fade out ~1.5s after reaching ready")

	HandTrackingClient.reset_state()
	if FileAccess.file_exists(temp_status_path):
		DirAccess.remove_absolute(temp_status_path)


func test_hand_tracking_udp_decoding_socket_draining_and_mirrored_palm_target() -> void:
	var level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	var tracker: Node = track(HAND_TRACKING_CLIENT_SCRIPT.new()) as Node
	level.set_hand_tracker(tracker)
	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D

	var bad_pkt: PackedByteArray = PackedByteArray([1, 2])
	assert_false(tracker.ingest_packet(bad_pkt), "Malformed packet (<4 bytes) must be rejected")

	var old_hand: Array[Vector3] = _build_hand_landmarks(Vector2(0.80, 0.70), false)
	var new_hand: Array[Vector3] = _build_hand_landmarks(Vector2(0.25, 0.30), false)
	var pkt_old: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(old_hand)
	var pkt_new: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(new_hand)
	assert_eq(pkt_old.size(), 256, "Encoded <i63f packet must be exactly 256 bytes")

	var batch: Array[PackedByteArray] = [pkt_old, pkt_new]
	level.ingest_hand_packet_batch(batch)

	assert_true(tracker.has_hand, "Tracker must report has_hand=true after 21-landmark packet")
	var mirrored_palm: Vector2 = tracker.get_mirrored_palm_center()
	assert_true(absf(mirrored_palm.x - 0.75) < 0.001, "Mirrored palm X must be 1.0 - 0.25 = 0.75")
	assert_true(absf(mirrored_palm.y - 0.30) < 0.001, "Mirrored palm Y must be 0.30")
	assert_true(player.external_tracking_active, "Player must engage external_tracking_active")

	var open_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(
		_build_hand_landmarks(Vector2(0.50, 0.50), false)
	)
	var fist_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(
		_build_hand_landmarks(Vector2(0.50, 0.50), true)
	)
	level.ingest_hand_packet(open_pkt)
	player._physics_process(0.016)
	assert_false(player.is_shielding, "Open hand must not raise shield")

	level.ingest_hand_packet(fist_pkt)
	player._physics_process(0.016)
	assert_true(player.is_shielding, "Closed fist must raise shield")

	for _i: int in range(40):
		level.ingest_hand_packet(fist_pkt)
		player._physics_process(0.05)
		level.simulate_physics(0.05)
	assert_false(player.is_shielding, "Sustained fist must exhaust the shield")
	assert_true(player.shield_exhausted, "Shield must report the exhausted state")
	var hand_shadow_node: Node2D = level.get_node("HandShadow") as Node2D
	var hull_border_node: Line2D = level.get_node("HandShadow/ShieldHullBorder") as Line2D
	assert_false(bool(hand_shadow_node.is_shield_visual_active), "Exhausted shield must deactivate hand hologram shield state")
	assert_false(hull_border_node.visible, "Exhausted shield must hide hand hologram shield hull border")

	level.ingest_hand_packet(open_pkt)
	player._physics_process(0.016)
	assert_false(player.is_shielding, "Opening the hand must release the shield")
	for _i: int in range(30):
		player._physics_process(0.05)
	level.ingest_hand_packet(fist_pkt)
	player._physics_process(0.016)
	assert_true(player.is_shielding, "A new closed fist must raise the recharged shield")


func test_hand_tracking_bidirectional_fallback_and_resumption() -> void:
	var level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	var tracker: Node = track(HAND_TRACKING_CLIENT_SCRIPT.new()) as Node
	level.set_hand_tracker(tracker)
	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D

	var hand_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(
		_build_hand_landmarks(Vector2(0.30, 0.40), false)
	)
	var empty_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_empty_packet()
	assert_eq(empty_pkt.size(), 4, "Empty <i packet must be 4 bytes")

	level.ingest_hand_packet(hand_pkt)
	assert_true(player.external_tracking_active, "21-landmark packet must engage external_tracking_active")

	level.ingest_hand_packet(empty_pkt)
	assert_false(player.external_tracking_active, "0-landmark packet must immediately clear external_tracking_active")
	assert_false(player.use_target_position, "Releasing hand tracking must clear stale target following")

	var mouse_target: Vector2 = Vector2(220.0, 180.0)
	player.set_target_position(mouse_target, false)
	assert_false(player.external_tracking_active, "Mouse target must keep external_tracking_active false")
	for _i: int in range(30):
		player._physics_process(0.016)
	assert_true(player.global_position.distance_to(mouse_target) < 6.0, "Mouse fallback must move player when no hand is tracked")

	level.ingest_hand_packet(hand_pkt)
	assert_true(player.external_tracking_active, "Subsequent 21-landmark packet must automatically re-engage external_tracking_active")

	tracker.poll_and_update(0.6)
	level.simulate_physics(0.016)
	assert_false(player.external_tracking_active, "UDP packet timeout must release external_tracking_active")


func test_hand_tracking_hud_status_pill_and_constellation_shadow() -> void:
	var level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	var tracker: Node = track(HAND_TRACKING_CLIENT_SCRIPT.new()) as Node
	level.set_hand_tracker(tracker)

	var bg: ColorRect = level.get_node("Background") as ColorRect
	var hand_shadow: Node2D = level.get_node("HandShadow") as Node2D
	var beam_container: Node2D = level.get_node("BeamContainer") as Node2D
	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	var palm_poly: Polygon2D = level.get_node("HandShadow/PalmPolygon") as Polygon2D
	var hull_poly: Polygon2D = level.get_node("HandShadow/ShieldHullPolygon") as Polygon2D
	var hull_border: Line2D = level.get_node("HandShadow/ShieldHullBorder") as Line2D
	var index_bone: Line2D = level.get_node("HandShadow/IndexBone") as Line2D
	var tip_4: Polygon2D = level.get_node("HandShadow/Fingertip4") as Polygon2D
	var tip_8: Polygon2D = level.get_node("HandShadow/Fingertip8") as Polygon2D
	var tip_12: Polygon2D = level.get_node("HandShadow/Fingertip12") as Polygon2D
	var tip_16: Polygon2D = level.get_node("HandShadow/Fingertip16") as Polygon2D
	var tip_20: Polygon2D = level.get_node("HandShadow/Fingertip20") as Polygon2D
	var player_shield_ring: Line2D = level.get_node("Player/ShieldRing") as Line2D
	var status_pill: ColorRect = level.get_node("HUD/HUDRoot/HandStatusPill") as ColorRect
	var status_icon: Polygon2D = level.get_node("HUD/HUDRoot/HandStatusPill/HandStatusIcon") as Polygon2D
	var status_label: Label = level.get_node("HUD/HUDRoot/HandStatusPill/HandStatusLabel") as Label

	assert_true(hand_shadow != null, "HandShadow node must exist in level.tscn")
	assert_true(hull_poly != null and hull_border != null, "HandShadow must include ShieldHullPolygon and ShieldHullBorder")
	assert_true(status_pill != null and status_icon != null and status_label != null, "HUD HandStatusPill, icon, and label must exist")
	assert_gt(hand_shadow.get_index(), bg.get_index(), "Background must be drawn behind HandShadow")
	assert_gt(beam_container.get_index(), hand_shadow.get_index(), "HandShadow must be drawn behind BeamContainer hazards")
	assert_gt(player.get_index(), beam_container.get_index(), "BeamContainer must be ordered before Player")

	assert_eq(status_label.text, "HAND: OFFLINE", "HUD status must start as HAND: OFFLINE")
	assert_false(hand_shadow.visible, "HandShadow must be hidden when no hand has been tracked")

	var open_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(
		_build_hand_landmarks(Vector2(0.40, 0.50), false)
	)
	level.ingest_hand_packet(open_pkt)
	assert_eq(status_label.text, "HAND: TRACKING", "HUD status must display HAND: TRACKING when 21 landmarks are received")
	assert_true(hand_shadow.visible, "HandShadow must become visible when hand is tracked")
	assert_false(hull_poly.visible, "ShieldHullPolygon must be hidden when hand is open")
	assert_false(hull_border.visible, "ShieldHullBorder must be hidden when hand is open")
	assert_eq(palm_poly.polygon.size(), 6, "PalmPolygon must have 6 vertices (#0, #1, #5, #9, #13, #17)")
	assert_eq(index_bone.points.size(), 5, "IndexBone Line2D must connect 5 landmarks (#0, #5, #6, #7, #8)")
	var open_tip8_pos: Vector2 = tip_8.position
	var open_tip8_scale: Vector2 = tip_8.scale
	var open_bone_width: float = index_bone.width

	var fist_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_landmarks_packet(
		_build_hand_landmarks(Vector2(0.40, 0.50), true)
	)
	level.ingest_hand_packet(fist_pkt)
	player._physics_process(0.016)
	assert_gt(tip_8.scale.x, open_tip8_scale.x, "Fingertip node must pulse larger on closed-fist input")
	assert_true(tip_8.position != open_tip8_pos, "Fingertip node must contract toward palm on closed fist")
	assert_true(bool(hand_shadow.is_shield_visual_active), "HandShadow must activate shield visual state on closed fist")
	assert_true(hull_poly.visible and hull_border.visible, "HandShadow shield hull barrier must appear when fist is closed")
	assert_gt(index_bone.width, open_bone_width, "HandShadow bone conduits must thicken when acting as the shield")
	assert_true(absf(tip_4.position.y - tip_20.position.y) < 4.0, "Thumb and pinky tips must align horizontally as shield shoulders")
	assert_true(absf(tip_8.position.y - tip_16.position.y) < 4.0, "Index and ring tips must align horizontally as shield crown peaks")
	assert_true(tip_12.position.y < tip_8.position.y, "Middle tip must form the top-center apex of the crest shield")
	assert_gt(palm_poly.polygon[0].y, tip_4.position.y + 40.0, "Wrist landmark must form the bottom point of the crest shield")
	assert_false(player_shield_ring.visible, "Player circular ShieldRing must be hidden while hand hologram acts as the shield")

	var empty_pkt: PackedByteArray = HAND_TRACKING_CLIENT_SCRIPT.encode_empty_packet()
	level.ingest_hand_packet(empty_pkt)
	assert_eq(status_label.text, "HAND: NO HAND", "HUD status must display HAND: NO HAND when 0 landmarks are received")

	var alpha_before_fade: float = hand_shadow.alpha
	level.simulate_physics(0.1)
	assert_gt(alpha_before_fade, hand_shadow.alpha, "HandShadow alpha must smoothly decrease when no hand is tracked")

	for _i: int in range(10):
		tracker.poll_and_update(0.1)
		level.simulate_physics(0.1)
	assert_eq(hand_shadow.alpha, 0.0, "HandShadow alpha must reach 0.0 after fade-out")
	assert_false(hand_shadow.visible, "HandShadow must hide once faded out")
	assert_eq(status_label.text, "HAND: OFFLINE", "HUD status must return to HAND: OFFLINE after packet timeout")


func test_shield_hud_reflects_energy_state() -> void:
	var level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	var shield_label: Label = level.get_node("HUD/HUDRoot/ShieldLabel") as Label
	var shield_bg: ColorRect = level.get_node("HUD/HUDRoot/ShieldBg") as ColorRect
	var shield_fill: ColorRect = level.get_node("HUD/HUDRoot/ShieldFill") as ColorRect

	assert_true(shield_label != null and shield_bg != null and shield_fill != null, "HUD must expose the shield bar")
	assert_eq(shield_label.text, "SHIELD: READY", "Shield HUD must start ready")
	assert_true(absf(shield_fill.size.x - shield_bg.size.x) < 0.5, "Shield bar must start full")

	player.set_shield_held(true)
	player._physics_process(0.5)
	level.simulate_physics(0.016)
	assert_eq(shield_label.text, "SHIELD: ACTIVE", "Shield HUD must report active state")
	assert_true(shield_fill.size.x < shield_bg.size.x, "Shield HUD must shrink while draining")
	assert_true((player.get_node("ShieldRing") as Line2D).visible, "Player circular ShieldRing must remain visible when shielding via keyboard/mouse")

	for _i: int in range(40):
		player._physics_process(0.05)
	level.simulate_physics(0.016)
	assert_eq(shield_label.text, "SHIELD: EMPTY", "Shield HUD must report the exhausted state")
	assert_true(shield_fill.size.x < 1.0, "Exhausted shield bar must be empty")

	player.set_shield_held(false)
	player._physics_process(0.2)
	level.simulate_physics(0.016)
	assert_eq(shield_label.text, "SHIELD: RECHARGING", "Shield HUD must report recharge state")


func test_autonomous_threat_rotation_covers_all_new_types() -> void:
	var level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	level.set_difficulty(0)
	level.restart_level()

	var seen_groups: Dictionary = {}
	for _i: int in range(3):
		assert_true(level._spawn_rotating_autonomous_threat(), "Easy must spawn an autonomous threat when the slot is free")
		var container: Node2D = level.get_node("BeamContainer") as Node2D
		var spawned: Node = container.get_child(container.get_child_count() - 1)
		for g: StringName in [&"enemies", &"saws", &"closing_walls"]:
			if spawned.is_in_group(g):
				seen_groups[g] = true
		container.remove_child(spawned)
		spawned.free()

	for expected_group: StringName in [&"enemies", &"saws", &"closing_walls"]:
		assert_true(seen_groups.has(expected_group), "Autonomous rotation must cover group %s on Easy" % String(expected_group))


func test_saw_telegraph_bounce_collision_and_lifetime() -> void:
	var saw: Area2D = _spawn(SAW_SCENE) as Area2D
	var bounces: Array[Vector2] = []
	saw.bounced.connect(func(_pos: Vector2, normal: Vector2) -> void: bounces.append(normal))
	saw.configure(0, Vector2(160.0, 324.0), Vector2.LEFT, 280.0, 30.0, 0.4, 3.0)
	var col: CollisionShape2D = saw.get_node("CollisionShape2D") as CollisionShape2D
	var blade: Polygon2D = saw.get_node("Blade") as Polygon2D

	assert_eq(saw.current_phase, 0, "Saw must start in TELEGRAPH phase")
	assert_false(saw.is_hazard_active, "Saw must be harmless while telegraphing")
	assert_true(col.disabled, "Saw collision must be disabled while telegraphing")
	assert_true(blade.polygon.size() >= 16, "Saw blade must be a toothed primitive polygon")

	for _i: int in range(5):
		saw.simulate_physics(0.1)
	assert_eq(saw.current_phase, 1, "Saw must activate after its warning")
	assert_true(saw.is_hazard_active, "Active saw must be lethal")
	assert_false(col.disabled, "Active saw collision must be enabled")

	var start_x: float = saw.global_position.x
	for _i: int in range(10):
		saw.simulate_physics(0.05)
	assert_true(saw.global_position.x < start_x, "Saw must travel in its launch direction")
	assert_gt(bounces.size(), 0, "Saw must bounce off arena edges and emit bounced")

	for _i: int in range(40):
		saw.simulate_physics(0.1)
	assert_false(saw.is_hazard_active, "Fading saw must stop dealing damage")


func test_closing_wall_gap_telegraph_and_cycle() -> void:
	var wall: Node2D = _spawn(CLOSING_WALL_SCENE) as Node2D
	var slams: Array[Vector2] = []
	wall.wall_slammed.connect(func(center: Vector2, _axis: int) -> void: slams.append(center))
	wall.configure(0, 324.0, 140.0, 46.0, 0.5, 0.4, 0.3, 0.2)

	assert_eq(wall.current_phase, 0, "Closing wall must start in TELEGRAPH phase")
	assert_false(wall.is_hazard_active, "Closing wall must be harmless while telegraphing")
	assert_true(wall.get_gap_size() >= 112.0, "Wall gap must stay wide enough to traverse")
	assert_eq(wall.wall_a.visible, false, "Walls must stay offscreen during telegraph")
	assert_false(wall.damage_a.monitoring, "Wall damage must be disabled during telegraph")
	assert_eq(wall.telegraph_a.visible, true, "Telegraph preview must be visible")

	var wall_a_start: Vector2 = wall.wall_a.global_position
	wall.simulate_physics(0.55)
	assert_eq(wall.current_phase, 1, "Wall must start closing after warning")
	assert_true(wall.is_hazard_active, "Closing wall must be lethal while sliding")
	assert_true(wall.wall_a.visible, "Walls must appear while closing")
	assert_true(wall.damage_a.monitoring, "Wall damage must enable while closing")

	wall.simulate_physics(0.2)
	assert_gt(wall.wall_a.global_position.x, wall_a_start.x, "Left wall must slide inward")

	wall.simulate_physics(0.3)
	assert_eq(wall.current_phase, 2, "Wall must hold at its target position")
	assert_eq(slams.size(), 1, "Wall must emit wall_slammed on entering HOLD")
	var inner_gap: float = (wall.wall_b.global_position.x - 23.0) - (wall.wall_a.global_position.x + 23.0)
	assert_true(absf(inner_gap - wall.get_gap_size()) < 1.0, "Final gap must match the configured traversable width")

	wall.simulate_physics(0.35)
	assert_eq(wall.current_phase, 3, "Wall must retract after its hold window")
	assert_false(wall.is_hazard_active, "Retracting wall must stop dealing damage")


func test_enemy_behaviours_telegraph_and_damage_windows() -> void:
	var target: Node2D = _add_node(Node2D.new()) as Node2D
	target.global_position = Vector2(500.0, 324.0)

	var chaser: Area2D = _spawn(ENEMY_SCENE) as Area2D
	var lunges: Array[Vector2] = []
	chaser.enemy_lunged.connect(func(_pos: Vector2, dir: Vector2) -> void: lunges.append(dir))
	chaser.configure_enemy(0, Vector2(800.0, 324.0), target, 1.0, 0.35, 6.0)
	var chaser_col: CollisionShape2D = chaser.get_node("CollisionShape2D") as CollisionShape2D
	assert_eq(chaser.current_phase, 0, "Chaser must start in SPAWN phase")
	assert_false(chaser.is_hazard_active, "Chaser must be harmless while spawning")
	assert_true(chaser_col.disabled, "Chaser collision must be disabled while spawning")
	chaser.simulate_physics(0.4)
	assert_eq(chaser.current_phase, 1, "Chaser must activate after its warning")
	assert_false(chaser_col.disabled, "Active chaser must have collision enabled")
	var chaser_start_x: float = chaser.global_position.x
	for _i: int in range(36):
		chaser.simulate_physics(0.05)
	assert_true(chaser.global_position.x < chaser_start_x, "Chaser must move toward the player")
	assert_gt(lunges.size(), 0, "Chaser must perform at least one high-speed lunge")

	var turret: Area2D = _spawn(ENEMY_SCENE) as Area2D
	var fired_directions: Array[Vector2] = []
	turret.fire_projectile.connect(func(_origin: Vector2, direction: Vector2, _speed: float, _radius: float) -> void:
		fired_directions.append(direction)
	)
	turret.configure_enemy(1, Vector2(800.0, 300.0), target, 1.0, 0.35, 5.0)
	turret.simulate_physics(0.4)
	assert_eq(turret.current_phase, 1, "Turret must activate after its warning")
	turret.simulate_physics(0.8)
	assert_true(turret.aim_line.visible, "Turret must paint its aim line before firing")
	turret.simulate_physics(0.35)
	assert_eq(fired_directions.size(), 3, "Turret must emit three projectile signals")

	var orbiter: Area2D = _spawn(ENEMY_SCENE) as Area2D
	var orbiter_shots: Array[Vector2] = []
	orbiter.fire_projectile.connect(func(_origin: Vector2, direction: Vector2, _speed: float, _radius: float) -> void:
		orbiter_shots.append(direction)
	)
	orbiter.configure_enemy(2, Vector2(800.0, 300.0), target, 1.0, 0.35, 6.0)
	orbiter.simulate_physics(0.4)
	for _i: int in range(40):
		orbiter.simulate_physics(0.05)
	var orbit_distance: float = orbiter.global_position.distance_to(target.global_position)
	assert_true(orbit_distance > 100.0 and orbit_distance < 330.0, "Orbiter must circle the player at a readable distance")
	assert_gt(orbiter_shots.size(), 0, "Orbiter must periodically fire inward pulse projectiles")

	var pulsar: Area2D = _spawn(ENEMY_SCENE) as Area2D
	var pulsar_shots: Array[Vector2] = []
	pulsar.fire_projectile.connect(func(_origin: Vector2, direction: Vector2, _speed: float, _radius: float) -> void:
		pulsar_shots.append(direction)
	)
	pulsar.configure_enemy(3, Vector2(900.0, 324.0), target, 1.0, 0.35, 6.0)
	pulsar.simulate_physics(0.4)
	for _i: int in range(28):
		pulsar.simulate_physics(0.05)
	assert_eq(pulsar_shots.size(), 3, "Pulsar must emit 3 fire_projectile signals")


func test_beam_exact_hitbox_and_shield_latch_guard() -> void:
	var beam: Area2D = _spawn(LIGHT_BEAM_SCENE) as Area2D
	beam.configure(Vector2(576.0, 324.0), 0.0, 44.0, 0.5, 0.4)
	var beam_vis: Polygon2D = beam.get_node("BeamVisual") as Polygon2D
	assert_eq(beam_vis.scale, Vector2.ONE, "Telegraph BeamVisual must stay at 1:1 width scale with hitbox")

	var player: CharacterBody2D = _spawn(PLAYER_SCENE) as CharacterBody2D
	player.reset_player(Vector2(576.0, 324.0 + 48.0))
	assert_false(beam._is_within_beam(player), "Player 48px off beam axis must be outside 44px beam hitbox")

	player.reset_player(Vector2(576.0, 324.0 + 12.0))
	assert_true(beam._is_within_beam(player), "Player 12px off beam axis must be inside 44px beam hitbox")

	Input.action_press("shield")
	player.reset_player(Vector2(576.0, 324.0))
	player._physics_process(0.05)
	var latched_after_reset: bool = player.is_shielding
	Input.action_release("shield")
	assert_false(latched_after_reset, "Held shield input across reset_player must not latch shield active")
	player._physics_process(0.05)
	assert_false(player.is_shielding, "Releasing shield input clears latch guard without activating shield")

	Input.action_press("shield")
	player._physics_process(0.05)
	var active_on_fresh_press: bool = player.is_shielding
	player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	Input.action_release("shield")
	assert_true(active_on_fresh_press, "Fresh shield press after release must activate shield")
	assert_false(player.is_shielding, "Window focus loss must immediately release active shield")


func test_player_radial_glow_and_light_mask_isolation() -> void:
	var level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	var glow: Polygon2D = player.get_node("PlayerGlow") as Polygon2D
	var light: PointLight2D = player.get_node("PlayerLight") as PointLight2D
	var shield_glow: Polygon2D = player.get_node("ShieldGlow") as Polygon2D
	var shield_ring: Line2D = player.get_node("ShieldRing") as Line2D
	var outer_poly: Polygon2D = player.get_node("OuterPolygon") as Polygon2D
	var arena_grid: Node2D = level.get_node("ArenaGrid") as Node2D

	assert_gt(glow.polygon.size(), 200, "PlayerGlow must use multi-ring radial gradient vertices")
	assert_eq(glow.vertex_colors.size(), glow.polygon.size(), "PlayerGlow must assign per-vertex alpha falloff colors")
	assert_gt(glow.polygons.size(), 200, "PlayerGlow must build sub-polygons across concentric rings")
	assert_eq(shield_glow.polygon.size(), 32, "ShieldGlow must be a smooth 32-segment circle")
	assert_eq(shield_ring.points.size(), 32, "ShieldRing must be a smooth 32-segment circle")

	assert_eq(glow.light_mask, 0, "PlayerGlow must ignore PointLight2D self-illumination")
	assert_eq(outer_poly.light_mask, 0, "OuterPolygon must ignore PointLight2D self-illumination")
	assert_eq(light.range_item_cull_mask, 2, "PlayerLight must only illuminate light_mask layer 2")
	assert_eq(arena_grid.light_mask, 2, "ArenaGrid must be on light_mask layer 2 to receive PlayerLight")

	var idle_scale: Vector2 = glow.scale
	var idle_alpha: float = glow.color.a
	player.velocity = Vector2(420.0, 0.0)
	player._update_visuals(0.25)
	assert_eq(glow.scale, idle_scale, "Steady PlayerGlow must not scale with idle time or movement speed")
	assert_eq(glow.color.a, idle_alpha, "Steady PlayerGlow alpha must not fluctuate with idle time or movement speed")


func _build_hand_landmarks(palm_target: Vector2, closed_fist: bool) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	pts.resize(21)
	var px: float = palm_target.x
	var py: float = palm_target.y

	pts[0] = Vector3(px, py + 0.08, 0.0)
	pts[1] = Vector3(px - 0.05, py + 0.05, 0.0)
	pts[2] = Vector3(px - 0.08, py + 0.02, 0.0)
	pts[3] = Vector3(px - 0.10, py - 0.01, 0.0)
	pts[4] = Vector3(px - 0.04, py + 0.01, 0.0) if closed_fist else Vector3(px - 0.12, py - 0.04, 0.0)

	var finger_x_offsets: Array[float] = [-0.06, -0.02, 0.02, 0.06]
	var base_indices: Array[int] = [5, 9, 13, 17]
	for f: int in range(4):
		var b_idx: int = base_indices[f]
		var fx: float = px + finger_x_offsets[f]
		pts[b_idx] = Vector3(fx, py - 0.02, 0.0)
		pts[b_idx + 1] = Vector3(fx, py - 0.07, 0.0)
		if closed_fist:
			pts[b_idx + 2] = Vector3(fx, py - 0.03, 0.0)
			pts[b_idx + 3] = Vector3(fx, py + 0.01, 0.0)
		else:
			pts[b_idx + 2] = Vector3(fx, py - 0.12, 0.0)
			pts[b_idx + 3] = Vector3(fx, py - 0.17, 0.0)

	return pts


func _assert_subtree_monochrome_and_primitive(node: Node) -> void:
	assert_false(node is Sprite2D, "External texture Sprite2D is not allowed: " + node.name)
	assert_false(node is TextureRect, "External TextureRect is not allowed: " + node.name)
	if node is Polygon2D:
		var c: Color = (node as Polygon2D).color
		assert_true(absf(c.r - c.g) < 0.01 and absf(c.g - c.b) < 0.01, "Polygon2D must be grayscale: " + node.name)
	elif node is ColorRect:
		var c: Color = (node as ColorRect).color
		assert_true(absf(c.r - c.g) < 0.01 and absf(c.g - c.b) < 0.01, "ColorRect must be grayscale: " + node.name)
	elif node is Line2D:
		var c: Color = (node as Line2D).default_color
		assert_true(absf(c.r - c.g) < 0.01 and absf(c.g - c.b) < 0.01, "Line2D must be grayscale: " + node.name)

	for child: Node in node.get_children():
		_assert_subtree_monochrome_and_primitive(child)
