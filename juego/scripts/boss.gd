extends Area2D

signal request_beam(spawn_pos: Vector2, angle_radians: float, width: float, warning_time: float, active_time: float)
signal request_circle(spawn_pos: Vector2, radius: float, fill_mode: int, warning_time: float, active_time: float)
signal request_projectile(spawn_pos: Vector2, direction: Vector2, speed: float, radius: float)
signal request_exploder(spawn_pos: Vector2, warning_time: float, burst_count: int, projectile_speed: float)
signal request_saw(mode: int, spawn_position: Vector2, direction: Vector2, speed: float, radius: float, warning: float, max_lifetime: float)
signal request_closing_wall(axis: int, gap_center: float, gap_size: float, warning: float, close_time: float, hold_time: float)
signal request_enemy(type: int, spawn_position: Vector2, speed_scale: float, warning: float, max_lifetime: float)
signal request_clear_hazards()
signal boss_slammed(at_position: Vector2, strength: float)
signal phase_changed(new_phase: int)

enum ActingState {
	COCKY_CONDUCTOR,
	FROZEN_DOUBLE_TAKE,
	FLOOR_SLAM_TANTRUM,
	ACCUSING_POINT,
	FAKE_OUT_COLLAPSE,
	HOLLOW_REBIRTH,
	EXHAUSTED_PANTING,
	TEMPLE_CLUTCH_PANIC,
	SILENT_SHATTER,
}

enum HandPose {
	OPEN,
	FIST,
	POINTER,
	CLAW,
}

enum HandDashStyle {
	FIST_ROCKET,
	CLAW_SWIPE,
	FLOOR_RAKE,
}

const MUSIC_BPM: float = 128.0
const BEAT_DURATION: float = 60.0 / MUSIC_BPM
const BEATS_PER_BAR: int = 4
const BARS_PER_PHASE: int = 8
const BEATS_PER_PHASE: int = BEATS_PER_BAR * BARS_PER_PHASE
const PHASE_DURATION: float = 15.0
const TOTAL_PHASES: int = 8
const TOTAL_BEATS: int = 256

const BODY_RADIUS: float = 42.0
const HAND_RADIUS: float = 26.0
const PLAYER_HIT_RADIUS: float = 14.0
const DEFAULT_ARENA_SIZE: Vector2 = Vector2(1152.0, 648.0)

const MAX_HAND_REPOSITION_SPEED: float = 640.0
const MAX_HAND_OVERDRIVE_SPEED: float = 760.0
const MAX_HAND_ROT_SPEED: float = 12.0
const MAX_BODY_REPOSITION_SPEED: float = 640.0
const MAX_BODY_OVERDRIVE_SPEED: float = 760.0
const SPAWN_GRACE_DURATION: float = 0.45

const EYE_OFFSET_LEFT: Vector2 = Vector2(-14.0, -5.0)
const EYE_OFFSET_RIGHT: Vector2 = Vector2(14.0, -5.0)
const PHASE_8_SILENT_SHATTER_BEAT: int = 252

var current_phase: int = 1
var acting_state: ActingState = ActingState.COCKY_CONDUCTOR
var is_body_hazardous: bool = false
var is_left_hand_hazardous: bool = false
var is_right_hand_hazardous: bool = false
var is_hand_hazardous: bool = false

var _arena_size: Vector2 = DEFAULT_ARENA_SIZE
var _elapsed_time: float = 0.0
var _last_sim_delta: float = 0.0
var _next_beat_idx: int = 0
var _last_beat_pulse: float = 0.0
var _player_pos: Vector2 = Vector2(576.0, 324.0)

var _body_pos: Vector2 = Vector2(576.0, 152.0)
var _body_target: Vector2 = Vector2(576.0, 152.0)
var _body_move_speed: float = 6.5

var _left_hand_pos: Vector2 = Vector2(441.0, 172.0)
var _right_hand_pos: Vector2 = Vector2(711.0, 172.0)
var _left_hand_rot: float = 0.0
var _right_hand_rot: float = 0.0
var _left_hand_pose: int = -1
var _right_hand_pose: int = -1
var _active_crown_phase: int = -1
var _phase5_hands_awake: bool = false

# Body lunges (Jaw-Chomp)
var _lunge_active: bool = false
var _lunge_telegraphing: bool = false
var _lunge_start: Vector2 = Vector2.ZERO
var _lunge_target: Vector2 = Vector2.ZERO
var _lunge_prev_pos: Vector2 = Vector2.ZERO
var _lunge_step_swept: bool = false
var _lunge_timer: float = 0.0
var _lunge_duration: float = 0.40
var _lunge_emit_slam: bool = false
var _lunge_wake_emitted: bool = false

# Unified per-hand state (index 0 = left, index 1 = right)
var _hand_slams: Array[Dictionary] = [_make_slam_state(), _make_slam_state()]
var _hand_dashes: Array[Dictionary] = [_make_dash_state(), _make_dash_state()]
var _hand_aims: Array[Dictionary] = [_make_aim_state(), _make_aim_state()]
var _hand_throw_flash: Array[float] = [0.0, 0.0]

# Coordinated two-hand attacks & overrides
var _pincer_timer: float = 0.0
var _pincer_left: Vector2 = Vector2.ZERO
var _pincer_right: Vector2 = Vector2.ZERO
var _pincer_mid: Vector2 = Vector2.ZERO

var _claw_orbit_timer: float = 0.0
var _claw_orbit_duration: float = 1.4
var _claw_orbit_angle: float = 0.0

var _wall_push_timer: float = 0.0
var _wall_push_duration: float = 1.6
var _wall_push_axis: int = 0
var _wall_push_gap_center: float = 576.0
var _wall_push_gap_size: float = 156.0

var _tether_beam_timer: float = 0.0
var _tether_left: Vector2 = Vector2.ZERO
var _tether_right: Vector2 = Vector2.ZERO

var _mouth_charge_timer: float = 0.0
var _mouth_beam_flash: float = 0.0

var _freeze_timer: float = 0.0
var _double_blink_timer: float = 0.0
var _aim_telegraph_timer: float = 0.0
var _locked_aim_pos: Vector2 = Vector2(576.0, 324.0)
var _flinch_timer: float = 0.0
var _laugh_timer: float = 0.0
var _white_flash: float = 0.0
var _crack_intensity: float = 0.0
var _inflate_amount: float = 0.0
var _silence_freeze: bool = false
var _spiral_angle: float = 0.0
var _rotisserie_angle: float = 0.0
var _anchor_index: int = 0
var _shattered: bool = false

var _thrown_seeds: Array[Dictionary] = []
var _afterimages: Array[Dictionary] = []
var _slash_arcs: Array[Dictionary] = []
var _rake_grooves: Array[Dictionary] = []
var _sweat_shards: Array[Dictionary] = []
var _sweat_spawn_timer: float = 0.0
var _shatter_shards: Array[Dictionary] = []
var _was_laughing: bool = false

@onready var face_rig: Node2D = $FaceRig
@onready var boss_glow: Polygon2D = $FaceRig/BossGlow
@onready var crown_polygon: Polygon2D = $FaceRig/CrownPolygon
@onready var body_polygon: Polygon2D = $FaceRig/BodyPolygon
@onready var void_polygon: Polygon2D = $FaceRig/VoidPolygon
@onready var left_eye_polygon: Polygon2D = $FaceRig/LeftEyePolygon
@onready var right_eye_polygon: Polygon2D = $FaceRig/RightEyePolygon
@onready var left_pupil_polygon: Polygon2D = $FaceRig/LeftPupilPolygon
@onready var right_pupil_polygon: Polygon2D = $FaceRig/RightPupilPolygon
@onready var left_brow_line: Line2D = $FaceRig/LeftBrowLine
@onready var right_brow_line: Line2D = $FaceRig/RightBrowLine
@onready var mouth_line: Line2D = $FaceRig/MouthLine

@onready var telegraph_line: Line2D = $TelegraphLine
@onready var body_collision: CollisionShape2D = $CollisionShape2D

@onready var left_hand: Area2D = $LeftHand
@onready var left_hand_polygon: Polygon2D = $LeftHand/HandPolygon
@onready var left_hand_void: Polygon2D = $LeftHand/HandVoid
@onready var left_hand_core: Polygon2D = $LeftHand/HandCore
@onready var left_hand_ring: Line2D = $LeftHand/HandRing
@onready var left_hand_collision: CollisionShape2D = $LeftHand/CollisionShape2D

@onready var right_hand: Area2D = $RightHand
@onready var right_hand_polygon: Polygon2D = $RightHand/HandPolygon
@onready var right_hand_void: Polygon2D = $RightHand/HandVoid
@onready var right_hand_core: Polygon2D = $RightHand/HandCore
@onready var right_hand_ring: Line2D = $RightHand/HandRing
@onready var right_hand_collision: CollisionShape2D = $RightHand/CollisionShape2D


static func _make_slam_state() -> Dictionary:
	return {
		"telegraph": 0.0,
		"active": 0.0,
		"timer": 0.0,
		"duration": 0.16,
		"start": Vector2.ZERO,
		"target": Vector2.ZERO,
		"impact_pending": false,
		"impact_mode": 0,
	}


static func _make_dash_state() -> Dictionary:
	return {
		"telegraph": 0.0,
		"active": false,
		"style": HandDashStyle.FIST_ROCKET,
		"start": Vector2.ZERO,
		"target": Vector2.ZERO,
		"prev": Vector2.ZERO,
		"swept": false,
		"timer": 0.0,
		"duration": 0.28,
		"burst": false,
		"rake_seeds_left": 0,
		"rake_next_p": 0.35,
	}


static func _make_aim_state() -> Dictionary:
	return {"timer": 0.0, "pos": Vector2.ZERO, "angle": 0.0}


func _ready() -> void:
	Shapes.apply_radial_glow(
		boss_glow,
		[28.0, 44.0, 62.0, 82.0, 102.0, 122.0],
		[0.45, 0.28, 0.16, 0.08, 0.03, 0.0],
		32,
		0.65
	)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not left_hand.body_entered.is_connected(_on_left_hand_body_entered):
		left_hand.body_entered.connect(_on_left_hand_body_entered)
	if not right_hand.body_entered.is_connected(_on_right_hand_body_entered):
		right_hand.body_entered.connect(_on_right_hand_body_entered)
	_build_base_geometry()
	reset_boss(_resolve_arena_size(Vector2.ZERO))


func reset_boss(arena_size: Vector2) -> void:
	_arena_size = _resolve_arena_size(arena_size)
	var s: Vector2 = _scale_vec()
	_elapsed_time = 0.0
	_last_sim_delta = 0.0
	_next_beat_idx = 0
	_last_beat_pulse = 0.0
	_player_pos = _arena_size * 0.5

	current_phase = 1
	acting_state = ActingState.COCKY_CONDUCTOR
	_phase5_hands_awake = false

	_body_pos = Vector2(576.0 * s.x, 152.0 * s.y)
	_body_target = _body_pos
	_body_move_speed = 6.5
	global_position = _body_pos
	scale = Vector2.ONE
	rotation = 0.0

	_left_hand_pos = _body_pos + Vector2(-145.0 * s.x, 22.0 * s.y)
	_right_hand_pos = _body_pos + Vector2(145.0 * s.x, 22.0 * s.y)
	_left_hand_rot = 0.0
	_right_hand_rot = 0.0
	left_hand.global_position = _left_hand_pos
	right_hand.global_position = _right_hand_pos

	_clear_active_attacks()

	_freeze_timer = 0.0
	_double_blink_timer = 0.0
	_aim_telegraph_timer = 0.0
	_locked_aim_pos = _player_pos
	_flinch_timer = 0.0
	_laugh_timer = 0.0
	_white_flash = 0.0
	_crack_intensity = 0.0
	_inflate_amount = 0.0
	_silence_freeze = false
	_spiral_angle = 0.0
	_rotisserie_angle = 0.0
	_anchor_index = 0
	_shattered = false

	_sweat_shards.clear()
	_sweat_spawn_timer = 0.0
	_shatter_shards.clear()
	_was_laughing = false

	_sync_hazard_flags()

	visible = true
	face_rig.visible = true
	face_rig.position = Vector2.ZERO
	face_rig.rotation = 0.0
	face_rig.scale = Vector2.ONE
	left_hand.visible = true
	right_hand.visible = true
	telegraph_line.visible = false
	telegraph_line.clear_points()

	_active_crown_phase = -1
	_left_hand_pose = -1
	_right_hand_pose = -1
	_set_crown_for_phase(1)
	_set_hand_pose(true, HandPose.OPEN)
	_set_hand_pose(false, HandPose.OPEN)
	_set_eye_polygons(false)
	_apply_visuals(0.0)
	queue_redraw()


func _clear_active_attacks() -> void:
	_lunge_active = false
	_lunge_telegraphing = false
	_lunge_prev_pos = _body_pos
	_lunge_step_swept = false
	_lunge_timer = 0.0
	_lunge_emit_slam = false
	_lunge_wake_emitted = false

	for idx: int in range(2):
		_hand_slams[idx] = _make_slam_state()
		_hand_dashes[idx] = _make_dash_state()
		_hand_aims[idx] = _make_aim_state()
		_hand_throw_flash[idx] = 0.0

	_pincer_timer = 0.0
	_claw_orbit_timer = 0.0
	_claw_orbit_angle = 0.0
	_wall_push_timer = 0.0
	_tether_beam_timer = 0.0
	_mouth_charge_timer = 0.0
	_mouth_beam_flash = 0.0

	_thrown_seeds.clear()
	_afterimages.clear()
	_slash_arcs.clear()
	_rake_grooves.clear()


func simulate_boss(delta: float, elapsed_time: float, arena_size: Vector2, player_node: Node2D) -> void:
	_arena_size = _resolve_arena_size(arena_size)
	var safe_delta: float = maxf(delta, 0.0)
	_last_sim_delta = safe_delta
	_elapsed_time = maxf(elapsed_time, 0.0)
	if player_node != null and is_instance_valid(player_node):
		_player_pos = player_node.global_position
	else:
		_player_pos = _arena_size * 0.5

	if _shattered:
		return

	_tick_timers(safe_delta)

	var target_beat_idx: int = mini(int(floor((_elapsed_time + 0.000001) / BEAT_DURATION)), TOTAL_BEATS - 1)
	while _next_beat_idx <= target_beat_idx:
		_on_beat(_next_beat_idx)
		_next_beat_idx += 1

	_update_thrown_seeds(safe_delta)
	_update_timed_fx(_afterimages, safe_delta)
	_update_timed_fx(_slash_arcs, safe_delta)
	_update_timed_fx(_rake_grooves, safe_delta)
	_update_motion(safe_delta)
	_update_sweat_shards(safe_delta)
	_sync_hazard_flags()
	_check_contact_damage(player_node)
	_apply_visuals(safe_delta)
	queue_redraw()


func on_player_shield_blocked() -> void:
	if _shattered or acting_state == ActingState.FAKE_OUT_COLLAPSE or acting_state == ActingState.SILENT_SHATTER:
		return
	_flinch_timer = 0.34
	_apply_visuals(0.0)
	queue_redraw()


