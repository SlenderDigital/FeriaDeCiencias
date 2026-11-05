extends Node2D

signal level_completed
signal game_over

enum Difficulty {
	EASY = 0,
	NORMAL = 1,
	HARD = 2,
}

const LEVEL_DURATION: float = 45.0
const LIGHT_BEAM_SCENE: PackedScene = preload("res://scenes/light_beam.tscn")
const FILLING_CIRCLE_SCENE: PackedScene = preload("res://scenes/filling_circle.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")
const EXPLODER_SCENE: PackedScene = preload("res://scenes/exploder.tscn")
const SAW_SCENE: PackedScene = preload("res://scenes/saw.tscn")
const CLOSING_WALL_SCENE: PackedScene = preload("res://scenes/closing_wall.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/enemy.tscn")

const DEFAULT_BEAM_WIDTH: float = 44.0
const DEFAULT_CIRCLE_RADIUS: float = 78.0
const DEFAULT_PROJECTILE_SPEED: float = 390.0
const DEFAULT_PROJECTILE_RADIUS: float = 10.0
const DEFAULT_EXPLODER_BURST_COUNT: int = 8
const TELEGRAPH_TIME: float = 1.0
const ACTIVE_TIME: float = 0.35
const MIN_WALL_GAP: float = 132.0
const SAFE_SPAWN_DISTANCE: float = 250.0
const DEFAULT_ENEMY_WARNING: float = 0.85

@export var level_duration: float = LEVEL_DURATION

var difficulty_mode: int = Difficulty.NORMAL
var elapsed_time: float = 0.0
var is_level_running: bool = true
var current_music_section: int = 0
var spawn_timer: float = 0.45
var wave_index: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var hand_tracker: Node = null
var saws_spawned: int = 0
var walls_spawned: int = 0
var enemies_spawned: int = 0
var autonomous_spawn_cursor: int = 0

var _arena_size: Vector2 = Vector2(1152.0, 648.0)
var _last_music_beat_idx: int = 0
var _shake_time: float = 0.0
var _shake_duration: float = 0.0
var _shake_strength: float = 0.0
var _shake_rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var background: ColorRect = $Background
@onready var hand_shadow: Node2D = $HandShadow
@onready var beam_container: Node2D = $BeamContainer
@onready var arena_fx: Node2D = $ArenaFX
@onready var arena_grid: Node2D = $ArenaGrid
@onready var player: CharacterBody2D = $Player
@onready var game_camera: Camera2D = $GameCamera
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	rng.randomize()
	_shake_rng.randomize()
	hand_tracker = HandTrackingClient
	difficulty_mode = clampi(GameManager.selected_difficulty, Difficulty.EASY, Difficulty.HARD)

	get_viewport().size_changed.connect(_on_viewport_resized)
	player.hp_changed.connect(hud.update_hp)
	player.died.connect(_on_player_died)
	player.shield_changed.connect(_on_player_shield_changed)
	player.shield_blocked.connect(_on_player_shield_blocked)
	player.shield_broken.connect(_on_player_shield_broken)
	player.damaged.connect(_on_player_damaged)
	hud.retry_requested.connect(_on_retry_pressed)
	hud.main_menu_requested.connect(_on_main_menu_pressed)

	_on_viewport_resized()
	restart_level()


func _process(delta: float) -> void:
	_update_screen_shake(delta)


func _exit_tree() -> void:
	SoundManager.stop_music()


func set_hand_tracker(tracker: Node) -> void:
	hand_tracker = tracker
	_sync_hand_tracking_to_gameplay(0.0)


func ingest_hand_packet(packet: PackedByteArray) -> bool:
	if hand_tracker == null:
		return false
	var ok: bool = hand_tracker.ingest_packet(packet)
	_sync_hand_tracking_to_gameplay(0.016)
	return ok


func ingest_hand_packet_batch(packets: Array[PackedByteArray]) -> bool:
	if hand_tracker == null:
		return false
	var ok: bool = hand_tracker.ingest_packet_batch(packets)
	_sync_hand_tracking_to_gameplay(0.016)
	return ok


func set_difficulty(mode: int) -> void:
	difficulty_mode = clampi(mode, Difficulty.EASY, Difficulty.HARD)
	GameManager.selected_difficulty = difficulty_mode
	spawn_timer = get_initial_spawn_delay()


func get_difficulty_name() -> String:
	return GameManager.get_difficulty_name(difficulty_mode)


