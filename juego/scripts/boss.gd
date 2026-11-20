extends Area2D

signal boss_slammed(at_position: Vector2, strength: float)
signal boss_wall_slammed(wall_pos: Vector2, inward_normal: Vector2, strength: float)
signal phase_changed(new_phase: int)
signal request_clear_hazards()
signal boss_parried(boss_pos: Vector2)
signal hand_slam_impact(is_left: bool, impact_pos: Vector2, impact_mode: int)
signal lunge_impact(impact_pos: Vector2)
signal teleported(from_pos: Vector2, to_pos: Vector2)

enum ActingState {
	COCKY_CONDUCTOR, FROZEN_DOUBLE_TAKE, FLOOR_SLAM_TANTRUM,
	ACCUSING_POINT, FAKE_OUT_COLLAPSE, HOLLOW_REBIRTH,
	EXHAUSTED_PANTING, TEMPLE_CLUTCH_PANIC, SILENT_SHATTER,
}
enum HandPose { OPEN, FIST, POINTER, CLAW }
enum HandDashStyle { FIST_ROCKET, CLAW_SWIPE, FLOOR_RAKE }
enum BossForm {
	CONDUCTOR = 0, SPIKE_ROLL = 1, WHEEL_CORE = 2, MARIONETTE = 3,
	TRIPLE_CANNON = 4, STOMP_COLOSSUS = 5, OVERDRIVE_PANIC = 6, SHATTERED = 7,
}
enum HandAction {
	IDLE, POINTER_AIM, DASH_TELEGRAPH, DASH_ACTIVE,
	FLOOR_SLAM_TELEGRAPH, FLOOR_SLAM_ACTIVE,
	WALL_SLAM_WINDUP, WALL_SLAM_STRIKE, WALL_SLAM_RECOVER,
	PINCER_TELEGRAPH, PINCER_CLAP, ORBIT, TETHER_SWEEP, RETRACTED,
}

const MUSIC_BPM: float = 128.0
const BEAT_DURATION: float = 60.0 / MUSIC_BPM
const TOTAL_PHASES: int = 8
const BODY_RADIUS: float = 30.0
const HAND_RADIUS: float = 19.0
const CANNON_MUZZLE_RADIUS: float = 48.0
const DEFAULT_ARENA_SIZE: Vector2 = Vector2(1152.0, 648.0)
const MAX_BODY_REPOSITION_SPEED: float = 680.0
const MAX_BODY_OVERDRIVE_SPEED: float = 820.0
const MAX_HAND_REPOSITION_SPEED: float = 700.0
const MAX_HAND_OVERDRIVE_SPEED: float = 860.0
const MAX_HAND_ROT_SPEED: float = 14.0
const SPAWN_GRACE_DURATION: float = 0.45
const EYE_OFFSET_LEFT: Vector2 = Vector2(-10.5, -4.0)
const EYE_OFFSET_RIGHT: Vector2 = Vector2(10.5, -4.0)

var current_phase: int = 1
var acting_state: ActingState = ActingState.COCKY_CONDUCTOR
var boss_form: BossForm = BossForm.CONDUCTOR
var is_body_hazardous: bool = false
var is_left_hand_hazardous: bool = false
var is_right_hand_hazardous: bool = false
var is_hand_hazardous: bool = false
var total_wall_slams: int = 0
var total_parries: int = 0
var _shattered: bool = false
var _flinch_timer: float = 0.0
var _laugh_timer: float = 0.0
var _tether_active: bool = false
var _lunge_active: bool = false
var _intro_active: bool = false
var _intro_progress: float = 0.0
var _intro_quick_mode: bool = false
var _intro_target_pos: Vector2 = Vector2.ZERO

var _arena_size: Vector2 = DEFAULT_ARENA_SIZE
var _elapsed_time: float = 0.0
var _last_sim_delta: float = 0.0
var _player_pos: Vector2 = Vector2(576.0, 324.0)
var _body_pos: Vector2 = Vector2(576.0, 152.0)
var _body_target: Vector2 = Vector2(576.0, 152.0)
var _body_move_speed: float = 7.5
var _recoil_vel: Vector2 = Vector2.ZERO
var _teleport_grace_timer: float = 0.0
var _lunge: Dictionary = _make_lunge_state()
var _hands: Array[Dictionary] = [_make_hand_state(), _make_hand_state()]
var _pincer_mid: Vector2 = Vector2.ZERO

var _active_crown_tier: int = -1
var _phase5_hands_awake: bool = false
var _last_beat_pulse: float = 0.0
var _freeze_timer: float = 0.0
var _double_blink_timer: float = 0.0
var _white_flash: float = 0.0
var _mouth_beam_flash: float = 0.0
var _crack_intensity: float = 0.0
var _inflate_amount: float = 0.0
var _silence_freeze: bool = false
var _was_laughing: bool = false
var _spike_roll_angle: float = 0.0
var _cannon_angle: float = 0.0
var _sweat_spawn_timer: float = 0.0

const BODY_CRACK_SEGMENTS: Array[Vector2] = [
	Vector2(-23.0, -16.0), Vector2(-13.0, -7.2),
	Vector2(-13.0, -7.2), Vector2(-17.5, 3.0),
	Vector2(-17.5, 3.0), Vector2(-7.2, 11.5),
	Vector2(21.5, -17.5), Vector2(13.0, -8.6),
	Vector2(13.0, -8.6), Vector2(18.0, 1.5),
	Vector2(18.0, 1.5), Vector2(10.0, 13.0),
	Vector2(-4.2, -24.5), Vector2(1.5, -14.5),
	Vector2(1.5, -14.5), Vector2(-3.6, -5.8),
	Vector2(5.8, 14.5), Vector2(0.0, 23.0),
	Vector2(0.0, 23.0), Vector2(8.6, 27.5),
]
const OPEN_FINGER_XS: Array[float] = [-10.8, -3.6, 3.6, 10.8]
const OPEN_FINGER_LS: Array[float] = [12.2, 15.8, 14.4, 10.8]

var _fx: Dictionary = {"afterimages": [], "slash": [], "rake": [], "cracks": [], "teleport": []}
var _sweat_shards: Array[Dictionary] = []
var _shatter_shards: Array[Dictionary] = []
var _pending_events: Array[Dictionary] = []

var _scratch_tri: PackedVector2Array = PackedVector2Array()
var _scratch_quad: PackedVector2Array = PackedVector2Array()
var _scratch_finger: PackedVector2Array = PackedVector2Array()
var _scratch_poly: PackedVector2Array = PackedVector2Array()
var _scratch_marionette_tf: PackedVector2Array = PackedVector2Array()
var _scratch_tether_pts: PackedVector2Array = PackedVector2Array()
var _scratch_line_pts: PackedVector2Array = PackedVector2Array()
var _scratch_line_pts_b: PackedVector2Array = PackedVector2Array()
var _scratch_line_cols: PackedColorArray = PackedColorArray()
var _marionette_rim: PackedVector2Array = PackedVector2Array()
var _cannon_barrel_poly: PackedVector2Array = PackedVector2Array()
var _cannon_slit_poly: PackedVector2Array = PackedVector2Array()

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


static func _make_lunge_state() -> Dictionary:
	return {
		"tele": false, "start": Vector2.ZERO, "target": Vector2.ZERO, "prev": Vector2.ZERO,
		"swept": false, "timer": 0.0, "tele_dur": 0.45, "dash_dur": 0.32, "emit_slam": true,
	}


static func _make_hand_state() -> Dictionary:
	return {
		"action": HandAction.IDLE, "pos": Vector2.ZERO, "prev_pos": Vector2.ZERO,
		"rot": 0.0, "pose": -1, "timer": 0.0, "duration": 0.0, "next_duration": 0.0,
		"start_pos": Vector2.ZERO, "stage_pos": Vector2.ZERO, "target_pos": Vector2.ZERO,
		"wall_pos": Vector2.ZERO, "normal": Vector2.RIGHT, "target_rot": 0.0,
		"style": HandDashStyle.FIST_ROCKET, "impact_mode": 0, "strength": 0.78,
		"swept": false, "flash": 0.0, "orbit_angle": 0.0, "orbit_speed": 3.6,
		"tether_start_y": 165.0, "tether_end_y": 465.0, "tether_active_phase": false,
		"retract_blend": 0.0,
	}


func _ready() -> void:
	_scratch_tri.resize(3)
	_scratch_quad.resize(4)
	_scratch_finger.resize(5)
	_scratch_tether_pts.resize(11)
	_marionette_rim = Shapes.circle(BODY_RADIUS + 2.0, 8, PI / 8.0)
	_scratch_marionette_tf.resize(_marionette_rim.size() + 1)
	_cannon_barrel_poly = PackedVector2Array([Vector2(22.0, -7.5), Vector2(CANNON_MUZZLE_RADIUS, -5.0), Vector2(CANNON_MUZZLE_RADIUS + 3.0, 0.0), Vector2(CANNON_MUZZLE_RADIUS, 5.0), Vector2(22.0, 7.5)])
	_cannon_slit_poly = PackedVector2Array([Vector2(26.0, -2.2), Vector2(CANNON_MUZZLE_RADIUS - 3.0, -1.6), Vector2(CANNON_MUZZLE_RADIUS - 3.0, 1.6), Vector2(26.0, 2.2)])
	Shapes.apply_radial_glow(boss_glow, [20.0, 32.0, 45.0, 60.0, 74.0, 88.0], [0.45, 0.28, 0.16, 0.08, 0.03, 0.0], 32, 0.65)
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
	_player_pos = _arena_size * 0.5
	current_phase = 1
	acting_state = ActingState.COCKY_CONDUCTOR
	boss_form = BossForm.CONDUCTOR
	_phase5_hands_awake = false
	total_wall_slams = 0
	total_parries = 0
	_shattered = false
	_intro_active = false
	_intro_progress = 0.0
	_intro_quick_mode = false
	_body_pos = Vector2(576.0 * s.x, 152.0 * s.y)
	_intro_target_pos = _body_pos
	_body_target = _body_pos
	_body_move_speed = 7.5
	_recoil_vel = Vector2.ZERO
	_teleport_grace_timer = 0.0
	global_position = _body_pos
	scale = Vector2.ONE
	rotation = 0.0

	_hands = [_make_hand_state(), _make_hand_state()]
	_hands[0]["pos"] = _body_pos + Vector2(-112.0 * s.x, 18.0 * s.y)
	_hands[1]["pos"] = _body_pos + Vector2(112.0 * s.x, 18.0 * s.y)
	_clear_active_attacks()
	_sync_hand_nodes()

	_last_beat_pulse = 0.0
	_freeze_timer = 0.0
	_double_blink_timer = 0.0
	_flinch_timer = 0.0
	_laugh_timer = 0.0
	_white_flash = 0.0
	_crack_intensity = 0.0
	_inflate_amount = 0.0
	_silence_freeze = false
	_was_laughing = false
	_spike_roll_angle = 0.0
	_cannon_angle = 0.0
	_sweat_shards.clear()
	_sweat_spawn_timer = 0.0
	_shatter_shards.clear()

	visible = true
	face_rig.visible = true
	face_rig.position = Vector2.ZERO
	face_rig.rotation = 0.0
	face_rig.scale = Vector2.ONE
	left_hand.visible = true
	right_hand.visible = true
	telegraph_line.clear_points()
	_active_crown_tier = -1
	_set_crown_for_phase_and_form(1, BossForm.CONDUCTOR)
	_set_hand_pose(0, HandPose.OPEN)
	_set_hand_pose(1, HandPose.OPEN)
	_set_eye_polygons(false)
	_sync_hazard_flags()
	_apply_visuals(0.0)
	queue_redraw()


func _clear_active_attacks() -> void:
	_lunge_active = false
	_lunge = _make_lunge_state()
	_lunge["prev"] = _body_pos
	_tether_active = false
	_mouth_beam_flash = 0.0
	telegraph_line.visible = false
	for idx: int in range(2):
		var prev: Dictionary = _hands[idx]
		var fresh: Dictionary = _make_hand_state()
		fresh["pos"] = prev["pos"]
		fresh["prev_pos"] = prev["pos"]
		fresh["rot"] = prev["rot"]
		fresh["pose"] = prev["pose"]
		fresh["retract_blend"] = prev["retract_blend"]
		_hands[idx] = fresh
	for key: String in _fx.keys():
		(_fx[key] as Array).clear()
	_pending_events.clear()


# ------------------------------------------------------------------------------
# PUBLIC CHOREOGRAPHER COMMAND API
# ------------------------------------------------------------------------------
func set_phase_state(phase: int, new_acting: ActingState, new_form: BossForm, body_target: Vector2, move_speed: float = 7.5) -> void:
	var prev_phase: int = current_phase
	current_phase = clampi(phase, 1, TOTAL_PHASES)
	acting_state = new_acting
	boss_form = new_form
	_body_target = body_target
	_body_move_speed = maxf(move_speed, 0.5)
	if current_phase != prev_phase:
		_clear_active_attacks()
		_phase5_hands_awake = false
		_silence_freeze = false
		_inflate_amount = 0.0
		_teleport_grace_timer = 0.0
		match new_acting:
			ActingState.FROZEN_DOUBLE_TAKE:
				_freeze_timer = 0.36
				_double_blink_timer = 0.62
			ActingState.FAKE_OUT_COLLAPSE:
				_flinch_timer = 0.0
				_laugh_timer = 0.0
				_white_flash = 1.0
				_crack_intensity = maxf(_crack_intensity, 0.62)
			ActingState.HOLLOW_REBIRTH: _crack_intensity = maxf(_crack_intensity, 0.35)
			ActingState.EXHAUSTED_PANTING: _crack_intensity = maxf(_crack_intensity, 0.55)
			ActingState.TEMPLE_CLUTCH_PANIC: _crack_intensity = maxf(_crack_intensity, 0.85)
			ActingState.SILENT_SHATTER:
				_flinch_timer = 0.0
				_laugh_timer = 0.0
	_set_crown_for_phase_and_form(current_phase, boss_form)
	command_retract_hands(boss_form == BossForm.SPIKE_ROLL or boss_form == BossForm.TRIPLE_CANNON)
	_sync_hazard_flags()
	if current_phase != prev_phase:
		phase_changed.emit(current_phase)


func set_body_target(target: Vector2, speed: float = 7.5) -> void:
	_body_target = target
	_body_move_speed = maxf(speed, 0.5)

