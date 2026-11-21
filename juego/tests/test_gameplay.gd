extends McpTestSuite

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const CREDITS_SCENE: PackedScene = preload("res://scenes/credits.tscn")
const LEVEL_SCENE: PackedScene = preload("res://scenes/level.tscn")
const BOSS_LEVEL_SCENE: PackedScene = preload("res://scenes/boss_level.tscn")
const BOSS_SCENE: PackedScene = preload("res://scenes/boss.tscn")
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
	GameManager.spectator_override_mode = 0
	GameManager.set_test_screen_count_override(-1)
	GameManager.save_path = "user://test_gameplay_save.tres"
	GameManager.save_data = SaveData.new()
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
		BOSS_LEVEL_SCENE,
		BOSS_SCENE,
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
	var missing_status_path: String = ProjectSettings.globalize_path("user://test_hud_missing_tracker.status")
	if FileAccess.file_exists(missing_status_path):
		DirAccess.remove_absolute(missing_status_path)
	tracker.set_status_file_override(missing_status_path)
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


func test_cube_life_slices_and_shield_time_feedback() -> void:
	var level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	var player: CharacterBody2D = level.get_node("Player") as CharacterBody2D
	var slice1: Polygon2D = player.get_node_or_null("LifeSlice1") as Polygon2D
	var slice2: Polygon2D = player.get_node_or_null("LifeSlice2") as Polygon2D
	var slice3: Polygon2D = player.get_node_or_null("LifeSlice3") as Polygon2D
	var shield_bar_root: Node2D = player.get_node_or_null("ShieldBarRoot") as Node2D
	var shield_bar_fill: Polygon2D = player.get_node_or_null("ShieldBarRoot/ShieldBarFill") as Polygon2D
	var shield_time_label: Label = level.get_node_or_null("HUD/HUDRoot/ShieldTimeLabel") as Label

	assert_true(slice1 != null and slice2 != null and slice3 != null, "Player must expose LifeSlice1..3 nodes")
	assert_true(shield_bar_root != null and shield_bar_fill != null, "Player must expose ShieldBarRoot and ShieldBarFill")
	assert_true(shield_time_label != null, "HUD must expose ShieldTimeLabel")
	_assert_subtree_monochrome_and_primitive(player)
	for slice: Polygon2D in [slice1, slice2, slice3]:
		assert_eq(slice.light_mask, 0, "Life slices must have light_mask == 0")
		assert_true(slice.color.r > 0.9, "All 3 life slices must start bright at 3 HP")

	player.take_damage(1)
	assert_eq(player.current_hp, 2, "Player HP must drop to 2 after 1 damage")
	for _i: int in range(15):
		player._physics_process(0.1)
	assert_true(slice1.color.r > 0.9 and slice2.color.r > 0.9, "LifeSlice1 and LifeSlice2 must remain bright at 2 HP")
	assert_true(slice3.color.r < 0.3, "LifeSlice3 must dim at 2 HP once flash settles")

	player.take_damage(1)
	assert_eq(player.current_hp, 1, "Player HP must drop to 1 after second hit")
	for _i: int in range(15):
		player._physics_process(0.1)
	assert_true(slice1.color.r > 0.6, "LifeSlice1 must remain visible/bright at 1 HP")
	assert_true(slice2.color.r < 0.3 and slice3.color.r < 0.3, "LifeSlice2 and LifeSlice3 must dim at 1 HP")

	player.heal(2)
	assert_eq(player.current_hp, 3, "heal(2) must restore player to 3 HP")
	assert_true(slice1.color.r > 0.9 and slice2.color.r > 0.9 and slice3.color.r > 0.9, "All 3 life slices must restore bright on heal")

	assert_false(shield_bar_root.visible, "Under-cube ShieldBarRoot must start hidden when full")
	assert_eq(shield_time_label.text, "1.7s", "HUD ShieldTimeLabel must start at 1.7s")

	player.set_shield_held(true)
	player._physics_process(0.5)
	level.simulate_physics(0.016)
	assert_true(shield_bar_root.visible, "ShieldBarRoot must become visible while shielding")
	assert_true(shield_bar_fill.scale.x < 1.0 and shield_bar_fill.scale.x > 0.0, "ShieldBarFill.scale.x must shrink while draining")
	assert_true(shield_time_label.text.ends_with("s"), "ShieldTimeLabel must format seconds with s suffix")
	assert_true(float(shield_time_label.text.trim_suffix("s")) < 1.5, "ShieldTimeLabel must drop below 1.5s while draining")

	for _i: int in range(30):
		player._physics_process(0.05)
	level.simulate_physics(0.016)
	assert_eq(shield_time_label.text, "0.0s", "ShieldTimeLabel must reach 0.0s when empty")

	player.set_shield_held(false)
	for _i: int in range(10):
		player._physics_process(0.08)
	level.simulate_physics(0.016)
	assert_true(shield_bar_root.visible, "ShieldBarRoot must stay visible while recharging")
	assert_true(shield_bar_fill.scale.x > 0.0 and shield_bar_fill.scale.x < 1.0, "ShieldBarFill.scale.x must reflect partial recharge")

	for _i: int in range(50):
		player._physics_process(0.05)
	level.simulate_physics(0.016)
	assert_eq(shield_time_label.text, "1.7s", "ShieldTimeLabel must restore 1.7s on full recharge")
	assert_false(shield_bar_root.visible, "ShieldBarRoot must fade back out after reaching full")


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


func test_multiplayer_ranking_isolation_and_responsive_leaderboard() -> void:
	var backup_save: SaveData = GameManager.save_data
	GameManager.save_data = SaveData.new()

	GameManager.set_player_name("Alice")
	assert_eq(GameManager.get_best_summary(), "No runs yet", "Fresh Alice must start with no runs")
	assert_true(GameManager.report_result(2, 45.0, true), "Alice Hard completion must be recorded")
	assert_eq(GameManager.get_best_summary(), "BEST  HARD  -  COMPLETED", "Alice best summary must be Hard Completed")

	GameManager.set_player_name("Bob")
	assert_eq(GameManager.get_best_summary(), "No runs yet", "Bob must not share Alice's scores")
	assert_true(GameManager.save_data.get_record(2).is_empty(), "Bob must have empty Hard record")
	assert_true(GameManager.report_result(1, 29.4, false), "Bob Normal 29.4s run must be recorded")
	assert_eq(GameManager.get_best_summary(), "BEST  NORMAL  -  29.4s", "Bob best summary must be Normal 29.4s")

	GameManager.set_player_name("alice")
	assert_eq(GameManager.get_best_summary(), "BEST  HARD  -  COMPLETED", "Case-insensitive switch to 'alice' must restore Alice's records")
	assert_eq(GameManager.get_player_rank(-1, "Alice"), 1, "Alice must rank #1 globally")
	assert_eq(GameManager.get_player_rank(-1, "Bob"), 2, "Bob must rank #2 globally")

	var menu: Control = _spawn(MAIN_MENU_SCENE) as Control
	menu.name_edit.text = "Bob"
	menu._on_name_text_changed("Bob")
	assert_true(menu.best_label.text.find("BEST  NORMAL  -  29.4s") != -1, "Typing Bob in NameEdit must live-update BestLabel")

	menu.name_edit.text = "Charlie"
	menu._on_name_text_changed("Charlie")
	assert_eq(menu.best_label.text, "No runs yet", "Typing unplayed Charlie must show 'No runs yet'")

	menu._on_records_pressed()
	assert_true(menu.records_panel.visible, "RecordsPanel must open")
	assert_eq(menu.leaderboard_list.get_child_count(), 2, "Global leaderboard must show 2 ranked players (Alice and Bob)")
	_assert_subtree_monochrome_and_primitive(menu.records_panel)

	menu._on_resized(Vector2(480.0, 360.0))
	assert_true(menu.records_box.custom_minimum_size.x <= 480.0, "RecordsBox must responsively shrink on narrow viewports")
	assert_true(menu.personal_stats_box.vertical, "PersonalStatsBox must stack vertically on narrow viewports")

	GameManager.save_data = backup_save
	GameManager.save_game()


func test_dual_monitor_spectator_ranking_window_and_pinned_rank() -> void:
	assert_false(GameManager.is_spectator_window_active(), "Spectator window must be closed on 1 monitor by default")

	GameManager.set_test_screen_count_override(2)
	assert_true(GameManager.is_spectator_window_active(), "Connecting 2nd monitor must auto-open SpectatorRankingWindow")
	assert_true(GameManager.spectator_view != null, "SpectatorRankingView must be instantiated inside SpectatorRankingWindow")

	var view: Control = GameManager.spectator_view
	_assert_subtree_monochrome_and_primitive(view)

	GameManager.notify_preview_player_name("Valentina")
	assert_true(view.player_label.text.find("VALENTINA") != -1, "Spectator header must live-update as player types username")

	# Populate 12 players so active player (#12) is outside Top 10
	for i: int in range(1, 12):
		GameManager.set_player_name("Player%02d" % i)
		GameManager.report_result(2, 45.0 - float(i), false)

	GameManager.set_player_name("Challenger12")
	GameManager.report_result(2, 12.5, false)
	assert_true(view.record_banner_label.visible, "New record must trigger celebration banner on spectator display")

	var global_list: VBoxContainer = view._column_lists.get(-1) as VBoxContainer
	assert_true(global_list != null, "Global leaderboard column list must exist")
	# 8 top rows + 1 ellipsis + 1 pinned row = 10 children
	assert_eq(global_list.get_child_count(), 10, "Leaderboard column must render Top 8 + ellipsis + pinned #12 active player")
	assert_true(global_list.get_node_or_null("PinnedCurrentPlayerRow") != null, "Active player ranked #12 must be pinned at bottom")

	# Responsive column adaptation for distance legibility
	view._on_resized(Vector2(1280.0, 720.0))
	assert_eq(view.columns_grid.columns, 2, "Wide monitor must display 2 giant side-by-side ranking boards for distance legibility")
	view._on_resized(Vector2(800.0, 600.0))
	assert_eq(view.columns_grid.columns, 2, "Medium monitor must display 2 side-by-side ranking boards")
	view._on_resized(Vector2(500.0, 700.0))
	assert_eq(view.columns_grid.columns, 1, "Narrow portrait monitor must stack ranking boards")

	# Unplugging 2nd monitor closes auto window
	GameManager.set_test_screen_count_override(1)
	assert_false(GameManager.is_spectator_window_active(), "Unplugging 2nd monitor must auto-close spectator window")

	# F10 manual toggle works on 1 monitor
	assert_true(GameManager.toggle_spectator_window(), "F10 toggle must open preview window on single monitor")
	assert_false(GameManager.toggle_spectator_window(), "Second F10 toggle must close preview window")
	GameManager.spectator_override_mode = 0
	GameManager.set_test_screen_count_override(-1)


func test_boss_mode_menu_and_phase_leaderboard_integration() -> void:
	var backup_save: SaveData = GameManager.save_data
	var backup_diff: int = GameManager.selected_difficulty
	GameManager.save_data = SaveData.new()
	GameManager.set_state(GameManager.State.MENU)
	GameManager.set_difficulty(GameManager.Difficulty.NORMAL)

	var menu: Control = _spawn(MAIN_MENU_SCENE) as Control
	var diff_btn: Button = menu.get_node_or_null("CenterContainer/MenuBox/DifficultyButton") as Button
	var boss_btn: Button = menu.get_node_or_null("CenterContainer/MenuBox/BossButton") as Button
	assert_true(diff_btn != null and boss_btn != null, "DifficultyButton and BossButton must exist in MainMenu")
	assert_true(boss_btn.pressed.is_connected(menu._on_boss_pressed), "BossButton must connect to _on_boss_pressed")

	# Verify DifficultyButton still cycles Normal -> Hard -> Easy -> Normal
	assert_eq(menu.selected_difficulty, GameManager.Difficulty.NORMAL, "Menu must start on Normal")
	assert_eq(diff_btn.text, "Difficulty: Normal", "DifficultyButton must display Normal")
	menu._on_difficulty_pressed()
	assert_eq(menu.selected_difficulty, GameManager.Difficulty.HARD, "First press must cycle to Hard")
	menu._on_difficulty_pressed()
	assert_eq(menu.selected_difficulty, GameManager.Difficulty.EASY, "Second press must cycle to Easy")
	menu._on_difficulty_pressed()
	assert_eq(menu.selected_difficulty, GameManager.Difficulty.NORMAL, "Third press must cycle back to Normal")

	# Select Hard, launch Boss Mode, and verify selected_difficulty is NOT overwritten
	menu.set_difficulty(GameManager.Difficulty.HARD)
	assert_eq(GameManager.selected_difficulty, GameManager.Difficulty.HARD, "Standard difficulty must be Hard")
	GameManager.start_level(GameManager.Difficulty.BOSS)
	assert_eq(GameManager.active_run_difficulty, GameManager.Difficulty.BOSS, "active_run_difficulty must become BOSS (3)")
	assert_eq(GameManager.selected_difficulty, GameManager.Difficulty.HARD, "Playing Boss Mode must NOT overwrite GameManager.selected_difficulty")

	GameManager.go_to_menu()
	var menu_after_boss: Control = _spawn(MAIN_MENU_SCENE) as Control
	assert_eq(menu_after_boss.selected_difficulty, GameManager.Difficulty.HARD, "Returning to menu after Boss must preserve Hard selection")
	assert_eq(menu_after_boss.difficulty_button.text, "Difficulty: Hard", "DifficultyButton after Boss must still read Hard")
	assert_eq(GameManager.active_run_difficulty, GameManager.Difficulty.HARD, "go_to_menu must restore active_run_difficulty to selected_difficulty")

	# Global leaderboard (-1) protection: incomplete 3s Boss Phase 1 death must NOT outrank Hard COMPLETED
	GameManager.set_player_name("HardWinner")
	assert_true(GameManager.report_result(GameManager.Difficulty.HARD, 45.0, true), "HardWinner Hard completion must save")
	assert_true(GameManager.report_result(GameManager.Difficulty.BOSS, 3.0, false), "HardWinner 3s Boss death must save under key 3")
	assert_eq(GameManager.get_best_summary("HardWinner"), "BEST  HARD  -  COMPLETED", "Incomplete 3s Boss death must NOT overwrite Hard COMPLETED best summary")

	GameManager.set_player_name("BossRookie")
	assert_true(GameManager.report_result(GameManager.Difficulty.BOSS, 3.0, false), "BossRookie 3s Boss Phase 1 run must save")
	assert_eq(GameManager.get_best_summary("BossRookie"), "BEST  BOSS  -  PHASE 1/8 (3.0s)", "BossRookie summary must format Phase 1/8 (3.0s)")

	GameManager.set_player_name("BossChamp")
	assert_true(GameManager.report_result(GameManager.Difficulty.BOSS, 120.0, true), "BossChamp 120s Boss completion must save")
	assert_eq(GameManager.get_best_summary("BossChamp"), "BEST  BOSS  -  COMPLETED (8/8)", "BossChamp summary must format COMPLETED (8/8)")

	var global_board: Array[Dictionary] = GameManager.get_leaderboard(-1)
	assert_eq(global_board.size(), 3, "Global leaderboard must list all 3 players")
	assert_eq(str(global_board[0].get("key", "")), "bosschamp", "Completed Boss (8/8) must rank #1 globally")
	assert_eq(str(global_board[1].get("key", "")), "hardwinner", "Completed Hard must rank #2 above incomplete 3s Boss Phase 1")
	assert_eq(str(global_board[2].get("key", "")), "bossrookie", "Incomplete 3s Boss Phase 1 must rank #3 below Completed Hard")

	# FilterBossButton (3) in RecordsPanel
	GameManager.set_player_name("HardWinner")
	GameManager.set_state(GameManager.State.MENU)
	menu_after_boss.name_edit.text = "HardWinner"
	menu_after_boss._on_records_pressed()
	assert_true(menu_after_boss.records_panel.visible, "RecordsPanel must open")
	assert_true(menu_after_boss.filter_boss_button != null, "FilterBossButton must exist")
	assert_true(menu_after_boss.records_boss_label != null, "RecordsBossLabel must exist")
	assert_true(menu_after_boss.records_boss_label.text.find("Phase 1/8 (3.0s)") != -1, "RecordsBossLabel must display HardWinner's Boss phase score")

	menu_after_boss.filter_boss_button.pressed.emit()
	assert_eq(menu_after_boss.leaderboard_filter, GameManager.Difficulty.BOSS, "FilterBossButton must set filter to BOSS (3)")
	var boss_board: Array[Dictionary] = GameManager.get_leaderboard(GameManager.Difficulty.BOSS)
	assert_eq(boss_board.size(), 3, "Boss leaderboard must list all 3 Boss players")
	assert_eq(str(boss_board[0].get("key", "")), "bosschamp", "Boss filter #1 must be BossChamp")
	assert_eq(menu_after_boss.leaderboard_list.get_child_count(), 3, "RecordsPanel Boss filter must render 3 Boss rows")
	_assert_subtree_monochrome_and_primitive(menu_after_boss.records_panel)

	# Column_3 (BOSS MODE RANKING) in SpectatorRankingView
	GameManager.set_test_screen_count_override(2)
	assert_true(GameManager.is_spectator_window_active(), "Spectator window must open on 2 screens")
	var spec_view: Control = GameManager.spectator_view
	assert_true(spec_view != null, "SpectatorRankingView must exist")
	var boss_col_panel: PanelContainer = spec_view.columns_grid.get_node_or_null("Column_3") as PanelContainer
	assert_true(boss_col_panel != null, "SpectatorRankingView must contain Column_3")
	var boss_col_header: Label = spec_view._column_headers.get(3) as Label
	assert_true(boss_col_header != null, "Column_3 header must exist")
	assert_eq(boss_col_header.text, "BOSS MODE RANKING", "Column_3 header must be BOSS MODE RANKING")
	var boss_col_list: VBoxContainer = spec_view._column_lists.get(3) as VBoxContainer
	assert_true(boss_col_list != null and boss_col_list.get_child_count() == 3, "Column_3 must list 3 Boss players")

	GameManager.start_level(GameManager.Difficulty.BOSS)
	GameManager.report_live_telemetry(62.5, 120.0, 2, 3)
	assert_true(boss_col_panel.visible, "Column_3 must be visible while playing Boss Mode")
	assert_true(spec_view.status_label.text.find("LIVE BOSS: PHASE 5/8") != -1, "Spectator status must display LIVE BOSS: PHASE 5/8")

	GameManager.spectator_override_mode = 0
	GameManager.set_test_screen_count_override(-1)
	GameManager.set_state(GameManager.State.MENU)
	GameManager.set_difficulty(backup_diff)
	GameManager.save_data = backup_save
	GameManager.save_game()