func get_initial_spawn_delay() -> float:
	match difficulty_mode:
		Difficulty.EASY:
			return 0.55
		Difficulty.HARD:
			return 0.30
		_:
			return 0.45


func get_spawn_interval_for_progress(progress_ratio: float) -> float:
	var clamped: float = clampf(progress_ratio, 0.0, 1.0)
	match difficulty_mode:
		Difficulty.EASY:
			return lerpf(1.65, 1.20, clamped)
		Difficulty.HARD:
			return lerpf(0.78, 0.50, clamped)
		_:
			return lerpf(1.20, 0.82, clamped)


func get_threat_speed_scale() -> float:
	match difficulty_mode:
		Difficulty.EASY:
			return 0.88
		Difficulty.HARD:
			return 1.14
		_:
			return 1.0


func get_max_autonomous_threats() -> int:
	match difficulty_mode:
		Difficulty.EASY:
			return 1
		Difficulty.HARD:
			return 3
		_:
			return 2


func get_max_saws() -> int:
	return 1 if difficulty_mode == Difficulty.EASY else 2


func get_max_enemies() -> int:
	return 1 if difficulty_mode == Difficulty.EASY else 2


func _count_active_threats(group_name: StringName) -> int:
	var count: int = 0
	for child: Node in beam_container.get_children():
		if not child.is_queued_for_deletion() and child.is_in_group(group_name):
			count += 1
	return count


func _can_spawn_autonomous_threat() -> bool:
	var total: int = (
		_count_active_threats(&"enemies")
		+ _count_active_threats(&"saws")
		+ _count_active_threats(&"closing_walls")
	)
	return total < get_max_autonomous_threats()


func _physics_process(delta: float) -> void:
	simulate_physics(delta)


func simulate_physics(delta: float) -> void:
	_sync_hand_tracking_to_gameplay(delta)
	hud.update_shield(player.get_shield_energy_ratio(), player.is_shielding, player.shield_exhausted)
	if not is_level_running:
		return

	elapsed_time += delta
	hud.update_timer(elapsed_time, level_duration)
	_update_music_reactivity()

	if elapsed_time >= level_duration:
		trigger_level_complete()
		return

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_next_wave()
		var progress_ratio: float = clampf(elapsed_time / maxf(level_duration, 0.001), 0.0, 1.0)
		spawn_timer = get_spawn_interval_for_progress(progress_ratio)


func restart_level() -> void:
	_clear_beams()
	arena_fx.clear()
	_shake_time = 0.0
	_shake_strength = 0.0
	game_camera.offset = Vector2.ZERO
	elapsed_time = 0.0
	wave_index = 0
	saws_spawned = 0
	walls_spawned = 0
	enemies_spawned = 0
	autonomous_spawn_cursor = 0
	current_music_section = 0
	_last_music_beat_idx = 0
	spawn_timer = get_initial_spawn_delay()
	is_level_running = true

	player.reset_player(_arena_size * 0.5)
	hud.reset(level_duration)
	hud.update_shield(player.get_shield_energy_ratio(), player.is_shielding, player.shield_exhausted)
	_sync_hand_tracking_to_gameplay(0.0)
	SoundManager.play_music(_get_music_pitch_for_difficulty())
	_update_music_reactivity()


func spawn_beam(
	spawn_pos: Vector2,
	angle_radians: float,
	width: float = DEFAULT_BEAM_WIDTH,
	warning_time: float = TELEGRAPH_TIME,
	active_time: float = ACTIVE_TIME
) -> Area2D:
	var beam: Area2D = LIGHT_BEAM_SCENE.instantiate() as Area2D
	beam_container.add_child(beam)
	beam.configure(spawn_pos, angle_radians, width, warning_time, active_time)
	return beam


func spawn_circle(
	spawn_pos: Vector2,
	radius: float = DEFAULT_CIRCLE_RADIUS,
	fill_mode: int = 0,
	warning_time: float = TELEGRAPH_TIME,
	active_time: float = ACTIVE_TIME
) -> Area2D:
	var hazard: Area2D = FILLING_CIRCLE_SCENE.instantiate() as Area2D
	beam_container.add_child(hazard)
	hazard.configure(spawn_pos, radius, fill_mode, warning_time, active_time)
	return hazard