func pulse_beat(strength: float = 1.0) -> void:
	_last_beat_pulse = clampf(strength, 0.0, 1.5)

func set_silence_freeze(frozen: bool, inflate: float = 0.0) -> void:
	_silence_freeze = frozen
	_inflate_amount = clampf(inflate, 0.0, 1.25)

func set_phase5_hands_awake(awake: bool) -> void:
	_phase5_hands_awake = awake
	if awake:
		_hands[0]["flash"] = 0.42
		_hands[1]["flash"] = 0.42
	_sync_hazard_flags()

func trigger_white_flash(amount: float = 1.0) -> void:
	_white_flash = maxf(_white_flash, clampf(amount, 0.0, 1.5))

func trigger_mouth_flare(duration: float = 0.35) -> void:
	_mouth_beam_flash = maxf(_mouth_beam_flash, maxf(duration, 0.05))

func set_cannon_angle(angle_rad: float) -> void:
	_cannon_angle = angle_rad

func get_hand_action(is_left: bool) -> HandAction:
	return int(_hands[0 if is_left else 1]["action"]) as HandAction


func command_teleport(to_pos: Vector2, arrival_grace: float = 0.35) -> void:
	var from_pos: Vector2 = _body_pos
	var dest: Vector2 = _clamp_combat_bounds(to_pos, _scale_vec())
	_lunge_active = false
	_lunge["tele"] = false
	_lunge["swept"] = false
	telegraph_line.visible = false
	(_fx["teleport"] as Array).append({"pos": from_pos, "kind": "depart", "life": 0.30, "max_life": 0.30})
	(_fx["teleport"] as Array).append({"pos": dest, "kind": "arrive", "life": maxf(arrival_grace, 0.25), "max_life": maxf(arrival_grace, 0.25)})
	(_fx["afterimages"] as Array).append({"pos": from_pos, "radius": BODY_RADIUS, "rot": face_rig.rotation, "shape": "oct", "life": 0.22, "max_life": 0.22})
	_body_pos = dest
	_body_target = dest
	_lunge["prev"] = dest
	global_position = dest
	_teleport_grace_timer = maxf(arrival_grace, 0.0)
	_white_flash = maxf(_white_flash, 0.55)
	for idx: int in range(2):
		if int(_hands[idx]["action"]) == HandAction.RETRACTED:
			_hands[idx]["pos"] = dest
			_hands[idx]["prev_pos"] = dest
	_sync_hand_nodes()
	_sync_hazard_flags()
	teleported.emit(from_pos, dest)


func command_body_lunge(from_pos: Vector2, to_pos: Vector2, telegraph_time: float, dash_time: float, emit_slam: bool = true) -> void:
	var s: Vector2 = _scale_vec()
	var c_from: Vector2 = _clamp_combat_bounds(from_pos, s)
	var c_to: Vector2 = _clamp_combat_bounds(to_pos, s)
	_lunge = {
		"tele": telegraph_time > 0.0, "start": c_from if telegraph_time > 0.0 else _body_pos,
		"target": c_to, "prev": _body_pos, "swept": false, "timer": 0.0,
		"tele_dur": maxf(telegraph_time, 0.0), "dash_dur": maxf(dash_time, 0.05), "emit_slam": emit_slam,
	}
	_lunge_active = telegraph_time <= 0.0
	_body_target = c_from if telegraph_time > 0.0 else c_to
	telegraph_line.visible = telegraph_time > 0.0
	if telegraph_time > 0.0:
		telegraph_line.points = PackedVector2Array([Vector2.ZERO, c_to - global_position])


func command_hand_pointer(is_left: bool, pos: Vector2, angle: float, hold_time: float) -> void:
	var h: Dictionary = _reset_hand_for_command(0 if is_left else 1)
	h["action"] = HandAction.POINTER_AIM
	h["target_pos"] = _clamp_perimeter_bounds(pos, _scale_vec())
	h["target_rot"] = angle
	h["duration"] = maxf(hold_time, 0.05)
	h["flash"] = 0.28


func command_hand_dash(is_left: bool, from_pos: Vector2, to_pos: Vector2, telegraph_time: float, dash_time: float, style: int = HandDashStyle.FIST_ROCKET) -> void:
	var s: Vector2 = _scale_vec()
	var cf: Vector2 = _clamp_hand_dash_bounds(from_pos, s)
	var ct: Vector2 = _clamp_hand_dash_bounds(to_pos, s)
	var ang: float = (ct - cf).angle() if ct.distance_squared_to(cf) > 1.0 else 0.0
	var h: Dictionary = _begin_staged_hand(0 if is_left else 1, cf, ct, ang, telegraph_time, dash_time, HandAction.DASH_TELEGRAPH, HandAction.DASH_ACTIVE)
	h["style"] = style


func command_hand_floor_slam(is_left: bool, target_pos: Vector2, telegraph_time: float, strike_time: float = 0.16, impact_mode: int = 1) -> void:
	var s: Vector2 = _scale_vec()
	var ct: Vector2 = _clamp_combat_bounds(target_pos, s)
	var h: Dictionary = _begin_staged_hand(0 if is_left else 1, _clamp_combat_bounds(ct + Vector2(0.0, -72.0 * s.y), s), ct, PI * 0.5, telegraph_time, strike_time, HandAction.FLOOR_SLAM_TELEGRAPH, HandAction.FLOOR_SLAM_ACTIVE)
	h["impact_mode"] = impact_mode


func command_wall_slam(is_left: bool, wall_side: StringName, coord: float, windup_time: float, strike_time: float = 0.16, strength: float = 0.78) -> void:
	var s: Vector2 = _scale_vec()
	var wall_pos: Vector2 = Vector2(24.0 * s.x, clampf(coord, 100.0 * s.y, _arena_size.y - 100.0 * s.y))
	var normal: Vector2 = Vector2.RIGHT
	match wall_side:
		&"right":
			wall_pos = Vector2(_arena_size.x - 24.0 * s.x, clampf(coord, 100.0 * s.y, _arena_size.y - 100.0 * s.y))
			normal = Vector2.LEFT
		&"top":
			wall_pos = Vector2(clampf(coord, 110.0 * s.x, _arena_size.x - 110.0 * s.x), 56.0 * s.y)
			normal = Vector2.DOWN
		&"bottom":
			wall_pos = Vector2(clampf(coord, 110.0 * s.x, _arena_size.x - 110.0 * s.x), _arena_size.y - 44.0 * s.y)
			normal = Vector2.UP
	var contact_pos: Vector2 = wall_pos + normal * HAND_RADIUS
	var h: Dictionary = _begin_staged_hand(0 if is_left else 1, contact_pos + normal * 86.0, contact_pos, (-normal).angle(), windup_time, strike_time, HandAction.WALL_SLAM_WINDUP, HandAction.WALL_SLAM_STRIKE)
	h["wall_pos"] = wall_pos
	h["normal"] = normal
	h["strength"] = clampf(strength, 0.25, 1.0)


func command_pincer(mid_pos: Vector2, telegraph_time: float, clap_time: float = 0.18) -> void:
	var s: Vector2 = _scale_vec()
	_pincer_mid = Vector2(clampf(mid_pos.x, 280.0 * s.x, _arena_size.x - 280.0 * s.x), clampf(mid_pos.y, 125.0 * s.y, _arena_size.y - 125.0 * s.y))
	for idx: int in range(2):
		var side: float = -1.0 if idx == 0 else 1.0
		_begin_staged_hand(idx, _clamp_combat_bounds(_pincer_mid + Vector2(side * 185.0 * s.x, 0.0), s), _clamp_combat_bounds(_pincer_mid + Vector2(side * 22.0 * s.x, 0.0), s), 0.0 if idx == 0 else PI, telegraph_time, clap_time, HandAction.PINCER_TELEGRAPH, HandAction.PINCER_CLAP)


func command_claw_orbit(duration: float, angular_speed: float = 3.6) -> void:
	for idx: int in range(2):
		var h: Dictionary = _reset_hand_for_command(idx)
		h["action"] = HandAction.ORBIT
		h["duration"] = maxf(duration, 0.10)
		h["orbit_angle"] = 0.0 if idx == 0 else PI
		h["orbit_speed"] = angular_speed


func command_tether_sweep(start_y: float, end_y: float, telegraph_time: float, sweep_time: float) -> void:
	var s: Vector2 = _scale_vec()
	var sy: float = clampf(start_y, 115.0 * s.y, _arena_size.y - 115.0 * s.y)
	var ey: float = clampf(end_y, 115.0 * s.y, _arena_size.y - 115.0 * s.y)
	_tether_active = telegraph_time <= 0.0
	for idx: int in range(2):
		var ax: float = (115.0 * s.x) if idx == 0 else (_arena_size.x - 115.0 * s.x)
		var h: Dictionary = _begin_staged_hand(idx, Vector2(ax, sy), Vector2(ax, ey), 0.0 if idx == 0 else PI, telegraph_time, maxf(sweep_time, 0.10), HandAction.TETHER_SWEEP, HandAction.TETHER_SWEEP)
		h["tether_start_y"] = sy
		h["tether_end_y"] = ey
		h["tether_active_phase"] = telegraph_time <= 0.0


func command_retract_hands(retracted: bool) -> void:
	if retracted:
		_tether_active = false
		for idx: int in range(2):
			_hands[idx]["action"] = HandAction.RETRACTED
			_hands[idx]["timer"] = 0.0
			_hands[idx]["swept"] = false
	else:
		for idx: int in range(2):
			if int(_hands[idx]["action"]) == HandAction.RETRACTED:
				_hands[idx]["action"] = HandAction.IDLE
				_hands[idx]["timer"] = 0.0
	_sync_hazard_flags()


func get_triple_cannon_muzzles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(3):
		var ang: float = _cannon_angle + TAU * float(i) / 3.0
		out.append({"pos": _body_pos + Vector2.from_angle(ang) * CANNON_MUZZLE_RADIUS, "angle": ang})
	return out


func enter_silent_shatter() -> void:
	_clear_active_attacks()
	acting_state = ActingState.SILENT_SHATTER
	boss_form = BossForm.SHATTERED
	_phase5_hands_awake = false
	_flinch_timer = 0.0
	_laugh_timer = 0.0
	_silence_freeze = false
	_teleport_grace_timer = 0.0
	_sync_hazard_flags()
	request_clear_hazards.emit()
	_apply_visuals(0.0)
	queue_redraw()


func shatter() -> void:
	if _shattered:
		return
	_shattered = true
	acting_state = ActingState.SILENT_SHATTER
	boss_form = BossForm.SHATTERED
	_phase5_hands_awake = false
	_clear_active_attacks()
	_flinch_timer = 0.0
	_laugh_timer = 0.0
	_teleport_grace_timer = 0.0
	_sync_hazard_flags()
	face_rig.visible = false
	left_hand.visible = false
	right_hand.visible = false
	_shatter_shards.clear()
	for i: int in range(28):
		var ang: float = TAU * float(i) / 28.0 + float(i % 3) * 0.11
		_shatter_shards.append({"offset": Vector2.from_angle(ang) * (16.0 + float((i * 17) % 44)), "rot": ang + float(i) * 0.5, "size": 5.0 + float(i % 4) * 2.8, "gray": 0.72 + float(i % 3) * 0.14})
	boss_slammed.emit(global_position, 1.0)
	queue_redraw()


func _reset_hand_for_command(idx: int) -> Dictionary:
	if int(_hands[idx]["action"]) == HandAction.TETHER_SWEEP:
		_tether_active = false
	var h: Dictionary = _hands[idx]
	h["timer"] = 0.0
	h["duration"] = 0.0
	h["next_duration"] = 0.0
	h["swept"] = false
	h["tether_active_phase"] = false
	return h


func _begin_staged_hand(idx: int, stage_pos: Vector2, target_pos: Vector2, target_rot: float, tele_time: float, active_time: float, tele_action: int, active_action: int) -> Dictionary:
	var h: Dictionary = _reset_hand_for_command(idx)
	h["start_pos"] = Vector2(h["pos"])
	h["stage_pos"] = stage_pos
	h["target_pos"] = target_pos
	h["target_rot"] = target_rot
	h["next_duration"] = maxf(active_time, 0.05)
	h["action"] = tele_action if tele_time > 0.0 else active_action
	h["duration"] = tele_time if tele_time > 0.0 else float(h["next_duration"])
	return h


# ------------------------------------------------------------------------------
# PARRY & REACTION CALLBACKS
# ------------------------------------------------------------------------------
func on_player_parried(from_pos: Vector2) -> void:
	if _shattered or acting_state == ActingState.SILENT_SHATTER:
		return
	total_parries += 1
	_flinch_timer = 0.45
	_white_flash = 0.90
	_crack_intensity = minf(1.0, _crack_intensity + 0.10)
	_recoil_vel = ((_body_pos - from_pos).normalized() if _body_pos.distance_squared_to(from_pos) > 1.0 else Vector2.UP) * 240.0
	boss_parried.emit(global_position)
	_apply_visuals(0.0)
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


# ------------------------------------------------------------------------------
# SIMULATION STEP & EXCLUSIVE STATE MACHINES
# ------------------------------------------------------------------------------
func simulate_boss(delta: float, elapsed_time: float, arena_size: Vector2, player_node: Node2D) -> void:
	_arena_size = _resolve_arena_size(arena_size)
	var dt: float = maxf(delta, 0.0)
	_last_sim_delta = dt
	_elapsed_time = maxf(elapsed_time, 0.0)
	_player_pos = player_node.global_position if (player_node != null and is_instance_valid(player_node)) else (_arena_size * 0.5)
	if _intro_active:
		_sync_hazard_flags()
		return
	if _shattered:
		return
	_tick_timers(dt)
	for key: String in _fx.keys():
		var arr: Array = _fx[key]
		for i: int in range(arr.size() - 1, -1, -1):
			arr[i]["life"] = float(arr[i]["life"]) - dt
			if float(arr[i]["life"]) <= 0.0:
				arr.remove_at(i)
	_update_motion(dt)
	_update_sweat_shards(dt)
	_sync_hazard_flags()
	_flush_pending_events()
	_check_contact_damage(player_node)
	_apply_visuals(dt)
	queue_redraw()