func test_boss_level_8_phases_jsab_acting_healing_and_monochrome_visuals() -> void:
	var backup_save: SaveData = GameManager.save_data
	var backup_diff: int = GameManager.selected_difficulty
	GameManager.save_data = SaveData.new()
	GameManager.set_player_name("BossTester")

	# Verify Boss Mode 0.78x player scale isolation vs normal Level 1.0x scale
	var normal_level: Node2D = _spawn(LEVEL_SCENE) as Node2D
	var normal_player: CharacterBody2D = normal_level.get_node_or_null("Player") as CharacterBody2D
	assert_true(normal_player != null, "Normal Level player must exist")
	assert_true(normal_player.scale.is_equal_approx(Vector2.ONE), "Normal Level must keep player.scale == Vector2.ONE")

	var boss_level: Node2D = _spawn(BOSS_LEVEL_SCENE) as Node2D
	var boss_container: Node2D = boss_level.get_node_or_null("BossContainer") as Node2D
	var beam_container: Node2D = boss_level.get_node_or_null("BeamContainer") as Node2D
	var hazard_layer: Node2D = boss_level.get_node_or_null("BossHazardLayer") as Node2D
	var boss: Area2D = boss_level.get_node_or_null("BossContainer/Boss") as Area2D
	var player: CharacterBody2D = boss_level.get_node_or_null("Player") as CharacterBody2D
	var complete_panel: Control = boss_level.get_node_or_null("HUD/HUDRoot/LevelCompletePanel") as Control
	var hud: CanvasLayer = boss_level.get_node_or_null("HUD") as CanvasLayer

	assert_true(boss_container != null and beam_container != null and hazard_layer != null and boss != null and player != null, "BossLevel nodes must exist")
	assert_gt(beam_container.get_index(), boss_container.get_index(), "BossContainer must precede BeamContainer so _clear_hazards never frees Boss")
	assert_true(boss_level.boss_hex_grid != null and boss_level.boss_hex_grid.get_parent() == hazard_layer, "BossHexGrid must live in BossHazardLayer outside BeamContainer")
	assert_true(boss_level.boss_bullet_manager != null and boss_level.boss_bullet_manager.get_parent() == hazard_layer, "BossBulletManager must live in BossHazardLayer outside BeamContainer")
	assert_eq(boss_level.difficulty_mode, GameManager.Difficulty.BOSS, "BossLevel difficulty_mode must be BOSS (3)")
	assert_eq(boss_level.level_duration, 120.0, "BossLevel duration must be 120.0s")
	assert_true(player.scale.is_equal_approx(Vector2(0.78, 0.78)), "BossLevel must set player.scale to Vector2(0.78, 0.78)")
	assert_eq(float(boss.BODY_RADIUS), 30.0, "Boss BODY_RADIUS must be 30.0")
	assert_eq(float(boss.HAND_RADIUS), 19.0, "Boss HAND_RADIUS must be 19.0")
	assert_eq((boss.body_collision.shape as CircleShape2D).radius, 30.0, "Boss body CircleShape2D radius must be 30.0")
	assert_eq((boss.left_hand_collision.shape as CircleShape2D).radius, 19.0, "Boss left hand CircleShape2D radius must be 19.0")
	assert_eq((boss.right_hand_collision.shape as CircleShape2D).radius, 19.0, "Boss right hand CircleShape2D radius must be 19.0")
	assert_true(hud.boss_phase_label != null and hud.boss_phase_label.visible, "Boss HUD phase label must be visible")
	assert_eq(hud.boss_phase_label.text, "PHASE 1 / 8", "Boss HUD must start at PHASE 1 / 8")
	assert_eq(hud.controls_hint_label.modulate.a, 1.0, "ControlsHintLabel alpha must be 1.0 in Phase 1")
	assert_eq(boss.face_rig.z_index, 2, "Boss FaceRig z_index must be 2 so eyes/mouth stay visible over beams and walls")

	_assert_subtree_monochrome_and_primitive(boss_level)
	_assert_no_text_nodes(boss)

	# Phase 1 acting state, form, always-active hitboxes & live micro-reactions (shield_blocked -> flinch, damaged -> laugh)
	assert_eq(boss.current_phase, 1, "Boss must start in Phase 1")
	assert_eq(int(boss.acting_state), int(boss.ActingState.COCKY_CONDUCTOR), "Phase 1 acting_state must be COCKY_CONDUCTOR")
	assert_eq(int(boss.boss_form), int(boss.BossForm.CONDUCTOR), "Phase 1 boss_form must be CONDUCTOR")
	assert_false(bool(boss._lunge_active), "Boss must not be lunging at spawn")
	assert_true(bool(boss.is_body_hazardous), "Boss body must be hazardous in active Phase 1 even when idle")
	assert_true(bool(boss.is_left_hand_hazardous), "Boss left hand must be hazardous in active Phase 1 even when idle")
	assert_true(bool(boss.is_right_hand_hazardous), "Boss right hand must be hazardous in active Phase 1 even when idle")
	assert_true(bool(boss.is_hand_hazardous), "Boss is_hand_hazardous must be true in active Phase 1")
	assert_false(boss.body_collision.disabled, "Boss body CollisionShape2D must be enabled in active Phase 1")
	assert_false(boss.left_hand_collision.disabled, "Boss left hand CollisionShape2D must be enabled in active Phase 1")
	assert_false(boss.right_hand_collision.disabled, "Boss right hand CollisionShape2D must be enabled in active Phase 1")

	# Verify placing player onto Boss body, left_hand, and right_hand triggers shield_blocked when shielding and take_damage(1) when unshielded
	var shield_block_count: Array[int] = [0]
	player.shield_blocked.connect(func() -> void: shield_block_count[0] += 1)
	var contact_targets: Array[Dictionary] = [
		{"label": "body", "pos": boss.global_position},
		{"label": "left_hand", "pos": boss.left_hand.global_position},
		{"label": "right_hand", "pos": boss.right_hand.global_position},
	]
	for idx_c: int in range(contact_targets.size()):
		var c_info: Dictionary = contact_targets[idx_c]
		var c_label: String = String(c_info["label"])
		var c_pos: Vector2 = Vector2(c_info["pos"])

		player.set_shield_held(true)
		player.shield_energy = player.SHIELD_MAX_ENERGY
		player.shield_exhausted = false
		player.shield_block_feedback_timer = 0.0
		player._physics_process(0.016)
		boss._flinch_timer = 0.0
		player.global_position = c_pos
		boss.simulate_boss(0.0, boss_level.elapsed_time, Vector2(1152.0, 648.0), player)
		assert_eq(shield_block_count[0], idx_c + 1, "Shielded contact with Boss %s must emit shield_blocked" % c_label)
		assert_gt(float(boss._flinch_timer), 0.0, "Shielded contact with Boss %s must trigger Boss flinch reaction" % c_label)

		player.set_shield_held(false)
		player._physics_process(0.016)
		player.current_hp = 3
		player.hit_invincibility_timer = 0.0
		boss._laugh_timer = 0.0
		player.global_position = c_pos
		boss.simulate_boss(0.0, boss_level.elapsed_time, Vector2(1152.0, 648.0), player)
		assert_eq(player.current_hp, 2, "Unshielded contact with Boss %s must deal 1 contact damage" % c_label)
		assert_gt(float(boss._laugh_timer), 0.0, "Unshielded contact with Boss %s must trigger Boss laugh reaction" % c_label)

	# Reset player and park at old (100, 580) corner to prove AFK safe-corner exploit is eliminated in Act 1
	player.global_position = Vector2(100.0, 580.0)
	player.heal(1, true)
	player.hit_invincibility_timer = 0.0
	player.hit_flash_timer = 0.0
	boss._flinch_timer = 0.0
	boss._laugh_timer = 0.0
	boss_level.total_parries = 0
	boss.total_parries = 0
	boss_level._parry_cooldown = 0.0

	var seen_states: Dictionary = {int(boss.acting_state): true}
	var seen_forms: Dictionary = {int(boss.boss_form): true}
	var phase_transitions_checked: Dictionary = {1: true}
	var phase_heals_verified: Dictionary = {}
	var seen_hand_actions: Dictionary = {}
	var afk_corner_hits_act1: int = 0
	var bar0_active_hazards: int = 0
	var bar8_dropout_active_hazards: int = 0
	var beat36_drop_active_hazards: int = 0
	var bar39_silence_active_hazards: int = 0
	var beat158_supernova_bullets: int = 0
	var wall_slam_signals: Array[int] = [0]
	var max_wall_slam_miss_dist: Array[float] = [0.0]
	var verified_phase4_tether: bool = false

	boss.boss_wall_slammed.connect(func(wall_pos: Vector2, inward_normal: Vector2, _strength: float) -> void:
		wall_slam_signals[0] += 1
		var expected_contact: Vector2 = wall_pos + inward_normal * float(boss.HAND_RADIUS)
		var hand_dist: float = minf(
			expected_contact.distance_to(boss.left_hand.global_position),
			expected_contact.distance_to(boss.right_hand.global_position)
		)
		max_wall_slam_miss_dist[0] = maxf(max_wall_slam_miss_dist[0], hand_dist)
		assert_true(hand_dist <= 28.0, "Wall slam impact #%d contact-to-hand distance %.2fpx must be <= 28.0px" % [wall_slam_signals[0], hand_dist])
	)

	# Step 0s -> 120s in 0.5s outer steps (4x 0.125s substeps)
	for step: int in range(1, 241):
		var is_pre_phase_boundary: bool = step in [30, 60, 90, 120, 150, 180, 210]
		for sub: int in range(4):
			# Right before the final substep that crosses each 15.0s phase boundary (14.875->15.0, 29.875->30.0, ...),
			# arm player at HP=1 with exhausted shield and invincibility so the phase transition heal is tested cleanly.
			if is_pre_phase_boundary and sub == 3:
				player.current_hp = 1
				player.shield_energy = 0.20
				player.shield_exhausted = true
				player.hit_invincibility_timer = 1.0
			elif step <= 29:
				# In Phase 1, keep unshielded passive player vulnerable at (100, 580) to prove AFK corner takes damage
				player.global_position = Vector2(100.0, 580.0)
				player.set_shield_held(false)
				player.hit_invincibility_timer = 0.0
			else:
				# After Phase 1 AFK corner proof, keep probe player alive with invulnerability between heal probes
				player.hit_invincibility_timer = 1.0

			boss_level.simulate_physics(0.125)

			if step <= 29 and player.current_hp < 3:
				afk_corner_hits_act1 += 1
				player.current_hp = 3
				player.hit_invincibility_timer = 0.0

			if boss_level.is_level_running:
				seen_states[int(boss.acting_state)] = true
				seen_forms[int(boss.boss_form)] = true
				seen_hand_actions[int(boss.get_hand_action(true))] = true
				seen_hand_actions[int(boss.get_hand_action(false))] = true
				var t_now: float = boss_level.elapsed_time
				if t_now < 1.8:
					bar0_active_hazards += _count_active_boss_hazards(boss_level)
					assert_eq(int(boss.total_wall_slams), 0, "Bar 0 intro (t < 1.8s) must trigger 0 wall slams")
				elif t_now >= 15.0 and t_now <= 16.75:
					bar8_dropout_active_hazards += _count_active_boss_hazards(boss_level)
				elif absf(t_now - 17.0) < 0.01:
					beat36_drop_active_hazards = _count_active_boss_hazards(boss_level)
				elif t_now >= 73.125 and t_now <= 74.001:
					bar39_silence_active_hazards += _count_active_boss_hazards(boss_level)
					assert_eq(SoundManager.get_boss_beat_intensity(t_now), 0.0, "Bar 39 silence (%.3fs) must have 0.0 beat intensity" % t_now)
				elif absf(t_now - 74.125) < 0.01:
					beat158_supernova_bullets = boss_level.boss_bullet_manager.get_active_count()

		if boss_level.is_level_running:
			phase_transitions_checked[int(boss.current_phase)] = true
			_assert_subtree_monochrome_and_primitive(boss_level)
			if step < 30:
				assert_eq(hud.controls_hint_label.modulate.a, 1.0, "ControlsHintLabel alpha must stay 1.0 in Phase 1 (step %d)" % step)
			else:
				assert_true(hud.controls_hint_label.modulate.a <= 0.20, "ControlsHintLabel alpha must dim to <= 0.20 in Phases 2-8 (step %d)" % step)

		if step == 3:
			assert_eq(bar0_active_hazards, 0, "Bar 0 intro (t < 1.8s) must have 0 active lethal hazards")
		elif step == 29:
			assert_gt(afk_corner_hits_act1, 0, "Unshielded passive player parked at Vector2(100, 580) must take damage during Phase 1 (AFK corner eliminated)")
		elif step == 30:
			assert_eq(boss.current_phase, 2, "t=15s must be Phase 2")
			assert_eq(int(boss.acting_state), int(boss.ActingState.FROZEN_DOUBLE_TAKE), "Phase 2 must enter FROZEN_DOUBLE_TAKE")
			assert_true(bool(boss.is_body_hazardous) and bool(boss.is_left_hand_hazardous) and bool(boss.is_right_hand_hazardous), "Boss body and hands must remain hazardous in Phase 2")
			assert_eq(player.current_hp, 2, "Phase 2 transition must heal +1 HP (1 -> 2)")
			assert_true(player.shield_exhausted, "Standard Phase 2 heal(1, false) must preserve shield exhaustion")
			phase_heals_verified[2] = true
		elif step == 34:
			assert_eq(bar8_dropout_active_hazards, 0, "Phase 2 Bar 8 dropout (15.0..16.75s) must have 0 active lethal hazards")
			assert_true(beat36_drop_active_hazards >= 2, "Phase 2 Beat 36 (16.875s) hard drop must activate twin pistons + shockwave ring")
		elif step == 60:
			assert_eq(boss.current_phase, 3, "t=30s must be Phase 3")
			assert_eq(int(boss.acting_state), int(boss.ActingState.FLOOR_SLAM_TANTRUM), "Phase 3 must enter FLOOR_SLAM_TANTRUM")
			assert_eq(player.current_hp, 2, "Phase 3 transition must heal +1 HP (1 -> 2)")
			assert_true(player.shield_exhausted, "Standard Phase 3 heal(1, false) must preserve shield exhaustion")
			phase_heals_verified[3] = true
		elif step == 90:
			assert_eq(boss.current_phase, 4, "t=45s must be Phase 4")
			assert_eq(int(boss.acting_state), int(boss.ActingState.ACCUSING_POINT), "Phase 4 must enter ACCUSING_POINT")
			assert_eq(int(boss.boss_form), int(boss.BossForm.WHEEL_CORE), "Phase 4 must use WHEEL_CORE form")
			assert_eq(player.current_hp, 2, "Phase 4 transition must heal +1 HP (1 -> 2)")
			assert_true(player.shield_exhausted, "Standard Phase 4 heal(1, false) must preserve shield exhaustion")
			phase_heals_verified[4] = true
		elif step == 96:
			assert_true(bool(boss._tether_active), "Phase 4 High-Voltage Clothesline (_tether_active) must be active at t=48.0s")
			var tether_pt: Vector2 = boss.left_hand.global_position.lerp(boss.right_hand.global_position, 0.22)
			assert_gt(tether_pt.distance_to(boss.global_position), 80.0, "Clothesline probe point must be clear of Boss body")
			assert_gt(tether_pt.distance_to(boss.left_hand.global_position), 80.0, "Clothesline probe point must be clear of Left Hand")
			assert_gt(tether_pt.distance_to(boss.right_hand.global_position), 80.0, "Clothesline probe point must be clear of Right Hand")

			var tether_dir: Vector2 = (boss.right_hand.global_position - boss.left_hand.global_position).normalized()
			var tether_perp: Vector2 = Vector2(-tether_dir.y, tether_dir.x)
			player.current_hp = 3
			player.set_shield_held(false)
			player._physics_process(0.016)
			player.hit_invincibility_timer = 0.0
			player.global_position = tether_pt + tether_perp * 22.0
			boss.simulate_boss(0.0, boss_level.elapsed_time, Vector2(1152.0, 648.0), player)
			assert_eq(player.current_hp, 3, "22px outside Phase 4 Clothesline must NOT deal damage")

			var blocks_before_tether: int = shield_block_count[0]
			player.set_shield_held(true)
			player.shield_energy = player.SHIELD_MAX_ENERGY
			player.shield_exhausted = false
			player.shield_block_feedback_timer = 0.0
			player._physics_process(0.016)
			player.global_position = tether_pt
			boss.simulate_boss(0.0, boss_level.elapsed_time, Vector2(1152.0, 648.0), player)
			assert_eq(shield_block_count[0], blocks_before_tether + 1, "Shielded overlap with Phase 4 Clothesline must emit shield_blocked")

			player.set_shield_held(false)
			player._physics_process(0.016)
			player.hit_invincibility_timer = 0.0
			player.global_position = tether_pt
			boss.simulate_boss(0.0, boss_level.elapsed_time, Vector2(1152.0, 648.0), player)
			assert_eq(player.current_hp, 2, "Unshielded overlap with Phase 4 Clothesline must deal 1 damage")

			player.global_position = Vector2(100.0, 580.0)
			player.heal(1, true)
			player.hit_invincibility_timer = 1.0
			verified_phase4_tether = true
		elif step == 120:
			assert_eq(boss.current_phase, 5, "t=60s must be Phase 5")
			assert_eq(int(boss.acting_state), int(boss.ActingState.FAKE_OUT_COLLAPSE), "Phase 5 must enter FAKE_OUT_COLLAPSE")
			assert_eq(int(boss.boss_form), int(boss.BossForm.MARIONETTE), "Phase 5 must enter MARIONETTE form")
			assert_false(bool(boss.is_body_hazardous), "Collapsed Boss head must have is_body_hazardous == false during FAKE_OUT_COLLAPSE")
			assert_true(boss.body_collision.disabled, "Collapsed Boss body CollisionShape2D must be disabled during FAKE_OUT_COLLAPSE")
			assert_false(bool(boss.is_left_hand_hazardous) or bool(boss.is_right_hand_hazardous), "Hands must stay dormant before beat 8 of FAKE_OUT_COLLAPSE")
			assert_eq(player.current_hp, 2, "Phase 5 must heal player from 1 HP to 2 HP")
			assert_eq(player.shield_energy, player.SHIELD_MAX_ENERGY, "Phase 5 heal must recharge shield to 100%")
			assert_false(player.shield_exhausted, "Phase 5 heal must clear shield_exhausted")
			assert_eq(hud.boss_phase_label.text, "PHASE 5 / 8", "HUD must display PHASE 5 / 8")
			phase_heals_verified[5] = true
		elif step == 121:
			# Verify live Boss micro-reactions are suppressed during FAKE_OUT_COLLAPSE
			assert_eq(float(boss._flinch_timer), 0.0, "Boss flinch timer must be 0 during FAKE_OUT_COLLAPSE")
			assert_eq(float(boss._laugh_timer), 0.0, "Boss laugh timer must be 0 during FAKE_OUT_COLLAPSE")
			player.shield_blocked.emit()
			player.damaged.emit(1)
			assert_eq(float(boss._flinch_timer), 0.0, "shield_blocked must be suppressed during FAKE_OUT_COLLAPSE")
			assert_eq(float(boss._laugh_timer), 0.0, "damaged must be suppressed during FAKE_OUT_COLLAPSE")
		elif step == 128:
			assert_false(bool(boss.is_body_hazardous), "Collapsed Boss head must remain non-hazardous at beat >= 8 of Phase 5")
			assert_true(bool(boss.is_left_hand_hazardous) and bool(boss.is_right_hand_hazardous), "Possessed hands must wake up hazardous by beat 8 of Phase 5")
			assert_false(boss.left_hand_collision.disabled or boss.right_hand_collision.disabled, "Possessed hand CollisionShape2Ds must be enabled by beat 8 of Phase 5")
		elif step == 149:
			assert_eq(bar39_silence_active_hazards, 0, "Phase 5 Bar 39 digital silence (73.125..74.0s) must have 0 active lethal hazards")
			assert_true(beat158_supernova_bullets >= 24, "Phase 5 Beat 158 (74.0625s) supernova must detonate >= 24 radial bullets")
		elif step == 150:
			assert_eq(boss.current_phase, 6, "t=75s must be Phase 6")
			assert_eq(int(boss.acting_state), int(boss.ActingState.HOLLOW_REBIRTH), "Phase 6 must enter HOLLOW_REBIRTH")
			assert_eq(int(boss.boss_form), int(boss.BossForm.TRIPLE_CANNON), "Phase 6 must enter TRIPLE_CANNON form")
			assert_true(bool(boss.is_body_hazardous), "Boss body must be hazardous in Phase 6")
			assert_false(bool(boss.is_left_hand_hazardous) or bool(boss.is_right_hand_hazardous), "Hands must retract into Triple-Cannon body in Phase 6")
			assert_eq(player.current_hp, 2, "Phase 6 transition must heal +1 HP (1 -> 2)")
			assert_true(player.shield_exhausted, "Standard Phase 6 heal(1, false) must preserve shield exhaustion")
			phase_heals_verified[6] = true
		elif step == 180:
			assert_eq(boss.current_phase, 7, "t=90s must be Phase 7")
			assert_eq(int(boss.acting_state), int(boss.ActingState.EXHAUSTED_PANTING), "Phase 7 must enter EXHAUSTED_PANTING")
			assert_eq(int(boss.boss_form), int(boss.BossForm.STOMP_COLOSSUS), "Phase 7 must enter STOMP_COLOSSUS form")
			assert_eq(player.current_hp, 2, "Phase 7 must heal player from 1 HP to 2 HP")
			assert_eq(player.shield_energy, player.SHIELD_MAX_ENERGY, "Phase 7 heal must recharge shield to 100%")
			assert_false(player.shield_exhausted, "Phase 7 heal must clear shield_exhausted")
			player.heal(1, true)
			assert_eq(player.current_hp, 3, "player.heal must clamp at MAX_HP (3)")
			phase_heals_verified[7] = true
		elif step == 210:
			assert_eq(boss.current_phase, 8, "t=105s must be Phase 8")
			assert_eq(int(boss.acting_state), int(boss.ActingState.TEMPLE_CLUTCH_PANIC), "Phase 8 must enter TEMPLE_CLUTCH_PANIC")
			assert_eq(int(boss.boss_form), int(boss.BossForm.OVERDRIVE_PANIC), "Phase 8 must enter OVERDRIVE_PANIC form")
			assert_eq(player.current_hp, 2, "Phase 8 transition must heal +1 HP (1 -> 2)")
			assert_true(player.shield_exhausted, "Standard Phase 8 heal(1, false) must preserve shield exhaustion")
			phase_heals_verified[8] = true
		elif step == 237:
			assert_eq(int(boss.acting_state), int(boss.ActingState.SILENT_SHATTER), "Beat 252 (>=118.125s) must enter SILENT_SHATTER")
			assert_eq(int(boss.boss_form), int(boss.BossForm.SHATTERED), "Beat 252 (>=118.125s) must enter SHATTERED form")
			assert_false(bool(boss.is_body_hazardous) or bool(boss.is_left_hand_hazardous) or bool(boss.is_right_hand_hazardous), "SILENT_SHATTER must disable Boss and hand hazard flags")
			assert_eq(_count_active_boss_hazards(boss_level), 0, "SILENT_SHATTER at Beat 252 must clear all active hazards")
			assert_eq(boss_level.boss_hex_grid.get_active_tile_count(), 0, "SILENT_SHATTER must clear BossHexGrid tiles")
			assert_eq(boss_level.boss_bullet_manager.get_active_count(), 0, "SILENT_SHATTER must clear BossBulletManager bullets")

	assert_eq(int(boss_level.enemies_spawned), 0, "Boss Mode must spawn 0 regular enemy.gd instances")
	assert_true(int(boss_level.boss_choreographer.glitch_waves_spawned) >= 2, "Phase 8 must spawn >= 2 Chromatic Glitch Waves")
	assert_true(int(boss.total_wall_slams) >= 16, "Border wall slams must trigger >= 16 times across Phases 2, 7, 8 (got %d)" % int(boss.total_wall_slams))
	assert_true(wall_slam_signals[0] >= 16, "boss_wall_slammed signal must fire >= 16 times across phases (got %d)" % wall_slam_signals[0])
	assert_true(max_wall_slam_miss_dist[0] <= 28.0, "Every wall slam impact must have hand within 28.0px of wall contact (max %.2fpx)" % max_wall_slam_miss_dist[0])
	assert_true(verified_phase4_tether, "Phase 4 Clothesline tether contact verification must execute")

	for expected_hazard: StringName in [
		&"sweeping_beam",
		&"shockwave_ring",
		&"tidal_wave",
		&"piston_wall",
		&"hex_grid",
		&"gravity_well",
		&"spike_ring",
		&"border_cage",
		&"ceiling_spike",
		&"beat_minion",
		&"minion_thread_spider",
		&"minion_orbit_specter",
		&"minion_border_snapper",
		&"glitch_wave",
		&"filling_circle",
		&"boss_bullets",
	]:
		assert_true(boss_level.boss_choreographer.seen_hazard_kinds.has(expected_hazard), "Boss choreography must fire JSAB hazard primitive '%s'" % String(expected_hazard))

	for p: int in range(1, 9):
		assert_true(phase_transitions_checked.has(p), "Boss must visit Phase %d/8" % p)
	for hp_phase: int in range(2, 9):
		assert_true(phase_heals_verified.has(hp_phase), "Phase %d transition heal must be verified" % hp_phase)
	for st: int in [
		int(boss.ActingState.COCKY_CONDUCTOR),
		int(boss.ActingState.FROZEN_DOUBLE_TAKE),
		int(boss.ActingState.FLOOR_SLAM_TANTRUM),
		int(boss.ActingState.ACCUSING_POINT),
		int(boss.ActingState.FAKE_OUT_COLLAPSE),
		int(boss.ActingState.HOLLOW_REBIRTH),
		int(boss.ActingState.EXHAUSTED_PANTING),
		int(boss.ActingState.TEMPLE_CLUTCH_PANIC),
		int(boss.ActingState.SILENT_SHATTER),
	]:
		assert_true(seen_states.has(st), "Boss must transition through ActingState %d" % st)
	for fm: int in [
		int(boss.BossForm.CONDUCTOR),
		int(boss.BossForm.SPIKE_ROLL),
		int(boss.BossForm.WHEEL_CORE),
		int(boss.BossForm.MARIONETTE),
		int(boss.BossForm.TRIPLE_CANNON),
		int(boss.BossForm.STOMP_COLOSSUS),
		int(boss.BossForm.OVERDRIVE_PANIC),
		int(boss.BossForm.SHATTERED),
	]:
		assert_true(seen_forms.has(fm) or boss_level.boss_choreographer.seen_forms.has(fm), "Boss must morph through BossForm %d" % fm)

	assert_false(boss_level.is_level_running, "BossLevel must complete at 120.0s")
	assert_true(complete_panel.visible, "LevelCompletePanel must display at 120.0s")
	assert_true(bool(boss._shattered), "Boss must shatter on level completion")

	var boss_rec: Dictionary = GameManager.save_data.get_record(GameManager.Difficulty.BOSS)
	assert_false(boss_rec.is_empty(), "Boss completion must save a record under difficulty key 3")
	assert_true(bool(boss_rec.get("completed", false)), "Boss record key 3 must be marked completed=true")
	assert_true(float(boss_rec.get("time", 0.0)) >= 120.0, "Boss record key 3 time must be >= 120.0s")

	# Retry must reset Boss, preserve persistent managers, restore 0.78x scale & 3 HP, and re-arm Phase 2..8 heals
	boss_level._on_retry_pressed()
	assert_true(boss_level.is_level_running, "Retry must restart BossLevel")
	assert_eq(boss_level.elapsed_time, 0.0, "Retry must reset elapsed_time")
	assert_eq(boss.current_phase, 1, "Retry must reset Boss to Phase 1")
	assert_eq(int(boss.acting_state), int(boss.ActingState.COCKY_CONDUCTOR), "Retry must reset Boss ActingState to COCKY_CONDUCTOR")
	assert_eq(int(boss.boss_form), int(boss.BossForm.CONDUCTOR), "Retry must reset BossForm to CONDUCTOR")
	assert_false(bool(boss._shattered), "Retry must clear Boss shattered state")
	assert_eq(int(boss.total_wall_slams), 0, "Retry must reset total_wall_slams to 0")
	assert_eq(int(boss.total_parries), 0, "Retry must reset boss.total_parries to 0")
	assert_eq(int(boss_level.total_parries), 0, "Retry must reset boss_level.total_parries to 0")
	assert_true(is_instance_valid(boss_level.boss_hex_grid) and boss_level.boss_hex_grid.get_active_tile_count() == 0, "Retry must clear BossHexGrid without freeing it")
	assert_true(is_instance_valid(boss_level.boss_bullet_manager) and boss_level.boss_bullet_manager.get_active_count() == 0, "Retry must clear BossBulletManager without freeing it")
	assert_eq(int(boss_level._last_healed_phase), 1, "Retry must reset _last_healed_phase to 1")
	assert_eq(hud.controls_hint_label.modulate.a, 1.0, "Retry must restore ControlsHintLabel alpha to 1.0 in Phase 1")
	assert_true(player.scale.is_equal_approx(Vector2(0.78, 0.78)), "Retry must preserve Boss Mode player.scale == Vector2(0.78, 0.78)")
	assert_eq(player.current_hp, 3, "Retry must restore player to 3 HP")

	player.global_position = Vector2(100.0, 580.0)
	for step_retry: int in range(1, 121):
		player.hit_invincibility_timer = 1.0
		if step_retry == 29 or step_retry == 119:
			player.current_hp = 1
		boss_level.simulate_physics(0.5)
		if step_retry == 30:
			assert_eq(player.current_hp, 2, "Re-armed Phase 2 heal must trigger again after Retry")
	assert_eq(player.current_hp, 2, "Re-armed Phase 5 heal must trigger again after Retry")

	GameManager.set_state(GameManager.State.MENU)
	GameManager.set_difficulty(backup_diff)
	GameManager.save_data = backup_save
	GameManager.save_game()