func on_player_damaged() -> void:
	if _shattered or acting_state == ActingState.FAKE_OUT_COLLAPSE or acting_state == ActingState.SILENT_SHATTER:
		return
	_laugh_timer = 0.72
	_apply_visuals(0.0)
	queue_redraw()


func shatter() -> void:
	if _shattered:
		return
	_shattered = true
	acting_state = ActingState.SILENT_SHATTER
	_phase5_hands_awake = false
	_clear_active_attacks()
	_flinch_timer = 0.0
	_laugh_timer = 0.0
	_sync_hazard_flags()

	face_rig.visible = false
	left_hand.visible = false
	right_hand.visible = false
	telegraph_line.visible = false

	_shatter_shards.clear()
	for i: int in range(20):
		var ang: float = TAU * float(i) / 20.0 + float(i % 3) * 0.14
		var dist: float = 24.0 + float((i * 19) % 46)
		var sz: float = 7.0 + float(i % 4) * 3.5
		var gray: float = 0.72 + float(i % 3) * 0.14
		_shatter_shards.append({
			"offset": Vector2.from_angle(ang) * dist,
			"rot": ang + float(i) * 0.5,
			"size": sz,
			"gray": gray,
		})

	boss_slammed.emit(global_position, 1.0)
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	_handle_contact_body(body, is_body_hazardous)


func _on_left_hand_body_entered(body: Node2D) -> void:
	_handle_contact_body(body, is_left_hand_hazardous)


func _on_right_hand_body_entered(body: Node2D) -> void:
	_handle_contact_body(body, is_right_hand_hazardous)


func _handle_contact_body(body: Node2D, hazardous: bool) -> void:
	if _elapsed_time < SPAWN_GRACE_DURATION:
		return
	if hazardous and body != null and body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(1)


func _on_beat(beat_idx: int) -> void:
	var new_phase: int = clampi((beat_idx / BEATS_PER_PHASE) + 1, 1, TOTAL_PHASES)
	if new_phase != current_phase:
		_enter_phase(new_phase)

	var beat_in_phase: int = beat_idx % BEATS_PER_PHASE
	_last_beat_pulse = 1.0

	match current_phase:
		1:
			_choreograph_phase_1(beat_in_phase)
		2:
			_choreograph_phase_2(beat_in_phase)
		3:
			_choreograph_phase_3(beat_in_phase)
		4:
			_choreograph_phase_4(beat_in_phase)
		5:
			_choreograph_phase_5(beat_in_phase)
		6:
			_choreograph_phase_6(beat_in_phase)
		7:
			_choreograph_phase_7(beat_in_phase)
		8:
			_choreograph_phase_8(beat_idx, beat_in_phase)


func _enter_phase(new_phase: int) -> void:
	current_phase = new_phase
	_phase5_hands_awake = false
	_clear_active_attacks()
	_aim_telegraph_timer = 0.0
	_silence_freeze = false
	_inflate_amount = 0.0
	telegraph_line.visible = false
	_set_crown_for_phase(new_phase)

	var s: Vector2 = _scale_vec()
	var center: Vector2 = _arena_size * 0.5

	match new_phase:
		1:
			acting_state = ActingState.COCKY_CONDUCTOR
			_body_target = Vector2(576.0 * s.x, 152.0 * s.y)
			_body_move_speed = 6.5
			_crack_intensity = 0.0
		2:
			acting_state = ActingState.FROZEN_DOUBLE_TAKE
			_body_target = Vector2(576.0 * s.x, 152.0 * s.y)
			_body_move_speed = 7.0
			_freeze_timer = 0.40
			_double_blink_timer = 0.62
		3:
			acting_state = ActingState.FLOOR_SLAM_TANTRUM
			_body_target = Vector2(576.0 * s.x, 148.0 * s.y)
			_body_move_speed = 8.0
		4:
			acting_state = ActingState.ACCUSING_POINT
			_body_target = center
			_body_move_speed = 5.5
		5:
			acting_state = ActingState.FAKE_OUT_COLLAPSE
			_flinch_timer = 0.0
			_laugh_timer = 0.0
			_white_flash = 1.0
			_crack_intensity = 0.65
			_body_target = Vector2(576.0 * s.x, 470.0 * s.y)
			_body_move_speed = 7.5
			request_clear_hazards.emit()
		6:
			acting_state = ActingState.HOLLOW_REBIRTH
			_crack_intensity = 0.35
			_anchor_index = 0
			_body_target = Vector2(576.0 * s.x, 175.0 * s.y)
			_body_move_speed = 9.0
		7:
			acting_state = ActingState.EXHAUSTED_PANTING
			_crack_intensity = 0.55
			_body_target = Vector2(576.0 * s.x, 175.0 * s.y)
			_body_move_speed = 5.0
		8:
			acting_state = ActingState.TEMPLE_CLUTCH_PANIC
			_crack_intensity = 0.85
			_body_target = Vector2(576.0 * s.x, 180.0 * s.y)
			_body_move_speed = 7.5

	_sync_hazard_flags()
	phase_changed.emit(new_phase)


# ------------------------------------------------------------------------------
# PHASE 1: COCKY CONDUCTOR — Fingertip Beams, 1-2 Rocket Fists & Claw Backhand
# ------------------------------------------------------------------------------
func _choreograph_phase_1(beat_in_phase: int) -> void:
	var s: Vector2 = _scale_vec()
	var aim_pos: Vector2 = _clamp_hazard_target(_player_pos, s)
	if beat_in_phase in [2, 6, 14, 18]:
		var use_left: bool = beat_in_phase in [2, 14]
		var shooter_x: float = 125.0 * s.x if use_left else 1027.0 * s.x
		var shooter_pos: Vector2 = Vector2(shooter_x, clampf(aim_pos.y, 135.0 * s.y, 505.0 * s.y))
		_aim_hand_pointer(use_left, shooter_pos, (aim_pos - shooter_pos).angle(), BEAT_DURATION * 2.05)
	elif beat_in_phase in [4, 8, 16, 20]:
		var use_left: bool = beat_in_phase in [4, 16]
		var idx: int = 0 if use_left else 1
		var origin: Vector2 = Vector2(_hand_aims[idx]["pos"])
		var ang: float = float(_hand_aims[idx]["angle"])
		_fire_hand_beam(use_left, origin, ang, 44.0, 0.98, 0.34)
		var ring_target: Vector2 = _clamp_hazard_target(_player_pos + Vector2(90.0 * s.x if use_left else -90.0 * s.x, 0.0), s)
		_launch_seed(not use_left, "hand", ring_target, 0.36, &"circle", [ring_target, 78.0, beat_in_phase % 3, 1.05, 0.35])
	elif beat_in_phase == 9:
		# 1-2 Rocket Fist Combo windup (>= 0.55s telegraph)
		var end_l: Vector2 = _clamp_combat_bounds(_player_pos + Vector2(-45.0 * s.x, 0.0), s)
		var end_r: Vector2 = _clamp_combat_bounds(_player_pos + Vector2(45.0 * s.x, 0.0), s)
		_start_hand_telegraph(true, _clamp_combat_bounds(_body_pos + Vector2(-115.0 * s.x, 12.0 * s.y), s), end_l, BEAT_DURATION * 1.95, HandDashStyle.FIST_ROCKET)
		_start_hand_telegraph(false, _clamp_combat_bounds(_body_pos + Vector2(115.0 * s.x, 12.0 * s.y), s), end_r, BEAT_DURATION * 2.95, HandDashStyle.FIST_ROCKET)
	elif beat_in_phase == 11:
		_start_hand_dash(true, 0.26, true, HandDashStyle.FIST_ROCKET)
	elif beat_in_phase == 12:
		_start_hand_dash(false, 0.26, true, HandDashStyle.FIST_ROCKET)
	elif beat_in_phase in [22, 24]:
		var target_c: Vector2 = _clamp_hazard_target(_player_pos, s)
		_launch_seed(beat_in_phase == 22, "hand", target_c, 0.34, &"circle", [target_c, 84.0, 1, 0.95, 0.35])
	elif beat_in_phase == 25:
		# Full-Arena Claw Backhand Sweep telegraph (>= 0.55s)
		var lane_y: float = clampf(_player_pos.y, 135.0 * s.y, 505.0 * s.y)
		_start_hand_telegraph(false, Vector2(987.0 * s.x, lane_y), Vector2(165.0 * s.x, lane_y), BEAT_DURATION * 1.95, HandDashStyle.CLAW_SWIPE)
	elif beat_in_phase == 27:
		_start_hand_dash(false, 0.32, false, HandDashStyle.CLAW_SWIPE)


# ------------------------------------------------------------------------------
# PHASE 2: FROZEN DOUBLE-TAKE — Tether Beams, 1-2 Fists, Claw Swipe & Mouth Fans
# ------------------------------------------------------------------------------
func _choreograph_phase_2(beat_in_phase: int) -> void:
	var s: Vector2 = _scale_vec()
	if beat_in_phase in [2, 6, 10, 14]:
		var lane_y: float = clampf(_player_pos.y, 135.0 * s.y, 505.0 * s.y)
		_tether_left = Vector2(125.0 * s.x, lane_y)
		_tether_right = Vector2(1027.0 * s.x, lane_y)
		_tether_beam_timer = BEAT_DURATION * 2.05
		_aim_hand_pointer(true, _tether_left, 0.0, BEAT_DURATION * 2.05)
		_aim_hand_pointer(false, _tether_right, PI, BEAT_DURATION * 2.05)
	elif beat_in_phase in [4, 8, 12, 16]:
		var mid: Vector2 = (_tether_left + _tether_right) * 0.5
		request_beam.emit(mid, (_tether_right - _tether_left).angle(), 48.0, 0.92, 0.34)
		boss_slammed.emit(mid, 0.36)
		if beat_in_phase in [8, 16]:
			var drop_pos: Vector2 = _clamp_hazard_target(_player_pos, s)
			_launch_seed(beat_in_phase == 8, "hand", drop_pos, 0.32, &"circle", [drop_pos, 82.0, 0, 0.95, 0.35])
	elif beat_in_phase == 17:
		var end_l: Vector2 = _clamp_combat_bounds(_player_pos, s)
		var end_r: Vector2 = _clamp_combat_bounds(_player_pos + Vector2(60.0 * s.x, -40.0 * s.y), s)
		_start_hand_telegraph(true, Vector2(175.0 * s.x, end_l.y), end_l, BEAT_DURATION * 1.95, HandDashStyle.FIST_ROCKET)
		_start_hand_telegraph(false, Vector2(977.0 * s.x, end_r.y), end_r, BEAT_DURATION * 2.95, HandDashStyle.FIST_ROCKET)
	elif beat_in_phase == 18:
		_locked_aim_pos = _player_pos
		_aim_telegraph_timer = 0.42
		_mouth_charge_timer = 0.45
	elif beat_in_phase == 19:
		_start_hand_dash(true, 0.25, true, HandDashStyle.FIST_ROCKET)
		_fire_mouth_fan(_locked_aim_pos, 5, deg_to_rad(15.0), 370.0)
	elif beat_in_phase == 20:
		_start_hand_dash(false, 0.25, true, HandDashStyle.FIST_ROCKET)
	elif beat_in_phase == 21:
		var sweep_y: float = clampf(_player_pos.y, 135.0 * s.y, 505.0 * s.y)
		_start_hand_telegraph(true, Vector2(165.0 * s.x, sweep_y), Vector2(987.0 * s.x, sweep_y), BEAT_DURATION * 1.95, HandDashStyle.CLAW_SWIPE)
	elif beat_in_phase == 23:
		_start_hand_dash(true, 0.30, true, HandDashStyle.CLAW_SWIPE)
	elif beat_in_phase in [25, 29]:
		var use_left: bool = beat_in_phase == 25
		var side_x: float = (280.0 if use_left else 872.0) * s.x
		var hand_top: Vector2 = Vector2(side_x, 135.0 * s.y)
		_aim_hand_pointer(use_left, hand_top, PI * 0.5, BEAT_DURATION * 1.15)
	elif beat_in_phase in [26, 30]:
		var use_left: bool = beat_in_phase == 26
		var idx: int = 0 if use_left else 1
		var hand_top: Vector2 = Vector2(_hand_aims[idx]["pos"])
		_fire_hand_beam(use_left, hand_top, PI * 0.5, 44.0, 0.95, 0.32)
		if beat_in_phase == 26:
			var end_p: Vector2 = _clamp_combat_bounds(_player_pos, s)
			_start_hand_telegraph(false, Vector2(977.0 * s.x, end_p.y), end_p, BEAT_DURATION * 1.95, HandDashStyle.FIST_ROCKET)
	elif beat_in_phase == 27:
		_locked_aim_pos = _player_pos
		_aim_telegraph_timer = 0.40
		_mouth_charge_timer = 0.42
	elif beat_in_phase == 28:
		_start_hand_dash(false, 0.25, true, HandDashStyle.FIST_ROCKET)
		_fire_mouth_fan(_locked_aim_pos, 5, deg_to_rad(15.0), 370.0)


# ------------------------------------------------------------------------------
# PHASE 3: FLOOR-SLAM TANTRUM — Ground-Slam Pounces, Hand-Pushed Walls & Chaser
# ------------------------------------------------------------------------------
func _choreograph_phase_3(beat_in_phase: int) -> void:
	var s: Vector2 = _scale_vec()
	var center: Vector2 = _arena_size * 0.5
	if beat_in_phase in [1, 9, 17, 25]:
		var is_left: bool = beat_in_phase in [1, 17]
		_start_hand_slam_telegraph(is_left, _player_pos, BEAT_DURATION * 1.95)

	if beat_in_phase in [3, 11, 19, 27]:
		var is_left: bool = beat_in_phase in [3, 19]
		_start_hand_slam_active(is_left, 0.16, 1)

	if beat_in_phase == 4:
		var gap_x: float = clampf(_player_pos.x, 220.0 * s.x, _arena_size.x - 220.0 * s.x)
		_start_wall_push(0, gap_x, 168.0, 1.25, 0.60, 0.85)
		var exp_pos: Vector2 = _clamp_hazard_target(Vector2(220.0 * s.x, 450.0 * s.y), s)
		_launch_seed(true, "hand", exp_pos, 0.38, &"exploder", [exp_pos, 1.05, 8, 340.0])
	elif beat_in_phase == 12:
		var enemy_pos: Vector2 = _clamp_hazard_target(Vector2(900.0 * s.x, 180.0 * s.y) if _player_pos.x < center.x else Vector2(250.0 * s.x, 180.0 * s.y), s)
		_launch_seed(false, "mouth", enemy_pos, 0.42, &"enemy", [0, enemy_pos, 1.0, 0.80, 7.5])
	elif beat_in_phase == 14:
		var exp_pos_r: Vector2 = _clamp_hazard_target(Vector2(932.0 * s.x, 180.0 * s.y), s)
		_launch_seed(false, "hand", exp_pos_r, 0.38, &"exploder", [exp_pos_r, 1.05, 8, 340.0])
	elif beat_in_phase == 20:
		var gap_y: float = clampf(_player_pos.y, 175.0 * s.y, _arena_size.y - 175.0 * s.y)
		_start_wall_push(1, gap_y, 164.0, 1.20, 0.58, 0.85)
		_mouth_beam_flash = 0.35
		request_beam.emit(_body_pos, PI * 0.25, 46.0, 0.95, 0.32)
		request_beam.emit(_body_pos, PI * 0.75, 46.0, 0.95, 0.32)
		boss_slammed.emit(_body_pos, 0.44)
	elif beat_in_phase in [8, 28, 30]:
		_mouth_beam_flash = 0.35
		request_beam.emit(_body_pos, PI * 0.25, 46.0, 0.95, 0.32)
		request_beam.emit(_body_pos, PI * 0.75, 46.0, 0.95, 0.32)
		boss_slammed.emit(_body_pos, 0.44)