func _tick_timers(dt: float) -> void:
	_last_beat_pulse = maxf(0.0, _last_beat_pulse - dt * 3.8)
	_freeze_timer = maxf(0.0, _freeze_timer - dt)
	_double_blink_timer = maxf(0.0, _double_blink_timer - dt)
	_flinch_timer = maxf(0.0, _flinch_timer - dt)
	_laugh_timer = maxf(0.0, _laugh_timer - dt)
	_white_flash = maxf(0.0, _white_flash - dt * 3.0)
	_mouth_beam_flash = maxf(0.0, _mouth_beam_flash - dt)
	_teleport_grace_timer = maxf(0.0, _teleport_grace_timer - dt)
	_hands[0]["flash"] = maxf(0.0, float(_hands[0]["flash"]) - dt)
	_hands[1]["flash"] = maxf(0.0, float(_hands[1]["flash"]) - dt)
	if boss_form == BossForm.SPIKE_ROLL:
		_spike_roll_angle += dt * (15.0 if _lunge_active else 8.5)


func _update_motion(dt: float) -> void:
	var s: Vector2 = _scale_vec()
	_lunge["swept"] = false
	if _recoil_vel.length_squared() > 1.0:
		if not _lunge_active:
			_body_pos = _clamp_combat_bounds(_body_pos + _recoil_vel * dt, s)
		_recoil_vel = _recoil_vel.move_toward(Vector2.ZERO, 1350.0 * dt)
	else:
		_recoil_vel = Vector2.ZERO
	_step_body_motion(dt, s)
	global_position = _body_pos
	for idx: int in range(2):
		_step_hand(idx, dt, s)
	_sync_hand_nodes()
	_tether_active = int(_hands[0]["action"]) == HandAction.TETHER_SWEEP and int(_hands[1]["action"]) == HandAction.TETHER_SWEEP and bool(_hands[0]["tether_active_phase"]) and bool(_hands[1]["tether_active_phase"])


func _step_body_motion(dt: float, s: Vector2) -> void:
	var rem: float = dt
	if bool(_lunge["tele"]):
		_lunge["timer"] = float(_lunge["timer"]) + rem
		var t_dur: float = float(_lunge["tele_dur"])
		var max_spd: float = MAX_BODY_OVERDRIVE_SPEED if current_phase == 8 else MAX_BODY_REPOSITION_SPEED
		var stage_spd: float = maxf(max_spd, _body_pos.distance_to(Vector2(_lunge["start"])) / maxf(t_dur - float(_lunge["timer"]), 0.06))
		_body_pos = _body_pos.move_toward(Vector2(_lunge["start"]), stage_spd * rem)
		telegraph_line.visible = true
		telegraph_line.points = PackedVector2Array([Vector2.ZERO, Vector2(_lunge["target"]) - _body_pos])
		if float(_lunge["timer"]) >= t_dur:
			rem = float(_lunge["timer"]) - t_dur
			_lunge["tele"] = false
			_lunge["start"] = _body_pos
			_lunge["timer"] = 0.0
			_lunge_active = true
			telegraph_line.visible = false
		else:
			return
	if _lunge_active:
		_lunge["prev"] = _body_pos
		_lunge["swept"] = true
		_lunge["timer"] = float(_lunge["timer"]) + rem
		var p: float = clampf(float(_lunge["timer"]) / maxf(float(_lunge["dash_dur"]), 0.001), 0.0, 1.0)
		_body_pos = Vector2(_lunge["start"]).lerp(Vector2(_lunge["target"]), ease(p, 0.45))
		(_fx["afterimages"] as Array).append({"pos": _body_pos, "radius": BODY_RADIUS * 0.92, "rot": _spike_roll_angle if boss_form == BossForm.SPIKE_ROLL else 0.0, "shape": "oct", "life": 0.16, "max_life": 0.16})
		if p >= 1.0:
			_lunge_active = false
			_body_pos = Vector2(_lunge["target"])
			_body_target = _body_pos
			_pending_events.append({"kind": &"lunge_impact", "pos": _body_pos, "emit_slam": bool(_lunge["emit_slam"])})
		return
	telegraph_line.visible = false
	var bob_y: float = sin(_elapsed_time * TAU / (BEAT_DURATION * 2.0)) * (7.0 if acting_state == ActingState.COCKY_CONDUCTOR else (6.0 if (acting_state == ActingState.EXHAUSTED_PANTING or boss_form == BossForm.STOMP_COLOSSUS) else 0.0)) * s.y
	var desired: Vector2 = _body_pos if (_freeze_timer > 0.0 or _silence_freeze) else Vector2(_body_target.x, maxf(_body_target.y + bob_y, 112.0 * s.y))
	var max_b: float = MAX_BODY_OVERDRIVE_SPEED if current_phase == 8 else MAX_BODY_REPOSITION_SPEED
	_body_pos = _body_pos.move_toward(_body_pos.lerp(desired, clampf(_body_move_speed * dt, 0.0, 1.0)), max_b * dt)


func _step_stage_phase(h: Dictionary, rem: float, next_action: int, rot_mult: float = 1.0) -> float:
	h["retract_blend"] = clampf(float(h["retract_blend"]) - rem * 9.0, 0.0, 1.0)
	h["timer"] = float(h["timer"]) + rem
	var dur: float = maxf(float(h["duration"]), 0.001)
	var p: float = clampf(float(h["timer"]) / dur, 0.0, 1.0)
	h["pos"] = Vector2(h["start_pos"]).lerp(Vector2(h["stage_pos"]), ease(p, 0.55))
	h["rot"] = rotate_toward(float(h["rot"]), float(h["target_rot"]), MAX_HAND_ROT_SPEED * rot_mult * rem)
	if float(h["timer"]) >= dur:
		var overflow: float = float(h["timer"]) - dur
		h["pos"] = Vector2(h["stage_pos"])
		h["start_pos"] = Vector2(h["stage_pos"])
		h["action"] = next_action
		h["timer"] = 0.0
		h["duration"] = maxf(float(h["next_duration"]), 0.05)
		return overflow
	return -1.0


func _step_lerp_active(h: Dictionary, rem: float, ease_exp: float) -> float:
	h["retract_blend"] = 0.0
	h["prev_pos"] = Vector2(h["pos"])
	h["swept"] = true
	h["timer"] = float(h["timer"]) + rem
	var p: float = clampf(float(h["timer"]) / maxf(float(h["duration"]), 0.001), 0.0, 1.0)
	h["pos"] = Vector2(h["start_pos"]).lerp(Vector2(h["target_pos"]), p if absf(ease_exp - 1.0) < 0.001 else ease(p, ease_exp))
	return p


func _step_hand(idx: int, dt: float, s: Vector2) -> void:
	var h: Dictionary = _hands[idx]
	h["swept"] = false
	var rem: float = dt
	var pose: HandPose = HandPose.OPEN

	for _iter: int in range(3):
		var act: int = int(h["action"])
		var cur_pos: Vector2 = Vector2(h["pos"])
		var cur_rot: float = float(h["rot"])
		var max_spd: float = MAX_HAND_OVERDRIVE_SPEED if current_phase == 8 else MAX_HAND_REPOSITION_SPEED
		match act:
			HandAction.RETRACTED:
				h["retract_blend"] = clampf(float(h["retract_blend"]) + rem * 7.0, 0.0, 1.0)
				var np: Vector2 = cur_pos.lerp(_body_pos, clampf(rem * 14.0, 0.0, 1.0))
				h["pos"] = _body_pos if np.distance_to(_body_pos) < 4.0 else np
				h["rot"] = rotate_toward(cur_rot, 0.0, MAX_HAND_ROT_SPEED * rem)
				pose = HandPose.FIST
				break
			HandAction.IDLE:
				h["retract_blend"] = clampf(float(h["retract_blend"]) - rem * 7.0, 0.0, 1.0)
				var idle: Array = _compute_idle_hand_target(idx, s)
				h["pos"] = cur_pos.move_toward(Vector2(idle[0]), max_spd * rem)
				h["rot"] = rotate_toward(cur_rot, float(idle[1]), MAX_HAND_ROT_SPEED * rem)
				pose = int(idle[2]) as HandPose
				break
			HandAction.POINTER_AIM:
				h["retract_blend"] = clampf(float(h["retract_blend"]) - rem * 9.0, 0.0, 1.0)
				h["timer"] = float(h["timer"]) + rem
				pose = HandPose.POINTER
				h["pos"] = cur_pos.move_toward(Vector2(h["target_pos"]), max_spd * 1.35 * rem)
				h["rot"] = rotate_toward(cur_rot, float(h["target_rot"]), MAX_HAND_ROT_SPEED * 1.4 * rem)
				if float(h["timer"]) >= float(h["duration"]):
					h["action"] = HandAction.IDLE
					h["timer"] = 0.0
				break
			HandAction.DASH_TELEGRAPH:
				pose = _pose_for_dash_style(int(h["style"]))
				var ov: float = _step_stage_phase(h, rem, HandAction.DASH_ACTIVE, 1.4)
				if ov > 0.0:
					rem = ov
					continue
				break
			HandAction.DASH_ACTIVE:
				var style: int = int(h["style"])
				var p: float = _step_lerp_active(h, rem, 1.0 if style == HandDashStyle.FLOOR_RAKE else 0.42)
				var np: Vector2 = Vector2(h["pos"])
				var ang: float = float(h["target_rot"])
				h["rot"] = ang
				pose = _pose_for_dash_style(style)
				if style == HandDashStyle.CLAW_SWIPE:
					(_fx["slash"] as Array).append({"pos": np, "rot": ang, "radius": 28.0, "life": 0.16, "max_life": 0.16})
				elif style == HandDashStyle.FLOOR_RAKE:
					(_fx["rake"] as Array).append({"from": cur_pos, "to": np, "life": 0.44, "max_life": 0.44})
				(_fx["afterimages"] as Array).append({"pos": np, "radius": 16.0, "rot": ang, "shape": "diamond", "life": 0.14, "max_life": 0.14})
				if p >= 1.0:
					h["pos"] = Vector2(h["target_pos"])
					h["flash"] = 0.28
					h["action"] = HandAction.IDLE
					_pending_events.append({"kind": &"slam", "pos": Vector2(h["target_pos"]), "strength": 0.48})
				break
			HandAction.FLOOR_SLAM_TELEGRAPH:
				pose = HandPose.FIST
				var ov: float = _step_stage_phase(h, rem, HandAction.FLOOR_SLAM_ACTIVE, 1.0)
				if ov > 0.0:
					rem = ov
					continue
				break
			HandAction.FLOOR_SLAM_ACTIVE:
				var p: float = _step_lerp_active(h, rem, 1.8)
				h["rot"] = PI * 0.5
				pose = HandPose.FIST
				if p >= 1.0:
					h["pos"] = Vector2(h["target_pos"])
					h["flash"] = 0.34
					h["action"] = HandAction.IDLE
					_pending_events.append({"kind": &"floor_slam", "is_left": idx == 0, "pos": Vector2(h["target_pos"]), "mode": int(h["impact_mode"])})
				break
			HandAction.WALL_SLAM_WINDUP:
				pose = HandPose.CLAW if acting_state == ActingState.FAKE_OUT_COLLAPSE else HandPose.FIST
				var ov: float = _step_stage_phase(h, rem, HandAction.WALL_SLAM_STRIKE, 1.4)
				if ov > 0.0:
					rem = ov
					continue
				break
			HandAction.WALL_SLAM_STRIKE:
				var p: float = _step_lerp_active(h, rem, 1.0)
				h["rot"] = rotate_toward(cur_rot, float(h["target_rot"]), MAX_HAND_ROT_SPEED * 2.0 * rem)
				pose = HandPose.CLAW if acting_state == ActingState.FAKE_OUT_COLLAPSE else HandPose.FIST
				(_fx["afterimages"] as Array).append({"pos": Vector2(h["pos"]), "radius": 15.0, "rot": float(h["rot"]), "shape": "diamond", "life": 0.13, "max_life": 0.13})
				if p >= 1.0:
					h["pos"] = Vector2(h["target_pos"])
					h["rot"] = float(h["target_rot"])
					h["flash"] = 0.34
					h["action"] = HandAction.WALL_SLAM_RECOVER
					h["timer"] = 0.0
					h["duration"] = 0.14
					_pending_events.append({"kind": &"wall_slam", "wall_pos": Vector2(h["wall_pos"]), "normal": Vector2(h["normal"]), "strength": float(h["strength"])})
				break
			HandAction.WALL_SLAM_RECOVER:
				h["timer"] = float(h["timer"]) + rem
				var p: float = clampf(float(h["timer"]) / maxf(float(h["duration"]), 0.001), 0.0, 1.0)
				var cp: Vector2 = Vector2(h["target_pos"])
				h["pos"] = cp.lerp(cp + Vector2(h["normal"]) * 16.0, p)
				h["rot"] = float(h["target_rot"])
				pose = HandPose.CLAW if acting_state == ActingState.FAKE_OUT_COLLAPSE else HandPose.FIST
				if p >= 1.0:
					h["action"] = HandAction.IDLE
				break
			HandAction.PINCER_TELEGRAPH:
				pose = HandPose.FIST
				var ov: float = _step_stage_phase(h, rem, HandAction.PINCER_CLAP, 1.0)
				if ov > 0.0:
					rem = ov
					continue
				break
			HandAction.PINCER_CLAP:
				var p: float = _step_lerp_active(h, rem, 0.42)
				h["rot"] = float(h["target_rot"])
				pose = HandPose.FIST
				(_fx["afterimages"] as Array).append({"pos": Vector2(h["pos"]), "radius": 15.0, "rot": float(h["rot"]), "shape": "diamond", "life": 0.13, "max_life": 0.13})
				if p >= 1.0:
					h["pos"] = Vector2(h["target_pos"])
					h["flash"] = 0.32
					h["action"] = HandAction.IDLE
					if idx == 0:
						_pending_events.append({"kind": &"slam", "pos": _pincer_mid, "strength": 0.65})
				break
			HandAction.ORBIT:
				h["retract_blend"] = 0.0
				h["prev_pos"] = cur_pos
				h["swept"] = true
				h["timer"] = float(h["timer"]) + rem
				var p: float = clampf(float(h["timer"]) / maxf(float(h["duration"]), 0.001), 0.0, 1.0)
				var ang: float = float(h["orbit_angle"]) + rem * float(h["orbit_speed"])
				h["orbit_angle"] = ang
				var rad: float = lerpf(88.0, 158.0, sin(p * PI * 0.5)) * minf(s.x, s.y)
				var np: Vector2 = _clamp_combat_bounds(_body_pos + Vector2.from_angle(ang) * rad, s)
				h["pos"] = np
				h["rot"] = ang + PI * 0.5
				pose = HandPose.CLAW
				(_fx["slash"] as Array).append({"pos": np, "rot": float(h["rot"]), "radius": 24.0, "life": 0.12, "max_life": 0.12})
				if p >= 1.0:
					h["action"] = HandAction.IDLE
				break
			HandAction.TETHER_SWEEP:
				pose = HandPose.POINTER
				if not bool(h["tether_active_phase"]):
					var ov: float = _step_stage_phase(h, rem, HandAction.TETHER_SWEEP, 1.0)
					if ov >= 0.0:
						h["tether_active_phase"] = true
						if ov > 0.0:
							rem = ov
							continue
				else:
					h["prev_pos"] = cur_pos
					h["swept"] = true
					h["timer"] = float(h["timer"]) + rem
					var p: float = clampf(float(h["timer"]) / maxf(float(h["duration"]), 0.001), 0.0, 1.0)
					h["pos"] = Vector2(Vector2(h["stage_pos"]).x, lerpf(float(h["tether_start_y"]), float(h["tether_end_y"]), p))
					h["rot"] = float(h["target_rot"])
					if p >= 1.0:
						h["action"] = HandAction.IDLE
						h["tether_active_phase"] = false
				break
	_set_hand_pose(idx, pose)