func test_boss_parry_glitch_wave_and_gravity_well() -> void:
	var backup_save: SaveData = GameManager.save_data
	var backup_diff: int = GameManager.selected_difficulty
	GameManager.save_data = SaveData.new()

	var boss_level: Node2D = _spawn(BOSS_LEVEL_SCENE) as Node2D
	var beam_container: Node2D = boss_level.get_node_or_null("BeamContainer") as Node2D
	var boss: Area2D = boss_level.get_node_or_null("BossContainer/Boss") as Area2D
	var player: CharacterBody2D = boss_level.get_node_or_null("Player") as CharacterBody2D
	assert_true(beam_container != null and boss != null and player != null, "BossLevel nodes must exist for focused unit tests")

	# 1. Timed fist-shield parry on a parryable shockwave ring + BossGlitchWave purge_by_parry()
	boss_level.elapsed_time = 2.0
	player.global_position = Vector2(576.0, 420.0)
	player.shield_energy = 0.50
	player.shield_exhausted = false
	player.shield_block_feedback_timer = 0.0
	player.set_shield_held(true)
	player._physics_process(0.016)
	assert_true(player.is_shielding, "Player must raise shield before timed parry")

	var crack_before: float = float(boss._crack_intensity)
	var energy_before: float = player.shield_energy
	var ring: BossShockwaveRing = BossShockwaveRing.new()
	beam_container.add_child(ring)
	ring.configure_ring(player.global_position, 10.0, 200.0, 32.0, 0.01, 1.0, true)
	ring.simulate_physics(0.02, player)
	_assert_subtree_monochrome_and_primitive(ring)

	assert_eq(int(boss_level.total_parries), 1, "Timed shield block within 0.32s must increment boss_level.total_parries")
	assert_eq(int(boss.total_parries), 1, "Timed shield block within 0.32s must increment boss.total_parries")
	assert_gt(player.shield_energy, energy_before, "Timed parry must refund player.shield_energy")
	assert_gt(float(boss._crack_intensity), crack_before, "Timed parry must increase Boss crack intensity")
	ring.queue_free()

	# Parrying a BossGlitchWave must call purge_by_parry() and enter SHATTER_PURGE (is_hazard_active = false)
	boss_level._parry_cooldown = 0.0
	boss_level.elapsed_time = 3.0
	player.set_shield_held(false)
	player._physics_process(0.016)
	player.shield_energy = 0.55
	player.shield_block_feedback_timer = 0.0
	player.set_shield_held(true)
	player._physics_process(0.016)

	var glitch_wave: BossGlitchWave = BossGlitchWave.new()
	beam_container.add_child(glitch_wave)
	assert_eq(glitch_wave.get_child_count(), 0, "BossGlitchWave must use pure _draw() with 0 child nodes")
	glitch_wave.configure(Vector2(1152.0, 648.0), Vector2.RIGHT, 0.01, 1.60, 80.0, 0.5, 148.0, 0.0, true)
	glitch_wave.simulate_physics(0.02, null)
	assert_true(glitch_wave.is_hazard_active, "BossGlitchWave must become active after warning_time")
	# Place player on the top wing of the glitch wave crest (outside the center safe gap)
	player.global_position = Vector2(glitch_wave._current_sweep, 80.0)
	glitch_wave.simulate_physics(0.016, player)

	assert_eq(int(boss_level.total_parries), 2, "Parrying BossGlitchWave must increment boss_level.total_parries to 2")
	assert_eq(int(boss.total_parries), 2, "Parrying BossGlitchWave must increment boss.total_parries to 2")
	assert_false(glitch_wave.is_hazard_active, "purge_by_parry() must immediately deactivate BossGlitchWave hazard")
	assert_eq(int(glitch_wave.current_phase), int(BossGlitchWave.Phase.SHATTER_PURGE), "Parried BossGlitchWave must enter SHATTER_PURGE phase")
	glitch_wave.simulate_physics(0.35, null)
	assert_true(glitch_wave.is_queued_for_deletion(), "Purged BossGlitchWave must self-queue_free after SHATTER_PURGE")
	_assert_subtree_monochrome_and_primitive(boss_level)

	# 2. BossGravityWell pull in both direct (use_target_position = false) and target-position (hand tracking/mouse) modes
	player.set_shield_held(false)
	player._physics_process(0.016)
	var well: BossGravityWell = BossGravityWell.new()
	beam_container.add_child(well)
	var well_origin: Vector2 = Vector2(576.0, 324.0)
	well.configure(well_origin, 24.0, 460.0, 76.0, 145.0, 0.01, 5.0)
	well.simulate_physics(0.02, null)
	well.simulate_physics(0.35, null)
	assert_true(well.is_hazard_active, "BossGravityWell must be active after warning_time")
	_assert_subtree_monochrome_and_primitive(well)

	# WASD / direct mode (use_target_position = false)
	player.release_external_tracking()
	player.use_target_position = false
	player.global_position = Vector2(360.0, 324.0)
	var dist_before_direct: float = player.global_position.distance_to(well_origin)
	boss_level._apply_gravity_well_pull(0.10)
	var dist_after_direct: float = player.global_position.distance_to(well_origin)
	assert_true(dist_after_direct < dist_before_direct, "BossGravityWell must pull player smoothly inward in direct (WASD) mode")
	assert_true(_is_player_within_arena(player.global_position, Vector2(1152.0, 648.0), player.PLAYER_HALF_SIZE), "Direct gravity pull must stay clamped within arena bounds")

	# Hand-tracking / mouse mode (use_target_position = true)
	var hand_anchor: Vector2 = Vector2(360.0, 324.0)
	player.global_position = hand_anchor
	player.set_target_position(hand_anchor, true)
	boss_level._apply_gravity_well_pull(0.10)
	assert_true(player.target_position.distance_to(well_origin) < hand_anchor.distance_to(well_origin), "BossGravityWell must pull player.target_position inward in target-position mode")
	assert_true(player.target_position.distance_to(hand_anchor) <= 76.5, "Target-position gravity pull must remain bounded by max_pull_offset")
	assert_true(_is_player_within_arena(player.target_position, Vector2(1152.0, 648.0), player.PLAYER_HALF_SIZE), "Target-position gravity pull must stay clamped within arena bounds")

	# Near-edge clamp check
	var edge_well: BossGravityWell = BossGravityWell.new()
	beam_container.add_child(edge_well)
	edge_well.configure(Vector2(2.0, 324.0), 24.0, 460.0, 90.0, 220.0, 0.01, 5.0)
	edge_well.simulate_physics(0.40, null)
	player.use_target_position = false
	player.global_position = Vector2(18.0, 324.0)
	boss_level._apply_gravity_well_pull(0.25)
	assert_true(_is_player_within_arena(player.global_position, Vector2(1152.0, 648.0), player.PLAYER_HALF_SIZE), "Gravity pull near border must never pull player outside viewport bounds")

	GameManager.set_state(GameManager.State.MENU)
	GameManager.set_difficulty(backup_diff)
	GameManager.save_data = backup_save
	GameManager.save_game()


