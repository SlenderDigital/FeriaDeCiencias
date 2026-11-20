class_name BossBeatMinion
extends Node2D

enum Phase {
	TELEGRAPH = 0,
	ACTIVE = 1,
	FADE_OUT = 2,
}

const FADE_DURATION: float = 0.24

var is_hazard_active: bool = false
var parryable: bool = false
var hazard_kind: StringName = &"beat_minion"

var minion_type: int = BossConstants.MinionType.THREAD_SPIDER
var current_phase: int = Phase.TELEGRAPH
var phase_timer: float = 0.0
var beats_lived: int = 0
var lifetime_beats: int = 8

var _arena_size: Vector2 = BossConstants.ARENA_REF
var _warning_time: float = 0.70
var _params: Dictionary = {}
var _body_radius: float = 16.0
var _beat_pulse: float = 0.0
var _elapsed: float = 0.0
var _max_active_fallback: float = 6.0

# THREAD_SPIDER state
var _anchor_pos: Vector2 = Vector2.ZERO
var _drop_target_pos: Vector2 = Vector2.ZERO
var _drop_progress: float = 0.0
var _drop_goal: float = 0.0
var _burst_beat: int = 4
var _burst_fired: bool = false

# ORBIT_SPECTER state
var _orbit_center: Vector2 = Vector2(576.0, 324.0)
var _orbit_radius: float = 180.0
var _orbit_angle: float = 0.0
var _orbit_target_angle: float = 0.0
var _orbit_step_rad: float = PI * 0.25
var _orbit_drift_speed: float = 0.65

# BORDER_SNAPPER state
var _snap_normal: Vector2 = Vector2.RIGHT
var _snap_leap_depth: float = 175.0
var _snap_extension: float = 0.0
var _snap_goal: float = 0.0
var _snap_apex_pending: bool = false
var _pending_bullet_manager: Node = null
var _pending_player_pos: Vector2 = Vector2.ZERO

var _queued_free: bool = false


func _init() -> void:
	add_to_group("boss_hazards")


func _ready() -> void:
	if not is_in_group("boss_hazards"):
		add_to_group("boss_hazards")
	queue_redraw()


func _physics_process(delta: float) -> void:
	simulate_physics(delta)


