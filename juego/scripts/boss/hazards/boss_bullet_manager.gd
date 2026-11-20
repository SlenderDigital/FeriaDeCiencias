class_name BossBulletManager
extends Node2D

const MAX_BULLETS: int = 720
const ARENA_CULL_MARGIN: float = 96.0
const CIRCLE_VERTS: int = 12

var is_hazard_active: bool = false
var parryable: bool = false
var hazard_kind: StringName = &"boss_bullets"
var arena_size: Vector2 = BossConstants.ARENA_REF

var _bullets: Array[Dictionary] = []
var _unit_circle: PackedVector2Array = PackedVector2Array()
var _tail_pts: PackedVector2Array = PackedVector2Array()
var _tail_cols: PackedColorArray = PackedColorArray()
var _needle_line_pts: PackedVector2Array = PackedVector2Array()
var _needle_line_cols: PackedColorArray = PackedColorArray()
var _tri_pts: PackedVector2Array = PackedVector2Array()
var _tri_cols: PackedColorArray = PackedColorArray()
var _tri_indices: PackedInt32Array = PackedInt32Array()
var _tri_v_i: int = 0
var _tri_idx_i: int = 0


func _init() -> void:
	_unit_circle.resize(CIRCLE_VERTS)
	for k: int in range(CIRCLE_VERTS):
		var a: float = float(k) * TAU / float(CIRCLE_VERTS)
		_unit_circle[k] = Vector2(cos(a), sin(a))


func _physics_process(delta: float) -> void:
	simulate_physics(delta, arena_size)


func clear() -> void:
	_bullets.clear()
	is_hazard_active = false
	queue_redraw()


func get_active_count() -> int:
	return _bullets.size()


func spawn_bullet(
	pos: Vector2,
	dir: Vector2,
	speed: float,
	radius: float = BossConstants.BULLET_RADIUS,
	max_life: float = 8.0,
	shape: StringName = &"orb"
) -> void:
	var norm_dir: Vector2 = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	if _bullets.size() >= MAX_BULLETS:
		_bullets.pop_front()
	_bullets.append({
		"pos": pos,
		"prev_pos": pos,
		"vel": norm_dir * speed,
		"radius": maxf(radius, 2.0),
		"age": 0.0,
		"max_life": maxf(max_life, 0.05),
		"spin": norm_dir.angle(),
		"shape": shape,
	})
	is_hazard_active = true
	queue_redraw()


func spawn_ring(
	origin: Vector2,
	count: int,
	speed: float,
	angle_offset: float = 0.0,
	radius: float = BossConstants.BULLET_RADIUS,
	max_life: float = 8.0,
	shape: StringName = &"orb"
) -> void:
	var n: int = maxi(count, 1)
	var step: float = TAU / float(n)
	for i: int in range(n):
		var angle: float = angle_offset + step * float(i)
		spawn_bullet(origin, Vector2.from_angle(angle), speed, radius, max_life, shape)


func spawn_fan(
	origin: Vector2,
	aim_dir: Vector2,
	count: int,
	step_angle: float,
	speed: float,
	radius: float = BossConstants.BULLET_RADIUS,
	max_life: float = 8.0,
	shape: StringName = &"orb"
) -> void:
	var n: int = maxi(count, 1)
	var base_angle: float = aim_dir.angle() if aim_dir.length_squared() > 0.0001 else 0.0
	var half_span: float = float(n - 1) * 0.5
	for i: int in range(n):
		var angle: float = base_angle + (float(i) - half_span) * step_angle
		spawn_bullet(origin, Vector2.from_angle(angle), speed, radius, max_life, shape)


func simulate_physics(
	delta: float,
	sim_arena_size: Vector2 = BossConstants.ARENA_REF,
	player_node: Node2D = null
) -> void:
	if sim_arena_size.x > 0.0 and sim_arena_size.y > 0.0:
		arena_size = sim_arena_size

	if _bullets.is_empty():
		is_hazard_active = false
		return

	var players: Array[Node2D] = BossConstants.collect_players(self, player_node)
	var min_x: float = -ARENA_CULL_MARGIN
	var min_y: float = -ARENA_CULL_MARGIN
	var max_x: float = arena_size.x + ARENA_CULL_MARGIN
	var max_y: float = arena_size.y + ARENA_CULL_MARGIN

	var i: int = _bullets.size() - 1
	while i >= 0:
		var b: Dictionary = _bullets[i]
		var prev_pos: Vector2 = b["pos"]
		var vel: Vector2 = b["vel"]
		var pos: Vector2 = prev_pos + vel * delta
		var age: float = float(b["age"]) + delta
		var max_life: float = float(b["max_life"])

		if age >= max_life or pos.x < min_x or pos.x > max_x or pos.y < min_y or pos.y > max_y:
			_bullets.remove_at(i)
			i -= 1
			continue

		b["prev_pos"] = prev_pos
		b["pos"] = pos
		b["age"] = age
		b["spin"] = float(b["spin"]) + delta * 5.5

		var hit_any: bool = false
		var r: float = float(b["radius"])
		for body: Node2D in players:
			var player_r: float = BossConstants.get_player_hit_radius(body)
			var p_pos: Vector2 = body.global_position
			var hit_r: float = r + player_r
			if (
				p_pos.x < minf(prev_pos.x, pos.x) - hit_r
				or p_pos.x > maxf(prev_pos.x, pos.x) + hit_r
				or p_pos.y < minf(prev_pos.y, pos.y) - hit_r
				or p_pos.y > maxf(prev_pos.y, pos.y) + hit_r
			):
				continue
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p_pos, prev_pos, pos)
			if closest.distance_squared_to(p_pos) <= hit_r * hit_r:
				BossConstants.apply_player_hit(body, parryable, hazard_kind)
				hit_any = true
				break

		if _bullets.is_empty():
			break
		if hit_any and i < _bullets.size():
			_bullets.remove_at(i)
		i = mini(i - 1, _bullets.size() - 1)

	is_hazard_active = not _bullets.is_empty()
	queue_redraw()