func test_boss_intro_animation_safety_and_handoff() -> void:
	var backup_save: SaveData = GameManager.save_data
	var backup_diff: int = GameManager.selected_difficulty
	GameManager.save_data = SaveData.new()

	var boss_level: Node2D = _spawn(BOSS_LEVEL_SCENE) as Node2D
	var boss: Area2D = boss_level.get_node_or_null("BossContainer/Boss") as Area2D
	var player: CharacterBody2D = boss_level.get_node_or_null("Player") as CharacterBody2D
	var intro_top_bar: ColorRect = boss_level.get_node_or_null("HUD/HUDRoot/IntroTopBar") as ColorRect
	var intro_bottom_bar: ColorRect = boss_level.get_node_or_null("HUD/HUDRoot/IntroBottomBar") as ColorRect
	var intro_banner: Control = boss_level.get_node_or_null("HUD/HUDRoot/IntroBanner") as Control
	assert_true(boss != null and player != null, "BossLevel boss and player must exist")
	assert_true(intro_top_bar != null and intro_bottom_bar != null and intro_banner != null, "Boss intro HUD overlays must exist under HUD/HUDRoot")

	boss_level.start_intro(false)
	assert_true(bool(boss_level.is_intro_active), "start_intro(false) must activate boss intro")
	assert_eq(float(boss_level.elapsed_time), 0.0, "Boss intro start must keep elapsed_time at 0.0")
	assert_false(bool(boss.is_body_hazardous), "Boss body must not be hazardous during intro")
	assert_false(bool(boss.is_left_hand_hazardous), "Boss left hand must not be hazardous during intro")
	assert_false(bool(boss.is_right_hand_hazardous), "Boss right hand must not be hazardous during intro")
	assert_false(bool(boss.is_hand_hazardous), "Boss is_hand_hazardous must be false during intro")
	assert_true(boss.body_collision.disabled, "Boss body CollisionShape2D must be disabled during intro")
	assert_true(boss.left_hand_collision.disabled, "Boss left hand CollisionShape2D must be disabled during intro")
	assert_true(boss.right_hand_collision.disabled, "Boss right hand CollisionShape2D must be disabled during intro")

	player.set_shield_held(false)
	player._physics_process(0.016)
	player.current_hp = 3
	player.hit_invincibility_timer = 0.0
	player.global_position = boss.global_position
	boss.simulate_boss(0.016, 1.0, Vector2(1152.0, 648.0), player)
	assert_eq(player.current_hp, 3, "Touching Boss during intro must deal 0 contact damage")

	# Step to t = 0.50s (before Beat 2 drop-in)
	for _i: int in range(10):
		boss_level.simulate_physics(0.05)
	assert_true(bool(boss_level.is_intro_active), "Intro must remain active at 0.50s")
	assert_eq(float(boss_level.elapsed_time), 0.0, "Fight elapsed_time must stay 0.0 at 0.50s")
	assert_true(boss.global_position.y < 0.0, "Boss must remain staged above top edge before Beat 2 drop-in")
	assert_true(intro_top_bar.visible and intro_bottom_bar.visible, "Letterbox bars must be visible during full intro")
	assert_false(intro_banner.visible, "IntroBanner must remain hidden before Beat 2 slam")

	# Step to t = 1.05s (past Beat 2 slam at 0.9375s)
	for _i: int in range(11):
		boss_level.simulate_physics(0.05)
	assert_true(bool(boss_level.is_intro_active), "Intro must remain active at 1.05s")
	assert_eq(float(boss_level.elapsed_time), 0.0, "Fight elapsed_time must stay 0.0 at 1.05s")
	assert_true(boss.global_position.is_equal_approx(Vector2(576.0, 152.0)), "Boss must slam to (576, 152) on Beat 2")
	assert_true(intro_banner.visible, "HUD/HUDRoot/IntroBanner must be visible after Beat 2 slam")

	player.global_position = boss.global_position
	boss.simulate_boss(0.016, 1.0, Vector2(1152.0, 648.0), player)
	assert_eq(player.current_hp, 3, "Touching Boss after Beat 2 slam during intro must still deal 0 contact damage")
	_assert_subtree_monochrome_and_primitive(boss_level)
	_assert_no_text_nodes(boss)

	# Step past 1.875s (to 1.90s) to verify clean completion & hitbox handoff
	for _i: int in range(17):
		boss_level.simulate_physics(0.05)
	assert_false(bool(boss_level.is_intro_active), "Intro must complete cleanly past 1.875s")
	assert_eq(float(boss_level.elapsed_time), 0.0, "elapsed_time must start at 0.0 on the exact frame intro finishes")
	assert_true(boss.global_position.is_equal_approx(Vector2(576.0, 152.0)), "Boss must hand off at (576, 152)")
	assert_true(bool(boss.is_body_hazardous), "Boss body hitbox must re-enable after intro")
	assert_true(bool(boss.is_left_hand_hazardous), "Boss left hand hitbox must re-enable after intro")
	assert_true(bool(boss.is_right_hand_hazardous), "Boss right hand hitbox must re-enable after intro")
	assert_false(boss.body_collision.disabled, "Boss body CollisionShape2D must re-enable after intro")
	assert_false(boss.left_hand_collision.disabled, "Boss left hand CollisionShape2D must re-enable after intro")
	assert_false(boss.right_hand_collision.disabled, "Boss right hand CollisionShape2D must re-enable after intro")

	boss_level.simulate_physics(0.05)
	assert_gt(float(boss_level.elapsed_time), 0.0, "Next simulate_physics after intro must advance elapsed_time > 0")
	for _i: int in range(7):
		boss_level.simulate_physics(0.05)
	assert_false(intro_banner.visible, "IntroBanner must hide cleanly after dismiss transition")
	assert_false(intro_top_bar.visible or intro_bottom_bar.visible, "Intro letterbox bars must hide cleanly after dismiss")

	# Verify skip_intro() immediately completes intro
	boss_level.start_intro(false)
	boss_level.simulate_physics(0.10)
	assert_true(bool(boss_level.is_intro_active), "Intro must be active before skip_intro()")
	boss_level.skip_intro()
	assert_false(bool(boss_level.is_intro_active), "skip_intro() must immediately finish intro")
	assert_true(boss.global_position.is_equal_approx(Vector2(576.0, 152.0)), "skip_intro() must snap Boss to (576, 152)")
	assert_true(bool(boss.is_body_hazardous) and not boss.body_collision.disabled, "skip_intro() must re-enable Boss hitboxes")

	# Verify quick Retry intro finishes cleanly within 0.5s
	boss_level.start_intro(true)
	assert_true(bool(boss_level.is_intro_active), "start_intro(true) must activate quick Retry intro")
	assert_false(intro_top_bar.visible or intro_bottom_bar.visible, "Quick Retry intro must keep letterbox bars hidden")
	for _i: int in range(10):
		boss_level.simulate_physics(0.05)
	assert_false(bool(boss_level.is_intro_active), "Quick Retry intro must finish cleanly within 0.5s")
	assert_true(boss.global_position.is_equal_approx(Vector2(576.0, 152.0)), "Quick Retry intro must land Boss at (576, 152)")
	assert_true(bool(boss.is_body_hazardous) and not boss.body_collision.disabled, "Quick Retry intro must re-enable Boss hitboxes")

	GameManager.set_state(GameManager.State.MENU)
	GameManager.set_difficulty(backup_diff)
	GameManager.save_data = backup_save
	GameManager.save_game()