func configure(
	p_minion_type: int,
	spawn_pos: Vector2,
	arena_size: Vector2,
	warning_time: float = 0.70,
	p_lifetime_beats: int = 8,
	params: Dictionary = {}
) -> void:
	minion_type = p_minion_type
	_arena_size = arena_size
	_warning_time = maxf(warning_time, 0.001)
	lifetime_beats = maxi(p_lifetime_beats, 2)
	_params = params.duplicate()
	beats_lived = 0
	phase_timer = 0.0
	_elapsed = 0.0
	_beat_pulse = 0.0
	_max_active_fallback = float(lifetime_beats + 3) * BossConstants.BEAT_DURATION
	current_phase = Phase.TELEGRAPH
	is_hazard_active = false

	match minion_type:
		BossConstants.MinionType.THREAD_SPIDER:
			hazard_kind = &"minion_thread_spider"
			_body_radius = float(_params.get("radius", 16.0))
			var from_top: bool = bool(_params.get("from_top", spawn_pos.y <= _arena_size.y * 0.5))
			var x_pos: float = clampf(spawn_pos.x, 42.0, _arena_size.x - 42.0)
			_anchor_pos = Vector2(x_pos, 0.0 if from_top else _arena_size.y)
			var default_drop: float = clampf(spawn_pos.y, 130.0, _arena_size.y - 130.0)
			_drop_target_pos = Vector2(x_pos, float(_params.get("drop_y", default_drop)))
			_drop_progress = 0.0
			_drop_goal = 0.0
			_burst_beat = clampi(int(_params.get("burst_beat", maxi(lifetime_beats / 2, 2))), 2, lifetime_beats)
			_burst_fired = false
			global_position = _anchor_pos

		BossConstants.MinionType.ORBIT_SPECTER:
			hazard_kind = &"minion_orbit_specter"
			_body_radius = float(_params.get("radius", 15.0))
			_orbit_center = _params.get("orbit_center", _arena_size * 0.5)
			var rel: Vector2 = spawn_pos - _orbit_center
			var init_r: float = rel.length() if rel.length() > 30.0 else 180.0
			_orbit_radius = maxf(float(_params.get("orbit_radius", init_r)), 64.0)
			_orbit_angle = float(_params.get("start_angle", rel.angle() if rel.length_squared() > 1.0 else 0.0))
			_orbit_target_angle = _orbit_angle
			_orbit_step_rad = float(_params.get("angular_step", PI * 0.25))
			_orbit_drift_speed = float(_params.get("angular_speed", 0.65))
			global_position = _orbit_center + Vector2.from_angle(_orbit_angle) * _orbit_radius

		BossConstants.MinionType.BORDER_SNAPPER:
			hazard_kind = &"minion_border_snapper"
			_body_radius = float(_params.get("radius", 17.0))
			_snap_leap_depth = maxf(float(_params.get("leap_depth", 175.0)), 64.0)
			var side_name: StringName = StringName(_params.get("side", _infer_nearest_side(spawn_pos)))
			match side_name:
				&"right":
					_anchor_pos = Vector2(_arena_size.x, clampf(spawn_pos.y, 48.0, _arena_size.y - 48.0))
					_snap_normal = Vector2.LEFT
				&"top":
					_anchor_pos = Vector2(clampf(spawn_pos.x, 48.0, _arena_size.x - 48.0), 0.0)
					_snap_normal = Vector2.DOWN
				&"bottom":
					_anchor_pos = Vector2(clampf(spawn_pos.x, 48.0, _arena_size.x - 48.0), _arena_size.y)
					_snap_normal = Vector2.UP
				_:
					_anchor_pos = Vector2(0.0, clampf(spawn_pos.y, 48.0, _arena_size.y - 48.0))
					_snap_normal = Vector2.RIGHT
			_snap_extension = 0.0
			_snap_goal = 0.0
			_snap_apex_pending = false
			global_position = _anchor_pos

	queue_redraw()


func on_beat(beat_idx: int, bullet_manager: Node, player_pos: Vector2) -> void:
	if _queued_free or current_phase == Phase.FADE_OUT:
		return

	_beat_pulse = 1.0
	_pending_bullet_manager = bullet_manager
	_pending_player_pos = player_pos

	if current_phase == Phase.TELEGRAPH:
		queue_redraw()
		return

	beats_lived += 1

	match minion_type:
		BossConstants.MinionType.THREAD_SPIDER:
			if beats_lived < _burst_beat:
				_drop_goal = clampf(float(beats_lived) / float(maxi(_burst_beat - 1, 1)), 0.0, 1.0)
			elif beats_lived == _burst_beat and not _burst_fired:
				_drop_goal = 1.0
				_drop_progress = 1.0
				global_position = _anchor_pos.lerp(_drop_target_pos, 1.0)
				_burst_fired = true
				if bullet_manager != null and bullet_manager.has_method(&"spawn_ring"):
					var speed: float = float(_params.get("bullet_speed", 235.0))
					var burst_count: int = clampi(int(_params.get("bullet_count", 12)), 4, 24)
					bullet_manager.spawn_ring(global_position, burst_count, speed, float(beat_idx) * 0.35, 6.0, 7.0, &"orb")
					BossConstants.play_sfx(self, &"enemy_fire", -6.0)
			else:
				var retract_beats: int = maxi(lifetime_beats - _burst_beat, 1)
				var retract_frac: float = clampf(float(beats_lived - _burst_beat) / float(retract_beats), 0.0, 1.0)
				_drop_goal = 1.0 - retract_frac

		BossConstants.MinionType.ORBIT_SPECTER:
			_orbit_target_angle += _orbit_step_rad
			if beats_lived % 2 == 0 and bullet_manager != null and bullet_manager.has_method(&"spawn_bullet"):
				var use_player_aim: bool = bool(_params.get("aim_player", false))
				var aim_target: Vector2 = player_pos if use_player_aim else _orbit_center
				var aim_dir: Vector2 = (aim_target - global_position).normalized()
				if aim_dir.length_squared() < 0.001:
					aim_dir = Vector2.RIGHT
				var speed: float = float(_params.get("bullet_speed", 285.0))
				bullet_manager.spawn_bullet(global_position, aim_dir, speed, 6.0, 7.0, &"needle")
				BossConstants.play_sfx(self, &"enemy_fire", -7.0)

		BossConstants.MinionType.BORDER_SNAPPER:
			if beats_lived % 2 == 1:
				_snap_goal = 1.0
				_snap_apex_pending = true
				BossConstants.play_sfx(self, &"enemy_lunge", -7.0)
			else:
				if _snap_apex_pending:
					_fire_snapper_fan()
				_snap_goal = 0.0

	if beats_lived >= lifetime_beats:
		current_phase = Phase.FADE_OUT
		phase_timer = 0.0
		is_hazard_active = false

	queue_redraw()


