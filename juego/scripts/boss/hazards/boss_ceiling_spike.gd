class_name BossCeilingSpike
extends Node2D

enum SpearState {
	DELAYED = 0,
	TELEGRAPH = 1,
	FALLING = 2,
	DONE = 3,
}

var is_hazard_active: bool = false
var parryable: bool = false
var hazard_kind: StringName = &"ceiling_spike"

var _arena_size: Vector2 = BossConstants.ARENA_REF
var _from_top: bool = true
var _warning_time: float = 0.9375
var _fall_speed: float = 540.0
var _spike_radius: float = 15.0
var _spears: Array[Dictionary] = []
var _elapsed: float = 0.0
var _queued_free: bool = false
var _scratch_tip: PackedVector2Array = PackedVector2Array()
var _scratch_spear: PackedVector2Array = PackedVector2Array()
var _thread_pts: PackedVector2Array = PackedVector2Array()
var _thread_cols: PackedColorArray = PackedColorArray()
var _tip_outline_pts: PackedVector2Array = PackedVector2Array()
var _chev_pts: PackedVector2Array = PackedVector2Array()
var _chev_cols: PackedColorArray = PackedColorArray()
var _trail_pts: PackedVector2Array = PackedVector2Array()
var _spine_pts: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_scratch_tip.resize(3)
	_scratch_spear.resize(6)
	add_to_group("boss_hazards")


func _ready() -> void:
	if not is_in_group("boss_hazards"):
		add_to_group("boss_hazards")
	queue_redraw()


func _physics_process(delta: float) -> void:
	simulate_physics(delta)


func configure_curtain(
	arena_size: Vector2,
	from_top: bool,
	count: int,
	safe_lane_x: float,
	safe_half_width: float = 82.0,
	warning_time: float = 0.9375,
	fall_speed: float = 540.0,
	cascade_delay: float = 0.04,
	spike_radius: float = 15.0
) -> void:
	global_position = Vector2.ZERO
	_arena_size = arena_size
	_from_top = from_top
	_warning_time = maxf(warning_time, 0.001)
	_fall_speed = maxf(fall_speed, 60.0)
	_spike_radius = maxf(spike_radius, 8.0)
	_elapsed = 0.0
	is_hazard_active = false
	_spears.clear()

	var n: int = maxi(count, 2)
	var margin: float = maxf(_spike_radius + 16.0, 30.0)
	var usable_w: float = maxf(_arena_size.x - margin * 2.0, 20.0)
	var safe_half: float = maxf(safe_half_width, 64.0)
	var safe_x: float = clampf(safe_lane_x, margin + safe_half * 0.5, _arena_size.x - margin - safe_half * 0.5)
	var start_y: float = -_spike_radius * 1.4 if _from_top else (_arena_size.y + _spike_radius * 1.4)
	var dir_y: float = 1.0 if _from_top else -1.0

	var idx_active: int = 0
	for i: int in range(n):
		var frac: float = float(i) / float(maxi(n - 1, 1))
		var x: float = margin + usable_w * frac
		if absf(x - safe_x) < safe_half:
			continue
		var d: float = float(idx_active) * maxf(cascade_delay, 0.0)
		_spears.append({
			"x": x,
			"y": start_y,
			"prev_y": start_y,
			"dir_y": dir_y,
			"radius": _spike_radius,
			"delay": d,
			"timer": 0.0,
			"state": SpearState.DELAYED if d > 0.0001 else SpearState.TELEGRAPH,
		})
		idx_active += 1

	queue_redraw()


func get_spear_count() -> int:
	return _spears.size()