func test_boss_phase7_and_8_telegraph_and_transition_hygiene() -> void:
	var backup_save: SaveData = GameManager.save_data
	var backup_diff: int = GameManager.selected_difficulty
	GameManager.save_data = SaveData.new()

	var cues: Array[Dictionary] = BossScore.build_score()
	var telegraphed_spatial_kinds: Array[StringName] = [
		&"tidal_wave",
		&"piston_wall",
		&"wall_slam",
		&"hex_grid",
		&"sweeping_beam",
		&"pincer",
		&"hand_dash",
		&"spike_ring",
		&"glitch_wave",
		&"tether_sweep",
		&"shockwave_ring",
		&"ceiling_spike",
		&"gravity_well",
		&"filling_circle",
		&"beat_minion",
		&"floor_slam",
		&"body_lunge",
	]

	var found_p7_transition: bool = false
	var found_p8_transition: bool = false
	var p7_cue_count: int = 0
	var p8_cue_count: int = 0

	for cue: Dictionary in cues:
		var phase: int = int(cue.get("phase", 0))
		if phase != 7 and phase != 8:
			continue
		var kind: StringName = cue.get("kind", &"")
		var impact_beat: float = float(cue.get("impact_beat", 0.0))
		var lead_beats: float = float(cue.get("lead_beats", 0.0))
		var trigger_beat: float = float(cue.get("trigger_beat", 0.0))
		var params: Dictionary = cue.get("params", {}) as Dictionary

		if phase == 7:
			p7_cue_count += 1
			assert_true(
				trigger_beat >= 192.0 - 0.0001,
				"Phase 7 cue '%s' (impact=%.2f) trigger_beat=%.2f must be >= 192.0" % [String(kind), impact_beat, trigger_beat]
			)
			if kind == &"phase_transition" and absf(impact_beat - 192.0) < 0.001:
				found_p7_transition = true
				assert_true(bool(params.get("clear_hazards", false)), "Phase 7 phase_transition at beat 192.0 must set clear_hazards == true")
		else:
			p8_cue_count += 1
			assert_true(
				trigger_beat >= 224.0 - 0.0001,
				"Phase 8 cue '%s' (impact=%.2f) trigger_beat=%.2f must be >= 224.0" % [String(kind), impact_beat, trigger_beat]
			)
			if kind == &"phase_transition" and absf(impact_beat - 224.0) < 0.001:
				found_p8_transition = true
				assert_true(bool(params.get("clear_hazards", false)), "Phase 8 phase_transition at beat 224.0 must set clear_hazards == true")

		if lead_beats > 0.0 or kind in telegraphed_spatial_kinds:
			assert_true(
				lead_beats >= 2.0 - 0.0001,
				"Phase %d telegraphed lethal cue '%s' at impact=%.2f must have lead_beats >= 2.0 (got %.2f)" % [phase, String(kind), impact_beat, lead_beats]
			)

	assert_true(found_p7_transition, "BossScore must contain Phase 7 phase_transition at beat 192.0")
	assert_true(found_p8_transition, "BossScore must contain Phase 8 phase_transition at beat 224.0")
	assert_gt(p7_cue_count, 0, "Phase 7 must have scheduled cues")
	assert_gt(p8_cue_count, 0, "Phase 8 must have scheduled cues")

	# Step BossLevel cleanly through Phase 7 & Phase 8 transitions and verify:
	# - clean hazard purge at 90.0s (P7) and 105.0s (P8)
	# - zero unwarned tangential spikes fired by BossSpikeRing during Phase 8 (b224..252)
	var boss_level: Node2D = _spawn(BOSS_LEVEL_SCENE) as Node2D
	var boss: Area2D = boss_level.get_node("BossContainer/Boss") as Area2D
	var player: CharacterBody2D = boss_level.get_node("Player") as CharacterBody2D
	var beam_container: Node2D = boss_level.get_node("BeamContainer") as Node2D
	_advance_boss_level_safely(boss_level, player, 90.0, 0.125)

	assert_eq(int(boss.current_phase), 7, "Boss must reach Phase 7 at t=90.0s")
	assert_eq(_count_active_boss_hazards(boss_level), 0, "Phase 7 transition at 90.0s must clear prior active hazards")
	assert_eq(boss_level.boss_bullet_manager.get_active_count(), 0, "Phase 7 transition must clear bullets")
	assert_eq(boss_level.boss_hex_grid.get_active_tile_count(), 0, "Phase 7 transition must clear hex tiles")

	_advance_boss_level_safely(boss_level, player, 105.0, 0.125)
	assert_eq(int(boss.current_phase), 8, "Boss must reach Phase 8 at t=105.0s")
	assert_eq(_count_active_boss_hazards(boss_level), 0, "Phase 8 transition at 105.0s must clear prior active hazards")
	assert_eq(boss_level.boss_bullet_manager.get_active_count(), 0, "Phase 8 transition must clear bullets")
	assert_eq(boss_level.boss_hex_grid.get_active_tile_count(), 0, "Phase 8 transition must clear hex tiles")

	var dt: float = 1.0 / 30.0
	var p8_spike_ring_seen: bool = false
	var p8_tangential_release_count: int = 0
	var p8_act8a_spike_bullets: int = 0
	while boss_level.is_level_running and boss_level.elapsed_time < 118.125:
		player.hit_invincibility_timer = 1.0
		boss_level.simulate_physics(dt)
		var song_beat: float = boss_level.elapsed_time / BossConstants.BEAT_DURATION
		for child: Node in beam_container.get_children():
			if child is BossSpikeRing and is_instance_valid(child) and not child.is_queued_for_deletion():
				var sr: BossSpikeRing = child as BossSpikeRing
				p8_spike_ring_seen = true
				if float(sr._release_flash) > 0.001:
					p8_tangential_release_count += 1
		if song_beat < 236.0:
			for b: Dictionary in boss_level.boss_bullet_manager._bullets:
				if StringName(b.get("shape", &"orb")) == &"spike":
					p8_act8a_spike_bullets += 1

	assert_true(p8_spike_ring_seen, "Phase 8 Act 8A must spawn its BossSpikeRing")
	assert_eq(p8_tangential_release_count, 0, "Phase 8 BossSpikeRing must never fire unwarned tangential spikes (b224..252)")
	assert_eq(p8_act8a_spike_bullets, 0, "Phase 8 Act 8A (b224..236) must contain zero tangential spike bullets")

	GameManager.set_state(GameManager.State.MENU)
	GameManager.set_difficulty(backup_diff)
	GameManager.save_data = backup_save
	GameManager.save_game()


func test_boss_phase7_and_8_concurrency_and_reachable_safe_space() -> void:
	var backup_save: SaveData = GameManager.save_data
	var backup_diff: int = GameManager.selected_difficulty
	GameManager.save_data = SaveData.new()

	var boss_level: Node2D = _spawn(BOSS_LEVEL_SCENE) as Node2D
	var boss: Area2D = boss_level.get_node("BossContainer/Boss") as Area2D
	var player: CharacterBody2D = boss_level.get_node("Player") as CharacterBody2D
	_advance_boss_level_safely(boss_level, player, 90.0, 0.125)
	assert_eq(int(boss.current_phase), 7, "Setup must enter Phase 7 at t=90.0s")

	var grid_cols: int = 24
	var grid_rows: int = 14
	var cell_count: int = grid_cols * grid_rows
	var min_x: float = 14.0
	var max_x: float = 1138.0
	var min_y: float = 14.0
	var max_y: float = 634.0
	var step_x: float = (max_x - min_x) / float(grid_cols - 1)
	var step_y: float = (max_y - min_y) / float(grid_rows - 1)
	var grid_pts: PackedVector2Array = PackedVector2Array()
	grid_pts.resize(cell_count)
	for gy: int in range(grid_rows):
		for gx: int in range(grid_cols):
			grid_pts[gy * grid_cols + gx] = Vector2(min_x + float(gx) * step_x, min_y + float(gy) * step_y)

	var player_r: float = BossConstants.get_player_hit_radius(player)
	assert_true(absf(player_r - 9.36) < 0.01, "Boss Mode player hit radius must be 9.36px")

	# Continuous wavefront reachability (dist[i] = remaining px to reach cell center i; 0.0 = occupied)
	var reach_dist: PackedFloat32Array = PackedFloat32Array()
	reach_dist.resize(cell_count)
	var start_snap: Dictionary = _snapshot_active_spatial_hazards(boss_level, boss)
	for i: int in range(cell_count):
		reach_dist[i] = INF if _is_point_in_spatial_snapshot(grid_pts[i], player_r, start_snap, true) else 0.0

	var dt: float = 1.0 / 30.0
	var move_budget: float = 360.0 * dt # Conservative 360 px/s under keyboard 420 px/s
	var half_cell_step: float = 0.5 * minf(step_x, step_y)
	var neighbor_offsets: Array[Vector2i] = [
		Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
	]
	var neighbor_lens: PackedFloat32Array = PackedFloat32Array([
		step_x, step_x, step_y, step_y,
		sqrt(step_x * step_x + step_y * step_y), sqrt(step_x * step_x + step_y * step_y),
		sqrt(step_x * step_x + step_y * step_y), sqrt(step_x * step_x + step_y * step_y),
	])

	var total_frames: int = 0
	var frames_le_2_spatial: int = 0
	var max_spatial_concurrent: int = 0
	var max_spatial_time: float = 90.0
	var min_safe_cells: int = cell_count
	var min_safe_time: float = 90.0
	var min_reachable_cells: int = cell_count
	var min_reachable_time: float = 90.0
	var zero_reachable_report: String = ""

	while boss_level.is_level_running and boss_level.elapsed_time < 118.125:
		player.hit_invincibility_timer = 1.0
		boss_level.simulate_physics(dt)
		if not boss_level.is_level_running or boss_level.elapsed_time >= 118.125:
			break

		total_frames += 1
		var snap: Dictionary = _snapshot_active_spatial_hazards(boss_level, boss)
		var spatial_count: int = int(snap["spatial_count"])
		if spatial_count <= 2:
			frames_le_2_spatial += 1
		if spatial_count > max_spatial_concurrent:
			max_spatial_concurrent = spatial_count
			max_spatial_time = boss_level.elapsed_time

		var safe_mask: PackedByteArray = PackedByteArray()
		safe_mask.resize(cell_count)
		var safe_now: int = 0
		for i: int in range(cell_count):
			# Exempt parryable 360-deg expanding ShockwaveRings from blocking reachability
			# (they cover 360 deg around arena by design and are crossed via timed parry/shield).
			var blocked: bool = _is_point_in_spatial_snapshot(grid_pts[i], player_r, snap, true)
			if blocked:
				safe_mask[i] = 0
				reach_dist[i] = INF
			else:
				safe_mask[i] = 1
				safe_now += 1

		if safe_now < min_safe_cells:
			min_safe_cells = safe_now
			min_safe_time = boss_level.elapsed_time

		# Step 1: seed immediate safe neighbors from occupied cells (reach_dist == 0.0)
		var next_dist: PackedFloat32Array = reach_dist.duplicate()
		for gy: int in range(grid_rows):
			for gx: int in range(grid_cols):
				var idx: int = gy * grid_cols + gx
				if safe_mask[idx] == 0 or reach_dist[idx] > 0.0001:
					continue
				for k: int in range(8):
					var nx: int = gx + neighbor_offsets[k].x
					var ny: int = gy + neighbor_offsets[k].y
					if nx < 0 or nx >= grid_cols or ny < 0 or ny >= grid_rows:
						continue
					var n_idx: int = ny * grid_cols + nx
					if safe_mask[n_idx] == 1 and neighbor_lens[k] < next_dist[n_idx]:
						next_dist[n_idx] = neighbor_lens[k]

		# Step 2: prune in-flight cells whose predecessor became unsafe before midpoint crossing
		for gy: int in range(grid_rows):
			for gx: int in range(grid_cols):
				var idx: int = gy * grid_cols + gx
				var d: float = next_dist[idx]
				if d <= half_cell_step or is_inf(d):
					continue
				var has_closer_safe_pred: bool = false
				for k: int in range(8):
					var nx: int = gx + neighbor_offsets[k].x
					var ny: int = gy + neighbor_offsets[k].y
					if nx < 0 or nx >= grid_cols or ny < 0 or ny >= grid_rows:
						continue
					var n_idx: int = ny * grid_cols + nx
					if safe_mask[n_idx] == 1 and next_dist[n_idx] + 0.01 < d:
						has_closer_safe_pred = true
						break
				if not has_closer_safe_pred:
					next_dist[idx] = INF

		# Step 3: advance surviving safe wavefront by conservative keyboard step (360 px/s * dt)
		var reachable_now: int = 0
		for i: int in range(cell_count):
			if safe_mask[i] == 1 and not is_inf(next_dist[i]):
				var advanced: float = maxf(0.0, next_dist[i] - move_budget)
				reach_dist[i] = advanced
				if advanced <= half_cell_step:
					reachable_now += 1
			else:
				reach_dist[i] = INF

		if reachable_now < min_reachable_cells:
			min_reachable_cells = reachable_now
			min_reachable_time = boss_level.elapsed_time
		if reachable_now == 0 and zero_reachable_report.is_empty():
			var beat_now: float = boss_level.elapsed_time / BossConstants.BEAT_DURATION
			zero_reachable_report = "t=%.3fs (beat %.2f), spatial=%d, safe=%d" % [boss_level.elapsed_time, beat_now, spatial_count, safe_now]

	var pct_le_2: float = (100.0 * float(frames_le_2_spatial)) / maxf(float(total_frames), 1.0)
	print("[PHASE7-8 REACHABILITY] frames=%d max_spatial=%d(at %.2fs) <=2_pct=%.1f%% min_safe=%d(at %.2fs) min_reachable=%d(at %.2fs)" % [
		total_frames, max_spatial_concurrent, max_spatial_time, pct_le_2, min_safe_cells, min_safe_time, min_reachable_cells, min_reachable_time,
	])

	assert_gt(total_frames, 800, "Reachability sweep must cover full Phase 7 & 8 window")
	assert_true(
		max_spatial_concurrent <= 3,
		"Max concurrent active non-bullet spatial hazards must be <= 3 (got %d at %.2fs)" % [max_spatial_concurrent, max_spatial_time]
	)
	assert_true(
		pct_le_2 >= 95.0,
		"At least 95%% of Phase 7 & 8 frames must have <= 2 concurrent active spatial hazards (got %.1f%%)" % pct_le_2
	)
	assert_gt(min_safe_cells, 0, "Non-empty safe space must exist on every frame (hit 0 at %.2fs)" % min_safe_time)
	assert_gt(
		min_reachable_cells,
		0,
		"Keyboard-speed (<=360 px/s) reachable safe frontier must never become empty (%s)" % zero_reachable_report
	)

	GameManager.set_state(GameManager.State.MENU)
	GameManager.set_difficulty(backup_diff)
	GameManager.save_data = backup_save
	GameManager.save_game()