func _compute_idle_hand_target(idx: int, s: Vector2) -> Array:
	var is_left: bool = idx == 0
	var side: float = -1.0 if is_left else 1.0
	var target: Vector2 = _body_pos + Vector2(side * 112.0 * s.x, 18.0 * s.y)
	var rot: float = 0.0
	var pose: HandPose = HandPose.OPEN
	match acting_state:
		ActingState.COCKY_CONDUCTOR:
			target.y += (-side) * sin(_elapsed_time * TAU / BEAT_DURATION) * 11.0 * s.y
		ActingState.FROZEN_DOUBLE_TAKE:
			target = _body_pos + Vector2(side * 120.0 * s.x, 10.0 * s.y)
		ActingState.FLOOR_SLAM_TANTRUM:
			pose = HandPose.FIST
			target = _body_pos + Vector2(side * 108.0 * s.x, 54.0 * s.y)
		ActingState.ACCUSING_POINT:
			pose = HandPose.FIST if is_left else HandPose.POINTER
			target = _clamp_combat_bounds(_body_pos + (Vector2(-90.0 * s.x, 22.0 * s.y) + Vector2(sin(_elapsed_time * 42.0) * 3.0, cos(_elapsed_time * 38.0) * 3.0) if is_left else Vector2(104.0 * s.x, -18.0 * s.y)), s)
			if not is_left:
				rot = (_player_pos - target).angle()
		ActingState.FAKE_OUT_COLLAPSE:
			pose = HandPose.CLAW if _phase5_hands_awake else HandPose.OPEN
			var tw: float = sin(_elapsed_time * 32.0) * 7.0 if (_inflate_amount > 0.05 or _phase5_hands_awake) and not _silence_freeze else 0.0
			target = Vector2((445.0 if is_left else 707.0) * s.x + side * tw, 505.0 * s.y)
			rot = side * 0.35
		ActingState.HOLLOW_REBIRTH:
			pose = HandPose.CLAW
			target = _clamp_combat_bounds(_body_pos + Vector2(side * 102.0 * s.x, 24.0 * s.y), s)
			rot = (-side) * sin(_elapsed_time * 3.0) * 0.35
		ActingState.EXHAUSTED_PANTING:
			pose = HandPose.FIST
			target = _body_pos + Vector2(side * 114.0 * s.x, 66.0 * s.y + sin(_elapsed_time * TAU / (BEAT_DURATION * 2.0)) * 8.0 * s.y)
		ActingState.TEMPLE_CLUTCH_PANIC, ActingState.SILENT_SHATTER:
			pose = HandPose.CLAW
			var sh: Vector2 = Vector2(sin(_elapsed_time * 55.0) * 3.2, cos(_elapsed_time * 47.0) * 3.2) if acting_state == ActingState.TEMPLE_CLUTCH_PANIC else Vector2.ZERO
			target = _clamp_combat_bounds(_body_pos + Vector2(side * 44.0 * s.x, -11.0 * s.y) + (-side) * sh, s)
			rot = (-side) * 0.35
	target.y = maxf(target.y, 84.0 * s.y)
	return [target, rot, pose]


func _sync_hand_nodes() -> void:
	var nodes: Array[Area2D] = [left_hand, right_hand]
	for idx: int in range(2):
		var blend: float = float(_hands[idx]["retract_blend"])
		nodes[idx].global_position = Vector2(_hands[idx]["pos"])
		nodes[idx].rotation = float(_hands[idx]["rot"])
		nodes[idx].scale = Vector2.ONE * maxf(1.0 - blend, 0.0)
		nodes[idx].visible = (not _shattered) and blend < 0.96


func _flush_pending_events() -> void:
	if _pending_events.is_empty():
		return
	var events: Array[Dictionary] = _pending_events.duplicate()
	_pending_events.clear()
	for ev: Dictionary in events:
		match StringName(ev["kind"]):
			&"wall_slam":
				var wp: Vector2 = Vector2(ev["wall_pos"])
				var n: Vector2 = Vector2(ev["normal"])
				var st: float = float(ev["strength"])
				(_fx["cracks"] as Array).append({"pos": wp, "normal": n, "life": 0.55, "max_life": 0.55, "strength": st})
				total_wall_slams += 1
				boss_wall_slammed.emit(wp, n, st)
			&"floor_slam":
				var fp: Vector2 = Vector2(ev["pos"])
				boss_slammed.emit(fp, 0.52)
				hand_slam_impact.emit(bool(ev["is_left"]), fp, int(ev["mode"]))
			&"lunge_impact":
				var lp: Vector2 = Vector2(ev["pos"])
				lunge_impact.emit(lp)
				if bool(ev["emit_slam"]):
					boss_slammed.emit(lp, 0.58)
			&"slam":
				boss_slammed.emit(Vector2(ev["pos"]), float(ev["strength"]))


# ------------------------------------------------------------------------------
# HAZARD FLAGS & CONTACT DAMAGE
# ------------------------------------------------------------------------------
func _is_hand_retracted(idx: int) -> bool:
	return int(_hands[idx]["action"]) == HandAction.RETRACTED and float(_hands[idx]["retract_blend"]) > 0.45

func _is_hand_action_parryable(idx: int) -> bool:
	return int(_hands[idx]["action"]) in [HandAction.DASH_ACTIVE, HandAction.WALL_SLAM_STRIKE, HandAction.FLOOR_SLAM_ACTIVE, HandAction.PINCER_CLAP, HandAction.ORBIT]

func set_intro_state(active: bool, progress: float, arena_size: Vector2, quick_mode: bool = false) -> void:
	_arena_size = _resolve_arena_size(arena_size)
	var s: Vector2 = _scale_vec()
	var target_pos: Vector2 = Vector2(576.0 * s.x, 152.0 * s.y)
	_intro_target_pos = target_pos
	visible = true
	scale = Vector2.ONE
	rotation = 0.0
	_shattered = false

	if active:
		_intro_active = true
		var p: float = clampf(progress, 0.0, 1.0)
		_intro_progress = p
		_intro_quick_mode = quick_mode

		var intro_face_visible: bool = true
		var intro_face_scale: Vector2 = Vector2.ONE
		var intro_hands_visible: bool = false
		var wide_open_eyes: bool = false
		_white_flash = 0.0
		_hands[0]["rot"] = 0.0
		_hands[1]["rot"] = 0.0
		_hands[0]["flash"] = 0.0
		_hands[1]["flash"] = 0.0
		_hands[0]["retract_blend"] = 0.0
		_hands[1]["retract_blend"] = 0.0
		_set_hand_pose(0, HandPose.OPEN)
		_set_hand_pose(1, HandPose.OPEN)
		_set_eye_polygons(false)

		if not quick_mode:
			if p < 0.42:
				_body_pos = Vector2(target_pos.x, -120.0 * s.y)
				intro_face_visible = false
				intro_hands_visible = false
				_hands[0]["pos"] = _body_pos
				_hands[1]["pos"] = _body_pos
			elif p < 0.50:
				var drop_t: float = ease((p - 0.42) / 0.08, 2.2)
				_body_pos = Vector2(target_pos.x, lerpf(-120.0 * s.y, target_pos.y, drop_t))
				intro_face_visible = true
				intro_face_scale = Vector2(0.84, 1.24)
				intro_hands_visible = false
				_hands[0]["pos"] = _body_pos
				_hands[1]["pos"] = _body_pos
			elif p < 0.64:
				var settle_t: float = clampf((p - 0.50) / 0.14, 0.0, 1.0)
				var settle_e: float = ease(settle_t, 0.4)
				_body_pos = target_pos
				intro_face_visible = true
				intro_face_scale = Vector2(lerpf(1.26, 1.0, settle_e), lerpf(0.76, 1.0, settle_e))
				wide_open_eyes = true
				intro_hands_visible = false
				_white_flash = maxf(0.0, 1.0 - settle_t)
				_hands[0]["pos"] = target_pos
				_hands[1]["pos"] = target_pos
			else:
				var hb_t: float = ease(clampf((p - 0.64) / 0.24, 0.0, 1.0), 0.35)
				_body_pos = target_pos
				intro_face_visible = true
				intro_face_scale = Vector2.ONE
				intro_hands_visible = true
				_hands[0]["pos"] = target_pos.lerp(target_pos + Vector2(-112.0 * s.x, 18.0 * s.y), hb_t)
				_hands[1]["pos"] = target_pos.lerp(target_pos + Vector2(112.0 * s.x, 18.0 * s.y), hb_t)
				var h_flash: float = maxf(0.0, 1.0 - (p - 0.64) / 0.25)
				_hands[0]["flash"] = h_flash
				_hands[1]["flash"] = h_flash
		else:
			if p < 0.45:
				var q_drop: float = ease(p / 0.45, 2.0)
				_body_pos = Vector2(target_pos.x, lerpf(-90.0 * s.y, target_pos.y, q_drop))
				intro_face_visible = true
				intro_face_scale = Vector2(0.86, 1.20)
				intro_hands_visible = false
				_hands[0]["pos"] = _body_pos
				_hands[1]["pos"] = _body_pos
			else:
				var q_settle: float = clampf((p - 0.45) / 0.25, 0.0, 1.0)
				var q_e: float = ease(q_settle, 0.4)
				var q_hb: float = ease(clampf((p - 0.45) / 0.35, 0.0, 1.0), 0.35)
				_body_pos = target_pos
				intro_face_visible = true
				intro_face_scale = Vector2(lerpf(1.22, 1.0, q_e), lerpf(0.78, 1.0, q_e))
				intro_hands_visible = true
				_white_flash = maxf(0.0, 1.0 - q_settle)
				_hands[0]["pos"] = target_pos.lerp(target_pos + Vector2(-112.0 * s.x, 18.0 * s.y), q_hb)
				_hands[1]["pos"] = target_pos.lerp(target_pos + Vector2(112.0 * s.x, 18.0 * s.y), q_hb)
				var q_flash: float = maxf(0.0, 1.0 - (p - 0.45) / 0.30)
				_hands[0]["flash"] = q_flash
				_hands[1]["flash"] = q_flash

		_body_target = _body_pos
		global_position = _body_pos
		_sync_hand_nodes()
		_sync_hazard_flags()
		_apply_visuals(0.0)
		face_rig.visible = intro_face_visible
		face_rig.scale = intro_face_scale
		left_hand.visible = intro_hands_visible
		right_hand.visible = intro_hands_visible
		if wide_open_eyes:
			left_eye_polygon.scale = Vector2.ONE
			right_eye_polygon.scale = Vector2.ONE
		queue_redraw()
		return

	_intro_active = false
	_intro_progress = 1.0
	_intro_quick_mode = false
	_white_flash = 0.0
	_hands[0]["flash"] = 0.0
	_hands[1]["flash"] = 0.0
	_hands[0]["rot"] = 0.0
	_hands[1]["rot"] = 0.0
	_hands[0]["retract_blend"] = 0.0
	_hands[1]["retract_blend"] = 0.0
	_body_pos = target_pos
	_body_target = target_pos
	global_position = target_pos
	_hands[0]["pos"] = target_pos + Vector2(-112.0 * s.x, 18.0 * s.y)
	_hands[1]["pos"] = target_pos + Vector2(112.0 * s.x, 18.0 * s.y)
	_set_hand_pose(0, HandPose.OPEN)
	_set_hand_pose(1, HandPose.OPEN)
	_set_eye_polygons(false)
	_sync_hand_nodes()
	_sync_hazard_flags()
	_apply_visuals(0.0)
	face_rig.visible = true
	face_rig.scale = Vector2.ONE
	left_hand.visible = true
	right_hand.visible = true
	queue_redraw()


func _sync_hazard_flags() -> void:
	if _intro_active:
		is_body_hazardous = false
		is_left_hand_hazardous = false
		is_right_hand_hazardous = false
		is_hand_hazardous = false
		body_collision.disabled = true
		left_hand_collision.disabled = true
		right_hand_collision.disabled = true
		return
	if _shattered or acting_state == ActingState.SILENT_SHATTER or boss_form == BossForm.SHATTERED:
		is_body_hazardous = false
		is_left_hand_hazardous = false
		is_right_hand_hazardous = false
	elif acting_state == ActingState.FAKE_OUT_COLLAPSE:
		is_body_hazardous = false
		is_left_hand_hazardous = _phase5_hands_awake and not _is_hand_retracted(0)
		is_right_hand_hazardous = _phase5_hands_awake and not _is_hand_retracted(1)
	else:
		is_body_hazardous = (_teleport_grace_timer <= 0.0)
		is_left_hand_hazardous = not _is_hand_retracted(0)
		is_right_hand_hazardous = not _is_hand_retracted(1)
	is_hand_hazardous = is_left_hand_hazardous or is_right_hand_hazardous
	body_collision.disabled = not is_body_hazardous
	left_hand_collision.disabled = not is_left_hand_hazardous
	right_hand_collision.disabled = not is_right_hand_hazardous

