class_name BossSpikeRing
extends Node2D

enum RingMode {
	ORBIT_RING = 0,
	BORDER_CAGE = 1,
}

enum Phase {
	TELEGRAPH = 0,
	ACTIVE = 1,
	FADE_OUT = 2,
}

const FADE_DURATION: float = 0.25
const CIRCLE_VERTS: int = 12

var is_hazard_active: bool = false
var parryable: bool = false
var hazard_kind: StringName = &"spike_ring"

var ring_mode: int = RingMode.ORBIT_RING
var current_phase: int = Phase.TELEGRAPH
var phase_timer: float = 0.0
var current_radius: float = 78.0

var _count: int = 10
var _start_radius: float = 78.0
var _end_radius: float = 78.0
var _spike_radius: float = BossConstants.SPIKE_RADIUS
var _angular_speed: float = 2.6
var _warning_time: float = 0.70
var _duration: float = 5.5
var _follow_node: Node2D = null

var _arena_size: Vector2 = BossConstants.ARENA_REF
var _cage_margin: float = 32.0
var _cage_speed: float = 160.0
var _cage_perimeter: float = 1000.0
var _cage_offset: float = 0.0

var _orbit_angle: float = 0.0
var _spin_angle: float = 0.0
var _release_flash: float = 0.0
var _spike_world_positions: Array[Vector2] = []
var _spike_tangents: Array[Vector2] = []
var _saw_template: PackedVector2Array = PackedVector2Array()
var _rotated_saw: PackedVector2Array = PackedVector2Array()
var _outline_pts: PackedVector2Array = PackedVector2Array()
var _unit_circle: PackedVector2Array = PackedVector2Array()
var _tri_pts: PackedVector2Array = PackedVector2Array()
var _tri_cols: PackedColorArray = PackedColorArray()
var _tri_indices: PackedInt32Array = PackedInt32Array()
var _tri_v_i: int = 0
var _tri_idx_i: int = 0
var _queued_free: bool = false


func _init() -> void:
	add_to_group("boss_hazards")
	_unit_circle.resize(CIRCLE_VERTS)
	for k: int in range(CIRCLE_VERTS):
		var a: float = float(k) * TAU / float(CIRCLE_VERTS)
		_unit_circle[k] = Vector2(cos(a), sin(a))
	_rebuild_saw_template()


func _ready() -> void:
	if not is_in_group("boss_hazards"):
		add_to_group("boss_hazards")
	queue_redraw()


func _physics_process(delta: float) -> void:
	simulate_physics(delta)


func configure_orbit(
	center_pos: Vector2,
	count: int = 10,
	start_radius: float = 78.0,
	end_radius: float = 78.0,
	spike_radius: float = BossConstants.SPIKE_RADIUS,
	angular_speed: float = 2.6,
	warning_time: float = 0.70,
	duration: float = 5.5,
	follow_node: Node2D = null
) -> void:
	ring_mode = RingMode.ORBIT_RING
	hazard_kind = &"spike_ring"
	global_position = center_pos
	_count = maxi(count, 3)
	_start_radius = maxf(start_radius, 18.0)
	_end_radius = maxf(end_radius, 18.0)
	current_radius = _start_radius
	_spike_radius = maxf(spike_radius, 8.0)
	_angular_speed = angular_speed
	_warning_time = maxf(warning_time, 0.001)
	_duration = maxf(duration, 0.1)
	_follow_node = follow_node
	_orbit_angle = 0.0
	_spin_angle = 0.0
	_release_flash = 0.0
	current_phase = Phase.TELEGRAPH
	phase_timer = 0.0
	is_hazard_active = false
	_rebuild_saw_template()
	_update_spike_positions()
	queue_redraw()