func test_boss_phase7_and_8_scripted_keyboard_player_survival() -> void:
	var backup_save: SaveData = GameManager.save_data
	var backup_diff: int = GameManager.selected_difficulty
	GameManager.save_data = SaveData.new()

	var boss_level: Node2D = _spawn(BOSS_LEVEL_SCENE) as Node2D
	var boss: Area2D = boss_level.get_node("BossContainer/Boss") as Area2D
	var player: CharacterBody2D = boss_level.get_node("Player") as CharacterBody2D
	_advance_boss_level_safely(boss_level, player, 90.0, 0.125)
	assert_eq(int(boss.current_phase), 7, "Keyboard survival test must begin cleanly at Phase 7 (t=90.0s)")

	# Clean starting state at t = 90.0s: 3 HP, full shield, strict keyboard control (use_target_position = false)
	player.release_external_tracking()
	player.use_target_position = false
	player.external_tracking_active = false
	player.global_position = Vector2(576.0, 380.0)
	player.velocity = Vector2.ZERO
	player.current_hp = player.MAX_HP
	player.shield_energy = player.SHIELD_MAX_ENERGY
	player.shield_exhausted = false
	player.shield_recharge_timer = 0.0
	player.hit_invincibility_timer = 0.0
	player.set_shield_held(false)
	boss_level.total_parries = 0
	boss.total_parries = 0
	boss_level._parry_cooldown = 0.0

	var hits_taken: Array[int] = [0]
	var hit_log: Array[String] = []
	player.damaged.connect(func(_amount: int) -> void:
		hits_taken[0] += 1
		var b_now: float = boss_level.elapsed_time / BossConstants.BEAT_DURATION
		var kind_str: String = String(player.get_meta(&"last_hit_hazard_kind", &"unknown"))
		var extra: String = ""
		if kind_str == "boss_hand":
			extra = ",l_act=%d,r_act=%d,grace=%.2f" % [
				int(boss.get_hand_action(true)), int(boss.get_hand_action(false)), float(boss._teleport_grace_timer),
			]
		hit_log.append("t=%.2fs(b%.1f,p%d,kind=%s,pos=%s%s)" % [
			boss_level.elapsed_time, b_now, int(boss.current_phase), kind_str, str(player.global_position.round()), extra,
		])
	)

	var grid_cols: int = 20
	var grid_rows: int = 12
	var cand_pts: PackedVector2Array = PackedVector2Array()
	cand_pts.resize(grid_cols * grid_rows)
	for gy: int in range(grid_rows):
		for gx: int in range(grid_cols):
			cand_pts[gy * grid_cols + gx] = Vector2(
				lerpf(36.0, 1116.0, float(gx) / float(grid_cols - 1)),
				lerpf(36.0, 612.0, float(gy) / float(grid_rows - 1))
			)

	var dt: float = 1.0 / 30.0
	var player_r: float = BossConstants.get_player_hit_radius(player)
	var max_observed_speed: float = 0.0
	var shield_hold_frames: int = 0

	while boss_level.is_level_running and boss_level.elapsed_time < 120.0:
		var plan: Dictionary = _compute_keyboard_bot_plan(boss_level, boss, player, cand_pts, player_r, dt)
		var target_pt: Vector2 = Vector2(plan["target"])
		var want_shield: bool = bool(plan["shield"])

		var delta_vec: Vector2 = target_pt - player.global_position
		_set_simulated_move_inputs(
			delta_vec.x < -4.0,
			delta_vec.x > 4.0,
			delta_vec.y < -4.0,
			delta_vec.y > 4.0
		)
		player.set_shield_held(want_shield)
		if want_shield:
			shield_hold_frames += 1

		var prev_pos: Vector2 = player.global_position
		player._physics_process(dt)
		var step_speed: float = prev_pos.distance_to(player.global_position) / dt
		max_observed_speed = maxf(max_observed_speed, step_speed)
		boss_level.simulate_physics(dt)

	# Always release all simulated inputs before assertions so no state leaks
	_release_all_simulated_inputs()
	player.set_shield_held(false)

	print("[PHASE7-8 KEYBOARD BOT] final_t=%.2fs hp=%d/%d hits=%d parries=%d max_speed=%.1fpx/s shield_frames=%d hit_log=%s" % [
		boss_level.elapsed_time, player.current_hp, player.MAX_HP, hits_taken[0],
		int(boss_level.total_parries), max_observed_speed, shield_hold_frames, ", ".join(hit_log),
	])

	assert_false(player.use_target_position, "Keyboard survival bot must keep use_target_position == false")
	assert_true(
		max_observed_speed <= player.MOVE_SPEED + 2.0,
		"Keyboard survival bot speed %.1f px/s must not exceed MOVE_SPEED (%.1f px/s)" % [max_observed_speed, player.MOVE_SPEED]
	)
	assert_true(
		boss_level.elapsed_time >= 120.0 - 0.001,
		"Keyboard player must survive to victory at 120.0s (died at %.2fs, hits: %s)" % [boss_level.elapsed_time, ", ".join(hit_log)]
	)
	assert_true(player.current_hp >= 1, "Keyboard player must finish alive with >= 1 HP (got %d)" % player.current_hp)
	assert_false(boss_level.is_level_running, "BossLevel must finish cleanly at victory (120.0s)")
	assert_true(bool(boss._shattered), "Boss must shatter on keyboard-player victory")

	GameManager.set_state(GameManager.State.MENU)
	GameManager.set_difficulty(backup_diff)
	GameManager.save_data = backup_save
	GameManager.save_game()