func _append_tri_quad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, col: Color) -> void:
	var b: int = _tri_v_i
	var idx_i: int = _tri_idx_i
	_tri_pts[b] = p0
	_tri_pts[b + 1] = p1
	_tri_pts[b + 2] = p2
	_tri_pts[b + 3] = p3
	_tri_cols[b] = col
	_tri_cols[b + 1] = col
	_tri_cols[b + 2] = col
	_tri_cols[b + 3] = col
	_tri_indices[idx_i] = b
	_tri_indices[idx_i + 1] = b + 1
	_tri_indices[idx_i + 2] = b + 2
	_tri_indices[idx_i + 3] = b
	_tri_indices[idx_i + 4] = b + 2
	_tri_indices[idx_i + 5] = b + 3
	_tri_v_i = b + 4
	_tri_idx_i = idx_i + 6


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


func _append_tri_diamond(center: Vector2, spin: float, rad: float, col: Color) -> void:
	var cs: float = cos(spin)
	var sn: float = sin(spin)
	_append_tri_quad(
		center + Vector2(cs, sn) * rad,
		center + Vector2(-sn, cs) * rad,
		center + Vector2(-cs, -sn) * rad,
		center + Vector2(sn, -cs) * rad,
		col
	)


func _append_tri_star(center: Vector2, spin: float, outer_rad: float, inner_rad: float, col: Color) -> void:
	var v: Vector2 = Vector2.from_angle(spin)
	const SQRT1_2: float = 0.7071067811865475
	var base: int = _tri_v_i
	var idx_i: int = _tri_idx_i
	_tri_pts[base] = center
	_tri_cols[base] = col
	for k: int in range(8):
		var rr: float = outer_rad if k % 2 == 0 else inner_rad
		_tri_pts[base + 1 + k] = center + v * rr
		_tri_cols[base + 1 + k] = col
		v = Vector2(v.x * SQRT1_2 - v.y * SQRT1_2, v.x * SQRT1_2 + v.y * SQRT1_2)
		_tri_indices[idx_i] = base
		_tri_indices[idx_i + 1] = base + 1 + k
		_tri_indices[idx_i + 2] = base + 1 + ((k + 1) % 8)
		idx_i += 3
	_tri_v_i = base + 9
	_tri_idx_i = idx_i