func _on_body_entered(body: Node2D) -> void:
	_handle_contact_body(body, is_body_hazardous, _lunge_active)

func _on_left_hand_body_entered(body: Node2D) -> void:
	_handle_contact_body(body, is_left_hand_hazardous, _is_hand_action_parryable(0))

func _on_right_hand_body_entered(body: Node2D) -> void:
	_handle_contact_body(body, is_right_hand_hazardous, _is_hand_action_parryable(1))

func _handle_contact_body(body: Node2D, hazardous: bool, parryable: bool) -> void:
	if _elapsed_time >= SPAWN_GRACE_DURATION and hazardous and body != null and body.is_in_group("player") and body.has_method("take_damage"):
		body.set_meta(&"last_hit_parryable", parryable)
		body.take_damage(1)

func _check_contact_damage(player_node: Node2D) -> void:
	if (_elapsed_time < SPAWN_GRACE_DURATION and (_elapsed_time > 0.0 or _last_sim_delta > 0.0)) or player_node == null or not is_instance_valid(player_node) or not player_node.has_method("take_damage"):
		return
	var player_radius: float = 12.0 * clampf(player_node.scale.x, 0.5, 1.5)
	var p_pos: Vector2 = player_node.global_position
	if is_body_hazardous:
		var cb: Vector2 = Geometry2D.get_closest_point_to_segment(p_pos, Vector2(_lunge["prev"]), global_position) if bool(_lunge["swept"]) else global_position
		if cb.distance_to(p_pos) <= BODY_RADIUS + player_radius:
			player_node.set_meta(&"last_hit_parryable", _lunge_active)
			player_node.take_damage(1)
			return
	for idx: int in range(2):
		if not (is_left_hand_hazardous if idx == 0 else is_right_hand_hazardous):
			continue
		var h: Dictionary = _hands[idx]
		var hp: Vector2 = left_hand.global_position if idx == 0 else right_hand.global_position
		var ch: Vector2 = Geometry2D.get_closest_point_to_segment(p_pos, Vector2(h["prev_pos"]), hp) if bool(h["swept"]) else hp
		if ch.distance_to(p_pos) <= HAND_RADIUS + player_radius:
			player_node.set_meta(&"last_hit_parryable", _is_hand_action_parryable(idx))
			player_node.take_damage(1)
			return
	if _tether_active:
		var lp: Vector2 = left_hand.global_position
		var rp: Vector2 = right_hand.global_position
		var tether_r: float = 5.0 + player_radius
		var hit_t: bool = Geometry2D.get_closest_point_to_segment(p_pos, lp, rp).distance_to(p_pos) <= tether_r
		if not hit_t and p_pos.x >= minf(lp.x, rp.x) - player_radius and p_pos.x <= maxf(lp.x, rp.x) + player_radius:
			var prev_y: float = Vector2(_hands[0]["prev_pos"]).y
			hit_t = p_pos.y >= minf(prev_y, lp.y) - tether_r and p_pos.y <= maxf(prev_y, lp.y) + tether_r
		if hit_t:
			player_node.set_meta(&"last_hit_parryable", true)
			player_node.take_damage(1)


# ------------------------------------------------------------------------------
# FACIAL RIG, FORM VISUALS & CUSTOM _draw() RENDERING
# ------------------------------------------------------------------------------
func _apply_visuals(_dt: float) -> void:
	var rig_scale: Vector2 = Vector2.ONE
	var rig_rot: float = 0.0
	var rig_off: Vector2 = Vector2.ZERO
	var eye_l: Vector2 = Vector2.ONE
	var eye_r: Vector2 = Vector2.ONE
	var p_scale: float = 1.0
	var show_p: bool = true
	var hollow: bool = false
	var dim: float = 1.0
	var p_jit: Vector2 = Vector2.ZERO

	match acting_state:
		ActingState.COCKY_CONDUCTOR:
			rig_scale = Vector2(1.0 + 0.045 * _last_beat_pulse, 1.0 - 0.032 * _last_beat_pulse)
			eye_l = Vector2(1.0, 0.65)
			eye_r = eye_l
		ActingState.FROZEN_DOUBLE_TAKE:
			rig_rot = deg_to_rad(16.0)
			p_scale = 1.35
			var bp: float = 1.0 - (_double_blink_timer / 0.62) if _double_blink_timer > 0.0 else 0.0
			eye_l = Vector2(1.1, 0.05 if ((bp > 0.15 and bp < 0.30) or (bp > 0.50 and bp < 0.65)) else 1.0)
			eye_r = eye_l
		ActingState.FLOOR_SLAM_TANTRUM:
			rig_scale = Vector2(1.0 + 0.08 * _last_beat_pulse, 1.0 - 0.08 * _last_beat_pulse)
			p_scale = 0.58
			rig_off = Vector2(sin(_elapsed_time * 40.0) * 2.2, 0.0)
		ActingState.ACCUSING_POINT:
			eye_l = Vector2(1.0, 0.35)
			eye_r = Vector2(1.0, 0.85)
			p_scale = 0.55
			if _lunge_active:
				rig_scale = Vector2(1.18, 0.84)
		ActingState.FAKE_OUT_COLLAPSE:
			rig_rot = deg_to_rad(-14.0)
			rig_scale = Vector2(0.95 + 0.28 * _inflate_amount, 0.90 + 0.22 * _inflate_amount)
			eye_l = Vector2(1.0, 0.08)
			eye_r = eye_l
			show_p = false
			dim = 0.42 if _silence_freeze else 0.52
		ActingState.HOLLOW_REBIRTH:
			hollow = true
			show_p = false
			eye_l = Vector2(1.22, 1.22)
			eye_r = eye_l
			rig_scale = Vector2.ONE * (1.0 + 0.06 * _last_beat_pulse)
		ActingState.EXHAUSTED_PANTING:
			var pant: float = 0.5 + 0.5 * sin(_elapsed_time * TAU / (BEAT_DURATION * 2.0))
			rig_scale = Vector2(lerpf(0.86, 1.22, pant) + 0.08 * _last_beat_pulse, lerpf(1.20, 0.78, pant) - 0.05 * _last_beat_pulse)
			eye_l = Vector2(1.0, 0.55)
			eye_r = eye_l
		ActingState.TEMPLE_CLUTCH_PANIC:
			rig_off = Vector2(sin(_elapsed_time * 52.0) * 2.6, cos(_elapsed_time * 44.0) * 1.8)
			eye_l = Vector2(1.15, 1.28)
			eye_r = eye_l
			p_scale = 0.48
			p_jit = Vector2(sin(_elapsed_time * TAU * 15.0) * 2.6, cos(_elapsed_time * TAU * 11.0) * 2.2)
		ActingState.SILENT_SHATTER:
			rig_scale = Vector2(0.72, 1.48)
			eye_l = Vector2(1.20, 1.35)
			eye_r = eye_l
			p_scale = 0.42

	if boss_form == BossForm.TRIPLE_CANNON:
		hollow = true
		show_p = false
	elif boss_form == BossForm.SPIKE_ROLL:
		rig_rot = _spike_roll_angle

	var laughing: bool = _laugh_timer > 0.0
	if laughing:
		rig_off.y += sin(_elapsed_time * TAU * 14.0) * 4.0
		eye_l = Vector2(1.1, 1.0)
		eye_r = eye_l
		show_p = false
	elif _flinch_timer > 0.0:
		rig_scale *= Vector2(0.84, 1.14)
		p_scale *= 0.55
	if laughing != _was_laughing:
		_set_eye_polygons(laughing)
		_was_laughing = laughing

	face_rig.position = rig_off
	face_rig.rotation = rig_rot
	face_rig.scale = rig_scale
	match boss_form:
		BossForm.SPIKE_ROLL: crown_polygon.rotation = _spike_roll_angle * 0.5
		BossForm.WHEEL_CORE: crown_polygon.rotation = _elapsed_time * 1.6
		BossForm.TRIPLE_CANNON: crown_polygon.rotation = _cannon_angle
		BossForm.OVERDRIVE_PANIC: crown_polygon.rotation = _elapsed_time * 0.9
		_: crown_polygon.rotation = _elapsed_time * 0.4 if current_phase >= 6 else 0.0

	var ga: float = 0.55 if _teleport_grace_timer > 0.0 else 1.0
	var fb: float = _white_flash * 0.45
	var bg: float = clampf(0.96 * dim + fb, 0.0, 1.0)
	var cg: float = clampf(0.86 * dim + fb, 0.0, 1.0)
	var eg: float = clampf((1.0 if hollow else 0.96) * dim + fb, 0.0, 1.0)
	body_polygon.color = Color(bg, bg, bg, ga)
	crown_polygon.color = Color(cg, cg, cg, ga)
	left_eye_polygon.color = Color(eg, eg, eg, ga)
	right_eye_polygon.color = Color(eg, eg, eg, ga)
	void_polygon.color = Color(0.06, 0.06, 0.06, ga)
	boss_glow.color = Color(1.0, 1.0, 1.0, clampf((0.32 + 0.14 * _last_beat_pulse + 0.30 * _white_flash + 0.25 * _mouth_beam_flash) * dim, 0.0, 0.90))
	left_eye_polygon.scale = eye_l
	right_eye_polygon.scale = eye_r

	var to_p: Vector2 = _player_pos - _body_pos
	var p_off: Vector2 = ((to_p.normalized() * minf(to_p.length() * 0.015, 2.6) if to_p.length_squared() > 1.0 else Vector2.ZERO) + p_jit).limit_length(2.8)
	var p_vis: bool = show_p and eye_l.y >= 0.25 and eye_r.y >= 0.25
	left_pupil_polygon.visible = p_vis
	right_pupil_polygon.visible = p_vis
	left_pupil_polygon.position = EYE_OFFSET_LEFT + p_off
	right_pupil_polygon.position = EYE_OFFSET_RIGHT + p_off
	left_pupil_polygon.scale = Vector2.ONE * p_scale
	right_pupil_polygon.scale = Vector2.ONE * p_scale
	_update_brows_and_mouth(laughing, dim)
	_update_hands_visuals(dim)


func _set_face_lines(lb: Array, rb: Array, m: Array) -> void:
	left_brow_line.points = PackedVector2Array(lb)
	right_brow_line.points = PackedVector2Array(rb)
	mouth_line.points = PackedVector2Array(m)


func _update_brows_and_mouth(laughing: bool, dim: float) -> void:
	var g: float = clampf(0.96 * dim + _white_flash * 0.2, 0.0, 1.0)
	var col: Color = Color(g, g, g, 1.0)
	left_brow_line.default_color = col
	right_brow_line.default_color = col
	mouth_line.default_color = col
	if laughing:
		_set_face_lines([Vector2(-16.5, -11.5), Vector2(-10.0, -14.5), Vector2(-3.5, -11.5)], [Vector2(3.5, -11.5), Vector2(10.0, -14.5), Vector2(16.5, -11.5)], [Vector2(-11.0, 7.2), Vector2(-5.0, 12.2), Vector2(0.0, 13.6), Vector2(5.0, 12.2), Vector2(11.0, 7.2)])
		return
	if _flinch_timer > 0.0:
		_set_face_lines([Vector2(-16.0, -11.5), Vector2(-4.2, -7.2)], [Vector2(4.2, -7.2), Vector2(16.0, -11.5)], [Vector2(-8.0, 10.8), Vector2(-3.6, 8.0), Vector2(0.0, 10.8), Vector2(3.6, 8.0), Vector2(8.0, 10.8)])
		return
	if _mouth_beam_flash > 0.0:
		_set_face_lines([Vector2(-16.5, -13.0), Vector2(-3.6, -7.2)], [Vector2(3.6, -7.2), Vector2(16.5, -13.0)], [Vector2(-10.8, 7.2), Vector2(-5.8, 15.8), Vector2(0.0, 10.0), Vector2(5.8, 15.8), Vector2(10.8, 7.2), Vector2(0.0, 5.0), Vector2(-10.8, 7.2)])
		return
	match acting_state:
		ActingState.COCKY_CONDUCTOR:
			_set_face_lines([Vector2(-16.0, -10.2), Vector2(-4.2, -9.4)], [Vector2(4.2, -11.6), Vector2(16.0, -13.8)], [Vector2(-8.8, 8.6), Vector2(-1.4, 10.2), Vector2(5.8, 8.6), Vector2(10.2, 5.2)])
		ActingState.FROZEN_DOUBLE_TAKE:
			_set_face_lines([Vector2(-16.0, -12.2), Vector2(-10.2, -15.2), Vector2(-4.2, -12.2)], [Vector2(4.2, -12.2), Vector2(10.2, -15.2), Vector2(16.0, -12.2)], [Vector2(-5.8, 9.4), Vector2(-2.2, 12.2), Vector2(2.2, 12.2), Vector2(5.8, 9.4)])
		ActingState.FLOOR_SLAM_TANTRUM, ActingState.HOLLOW_REBIRTH:
			var j: float = sin(_elapsed_time * 48.0) * 1.6
			_set_face_lines([Vector2(-16.6, -13.0), Vector2(-3.6, -7.2)], [Vector2(3.6, -7.2), Vector2(16.6, -13.0)], [Vector2(-11.5, 8.6 + j), Vector2(-6.5, 12.2 - j), Vector2(-2.2, 7.2 + j), Vector2(2.2, 12.2 - j), Vector2(6.5, 7.2 + j), Vector2(11.5, 8.6 - j)])
		ActingState.ACCUSING_POINT:
			var m_pts: Array = [Vector2(-11.5, 7.2), Vector2(-5.8, 14.5), Vector2(0.0, 8.6), Vector2(5.8, 14.5), Vector2(11.5, 7.2)] if (_lunge_active or bool(_lunge["tele"])) else [Vector2(-8.6, 10.2), Vector2(0.0, 8.6), Vector2(8.6, 10.8)]
			_set_face_lines([Vector2(-16.0, -10.8), Vector2(-4.2, -8.0)], [Vector2(4.2, -8.0), Vector2(16.0, -12.2)], m_pts)
		ActingState.FAKE_OUT_COLLAPSE:
			_set_face_lines([Vector2(-15.2, -8.6), Vector2(-5.0, -8.6)], [Vector2(5.0, -8.6), Vector2(15.2, -8.6)], [Vector2(-8.6, 10.2), Vector2(8.6, 10.2)])
		ActingState.EXHAUSTED_PANTING:
			var po: float = 2.6 * (0.5 + 0.5 * sin(_elapsed_time * TAU / (BEAT_DURATION * 2.0)))
			_set_face_lines([Vector2(-16.0, -8.6), Vector2(-4.2, -12.2)], [Vector2(4.2, -12.2), Vector2(16.0, -8.6)], [Vector2(-8.6, 8.6), Vector2(-3.6, 11.6 + po), Vector2(0.0, 9.4), Vector2(3.6, 11.6 + po), Vector2(8.6, 8.6)])
		ActingState.TEMPLE_CLUTCH_PANIC, ActingState.SILENT_SHATTER:
			var sc: float = sin(_elapsed_time * 55.0) * 1.5
			_set_face_lines([Vector2(-16.0, -10.2), Vector2(-4.2, -15.2)], [Vector2(4.2, -15.2), Vector2(16.0, -10.2)], [Vector2(-10.2, 10.8 + sc), Vector2(-5.0, 7.2 - sc), Vector2(0.0, 13.0 + sc), Vector2(5.0, 7.2 - sc), Vector2(10.2, 10.8 + sc)])