func test_boss_parry_under_overlap_and_tether_fixes() -> void:
	var backup_save: SaveData = GameManager.save_data
	var backup_diff: int = GameManager.selected_difficulty
	GameManager.save_data = SaveData.new()

	var boss_level: Node2D = _spawn(BOSS_LEVEL_SCENE) as Node2D
	var beam_container: Node2D = boss_level.get_node("BeamContainer") as Node2D
	var boss: Area2D = boss_level.get_node("BossContainer/Boss") as Area2D
	var player: CharacterBody2D = boss_level.get_node("Player") as CharacterBody2D

	# (a) Blocking a non-parryable bullet < 0.12s before BossGlitchWave must still trigger parry + SHATTER_PURGE
	boss_level.elapsed_time = 2.0
	boss._elapsed_time = 2.0
	boss_level.total_parries = 0
	boss.total_parries = 0
	boss_level._parry_cooldown = 0.0
	player.global_position = Vector2(576.0, 460.0)
	player.shield_energy = 0.70
	player.shield_exhausted = false
	player.shield_block_feedback_timer = 0.0
	player.set_shield_held(true)
	player._physics_process(0.016)
	assert_true(player.is_shielding, "Player must raise shield before overlapped bullet + glitch wave test")

	# Non-parryable bullet strikes shield first and arms the 0.12s SHIELD_BLOCK_FEEDBACK_COOLDOWN
	boss_level.boss_bullet_manager.spawn_bullet(player.global_position - Vector2(4.0, 0.0), Vector2.RIGHT, 240.0, 6.5, 4.0, &"orb")
	boss_level.boss_bullet_manager.simulate_physics(0.016, Vector2(1152.0, 648.0), player)
	assert_gt(player.shield_block_feedback_timer, 0.05, "Blocking non-parryable bullet must start shield_block_feedback_timer cooldown")
	assert_eq(int(boss_level.total_parries), 0, "Non-parryable bullet must not trigger a parry")

	# Advance only 0.02s (< 0.12s cooldown), then hit shield with a parryable BossGlitchWave
	player._physics_process(0.02)
	assert_gt(player.shield_block_feedback_timer, 0.02, "Feedback cooldown must still be active (<0.12s) when GlitchWave hits")
	var glitch_wave: BossGlitchWave = BossGlitchWave.new()
	beam_container.add_child(glitch_wave)
	glitch_wave.configure(Vector2(1152.0, 648.0), Vector2.RIGHT, 0.01, 1.50, 74.0, 0.5, 160.0, 0.0, true)
	glitch_wave.simulate_physics(0.02, null)
	assert_true(glitch_wave.is_hazard_active, "BossGlitchWave must be active")
	player.global_position = Vector2(glitch_wave._current_sweep, 70.0)
	glitch_wave.simulate_physics(0.016, player)

	assert_eq(int(boss_level.total_parries), 1, "Parryable GlitchWave <0.12s after non-parryable bullet block must still trigger parry")
	assert_eq(int(boss.total_parries), 1, "Boss total_parries must increment to 1 on overlapped GlitchWave parry")
	assert_false(glitch_wave.is_hazard_active, "Parried GlitchWave must deactivate immediately even during block feedback cooldown")
	assert_eq(int(glitch_wave.current_phase), int(BossGlitchWave.Phase.SHATTER_PURGE), "Parried GlitchWave must enter SHATTER_PURGE")
	glitch_wave.queue_free()

	# (b) BossConstants.apply_player_hit and Boss contacts (body/hand/tether) must overwrite stale &"glitch_wave" kind
	player.set_shield_held(false)
	player._physics_process(0.016)
	player.hit_invincibility_timer = 1.0
	player.set_meta(&"last_hit_hazard_kind", &"glitch_wave")
	BossConstants.apply_player_hit(player, false, &"")
	assert_eq(StringName(player.get_meta(&"last_hit_hazard_kind", &"stale")), &"", "apply_player_hit with empty kind must still overwrite stale glitch_wave metadata")

	boss.set_phase_state(7, boss.ActingState.EXHAUSTED_PANTING, boss.BossForm.STOMP_COLOSSUS, Vector2(576.0, 152.0), 8.0)
	boss.simulate_boss(0.60, 91.0, Vector2(1152.0, 648.0), null)
	player.set_meta(&"last_hit_hazard_kind", &"glitch_wave")
	player.global_position = boss.global_position
	boss.simulate_boss(0.016, 91.02, Vector2(1152.0, 648.0), player)
	assert_eq(StringName(player.get_meta(&"last_hit_hazard_kind", &"")), &"boss_body", "Boss body contact must overwrite last_hit_hazard_kind with &'boss_body'")

	player.set_meta(&"last_hit_hazard_kind", &"glitch_wave")
	player.global_position = boss.left_hand.global_position
	boss.simulate_boss(0.016, 91.04, Vector2(1152.0, 648.0), player)
	assert_eq(StringName(player.get_meta(&"last_hit_hazard_kind", &"")), &"boss_hand", "Boss hand contact must overwrite last_hit_hazard_kind with &'boss_hand'")

	boss.command_tether_sweep(340.0, 490.0, 0.0, 0.80)
	boss.simulate_boss(0.016, 91.06, Vector2(1152.0, 648.0), null)
	assert_true(bool(boss._tether_active), "Zero-telegraph tether sweep must activate immediately")
	player.set_meta(&"last_hit_hazard_kind", &"glitch_wave")
	player.global_position = Vector2(576.0, boss.left_hand.global_position.y)
	boss.simulate_boss(0.016, 91.08, Vector2(1152.0, 648.0), player)
	assert_eq(StringName(player.get_meta(&"last_hit_hazard_kind", &"")), &"boss_tether", "Boss tether contact must overwrite last_hit_hazard_kind with &'boss_tether'")

	# (c) Phase 6->7 emerging hands (retract_blend > 0.45) and staging/windup/recovering hands must be non-hazardous
	boss.set_phase_state(6, boss.ActingState.HOLLOW_REBIRTH, boss.BossForm.TRIPLE_CANNON, Vector2(576.0, 324.0), 8.0)
	for _i: int in range(12):
		boss.simulate_boss(0.05, 80.0, Vector2(1152.0, 648.0), null)
	assert_true(float(boss._hands[0]["retract_blend"]) > 0.80, "Phase 6 TRIPLE_CANNON must retract hands")

	boss.set_phase_state(7, boss.ActingState.EXHAUSTED_PANTING, boss.BossForm.STOMP_COLOSSUS, Vector2(576.0, 168.0), 6.8)
	assert_true(float(boss._hands[0]["retract_blend"]) > 0.45, "Hands must still be retracted immediately on Phase 6->7 transition")
	assert_false(bool(boss.is_left_hand_hazardous) or bool(boss.is_right_hand_hazardous), "Emerging Phase 6->7 hands with retract_blend > 0.45 must be non-hazardous")
	assert_true(boss.left_hand_collision.disabled and boss.right_hand_collision.disabled, "Emerging Phase 6->7 hand collisions must be disabled")

	for _i: int in range(14):
		boss.simulate_boss(0.05, 90.8, Vector2(1152.0, 648.0), null)
	assert_true(bool(boss.is_left_hand_hazardous) and bool(boss.is_right_hand_hazardous), "Fully emerged idle hands must become hazardous again")

	# WALL_SLAM_WINDUP -> WALL_SLAM_STRIKE -> WALL_SLAM_RECOVER
	boss.command_wall_slam(true, &"left", 324.0, 0.50, 0.16, 0.88)
	boss.simulate_boss(0.05, 91.0, Vector2(1152.0, 648.0), null)
	assert_eq(int(boss.get_hand_action(true)), int(boss.HandAction.WALL_SLAM_WINDUP), "Left hand must be in WALL_SLAM_WINDUP")
	assert_false(bool(boss.is_left_hand_hazardous), "WALL_SLAM_WINDUP hand must be non-hazardous")
	assert_true(boss.left_hand_collision.disabled, "WALL_SLAM_WINDUP collision must be disabled")
	boss.simulate_boss(0.47, 91.47, Vector2(1152.0, 648.0), null)
	assert_eq(int(boss.get_hand_action(true)), int(boss.HandAction.WALL_SLAM_STRIKE), "Left hand must enter WALL_SLAM_STRIKE")
	assert_true(bool(boss.is_left_hand_hazardous), "WALL_SLAM_STRIKE hand must be hazardous")
	boss.simulate_boss(0.18, 91.65, Vector2(1152.0, 648.0), null)
	assert_eq(int(boss.get_hand_action(true)), int(boss.HandAction.WALL_SLAM_RECOVER), "Left hand must enter WALL_SLAM_RECOVER")
	assert_false(bool(boss.is_left_hand_hazardous), "WALL_SLAM_RECOVER hand must be non-hazardous")

	# PINCER_TELEGRAPH -> PINCER_CLAP -> return_grace -> resting IDLE
	boss.command_pincer(Vector2(576.0, 360.0), 0.50, 0.18)
	boss.simulate_boss(0.05, 92.0, Vector2(1152.0, 648.0), null)
	assert_eq(int(boss.get_hand_action(true)), int(boss.HandAction.PINCER_TELEGRAPH), "Hands must enter PINCER_TELEGRAPH")
	assert_false(bool(boss.is_left_hand_hazardous) or bool(boss.is_right_hand_hazardous), "PINCER_TELEGRAPH hands must be non-hazardous")
	boss.simulate_boss(0.46, 92.46, Vector2(1152.0, 648.0), null)
	assert_eq(int(boss.get_hand_action(true)), int(boss.HandAction.PINCER_CLAP), "Hands must enter PINCER_CLAP")
	assert_true(bool(boss.is_left_hand_hazardous) and bool(boss.is_right_hand_hazardous), "Active PINCER_CLAP hands must be hazardous")
	boss.simulate_boss(0.20, 92.66, Vector2(1152.0, 648.0), null)
	assert_eq(int(boss.get_hand_action(true)), int(boss.HandAction.IDLE), "Finished PINCER_CLAP must return hands to IDLE")
	assert_gt(float(boss._hands[0]["return_grace"]), 0.0, "Finished PINCER_CLAP must grant return_grace")
	assert_false(bool(boss.is_left_hand_hazardous) or bool(boss.is_right_hand_hazardous), "Post-PINCER_CLAP returning hands must stay non-hazardous during return_grace")
	boss.simulate_boss(0.45, 93.11, Vector2(1152.0, 648.0), null)
	assert_true(bool(boss.is_left_hand_hazardous) and bool(boss.is_right_hand_hazardous), "Resting IDLE hands must become hazardous again once return_grace expires")

	# DASH_ACTIVE -> return_grace -> resting IDLE
	boss.command_hand_dash(true, Vector2(110.0, 480.0), Vector2(1042.0, 480.0), 0.20, 0.30, 1)
	boss.simulate_boss(0.25, 93.36, Vector2(1152.0, 648.0), null)
	assert_eq(int(boss.get_hand_action(true)), int(boss.HandAction.DASH_ACTIVE), "Left hand must enter DASH_ACTIVE")
	assert_true(bool(boss.is_left_hand_hazardous), "Active DASH_ACTIVE hand must be hazardous")
	boss.simulate_boss(0.30, 93.66, Vector2(1152.0, 648.0), null)
	assert_eq(int(boss.get_hand_action(true)), int(boss.HandAction.IDLE), "Finished DASH_ACTIVE must return hand to IDLE")
	assert_gt(float(boss._hands[0]["return_grace"]), 0.0, "Finished DASH_ACTIVE must grant return_grace")
	assert_false(bool(boss.is_left_hand_hazardous), "Post-DASH_ACTIVE returning hand must stay non-hazardous during return_grace")
	boss.simulate_boss(0.45, 94.11, Vector2(1152.0, 648.0), null)
	assert_true(bool(boss.is_left_hand_hazardous), "Resting IDLE hand must become hazardous again after DASH_ACTIVE return_grace expires")

	# Phase 8 transition grace must make both body & hands non-hazardous during _teleport_grace_timer > 0.0, then re-enable
	boss.set_phase_state(8, boss.ActingState.TEMPLE_CLUTCH_PANIC, boss.BossForm.OVERDRIVE_PANIC, Vector2(576.0, 560.0), 50.0)
	assert_gt(float(boss._teleport_grace_timer), 0.0, "Phase 8 large reposition must activate _teleport_grace_timer")
	assert_false(bool(boss.is_body_hazardous), "Phase 8 transition grace must keep body non-hazardous")
	assert_false(bool(boss.is_left_hand_hazardous) or bool(boss.is_right_hand_hazardous), "Phase 8 transition grace must keep both hands non-hazardous")
	assert_true(boss.left_hand_collision.disabled and boss.right_hand_collision.disabled, "Phase 8 transition grace must disable hand collisions")
	boss.simulate_boss(0.50, 106.0, Vector2(1152.0, 648.0), null)
	assert_true(bool(boss.is_body_hazardous) and bool(boss.is_left_hand_hazardous) and bool(boss.is_right_hand_hazardous), "Body and hands must re-enable after Phase 8 transition grace expires")

	# Pre-active TETHER_SWEEP + (d) zero 1-frame phantom sweep from stale prev_pos & active tether hands parryable
	boss._hands[0]["pos"] = Vector2(200.0, 60.0)
	boss._hands[0]["prev_pos"] = Vector2(200.0, 60.0)
	boss._hands[1]["pos"] = Vector2(950.0, 60.0)
	boss._hands[1]["prev_pos"] = Vector2(950.0, 60.0)
	boss.command_tether_sweep(260.0, 480.0, 0.50, 0.80)
	boss.simulate_boss(0.25, 106.25, Vector2(1152.0, 648.0), null)
	assert_false(bool(boss._tether_active), "Pre-active TETHER_SWEEP must keep _tether_active == false")
	assert_false(bool(boss.is_left_hand_hazardous) or bool(boss.is_right_hand_hazardous), "Pre-active TETHER_SWEEP hands must be non-hazardous")

	# Exact-boundary transition (0.25 + 0.25 == 0.50 -> ov == 0.0) with unshielded player in stale corridor y=130
	player.current_hp = 3
	player.hit_invincibility_timer = 0.0
	player.set_shield_held(false)
	player._physics_process(0.016)
	player.global_position = Vector2(576.0, 130.0)
	boss.simulate_boss(0.25, 106.50, Vector2(1152.0, 648.0), player)
	assert_true(bool(boss._tether_active), "TETHER_SWEEP must activate at exact telegraph boundary")
	assert_eq(player.current_hp, 3, "Exact-boundary TETHER_SWEEP activation must not cause a 1-frame phantom sweep hit at y=130")
	assert_true(Vector2(boss._hands[0]["prev_pos"]).y >= 259.0, "TETHER_SWEEP hand prev_pos.y must reset to stage_pos.y (260) on activation")

	# Active tether hands must be parryable
	assert_true(boss._is_hand_action_parryable(0) and boss._is_hand_action_parryable(1), "Active TETHER_SWEEP hands must be parryable")
	boss_level._parry_cooldown = 0.0
	boss_level.elapsed_time = 106.55
	var parries_before_tether_hand: int = int(boss_level.total_parries)
	player.shield_energy = player.SHIELD_MAX_ENERGY
	player.shield_exhausted = false
	player.shield_block_feedback_timer = 0.0
	player.set_shield_held(true)
	player._physics_process(0.016)
	player.global_position = boss.left_hand.global_position
	boss.simulate_boss(0.016, 106.56, Vector2(1152.0, 648.0), player)
	assert_eq(int(boss_level.total_parries), parries_before_tether_hand + 1, "Shielding on active TETHER_SWEEP hand must trigger timed parry")

	GameManager.set_state(GameManager.State.MENU)
	GameManager.set_difficulty(backup_diff)
	GameManager.save_data = backup_save
	GameManager.save_game()


func _advance_boss_level_safely(boss_level: Node2D, player: CharacterBody2D, target_time: float, dt: float) -> void:
	while boss_level.is_level_running and boss_level.elapsed_time + 0.0001 < target_time:
		var step: float = minf(dt, target_time - boss_level.elapsed_time)
		player.global_position = Vector2(100.0, 580.0)
		player.hit_invincibility_timer = 1.0
		boss_level.simulate_physics(step)


func _snapshot_active_spatial_hazards(boss_level: Node2D, boss: Area2D) -> Dictionary:
	var spatial_count: int = 0
	var active_hex_centers: PackedVector2Array = PackedVector2Array()
	if boss_level.boss_hex_grid != null and bool(boss_level.boss_hex_grid.is_hazard_active):
		spatial_count += 1
		var hex_grid: BossHexGrid = boss_level.boss_hex_grid
		for idx: int in hex_grid._busy_indices:
			var c: Dictionary = hex_grid._cells[idx]
			if int(c["state"]) == BossHexGrid.TileState.ACTIVE:
				active_hex_centers.append(Vector2(c["pos"]))

	var beams: Array[BossSweepingBeam] = []
	var rings: Array[BossShockwaveRing] = []
	var tidal_rects: Array[Rect2] = []
	var piston_rects: Array[Rect2] = []
	var spike_rings: Array[BossSpikeRing] = []
	var glitch_waves: Array[BossGlitchWave] = []

	var beam_container: Node2D = boss_level.get_node_or_null("BeamContainer") as Node2D
	if beam_container != null:
		for child: Node in beam_container.get_children():
			if not is_instance_valid(child) or child.is_queued_for_deletion():
				continue
			if not ("is_hazard_active" in child) or not bool(child.is_hazard_active):
				continue
			spatial_count += 1
			if child is BossSweepingBeam:
				beams.append(child as BossSweepingBeam)
			elif child is BossShockwaveRing:
				var sw: BossShockwaveRing = child as BossShockwaveRing
				if sw.wave_mode == BossShockwaveRing.WaveMode.RING:
					rings.append(sw)
				else:
					for r: Rect2 in sw._get_tidal_rects(sw.current_wave_coord):
						tidal_rects.append(r)
			elif child is BossPistonWall:
				var pw: BossPistonWall = child as BossPistonWall
				if pw.current_extension > 0.5:
					piston_rects.append(pw.get_piston_rect())
			elif child is BossSpikeRing:
				spike_rings.append(child as BossSpikeRing)
			elif child is BossGlitchWave:
				glitch_waves.append(child as BossGlitchWave)

	return {
		"spatial_count": spatial_count,
		"hex_centers": active_hex_centers,
		"beams": beams,
		"rings": rings,
		"tidal_rects": tidal_rects,
		"piston_rects": piston_rects,
		"spike_rings": spike_rings,
		"glitch_waves": glitch_waves,
		"boss": boss,
	}


func _is_point_in_spatial_snapshot(pt: Vector2, player_r: float, snap: Dictionary, ignore_parryable_rings: bool) -> bool:
	var hex_centers: PackedVector2Array = snap["hex_centers"]
	var eff_hex_r: float = BossHexGrid.HEX_RADIUS * 0.92
	for h_pos: Vector2 in hex_centers:
		if BossConstants.circle_flat_hex_overlap(pt - h_pos, eff_hex_r, player_r):
			return true

	for beam: BossSweepingBeam in snap["beams"]:
		var half_len: float = beam.beam_length * 0.5
		var half_w: float = beam.beam_width * 0.5
		var rel: Vector2 = pt - beam.global_position
		for i: int in range(beam.beam_count):
			var dir: Vector2 = Vector2.from_angle(beam.get_spoke_angle(i))
			if absf(rel.dot(dir)) <= half_len + player_r and absf(rel.cross(dir)) <= half_w + player_r:
				return true

	for rect: Rect2 in snap["tidal_rects"]:
		if BossConstants.circle_rect_overlap(pt, player_r, rect):
			return true

	for rect: Rect2 in snap["piston_rects"]:
		if BossConstants.circle_rect_overlap(pt, player_r, rect):
			return true

	for sw: BossShockwaveRing in snap["rings"]:
		if ignore_parryable_rings and sw.parryable:
			continue
		if absf(pt.distance_to(sw.global_position) - sw.current_radius) <= sw._thickness * 0.5 + player_r:
			return true

	for sr: BossSpikeRing in snap["spike_rings"]:
		var hit_r: float = sr._spike_radius * 0.88 + player_r
		var hit_r_sq: float = hit_r * hit_r
		for s_pos: Vector2 in sr._spike_world_positions:
			if pt.distance_squared_to(s_pos) <= hit_r_sq:
				return true

	for gw: BossGlitchWave in snap["glitch_waves"]:
		var half_t: float = gw._wave_thickness * 0.5
		var half_gap: float = gw._gap_size * 0.5
		var s_coord: float = pt.dot(gw._sweep_dir)
		if absf(s_coord - gw._current_sweep) <= half_t + player_r:
			var p_coord: float = pt.dot(gw._perp_dir)
			if absf(p_coord - gw._current_gap_perp) > maxf(half_gap - player_r, 0.0):
				return true

	var boss: Area2D = snap["boss"] as Area2D
	if boss != null and is_instance_valid(boss):
		if bool(boss.is_body_hazardous):
			var cb: Vector2 = Geometry2D.get_closest_point_to_segment(pt, Vector2(boss._lunge["prev"]), boss.global_position) if bool(boss._lunge["swept"]) else boss.global_position
			if cb.distance_to(pt) <= float(boss.BODY_RADIUS) + player_r:
				return true
		for idx: int in range(2):
			if not (bool(boss.is_left_hand_hazardous) if idx == 0 else bool(boss.is_right_hand_hazardous)):
				continue
			var h: Dictionary = boss._hands[idx]
			var hp: Vector2 = boss.left_hand.global_position if idx == 0 else boss.right_hand.global_position
			var ch: Vector2 = Geometry2D.get_closest_point_to_segment(pt, Vector2(h["prev_pos"]), hp) if bool(h["swept"]) else hp
			if ch.distance_to(pt) <= float(boss.HAND_RADIUS) + player_r:
				return true
		if bool(boss._tether_active):
			var lp: Vector2 = boss.left_hand.global_position
			var rp: Vector2 = boss.right_hand.global_position
			var tether_r: float = 5.0 + player_r
			var hit_t: bool = Geometry2D.get_closest_point_to_segment(pt, lp, rp).distance_to(pt) <= tether_r
			if not hit_t and pt.x >= minf(lp.x, rp.x) - player_r and pt.x <= maxf(lp.x, rp.x) + player_r:
				var prev_y: float = Vector2(boss._hands[0]["prev_pos"]).y
				hit_t = pt.y >= minf(prev_y, lp.y) - tether_r and pt.y <= maxf(prev_y, lp.y) + tether_r
			if hit_t:
				return true

	return false