func simulate_physics(delta: float, player_node: Node2D = null) -> void:
	if _queued_free:
		return

	_elapsed += delta
	phase_timer += delta
	_beat_pulse = maxf(0.0, _beat_pulse - delta * 3.8)

	match current_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if phase_timer >= _warning_time:
				current_phase = Phase.ACTIVE
				phase_timer = 0.0
				is_hazard_active = true
				_check_player_overlap(player_node)
		Phase.ACTIVE:
			is_hazard_active = true
			_step_minion_motion(delta)
			_check_player_overlap(player_node)
			if phase_timer >= _max_active_fallback:
				current_phase = Phase.FADE_OUT
				phase_timer = 0.0
				is_hazard_active = false
		Phase.FADE_OUT:
			is_hazard_active = false
			if phase_timer >= FADE_DURATION:
				_queued_free = true
				queue_free()
				return

	queue_redraw()


func _step_minion_motion(delta: float) -> void:
	match minion_type:
		BossConstants.MinionType.THREAD_SPIDER:
			_drop_progress = lerpf(_drop_progress, _drop_goal, clampf(delta * 10.0, 0.0, 1.0))
			global_position = _anchor_pos.lerp(_drop_target_pos, _drop_progress)

		BossConstants.MinionType.ORBIT_SPECTER:
			_orbit_target_angle += _orbit_drift_speed * delta
			_orbit_angle = lerpf(_orbit_angle, _orbit_target_angle, clampf(delta * 9.0, 0.0, 1.0))
			global_position = _orbit_center + Vector2.from_angle(_orbit_angle) * _orbit_radius

		BossConstants.MinionType.BORDER_SNAPPER:
			var rate: float = 11.0 if _snap_goal > _snap_extension else 6.5
			_snap_extension = lerpf(_snap_extension, _snap_goal, clampf(delta * rate, 0.0, 1.0))
			global_position = _anchor_pos + _snap_normal * (_snap_leap_depth * _snap_extension)
			if _snap_apex_pending and _snap_extension >= 0.88:
				_fire_snapper_fan()


func _fire_snapper_fan() -> void:
	_snap_apex_pending = false
	if _pending_bullet_manager == null or not is_instance_valid(_pending_bullet_manager):
		return
	if not _pending_bullet_manager.has_method(&"spawn_fan"):
		return
	var aim_dir: Vector2 = _snap_normal
	var to_player: Vector2 = _pending_player_pos - global_position
	if to_player.length_squared() > 16.0 and to_player.normalized().dot(_snap_normal) > 0.15:
		aim_dir = to_player.normalized()
	var speed: float = float(_params.get("bullet_speed", 255.0))
	_pending_bullet_manager.spawn_fan(global_position, aim_dir, 3, 0.30, speed, 6.0, 7.0, &"diamond")
	BossConstants.play_sfx(self, &"enemy_fire", -6.0)


func _check_player_overlap(player_node: Node2D = null) -> void:
	if not is_hazard_active:
		return
	var players: Array[Node2D] = BossConstants.collect_players(self, player_node)
	for body: Node2D in players:
		var player_r: float = BossConstants.get_player_hit_radius(body)
		var hit_r: float = _body_radius + player_r
		if body.global_position.distance_squared_to(global_position) <= hit_r * hit_r:
			BossConstants.apply_player_hit(body, parryable, hazard_kind)