func simulate_physics(delta: float, player_node: Node2D = null) -> void:
	if _queued_free:
		return

	if _spears.is_empty():
		is_hazard_active = false
		_queued_free = true
		queue_free()
		return

	_elapsed += delta
	var any_falling: bool = false
	var any_alive: bool = false
	var exit_margin: float = _spike_radius * 3.5

	for sp: Dictionary in _spears:
		var state: int = int(sp["state"])
		var rem_dt: float = delta

		if state == SpearState.DELAYED:
			any_alive = true
			var rem: float = float(sp["delay"]) - rem_dt
			if rem <= 0.0:
				sp["delay"] = 0.0
				state = SpearState.TELEGRAPH
				sp["state"] = state
				sp["timer"] = 0.0
				rem_dt = -rem
			else:
				sp["delay"] = rem
				rem_dt = 0.0

		if state == SpearState.TELEGRAPH:
			any_alive = true
			var t: float = float(sp["timer"]) + rem_dt
			if t >= _warning_time:
				state = SpearState.FALLING
				sp["state"] = state
				sp["timer"] = 0.0
				rem_dt = t - _warning_time
				BossConstants.play_sfx(self, &"enemy_lunge", -10.0)
			else:
				sp["timer"] = t
				rem_dt = 0.0

		if state == SpearState.FALLING:
			any_alive = true
			any_falling = true
			var prev_y: float = float(sp["y"])
			var dir_y: float = float(sp["dir_y"])
			var next_y: float = prev_y + dir_y * _fall_speed * rem_dt
			sp["prev_y"] = prev_y
			sp["y"] = next_y
			if (dir_y > 0.0 and next_y > _arena_size.y + exit_margin) or (dir_y < 0.0 and next_y < -exit_margin):
				sp["state"] = SpearState.DONE

	is_hazard_active = any_falling
	if is_hazard_active:
		_check_player_overlap(player_node)

	if not any_alive:
		is_hazard_active = false
		_queued_free = true
		queue_free()
		return

	queue_redraw()


func _check_player_overlap(player_node: Node2D = null) -> void:
	var players: Array[Node2D] = BossConstants.collect_players(self, player_node)
	if players.is_empty():
		return
	for body: Node2D in players:
		var player_r: float = BossConstants.get_player_hit_radius(body)
		var p_pos: Vector2 = body.global_position
		for sp: Dictionary in _spears:
			if int(sp["state"]) != SpearState.FALLING:
				continue
			var x: float = float(sp["x"])
			var y0: float = float(sp["prev_y"])
			var y1: float = float(sp["y"])
			var r: float = float(sp["radius"]) * 0.85
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p_pos, Vector2(x, y0), Vector2(x, y1))
			var hit_r: float = r + player_r
			if closest.distance_squared_to(p_pos) <= hit_r * hit_r:
				BossConstants.apply_player_hit(body, parryable, hazard_kind)
				break