func configure_border_cage(
	arena_size: Vector2,
	margin: float = 32.0,
	spike_radius: float = BossConstants.SPIKE_RADIUS,
	speed: float = 160.0,
	warning_time: float = 0.9375,
	duration: float = 7.5
) -> void:
	ring_mode = RingMode.BORDER_CAGE
	hazard_kind = &"border_cage"
	global_position = Vector2.ZERO
	_arena_size = arena_size
	_cage_margin = clampf(margin, 14.0, minf(arena_size.x, arena_size.y) * 0.35)
	_spike_radius = maxf(spike_radius, 8.0)
	_cage_speed = speed
	_warning_time = maxf(warning_time, 0.001)
	_duration = maxf(duration, 0.1)
	_follow_node = null

	var w: float = maxf(_arena_size.x - _cage_margin * 2.0, 40.0)
	var h: float = maxf(_arena_size.y - _cage_margin * 2.0, 40.0)
	_cage_perimeter = 2.0 * (w + h)
	_count = maxi(int(round(_cage_perimeter / 150.0)), 12)
	_cage_offset = 0.0
	_spin_angle = 0.0
	_release_flash = 0.0
	current_phase = Phase.TELEGRAPH
	phase_timer = 0.0
	is_hazard_active = false
	_rebuild_saw_template()
	_update_spike_positions()
	queue_redraw()


func release_tangential_spikes(bullet_manager: Node, speed: float = 275.0, every_nth: int = 2) -> void:
	if bullet_manager == null or not bullet_manager.has_method(&"spawn_bullet"):
		return
	if _spike_world_positions.is_empty():
		_update_spike_positions()
	var step: int = maxi(every_nth, 1)
	for i: int in range(0, _spike_world_positions.size(), step):
		var pos: Vector2 = _spike_world_positions[i]
		var fire_dir: Vector2 = _spike_tangents[i]
		bullet_manager.spawn_bullet(pos, fire_dir, speed, BossConstants.BULLET_RADIUS, 7.0, &"spike")
	_release_flash = 1.0
	BossConstants.play_sfx(self, &"enemy_fire", -6.0)
	queue_redraw()


func get_spike_count() -> int:
	return _spike_world_positions.size()


func simulate_physics(delta: float, player_node: Node2D = null) -> void:
	if _queued_free:
		return

	if ring_mode == RingMode.ORBIT_RING and _follow_node != null and is_instance_valid(_follow_node):
		global_position = _follow_node.global_position

	phase_timer += delta
	_spin_angle += delta * 5.4
	_release_flash = maxf(0.0, _release_flash - delta * 4.5)

	match current_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if ring_mode == RingMode.ORBIT_RING:
				current_radius = _start_radius
			_update_spike_positions()
			if phase_timer >= _warning_time:
				current_phase = Phase.ACTIVE
				phase_timer = 0.0
				is_hazard_active = true
				BossConstants.play_sfx(self, &"saw_bounce", -6.0)
				_check_player_overlap(player_node)
		Phase.ACTIVE:
			is_hazard_active = true
			var progress: float = clampf(phase_timer / maxf(_duration, 0.001), 0.0, 1.0)
			if ring_mode == RingMode.ORBIT_RING:
				current_radius = lerpf(_start_radius, _end_radius, progress)
				_orbit_angle += _angular_speed * delta
			else:
				_cage_offset = fposmod(_cage_offset + _cage_speed * delta, _cage_perimeter)
			_update_spike_positions()
			_check_player_overlap(player_node)
			if phase_timer >= _duration:
				current_phase = Phase.FADE_OUT
				phase_timer = 0.0
				is_hazard_active = false
		Phase.FADE_OUT:
			is_hazard_active = false
			_update_spike_positions()
			if phase_timer >= FADE_DURATION:
				_queued_free = true
				queue_free()
				return

	queue_redraw()


func _update_spike_positions() -> void:
	_spike_world_positions.resize(_count)
	_spike_tangents.resize(_count)

	if ring_mode == RingMode.ORBIT_RING:
		var rot_sign: float = 1.0 if _angular_speed >= 0.0 else -1.0
		var step: float = TAU / float(_count)
		for i: int in range(_count):
			var a: float = _orbit_angle + step * float(i)
			_spike_world_positions[i] = global_position + Vector2.from_angle(a) * current_radius
			_spike_tangents[i] = Vector2.from_angle(a + rot_sign * PI * 0.5)
	else:
		var left: float = _cage_margin
		var right: float = _arena_size.x - _cage_margin
		var top: float = _cage_margin
		var bottom: float = _arena_size.y - _cage_margin
		var w: float = maxf(right - left, 1.0)
		var h: float = maxf(bottom - top, 1.0)
		var stride: float = _cage_perimeter / float(_count)
		var travel_sign: float = 1.0 if _cage_speed >= 0.0 else -1.0
		for i: int in range(_count):
			var s: float = fposmod(_cage_offset + stride * float(i), _cage_perimeter)
			var pos: Vector2
			var tang: Vector2
			var inward: Vector2
			if s < w:
				pos = Vector2(left + s, top)
				tang = Vector2(travel_sign, 0.0)
				inward = Vector2.DOWN
			elif s < w + h:
				pos = Vector2(right, top + (s - w))
				tang = Vector2(0.0, travel_sign)
				inward = Vector2.LEFT
			elif s < 2.0 * w + h:
				pos = Vector2(right - (s - (w + h)), bottom)
				tang = Vector2(-travel_sign, 0.0)
				inward = Vector2.UP
			else:
				pos = Vector2(left, bottom - (s - (2.0 * w + h)))
				tang = Vector2(0.0, -travel_sign)
				inward = Vector2.RIGHT
			_spike_world_positions[i] = pos
			_spike_tangents[i] = (tang * 0.55 + inward * 0.85).normalized()