# ------------------------------------------------------------------------------
# PHASE 4: ACCUSING POINT — Rotisserie + Snipes + Nutcracker + Jaw-Chomp Lunges
# ------------------------------------------------------------------------------
func _choreograph_phase_4(beat_in_phase: int) -> void:
	var s: Vector2 = _scale_vec()
	var center: Vector2 = _arena_size * 0.5
	if beat_in_phase <= 18:
		_body_target = center
		_body_move_speed = 7.0
		if beat_in_phase >= 2 and beat_in_phase % 2 == 0 and beat_in_phase != 18:
			_rotisserie_angle += PI / 6.0
			_mouth_beam_flash = 0.28
			request_beam.emit(_body_pos, _rotisserie_angle, 44.0, 0.92, 0.28)
		if beat_in_phase in [4, 8, 12]:
			var use_left: bool = beat_in_phase == 8
			var side_x: float = 125.0 * s.x if use_left else 1027.0 * s.x
			var hand_origin: Vector2 = Vector2(side_x, clampf(_player_pos.y, 135.0 * s.y, 495.0 * s.y))
			var ang: float = (_player_pos - hand_origin).angle()
			_aim_hand_pointer(use_left, hand_origin, ang, BEAT_DURATION * 2.05)
		elif beat_in_phase in [6, 10, 14]:
			var use_left: bool = beat_in_phase == 10
			var idx: int = 0 if use_left else 1
			var hand_origin: Vector2 = Vector2(_hand_aims[idx]["pos"])
			var ang: float = float(_hand_aims[idx]["angle"])
			_fire_hand_beam(use_left, hand_origin, ang, 40.0, 0.96, 0.30)
		elif beat_in_phase == 16:
			_start_pincer_telegraph(_player_pos, BEAT_DURATION * 1.95)
		elif beat_in_phase == 18:
			_execute_pincer_clap()
		return

	match beat_in_phase:
		19:
			_body_target = Vector2(200.0 * s.x, 195.0 * s.y)
			_body_move_speed = 9.5
		20:
			_start_lunge_telegraph(Vector2(200.0 * s.x, 195.0 * s.y), Vector2(952.0 * s.x, 195.0 * s.y))
		22:
			SoundManager.play_sfx(&"boss_roar", -3.0)
			_start_lunge_dash(Vector2(200.0 * s.x, 195.0 * s.y), Vector2(952.0 * s.x, 195.0 * s.y), 0.38, true)
		23:
			_body_target = Vector2(952.0 * s.x, 445.0 * s.y)
			_body_move_speed = 9.5
		24:
			_start_lunge_telegraph(Vector2(952.0 * s.x, 445.0 * s.y), Vector2(200.0 * s.x, 445.0 * s.y))
		26:
			_start_lunge_dash(Vector2(952.0 * s.x, 445.0 * s.y), Vector2(200.0 * s.x, 445.0 * s.y), 0.38, true)
		27:
			var lane_y: float = _pick_phase_4_lunge_3_y(s)
			_body_target = Vector2(200.0 * s.x, lane_y)
			_body_move_speed = 9.5
		28:
			_start_lunge_telegraph(Vector2(200.0 * s.x, _body_target.y), Vector2(952.0 * s.x, _body_target.y))
		30:
			_start_lunge_dash(Vector2(200.0 * s.x, _body_target.y), Vector2(952.0 * s.x, _body_target.y), 0.38, true)
		31:
			_lunge_telegraphing = false
			_lunge_active = false


func _pick_phase_4_lunge_3_y(s: Vector2) -> float:
	if _player_pos.y < 290.0 * s.y:
		return clampf(_player_pos.y, 150.0 * s.y, 250.0 * s.y)
	if _player_pos.y > 358.0 * s.y:
		return clampf(_player_pos.y, 398.0 * s.y, 490.0 * s.y)
	return 225.0 * s.y


# ------------------------------------------------------------------------------
# PHASE 5: FAKE-OUT COLLAPSE — Limp Head + Possessed Hands (Beat >= 8) + Supernova
# ------------------------------------------------------------------------------
func _choreograph_phase_5(beat_in_phase: int) -> void:
	var s: Vector2 = _scale_vec()
	var center: Vector2 = _arena_size * 0.5
	if beat_in_phase >= 8 and not _phase5_hands_awake:
		_phase5_hands_awake = true
		_hand_throw_flash[0] = 0.45
		_hand_throw_flash[1] = 0.45
		_sync_hazard_flags()

	if beat_in_phase == 8:
		var saw_a: Vector2 = Vector2(180.0 * s.x, 165.0 * s.y)
		var saw_b: Vector2 = Vector2(972.0 * s.x, 165.0 * s.y)
		_launch_seed(true, "hand", saw_a, 0.36, &"saw", [0, saw_a, Vector2(0.84, 0.54).normalized(), 215.0, 28.0, 0.85, 9.5])
		_launch_seed(false, "hand", saw_b, 0.36, &"saw", [0, saw_b, Vector2(-0.84, 0.54).normalized(), 215.0, 28.0, 0.85, 9.5])
	elif beat_in_phase == 9:
		var lane_y: float = clampf(_player_pos.y, 140.0 * s.y, 505.0 * s.y)
		_start_hand_telegraph(true, Vector2(165.0 * s.x, lane_y), Vector2(987.0 * s.x, lane_y), BEAT_DURATION * 1.95, HandDashStyle.CLAW_SWIPE)
	elif beat_in_phase == 11:
		_start_hand_dash(true, 0.30, false, HandDashStyle.CLAW_SWIPE)
	elif beat_in_phase in [14, 21]:
		var use_left: bool = beat_in_phase == 14
		var target_c: Vector2 = _clamp_hazard_target(_player_pos, s)
		_launch_seed(use_left, "hand", target_c, 0.34, &"circle", [target_c, 76.0, 2, 0.95, 0.32])
	elif beat_in_phase == 17:
		var lane_y: float = clampf(_player_pos.y, 140.0 * s.y, 505.0 * s.y)
		_start_hand_telegraph(false, Vector2(987.0 * s.x, lane_y), Vector2(165.0 * s.x, lane_y), BEAT_DURATION * 1.95, HandDashStyle.CLAW_SWIPE)
	elif beat_in_phase == 19:
		_start_hand_dash(false, 0.30, false, HandDashStyle.CLAW_SWIPE)
	elif beat_in_phase >= 24 and beat_in_phase <= 26:
		_inflate_amount = float(beat_in_phase - 23) * 0.32
		_body_target = center
		_body_move_speed = 6.5
	elif beat_in_phase == 28 or beat_in_phase == 29:
		_silence_freeze = true
		_inflate_amount = 1.0
	elif beat_in_phase == 30:
		_silence_freeze = false
		_inflate_amount = 0.0
		_white_flash = 1.0
		_body_target = Vector2(576.0 * s.x, 180.0 * s.y)
		_body_move_speed = 11.0
		_mouth_beam_flash = 0.45
		SoundManager.play_sfx(&"boss_roar", -1.5)
		boss_slammed.emit(_body_pos, 0.88)
		_launch_seed(true, "mouth", _body_pos, 0.16, &"circle", [_body_pos, 146.0, 0, 0.65, 0.35])
		for i: int in range(4):
			request_beam.emit(_body_pos, float(i) * (PI * 0.25), 44.0, 0.90, 0.35)


# ------------------------------------------------------------------------------
# PHASE 6: HOLLOW-EYED REBIRTH — Quadrant Lunges, Spinning Claw Orbit & Pincers
# ------------------------------------------------------------------------------
func _choreograph_phase_6(beat_in_phase: int) -> void:
	var s: Vector2 = _scale_vec()
	var anchors: Array[Vector2] = [
		Vector2(260.0 * s.x, 190.0 * s.y),
		Vector2(892.0 * s.x, 190.0 * s.y),
		Vector2(892.0 * s.x, 458.0 * s.y),
		Vector2(260.0 * s.x, 458.0 * s.y),
	]
	if beat_in_phase in [3, 9, 15, 21]:
		var next_anchor: Vector2 = anchors[_anchor_index % 4]
		_start_lunge_telegraph(_body_pos, next_anchor)
	elif beat_in_phase in [4, 10, 16, 22]:
		var target_anchor: Vector2 = anchors[_anchor_index % 4]
		if beat_in_phase == 4:
			SoundManager.play_sfx(&"boss_roar", -3.0)
		_start_lunge_dash(_body_pos, target_anchor, 0.26, true)
		_mouth_beam_flash = 0.30
		request_beam.emit(target_anchor, PI * 0.25, 46.0, 0.92, 0.32)
		request_beam.emit(target_anchor, PI * 0.75, 46.0, 0.92, 0.32)
		_anchor_index += 1
	elif beat_in_phase == 5 or beat_in_phase == 17:
		# Spinning Claw Orbit (buzzsaw arms expanding 115px -> 195px)
		_claw_orbit_duration = BEAT_DURATION * 2.8
		_claw_orbit_timer = _claw_orbit_duration
	elif beat_in_phase == 11:
		_start_pincer_telegraph(_player_pos, BEAT_DURATION * 1.95)
	elif beat_in_phase == 13:
		_execute_pincer_clap()
	elif beat_in_phase == 23:
		var gap_x: float = clampf(_player_pos.x, 220.0 * s.x, _arena_size.x - 220.0 * s.x)
		_start_wall_push(0, gap_x, 162.0, 1.05, 0.50, 0.85)
		var pulsar_pos: Vector2 = _clamp_hazard_target(Vector2(220.0 * s.x, 200.0 * s.y) if _player_pos.x > _arena_size.x * 0.5 else Vector2(932.0 * s.x, 200.0 * s.y), s)
		_launch_seed(false, "mouth", pulsar_pos, 0.38, &"enemy", [3, pulsar_pos, 1.05, 0.80, 7.5])
	elif beat_in_phase == 27:
		var gap_y: float = clampf(_player_pos.y, 175.0 * s.y, _arena_size.y - 175.0 * s.y)
		_start_wall_push(1, gap_y, 160.0, 1.05, 0.50, 0.85)
		_fire_mouth_fan(_player_pos, 5, deg_to_rad(14.0), 380.0)


# ------------------------------------------------------------------------------
# PHASE 7: EXHAUSTED PANTING — Double Ground Pounds & Heavy Floor-Dragging Rakes
# ------------------------------------------------------------------------------
func _choreograph_phase_7(beat_in_phase: int) -> void:
	var s: Vector2 = _scale_vec()
	if beat_in_phase in [2, 10]:
		var target_c: Vector2 = _clamp_combat_bounds(_player_pos, s)
		_start_hand_slam_telegraph(true, target_c + Vector2(-120.0 * s.x, 0.0), BEAT_DURATION * 1.95)
		_start_hand_slam_telegraph(false, target_c + Vector2(120.0 * s.x, 0.0), BEAT_DURATION * 1.95)
	elif beat_in_phase in [4, 12]:
		_start_hand_slam_active(true, 0.16, 2)
		_start_hand_slam_active(false, 0.16, 2)
		_fire_radial_mouth_ring(6, 315.0, 0.22 * float(beat_in_phase / 4))
	elif beat_in_phase in [5, 13]:
		# Heavy Floor-Dragging Hand Rakes telegraph (>= 0.55s)
		var lane_a: float = clampf(_player_pos.y, 175.0 * s.y, 495.0 * s.y)
		var lane_b: float = clampf(485.0 * s.y if lane_a < 360.0 * s.y else 240.0 * s.y, 175.0 * s.y, 495.0 * s.y)
		_start_hand_telegraph(true, Vector2(175.0 * s.x, lane_a), Vector2(977.0 * s.x, lane_a), BEAT_DURATION * 1.95, HandDashStyle.FLOOR_RAKE)
		_start_hand_telegraph(false, Vector2(977.0 * s.x, lane_b), Vector2(175.0 * s.x, lane_b), BEAT_DURATION * 1.95, HandDashStyle.FLOOR_RAKE)
	elif beat_in_phase in [7, 15]:
		_start_hand_dash(true, 0.44, false, HandDashStyle.FLOOR_RAKE)
		_start_hand_dash(false, 0.44, false, HandDashStyle.FLOOR_RAKE)
		boss_slammed.emit(_arena_size * 0.5, 0.48)
	elif beat_in_phase == 18:
		var s1: Vector2 = Vector2(170.0 * s.x, 145.0 * s.y)
		var s2: Vector2 = Vector2(982.0 * s.x, 490.0 * s.y)
		_launch_seed(true, "hand", s1, 0.34, &"saw", [0, s1, Vector2(0.82, 0.57).normalized(), 225.0, 28.0, 0.85, 7.5])
		_launch_seed(false, "hand", s2, 0.34, &"saw", [0, s2, Vector2(-0.82, -0.57).normalized(), 225.0, 28.0, 0.85, 7.5])
	elif beat_in_phase == 22:
		var shooter_p: Vector2 = Vector2(125.0 * s.x, clampf(_player_pos.y, 135.0 * s.y, 495.0 * s.y))
		_aim_hand_pointer(true, shooter_p, (_player_pos - shooter_p).angle(), BEAT_DURATION * 2.05)
	elif beat_in_phase in [20, 24, 28]:
		_fire_radial_mouth_ring(6, 330.0, (PI / 6.0) if beat_in_phase == 24 else 0.0)
		if beat_in_phase == 24:
			var shooter_p: Vector2 = Vector2(_hand_aims[0]["pos"])
			var aim_ang: float = float(_hand_aims[0]["angle"])
			_fire_hand_beam(true, shooter_p, aim_ang, 44.0, 0.95, 0.32)
	elif beat_in_phase == 27:
		var sweep_y: float = clampf(_player_pos.y, 145.0 * s.y, 505.0 * s.y)
		_start_hand_telegraph(false, Vector2(987.0 * s.x, sweep_y), Vector2(165.0 * s.x, sweep_y), BEAT_DURATION * 1.95, HandDashStyle.CLAW_SWIPE)
	elif beat_in_phase == 29:
		_start_hand_dash(false, 0.30, true, HandDashStyle.CLAW_SWIPE)