func _draw() -> void:
	if _spears.is_empty():
		return

	var edge_y: float = 0.0 if _from_top else _arena_size.y
	var opp_y: float = _arena_size.y if _from_top else 0.0
	var warn_t: float = maxf(_warning_time, 0.001)

	_thread_pts.resize(0)
	_thread_cols.resize(0)
	_tip_outline_pts.resize(0)
	_chev_pts.resize(0)
	_chev_cols.resize(0)
	_trail_pts.resize(0)
	_spine_pts.resize(0)

	# Pass 1: collect and draw background dashed threads & falling speed trails
	for sp: Dictionary in _spears:
		var state: int = int(sp["state"])
		if state == SpearState.DELAYED or state == SpearState.DONE:
			continue
		var x: float = float(sp["x"])
		var dir_y: float = float(sp["dir_y"])
		var r: float = float(sp["radius"])
		if state == SpearState.TELEGRAPH:
			var progress: float = clampf(float(sp["timer"]) / warn_t, 0.0, 1.0)
			var thread_col: Color = Color(0.88, 0.88, 0.88, lerpf(0.46, 0.92, progress))
			var prev_sz: int = _thread_pts.size()
			_thread_pts = BossConstants.append_dashed_line_pts(_thread_pts, Vector2(x, edge_y), Vector2(x, opp_y), 10.0, 9.0, _elapsed * 60.0 * dir_y)
			var added_segs: int = (_thread_pts.size() - prev_sz) / 2
			if added_segs > 0:
				var col_idx: int = _thread_cols.size()
				_thread_cols.resize(col_idx + added_segs)
				for k: int in range(added_segs):
					_thread_cols[col_idx + k] = thread_col
		elif state == SpearState.FALLING:
			var y: float = float(sp["y"])
			var tail_len: float = r * 4.2
			var t_idx: int = _trail_pts.size()
			_trail_pts.resize(t_idx + 2)
			_trail_pts[t_idx] = Vector2(x, y - dir_y * r * 1.1)
			_trail_pts[t_idx + 1] = Vector2(x, y - dir_y * (r * 1.1 + tail_len))

	if _thread_pts.size() >= 2:
		draw_multiline_colors(_thread_pts, _thread_cols, 1.6, true)
	if _trail_pts.size() >= 2:
		draw_multiline(_trail_pts, Color(0.70, 0.70, 0.70, 0.42), maxf(_spike_radius * 0.35, 2.0), true)

	# Pass 2: emit all filled polygons (tips & spears) while collecting outlines, chevrons & spines
	var spear_fill_col: Color = Color(1.0, 1.0, 1.0, 1.0)
	for sp: Dictionary in _spears:
		var state: int = int(sp["state"])
		if state == SpearState.DELAYED or state == SpearState.DONE:
			continue
		var x: float = float(sp["x"])
		var dir_y: float = float(sp["dir_y"])
		var r: float = float(sp["radius"])

		if state == SpearState.TELEGRAPH:
			var progress: float = clampf(float(sp["timer"]) / warn_t, 0.0, 1.0)
			var peek: float = lerpf(r * 0.65, r * 1.85, ease(progress, 0.55))
			var half_w: float = r * lerpf(0.55, 0.88, progress)
			var tip_pt: Vector2 = Vector2(x, edge_y + dir_y * peek)
			var left_pt: Vector2 = Vector2(x - half_w, edge_y)
			var right_pt: Vector2 = Vector2(x + half_w, edge_y)
			_scratch_tip[0] = tip_pt
			_scratch_tip[1] = left_pt
			_scratch_tip[2] = right_pt
			draw_colored_polygon(_scratch_tip, Color(0.96, 0.96, 0.96, lerpf(0.52, 0.98, progress)))

			var o_idx: int = _tip_outline_pts.size()
			_tip_outline_pts.resize(o_idx + 4)
			_tip_outline_pts[o_idx] = left_pt
			_tip_outline_pts[o_idx + 1] = tip_pt
			_tip_outline_pts[o_idx + 2] = right_pt
			_tip_outline_pts[o_idx + 3] = tip_pt

			var chev_y: float = edge_y + dir_y * lerpf(r * 4.4, r * 2.1, progress)
			var chev_col: Color = Color(0.92, 0.92, 0.92, lerpf(0.48, 0.95, progress))
			_chev_pts = BossConstants.append_double_chevron_pts(_chev_pts, Vector2(x, chev_y), Vector2(0.0, dir_y), 7.0)
			var c_idx: int = _chev_cols.size()
			_chev_cols.resize(c_idx + 4)
			for k: int in range(4):
				_chev_cols[c_idx + k] = chev_col

		elif state == SpearState.FALLING:
			var y: float = float(sp["y"])
			var tip_y: float = y + dir_y * (r * 1.95)
			var shoulder_y: float = y - dir_y * (r * 0.55)
			var base_y: float = y - dir_y * (r * 1.45)
			_scratch_spear[0] = Vector2(x, tip_y)
			_scratch_spear[1] = Vector2(x + r * 0.88, shoulder_y)
			_scratch_spear[2] = Vector2(x + r * 0.36, base_y)
			_scratch_spear[3] = Vector2(x, y - dir_y * (r * 0.95))
			_scratch_spear[4] = Vector2(x - r * 0.36, base_y)
			_scratch_spear[5] = Vector2(x - r * 0.88, shoulder_y)
			draw_colored_polygon(_scratch_spear, spear_fill_col)

			var s_idx: int = _spine_pts.size()
			_spine_pts.resize(s_idx + 2)
			_spine_pts[s_idx] = Vector2(x, tip_y - dir_y * (r * 0.55))
			_spine_pts[s_idx + 1] = Vector2(x, shoulder_y)

	# Pass 3: batched tip outlines, chevrons & dark inner spines
	if _tip_outline_pts.size() >= 2:
		draw_multiline(_tip_outline_pts, Color(1.0, 1.0, 1.0, 0.94), 1.6, true)
	if _chev_pts.size() >= 2:
		draw_multiline_colors(_chev_pts, _chev_cols, 1.6, true)
	if _spine_pts.size() >= 2:
		draw_multiline(_spine_pts, Color(0.08, 0.08, 0.08, 0.88), 2.0, true)