func _infer_nearest_side(pos: Vector2) -> StringName:
	var d_left: float = pos.x
	var d_right: float = _arena_size.x - pos.x
	var d_top: float = pos.y
	var d_bottom: float = _arena_size.y - pos.y
	var best: float = minf(minf(d_left, d_right), minf(d_top, d_bottom))
	if best == d_right:
		return &"right"
	if best == d_top:
		return &"top"
	if best == d_bottom:
		return &"bottom"
	return &"left"


func _draw() -> void:
	var alpha: float = 1.0
	var scale_f: float = 1.0 + 0.15 * _beat_pulse
	if current_phase == Phase.TELEGRAPH:
		var progress: float = clampf(phase_timer / maxf(_warning_time, 0.001), 0.0, 1.0)
		alpha = lerpf(0.46, 0.92, progress)
		scale_f = lerpf(0.55, 1.0, progress)
	elif current_phase == Phase.FADE_OUT:
		var fade_t: float = clampf(phase_timer / maxf(FADE_DURATION, 0.001), 0.0, 1.0)
		alpha = 1.0 - fade_t
		scale_f = lerpf(1.0, 0.25, fade_t)

	match minion_type:
		BossConstants.MinionType.THREAD_SPIDER:
			_draw_thread_spider(alpha, scale_f)
		BossConstants.MinionType.ORBIT_SPECTER:
			_draw_orbit_specter(alpha, scale_f)
		BossConstants.MinionType.BORDER_SNAPPER:
			_draw_border_snapper(alpha, scale_f)


func _draw_thread_spider(alpha: float, scale_f: float) -> void:
	var local_anchor: Vector2 = to_local(_anchor_pos)
	var local_drop: Vector2 = to_local(_drop_target_pos)
	# Dotted monochrome hanging thread
	BossConstants.draw_dashed_line(self, local_anchor, Vector2.ZERO, Color(0.62, 0.62, 0.62, alpha * 0.68), 1.3, 6.0, 6.0, 0.0)
	if current_phase == Phase.TELEGRAPH:
		BossConstants.draw_dashed_line(self, Vector2.ZERO, local_drop, Color(0.65, 0.65, 0.65, alpha * 0.45), 1.1, 6.0, 8.0, _elapsed * 40.0)

	var r: float = _body_radius * scale_f
	var rim_col: Color = Color(0.02, 0.02, 0.02, 0.94 * alpha)
	# 8 angular geometric spider legs (16 segments = 32 points)
	var leg_col: Color = Color(0.95, 0.95, 0.95, alpha)
	var leg_pts: PackedVector2Array = PackedVector2Array()
	leg_pts.resize(32)
	var idx: int = 0
	for side_s: int in [-1, 1]:
		for k: int in range(4):
			var spread_a: float = -0.65 + float(k) * 0.44
			var knee: Vector2 = Vector2(float(side_s) * r * 1.35, sin(spread_a) * r * 1.1)
			var foot: Vector2 = Vector2(float(side_s) * r * 1.85, sin(spread_a) * r * 1.65 + cos(_elapsed * 9.0 + float(k)) * 2.5)
			leg_pts[idx] = Vector2.ZERO
			leg_pts[idx + 1] = knee
			leg_pts[idx + 2] = knee
			leg_pts[idx + 3] = foot
			idx += 4
	draw_multiline(leg_pts, rim_col, 3.4, true)
	draw_multiline(leg_pts, leg_col, 1.6, true)

	# Octagonal geometric body + pitch-black outer isolation rim + dark void eye
	var body_rim_pts: PackedVector2Array = Shapes.circle(r + 2.6, 8, PI / 8.0)
	draw_colored_polygon(body_rim_pts, rim_col)
	var body_pts: PackedVector2Array = Shapes.circle(r, 8, PI / 8.0)
	draw_colored_polygon(body_pts, Color(0.98, 0.98, 0.98, alpha))
	draw_circle(Vector2.ZERO, r * 0.44, Color(0.06, 0.06, 0.06, alpha))
	draw_circle(Vector2.ZERO, r * 0.16, Color(1.0, 1.0, 1.0, alpha))