func spawn_projectile(
	spawn_pos: Vector2,
	direction: Vector2,
	speed: float = DEFAULT_PROJECTILE_SPEED,
	radius: float = DEFAULT_PROJECTILE_RADIUS
) -> Area2D:
	var hazard: Area2D = PROJECTILE_SCENE.instantiate() as Area2D
	beam_container.add_child(hazard)
	hazard.configure(spawn_pos, direction, speed, radius)
	return hazard


func spawn_edge_projectile(
	edge_index: int = -1,
	speed: float = DEFAULT_PROJECTILE_SPEED,
	radius: float = DEFAULT_PROJECTILE_RADIUS
) -> Area2D:
	var chosen_edge: int = posmod(edge_index if edge_index >= 0 else rng.randi_range(0, 3), 4)
	var spawn_pos: Vector2 = Vector2.ZERO
	match chosen_edge:
		0:
			spawn_pos = Vector2(rng.randf_range(40.0, _arena_size.x - 40.0), 0.0)
		1:
			spawn_pos = Vector2(_arena_size.x, rng.randf_range(40.0, _arena_size.y - 40.0))
		2:
			spawn_pos = Vector2(rng.randf_range(40.0, _arena_size.x - 40.0), _arena_size.y)
		3:
			spawn_pos = Vector2(0.0, rng.randf_range(40.0, _arena_size.y - 40.0))

	var target_point: Vector2 = Vector2(
		rng.randf_range(_arena_size.x * 0.2, _arena_size.x * 0.8),
		rng.randf_range(_arena_size.y * 0.2, _arena_size.y * 0.8)
	)
	if rng.randf() < 0.55:
		target_point = player.global_position + Vector2(rng.randf_range(-90.0, 90.0), rng.randf_range(-90.0, 90.0))
	var dir: Vector2 = (target_point - spawn_pos).normalized()
	if dir.length_squared() <= 0.0001:
		dir = Vector2.DOWN
	return spawn_projectile(spawn_pos, dir, speed, radius)


func spawn_exploder(
	spawn_pos: Vector2,
	warning_time: float = TELEGRAPH_TIME,
	burst_count: int = DEFAULT_EXPLODER_BURST_COUNT,
	projectile_speed: float = DEFAULT_PROJECTILE_SPEED
) -> Area2D:
	var hazard: Area2D = EXPLODER_SCENE.instantiate() as Area2D
	beam_container.add_child(hazard)
	hazard.configure(spawn_pos, warning_time, burst_count, projectile_speed)
	hazard.exploder_detonated.connect(_on_exploder_detonated)
	return hazard


func spawn_closing_wall(
	axis: int = -1,
	gap_center: float = -1.0,
	gap_size: float = MIN_WALL_GAP,
	warning: float = 1.25
) -> Node2D:
	var wall: Node2D = CLOSING_WALL_SCENE.instantiate() as Node2D
	beam_container.add_child(wall)
	var chosen_axis: int = axis if axis >= 0 else rng.randi_range(0, 1)
	var axis_span: float = _arena_size.x if chosen_axis == 0 else _arena_size.y
	var player_axis_pos: float = player.global_position.x if chosen_axis == 0 else player.global_position.y
	var chosen_center: float = gap_center if gap_center >= 0.0 else player_axis_pos + rng.randf_range(-92.0, 92.0)
	chosen_center = clampf(chosen_center, gap_size * 0.5 + 40.0, axis_span - gap_size * 0.5 - 40.0)
	var close_time: float = 0.76 - 0.06 * float(difficulty_mode)
	var hold_time: float = 1.25 - 0.05 * float(difficulty_mode)
	wall.configure(chosen_axis, chosen_center, gap_size, 46.0, warning, close_time, hold_time, 0.55)
	wall.wall_slammed.connect(_on_wall_slammed)
	walls_spawned += 1
	var arrival_pos: Vector2 = Vector2(chosen_center, _arena_size.y * 0.5) if chosen_axis == 0 else Vector2(_arena_size.x * 0.5, chosen_center)
	arena_fx.spawn_ring(arrival_pos, 10.0, 46.0, 0.34, Color(0.72, 0.72, 0.72, 0.7), 2.0)
	return wall