func _update_hands_visuals(dim: float) -> void:
	var hdim: float = 0.94 if (acting_state == ActingState.FAKE_OUT_COLLAPSE and _phase5_hands_awake) else dim
	var outers: Array[Polygon2D] = [left_hand_polygon, right_hand_polygon]
	var cores: Array[Polygon2D] = [left_hand_core, right_hand_core]
	for idx: int in range(2):
		var act: int = int(_hands[idx]["action"])
		var fl: float = 1.0 if (_is_hand_action_parryable(idx) or float(_hands[idx]["flash"]) > 0.0) else (0.72 if act in [HandAction.DASH_TELEGRAPH, HandAction.FLOOR_SLAM_TELEGRAPH, HandAction.WALL_SLAM_WINDUP, HandAction.POINTER_AIM, HandAction.PINCER_TELEGRAPH] else (0.65 if (acting_state == ActingState.FAKE_OUT_COLLAPSE and _phase5_hands_awake) else 0.0))
		var g: float = clampf(0.94 * hdim + fl * 0.25, 0.0, 1.0)
		outers[idx].color = Color(g, g, g, 1.0)
		cores[idx].color = outers[idx].color
	var rg: float = clampf(0.84 * hdim, 0.0, 1.0)
	left_hand_ring.default_color = Color(rg, rg, rg, 0.72)
	right_hand_ring.default_color = left_hand_ring.default_color


func _update_sweat_shards(dt: float) -> void:
	for i: int in range(_sweat_shards.size() - 1, -1, -1):
		var sh: Dictionary = _sweat_shards[i]
		sh["life"] = float(sh["life"]) - dt
		if float(sh["life"]) <= 0.0:
			_sweat_shards.remove_at(i)
			continue
		var vel: Vector2 = Vector2(sh["vel"]) + Vector2(0.0, 240.0) * dt
		sh["vel"] = vel
		sh["pos"] = Vector2(sh["pos"]) + vel * dt
	if acting_state == ActingState.EXHAUSTED_PANTING or boss_form == BossForm.STOMP_COLOSSUS:
		_sweat_spawn_timer -= dt
		if _sweat_spawn_timer <= 0.0:
			_sweat_spawn_timer = 0.22
			for side: float in [-1.0, 1.0]:
				_sweat_shards.append({"pos": Vector2(side * 24.0, -13.0), "vel": Vector2(side * 52.0, -64.0), "life": 0.52, "max_life": 0.52})


func _draw() -> void:
	if _shattered:
		_scratch_line_pts.resize(16)
		for k: int in range(8):
			var d: Vector2 = Vector2.from_angle(TAU * float(k) / 8.0 + 0.18)
			_scratch_line_pts[k * 2] = d * 10.0
			_scratch_line_pts[k * 2 + 1] = d * 58.0
		draw_multiline(_scratch_line_pts, Color(0.88, 0.88, 0.88, 0.78), 1.8, true)
		for sh: Dictionary in _shatter_shards:
			var off: Vector2 = Vector2(sh["offset"])
			var rot: float = float(sh["rot"])
			var sz: float = float(sh["size"])
			var g: float = float(sh["gray"])
			var cs: float = cos(rot)
			var sn: float = sin(rot)
			_scratch_tri[0] = off + Vector2(sz * cs, sz * sn)
			var vx: float = -sz * 0.6
			var vy: float = sz * 0.7
			_scratch_tri[1] = off + Vector2(vx * cs + vy * sn, vx * sn - vy * cs)
			_scratch_tri[2] = off + Vector2(vx * cs - vy * sn, vx * sn + vy * cs)
			draw_colored_polygon(_scratch_tri, Color(g, g, g, 0.92))
		draw_arc(Vector2.ZERO, 52.0, 0.0, TAU, 32, Color(0.95, 0.95, 0.95, 0.75), 2.0, true)
		return
	if _intro_active:
		if not _intro_quick_mode and _intro_progress < 0.56:
			_draw_intro_acquisition()
		if left_hand.visible:
			_draw_jsab_hand_details(0)
		if right_hand.visible:
			_draw_jsab_hand_details(1)
		return
	_draw_world_fx()
	_draw_telegraphs()
	_draw_form_overlays()
	if acting_state == ActingState.FAKE_OUT_COLLAPSE and _phase5_hands_awake and not _silence_freeze:
		_draw_puppet_strings()
	if left_hand.visible:
		_draw_jsab_hand_details(0)
	if right_hand.visible:
		_draw_jsab_hand_details(1)
	if _mouth_beam_flash > 0.0:
		draw_circle(Vector2(0.0, 10.0), 8.5 + 7.5 * _mouth_beam_flash, Color(1.0, 1.0, 1.0, 0.72))
	_draw_body_cracks()
	for sh: Dictionary in _sweat_shards:
		var a: float = clampf(float(sh["life"]) / maxf(float(sh["max_life"]), 0.001), 0.0, 1.0)
		var p: Vector2 = Vector2(sh["pos"])
		_scratch_quad[0] = p + Vector2(0.0, -4.5)
		_scratch_quad[1] = p + Vector2(3.0, 0.0)
		_scratch_quad[2] = p + Vector2(0.0, 4.5)
		_scratch_quad[3] = p + Vector2(-3.0, 0.0)
		draw_colored_polygon(_scratch_quad, Color(0.88, 0.88, 0.88, 0.85 * a))


func _draw_intro_acquisition() -> void:
	var lt: Vector2 = to_local(_intro_target_pos)
	var p: float = clampf(_intro_progress, 0.0, 1.0)
	var beam_w: float = 2.0
	var beam_alpha: float = 0.0
	if p < 0.42:
		beam_w = 2.0
		beam_alpha = lerpf(0.25, 0.72, p / 0.42)
	elif p < 0.50:
		beam_w = lerpf(2.0, 28.0, (p - 0.42) / 0.08)
		beam_alpha = 0.88
	else:
		var collapse_t: float = clampf((p - 0.50) / 0.02, 0.0, 1.0)
		var fade_t: float = clampf((p - 0.50) / 0.06, 0.0, 1.0)
		beam_w = lerpf(28.0, 0.0, collapse_t)
		beam_alpha = lerpf(0.88, 0.0, fade_t)
	if beam_w > 0.1 and beam_alpha > 0.01:
		draw_line(Vector2(lt.x, lt.y - _arena_size.y), lt, Color(0.92, 0.92, 0.92, beam_alpha), beam_w, true)

	var lock_t: float = clampf(p / 0.50, 0.0, 1.0)
	var ring_fade: float = 1.0 - clampf((p - 0.50) / 0.06, 0.0, 1.0)
	if ring_fade <= 0.01:
		return
	var eased_lock: float = ease(lock_t, 0.6)
	for k: int in range(3):
		var start_r: float = BODY_RADIUS * (2.4 + float(k) * 1.0)
		var end_r: float = BODY_RADIUS + float(k) * 4.0
		var r_k: float = lerpf(start_r, end_r, eased_lock)
		var alpha: float = (0.35 + 0.50 * lock_t) * ring_fade * (1.0 - float(k) * 0.18)
		draw_arc(lt, r_k, 0.0, TAU, 32, Color(0.85, 0.85, 0.85, alpha), 1.6, true)

	var tick_inner: float = lerpf(BODY_RADIUS * 1.8, BODY_RADIUS + 8.0, eased_lock)
	var tick_outer: float = tick_inner + 14.0
	_scratch_line_pts.resize(8)
	_scratch_line_pts[0] = lt + Vector2(-tick_outer, 0.0)
	_scratch_line_pts[1] = lt + Vector2(-tick_inner, 0.0)
	_scratch_line_pts[2] = lt + Vector2(tick_inner, 0.0)
	_scratch_line_pts[3] = lt + Vector2(tick_outer, 0.0)
	_scratch_line_pts[4] = lt + Vector2(0.0, -tick_outer)
	_scratch_line_pts[5] = lt + Vector2(0.0, -tick_inner)
	_scratch_line_pts[6] = lt + Vector2(0.0, tick_inner)
	_scratch_line_pts[7] = lt + Vector2(0.0, tick_outer)
	draw_multiline(_scratch_line_pts, Color(0.90, 0.90, 0.90, (0.45 + 0.45 * lock_t) * ring_fade), 1.6, true)


func _draw_world_fx() -> void:
	for tfx: Dictionary in _fx["teleport"]:
		var lr: float = clampf(float(tfx["life"]) / maxf(float(tfx["max_life"]), 0.001), 0.0, 1.0)
		var pl: Vector2 = Vector2(tfx["pos"]) - global_position
		var rad: float = lerpf(46.0, 14.0, lr) if String(tfx["kind"]) == "depart" else lerpf(BODY_RADIUS, 54.0, lr)
		draw_arc(pl, rad, 0.0, TAU, 24, Color(0.96, 0.96, 0.96, 0.78 * lr), 2.2, true)
		draw_arc(pl, rad * 0.65, 0.0, TAU, 16, Color(0.82, 0.82, 0.82, 0.45 * lr), 1.4, true)
	for wc: Dictionary in _fx["cracks"]:
		var lr: float = clampf(float(wc["life"]) / maxf(float(wc["max_life"]), 0.001), 0.0, 1.0)
		var wp: Vector2 = Vector2(wc["pos"]) - global_position
		var n: Vector2 = Vector2(wc["normal"]).normalized()
		var tang: Vector2 = Vector2(-n.y, n.x)
		var sv: float = clampf(float(wc.get("strength", 0.6)), 0.3, 1.0)
		draw_arc(wp, (12.0 + 34.0 * (1.0 - lr)) * sv, n.angle() - PI * 0.52, n.angle() + PI * 0.52, 16, Color(0.96, 0.96, 0.96, 0.78 * lr), 2.2 * lr, true)
		draw_line(wp - tang * (26.0 + 22.0 * sv), wp + tang * (26.0 + 22.0 * sv), Color(0.95, 0.95, 0.95, 0.86 * lr), 2.6 * lr, true)
		_scratch_line_pts.resize(24)
		var c_idx: int = 0
		for b_ang: float in [-0.85, -0.32, 0.32, 0.85]:
			var bd: Vector2 = n.rotated(b_ang)
			var bp: Vector2 = Vector2(-bd.y, bd.x)
			var prev_pt: Vector2 = wp
			for st: int in range(1, 4):
				var next_pt: Vector2 = wp + bd * (16.0 * float(st) * sv) + bp * ((6.0 if st % 2 == 0 else -6.0) * sv)
				_scratch_line_pts[c_idx] = prev_pt
				_scratch_line_pts[c_idx + 1] = next_pt
				c_idx += 2
				prev_pt = next_pt
		draw_multiline(_scratch_line_pts, Color(0.94, 0.94, 0.94, 0.82 * lr), 1.8 * lr, true)
	for gr: Dictionary in _fx["rake"]:
		var lr: float = clampf(float(gr["life"]) / maxf(float(gr["max_life"]), 0.001), 0.0, 1.0)
		draw_line(Vector2(gr["from"]) - global_position, Vector2(gr["to"]) - global_position, Color(0.92, 0.92, 0.92, 0.55 * lr), 5.0 * lr, true)
	for sa: Dictionary in _fx["slash"]:
		var lr: float = clampf(float(sa["life"]) / maxf(float(sa["max_life"]), 0.001), 0.0, 1.0)
		draw_arc(Vector2(sa["pos"]) - global_position, float(sa["radius"]), float(sa["rot"]) - 0.85, float(sa["rot"]) + 0.85, 12, Color(0.98, 0.98, 0.98, 0.62 * lr), 2.5 * lr, true)
	for ghost: Dictionary in _fx["afterimages"]:
		var lr: float = clampf(float(ghost["life"]) / maxf(float(ghost["max_life"]), 0.001), 0.0, 1.0)
		var lg: Vector2 = Vector2(ghost["pos"]) - global_position
		var rad: float = float(ghost["radius"]) * (0.72 + 0.28 * lr)
		var rot: float = float(ghost["rot"])
		var col: Color = Color(0.90, 0.90, 0.90, 0.24 * lr)
		if String(ghost.get("shape", "")) == "diamond":
			var cs: float = cos(rot)
			var sn: float = sin(rot)
			_scratch_quad[0] = lg + Vector2(rad * 1.15 * cs, rad * 1.15 * sn)
			_scratch_quad[1] = lg + Vector2(rad * 0.8 * sn, -rad * 0.8 * cs)
			_scratch_quad[2] = lg + Vector2(-rad * cs, -rad * sn)
			_scratch_quad[3] = lg + Vector2(-rad * 0.8 * sn, rad * 0.8 * cs)
			draw_colored_polygon(_scratch_quad, col)
		else:
			draw_circle(lg, rad, col)