func _draw_orbit_specter(alpha: float, scale_f: float) -> void:
	var local_center: Vector2 = to_local(_orbit_center)
	var arc_a: float = (-local_center).angle()
	draw_arc(local_center, _orbit_radius, arc_a - 0.35, arc_a + 0.35, 16, Color(0.72, 0.72, 0.72, alpha * 0.35), 1.3, true)

	var r: float = _body_radius * scale_f
	var rim_col: Color = Color(0.02, 0.02, 0.02, 0.94 * alpha)
	var spin: float = _elapsed * 3.2
	var outer_rim_pts: PackedVector2Array = PackedVector2Array()
	outer_rim_pts.resize(4)
	var outer_pts: PackedVector2Array = PackedVector2Array()
	outer_pts.resize(4)
	var inner_pts: PackedVector2Array = PackedVector2Array()
	inner_pts.resize(4)
	for k: int in range(4):
		var a: float = spin + float(k) * PI * 0.5
		var dir: Vector2 = Vector2.from_angle(a)
		outer_rim_pts[k] = dir * (r * 1.25 + 2.6)
		outer_pts[k] = dir * (r * 1.25)
		inner_pts[k] = Vector2.from_angle(a + PI * 0.25) * (r * 0.62)

	draw_colored_polygon(outer_rim_pts, rim_col)
	draw_colored_polygon(outer_pts, Color(0.98, 0.98, 0.98, alpha))
	draw_colored_polygon(inner_pts, Color(0.06, 0.06, 0.06, alpha))
	draw_circle(Vector2.ZERO, r * 0.22, Color(1.0, 1.0, 1.0, alpha))


func _draw_border_snapper(alpha: float, scale_f: float) -> void:
	var fwd: Vector2 = _snap_normal
	var side: Vector2 = Vector2(-fwd.y, fwd.x)
	var local_anchor: Vector2 = to_local(_anchor_pos)
	var r: float = _body_radius * scale_f
	var rim_col: Color = Color(0.02, 0.02, 0.02, 0.94 * alpha)

	# Guide line back to anchor
	BossConstants.draw_dashed_line(self, local_anchor, Vector2.ZERO, Color(0.74, 0.74, 0.74, alpha * 0.55), 1.5, 8.0, 6.0, 0.0)
	if current_phase == Phase.TELEGRAPH:
		var preview_end: Vector2 = fwd * _snap_leap_depth
		BossConstants.draw_dashed_line(self, Vector2.ZERO, preview_end, Color(0.78, 0.78, 0.78, alpha * 0.5), 1.2, 8.0, 8.0, _elapsed * 55.0)

	# Serrated geometric fin / jaw wedge with pitch-black outer isolation rim
	var poly: PackedVector2Array = PackedVector2Array([
		fwd * (r * 1.65),
		fwd * (r * 0.45) + side * (r * 1.05),
		-fwd * (r * 0.15) + side * (r * 0.62),
		-fwd * (r * 0.65) + side * (r * 1.18),
		-fwd * (r * 1.15),
		-fwd * (r * 0.65) - side * (r * 1.18),
		-fwd * (r * 0.15) - side * (r * 0.62),
		fwd * (r * 0.45) - side * (r * 1.05),
	])
	var rim_scale: float = (r + 2.6) / maxf(r, 1.0)
	var rim_poly: PackedVector2Array = PackedVector2Array()
	rim_poly.resize(poly.size())
	for i: int in range(poly.size()):
		rim_poly[i] = poly[i] * rim_scale
	draw_colored_polygon(rim_poly, rim_col)
	draw_colored_polygon(poly, Color(0.98, 0.98, 0.98, alpha))
	draw_line(-fwd * (r * 0.55), fwd * (r * 0.85), Color(0.06, 0.06, 0.06, alpha), 2.4, true)