func spawn_saw(
	mode: int = -1,
	spawn_position: Vector2 = Vector2(-9999.0, -9999.0),
	direction: Vector2 = Vector2.ZERO,
	speed: float = -1.0,
	radius: float = 30.0,
	warning: float = -1.0,
	max_lifetime: float = -1.0
) -> Area2D:
	var chosen_mode: int = mode if mode >= 0 else rng.randi_range(0, 1)
	var pos: Vector2 = spawn_position
	var dir: Vector2 = direction
	if pos.x < -9000.0:
		if chosen_mode == 0:
			match rng.randi_range(0, 3):
				0:
					pos = Vector2(rng.randf_range(120.0, _arena_size.x - 120.0), 74.0)
				1:
					pos = Vector2(_arena_size.x - 74.0, rng.randf_range(120.0, _arena_size.y - 120.0))
				2:
					pos = Vector2(rng.randf_range(120.0, _arena_size.x - 120.0), _arena_size.y - 74.0)
				_:
					pos = Vector2(74.0, rng.randf_range(120.0, _arena_size.y - 120.0))
			var target: Vector2 = Vector2(rng.randf_range(_arena_size.x * 0.25, _arena_size.x * 0.75), rng.randf_range(_arena_size.y * 0.25, _arena_size.y * 0.75))
			dir = (target - pos).normalized()
		else:
			var from_left: bool = rng.randf() < 0.5
			pos = Vector2(74.0 if from_left else _arena_size.x - 74.0, rng.randf_range(110.0, _arena_size.y - 110.0))
			dir = Vector2.RIGHT if from_left else Vector2.LEFT
	if dir.length_squared() < 0.001:
		dir = Vector2.RIGHT
	var chosen_speed: float = speed if speed >= 0.0 else (195.0 + 26.0 * float(difficulty_mode)) * get_threat_speed_scale()
	var chosen_warning: float = warning if warning >= 0.0 else 0.68 - 0.05 * float(difficulty_mode)
	var chosen_lifetime: float = max_lifetime if max_lifetime > 0.0 else rng.randf_range(5.4, 6.4)
	var saw: Area2D = SAW_SCENE.instantiate() as Area2D
	beam_container.add_child(saw)
	saw.configure(chosen_mode, pos, dir, chosen_speed, radius, chosen_warning, chosen_lifetime)
	saw.bounced.connect(_on_saw_bounced)
	saws_spawned += 1
	arena_fx.spawn_ring(pos, 10.0, 46.0, 0.34, Color(0.72, 0.72, 0.72, 0.7), 2.0)
	return saw


func spawn_enemy(
	type: int = -1,
	spawn_position: Vector2 = Vector2(-9999.0, -9999.0),
	speed_scale: float = -1.0,
	warning: float = DEFAULT_ENEMY_WARNING,
	max_lifetime: float = 7.0
) -> Area2D:
	var chosen_type: int = type if type >= 0 else enemies_spawned % 4
	var pos: Vector2 = spawn_position if spawn_position.x > -9000.0 else _find_safe_spawn_position()
	var chosen_scale: float = speed_scale if speed_scale > 0.0 else get_threat_speed_scale()
	var enemy: Area2D = ENEMY_SCENE.instantiate() as Area2D
	beam_container.add_child(enemy)
	enemy.configure_enemy(chosen_type, pos, player, chosen_scale, warning, max_lifetime)
	enemy.fire_projectile.connect(_on_enemy_fire_projectile)
	enemy.enemy_lunged.connect(_on_enemy_lunged)
	enemy.enemy_despawned.connect(_on_enemy_despawned)
	enemies_spawned += 1
	arena_fx.spawn_ring(pos, 10.0, 46.0, 0.34, Color(0.72, 0.72, 0.72, 0.7), 2.0)
	return enemy


func _find_safe_spawn_position() -> Vector2:
	var best: Vector2 = Vector2(_arena_size.x - 80.0, _arena_size.y - 80.0)
	var best_distance: float = -1.0
	for _attempt: int in range(10):
		var candidate: Vector2 = Vector2(
			rng.randf_range(80.0, _arena_size.x - 80.0),
			rng.randf_range(90.0, _arena_size.y - 90.0)
		)
		var distance: float = candidate.distance_to(player.global_position)
		if distance >= SAFE_SPAWN_DISTANCE:
			return candidate
		if distance > best_distance:
			best_distance = distance
			best = candidate
	return best


func _on_enemy_fire_projectile(origin: Vector2, direction: Vector2, speed: float, radius: float) -> void:
	spawn_projectile(origin, direction, speed, radius)
	arena_fx.spawn_burst(origin, 4, 110.0, Color(0.85, 0.85, 0.85, 1.0), 0.22, 6.0, 1.5)
	SoundManager.play_sfx(&"enemy_fire", -6.0)