# ------------------------------------------------------------------------------
# PHASE 8: TEMPLE-CLUTCH PANIC & SILENT SHATTER — All-Out Barrage, Lunges & Fists
# ------------------------------------------------------------------------------
func _choreograph_phase_8(beat_idx: int, beat_in_phase: int) -> void:
	var s: Vector2 = _scale_vec()
	var center: Vector2 = _arena_size * 0.5
	if beat_idx >= PHASE_8_SILENT_SHATTER_BEAT:
		if acting_state != ActingState.SILENT_SHATTER:
			acting_state = ActingState.SILENT_SHATTER
			_clear_active_attacks()
			_flinch_timer = 0.0
			_laugh_timer = 0.0
			_sync_hazard_flags()
			telegraph_line.visible = false
			request_clear_hazards.emit()
		return

	if beat_in_phase in [4, 8, 12, 16, 20]:
		var is_cardinal: bool = (beat_in_phase == 4 or beat_in_phase == 12 or beat_in_phase == 20)
		var base_ang: float = 0.0 if is_cardinal else PI * 0.25
		_mouth_beam_flash = 0.30
		request_beam.emit(_body_pos, base_ang, 46.0, 0.92, 0.32)
		request_beam.emit(_body_pos, base_ang + PI * 0.5, 46.0, 0.92, 0.32)
		if is_cardinal:
			var exp_pos: Vector2 = _clamp_hazard_target(Vector2(200.0 * s.x, 165.0 * s.y) if beat_in_phase != 12 else Vector2(952.0 * s.x, 485.0 * s.y), s)
			_launch_seed(beat_in_phase != 12, "hand", exp_pos, 0.34, &"exploder", [exp_pos, 1.05, 8, 330.0])
		for i: int in range(4):
			var dir: Vector2 = Vector2.from_angle(_spiral_angle + TAU * float(i) / 4.0)
			request_projectile.emit(_body_pos + dir * 48.0, dir, 335.0, 9.5)
		_spiral_angle += deg_to_rad(22.0)

	if beat_in_phase == 5:
		var end_l: Vector2 = _clamp_combat_bounds(_player_pos, s)
		var end_r: Vector2 = _clamp_combat_bounds(_player_pos + Vector2(55.0 * s.x, -45.0 * s.y), s)
		_start_hand_telegraph(true, Vector2(180.0 * s.x, end_l.y), end_l, BEAT_DURATION * 1.95, HandDashStyle.FIST_ROCKET)
		_start_hand_telegraph(false, Vector2(972.0 * s.x, end_r.y), end_r, BEAT_DURATION * 2.95, HandDashStyle.FIST_ROCKET)
	elif beat_in_phase == 7:
		_start_hand_dash(true, 0.24, true, HandDashStyle.FIST_ROCKET)
	elif beat_in_phase == 8:
		_start_hand_dash(false, 0.24, true, HandDashStyle.FIST_ROCKET)
	elif beat_in_phase == 13:
		var lane_y: float = clampf(_player_pos.y, 165.0 * s.y, 485.0 * s.y)
		_body_target = Vector2(200.0 * s.x, lane_y)
		_body_move_speed = 11.0
	elif beat_in_phase == 14:
		_start_lunge_telegraph(Vector2(200.0 * s.x, _body_target.y), Vector2(952.0 * s.x, _body_target.y))
	elif beat_in_phase == 15:
		SoundManager.play_sfx(&"boss_roar", -2.5)
		_start_lunge_dash(Vector2(200.0 * s.x, _body_target.y), Vector2(952.0 * s.x, _body_target.y), 0.34, true)
	elif beat_in_phase == 16:
		_body_target = center
		_body_move_speed = 9.0
		var sweep_y: float = clampf(_player_pos.y, 145.0 * s.y, 505.0 * s.y)
		_start_hand_telegraph(false, Vector2(987.0 * s.x, sweep_y), Vector2(165.0 * s.x, sweep_y), BEAT_DURATION * 1.95, HandDashStyle.CLAW_SWIPE)
	elif beat_in_phase == 18:
		_start_hand_dash(false, 0.28, true, HandDashStyle.CLAW_SWIPE)
	elif beat_in_phase == 21:
		_start_pincer_telegraph(_player_pos, BEAT_DURATION * 1.95)
	elif beat_in_phase == 23:
		_execute_pincer_clap()
	elif beat_in_phase == 24:
		SoundManager.play_sfx(&"boss_roar", -2.0)
		_mouth_beam_flash = 0.45
		for i: int in range(4):
			request_beam.emit(_body_pos, float(i) * (PI * 0.25), 44.0, 0.98, 0.35)


# ------------------------------------------------------------------------------
# ATTACK HELPERS (SEEDS, POINTER BEAMS, ROCKET FISTS, SWIPES, RAKES, PINCER)
# ------------------------------------------------------------------------------
func _launch_seed(is_left: bool, source_kind: String, target_pos: Vector2, travel_time: float, payload_type: StringName, payload_args: Array) -> void:
	var start_pos: Vector2 = _body_pos
	if source_kind == "hand":
		start_pos = _left_hand_pos if is_left else _right_hand_pos
		_hand_throw_flash[0 if is_left else 1] = 0.32
	else:
		_mouth_charge_timer = maxf(_mouth_charge_timer, 0.28)
	_thrown_seeds.append({
		"start": start_pos,
		"pos": start_pos,
		"target": target_pos,
		"elapsed": 0.0,
		"duration": maxf(travel_time, 0.12),
		"payload_type": payload_type,
		"payload_args": payload_args,
		"trail": PackedVector2Array([start_pos]),
	})


func _update_thrown_seeds(delta: float) -> void:
	for i: int in range(_thrown_seeds.size() - 1, -1, -1):
		var sd: Dictionary = _thrown_seeds[i]
		sd["elapsed"] = float(sd["elapsed"]) + delta
		var dur: float = float(sd["duration"])
		var p: float = clampf(float(sd["elapsed"]) / dur, 0.0, 1.0)
		var start_p: Vector2 = Vector2(sd["start"])
		var end_p: Vector2 = Vector2(sd["target"])
		var arc_offset: Vector2 = Vector2(0.0, -sin(p * PI) * 52.0)
		var cur_p: Vector2 = start_p.lerp(end_p, p) + arc_offset
		sd["pos"] = cur_p
		var tr: PackedVector2Array = sd["trail"]
		tr.append(cur_p)
		if tr.size() > 8:
			tr.remove_at(0)
		sd["trail"] = tr
		if p >= 1.0:
			_deliver_seed_payload(sd)
			_thrown_seeds.remove_at(i)


func _deliver_seed_payload(sd: Dictionary) -> void:
	var ptype: StringName = StringName(sd["payload_type"])
	var args: Array = sd["payload_args"]
	match ptype:
		&"circle":
			request_circle.emit(Vector2(args[0]), float(args[1]), int(args[2]), float(args[3]), float(args[4]))
		&"exploder":
			request_exploder.emit(Vector2(args[0]), float(args[1]), int(args[2]), float(args[3]))
		&"saw":
			request_saw.emit(int(args[0]), Vector2(args[1]), Vector2(args[2]), float(args[3]), float(args[4]), float(args[5]), float(args[6]))
		&"enemy":
			request_enemy.emit(int(args[0]), Vector2(args[1]), float(args[2]), float(args[3]), float(args[4]))


func _aim_hand_pointer(is_left: bool, pos: Vector2, angle: float, duration: float) -> void:
	var idx: int = 0 if is_left else 1
	_hand_aims[idx]["timer"] = duration
	_hand_aims[idx]["pos"] = _clamp_perimeter_bounds(pos, _scale_vec())
	_hand_aims[idx]["angle"] = angle


func _start_hand_slam_telegraph(is_left: bool, target_pos: Vector2, duration: float) -> void:
	var s: Vector2 = _scale_vec()
	var idx: int = 0 if is_left else 1
	_hand_slams[idx]["target"] = _clamp_combat_bounds(target_pos, s)
	_hand_slams[idx]["telegraph"] = maxf(duration, BEAT_DURATION * 1.45)
	_hand_slams[idx]["active"] = 0.0
	_hand_slams[idx]["timer"] = 0.0
	_hand_slams[idx]["impact_pending"] = false


func _start_hand_slam_active(is_left: bool, duration: float = 0.16, impact_mode: int = 1) -> void:
	var idx: int = 0 if is_left else 1
	var sl: Dictionary = _hand_slams[idx]
	var cur_pos: Vector2 = _left_hand_pos if is_left else _right_hand_pos
	var target_pos: Vector2 = Vector2(sl["target"])
	var min_safe_duration: float = cur_pos.distance_to(target_pos) / 600.0
	var safe_dur: float = maxf(maxf(duration, 0.14), min_safe_duration)
	sl["telegraph"] = 0.0
	sl["duration"] = safe_dur
	sl["active"] = safe_dur
	sl["timer"] = 0.0
	sl["start"] = cur_pos
	sl["impact_pending"] = true
	sl["impact_mode"] = impact_mode


func _fire_hand_beam(is_left: bool, origin: Vector2, angle: float, width: float, warning_time: float, active_time: float) -> void:
	var dir: Vector2 = Vector2.from_angle(angle)
	var center_pos: Vector2 = origin + dir * 48.0
	var idx: int = 0 if is_left else 1
	_hand_throw_flash[idx] = 0.30
	_hand_aims[idx]["timer"] = maxf(float(_hand_aims[idx]["timer"]), 0.36)
	request_beam.emit(center_pos, angle, width, warning_time, active_time)


func _fire_mouth_fan(aim_target: Vector2, count: int, step_angle: float, speed: float) -> void:
	var to_aim: Vector2 = aim_target - _body_pos
	var aim_dir: Vector2 = to_aim.normalized() if to_aim.length_squared() > 1.0 else Vector2.DOWN
	var half: float = float(count - 1) * 0.5
	_mouth_beam_flash = 0.30
	for i: int in range(count):
		var offset: float = (float(i) - half) * step_angle
		var dir: Vector2 = aim_dir.rotated(offset)
		request_projectile.emit(_body_pos + dir * 48.0, dir, speed, 10.0)


func _fire_radial_mouth_ring(count: int, speed: float, angle_offset: float) -> void:
	_mouth_beam_flash = 0.28
	for i: int in range(count):
		var dir: Vector2 = Vector2.from_angle(angle_offset + TAU * float(i) / float(count))
		request_projectile.emit(_body_pos + dir * 48.0, dir, speed, 10.0)


func _start_hand_telegraph(is_left: bool, from_pos: Vector2, to_pos: Vector2, duration: float, style: int = HandDashStyle.FIST_ROCKET) -> void:
	var s: Vector2 = _scale_vec()
	var d: Dictionary = _hand_dashes[0 if is_left else 1]
	d["telegraph"] = duration
	d["active"] = false
	d["style"] = style
	d["start"] = _clamp_combat_bounds(from_pos, s)
	d["target"] = _clamp_combat_bounds(to_pos, s)


func _start_hand_dash(is_left: bool, duration: float, burst_on_impact: bool, style: int = HandDashStyle.FIST_ROCKET) -> void:
	var idx: int = 0 if is_left else 1
	var d: Dictionary = _hand_dashes[idx]
	d["telegraph"] = 0.0
	d["active"] = true
	d["style"] = style
	d["timer"] = 0.0
	d["duration"] = maxf(duration, 0.05)
	d["burst"] = burst_on_impact
	d["rake_seeds_left"] = 2 if style == HandDashStyle.FLOOR_RAKE else 0
	d["rake_next_p"] = 0.34
	var cur_pos: Vector2 = _left_hand_pos if is_left else _right_hand_pos
	d["start"] = cur_pos
	d["prev"] = cur_pos


func _start_pincer_telegraph(mid_pos: Vector2, duration: float) -> void:
	var s: Vector2 = _scale_vec()
	var clamped_mid: Vector2 = Vector2(
		clampf(mid_pos.x, 340.0 * s.x, 812.0 * s.x),
		clampf(mid_pos.y, 135.0 * s.y, 505.0 * s.y)
	)
	_pincer_timer = duration
	_pincer_mid = clamped_mid
	_pincer_left = _clamp_combat_bounds(clamped_mid - Vector2(210.0 * s.x, 0.0), s)
	_pincer_right = _clamp_combat_bounds(clamped_mid + Vector2(210.0 * s.x, 0.0), s)


func _execute_pincer_clap() -> void:
	_pincer_timer = 0.0
	var s: Vector2 = _scale_vec()
	_hand_dashes[0]["start"] = _pincer_left
	_hand_dashes[0]["target"] = _clamp_combat_bounds(_pincer_mid - Vector2(28.0 * s.x, 0.0), s)
	_hand_dashes[1]["start"] = _pincer_right
	_hand_dashes[1]["target"] = _clamp_combat_bounds(_pincer_mid + Vector2(28.0 * s.x, 0.0), s)
	_start_hand_dash(true, 0.22, false, HandDashStyle.FIST_ROCKET)
	_start_hand_dash(false, 0.22, false, HandDashStyle.FIST_ROCKET)
	boss_slammed.emit(_pincer_mid, 0.62)
	for i: int in range(4):
		var dir: Vector2 = Vector2.from_angle(float(i) * PI * 0.5 + PI * 0.25)
		request_projectile.emit(_pincer_mid + dir * 24.0, dir, 300.0, 8.5)
	_launch_seed(true, "hand", _pincer_mid, 0.22, &"circle", [_pincer_mid, 92.0, 0, 0.85, 0.35])


func _start_wall_push(axis: int, gap_center: float, gap_size: float, warning: float, close_time: float, hold_time: float) -> void:
	_wall_push_axis = axis
	_wall_push_gap_center = gap_center
	_wall_push_gap_size = gap_size
	_wall_push_duration = warning + close_time + 0.3
	_wall_push_timer = _wall_push_duration
	request_closing_wall.emit(axis, gap_center, gap_size, warning, close_time, hold_time)


func _start_lunge_telegraph(from_pos: Vector2, to_pos: Vector2) -> void:
	var s: Vector2 = _scale_vec()
	_lunge_telegraphing = true
	_lunge_active = false
	_lunge_start = _clamp_combat_bounds(from_pos, s)
	_lunge_target = _clamp_combat_bounds(to_pos, s)
	_body_target = _lunge_start
	telegraph_line.visible = true
	telegraph_line.points = PackedVector2Array([Vector2.ZERO, _lunge_target - global_position])


func _start_lunge_dash(_from_pos: Vector2, to_pos: Vector2, duration: float, emit_slam_on_finish: bool) -> void:
	var s: Vector2 = _scale_vec()
	_lunge_telegraphing = false
	_lunge_active = true
	_claw_orbit_timer = 0.0
	_lunge_start = _body_pos
	_lunge_target = _clamp_combat_bounds(to_pos, s)
	_lunge_timer = 0.0
	_lunge_duration = maxf(duration, 0.05)
	_lunge_emit_slam = emit_slam_on_finish
	_lunge_wake_emitted = false
	_body_target = _lunge_target
	global_position = _body_pos
	telegraph_line.visible = false


func _clamp_hazard_target(pos: Vector2, s: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, 90.0 * s.x, _arena_size.x - 90.0 * s.x),
		clampf(pos.y, 90.0 * s.y, _arena_size.y - 90.0 * s.y)
	)


func _clamp_perimeter_bounds(pos: Vector2, s: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, 125.0 * s.x, 1027.0 * s.x),
		clampf(pos.y, 120.0 * s.y, 515.0 * s.y)
	)


func _clamp_combat_bounds(pos: Vector2, s: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, 165.0 * s.x, 987.0 * s.x),
		clampf(pos.y, 120.0 * s.y, 515.0 * s.y)
	)


func _clamp_dash_target(pos: Vector2, s: Vector2) -> Vector2:
	return _clamp_combat_bounds(pos, s)