func _check_player_overlap(player_node: Node2D = null) -> void:
	if not is_hazard_active:
		return
	var players: Array[Node2D] = BossConstants.collect_players(self, player_node)
	var eff_spike_r: float = _spike_radius * 0.88
	for body: Node2D in players:
		var player_r: float = BossConstants.get_player_hit_radius(body)
		var hit_r_sq: float = (eff_spike_r + player_r) * (eff_spike_r + player_r)
		var p_pos: Vector2 = body.global_position
		for s_pos: Vector2 in _spike_world_positions:
			if p_pos.distance_squared_to(s_pos) <= hit_r_sq:
				BossConstants.apply_player_hit(body, parryable, hazard_kind)
				break


func _rebuild_saw_template() -> void:
	_saw_template = Shapes.saw(_spike_radius, 12, 0.68)
	_rotated_saw.resize(_saw_template.size())


func _append_tri_circle(center: Vector2, rad: float, col: Color) -> void:
	var b: int = _tri_v_i
	var idx_i: int = _tri_idx_i
	_tri_pts[b] = center
	_tri_cols[b] = col
	for k: int in range(CIRCLE_VERTS):
		_tri_pts[b + 1 + k] = center + _unit_circle[k] * rad
		_tri_cols[b + 1 + k] = col
		_tri_indices[idx_i] = b
		_tri_indices[idx_i + 1] = b + 1 + k
		_tri_indices[idx_i + 2] = b + 1 + ((k + 1) % CIRCLE_VERTS)
		idx_i += 3
	_tri_v_i = b + 1 + CIRCLE_VERTS
	_tri_idx_i = idx_i


func _draw_saws_batched(scale_factor: float, fill_col: Color, rim_col: Color, core_col: Color) -> void:
	var n_saws: int = _spike_world_positions.size()
	var n_verts: int = _saw_template.size()
	if scale_factor <= 0.05 or n_saws == 0 or n_verts == 0:
		return

	if _rotated_saw.size() != n_verts:
		_rotated_saw.resize(n_verts)

	var local_origin: Vector2 = to_local(Vector2.ZERO)
	var cs: float = cos(_spin_angle) * scale_factor
	var sn: float = sin(_spin_angle) * scale_factor
	for k: int in range(n_verts):
		var v: Vector2 = _saw_template[k]
		_rotated_saw[k] = Vector2(v.x * cs - v.y * sn, v.x * sn + v.y * cs)

	_outline_pts.resize(n_saws * n_verts * 2)
	_tri_pts.resize(n_saws * (1 + n_verts))
	_tri_cols.resize(n_saws * (1 + n_verts))
	_tri_indices.resize(n_saws * n_verts * 3)
	var out_i: int = 0
	var tri_v_i: int = 0
	var tri_idx_i: int = 0

	# Pass 1: batch all outer saw polygon fills into 1 triangle array (and pack outline segments)
	for w_pos: Vector2 in _spike_world_positions:
		var local_pos: Vector2 = w_pos + local_origin
		var b: int = tri_v_i
		_tri_pts[b] = local_pos
		_tri_cols[b] = fill_col
		for k: int in range(n_verts):
			_tri_pts[b + 1 + k] = local_pos + _rotated_saw[k]
			_tri_cols[b + 1 + k] = fill_col
		for k: int in range(n_verts):
			var next_k: int = (k + 1) % n_verts
			_tri_indices[tri_idx_i] = b
			_tri_indices[tri_idx_i + 1] = b + 1 + k
			_tri_indices[tri_idx_i + 2] = b + 1 + next_k
			tri_idx_i += 3
			_outline_pts[out_i] = _tri_pts[b + 1 + k]
			_outline_pts[out_i + 1] = _tri_pts[b + 1 + next_k]
			out_i += 2
		tri_v_i += 1 + n_verts

	if tri_idx_i >= 3:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _tri_indices, _tri_pts, _tri_cols)

	# Pass 2: all saw outlines in 1 draw_multiline() call
	if _outline_pts.size() >= 2:
		draw_multiline(_outline_pts, rim_col, 1.2, true)

	# Pass 3: all dark inner core circles, then all center rim circles in 1 batched triangle array
	var core_r: float = _spike_radius * 0.42 * scale_factor
	var center_r: float = _spike_radius * 0.16 * scale_factor
	_tri_pts.resize(n_saws * 2 * (1 + CIRCLE_VERTS))
	_tri_cols.resize(n_saws * 2 * (1 + CIRCLE_VERTS))
	_tri_indices.resize(n_saws * 2 * CIRCLE_VERTS * 3)
	_tri_v_i = 0
	_tri_idx_i = 0
	for w_pos: Vector2 in _spike_world_positions:
		_append_tri_circle(w_pos + local_origin, core_r, core_col)
	for w_pos: Vector2 in _spike_world_positions:
		_append_tri_circle(w_pos + local_origin, center_r, rim_col)
	if _tri_idx_i >= 3:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _tri_indices, _tri_pts, _tri_cols)