func _on_enemy_lunged(origin: Vector2, direction: Vector2) -> void:
	arena_fx.spawn_ring(origin, 10.0, 42.0, 0.24, Color(0.92, 0.92, 0.92, 0.82), 2.0)
	arena_fx.spawn_directional_burst(origin, -direction, 0.65, 7, 185.0, Color(0.88, 0.88, 0.88, 0.95), 0.24, 8.0, 1.6)
	SoundManager.play_sfx(&"enemy_lunge", -5.0)


func _on_enemy_despawned(origin: Vector2) -> void:
	arena_fx.spawn_ring(origin, 14.0, 38.0, 0.22, Color(0.65, 0.65, 0.65, 0.6), 1.5)
	arena_fx.spawn_burst(origin, 6, 130.0, Color(0.75, 0.75, 0.75, 0.8), 0.22, 6.5, 1.5)


func _on_saw_bounced(at_position: Vector2, normal: Vector2) -> void:
	arena_fx.spawn_ring(at_position, 14.0, 48.0, 0.24, Color(0.92, 0.92, 0.92, 0.8), 2.0)
	arena_fx.spawn_directional_burst(at_position, normal, 0.95, 8, 220.0, Color(0.94, 0.94, 0.94, 1.0), 0.26, 8.5, 1.8)
	arena_grid.pulse(0.26)
	SoundManager.play_sfx(&"saw_bounce", -5.0)


func _on_wall_slammed(gap_world_center: Vector2, _axis: int) -> void:
	arena_fx.spawn_ring(gap_world_center, 18.0, 84.0, 0.36, Color(0.95, 0.95, 0.95, 0.88), 2.4)
	arena_fx.spawn_burst(gap_world_center, 10, 210.0, Color(0.90, 0.90, 0.90, 0.95), 0.30, 9.0, 1.8)
	arena_grid.pulse(0.52)
	trigger_screen_shake(3.2, 0.18)
	SoundManager.play_sfx(&"wall_slam", -3.0)


func _on_exploder_detonated(at_position: Vector2) -> void:
	arena_fx.spawn_ring(at_position, 14.0, 76.0, 0.34, Color(0.96, 0.96, 0.96, 0.92), 2.4)
	arena_fx.spawn_burst(at_position, 12, 230.0, Color(0.92, 0.92, 0.92, 1.0), 0.30, 9.5, 1.8)
	arena_grid.pulse(0.42)
	trigger_screen_shake(2.6, 0.15)


func set_hand_tracking_target(screen_pos: Vector2) -> void:
	player.set_target_position(screen_pos, true)


func set_normalized_hand_tracking_target(normalized_pos: Vector2) -> void:
	player.set_normalized_target_position(normalized_pos)


func release_hand_tracking_target() -> void:
	player.release_external_tracking()


func _sync_hand_tracking_to_gameplay(delta: float) -> void:
	var has_tracked_hand: bool = hand_tracker != null and bool(hand_tracker.has_hand)
	if is_level_running:
		if has_tracked_hand:
			set_normalized_hand_tracking_target(hand_tracker.get_mirrored_palm_center())
			player.set_shield_held(bool(hand_tracker.is_fist))
		elif player.external_tracking_active:
			release_hand_tracking_target()

	hand_shadow.update_from_tracker(hand_tracker, delta, _arena_size)
	var state: int = int(hand_tracker.tracking_state) if hand_tracker != null else 0
	var label_str: String = hand_tracker.get_status_label_text() if hand_tracker != null else "HAND: OFFLINE"
	hud.update_hand_status(state, label_str, hand_shadow.pulse)