# ------------------------------------------------------------------------------
# TIMERS, MOTION & COLLISIONS
# ------------------------------------------------------------------------------
func _tick_timers(delta: float) -> void:
	_last_beat_pulse = maxf(0.0, _last_beat_pulse - delta * 3.8)
	_freeze_timer = maxf(0.0, _freeze_timer - delta)
	_double_blink_timer = maxf(0.0, _double_blink_timer - delta)
	_aim_telegraph_timer = maxf(0.0, _aim_telegraph_timer - delta)
	_flinch_timer = maxf(0.0, _flinch_timer - delta)
	_laugh_timer = maxf(0.0, _laugh_timer - delta)
	_white_flash = maxf(0.0, _white_flash - delta * 3.2)

	for idx: int in range(2):
		_hand_slams[idx]["telegraph"] = maxf(0.0, float(_hand_slams[idx]["telegraph"]) - delta)
		_hand_dashes[idx]["telegraph"] = maxf(0.0, float(_hand_dashes[idx]["telegraph"]) - delta)
		_hand_aims[idx]["timer"] = maxf(0.0, float(_hand_aims[idx]["timer"]) - delta)
		_hand_throw_flash[idx] = maxf(0.0, _hand_throw_flash[idx] - delta)

	_pincer_timer = maxf(0.0, _pincer_timer - delta)
	_claw_orbit_timer = maxf(0.0, _claw_orbit_timer - delta)
	_wall_push_timer = maxf(0.0, _wall_push_timer - delta)
	_tether_beam_timer = maxf(0.0, _tether_beam_timer - delta)
	_mouth_charge_timer = maxf(0.0, _mouth_charge_timer - delta)
	_mouth_beam_flash = maxf(0.0, _mouth_beam_flash - delta)


func _update_timed_fx(items: Array[Dictionary], delta: float) -> void:
	for i: int in range(items.size() - 1, -1, -1):
		items[i]["life"] = float(items[i]["life"]) - delta
		if float(items[i]["life"]) <= 0.0:
			items.remove_at(i)


func _update_motion(delta: float) -> void:
	var s: Vector2 = _scale_vec()
	_lunge_step_swept = false
	if _lunge_active:
		_lunge_prev_pos = _body_pos
		_lunge_step_swept = true
		_lunge_timer += delta
		var progress: float = clampf(_lunge_timer / maxf(_lunge_duration, 0.001), 0.0, 1.0)
		_body_pos = _lunge_start.lerp(_lunge_target, ease(progress, 0.45))
		global_position = _body_pos
		_afterimages.append({"pos": _body_pos, "radius": 38.0, "rot": 0.0, "shape": "oct", "life": 0.16, "max_life": 0.16})
		if progress >= 0.48 and not _lunge_wake_emitted:
			_lunge_wake_emitted = true
			var l_dir: Vector2 = (_lunge_target - _lunge_start).normalized()
			var perp: Vector2 = Vector2(-l_dir.y, l_dir.x)
			request_projectile.emit(_body_pos + perp * 38.0, perp, 290.0, 9.0)
			request_projectile.emit(_body_pos - perp * 38.0, -perp, 290.0, 9.0)
		if progress >= 1.0:
			_lunge_active = false
			_body_pos = _lunge_target
			_body_target = _lunge_target
			global_position = _lunge_target
			if _lunge_emit_slam:
				_lunge_emit_slam = false
				boss_slammed.emit(_lunge_target, 0.55)
	else:
		var bob: Vector2 = Vector2.ZERO
		if acting_state == ActingState.COCKY_CONDUCTOR:
			bob = Vector2(0.0, sin(_elapsed_time * TAU / (BEAT_DURATION * 2.0)) * 8.0 * s.y)
		elif acting_state == ActingState.EXHAUSTED_PANTING:
			bob = Vector2(0.0, sin(_elapsed_time * TAU / BEAT_DURATION) * 6.0 * s.y)
		var desired_pos: Vector2 = _body_target + bob
		if _freeze_timer > 0.0 or _silence_freeze:
			desired_pos = _body_pos
		var t: float = clampf(_body_move_speed * delta, 0.0, 1.0)
		var step_pos: Vector2 = _body_pos.lerp(desired_pos, t)
		var max_body_speed: float = MAX_BODY_OVERDRIVE_SPEED if current_phase == 8 else MAX_BODY_REPOSITION_SPEED
		_body_pos = _body_pos.move_toward(step_pos, max_body_speed * delta)
		global_position = _body_pos

	if _lunge_telegraphing:
		telegraph_line.visible = true
		telegraph_line.points = PackedVector2Array([Vector2.ZERO, _lunge_target - global_position])
	elif _aim_telegraph_timer > 0.0:
		telegraph_line.visible = true
		telegraph_line.points = PackedVector2Array([Vector2.ZERO, _locked_aim_pos - global_position])
	else:
		telegraph_line.visible = false

	_update_hands_motion(delta, s)


func _update_hands_motion(delta: float, s: Vector2) -> void:
	var target_left: Vector2 = _body_pos + Vector2(-145.0 * s.x, 22.0 * s.y)
	var target_right: Vector2 = _body_pos + Vector2(145.0 * s.x, 22.0 * s.y)
	var rot_left: float = 0.0
	var rot_right: float = 0.0
	var pose_left: HandPose = HandPose.OPEN
	var pose_right: HandPose = HandPose.OPEN

	# Base emotional idle poses
	match acting_state:
		ActingState.COCKY_CONDUCTOR:
			var tap: float = sin(_elapsed_time * TAU / BEAT_DURATION)
			target_left = _body_pos + Vector2(-145.0 * s.x, (22.0 + tap * 14.0) * s.y)
			target_right = _body_pos + Vector2(145.0 * s.x, (22.0 - tap * 14.0) * s.y)
		ActingState.FROZEN_DOUBLE_TAKE:
			target_left = _body_pos + Vector2(-155.0 * s.x, 12.0 * s.y)
			target_right = _body_pos + Vector2(155.0 * s.x, 12.0 * s.y)
		ActingState.FLOOR_SLAM_TANTRUM:
			pose_left = HandPose.FIST
			pose_right = HandPose.FIST
			target_left = _body_pos + Vector2(-140.0 * s.x, 70.0 * s.y)
			target_right = _body_pos + Vector2(140.0 * s.x, 70.0 * s.y)
		ActingState.ACCUSING_POINT:
			pose_left = HandPose.FIST
			pose_right = HandPose.POINTER
			var tremble: Vector2 = Vector2(sin(_elapsed_time * 42.0) * 3.5, cos(_elapsed_time * 38.0) * 3.5)
			target_left = _clamp_combat_bounds(_body_pos + Vector2(-115.0 * s.x, 28.0 * s.y) + tremble, s)
			target_right = _clamp_combat_bounds(_body_pos + Vector2(135.0 * s.x, -24.0 * s.y), s)
			rot_right = (_player_pos - target_right).angle()
		ActingState.FAKE_OUT_COLLAPSE:
			pose_left = HandPose.CLAW if _phase5_hands_awake else HandPose.OPEN
			pose_right = HandPose.CLAW if _phase5_hands_awake else HandPose.OPEN
			var twitch: Vector2 = Vector2(sin(_elapsed_time * 32.0) * 9.0, 0.0) if (_inflate_amount > 0.05 or _phase5_hands_awake) and not _silence_freeze else Vector2.ZERO
			target_left = Vector2(430.0 * s.x, 510.0 * s.y) - twitch
			target_right = Vector2(722.0 * s.x, 510.0 * s.y) + twitch
			rot_left = -0.35
			rot_right = 0.35
		ActingState.HOLLOW_REBIRTH:
			pose_left = HandPose.CLAW
			pose_right = HandPose.CLAW
			target_left = _clamp_combat_bounds(_body_pos + Vector2(-130.0 * s.x, 30.0 * s.y), s)
			target_right = _clamp_combat_bounds(_body_pos + Vector2(130.0 * s.x, 30.0 * s.y), s)
			rot_left = sin(_elapsed_time * 3.0) * 0.35
			rot_right = -sin(_elapsed_time * 3.0) * 0.35
		ActingState.EXHAUSTED_PANTING:
			pose_left = HandPose.FIST
			pose_right = HandPose.FIST
			target_left = _body_pos + Vector2(-145.0 * s.x, 85.0 * s.y)
			target_right = _body_pos + Vector2(145.0 * s.x, 85.0 * s.y)
		ActingState.TEMPLE_CLUTCH_PANIC, ActingState.SILENT_SHATTER:
			pose_left = HandPose.CLAW
			pose_right = HandPose.CLAW
			var shake: Vector2 = Vector2(sin(_elapsed_time * 55.0) * 4.0, cos(_elapsed_time * 47.0) * 4.0) if acting_state == ActingState.TEMPLE_CLUTCH_PANIC else Vector2.ZERO
			target_left = _clamp_combat_bounds(_body_pos + Vector2(-58.0 * s.x, -14.0 * s.y) + shake, s)
			target_right = _clamp_combat_bounds(_body_pos + Vector2(58.0 * s.x, -14.0 * s.y) - shake, s)
			rot_left = 0.35
			rot_right = -0.35

	# Active attack overrides (priority: Dash > Slam > Wall Push > Pincer > Claw Orbit > Pointer)
	if _claw_orbit_timer > 0.0:
		var orbit_p: float = 1.0 - clampf(_claw_orbit_timer / maxf(_claw_orbit_duration, 0.001), 0.0, 1.0)
		var orbit_r: float = lerpf(115.0, 195.0, sin(orbit_p * PI * 0.5)) * minf(s.x, s.y)
		_claw_orbit_angle += delta * 3.2
		pose_left = HandPose.CLAW
		pose_right = HandPose.CLAW
		target_left = _clamp_combat_bounds(_body_pos + Vector2.from_angle(_claw_orbit_angle) * orbit_r, s)
		target_right = _clamp_combat_bounds(_body_pos + Vector2.from_angle(_claw_orbit_angle + PI) * orbit_r, s)
		rot_left = _claw_orbit_angle + PI * 0.5
		rot_right = _claw_orbit_angle + PI * 1.5
		_slash_arcs.append({"pos": _left_hand_pos, "rot": rot_left, "radius": 34.0, "life": 0.14, "max_life": 0.14})
		_slash_arcs.append({"pos": _right_hand_pos, "rot": rot_right, "radius": 34.0, "life": 0.14, "max_life": 0.14})

	if _wall_push_timer > 0.0:
		var push_p: float = 1.0 - clampf(_wall_push_timer / maxf(_wall_push_duration, 0.001), 0.0, 1.0)
		pose_left = HandPose.CLAW
		pose_right = HandPose.CLAW
		if _wall_push_axis == 0:
			var edge_l: float = lerpf(80.0 * s.x, _wall_push_gap_center - _wall_push_gap_size * 0.5 - 32.0, ease(push_p, 0.7))
			var edge_r: float = lerpf(_arena_size.x - 80.0 * s.x, _wall_push_gap_center + _wall_push_gap_size * 0.5 + 32.0, ease(push_p, 0.7))
			target_left = Vector2(edge_l, _arena_size.y * 0.5)
			target_right = Vector2(edge_r, _arena_size.y * 0.5)
			rot_left = 0.0
			rot_right = PI
		else:
			var edge_t: float = lerpf(120.0 * s.y, _wall_push_gap_center - _wall_push_gap_size * 0.5 - 32.0, ease(push_p, 0.7))
			var edge_b: float = lerpf(_arena_size.y - 120.0 * s.y, _wall_push_gap_center + _wall_push_gap_size * 0.5 + 32.0, ease(push_p, 0.7))
			target_left = Vector2(_arena_size.x * 0.5, edge_t)
			target_right = Vector2(_arena_size.x * 0.5, edge_b)
			rot_left = PI * 0.5
			rot_right = -PI * 0.5

	if _pincer_timer > 0.0:
		pose_left = HandPose.FIST
		pose_right = HandPose.FIST
		target_left = _pincer_left
		target_right = _pincer_right
		rot_left = 0.0
		rot_right = PI

	if float(_hand_aims[0]["timer"]) > 0.0:
		pose_left = HandPose.POINTER
		target_left = Vector2(_hand_aims[0]["pos"])
		rot_left = float(_hand_aims[0]["angle"])
	if float(_hand_aims[1]["timer"]) > 0.0:
		pose_right = HandPose.POINTER
		target_right = Vector2(_hand_aims[1]["pos"])
		rot_right = float(_hand_aims[1]["angle"])

	if float(_hand_slams[0]["telegraph"]) > 0.0:
		pose_left = HandPose.FIST
		target_left = _clamp_combat_bounds(Vector2(_hand_slams[0]["target"]) + Vector2(0.0, -75.0 * s.y), s)
		rot_left = PI * 0.5
	elif float(_hand_slams[0]["active"]) > 0.0:
		pose_left = HandPose.FIST
		target_left = Vector2(_hand_slams[0]["target"])
		rot_left = PI * 0.5

	if float(_hand_slams[1]["telegraph"]) > 0.0:
		pose_right = HandPose.FIST
		target_right = _clamp_combat_bounds(Vector2(_hand_slams[1]["target"]) + Vector2(0.0, -75.0 * s.y), s)
		rot_right = PI * 0.5
	elif float(_hand_slams[1]["active"]) > 0.0:
		pose_right = HandPose.FIST
		target_right = Vector2(_hand_slams[1]["target"])
		rot_right = PI * 0.5

	if float(_hand_dashes[0]["telegraph"]) > 0.0:
		pose_left = _pose_for_dash_style(int(_hand_dashes[0]["style"]))
		target_left = Vector2(_hand_dashes[0]["start"])
		rot_left = (Vector2(_hand_dashes[0]["target"]) - target_left).angle()
	if float(_hand_dashes[1]["telegraph"]) > 0.0:
		pose_right = _pose_for_dash_style(int(_hand_dashes[1]["style"]))
		target_right = Vector2(_hand_dashes[1]["start"])
		rot_right = (Vector2(_hand_dashes[1]["target"]) - target_right).angle()

	var left_res: Array = _step_hand_motion(true, _left_hand_pos, _left_hand_rot, target_left, rot_left, pose_left, delta)
	_left_hand_pos = left_res[0]
	_left_hand_rot = float(left_res[1])
	pose_left = int(left_res[2]) as HandPose

	var right_res: Array = _step_hand_motion(false, _right_hand_pos, _right_hand_rot, target_right, rot_right, pose_right, delta)
	_right_hand_pos = right_res[0]
	_right_hand_rot = float(right_res[1])
	pose_right = int(right_res[2]) as HandPose

	left_hand.global_position = _left_hand_pos
	left_hand.rotation = _left_hand_rot
	right_hand.global_position = _right_hand_pos
	right_hand.rotation = _right_hand_rot

	_set_hand_pose(true, pose_left)
	_set_hand_pose(false, pose_right)


func _pose_for_dash_style(style: int) -> HandPose:
	if style == HandDashStyle.CLAW_SWIPE:
		return HandPose.CLAW
	return HandPose.FIST