func _compute_keyboard_bot_plan(
	boss_level: Node2D,
	boss: Area2D,
	player: CharacterBody2D,
	cand_pts: PackedVector2Array,
	player_r: float,
	dt: float
) -> Dictionary:
	var p_pos: Vector2 = player.global_position
	var margin_r: float = player_r + 12.0
	var active_snap: Dictionary = _snapshot_active_spatial_hazards(boss_level, boss)

	# Collect active + telegraphing hazards once per frame for lookahead steering
	var hex_grid: BossHexGrid = boss_level.boss_hex_grid
	var tele_hex_centers: PackedVector2Array = PackedVector2Array()
	var eval_pts: PackedVector2Array = cand_pts.duplicate()
	eval_pts.append(p_pos)
	if hex_grid != null and not hex_grid._busy_indices.is_empty():
		for c: Dictionary in hex_grid._cells:
			var st: int = int(c["state"])
			if st == BossHexGrid.TileState.TELEGRAPH or (st == BossHexGrid.TileState.DELAYED and float(c["delay"]) < 0.35):
				tele_hex_centers.append(Vector2(c["pos"]))
			elif st == BossHexGrid.TileState.IDLE:
				var hp: Vector2 = Vector2(c["pos"])
				if hp.x >= 36.0 and hp.x <= 1116.0 and hp.y >= 36.0 and hp.y <= 612.0:
					eval_pts.append(hp)

	var all_beams: Array[BossSweepingBeam] = []
	var all_rings: Array[BossShockwaveRing] = []
	var all_tidals: Array[BossShockwaveRing] = []
	var all_pistons: Array[BossPistonWall] = []
	var all_spikes: Array[BossSpikeRing] = []
	var all_glitches: Array[BossGlitchWave] = []
	var beam_container: Node2D = boss_level.get_node_or_null("BeamContainer") as Node2D
	if beam_container != null:
		for child: Node in beam_container.get_children():
			if not is_instance_valid(child) or child.is_queued_for_deletion():
				continue
			if child is BossSweepingBeam:
				var bm: BossSweepingBeam = child as BossSweepingBeam
				if bm.current_phase == BossSweepingBeam.Phase.TELEGRAPH or bm.current_phase == BossSweepingBeam.Phase.ACTIVE:
					all_beams.append(bm)
			elif child is BossShockwaveRing:
				var sw: BossShockwaveRing = child as BossShockwaveRing
				if sw.current_phase == BossShockwaveRing.Phase.TELEGRAPH or sw.current_phase == BossShockwaveRing.Phase.ACTIVE:
					if sw.wave_mode == BossShockwaveRing.WaveMode.RING:
						all_rings.append(sw)
					else:
						all_tidals.append(sw)
			elif child is BossPistonWall:
				var pw: BossPistonWall = child as BossPistonWall
				if pw.current_phase == BossPistonWall.Phase.TELEGRAPH or pw.current_phase == BossPistonWall.Phase.SLAM or pw.current_phase == BossPistonWall.Phase.HOLD:
					all_pistons.append(pw)
			elif child is BossSpikeRing:
				var sr: BossSpikeRing = child as BossSpikeRing
				if sr.current_phase == BossSpikeRing.Phase.TELEGRAPH or sr.current_phase == BossSpikeRing.Phase.ACTIVE:
					all_spikes.append(sr)
			elif child is BossGlitchWave:
				var gw: BossGlitchWave = child as BossGlitchWave
				if gw.current_phase == BossGlitchWave.Phase.TELEGRAPH or gw.current_phase == BossGlitchWave.Phase.ACTIVE:
					all_glitches.append(gw)

	var bullets: Array[Dictionary] = boss_level.boss_bullet_manager._bullets if boss_level.boss_bullet_manager != null else []

	# Shield/parry trigger: raise shield right before an expanding ShockwaveRing or unavoidable immediate impact
	var want_shield: bool = false
	for sw: BossShockwaveRing in all_rings:
		if not sw.is_hazard_active:
			continue
		var ring_speed: float = (sw._end_radius - sw._start_radius) / maxf(sw._travel_time, 0.05)
		var dist_p: float = p_pos.distance_to(sw.global_position)
		var gap_r: float = dist_p - sw.current_radius
		var band: float = sw._thickness * 0.5 + player_r
		if gap_r >= -band - 4.0 and gap_r <= band + ring_speed * (dt * 3.0):
			want_shield = true
			break

	if not want_shield:
		for b: Dictionary in bullets:
			var b_pos: Vector2 = Vector2(b["pos"])
			var b_vel: Vector2 = Vector2(b["vel"])
			var b_next: Vector2 = b_pos + b_vel * (dt * 2.2)
			var hit_r: float = float(b["radius"]) + player_r + 5.0
			if Geometry2D.get_closest_point_to_segment(p_pos, b_pos, b_next).distance_to(p_pos) <= hit_r:
				want_shield = true
				break

	if not want_shield and _is_point_in_spatial_snapshot(p_pos, player_r + 2.0, active_snap, true):
		want_shield = true

	var eff_hex_r: float = BossHexGrid.HEX_RADIUS * 0.92
	var hex_margin_r: float = player_r + 5.0
	var best_pt: Vector2 = p_pos
	var best_cost: float = INF

	for pt: Vector2 in eval_pts:
		var cost: float = 0.0

		# 1. Active spatial hazards (highest priority; tight margin for stationary hexes)
		if _is_point_in_spatial_snapshot(pt, player_r + 5.0, active_snap, true):
			cost += 1200.0
		elif _is_point_in_spatial_snapshot(pt, margin_r, active_snap, true):
			cost += 240.0

		# 2. Telegraphed hex tiles (stationary lattice -> 5px margin preserves 44px CHECKER safe pockets)
		for h_pos: Vector2 in tele_hex_centers:
			if BossConstants.circle_flat_hex_overlap(pt - h_pos, eff_hex_r, hex_margin_r):
				cost += 420.0
				break

		# 3. Beams (telegraph + forward angular sweep wedge)
		for bm: BossSweepingBeam in all_beams:
			var rel: Vector2 = pt - bm.global_position
			var half_w: float = bm.beam_width * 0.5 + margin_r + 14.0
			var look_angles: Array[float] = [bm.current_angle]
			if absf(bm._angular_speed) > 0.01:
				look_angles.append(bm.current_angle + bm._angular_speed * 0.30)
				look_angles.append(bm.current_angle + bm._angular_speed * 0.65)
				look_angles.append(bm.current_angle + bm._angular_speed * 1.00)
			var hit_bm: bool = false
			for base_a: float in look_angles:
				for si: int in range(bm.beam_count):
					var dir: Vector2 = Vector2.from_angle(base_a + PI * float(si) / float(bm.beam_count))
					if absf(rel.cross(dir)) <= half_w:
						hit_bm = true
						break
				if hit_bm:
					break
			if hit_bm:
				cost += 540.0 if bm.is_hazard_active else 380.0

		# 4. Pistons (full reach target rect during telegraph/active)
		for pw: BossPistonWall in all_pistons:
			if BossConstants.circle_rect_overlap(pt, margin_r, pw.get_piston_rect(pw._reach)):
				cost += 320.0

		# 5. Tidal waves (align into safe gap band before wave passes pt)
		for tw: BossShockwaveRing in all_tidals:
			var is_h: bool = (tw._side == &"left" or tw._side == &"right")
			var pt_sweep: float = pt.x if is_h else pt.y
			var pt_perp: float = pt.y if is_h else pt.x
			var moving_pos: bool = (tw._end_coord > tw._start_coord)
			var wave_ahead: bool = (pt_sweep >= tw.current_wave_coord - tw._thickness) if moving_pos else (pt_sweep <= tw.current_wave_coord + tw._thickness)
			if wave_ahead:
				var half_safe: float = maxf(tw._gap_size * 0.5 - margin_r - 12.0, 20.0)
				var off_gap: float = absf(pt_perp - tw._gap_center)
				if off_gap > half_safe:
					cost += 480.0 + (off_gap - half_safe) * 1.2

		# 6. Glitch waves (align into exact sinusoidal corridor before wave passes pt)
		for gw: BossGlitchWave in all_glitches:
			var s_pt: float = pt.dot(gw._sweep_dir)
			var p_pt: float = pt.dot(gw._perp_dir)
			if s_pt >= gw._current_sweep - gw._wave_thickness:
				var gap_here: float = gw._eval_gap_perp_at_sweep(s_pt)
				var half_safe: float = maxf(gw._gap_size * 0.5 - margin_r - 16.0, 20.0)
				var off_gap: float = absf(p_pt - gap_here)
				if off_gap > half_safe:
					cost += 540.0 + (off_gap - half_safe) * 1.4

		# 7. Orbit spike ring: stay cleanly outside or well inside the ring band
		for sr: BossSpikeRing in all_spikes:
			if sr.ring_mode == BossSpikeRing.RingMode.ORBIT_RING:
				var r_pt: float = pt.distance_to(sr.global_position)
				var r_lo: float = minf(sr._start_radius, sr._end_radius) - sr._spike_radius - margin_r - 10.0
				var r_hi: float = maxf(sr._start_radius, sr._end_radius) + sr._spike_radius + margin_r + 10.0
				if r_pt >= r_lo and r_pt <= r_hi:
					cost += 360.0

		# 8. Boss body clearance & telegraphed hand attacks (dash, pincer, wall slam, tether)
		if boss != null and is_instance_valid(boss):
			var body_d: float = pt.distance_to(boss.global_position)
			if body_d < float(boss.BODY_RADIUS) + margin_r + 32.0:
				cost += 380.0
			for idx: int in range(2):
				var h: Dictionary = boss._hands[idx]
				var act: int = int(h["action"])
				if act == int(boss.HandAction.DASH_TELEGRAPH) or act == int(boss.HandAction.DASH_ACTIVE):
					var seg_d: float = Geometry2D.get_closest_point_to_segment(pt, Vector2(h["stage_pos"]), Vector2(h["target_pos"])).distance_to(pt)
					if seg_d <= float(boss.HAND_RADIUS) + margin_r + 18.0:
						cost += 420.0
				elif act == int(boss.HandAction.PINCER_TELEGRAPH) or act == int(boss.HandAction.PINCER_CLAP):
					var seg_p: float = Geometry2D.get_closest_point_to_segment(pt, Vector2(h["stage_pos"]), Vector2(h["target_pos"])).distance_to(pt)
					if seg_p <= float(boss.HAND_RADIUS) + margin_r + 22.0:
						cost += 420.0
				elif act == int(boss.HandAction.WALL_SLAM_WINDUP) or act == int(boss.HandAction.WALL_SLAM_STRIKE):
					var seg_w: float = Geometry2D.get_closest_point_to_segment(pt, Vector2(h["stage_pos"]), Vector2(h["target_pos"])).distance_to(pt)
					if seg_w <= float(boss.HAND_RADIUS) + margin_r + 18.0:
						cost += 360.0
				elif act == int(boss.HandAction.TETHER_SWEEP):
					var lx: float = Vector2(boss._hands[0]["stage_pos"]).x
					var rx: float = Vector2(boss._hands[1]["stage_pos"]).x
					var sy: float = float(h["tether_start_y"])
					var ey: float = float(h["tether_end_y"])
					if pt.x >= lx - margin_r - 16.0 and pt.x <= rx + margin_r + 16.0 and pt.y >= minf(sy, ey) - margin_r - 18.0 and pt.y <= maxf(sy, ey) + margin_r + 18.0:
						cost += 460.0

		# 9. Bullet trajectory lookahead (0.0s .. 0.45s)
		for b: Dictionary in bullets:
			var b_pos: Vector2 = Vector2(b["pos"])
			var b_vel: Vector2 = Vector2(b["vel"])
			var b_end: Vector2 = b_pos + b_vel * 0.45
			var b_r: float = float(b["radius"]) + margin_r + 6.0
			if Geometry2D.get_closest_point_to_segment(pt, b_pos, b_end).distance_to(pt) <= b_r:
				cost += 220.0

		# 10. Mild travel-distance & edge-margin tiebreakers for smooth keyboard steering
		cost += pt.distance_to(p_pos) * 0.08
		if pt.x < 70.0 or pt.x > 1082.0 or pt.y < 70.0 or pt.y > 578.0:
			cost += 12.0

		if cost < best_cost:
			best_cost = cost
			best_pt = pt

	return {"target": best_pt, "shield": want_shield}


func _set_simulated_move_inputs(left: bool, right: bool, up: bool, down: bool) -> void:
	if left:
		Input.action_press("move_left")
	else:
		Input.action_release("move_left")
	if right:
		Input.action_press("move_right")
	else:
		Input.action_release("move_right")
	if up:
		Input.action_press("move_up")
	else:
		Input.action_release("move_up")
	if down:
		Input.action_press("move_down")
	else:
		Input.action_release("move_down")


func _release_all_simulated_inputs() -> void:
	for action: String in ["move_left", "move_right", "move_up", "move_down", "shield"]:
		Input.action_release(action)


func _count_active_boss_hazards(boss_level: Node2D) -> int:
	var count: int = 0
	if boss_level.boss_hex_grid != null and bool(boss_level.boss_hex_grid.is_hazard_active):
		count += 1
	if boss_level.boss_bullet_manager != null and bool(boss_level.boss_bullet_manager.is_hazard_active):
		count += 1
	var beam_container: Node2D = boss_level.get_node_or_null("BeamContainer") as Node2D
	if beam_container != null:
		for child: Node in beam_container.get_children():
			if is_instance_valid(child) and not child.is_queued_for_deletion() and "is_hazard_active" in child and bool(child.is_hazard_active):
				count += 1
	return count


func _is_player_within_arena(pos: Vector2, arena_size: Vector2, margin: float) -> bool:
	return pos.x >= margin - 0.01 and pos.x <= arena_size.x - margin + 0.01 and pos.y >= margin - 0.01 and pos.y <= arena_size.y - margin + 0.01


func _assert_no_text_nodes(node: Node) -> void:
	assert_false(node is Label, "Boss must contain zero Label nodes: " + node.name)
	assert_false(node is RichTextLabel, "Boss must contain zero RichTextLabel nodes: " + node.name)
	for child: Node in node.get_children():
		_assert_no_text_nodes(child)


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