func _draw_telegraphs() -> void:
	if bool(_lunge["tele"]):
		var pl: float = clampf(float(_lunge["timer"]) / maxf(float(_lunge["tele_dur"]), 0.001), 0.0, 1.0)
		_draw_corridor_rail(_body_pos, Vector2(_lunge["target"]), BODY_RADIUS * 0.95, BODY_RADIUS * 0.88, pl)
	if int(_hands[0]["action"]) == HandAction.ORBIT:
		var po: float = clampf(float(_hands[0]["timer"]) / maxf(float(_hands[0]["duration"]), 0.001), 0.0, 1.0)
		draw_arc(Vector2.ZERO, lerpf(88.0, 158.0, sin(po * PI * 0.5)) * minf(_scale_vec().x, _scale_vec().y), 0.0, TAU, 32, Color(0.92, 0.92, 0.92, 0.48), 1.8, true)
	if int(_hands[0]["action"]) == HandAction.TETHER_SWEEP and int(_hands[1]["action"]) == HandAction.TETHER_SWEEP:
		_draw_high_voltage_tether(Vector2(_hands[0]["pos"]) - global_position, Vector2(_hands[1]["pos"]) - global_position, _tether_active)
	if int(_hands[0]["action"]) == HandAction.PINCER_TELEGRAPH:
		var pp: float = clampf(float(_hands[0]["timer"]) / maxf(float(_hands[0]["duration"]), 0.001), 0.0, 1.0)
		_draw_corridor_rail(Vector2(_hands[0]["stage_pos"]), Vector2(_hands[0]["target_pos"]), 18.0, 18.0, pp)
		_draw_corridor_rail(Vector2(_hands[1]["stage_pos"]), Vector2(_hands[1]["target_pos"]), 18.0, 18.0, pp)
		var pmid: Vector2 = _pincer_mid - global_position
		draw_arc(pmid, lerpf(42.0, 22.0, pp), 0.0, TAU, 24, Color(0.98, 0.98, 0.98, lerpf(0.52, 0.96, pp)), 2.2, true)
	for idx: int in range(2):
		var h: Dictionary = _hands[idx]
		var ph: float = clampf(float(h["timer"]) / maxf(float(h["duration"]), 0.001), 0.0, 1.0)
		match int(h["action"]):
			HandAction.DASH_TELEGRAPH:
				_draw_corridor_rail(Vector2(h["stage_pos"]), Vector2(h["target_pos"]), 26.0 if int(h["style"]) == HandDashStyle.CLAW_SWIPE else 19.0, 20.0, ph)
			HandAction.FLOOR_SLAM_TELEGRAPH:
				var sp: Vector2 = Vector2(h["target_pos"]) - global_position
				_draw_corridor_rail(Vector2(h["stage_pos"]), Vector2(h["target_pos"]), 18.0, 26.0, ph)
				draw_arc(sp, lerpf(48.0, 26.0, ph), 0.0, TAU, 24, Color(0.95, 0.95, 0.95, lerpf(0.50, 0.96, ph)), 2.0, true)
				draw_line(sp - Vector2(16.0, 0.0), sp + Vector2(16.0, 0.0), Color(0.94, 0.94, 0.94, lerpf(0.50, 0.92, ph)), 1.6, true)
			HandAction.WALL_SLAM_WINDUP:
				var wpl: Vector2 = Vector2(h["wall_pos"]) - global_position
				var n: Vector2 = Vector2(h["normal"]).normalized()
				var tang: Vector2 = Vector2(-n.y, n.x)
				_draw_corridor_rail(Vector2(h["stage_pos"]), Vector2(h["target_pos"]), 19.0, 18.0, ph)
				draw_arc(wpl, lerpf(32.0, 15.0, ph), n.angle() - PI * 0.5, n.angle() + PI * 0.5, 16, Color(0.96, 0.96, 0.96, lerpf(0.54, 0.96, ph)), 2.2, true)
				draw_line(wpl - tang * 24.0, wpl + tang * 24.0, Color(0.98, 0.98, 0.98, lerpf(0.62, 0.98, ph)), 2.2, true)


func _draw_form_overlays() -> void:
	match boss_form:
		BossForm.SPIKE_ROLL:
			for r_i: int in range(2):
				var br: float = BODY_RADIUS + 8.0 + float(r_i) * 7.0
				var sa: float = _spike_roll_angle * (1.2 if r_i == 0 else -0.9)
				var col: Color = Color(0.94, 0.94, 0.94, 0.58 - float(r_i) * 0.22)
				for seg: int in range(3):
					var a0: float = sa + TAU * float(seg) / 3.0
					draw_arc(Vector2.ZERO, br, a0, a0 + 1.15, 10, col, 2.0, true)
		BossForm.WHEEL_CORE:
			var rh: float = _elapsed_time * 1.1
			_scratch_line_pts.resize(16)
			for seg: int in range(8):
				var a0: float = rh + TAU * float(seg) / 8.0
				draw_arc(Vector2.ZERO, 54.0, a0, a0 + 0.42, 6, Color(0.92, 0.92, 0.92, 0.56), 1.8, true)
				var td: Vector2 = Vector2.from_angle(-rh * 1.3 + TAU * float(seg) / 8.0)
				_scratch_line_pts[seg * 2] = td * 42.0
				_scratch_line_pts[seg * 2 + 1] = td * 48.0
			draw_multiline(_scratch_line_pts, Color(0.84, 0.84, 0.84, 0.65), 1.6, true)
		BossForm.MARIONETTE:
			var n_rim: int = _marionette_rim.size()
			var cs: float = cos(face_rig.rotation)
			var sn: float = sin(face_rig.rotation)
			var f_sc: Vector2 = face_rig.scale
			var f_pos: Vector2 = face_rig.position
			for i: int in range(n_rim):
				var v: Vector2 = _marionette_rim[i] * f_sc
				_scratch_marionette_tf[i] = Vector2(v.x * cs - v.y * sn, v.x * sn + v.y * cs) + f_pos
			_scratch_marionette_tf[n_rim] = _scratch_marionette_tf[0]
			draw_polyline(_scratch_marionette_tf, Color(0.54, 0.54, 0.54, 0.88), 1.6, true)
			if _inflate_amount > 0.02:
				draw_arc(Vector2.ZERO, BODY_RADIUS * (1.1 + 0.45 * _inflate_amount), 0.0, TAU, 24, Color(1.0, 1.0, 1.0, 0.55 * clampf(_inflate_amount, 0.0, 1.0)), 2.2, true)
		BossForm.TRIPLE_CANNON:
			var flare: float = clampf(_last_beat_pulse * 0.6 + _mouth_beam_flash, 0.0, 1.0)
			for i: int in range(3):
				var ang: float = _cannon_angle + TAU * float(i) / 3.0
				_draw_transformed_poly(_cannon_barrel_poly, Vector2.ZERO, ang, Color(0.96, 0.96, 0.96, 1.0))
				_draw_transformed_poly(_cannon_slit_poly, Vector2.ZERO, ang, Color(0.08, 0.08, 0.08, 1.0))
				if flare > 0.05:
					draw_circle(Vector2.from_angle(ang) * CANNON_MUZZLE_RADIUS, 4.5 + 4.0 * flare, Color(1.0, 1.0, 1.0, 0.88 * flare))
		BossForm.OVERDRIVE_PANIC:
			_scratch_line_pts.resize(16)
			for k: int in range(8):
				var d: Vector2 = Vector2.from_angle(TAU * float(k) / 8.0 + sin(_elapsed_time * 24.0 + float(k)) * 0.08)
				_scratch_line_pts[k * 2] = d * 44.0
				_scratch_line_pts[k * 2 + 1] = d * (52.0 + 4.0 * _last_beat_pulse)
			draw_multiline(_scratch_line_pts, Color(0.95, 0.95, 0.95, 0.62), 1.6, true)


func _draw_body_cracks() -> void:
	var inflating: bool = (boss_form == BossForm.MARIONETTE or acting_state == ActingState.FAKE_OUT_COLLAPSE) and _inflate_amount > 0.02
	var intensity: float = maxf(_crack_intensity, _inflate_amount if inflating else 0.0)
	if intensity <= 0.01:
		return
	var bright: bool = acting_state == ActingState.SILENT_SHATTER or inflating
	var cg: float = 0.98 if bright else 0.14
	var col: Color = Color(cg, cg, cg, clampf(intensity, 0.0, 1.0))
	var sc: Vector2 = face_rig.scale
	var cs: float = cos(face_rig.rotation)
	var sn: float = sin(face_rig.rotation)
	var f_pos: Vector2 = face_rig.position
	var n_pts: int = BODY_CRACK_SEGMENTS.size()
	_scratch_line_pts.resize(n_pts)
	for i: int in range(n_pts):
		var v: Vector2 = BODY_CRACK_SEGMENTS[i] * sc
		_scratch_line_pts[i] = Vector2(v.x * cs - v.y * sn, v.x * sn + v.y * cs) + f_pos
	draw_multiline(_scratch_line_pts, col, 2.2 if bright else 1.8, true)
	if boss_form == BossForm.OVERDRIVE_PANIC:
		draw_multiline(_scratch_line_pts, Color(0.96, 0.96, 0.96, 0.45 * intensity), 1.0, true)


func _draw_high_voltage_tether(lp: Vector2, rp: Vector2, active: bool) -> void:
	var dist: float = lp.distance_to(rp)
	var dir: Vector2 = (rp - lp) / dist if dist > 0.001 else Vector2.RIGHT
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	if not active:
		var pt: float = clampf(float(_hands[0]["timer"]) / maxf(float(_hands[0]["duration"]), 0.001), 0.0, 1.0)
		var dt: float = 0.0
		var col: Color = Color(0.90, 0.90, 0.90, lerpf(0.50, 0.94, pt))
		var gap_off: float = lerpf(10.0, 1.5, pt)
		var est_segs: int = int(ceil(dist / 22.0)) + 1
		_scratch_line_pts.resize(est_segs * 4)
		var w_idx: int = 0
		while dt < dist:
			var s1: float = minf(dt + 14.0, dist)
			var a_pt: Vector2 = lp + dir * dt
			var b_pt: Vector2 = lp + dir * s1
			_scratch_line_pts[w_idx] = a_pt + perp * gap_off
			_scratch_line_pts[w_idx + 1] = b_pt + perp * gap_off
			_scratch_line_pts[w_idx + 2] = a_pt - perp * gap_off
			_scratch_line_pts[w_idx + 3] = b_pt - perp * gap_off
			w_idx += 4
			dt += 22.0
		if w_idx >= 2:
			_scratch_line_pts.resize(w_idx)
			draw_multiline(_scratch_line_pts, col, 1.8, true)
		return
	draw_line(lp, rp, Color(0.88, 0.88, 0.88, 0.24), 9.0, true)
	draw_line(lp, rp, Color(0.98, 0.98, 0.98, 0.98), 3.2, true)
	for strand: int in range(2):
		for k: int in range(11):
			var frac: float = float(k) / 10.0
			_scratch_tether_pts[k] = lp.lerp(rp, frac) + perp * (sin(_elapsed_time * (28.0 + float(strand) * 12.0) + float(k) * 2.4 + float(strand) * 1.9) * (4.8 if strand == 0 else 8.0) * sin(frac * PI))
		var sg: float = 0.92 if strand == 0 else 0.80
		draw_polyline(_scratch_tether_pts, Color(sg, sg, sg, 0.78 if strand == 0 else 0.48), 1.6, true)


func _draw_puppet_strings() -> void:
	_scratch_line_pts.resize(4)
	_scratch_line_pts_b.resize(12)
	_scratch_line_cols.resize(6)
	var b_idx: int = 0
	var c_idx: int = 0
	var offs: Array[Vector2] = [Vector2(-13.0, -10.0), Vector2(0.0, -15.0), Vector2(13.0, -10.0)]
	for idx: int in range(2):
		var hw: Vector2 = Vector2(_hands[idx]["pos"])
		var hr: float = float(_hands[idx]["rot"])
		var hl: Vector2 = hw - global_position
		var top: Vector2 = Vector2(hw.x, 26.0) - global_position
		_scratch_line_pts[idx * 2] = Vector2(top.x - 15.0, 32.0 - global_position.y)
		_scratch_line_pts[idx * 2 + 1] = Vector2(top.x + 15.0, 32.0 - global_position.y)
		var cs: float = cos(hr)
		var sn: float = sin(hr)
		for k: int in range(3):
			var o: Vector2 = offs[k]
			var h_pt: Vector2 = hl + Vector2(o.x * cs - o.y * sn, o.x * sn + o.y * cs)
			var g: float = 0.44 if k == 1 else 0.38
			_scratch_line_pts_b[b_idx] = top + Vector2(float(k - 1) * 11.0, 0.0)
			_scratch_line_pts_b[b_idx + 1] = h_pt
			_scratch_line_cols[c_idx] = Color(g, g, g, 0.30 if k == 1 else 0.22)
			b_idx += 2
			c_idx += 1
	draw_multiline(_scratch_line_pts, Color(0.46, 0.46, 0.46, 0.30), 1.4, true)
	draw_multiline_colors(_scratch_line_pts_b, _scratch_line_cols, 1.1, true)
	var knot_col: Color = Color(0.55, 0.55, 0.55, 0.42)
	for k: int in range(6):
		draw_circle(_scratch_line_pts_b[k * 2 + 1], 2.0, knot_col)


func _draw_corridor_rail(from_pos: Vector2, to_pos: Vector2, half_width: float, end_radius: float, progress: float = 0.5) -> void:
	var a: Vector2 = from_pos - global_position
	var b: Vector2 = to_pos - global_position
	var dist: float = a.distance_to(b)
	var dir: Vector2 = (b - a) / dist if dist > 1.0 else Vector2.RIGHT
	var side: Vector2 = Vector2(-dir.y, dir.x)
	var perp: Vector2 = side * half_width
	var p: float = clampf(progress, 0.0, 1.0)
	var fill_col: Color = Color(0.36, 0.36, 0.36, lerpf(0.14, 0.30, p))
	if dist > 2.0:
		_scratch_quad[0] = a - perp
		_scratch_quad[1] = b - perp
		_scratch_quad[2] = b + perp
		_scratch_quad[3] = a + perp
		draw_colored_polygon(_scratch_quad, fill_col)
		var fill_dist: float = dist * p
		if fill_dist > 2.0:
			var bf: Vector2 = a + dir * fill_dist
			var inner_perp: Vector2 = side * (half_width * 0.45)
			_scratch_quad[0] = a - inner_perp
			_scratch_quad[1] = bf - inner_perp
			_scratch_quad[2] = bf + inner_perp
			_scratch_quad[3] = a + inner_perp
			draw_colored_polygon(_scratch_quad, Color(0.78, 0.78, 0.78, lerpf(0.16, 0.36, p)))
	var col: Color = Color(0.94, 0.94, 0.94, lerpf(0.50, 0.95, p))
	var est_dashes: int = int(ceil(dist / 32.0)) + 1
	_scratch_line_pts.resize(est_dashes * 4)
	var l_idx: int = 0
	var t: float = 0.0
	while t < dist:
		var s1: float = minf(t + 22.0, dist)
		var p_start: Vector2 = a + dir * t
		var p_end: Vector2 = a + dir * s1
		_scratch_line_pts[l_idx] = p_start + perp
		_scratch_line_pts[l_idx + 1] = p_end + perp
		_scratch_line_pts[l_idx + 2] = p_start - perp
		_scratch_line_pts[l_idx + 3] = p_end - perp
		l_idx += 4
		t += 32.0
	if l_idx >= 2:
		_scratch_line_pts.resize(l_idx)
		draw_multiline(_scratch_line_pts, col, 2.0, true)
	_scratch_line_pts_b.resize(0)
	var chev_step: float = 130.0
	var cd: float = 55.0
	var chev_sz: float = minf(half_width * 0.55, 9.0)
	while cd < dist - 30.0:
		_scratch_line_pts_b = BossConstants.append_double_chevron_pts(_scratch_line_pts_b, a + dir * cd, dir, chev_sz)
		cd += chev_step
	if _scratch_line_pts_b.size() >= 2:
		draw_multiline(_scratch_line_pts_b, col, 1.7, true)
	draw_arc(b, end_radius, 0.0, TAU, 22, col, 2.0, true)
	draw_arc(b, end_radius * lerpf(1.65, 1.0, p), 0.0, TAU, 22, Color(0.98, 0.98, 0.98, lerpf(0.45, 0.92, p)), 1.6, true)