func _step_hand_motion(is_left: bool, cur_pos: Vector2, cur_rot: float, target_pos: Vector2, target_rot: float, pose: HandPose, delta: float) -> Array:
	var idx: int = 0 if is_left else 1
	var d: Dictionary = _hand_dashes[idx]
	var sl: Dictionary = _hand_slams[idx]
	d["swept"] = false
	if not bool(d["active"]):
		if float(sl["active"]) > 0.0:
			var dur: float = maxf(float(sl["duration"]), 0.001)
			sl["timer"] = float(sl["timer"]) + delta
			var p: float = clampf(float(sl["timer"]) / dur, 0.0, 1.0)
			sl["active"] = maxf(0.0, dur - float(sl["timer"]))
			var start_p: Vector2 = Vector2(sl["start"])
			var end_p: Vector2 = Vector2(sl["target"])
			var next_pos: Vector2 = start_p.lerp(end_p, ease(p, 1.8))
			var next_rot: float = rotate_toward(cur_rot, PI * 0.5, MAX_HAND_ROT_SPEED * delta)
			if p >= 1.0:
				sl["active"] = 0.0
				next_pos = end_p
				if bool(sl["impact_pending"]):
					sl["impact_pending"] = false
					var mode: int = int(sl["impact_mode"])
					if mode == 1:
						boss_slammed.emit(end_p, 0.52)
						for i: int in range(4):
							var proj_dir: Vector2 = Vector2.from_angle(float(i) * PI * 0.5 + PI * 0.25)
							request_projectile.emit(end_p + proj_dir * 24.0, proj_dir, 305.0, 9.0)
					elif mode == 2:
						boss_slammed.emit(end_p, 0.45)
						_launch_seed(is_left, "hand", end_p, 0.22, &"circle", [end_p, 86.0, 0, 1.00, 0.35])
			return [next_pos, next_rot, HandPose.FIST]

		var max_speed: float = MAX_HAND_OVERDRIVE_SPEED if current_phase == 8 else MAX_HAND_REPOSITION_SPEED
		return [
			cur_pos.move_toward(target_pos, max_speed * delta),
			rotate_toward(cur_rot, target_rot, MAX_HAND_ROT_SPEED * delta),
			pose,
		]

	var style: int = int(d["style"])
	var active_pose: HandPose = _pose_for_dash_style(style)
	var start_p: Vector2 = Vector2(d["start"])
	var end_p: Vector2 = Vector2(d["target"])
	var dash_dir: Vector2 = (end_p - start_p).normalized() if end_p.distance_squared_to(start_p) > 1.0 else Vector2.RIGHT
	var dash_ang: float = dash_dir.angle()

	d["prev"] = cur_pos
	d["swept"] = true
	d["timer"] = float(d["timer"]) + delta
	var p: float = clampf(float(d["timer"]) / maxf(float(d["duration"]), 0.001), 0.0, 1.0)
	var eased_p: float = p if style == HandDashStyle.FLOOR_RAKE else ease(p, 0.42)
	var next_pos: Vector2 = start_p.lerp(end_p, eased_p)

	if style == HandDashStyle.CLAW_SWIPE:
		_slash_arcs.append({"pos": next_pos, "rot": dash_ang, "radius": 38.0, "life": 0.18, "max_life": 0.18})
	elif style == HandDashStyle.FLOOR_RAKE:
		_rake_grooves.append({"from": cur_pos, "to": next_pos, "life": 0.48, "max_life": 0.48})
		if int(d["rake_seeds_left"]) > 0 and p >= float(d["rake_next_p"]):
			d["rake_seeds_left"] = int(d["rake_seeds_left"]) - 1
			d["rake_next_p"] = float(d["rake_next_p"]) + 0.34
			var shock_p: Vector2 = _clamp_combat_bounds(next_pos, _scale_vec())
			_launch_seed(is_left, "hand", shock_p, 0.18, &"circle", [shock_p, 74.0, 0, 0.92, 0.32])
	_afterimages.append({"pos": next_pos, "radius": 22.0, "rot": dash_ang, "shape": "diamond", "life": 0.15, "max_life": 0.15})

	if p >= 1.0:
		d["active"] = false
		next_pos = end_p
		boss_slammed.emit(end_p, 0.48)
		if bool(d["burst"]):
			d["burst"] = false
			if style == HandDashStyle.CLAW_SWIPE:
				for i: int in range(-1, 2):
					var dir: Vector2 = (-dash_dir).rotated(float(i) * 0.35)
					request_projectile.emit(end_p + dir * 24.0, dir, 315.0, 9.0)
			else:
				var rot_off: float = 0.0 if is_left else PI / 6.0
				for i: int in range(6):
					var dir: Vector2 = Vector2.from_angle(TAU * float(i) / 6.0 + rot_off)
					request_projectile.emit(end_p + dir * 24.0, dir, 305.0, 8.5)

	return [next_pos, dash_ang, active_pose]


func _sync_hazard_flags() -> void:
	if _shattered or acting_state == ActingState.SILENT_SHATTER:
		is_body_hazardous = false
		is_left_hand_hazardous = false
		is_right_hand_hazardous = false
		is_hand_hazardous = false
	elif acting_state == ActingState.FAKE_OUT_COLLAPSE:
		is_body_hazardous = false
		is_left_hand_hazardous = _phase5_hands_awake
		is_right_hand_hazardous = _phase5_hands_awake
		is_hand_hazardous = is_left_hand_hazardous or is_right_hand_hazardous
	else:
		is_body_hazardous = true
		is_left_hand_hazardous = true
		is_right_hand_hazardous = true
		is_hand_hazardous = true
	_sync_collision_shapes()


func _sync_collision_shapes() -> void:
	body_collision.disabled = not is_body_hazardous
	left_hand_collision.disabled = not is_left_hand_hazardous
	right_hand_collision.disabled = not is_right_hand_hazardous


func _check_contact_damage(player_node: Node2D) -> void:
	if _elapsed_time < SPAWN_GRACE_DURATION and (_elapsed_time > 0.0 or _last_sim_delta > 0.0):
		return
	if player_node == null or not is_instance_valid(player_node) or not player_node.has_method("take_damage"):
		return
	var p_radius_val: Variant = player_node.get("PLAYER_HALF_SIZE")
	var player_radius: float = float(p_radius_val) if p_radius_val != null else PLAYER_HIT_RADIUS
	var p_pos: Vector2 = player_node.global_position

	if is_body_hazardous:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p_pos, _lunge_prev_pos, global_position) if _lunge_step_swept else global_position
		if closest.distance_to(p_pos) <= BODY_RADIUS + player_radius:
			player_node.take_damage(1)
			return
	if is_left_hand_hazardous:
		var ld: Dictionary = _hand_dashes[0]
		var closest_l: Vector2 = Geometry2D.get_closest_point_to_segment(p_pos, Vector2(ld["prev"]), left_hand.global_position) if bool(ld["swept"]) else left_hand.global_position
		if closest_l.distance_to(p_pos) <= HAND_RADIUS + player_radius:
			player_node.take_damage(1)
			return
	if is_right_hand_hazardous:
		var rd: Dictionary = _hand_dashes[1]
		var closest_r: Vector2 = Geometry2D.get_closest_point_to_segment(p_pos, Vector2(rd["prev"]), right_hand.global_position) if bool(rd["swept"]) else right_hand.global_position
		if closest_r.distance_to(p_pos) <= HAND_RADIUS + player_radius:
			player_node.take_damage(1)


# ------------------------------------------------------------------------------
# FACIAL RIG, ARTICULATED HANDS & CUSTOM _draw() RENDERING
# ------------------------------------------------------------------------------
func _apply_visuals(_delta: float) -> void:
	var rig_scale: Vector2 = Vector2.ONE
	var rig_rot: float = 0.0
	var rig_offset: Vector2 = Vector2.ZERO
	var eye_scale_left: Vector2 = Vector2.ONE
	var eye_scale_right: Vector2 = Vector2.ONE
	var pupil_scale: float = 1.0
	var show_pupils: bool = true
	var hollow_eyes: bool = false
	var dim_factor: float = 1.0
	var pupil_jitter: Vector2 = Vector2.ZERO

	match acting_state:
		ActingState.COCKY_CONDUCTOR:
			var beat_bob: float = 0.04 * _last_beat_pulse
			rig_scale = Vector2(1.0 + beat_bob, 1.0 - beat_bob * 0.7)
			eye_scale_left = Vector2(1.0, 0.65)
			eye_scale_right = Vector2(1.0, 0.65)
		ActingState.FROZEN_DOUBLE_TAKE:
			rig_rot = deg_to_rad(16.0)
			pupil_scale = 1.38
			var blink_y: float = 1.0
			if _double_blink_timer > 0.0:
				var p: float = 1.0 - (_double_blink_timer / 0.62)
				if (p > 0.15 and p < 0.30) or (p > 0.50 and p < 0.65):
					blink_y = 0.05
			eye_scale_left = Vector2(1.1, blink_y)
			eye_scale_right = Vector2(1.1, blink_y)
		ActingState.FLOOR_SLAM_TANTRUM:
			var pulse_s: float = 0.08 * _last_beat_pulse
			rig_scale = Vector2(1.0 + pulse_s, 1.0 - pulse_s)
			pupil_scale = 0.58
			rig_offset = Vector2(sin(_elapsed_time * 40.0) * 2.5, 0.0)
		ActingState.ACCUSING_POINT:
			eye_scale_left = Vector2(1.0, 0.35)
			eye_scale_right = Vector2(1.0, 0.85)
			pupil_scale = 0.55
			if _lunge_active:
				rig_scale = Vector2(1.18, 0.84)
		ActingState.FAKE_OUT_COLLAPSE:
			rig_rot = deg_to_rad(-14.0)
			rig_scale = Vector2(0.95 + 0.28 * _inflate_amount, 0.90 + 0.22 * _inflate_amount)
			eye_scale_left = Vector2(1.0, 0.08)
			eye_scale_right = Vector2(1.0, 0.08)
			show_pupils = false
			dim_factor = 0.52 if not _silence_freeze else 0.42
		ActingState.HOLLOW_REBIRTH:
			hollow_eyes = true
			show_pupils = false
			eye_scale_left = Vector2(1.22, 1.22)
			eye_scale_right = Vector2(1.22, 1.22)
			rig_scale = Vector2.ONE * (1.0 + 0.06 * _last_beat_pulse)
		ActingState.EXHAUSTED_PANTING:
			var pant: float = 0.5 + 0.5 * sin(_elapsed_time * TAU / BEAT_DURATION)
			rig_scale = Vector2(lerpf(0.88, 1.22, pant), lerpf(1.18, 0.80, pant))
			eye_scale_left = Vector2(1.0, 0.55)
			eye_scale_right = Vector2(1.0, 0.55)
		ActingState.TEMPLE_CLUTCH_PANIC:
			rig_offset = Vector2(sin(_elapsed_time * 50.0) * 3.0, cos(_elapsed_time * 43.0) * 2.0)
			eye_scale_left = Vector2(1.15, 1.28)
			eye_scale_right = Vector2(1.15, 1.28)
			pupil_scale = 0.48
			pupil_jitter = Vector2(sin(_elapsed_time * TAU * 15.0) * 3.5, cos(_elapsed_time * TAU * 11.0) * 3.0)
		ActingState.SILENT_SHATTER:
			rig_scale = Vector2(0.72, 1.48)
			eye_scale_left = Vector2(1.20, 1.35)
			eye_scale_right = Vector2(1.20, 1.35)
			pupil_scale = 0.42

	var laughing: bool = _laugh_timer > 0.0
	if laughing:
		rig_offset.y += sin(_elapsed_time * TAU * 14.0) * 5.0
		eye_scale_left = Vector2(1.1, 1.0)
		eye_scale_right = Vector2(1.1, 1.0)
		show_pupils = false
	elif _flinch_timer > 0.0:
		rig_scale *= Vector2(0.84, 1.14)
		pupil_scale *= 0.55

	if laughing != _was_laughing:
		_set_eye_polygons(laughing)
		_was_laughing = laughing

	face_rig.position = rig_offset
	face_rig.rotation = rig_rot
	face_rig.scale = rig_scale

	if current_phase >= 6:
		crown_polygon.rotation = _elapsed_time * (0.9 if current_phase == 6 else 0.4)
	else:
		crown_polygon.rotation = 0.0

	var flash_boost: float = _white_flash * 0.45
	var body_gray: float = clampf(0.96 * dim_factor + flash_boost, 0.0, 1.0)
	var crown_gray: float = clampf(0.86 * dim_factor + flash_boost, 0.0, 1.0)
	var eye_gray: float = clampf((1.0 if hollow_eyes else 0.96) * dim_factor + flash_boost, 0.0, 1.0)
	body_polygon.color = Color(body_gray, body_gray, body_gray, 1.0)
	crown_polygon.color = Color(crown_gray, crown_gray, crown_gray, 1.0)
	left_eye_polygon.color = Color(eye_gray, eye_gray, eye_gray, 1.0)
	right_eye_polygon.color = Color(eye_gray, eye_gray, eye_gray, 1.0)

	var glow_alpha: float = clampf((0.32 + 0.14 * _last_beat_pulse + 0.30 * _white_flash + 0.25 * _mouth_beam_flash) * dim_factor, 0.0, 0.90)
	boss_glow.color = Color(1.0, 1.0, 1.0, glow_alpha)

	left_eye_polygon.scale = eye_scale_left
	right_eye_polygon.scale = eye_scale_right

	var to_player: Vector2 = _player_pos - _body_pos
	var track_offset: Vector2 = to_player.normalized() * minf(to_player.length() * 0.02, 3.6) if to_player.length_squared() > 1.0 else Vector2.ZERO
	var final_pupil_offset: Vector2 = (track_offset + pupil_jitter).limit_length(4.0)

	var pupils_visible: bool = show_pupils and eye_scale_left.y >= 0.25 and eye_scale_right.y >= 0.25
	left_pupil_polygon.visible = pupils_visible
	right_pupil_polygon.visible = pupils_visible
	left_pupil_polygon.position = EYE_OFFSET_LEFT + final_pupil_offset
	right_pupil_polygon.position = EYE_OFFSET_RIGHT + final_pupil_offset
	left_pupil_polygon.scale = Vector2.ONE * pupil_scale
	right_pupil_polygon.scale = Vector2.ONE * pupil_scale

	_update_brows_and_mouth(laughing, dim_factor)
	_update_hands_visuals(dim_factor)