func _spawn_next_wave() -> void:
	var player_pos: Vector2 = player.global_position
	var current_wave: int = wave_index
	var pattern: int = current_wave % 7
	wave_index += 1

	if pattern >= 4:
		if _spawn_rotating_autonomous_threat():
			return
		pattern = current_wave % 4

	match pattern:
		0:
			var angle: float = rng.randf_range(-PI, PI)
			var offset: Vector2 = Vector2.from_angle(angle + PI * 0.5) * rng.randf_range(-35.0, 35.0)
			var pos: Vector2 = Vector2(
				clampf(player_pos.x + offset.x, 80.0, _arena_size.x - 80.0),
				clampf(player_pos.y + offset.y, 80.0, _arena_size.y - 80.0)
			)
			spawn_beam(pos, angle)
		1:
			var fill_mode: int = int(floor(float(current_wave) / 7.0)) % 3
			var circle_pos: Vector2 = Vector2(
				clampf(player_pos.x + rng.randf_range(-120.0, 120.0), 110.0, _arena_size.x - 110.0),
				clampf(player_pos.y + rng.randf_range(-100.0, 100.0), 110.0, _arena_size.y - 110.0)
			)
			spawn_circle(circle_pos, DEFAULT_CIRCLE_RADIUS, fill_mode)
		2:
			var edge_a: int = int(floor(float(current_wave) / 7.0)) % 4
			spawn_edge_projectile(edge_a)
			spawn_edge_projectile((edge_a + 2) % 4)
		3:
			spawn_exploder(_find_safe_spawn_position())


func _spawn_rotating_autonomous_threat() -> bool:
	if not _can_spawn_autonomous_threat():
		return false
	for offset: int in range(3):
		var threat_kind: int = (autonomous_spawn_cursor + offset) % 3
		match threat_kind:
			0:
				if _count_active_threats(&"enemies") < get_max_enemies():
					spawn_enemy(enemies_spawned % 4)
					autonomous_spawn_cursor = (threat_kind + 1) % 3
					return true
			1:
				if _count_active_threats(&"saws") < get_max_saws():
					spawn_saw(saws_spawned % 2)
					autonomous_spawn_cursor = (threat_kind + 1) % 3
					return true
			2:
				if _count_active_threats(&"closing_walls") < 1:
					var wall_gap: float = MIN_WALL_GAP + float(2 - difficulty_mode) * 4.0
					var wall_warning: float = 1.35 - 0.10 * float(difficulty_mode)
					spawn_closing_wall(-1, -1.0, wall_gap, wall_warning)
					autonomous_spawn_cursor = (threat_kind + 1) % 3
					return true
	return false


func _on_player_shield_changed(active: bool) -> void:
	if active and is_level_running:
		arena_fx.spawn_ring(player.global_position, 16.0, 34.0, 0.22, Color(0.82, 0.82, 0.82, 0.7), 1.5)


func _on_player_shield_blocked() -> void:
	arena_fx.spawn_ring(player.global_position, 16.0, 54.0, 0.30, Color(1.0, 1.0, 1.0, 0.9), 2.0)
	arena_fx.spawn_burst(player.global_position, 6, 190.0, Color(0.92, 0.92, 0.92, 1.0), 0.28, 8.0, 1.5)
	arena_grid.pulse(0.45)
	trigger_screen_shake(2.6, 0.14)


func _on_player_shield_broken() -> void:
	arena_fx.spawn_ring(player.global_position, 22.0, 92.0, 0.46, Color(0.92, 0.92, 0.92, 1.0), 2.5)
	arena_fx.spawn_burst(player.global_position, 18, 260.0, Color(0.85, 0.85, 0.85, 1.0), 0.42, 11.0, 2.0)
	arena_grid.pulse(0.7)
	trigger_screen_shake(5.0, 0.30)


func _on_player_damaged(_amount: int) -> void:
	arena_fx.spawn_burst(player.global_position, 12, 240.0, Color(0.95, 0.95, 0.95, 1.0), 0.36, 10.0, 2.0)
	arena_fx.spawn_ring(player.global_position, 8.0, 48.0, 0.34, Color(0.82, 0.82, 0.82, 1.0), 2.0)
	arena_grid.pulse(0.55)
	trigger_screen_shake(4.2, 0.24)


func trigger_screen_shake(strength: float = 3.0, duration: float = 0.2) -> void:
	_shake_strength = maxf(_shake_strength, maxf(strength, 0.0))
	_shake_duration = maxf(duration, 0.05)
	_shake_time = maxf(_shake_time, _shake_duration)


func _update_screen_shake(delta: float) -> void:
	if _shake_time <= 0.0:
		if game_camera.offset != Vector2.ZERO:
			game_camera.offset = Vector2.ZERO
		return
	_shake_time = maxf(0.0, _shake_time - maxf(delta, 0.0))
	var falloff: float = _shake_time / maxf(_shake_duration, 0.001)
	game_camera.offset = Vector2(
		_shake_rng.randf_range(-1.0, 1.0),
		_shake_rng.randf_range(-1.0, 1.0)
	) * _shake_strength * falloff
	if _shake_time <= 0.0:
		game_camera.offset = Vector2.ZERO
		_shake_strength = 0.0