func _draw() -> void:
	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(_warning_time, 0.001), 0.0, 1.0)
			var rail_col: Color = Color(0.84, 0.84, 0.84, lerpf(0.46, 0.88, progress))
			if ring_mode == RingMode.ORBIT_RING:
				BossConstants.draw_dashed_circle(self, Vector2.ZERO, current_radius, rail_col, 1.8, 32, 0.55, _orbit_angle)
			else:
				var rect: Rect2 = Rect2(_cage_margin, _cage_margin, _arena_size.x - _cage_margin * 2.0, _arena_size.y - _cage_margin * 2.0)
				draw_rect(rect, rail_col, false, 1.8)

			var ghost_scale: float = lerpf(0.42, 1.0, ease(progress, 0.55))
			var fill_col: Color = Color(0.76, 0.76, 0.76, lerpf(0.22, 0.55, progress))
			var rim_col: Color = Color(0.95, 0.95, 0.95, lerpf(0.50, 0.94, progress))
			var core_col: Color = Color(0.12, 0.12, 0.12, 0.55 * progress)
			_draw_saws_batched(ghost_scale, fill_col, rim_col, core_col)

		Phase.ACTIVE:
			var rail_col: Color = Color(0.62, 0.62, 0.62, 0.28 + 0.20 * _release_flash)
			if ring_mode == RingMode.ORBIT_RING:
				draw_arc(Vector2.ZERO, current_radius, 0.0, TAU, 48, rail_col, 1.4, true)
			else:
				var rect: Rect2 = Rect2(_cage_margin, _cage_margin, _arena_size.x - _cage_margin * 2.0, _arena_size.y - _cage_margin * 2.0)
				draw_rect(rect, rail_col, false, 1.4)

			var s: float = 1.0 + 0.14 * _release_flash
			var fill_col: Color = Color(0.96, 0.96, 0.96, 1.0)
			var rim_col: Color = Color(1.0, 1.0, 1.0, 1.0)
			var core_col: Color = Color(0.06, 0.06, 0.06, 1.0)
			_draw_saws_batched(s, fill_col, rim_col, core_col)

		Phase.FADE_OUT:
			var fade_t: float = clampf(phase_timer / maxf(FADE_DURATION, 0.001), 0.0, 1.0)
			var inv: float = 1.0 - fade_t
			var fill_col: Color = Color(0.82, 0.82, 0.82, inv * 0.78)
			var rim_col: Color = Color(0.92, 0.92, 0.92, inv * 0.85)
			var core_col: Color = Color(0.10, 0.10, 0.10, inv * 0.75)
			_draw_saws_batched(lerpf(1.0, 0.2, fade_t), fill_col, rim_col, core_col)