func _update_brows_and_mouth(laughing: bool, dim_factor: float) -> void:
	var brow_gray: float = clampf(0.96 * dim_factor + _white_flash * 0.2, 0.0, 1.0)
	var line_col: Color = Color(brow_gray, brow_gray, brow_gray, 1.0)
	left_brow_line.default_color = line_col
	right_brow_line.default_color = line_col
	mouth_line.default_color = line_col

	if laughing:
		left_brow_line.points = PackedVector2Array([Vector2(-23, -16), Vector2(-14, -20), Vector2(-5, -16)])
		right_brow_line.points = PackedVector2Array([Vector2(5, -16), Vector2(14, -20), Vector2(23, -16)])
		mouth_line.points = PackedVector2Array([Vector2(-15, 10), Vector2(-7, 17), Vector2(0, 19), Vector2(7, 17), Vector2(15, 10)])
		return

	if _flinch_timer > 0.0:
		left_brow_line.points = PackedVector2Array([Vector2(-22, -16), Vector2(-6, -10)])
		right_brow_line.points = PackedVector2Array([Vector2(6, -10), Vector2(22, -16)])
		mouth_line.points = PackedVector2Array([Vector2(-11, 15), Vector2(-5, 11), Vector2(0, 15), Vector2(5, 11), Vector2(11, 15)])
		return

	if _mouth_charge_timer > 0.0 or _mouth_beam_flash > 0.0:
		left_brow_line.points = PackedVector2Array([Vector2(-23, -18), Vector2(-5, -10)])
		right_brow_line.points = PackedVector2Array([Vector2(5, -10), Vector2(23, -18)])
		mouth_line.points = PackedVector2Array([
			Vector2(-15, 10), Vector2(-8, 22), Vector2(0, 14), Vector2(8, 22), Vector2(15, 10), Vector2(0, 7), Vector2(-15, 10)
		])
		return

	match acting_state:
		ActingState.COCKY_CONDUCTOR:
			left_brow_line.points = PackedVector2Array([Vector2(-22, -14), Vector2(-6, -13)])
			right_brow_line.points = PackedVector2Array([Vector2(6, -16), Vector2(22, -19)])
			mouth_line.points = PackedVector2Array([Vector2(-12, 12), Vector2(-2, 14), Vector2(8, 12), Vector2(14, 7)])
		ActingState.FROZEN_DOUBLE_TAKE:
			left_brow_line.points = PackedVector2Array([Vector2(-22, -17), Vector2(-14, -21), Vector2(-6, -17)])
			right_brow_line.points = PackedVector2Array([Vector2(6, -17), Vector2(14, -21), Vector2(22, -17)])
			mouth_line.points = PackedVector2Array([Vector2(-8, 13), Vector2(-3, 17), Vector2(3, 17), Vector2(8, 13)])
		ActingState.FLOOR_SLAM_TANTRUM, ActingState.HOLLOW_REBIRTH:
			left_brow_line.points = PackedVector2Array([Vector2(-23, -18), Vector2(-5, -10)])
			right_brow_line.points = PackedVector2Array([Vector2(5, -10), Vector2(23, -18)])
			var jit: float = sin(_elapsed_time * 48.0) * 2.2
			mouth_line.points = PackedVector2Array([
				Vector2(-16, 12 + jit), Vector2(-9, 17 - jit), Vector2(-3, 10 + jit),
				Vector2(3, 17 - jit), Vector2(9, 10 + jit), Vector2(16, 12 - jit),
			])
		ActingState.ACCUSING_POINT:
			left_brow_line.points = PackedVector2Array([Vector2(-22, -15), Vector2(-6, -11)])
			right_brow_line.points = PackedVector2Array([Vector2(6, -11), Vector2(22, -17)])
			if _lunge_active or _lunge_telegraphing:
				mouth_line.points = PackedVector2Array([Vector2(-16, 10), Vector2(-8, 20), Vector2(0, 12), Vector2(8, 20), Vector2(16, 10)])
			else:
				mouth_line.points = PackedVector2Array([Vector2(-12, 14), Vector2(0, 12), Vector2(12, 15)])
		ActingState.FAKE_OUT_COLLAPSE:
			left_brow_line.points = PackedVector2Array([Vector2(-21, -12), Vector2(-7, -12)])
			right_brow_line.points = PackedVector2Array([Vector2(7, -12), Vector2(21, -12)])
			mouth_line.points = PackedVector2Array([Vector2(-12, 14), Vector2(12, 14)])
		ActingState.EXHAUSTED_PANTING:
			left_brow_line.points = PackedVector2Array([Vector2(-22, -12), Vector2(-6, -17)])
			right_brow_line.points = PackedVector2Array([Vector2(6, -17), Vector2(22, -12)])
			var pant_open: float = 3.5 * (0.5 + 0.5 * sin(_elapsed_time * TAU / BEAT_DURATION))
			mouth_line.points = PackedVector2Array([
				Vector2(-12, 12), Vector2(-5, 16 + pant_open), Vector2(0, 13), Vector2(5, 16 + pant_open), Vector2(12, 12)
			])
		ActingState.TEMPLE_CLUTCH_PANIC, ActingState.SILENT_SHATTER:
			left_brow_line.points = PackedVector2Array([Vector2(-22, -14), Vector2(-6, -21)])
			right_brow_line.points = PackedVector2Array([Vector2(6, -21), Vector2(22, -14)])
			var scream: float = sin(_elapsed_time * 55.0) * 2.0
			mouth_line.points = PackedVector2Array([
				Vector2(-14, 15 + scream), Vector2(-7, 10 - scream), Vector2(0, 18 + scream),
				Vector2(7, 10 - scream), Vector2(14, 15 + scream),
			])


func _hand_flash_amount(idx: int) -> float:
	var sl: Dictionary = _hand_slams[idx]
	var da: Dictionary = _hand_dashes[idx]
	var ai: Dictionary = _hand_aims[idx]
	if float(sl["active"]) > 0.0 or bool(da["active"]) or _hand_throw_flash[idx] > 0.0:
		return 1.0
	if float(sl["telegraph"]) > 0.0 or float(da["telegraph"]) > 0.0 or float(ai["timer"]) > 0.0:
		return 0.75
	if acting_state == ActingState.FAKE_OUT_COLLAPSE and _phase5_hands_awake:
		return 0.65
	if _claw_orbit_timer > 0.0:
		return 0.85
	return 0.0


func _update_hands_visuals(dim_factor: float) -> void:
	var hand_dim: float = 0.94 if (acting_state == ActingState.FAKE_OUT_COLLAPSE and _phase5_hands_awake) else dim_factor
	var lg: float = clampf(0.94 * hand_dim + _hand_flash_amount(0) * 0.25, 0.0, 1.0)
	var rg: float = clampf(0.94 * hand_dim + _hand_flash_amount(1) * 0.25, 0.0, 1.0)
	left_hand_polygon.color = Color(lg, lg, lg, 1.0)
	right_hand_polygon.color = Color(rg, rg, rg, 1.0)
	left_hand_void.color = Color(0.06, 0.06, 0.06, 1.0)
	right_hand_void.color = Color(0.06, 0.06, 0.06, 1.0)
	left_hand_core.color = Color(lg, lg, lg, 1.0)
	right_hand_core.color = Color(rg, rg, rg, 1.0)
	var ring_g: float = clampf(0.84 * hand_dim, 0.0, 1.0)
	left_hand_ring.default_color = Color(ring_g, ring_g, ring_g, 0.72)
	right_hand_ring.default_color = left_hand_ring.default_color


func _update_sweat_shards(delta: float) -> void:
	for i: int in range(_sweat_shards.size() - 1, -1, -1):
		var sh: Dictionary = _sweat_shards[i]
		sh["life"] = float(sh["life"]) - delta
		if float(sh["life"]) <= 0.0:
			_sweat_shards.remove_at(i)
			continue
		var vel: Vector2 = Vector2(sh["vel"]) + Vector2(0.0, 260.0) * delta
		sh["vel"] = vel
		sh["pos"] = Vector2(sh["pos"]) + vel * delta

	if acting_state == ActingState.EXHAUSTED_PANTING:
		_sweat_spawn_timer -= delta
		if _sweat_spawn_timer <= 0.0:
			_sweat_spawn_timer = 0.22
			for side: float in [-1.0, 1.0]:
				_sweat_shards.append({
					"pos": Vector2(side * 34.0, -18.0),
					"vel": Vector2(side * 65.0, -75.0),
					"life": 0.55,
					"max_life": 0.55,
				})


func _draw() -> void:
	if _shattered:
		for sh: Dictionary in _shatter_shards:
			var offset: Vector2 = Vector2(sh["offset"])
			var rot: float = float(sh["rot"])
			var sz: float = float(sh["size"])
			var g: float = float(sh["gray"])
			var pts: PackedVector2Array = PackedVector2Array([
				offset + Vector2(sz, 0.0).rotated(rot),
				offset + Vector2(-sz * 0.6, -sz * 0.7).rotated(rot),
				offset + Vector2(-sz * 0.6, sz * 0.7).rotated(rot),
			])
			draw_colored_polygon(pts, Color(g, g, g, 0.92))
		draw_arc(Vector2.ZERO, 68.0, 0.0, TAU, 36, Color(0.95, 0.95, 0.95, 0.75), 2.2, true)
		return

	# Floor-rake grooves
	for gr: Dictionary in _rake_grooves:
		var lr: float = clampf(float(gr["life"]) / maxf(float(gr["max_life"]), 0.001), 0.0, 1.0)
		var f_l: Vector2 = Vector2(gr["from"]) - global_position
		var t_l: Vector2 = Vector2(gr["to"]) - global_position
		draw_line(f_l, t_l, Color(0.92, 0.92, 0.92, 0.55 * lr), 6.0 * lr, true)
		draw_line(f_l + Vector2(0, 10), t_l + Vector2(0, 10), Color(0.75, 0.75, 0.75, 0.35 * lr), 2.0, true)

	# Trailing claw slash arcs
	for sa: Dictionary in _slash_arcs:
		var lr: float = clampf(float(sa["life"]) / maxf(float(sa["max_life"]), 0.001), 0.0, 1.0)
		var c_l: Vector2 = Vector2(sa["pos"]) - global_position
		var rot: float = float(sa["rot"])
		var rad: float = float(sa["radius"])
		draw_arc(c_l, rad, rot - 0.85, rot + 0.85, 14, Color(0.98, 0.98, 0.98, 0.62 * lr), 3.0 * lr, true)

	# Geometric afterimages for body & hand dashes
	for ghost: Dictionary in _afterimages:
		var lr: float = clampf(float(ghost["life"]) / maxf(float(ghost["max_life"]), 0.001), 0.0, 1.0)
		var local_g: Vector2 = Vector2(ghost["pos"]) - global_position
		var rad: float = float(ghost["radius"]) * (0.72 + 0.28 * lr)
		var rot: float = float(ghost["rot"])
		var col: Color = Color(0.90, 0.90, 0.90, 0.24 * lr)
		if String(ghost.get("shape", "")) == "diamond":
			var pts: PackedVector2Array = PackedVector2Array([
				local_g + Vector2(rad * 1.15, 0.0).rotated(rot),
				local_g + Vector2(0.0, -rad * 0.8).rotated(rot),
				local_g + Vector2(-rad * 1.0, 0.0).rotated(rot),
				local_g + Vector2(0.0, rad * 0.8).rotated(rot),
			])
			draw_colored_polygon(pts, col)
		else:
			draw_circle(local_g, rad, col)

	# Spinning claw orbit ring
	if _claw_orbit_timer > 0.0:
		var orbit_p: float = 1.0 - clampf(_claw_orbit_timer / maxf(_claw_orbit_duration, 0.001), 0.0, 1.0)
		var s: Vector2 = _scale_vec()
		var orbit_r: float = lerpf(115.0, 195.0, sin(orbit_p * PI * 0.5)) * minf(s.x, s.y)
		draw_arc(Vector2.ZERO, orbit_r, 0.0, TAU, 36, Color(0.92, 0.92, 0.92, 0.34), 1.8, true)

	# Body lunge corridor telegraph
	if _lunge_telegraphing:
		_draw_corridor_rail(_body_pos, _lunge_target, 38.0, 34.0)

	# Hand dash / claw swipe / floor rake telegraphs
	for idx: int in range(2):
		var d: Dictionary = _hand_dashes[idx]
		if float(d["telegraph"]) > 0.0:
			var style: int = int(d["style"])
			var half_w: float = 34.0 if style == HandDashStyle.CLAW_SWIPE else 24.0
			_draw_corridor_rail(Vector2(d["start"]), Vector2(d["target"]), half_w, 26.0)
		var sl: Dictionary = _hand_slams[idx]
		if float(sl["telegraph"]) > 0.0:
			var sp: Vector2 = Vector2(sl["target"]) - global_position
			draw_arc(sp, 34.0, 0.0, TAU, 24, Color(0.92, 0.92, 0.92, 0.70), 2.4, true)
			draw_line(sp - Vector2(18, 0), sp + Vector2(18, 0), Color(0.92, 0.92, 0.92, 0.50), 1.6, true)

	# Twin-hand tether & pincer lines
	if _tether_beam_timer > 0.0:
		var lp: Vector2 = _left_hand_pos - global_position
		var rp: Vector2 = _right_hand_pos - global_position
		draw_line(lp, rp, Color(0.94, 0.94, 0.94, 0.68), 2.2, true)
		draw_circle((lp + rp) * 0.5, 10.0 + 4.0 * sin(_elapsed_time * 24.0), Color(0.96, 0.96, 0.96, 0.75))
	if _pincer_timer > 0.0:
		var pl: Vector2 = _pincer_left - global_position
		var pr: Vector2 = _pincer_right - global_position
		var pm: Vector2 = _pincer_mid - global_position
		draw_line(pl, pr, Color(0.94, 0.94, 0.94, 0.65), 2.2, true)
		draw_arc(pm, 28.0 + 5.0 * sin(_elapsed_time * 18.0), 0.0, TAU, 24, Color(0.98, 0.98, 0.98, 0.80), 2.4, true)

	# Wall-push grip tethers
	if _wall_push_timer > 0.0:
		var lp: Vector2 = _left_hand_pos - global_position
		var rp: Vector2 = _right_hand_pos - global_position
		if _wall_push_axis == 0:
			draw_line(lp + Vector2(16, -260), lp + Vector2(16, 260), Color(0.88, 0.88, 0.88, 0.52), 2.0, true)
			draw_line(rp + Vector2(-16, -260), rp + Vector2(-16, 260), Color(0.88, 0.88, 0.88, 0.52), 2.0, true)
		else:
			draw_line(lp + Vector2(-380, 16), lp + Vector2(380, 16), Color(0.88, 0.88, 0.88, 0.52), 2.0, true)
			draw_line(rp + Vector2(-380, -16), rp + Vector2(380, -16), Color(0.88, 0.88, 0.88, 0.52), 2.0, true)

	# Thrown Energy Seeds + destination reticles + ribbons
	for sd: Dictionary in _thrown_seeds:
		var cur_l: Vector2 = Vector2(sd["pos"]) - global_position
		var end_l: Vector2 = Vector2(sd["target"]) - global_position
		var p: float = clampf(float(sd["elapsed"]) / maxf(float(sd["duration"]), 0.001), 0.0, 1.0)
		draw_line(cur_l, end_l, Color(0.80, 0.80, 0.80, 0.35), 1.4, true)
		draw_arc(end_l, lerpf(36.0, 12.0, p), 0.0, TAU, 24, Color(0.95, 0.95, 0.95, 0.45 + 0.45 * p), 2.0, true)
		var tr: PackedVector2Array = sd["trail"]
		for t_i: int in range(tr.size() - 1):
			var frac: float = float(t_i + 1) / float(tr.size())
			draw_line(tr[t_i] - global_position, tr[t_i + 1] - global_position, Color(0.95, 0.95, 0.95, 0.65 * frac), 3.0 * frac, true)
		var rot_seed: float = _elapsed_time * 12.0
		var seed_poly: PackedVector2Array = PackedVector2Array([
			cur_l + Vector2(11.0, 0.0).rotated(rot_seed),
			cur_l + Vector2(0.0, -7.0).rotated(rot_seed),
			cur_l + Vector2(-11.0, 0.0).rotated(rot_seed),
			cur_l + Vector2(0.0, 7.0).rotated(rot_seed),
		])
		draw_colored_polygon(seed_poly, Color(1.0, 1.0, 1.0, 0.96))

	# Articulated 5-Finger JSAB Hand Details + thrust chevrons
	_draw_jsab_hand_details(true)
	_draw_jsab_hand_details(false)

	# Mouth charge / beam flare
	if _mouth_charge_timer > 0.0 or _mouth_beam_flash > 0.0:
		var r: float = 12.0 + 10.0 * maxf(_mouth_charge_timer, _mouth_beam_flash)
		draw_circle(Vector2(0.0, 14.0), r, Color(1.0, 1.0, 1.0, 0.72))

	# Cracks on body
	if _crack_intensity > 0.01:
		var c_gray: float = 0.96 if acting_state == ActingState.SILENT_SHATTER else 0.14
		var c_col: Color = Color(c_gray, c_gray, c_gray, clampf(_crack_intensity, 0.0, 1.0))
		var crack_w: float = 2.4 if acting_state == ActingState.SILENT_SHATTER else 2.0
		var sc: Vector2 = face_rig.scale
		var crack_paths: Array = [
			[Vector2(-32, -22), Vector2(-18, -10), Vector2(-24, 4), Vector2(-10, 16)],
			[Vector2(30, -24), Vector2(18, -12), Vector2(25, 2), Vector2(14, 18)],
			[Vector2(-6, -34), Vector2(2, -20), Vector2(-5, -8)],
			[Vector2(8, 20), Vector2(0, 32), Vector2(12, 38)],
		]
		for path: Array in crack_paths:
			for idx: int in range(path.size() - 1):
				var p0: Vector2 = (Vector2(path[idx]) * sc).rotated(face_rig.rotation) + face_rig.position
				var p1: Vector2 = (Vector2(path[idx + 1]) * sc).rotated(face_rig.rotation) + face_rig.position
				draw_line(p0, p1, c_col, crack_w, true)

	# Sweat shards
	for sh: Dictionary in _sweat_shards:
		var alpha: float = clampf(float(sh["life"]) / maxf(float(sh["max_life"]), 0.001), 0.0, 1.0)
		var pos: Vector2 = Vector2(sh["pos"])
		var drop: PackedVector2Array = PackedVector2Array([
			pos + Vector2(0.0, -6.0),
			pos + Vector2(4.0, 0.0),
			pos + Vector2(0.0, 6.0),
			pos + Vector2(-4.0, 0.0),
		])
		draw_colored_polygon(drop, Color(0.88, 0.88, 0.88, 0.85 * alpha))