func _draw() -> void:
	var n_bullets: int = _bullets.size()
	if n_bullets == 0:
		return

	var local_origin: Vector2 = to_local(Vector2.ZERO)
	_tail_pts.resize(n_bullets * 2)
	_tail_cols.resize(n_bullets)
	_needle_line_pts.resize(n_bullets * 2)
	_needle_line_cols.resize(n_bullets)
	_tri_pts.resize(n_bullets * 39)
	_tri_cols.resize(n_bullets * 39)
	_tri_indices.resize(n_bullets * 108)
	_tri_v_i = 0
	_tri_idx_i = 0

	# Pass 1: collect and emit all speed tails in 1 draw_multiline_colors() call
	for i: int in range(n_bullets):
		var b: Dictionary = _bullets[i]
		var pos: Vector2 = Vector2(b["pos"]) + local_origin
		var vel: Vector2 = b["vel"]
		var r: float = float(b["radius"])
		var life_remain: float = maxf(float(b["max_life"]) - float(b["age"]), 0.0)
		var alpha: float = clampf(life_remain / 0.22, 0.0, 1.0)
		var vel_len_sq: float = vel.length_squared()
		var vel_len: float = sqrt(vel_len_sq) if vel_len_sq > 0.001 else 0.0
		var dir: Vector2 = (vel / vel_len) if vel_len > 0.031 else Vector2.RIGHT
		var tail_len: float = clampf(vel_len * 0.042, r * 1.4, r * 3.8)
		_tail_pts[i * 2] = pos
		_tail_pts[i * 2 + 1] = pos - dir * tail_len
		_tail_cols[i] = Color(0.52, 0.52, 0.52, 0.42 * alpha)

	if _tail_pts.size() >= 2:
		draw_multiline_colors(_tail_pts, _tail_cols, 2.8, true)

	# Pass 2a: pitch-black outer isolation rim for all bullets into _tri_* buffers
	for i: int in range(n_bullets):
		var b: Dictionary = _bullets[i]
		var pos: Vector2 = Vector2(b["pos"]) + local_origin
		var r: float = float(b["radius"])
		var life_remain: float = maxf(float(b["max_life"]) - float(b["age"]), 0.0)
		var alpha: float = clampf(life_remain / 0.22, 0.0, 1.0)
		var spin: float = float(b["spin"])
		var shape: StringName = b["shape"]
		var rim_col: Color = Color(0.02, 0.02, 0.02, 0.94 * alpha)

		if shape == &"needle":
			var vel: Vector2 = b["vel"]
			var dir: Vector2 = vel.normalized() if vel.length_squared() > 0.001 else Vector2.RIGHT
			var side: Vector2 = Vector2(-dir.y, dir.x)
			_append_tri_quad(
				pos + dir * (r * 1.85 + 2.4),
				pos + side * (r * 0.72 + 2.4),
				pos - dir * (r * 1.25 + 2.4),
				pos - side * (r * 0.72 + 2.4),
				rim_col
			)
		elif shape == &"diamond":
			_append_tri_diamond(pos, spin, r * 1.56, rim_col)
		elif shape == &"spike":
			_append_tri_star(pos, spin, r * 1.62, r * 0.82, rim_col)
		else:
			_append_tri_circle(pos, r + 2.4, rim_col)

	# Pass 2b: pure-white bullet bodies into _tri_* buffers (and accumulate needle centerlines)
	var needle_pt_i: int = 0
	var needle_col_i: int = 0
	for i: int in range(n_bullets):
		var b: Dictionary = _bullets[i]
		var pos: Vector2 = Vector2(b["pos"]) + local_origin
		var vel: Vector2 = b["vel"]
		var r: float = float(b["radius"])
		var life_remain: float = maxf(float(b["max_life"]) - float(b["age"]), 0.0)
		var alpha: float = clampf(life_remain / 0.22, 0.0, 1.0)
		var spin: float = float(b["spin"])
		var shape: StringName = b["shape"]
		var white_col: Color = Color(1.0, 1.0, 1.0, alpha)

		if shape == &"needle":
			var dir: Vector2 = vel.normalized() if vel.length_squared() > 0.001 else Vector2.RIGHT
			var side: Vector2 = Vector2(-dir.y, dir.x)
			_append_tri_quad(
				pos + dir * (r * 1.85),
				pos + side * (r * 0.72),
				pos - dir * (r * 1.25),
				pos - side * (r * 0.72),
				white_col
			)
			_needle_line_pts[needle_pt_i] = pos - dir * (r * 0.55)
			_needle_line_pts[needle_pt_i + 1] = pos + dir * (r * 0.85)
			_needle_line_cols[needle_col_i] = Color(0.08, 0.08, 0.08, alpha)
			needle_pt_i += 2
			needle_col_i += 1
		elif shape == &"diamond":
			_append_tri_diamond(pos, spin, r * 1.25, white_col)
		elif shape == &"spike":
			_append_tri_star(pos, spin, r * 1.38, r * 0.58, white_col)
		else:
			_append_tri_circle(pos, r, white_col)

	# Pass 3: all inner dark cores appended after outer bodies into the same _tri_* buffers
	for i: int in range(n_bullets):
		var b: Dictionary = _bullets[i]
		var shape: StringName = b["shape"]
		if shape == &"needle":
			continue
		var pos: Vector2 = Vector2(b["pos"]) + local_origin
		var r: float = float(b["radius"])
		var life_remain: float = maxf(float(b["max_life"]) - float(b["age"]), 0.0)
		var alpha: float = clampf(life_remain / 0.22, 0.0, 1.0)
		var dark_col: Color = Color(0.06, 0.06, 0.06, alpha)

		if shape == &"diamond":
			_append_tri_diamond(pos, float(b["spin"]), r * 0.52, dark_col)
		elif shape == &"spike":
			_append_tri_circle(pos, r * 0.36, dark_col)
		else:
			_append_tri_circle(pos, r * 0.44, dark_col)

	if _tri_idx_i >= 3:
		_tri_pts.resize(_tri_v_i)
		_tri_cols.resize(_tri_v_i)
		_tri_indices.resize(_tri_idx_i)
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _tri_indices, _tri_pts, _tri_cols)

	if needle_pt_i >= 2:
		_needle_line_pts.resize(needle_pt_i)
		_needle_line_cols.resize(needle_col_i)
		draw_multiline_colors(_needle_line_pts, _needle_line_cols, 1.8, true)