func trigger_level_complete() -> void:
	if not is_level_running:
		return
	is_level_running = false
	SoundManager.stop_music()
	arena_grid.set_music_state(0.0, 0.0, 0)
	elapsed_time = level_duration
	hud.update_timer(elapsed_time, level_duration)
	_clear_beams()
	_shake_time = 0.0
	_shake_strength = 0.0
	game_camera.offset = Vector2.ZERO
	player.is_active = false

	var is_record: bool = GameManager.report_result(difficulty_mode, level_duration, true)
	var badge: String = " ★ NEW RECORD! ★" if is_record else ""
	hud.show_level_complete("%s: Survived 45.0s on %s%s" % [GameManager.get_player_name(), get_difficulty_name(), badge])
	SoundManager.play_sfx(&"victory", -1.5)
	level_completed.emit()


func _on_player_died() -> void:
	if not is_level_running:
		return
	is_level_running = false
	SoundManager.stop_music()
	arena_grid.set_music_state(0.0, 0.0, 0)
	_clear_beams()

	var is_record: bool = GameManager.report_result(difficulty_mode, elapsed_time, false)
	var badge: String = " ★ NEW RECORD! ★" if is_record else ""
	hud.show_game_over("%s: Survived %.1fs on %s%s" % [GameManager.get_player_name(), elapsed_time, get_difficulty_name(), badge])
	arena_grid.pulse(0.8)
	trigger_screen_shake(6.0, 0.35)
	SoundManager.play_sfx(&"game_over", -1.5)
	game_over.emit()


func _clear_beams() -> void:
	for child: Node in beam_container.get_children():
		child.set("is_hazard_active", false)
		if child is CanvasItem:
			(child as CanvasItem).visible = false
		child.queue_free()


func _on_viewport_resized() -> void:
	var rect_size: Vector2 = get_viewport_rect().size
	_arena_size = rect_size if (rect_size.x > 0.0 and rect_size.y > 0.0) else Vector2(1152.0, 648.0)
	background.size = _arena_size
	game_camera.position = _arena_size * 0.5
	arena_grid.set_arena_size(_arena_size)
	hud.sync_layout(_arena_size)


func _on_retry_pressed() -> void:
	SoundManager.play_sfx(&"menu")
	restart_level()


func _on_main_menu_pressed() -> void:
	is_level_running = false
	_shake_time = 0.0
	game_camera.offset = Vector2.ZERO
	SoundManager.stop_music()
	SoundManager.play_sfx(&"menu")
	GameManager.go_to_menu()


func _get_music_pitch_for_difficulty() -> float:
	match difficulty_mode:
		Difficulty.EASY:
			return 0.97
		Difficulty.HARD:
			return 1.04
		_:
			return 1.00


func _update_music_reactivity() -> void:
	if not SoundManager.is_music_playing():
		return
	var eff_time: float = elapsed_time * _get_music_pitch_for_difficulty()
	var beat_idx: int = int(floor(eff_time / SoundManager.BEAT_DURATION))
	var section: int = SoundManager.get_music_section(eff_time)
	var beat_phase: float = SoundManager.get_beat_phase(eff_time)
	var beat_energy: float = SoundManager.get_beat_intensity(eff_time)

	if beat_idx > _last_music_beat_idx:
		_last_music_beat_idx = beat_idx
		var base_pulse: float = 0.24 if (beat_idx % 4 == 0) else 0.12
		arena_grid.pulse(base_pulse * beat_energy)

	if section != current_music_section:
		current_music_section = section
		if section in [
			SoundManager.MusicSection.VERSE,
			SoundManager.MusicSection.CHORUS,
			SoundManager.MusicSection.CLIMAX,
			SoundManager.MusicSection.FINALE,
		]:
			var max_r: float = 260.0 if section >= SoundManager.MusicSection.CLIMAX else 190.0
			arena_fx.spawn_ring(_arena_size * 0.5, 24.0, max_r, 0.48, Color(0.82, 0.82, 0.82, 0.45), 2.2)
			arena_grid.pulse(0.58 if section >= SoundManager.MusicSection.CLIMAX else 0.42)

	arena_grid.set_music_state(beat_phase, beat_energy, current_music_section)
