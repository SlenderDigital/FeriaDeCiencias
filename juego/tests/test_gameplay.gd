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

	var boss_level: Node2D = _spawn(BOSS_LEVEL_SCENE) as Node2D
	var boss_container: Node2D = boss_level.get_node_or_null("BossContainer") as Node2D
	var beam_container: Node2D = boss_level.get_node_or_null("BeamContainer") as Node2D
	var boss: Area2D = boss_level.get_node_or_null("BossContainer/Boss") as Area2D
	var player: CharacterBody2D = boss_level.get_node_or_null("Player") as CharacterBody2D
	var complete_panel: Control = boss_level.get_node_or_null("HUD/HUDRoot/LevelCompletePanel") as Control
	var hud: CanvasLayer = boss_level.get_node_or_null("HUD") as CanvasLayer

	assert_true(boss_container != null and beam_container != null and boss != null and player != null, "BossLevel nodes must exist")
	assert_gt(beam_container.get_index(), boss_container.get_index(), "BossContainer must precede BeamContainer so _clear_hazards never frees Boss")
	assert_eq(boss_level.difficulty_mode, GameManager.Difficulty.BOSS, "BossLevel difficulty_mode must be BOSS (3)")
	assert_eq(boss_level.level_duration, 120.0, "BossLevel duration must be 120.0s")
	assert_true(hud.boss_phase_label != null and hud.boss_phase_label.visible, "Boss HUD phase label must be visible")
	assert_eq(hud.boss_phase_label.text, "PHASE 1 / 8", "Boss HUD must start at PHASE 1 / 8")
	assert_eq(hud.controls_hint_label.modulate.a, 1.0, "ControlsHintLabel alpha must be 1.0 in Phase 1")
	assert_eq(boss.face_rig.z_index, 2, "Boss FaceRig z_index must be 2 so eyes/mouth stay visible over beams and walls")

	_assert_subtree_monochrome_and_primitive(boss_level)
	_assert_no_text_nodes(boss)

	# Keep player in bottom-left safe corner so Boss lunges/slams do not accidentally hit during phase sweep
	player.global_position = Vector2(100.0, 580.0)

	# Phase 1 acting state, always-active hitboxes & live micro-reactions (shield_blocked -> flinch, damaged -> laugh)
	assert_eq(boss.current_phase, 1, "Boss must start in Phase 1")
	assert_eq(int(boss.acting_state), int(boss.ActingState.COCKY_CONDUCTOR), "Phase 1 acting_state must be COCKY_CONDUCTOR")
	assert_false(bool(boss._lunge_active), "Boss must not be lunging at spawn")
	assert_false(bool(boss._hand_dashes[0]["active"]) or bool(boss._hand_dashes[1]["active"]), "Hands must not be dashing at spawn")
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

	player.global_position = Vector2(100.0, 580.0)
	player.heal(1, true)
	player.hit_invincibility_timer = 0.0
	player.hit_flash_timer = 0.0
	boss._flinch_timer = 0.0
	boss._laugh_timer = 0.0

	# Step 0s -> 120s in 0.5s outer steps (4x 0.125s substeps so short physical dashes & thrown seeds are captured)
	var seen_states: Dictionary = {int(boss.acting_state): true}
	var phase_transitions_checked: Dictionary = {1: true}
	var seen_dash_styles: Dictionary = {}
	var seen_seed_payloads: Dictionary = {}
	var seen_pincer: bool = false
	var seen_claw_orbit: bool = false
	var seen_hand_slam: bool = false
	var seen_wall_push: bool = false
	var seen_thrown_seeds: bool = false
	var seen_ritual_styles: Dictionary = {}
	var intro_beams: Array[int] = [0]
	var intro_wall_slams: Array[int] = [0]
	var enemies_by_phase: Dictionary = {}
	var seen_enemy_types: Dictionary = {}
	var wall_slam_signals: Array[int] = [0]
	var max_wall_slam_miss_dist: Array[float] = [0.0]
	var verified_phase4_tether: bool = false
	var verified_safe_corner_pre_heal: bool = false

	boss.request_beam.connect(func(_pos: Vector2, _angle: float, _width: float, _warning: float, _active_t: float) -> void:
		if boss_level.elapsed_time < 1.8:
			intro_beams[0] += 1
	)
	boss.request_enemy.connect(func(enemy_type: int, _spawn_pos: Vector2, _speed_scale: float, _warning: float, _max_lifetime: float) -> void:
		var ph: int = int(boss.current_phase)
		enemies_by_phase[ph] = int(enemies_by_phase.get(ph, 0)) + 1
		seen_enemy_types[enemy_type] = true
	)
	boss.boss_wall_slammed.connect(func(wall_pos: Vector2, inward_normal: Vector2, _strength: float) -> void:
		wall_slam_signals[0] += 1
		if boss_level.elapsed_time < 1.8:
			intro_wall_slams[0] += 1
		var expected_contact: Vector2 = wall_pos + inward_normal * 20.0
		var hand_dist: float = minf(
			expected_contact.distance_to(boss.left_hand.global_position),
			expected_contact.distance_to(boss.right_hand.global_position)
		)
		max_wall_slam_miss_dist[0] = maxf(max_wall_slam_miss_dist[0], hand_dist)
		assert_true(hand_dist <= 28.0, "Wall slam impact #%d contact-to-hand distance %.2fpx must be <= 28.0px" % [wall_slam_signals[0], hand_dist])
	)

	for step: int in range(1, 241):
		for _sub: int in range(4):
			boss_level.simulate_physics(0.125)
			if boss_level.is_level_running:
				for h_idx: int in range(2):
					var hd: Dictionary = boss._hand_dashes[h_idx]
					if bool(hd["active"]):
						seen_dash_styles[int(hd["style"])] = true
					if float(boss._hand_slams[h_idx]["active"]) > 0.0:
						seen_hand_slam = true
				if float(boss._pincer_timer) > 0.0:
					seen_pincer = true
				if float(boss._claw_orbit_timer) > 0.0:
					seen_claw_orbit = true
				if float(boss._wall_push_timer) > 0.0:
					seen_wall_push = true
				if not boss._thrown_seeds.is_empty():
					seen_thrown_seeds = true
					for sd: Dictionary in boss._thrown_seeds:
						seen_seed_payloads[StringName(sd["payload_type"])] = true
				for rt: Dictionary in boss._spawn_rituals:
					seen_ritual_styles[int(rt["style"])] = true

		if boss_level.is_level_running:
			seen_states[int(boss.acting_state)] = true
			phase_transitions_checked[int(boss.current_phase)] = true
			if step < 30:
				assert_eq(hud.controls_hint_label.modulate.a, 1.0, "ControlsHintLabel alpha must stay 1.0 in Phase 1 (step %d)" % step)
			else:
				assert_true(hud.controls_hint_label.modulate.a <= 0.20, "ControlsHintLabel alpha must dim to <= 0.20 in Phases 2-8 (step %d)" % step)

		# Phase boundaries at 0.5s grid: 1.5s (3), 14.5s (29), 15s (30), 30s (60), 45s (90), 48s (96), 59s (118), 59.5s (119), 60s (120), 64s (128), 75s (150), 89.5s (179), 90s (180), 105s (210), 118.5s (237)
		if step == 3:
			assert_eq(intro_beams[0], 0, "Phase 1 opening intro (t < 1.8s) must trigger 0 beams")
			assert_eq(intro_wall_slams[0], 0, "Phase 1 opening intro (t < 1.8s) must trigger 0 wall slams")
			assert_eq(beam_container.get_child_count(), 0, "Phase 1 opening intro (t < 1.8s) must have 0 hazard nodes")
		elif step == 29:
			# Before Phase 2 (t = 14.5s): set HP=1 and exhaust shield to test standard phase heal(1, false)
			assert_eq(player.current_hp, 3, "Passive corner (100, 580) must be undamaged across Phase 1")
			player.current_hp = 1
			player.shield_energy = 0.25
			player.shield_exhausted = true
		elif step == 30:
			assert_eq(boss.current_phase, 2, "t=15s must be Phase 2")
			assert_eq(int(boss.acting_state), int(boss.ActingState.FROZEN_DOUBLE_TAKE), "Phase 2 must enter FROZEN_DOUBLE_TAKE")
			assert_true(bool(boss.is_body_hazardous) and bool(boss.is_left_hand_hazardous) and bool(boss.is_right_hand_hazardous), "Boss body and hands must remain hazardous in Phase 2")
			assert_eq(player.current_hp, 2, "Phase 2 completion must heal +1 HP (1 -> 2)")
			assert_true(player.shield_exhausted, "Standard Phase 2 heal(1, false) must preserve shield exhaustion")
		elif step == 60:
			assert_eq(boss.current_phase, 3, "t=30s must be Phase 3")
			assert_eq(int(boss.acting_state), int(boss.ActingState.FLOOR_SLAM_TANTRUM), "Phase 3 must enter FLOOR_SLAM_TANTRUM")
			assert_eq(player.current_hp, 3, "Phase 3 completion must heal +1 HP (2 -> 3)")
		elif step == 90:
			assert_eq(boss.current_phase, 4, "t=45s must be Phase 4")
			assert_eq(int(boss.acting_state), int(boss.ActingState.ACCUSING_POINT), "Phase 4 must enter ACCUSING_POINT")
		elif step == 96:
			assert_true(bool(boss._tether_active), "Phase 4 High-Voltage Clothesline (_tether_active) must be active at t=48.0s")
			assert_eq(player.current_hp, 3, "Passive corner (100, 580) must be undamaged prior to Phase 4 Clothesline probe")
			var tether_pt: Vector2 = boss.left_hand.global_position.lerp(boss.right_hand.global_position, 0.22)
			assert_gt(tether_pt.distance_to(boss.global_position), 80.0, "Clothesline probe point must be clear of Boss body")
			assert_gt(tether_pt.distance_to(boss.left_hand.global_position), 80.0, "Clothesline probe point must be clear of Left Hand")
			assert_gt(tether_pt.distance_to(boss.right_hand.global_position), 80.0, "Clothesline probe point must be clear of Right Hand")

			var tether_dir: Vector2 = (boss.right_hand.global_position - boss.left_hand.global_position).normalized()
			var tether_perp: Vector2 = Vector2(-tether_dir.y, tether_dir.x)
			player.set_shield_held(false)
			player._physics_process(0.016)
			player.hit_invincibility_timer = 0.0
			player.global_position = tether_pt + tether_perp * 22.0
			boss.simulate_boss(0.0, boss_level.elapsed_time, Vector2(1152.0, 648.0), player)
			assert_eq(player.current_hp, 3, "22px outside narrowed Phase 4 Clothesline (5 + 14 = 19px) must NOT deal damage")

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
			player.hit_invincibility_timer = 0.0
			player.hit_flash_timer = 0.0
			player.shield_block_feedback_timer = 0.0
			boss._flinch_timer = 0.0
			boss._laugh_timer = 0.0
			boss.simulate_boss(0.0, boss_level.elapsed_time, Vector2(1152.0, 648.0), player)
			assert_eq(player.current_hp, 3, "Passive safe corner (100, 580) must remain untouched by active Phase 4 Clothesline")
			verified_phase4_tether = true
		elif step == 118:
			assert_eq(player.current_hp, 3, "Passive safe corner Vector2(100.0, 580.0) must remain untouched across Act 1 & Phase 4")
			verified_safe_corner_pre_heal = true
		elif step == 119:
			# Right before Phase 5 (t = 59.5s): set HP=1 and exhaust shield to test Act Milestone Phase 5 heal(1, true)
			player.current_hp = 1
			player.shield_energy = 0.10
			player.shield_exhausted = true
		elif step == 120:
			assert_eq(boss.current_phase, 5, "t=60s must be Phase 5")
			assert_eq(int(boss.acting_state), int(boss.ActingState.FAKE_OUT_COLLAPSE), "Phase 5 must enter FAKE_OUT_COLLAPSE")
			assert_false(bool(boss.is_body_hazardous), "Collapsed Boss head must have is_body_hazardous == false during FAKE_OUT_COLLAPSE")
			assert_true(boss.body_collision.disabled, "Collapsed Boss body CollisionShape2D must be disabled during FAKE_OUT_COLLAPSE")
			assert_false(bool(boss.is_left_hand_hazardous) or bool(boss.is_right_hand_hazardous), "Hands must stay dormant before beat 8 of FAKE_OUT_COLLAPSE")
			assert_eq(player.current_hp, 2, "Phase 5 must heal player from 1 HP to 2 HP")
			assert_eq(player.shield_energy, player.SHIELD_MAX_ENERGY, "Phase 5 heal must recharge shield to 100%")
			assert_false(player.shield_exhausted, "Phase 5 heal must clear shield_exhausted")
			assert_eq(hud.boss_phase_label.text, "PHASE 5 / 8", "HUD must display PHASE 5 / 8")
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
		elif step == 150:
			assert_eq(boss.current_phase, 6, "t=75s must be Phase 6")
			assert_eq(int(boss.acting_state), int(boss.ActingState.HOLLOW_REBIRTH), "Phase 6 must enter HOLLOW_REBIRTH")
			assert_true(bool(boss.is_body_hazardous) and bool(boss.is_left_hand_hazardous) and bool(boss.is_right_hand_hazardous), "Boss body and hands must be hazardous in Phase 6")
			assert_false(boss.body_collision.disabled or boss.left_hand_collision.disabled or boss.right_hand_collision.disabled, "Boss CollisionShape2Ds must be enabled in Phase 6")
			assert_eq(player.current_hp, 3, "Phase 6 completion must heal +1 HP (2 -> 3)")
		elif step == 179:
			# Right before Phase 7 (t = 89.5s): set HP=2 and exhaust shield to test Act Milestone Phase 7 heal(1, true)
			player.current_hp = 2
			player.shield_energy = 0.15
			player.shield_exhausted = true
		elif step == 180:
			assert_eq(boss.current_phase, 7, "t=90s must be Phase 7")
			assert_eq(int(boss.acting_state), int(boss.ActingState.EXHAUSTED_PANTING), "Phase 7 must enter EXHAUSTED_PANTING")
			assert_eq(player.current_hp, 3, "Phase 7 must heal player from 2 HP to 3 HP")
			assert_eq(player.shield_energy, player.SHIELD_MAX_ENERGY, "Phase 7 heal must recharge shield to 100%")
			assert_false(player.shield_exhausted, "Phase 7 heal must clear shield_exhausted")
			player.heal(1, true)
			assert_eq(player.current_hp, 3, "player.heal must clamp at MAX_HP (3)")
		elif step == 210:
			assert_eq(boss.current_phase, 8, "t=105s must be Phase 8")
			assert_eq(int(boss.acting_state), int(boss.ActingState.TEMPLE_CLUTCH_PANIC), "Phase 8 must enter TEMPLE_CLUTCH_PANIC")
		elif step == 237:
			assert_eq(int(boss.acting_state), int(boss.ActingState.SILENT_SHATTER), "Beat 252 (>=118.125s) must enter SILENT_SHATTER")
			assert_false(bool(boss.is_body_hazardous) or bool(boss.is_left_hand_hazardous) or bool(boss.is_right_hand_hazardous), "SILENT_SHATTER must disable Boss and hand hazard flags")
			assert_eq(player.current_hp, 3, "Passive safe corner Vector2(100.0, 580.0) must remain untouched through Act 3")

	assert_true(seen_dash_styles.has(int(boss.HandDashStyle.FIST_ROCKET)), "Rocket fist dash (FIST_ROCKET) must trigger during Boss phases")
	assert_true(seen_dash_styles.has(int(boss.HandDashStyle.CLAW_SWIPE)), "Claw sweep (CLAW_SWIPE) must trigger during Boss phases")
	assert_true(seen_dash_styles.has(int(boss.HandDashStyle.FLOOR_RAKE)), "Floor rake (FLOOR_RAKE) must trigger during Boss phases")
	assert_true(seen_pincer, "Double-fist pincer attack must trigger during Boss phases")
	assert_true(seen_claw_orbit, "Spinning claw orbit must trigger during Boss phases")
	assert_true(seen_hand_slam, "Hand slam pounce must trigger during Boss phases")
	assert_true(seen_wall_push, "Hand-pushed closing wall must trigger during Boss phases")
	assert_true(seen_thrown_seeds, "Thrown hazard seeds must launch during Boss phases")
	assert_eq(intro_beams[0], 0, "Phase 1 opening intro (t < 1.8s) must fire 0 beams")
	assert_eq(intro_wall_slams[0], 0, "Phase 1 opening intro (t < 1.8s) must trigger 0 wall slams")
	assert_true(int(boss.total_wall_slams) >= 16, "Border wall slams must trigger >= 16 times across Phases 2, 5, 7, 8 (got %d)" % int(boss.total_wall_slams))
	assert_true(wall_slam_signals[0] >= 16, "boss_wall_slammed signal must fire >= 16 times across phases (got %d)" % wall_slam_signals[0])
	assert_true(max_wall_slam_miss_dist[0] <= 28.0, "Every wall slam impact must have hand within 28.0px of wall contact (max %.2fpx)" % max_wall_slam_miss_dist[0])
	assert_true(verified_phase4_tether, "Phase 4 Clothesline tether contact verification must execute")
	assert_true(verified_safe_corner_pre_heal, "Passive corner pre-heal verification must execute")
	assert_true(int(boss.total_spawn_rituals) >= 6, "Enemy-spawning rituals (CROWN_FORGE & DIMENSIONAL_RIFT) must execute >= 6 times across Phase 3 & Act 3 (got %d)" % int(boss.total_spawn_rituals))
	assert_true(seen_ritual_styles.has(int(boss.RitualStyle.CROWN_FORGE)), "CROWN_FORGE ritual must execute in Phase 3")
	assert_true(seen_ritual_styles.has(int(boss.RitualStyle.DIMENSIONAL_RIFT)), "DIMENSIONAL_RIFT ritual must execute in Act 3")
	assert_true(int(enemies_by_phase.get(3, 0)) >= 2, "Phase 3 must request >= 2 enemies (got %d)" % int(enemies_by_phase.get(3, 0)))
	assert_true(int(enemies_by_phase.get(6, 0)) >= 2, "Phase 6 must request >= 2 enemies (got %d)" % int(enemies_by_phase.get(6, 0)))
	assert_true(int(enemies_by_phase.get(7, 0)) >= 1, "Phase 7 must request >= 1 enemy (got %d)" % int(enemies_by_phase.get(7, 0)))
	assert_true(int(enemies_by_phase.get(8, 0)) >= 2, "Phase 8 must request >= 2 enemies (got %d)" % int(enemies_by_phase.get(8, 0)))
	for expected_enemy_type: int in [0, 1, 2, 3]:
		assert_true(seen_enemy_types.has(expected_enemy_type), "Boss must request Enemy type %d across Phase 3 & Act 3" % expected_enemy_type)
	for expected_payload: StringName in [&"circle", &"exploder", &"saw", &"enemy"]:
		assert_true(seen_seed_payloads.has(expected_payload), "Thrown seed payload '%s' must launch during Boss phases" % String(expected_payload))

	for p: int in range(1, 9):
		assert_true(phase_transitions_checked.has(p), "Boss must visit Phase %d/8" % p)
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

	assert_false(boss_level.is_level_running, "BossLevel must complete at 120.0s")
	assert_true(complete_panel.visible, "LevelCompletePanel must display at 120.0s")
	assert_true(bool(boss._shattered), "Boss must shatter on level completion")

	var boss_rec: Dictionary = GameManager.save_data.get_record(GameManager.Difficulty.BOSS)
	assert_false(boss_rec.is_empty(), "Boss completion must save a record under difficulty key 3")
	assert_true(bool(boss_rec.get("completed", false)), "Boss record key 3 must be marked completed=true")
	assert_true(float(boss_rec.get("time", 0.0)) >= 120.0, "Boss record key 3 time must be >= 120.0s")

	# Retry must reset Boss and re-arm Phase 2..8 heals
	boss_level._on_retry_pressed()
	assert_true(boss_level.is_level_running, "Retry must restart BossLevel")
	assert_eq(boss_level.elapsed_time, 0.0, "Retry must reset elapsed_time")
	assert_eq(boss.current_phase, 1, "Retry must reset Boss to Phase 1")
	assert_eq(int(boss.acting_state), int(boss.ActingState.COCKY_CONDUCTOR), "Retry must reset Boss ActingState to COCKY_CONDUCTOR")
	assert_false(bool(boss._shattered), "Retry must clear Boss shattered state")
	assert_eq(int(boss.total_wall_slams), 0, "Retry must reset total_wall_slams to 0")
	assert_eq(int(boss.total_spawn_rituals), 0, "Retry must reset total_spawn_rituals to 0")
	assert_eq(int(boss_level._last_healed_phase), 1, "Retry must reset _last_healed_phase to 1")
	assert_eq(hud.controls_hint_label.modulate.a, 1.0, "Retry must restore ControlsHintLabel alpha to 1.0 in Phase 1")
	assert_eq(player.current_hp, 3, "Retry must restore player to 3 HP")

	player.global_position = Vector2(100.0, 580.0)
	for step_retry: int in range(1, 121):
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