func _draw_corridor_rail(from_pos: Vector2, to_pos: Vector2, half_width: float, end_radius: float) -> void:
	var a: Vector2 = from_pos - global_position
	var b: Vector2 = to_pos - global_position
	var delta_v: Vector2 = b - a
	var dist: float = delta_v.length()
	var dir: Vector2 = delta_v / dist if dist > 1.0 else Vector2.RIGHT
	var perp: Vector2 = Vector2(-dir.y, dir.x) * half_width
	var col: Color = Color(0.92, 0.92, 0.92, 0.62)
	var dash_col: Color = Color(0.86, 0.86, 0.86, 0.45)

	# Segmented dashed outer rails
	var seg_len: float = 28.0
	var step: float = 42.0
	var t: float = 0.0
	while t < dist:
		var s0: float = t
		var s1: float = minf(t + seg_len, dist)
		draw_line(a + dir * s0 + perp, a + dir * s1 + perp, col, 2.0, true)
		draw_line(a + dir * s0 - perp, a + dir * s1 - perp, col, 2.0, true)
		t += step

	# Directional chevron markers along center
	var chev_step: float = maxf(dist / 4.0, 56.0)
	var c_dist: float = chev_step * 0.6
	while c_dist < dist - 20.0:
		var c_pos: Vector2 = a + dir * c_dist
		var wing: Vector2 = Vector2(-dir.y, dir.x) * (half_width * 0.42)
		draw_line(c_pos - dir * 10.0 + wing, c_pos + dir * 6.0, dash_col, 2.0, true)
		draw_line(c_pos - dir * 10.0 - wing, c_pos + dir * 6.0, dash_col, 2.0, true)
		c_dist += chev_step

	draw_arc(b, end_radius, 0.0, TAU, 22, col, 2.0, true)


func _draw_jsab_hand_details(is_left: bool) -> void:
	var idx: int = 0 if is_left else 1
	var hand_pos: Vector2 = (_left_hand_pos if is_left else _right_hand_pos) - global_position
	var hand_rot: float = _left_hand_rot if is_left else _right_hand_rot
	var pose: int = _left_hand_pose if is_left else _right_hand_pose
	var side: float = 1.0 if is_left else -1.0
	var flash: float = _hand_throw_flash[idx]
	var col_bright: Color = Color(0.96, 0.96, 0.96, 1.0)
	var col_mid: Color = Color(0.86, 0.86, 0.86, 0.96)
	var aim_active: bool = float(_hand_aims[idx]["timer"]) > 0.0
	var dashing: bool = bool(_hand_dashes[idx]["active"])
	var dash_tele: bool = float(_hand_dashes[idx]["telegraph"]) > 0.0

	match pose:
		HandPose.OPEN:
			var finger_xs: Array[float] = [-15.0 * side, -5.0 * side, 5.0 * side, 15.0 * side]
			var finger_lens: Array[float] = [17.0, 22.0, 20.0, 15.0]
			for i: int in range(4):
				var wave: float = sin(_elapsed_time * 6.5 + float(i) * 0.65) * 3.5
				var base_p: Vector2 = Vector2(finger_xs[i], -22.0 + wave * 0.35)
				var ang: float = side * (-0.28 + float(i) * 0.16)
				var seg: PackedVector2Array = _make_finger_poly(base_p, Vector2(0.0, -1.0).rotated(ang), finger_lens[i], 4.2, 2.0)
				_draw_transformed_poly(seg, hand_pos, hand_rot, col_bright if i % 2 == 0 else col_mid)
			var thumb: PackedVector2Array = _make_finger_poly(Vector2(21.0 * side, 2.0), Vector2(0.85 * side, -0.55).normalized(), 17.0, 4.6, 2.2)
			_draw_transformed_poly(thumb, hand_pos, hand_rot, col_bright)

		HandPose.FIST:
			for i: int in range(4):
				var ky: float = -13.5 + float(i) * 9.0
				var plate: PackedVector2Array = PackedVector2Array([
					Vector2(20.0, ky - 3.6),
					Vector2(28.0, ky - 2.6),
					Vector2(28.0, ky + 2.6),
					Vector2(20.0, ky + 3.6),
				])
				_draw_transformed_poly(plate, hand_pos, hand_rot, col_bright)
			var lock_thumb: PackedVector2Array = _make_finger_poly(Vector2(2.0, 17.0 * side), Vector2(1.0, -0.25 * side).normalized(), 18.0, 5.0, 3.2)
			_draw_transformed_poly(lock_thumb, hand_pos, hand_rot, col_mid)
			if dashing or dash_tele:
				for c_i: int in range(2):
					var cx: float = -30.0 - float(c_i) * 11.0
					var p_top: Vector2 = hand_pos + Vector2(cx - 8.0, -14.0).rotated(hand_rot)
					var p_mid: Vector2 = hand_pos + Vector2(cx + 4.0, 0.0).rotated(hand_rot)
					var p_bot: Vector2 = hand_pos + Vector2(cx - 8.0, 14.0).rotated(hand_rot)
					var c_alpha: float = 0.88 if dashing else 0.52
					draw_polyline(PackedVector2Array([p_top, p_mid, p_bot]), Color(0.98, 0.98, 0.98, c_alpha), 2.6, true)

		HandPose.POINTER:
			var barrel: PackedVector2Array = _make_finger_poly(Vector2(18.0, -4.0 * side), Vector2.RIGHT, 28.0, 5.4, 2.4)
			_draw_transformed_poly(barrel, hand_pos, hand_rot, col_bright)
			var cocked_thumb: PackedVector2Array = _make_finger_poly(Vector2(2.0, -15.0 * side), Vector2(0.5, -0.86 * side).normalized(), 15.0, 4.5, 2.2)
			_draw_transformed_poly(cocked_thumb, hand_pos, hand_rot, col_mid)
			for i: int in range(3):
				var ky: float = (4.0 + float(i) * 6.5) * side
				var curled: PackedVector2Array = PackedVector2Array([
					Vector2(13.0, ky - 2.6), Vector2(20.0, ky - 2.0), Vector2(20.0, ky + 2.0), Vector2(13.0, ky + 2.6)
				])
				_draw_transformed_poly(curled, hand_pos, hand_rot, col_mid)
			var tip_world: Vector2 = hand_pos + Vector2(48.0, -4.0 * side).rotated(hand_rot)
			if aim_active or flash > 0.0:
				draw_circle(tip_world, 7.5 + 4.0 * flash, Color(1.0, 1.0, 1.0, 0.92))
				draw_arc(tip_world, 13.0, 0.0, TAU, 20, Color(0.94, 0.94, 0.94, 0.72), 1.8, true)
				if aim_active:
					var ray_end: Vector2 = tip_world + Vector2.from_angle(hand_rot) * 1400.0
					draw_line(tip_world, ray_end, Color(0.92, 0.92, 0.92, 0.38), 1.6, true)

		HandPose.CLAW:
			var angles: Array[float] = [-1.15, -0.58, 0.0, 0.58, 1.15]
			for i: int in range(5):
				var a: float = angles[i]
				var base_p: Vector2 = Vector2.from_angle(a) * 20.0
				var talon: PackedVector2Array = _make_finger_poly(base_p, Vector2.from_angle(a + 0.14 * side), 20.0, 4.8, 1.0)
				_draw_transformed_poly(talon, hand_pos, hand_rot, col_bright if i % 2 == 0 else col_mid)


func _make_finger_poly(base: Vector2, dir: Vector2, length: float, half_base_w: float, half_tip_w: float) -> PackedVector2Array:
	var n: Vector2 = dir.normalized()
	var perp: Vector2 = Vector2(-n.y, n.x)
	var tip: Vector2 = base + n * length
	return PackedVector2Array([
		base + perp * half_base_w,
		tip + perp * half_tip_w,
		tip + n * 4.0,
		tip - perp * half_tip_w,
		base - perp * half_base_w,
	])


func _draw_transformed_poly(local_pts: PackedVector2Array, origin: Vector2, rot: float, color: Color) -> void:
	var out: PackedVector2Array = PackedVector2Array()
	out.resize(local_pts.size())
	for i: int in range(local_pts.size()):
		out[i] = origin + local_pts[i].rotated(rot)
	draw_colored_polygon(out, color)


func _build_base_geometry() -> void:
	body_polygon.polygon = Shapes.circle(BODY_RADIUS, 8, PI / 8.0)
	void_polygon.polygon = Shapes.circle(32.0, 8, PI / 8.0)
	var pupil_poly: PackedVector2Array = Shapes.circle(4.2, 10)
	left_pupil_polygon.polygon = pupil_poly
	right_pupil_polygon.polygon = pupil_poly
	_set_eye_polygons(false)


func _set_eye_polygons(laughing_crescent: bool) -> void:
	if laughing_crescent:
		var crescent: PackedVector2Array = PackedVector2Array([
			Vector2(-9.0, 3.0),
			Vector2(0.0, -7.0),
			Vector2(9.0, 3.0),
			Vector2(5.0, 5.0),
			Vector2(0.0, -2.0),
			Vector2(-5.0, 5.0),
		])
		left_eye_polygon.polygon = crescent
		right_eye_polygon.polygon = crescent
	else:
		var eye_poly: PackedVector2Array = Shapes.circle(8.5, 12)
		left_eye_polygon.polygon = eye_poly
		right_eye_polygon.polygon = eye_poly


func _set_crown_for_phase(phase: int) -> void:
	if phase == _active_crown_phase:
		return
	_active_crown_phase = phase
	if phase >= 6:
		crown_polygon.polygon = Shapes.star(62.0, 38.0, 12)
	elif phase >= 3 and phase <= 4:
		crown_polygon.polygon = Shapes.star(58.0, 36.0, 8)
	else:
		crown_polygon.polygon = Shapes.star(54.0, 40.0, 6)


func _set_hand_pose(is_left: bool, pose: int) -> void:
	var prev: int = _left_hand_pose if is_left else _right_hand_pose
	if pose == prev:
		return
	if is_left:
		_left_hand_pose = pose
	else:
		_right_hand_pose = pose

	var outer_poly: Polygon2D = left_hand_polygon if is_left else right_hand_polygon
	var void_poly: Polygon2D = left_hand_void if is_left else right_hand_void
	var core_poly: Polygon2D = left_hand_core if is_left else right_hand_core
	var ring_line: Line2D = left_hand_ring if is_left else right_hand_ring
	var side: float = 1.0 if is_left else -1.0

	match pose:
		HandPose.FIST:
			outer_poly.polygon = PackedVector2Array([
				Vector2(-22.0, -18.0),
				Vector2(18.0, -21.0),
				Vector2(22.0, -10.0),
				Vector2(22.0, 10.0),
				Vector2(18.0, 21.0),
				Vector2(-22.0, 18.0),
				Vector2(-26.0, 0.0),
			])
			void_poly.polygon = Shapes.rect(Vector2(24.0, 24.0))
			core_poly.polygon = Shapes.diamond(7.5)
			ring_line.points = Shapes.circle(30.0, 16)
		HandPose.POINTER:
			outer_poly.polygon = PackedVector2Array([
				Vector2(20.0, -10.0 * side),
				Vector2(15.0, 16.0 * side),
				Vector2(-16.0, 19.0 * side),
				Vector2(-23.0, 0.0),
				Vector2(-14.0, -18.0 * side),
			])
			void_poly.polygon = Shapes.circle(12.0, 6)
			core_poly.polygon = Shapes.diamond(6.0)
			ring_line.points = Shapes.circle(28.0, 16)
		HandPose.CLAW:
			outer_poly.polygon = Shapes.circle(23.0, 6)
			void_poly.polygon = Shapes.circle(14.0, 6)
			core_poly.polygon = Shapes.star(9.0, 4.5, 4)
			ring_line.points = Shapes.circle(31.0, 20)
		_:
			outer_poly.polygon = PackedVector2Array([
				Vector2(-20.0 * side, -20.0),
				Vector2(20.0 * side, -20.0),
				Vector2(24.0 * side, 6.0),
				Vector2(12.0 * side, 22.0),
				Vector2(-16.0 * side, 22.0),
				Vector2(-24.0 * side, 4.0),
			])
			void_poly.polygon = Shapes.circle(13.0, 6)
			core_poly.polygon = Shapes.diamond(6.5)
			ring_line.points = Shapes.circle(30.0, 20)


func _resolve_arena_size(requested: Vector2) -> Vector2:
	if requested.x > 0.0 and requested.y > 0.0:
		return requested
	var rect_size: Vector2 = get_viewport_rect().size
	if rect_size.x > 0.0 and rect_size.y > 0.0:
		return rect_size
	return DEFAULT_ARENA_SIZE


func _scale_vec() -> Vector2:
	return Vector2(_arena_size.x / DEFAULT_ARENA_SIZE.x, _arena_size.y / DEFAULT_ARENA_SIZE.y)