func _draw_jsab_hand_details(idx: int) -> void:
	var h: Dictionary = _hands[idx]
	var blend: float = float(h["retract_blend"])
	if blend >= 0.85:
		return
	var sc: float = 1.0 - blend
	var hp: Vector2 = Vector2(h["pos"]) - global_position
	var hr: float = float(h["rot"])
	var side: float = 1.0 if idx == 0 else -1.0
	var act: int = int(h["action"])
	var flash: float = float(h["flash"])
	var cb: Color = Color(0.96, 0.96, 0.96, sc)
	var cm: Color = Color(0.86, 0.86, 0.86, 0.96 * sc)
	match int(h["pose"]):
		HandPose.OPEN:
			for i: int in range(4):
				_draw_transformed_poly(_make_finger_poly(Vector2(OPEN_FINGER_XS[i] * side, -15.8 + sin(_elapsed_time * 6.5 + float(i) * 0.65) * 0.9) * sc, Vector2(0.0, -1.0).rotated(side * (-0.28 + float(i) * 0.16)), OPEN_FINGER_LS[i] * sc, 3.0 * sc, 1.5 * sc), hp, hr, cb if i % 2 == 0 else cm)
			_draw_transformed_poly(_make_finger_poly(Vector2(15.0 * side, 1.5) * sc, Vector2(0.85 * side, -0.55).normalized(), 12.2 * sc, 3.3 * sc, 1.6 * sc), hp, hr, cb)
		HandPose.FIST:
			for i: int in range(4):
				var ky: float = (-9.6 + float(i) * 6.4) * sc
				_scratch_quad[0] = Vector2(14.4 * sc, ky - 2.6 * sc)
				_scratch_quad[1] = Vector2(20.2 * sc, ky - 1.8 * sc)
				_scratch_quad[2] = Vector2(20.2 * sc, ky + 1.8 * sc)
				_scratch_quad[3] = Vector2(14.4 * sc, ky + 2.6 * sc)
				_draw_transformed_poly(_scratch_quad, hp, hr, cb)
			_draw_transformed_poly(_make_finger_poly(Vector2(1.5, 12.2 * side) * sc, Vector2(1.0, -0.25 * side).normalized(), 13.0 * sc, 3.6 * sc, 2.3 * sc), hp, hr, cm)
			if act in [HandAction.DASH_ACTIVE, HandAction.DASH_TELEGRAPH, HandAction.WALL_SLAM_STRIKE, HandAction.WALL_SLAM_WINDUP, HandAction.PINCER_CLAP]:
				var hot: bool = act in [HandAction.DASH_ACTIVE, HandAction.WALL_SLAM_STRIKE, HandAction.PINCER_CLAP]
				var cs: float = cos(hr)
				var sn: float = sin(hr)
				_scratch_line_pts.resize(8)
				for ci: int in range(2):
					var cx: float = (-21.5 - float(ci) * 8.0) * sc
					var v_top: Vector2 = Vector2(cx - 5.8 * sc, -10.0 * sc)
					var v_mid: Vector2 = Vector2(cx + 3.0 * sc, 0.0)
					var v_bot: Vector2 = Vector2(cx - 5.8 * sc, 10.0 * sc)
					var p_top: Vector2 = hp + Vector2(v_top.x * cs - v_top.y * sn, v_top.x * sn + v_top.y * cs)
					var p_mid: Vector2 = hp + Vector2(v_mid.x * cs - v_mid.y * sn, v_mid.x * sn + v_mid.y * cs)
					var p_bot: Vector2 = hp + Vector2(v_bot.x * cs - v_bot.y * sn, v_bot.x * sn + v_bot.y * cs)
					_scratch_line_pts[ci * 4] = p_top
					_scratch_line_pts[ci * 4 + 1] = p_mid
					_scratch_line_pts[ci * 4 + 2] = p_mid
					_scratch_line_pts[ci * 4 + 3] = p_bot
				draw_multiline(_scratch_line_pts, Color(0.98, 0.98, 0.98, (0.88 if hot else 0.52) * sc), 2.0, true)
		HandPose.POINTER:
			_draw_transformed_poly(_make_finger_poly(Vector2(13.0, -3.0 * side) * sc, Vector2.RIGHT, 20.2 * sc, 3.8 * sc, 1.8 * sc), hp, hr, cb)
			_draw_transformed_poly(_make_finger_poly(Vector2(1.5, -10.8 * side) * sc, Vector2(0.5, -0.86 * side).normalized(), 10.8 * sc, 3.2 * sc, 1.6 * sc), hp, hr, cm)
			for i: int in range(3):
				var ky: float = (3.0 + float(i) * 4.6) * side * sc
				_scratch_quad[0] = Vector2(9.4 * sc, ky - 1.8 * sc)
				_scratch_quad[1] = Vector2(14.4 * sc, ky - 1.4 * sc)
				_scratch_quad[2] = Vector2(14.4 * sc, ky + 1.4 * sc)
				_scratch_quad[3] = Vector2(9.4 * sc, ky + 1.8 * sc)
				_draw_transformed_poly(_scratch_quad, hp, hr, cm)
			var tip: Vector2 = hp + Vector2(34.5 * sc, -3.0 * side * sc).rotated(hr)
			if act == HandAction.POINTER_AIM or flash > 0.0:
				draw_circle(tip, (5.5 + 3.0 * flash) * sc, Color(1.0, 1.0, 1.0, 0.92 * sc))
				draw_arc(tip, 9.5 * sc, 0.0, TAU, 16, Color(0.94, 0.94, 0.94, 0.72 * sc), 1.5, true)
				if act == HandAction.POINTER_AIM:
					draw_line(tip, tip + Vector2.from_angle(hr) * 1400.0, Color(0.92, 0.92, 0.92, 0.20), 1.1, true)
		HandPose.CLAW:
			for i: int in range(5):
				var a: float = -1.15 + float(i) * 0.575
				_draw_transformed_poly(_make_finger_poly(Vector2.from_angle(a) * (14.4 * sc), Vector2.from_angle(a + 0.14 * side), 14.4 * sc, 3.4 * sc, 0.8 * sc), hp, hr, cb if i % 2 == 0 else cm)


func _make_finger_poly(base: Vector2, dir: Vector2, length: float, half_base_w: float, half_tip_w: float) -> PackedVector2Array:
	var n: Vector2 = dir.normalized()
	var perp: Vector2 = Vector2(-n.y, n.x)
	var tip: Vector2 = base + n * length
	_scratch_finger[0] = base + perp * half_base_w
	_scratch_finger[1] = tip + perp * half_tip_w
	_scratch_finger[2] = tip + n * 2.8
	_scratch_finger[3] = tip - perp * half_tip_w
	_scratch_finger[4] = base - perp * half_base_w
	return _scratch_finger


func _draw_transformed_poly(local_pts: PackedVector2Array, origin: Vector2, rot: float, color: Color) -> void:
	var n_pts: int = local_pts.size()
	if _scratch_poly.size() != n_pts:
		_scratch_poly.resize(n_pts)
	var cs: float = cos(rot)
	var sn: float = sin(rot)
	for i: int in range(n_pts):
		var v: Vector2 = local_pts[i]
		_scratch_poly[i] = origin + Vector2(v.x * cs - v.y * sn, v.x * sn + v.y * cs)
	draw_colored_polygon(_scratch_poly, color)


# ------------------------------------------------------------------------------
# SCALED POLYGON BUILDERS & BOUNDS HELPERS
# ------------------------------------------------------------------------------
func _build_base_geometry() -> void:
	body_polygon.polygon = Shapes.circle(BODY_RADIUS, 8, PI / 8.0)
	void_polygon.polygon = Shapes.circle(23.0, 8, PI / 8.0)
	var pupil_poly: PackedVector2Array = Shapes.circle(3.2, 10)
	left_pupil_polygon.polygon = pupil_poly
	right_pupil_polygon.polygon = pupil_poly
	left_eye_polygon.position = EYE_OFFSET_LEFT
	right_eye_polygon.position = EYE_OFFSET_RIGHT
	_set_eye_polygons(false)


func _set_eye_polygons(laughing_crescent: bool) -> void:
	var poly: PackedVector2Array = PackedVector2Array([Vector2(-6.5, 2.2), Vector2(0.0, -5.0), Vector2(6.5, 2.2), Vector2(3.6, 3.6), Vector2(0.0, -1.4), Vector2(-3.6, 3.6)]) if laughing_crescent else Shapes.circle(6.2, 12)
	left_eye_polygon.polygon = poly
	right_eye_polygon.polygon = poly


func _set_crown_for_phase_and_form(phase: int, form: BossForm) -> void:
	var tier: int = 2 if (phase >= 6 or form in [BossForm.TRIPLE_CANNON, BossForm.STOMP_COLOSSUS, BossForm.OVERDRIVE_PANIC, BossForm.SHATTERED]) else (1 if (phase >= 3 or form in [BossForm.WHEEL_CORE, BossForm.SPIKE_ROLL]) else 0)
	if tier == _active_crown_tier:
		return
	_active_crown_tier = tier
	crown_polygon.polygon = Shapes.star(45.0, 28.0, 12) if tier == 2 else (Shapes.star(42.0, 26.0, 8) if tier == 1 else Shapes.star(38.0, 28.0, 6))


func _set_hand_pose(idx: int, pose: int) -> void:
	if int(_hands[idx]["pose"]) == pose:
		return
	_hands[idx]["pose"] = pose
	var is_left: bool = idx == 0
	var outer: Polygon2D = left_hand_polygon if is_left else right_hand_polygon
	var inner: Polygon2D = left_hand_void if is_left else right_hand_void
	var core: Polygon2D = left_hand_core if is_left else right_hand_core
	var ring: Line2D = left_hand_ring if is_left else right_hand_ring
	var side: float = 1.0 if is_left else -1.0
	match pose:
		HandPose.FIST:
			outer.polygon = PackedVector2Array([Vector2(-15.8, -13.0), Vector2(13.0, -15.2), Vector2(15.8, -7.2), Vector2(15.8, 7.2), Vector2(13.0, 15.2), Vector2(-15.8, 13.0), Vector2(-18.8, 0.0)])
			inner.polygon = Shapes.rect(Vector2(17.2, 17.2))
			core.polygon = Shapes.diamond(5.4)
			ring.points = Shapes.circle(21.6, 16)
		HandPose.POINTER:
			outer.polygon = PackedVector2Array([Vector2(14.4, -7.2 * side), Vector2(10.8, 11.5 * side), Vector2(-11.5, 13.6 * side), Vector2(-16.5, 0.0), Vector2(-10.0, -13.0 * side)])
			inner.polygon = Shapes.circle(8.6, 6)
			core.polygon = Shapes.diamond(4.4)
			ring.points = Shapes.circle(20.2, 16)
		HandPose.CLAW:
			outer.polygon = Shapes.circle(16.6, 6)
			inner.polygon = Shapes.circle(10.0, 6)
			core.polygon = Shapes.star(6.5, 3.2, 4)
			ring.points = Shapes.circle(22.2, 18)
		_:
			outer.polygon = PackedVector2Array([Vector2(-14.4 * side, -14.4), Vector2(14.4 * side, -14.4), Vector2(17.2 * side, 4.4), Vector2(8.6 * side, 15.8), Vector2(-11.5 * side, 15.8), Vector2(-17.2 * side, 3.0)])
			inner.polygon = Shapes.circle(9.4, 6)
			core.polygon = Shapes.diamond(4.8)
			ring.points = Shapes.circle(21.6, 18)


func _pose_for_dash_style(style: int) -> HandPose:
	return HandPose.CLAW if style == HandDashStyle.CLAW_SWIPE else HandPose.FIST

func _clamp_perimeter_bounds(pos: Vector2, s: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, 110.0 * s.x, _arena_size.x - 110.0 * s.x), clampf(pos.y, 105.0 * s.y, _arena_size.y - 105.0 * s.y))

func _clamp_hand_dash_bounds(pos: Vector2, s: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, 64.0 * s.x, _arena_size.x - 64.0 * s.x), clampf(pos.y, 84.0 * s.y, _arena_size.y - 68.0 * s.y))

func _clamp_combat_bounds(pos: Vector2, s: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, 145.0 * s.x, _arena_size.x - 145.0 * s.x), clampf(pos.y, 108.0 * s.y, _arena_size.y - 108.0 * s.y))

func _resolve_arena_size(requested: Vector2) -> Vector2:
	if requested.x > 0.0 and requested.y > 0.0:
		return requested
	var rect_size: Vector2 = get_viewport_rect().size
	return rect_size if (rect_size.x > 0.0 and rect_size.y > 0.0) else DEFAULT_ARENA_SIZE

func _scale_vec() -> Vector2:
	return Vector2(_arena_size.x / DEFAULT_ARENA_SIZE.x, _arena_size.y / DEFAULT_ARENA_SIZE.y)
