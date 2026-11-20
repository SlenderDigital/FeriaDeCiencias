class_name BossHexGrid
extends Node2D

enum TileState {
	IDLE = 0,
	DELAYED = 1,
	TELEGRAPH = 2,
	ACTIVE = 3,
	FADE = 4,
}

const HEX_RADIUS: float = BossConstants.HEX_RADIUS
const TILE_FADE_DURATION: float = 0.18
const MIN_CORRIDOR_HALF_WIDTH: float = 75.0

var is_hazard_active: bool = false
var parryable: bool = false
var hazard_kind: StringName = &"hex_grid"
var arena_size: Vector2 = BossConstants.ARENA_REF

var _cells: Array[Dictionary] = []
var _busy_indices: Array[int] = []
var _active_tile_count: int = 0
var _max_col: int = 0
var _max_row: int = 0
var _unit_hex: PackedVector2Array = PackedVector2Array()
var _scratch_hex: PackedVector2Array = PackedVector2Array()
var _outer_rail_pts: PackedVector2Array = PackedVector2Array()
var _outer_rail_cols: PackedColorArray = PackedColorArray()
var _inner_rim_pts: PackedVector2Array = PackedVector2Array()
var _inner_rim_cols: PackedColorArray = PackedColorArray()
var _active_seam_pts: PackedVector2Array = PackedVector2Array()
var _active_seam_cols: PackedColorArray = PackedColorArray()
var _tri_pts: PackedVector2Array = PackedVector2Array()
var _tri_cols: PackedColorArray = PackedColorArray()
var _tri_indices: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	_scratch_hex.resize(6)
	_build_unit_hex()
	_rebuild_lattice()


func _ready() -> void:
	if _cells.is_empty():
		_rebuild_lattice()
	queue_redraw()


func _physics_process(delta: float) -> void:
	simulate_physics(delta)


func set_arena_size(sz: Vector2) -> void:
	if sz.x <= 0.0 or sz.y <= 0.0:
		return
	if arena_size.is_equal_approx(sz) and not _cells.is_empty():
		return
	arena_size = sz
	_rebuild_lattice()
	queue_redraw()


func clear() -> void:
	for idx: int in _busy_indices:
		var c: Dictionary = _cells[idx]
		c["state"] = TileState.IDLE
		c["timer"] = 0.0
		c["delay"] = 0.0
	_busy_indices.clear()
	_active_tile_count = 0
	is_hazard_active = false
	queue_redraw()


func get_active_tile_count() -> int:
	return _active_tile_count


func get_queued_tile_count() -> int:
	return _busy_indices.size()


func get_total_tile_count() -> int:
	return _cells.size()


func trigger_pattern(
	pattern: int,
	warning_time: float,
	active_time: float,
	cascade_step: float = 0.06,
	params: Dictionary = {}
) -> void:
	if _cells.is_empty():
		_rebuild_lattice()

	var warn_t: float = maxf(warning_time, 0.05)
	var act_t: float = maxf(active_time, 0.05)
	var step_t: float = maxf(cascade_step, 0.0)
	var reverse: bool = bool(params.get("reverse", false))
	var skip_center: Vector2 = params.get("skip_center", Vector2(-99999.0, -99999.0))
	var skip_radius: float = float(params.get("skip_radius", 0.0))
	var skip_r_sq: float = skip_radius * skip_radius
	var col_step: float = 1.5 * HEX_RADIUS
	var row_step: float = sqrt(3.0) * HEX_RADIUS

	match pattern:
		BossConstants.HexPattern.WAVE_LR:
			for idx: int in range(_cells.size()):
				var c: Dictionary = _cells[idx]
				if _should_skip(c["pos"], skip_center, skip_r_sq):
					continue
				var col: int = int(c["col"])
				var order: int = (_max_col - col) if reverse else col
				_schedule_cell(idx, float(order) * step_t, warn_t, act_t)

		BossConstants.HexPattern.WAVE_TB:
			for idx: int in range(_cells.size()):
				var c: Dictionary = _cells[idx]
				if _should_skip(c["pos"], skip_center, skip_r_sq):
					continue
				var row: int = int(c["row"])
				var order: int = (_max_row - row) if reverse else row
				_schedule_cell(idx, float(order) * step_t, warn_t, act_t)

		BossConstants.HexPattern.CHECKER_A, BossConstants.HexPattern.CHECKER_B:
			var parity: int = 0 if pattern == BossConstants.HexPattern.CHECKER_A else 1
			var ripple: bool = bool(params.get("ripple", false))
			for idx: int in range(_cells.size()):
				var c: Dictionary = _cells[idx]
				if _should_skip(c["pos"], skip_center, skip_r_sq):
					continue
				var col: int = int(c["col"])
				var row: int = int(c["row"])
				if (col + row) % 2 == parity:
					var d: float = float(col + row) * step_t * 0.25 if ripple else 0.0
					_schedule_cell(idx, d, warn_t, act_t)

		BossConstants.HexPattern.BORDER_RING:
			var depth: int = maxi(int(params.get("depth", 1)), 1)
			var margin_x: float = HEX_RADIUS * (1.2 + 1.45 * float(depth - 1))
			var margin_y: float = HEX_RADIUS * (1.2 + 1.55 * float(depth - 1))
			var center: Vector2 = arena_size * 0.5
			for idx: int in range(_cells.size()):
				var c: Dictionary = _cells[idx]
				var pos: Vector2 = c["pos"]
				if _should_skip(pos, skip_center, skip_r_sq):
					continue
				var near_edge: bool = (
					pos.x <= margin_x
					or pos.x >= arena_size.x - margin_x
					or pos.y <= margin_y
					or pos.y >= arena_size.y - margin_y
				)
				if near_edge:
					var angle: float = fposmod((pos - center).angle(), TAU)
					var d: float = (angle / TAU) * step_t * 6.0
					_schedule_cell(idx, d, warn_t, act_t)

		BossConstants.HexPattern.CORRIDOR_H:
			var safe_center: float = float(params.get("safe_center", arena_size.y * 0.5))
			var safe_half: float = maxf(float(params.get("safe_half_width", 96.0)), MIN_CORRIDOR_HALF_WIDTH)
			safe_center = clampf(safe_center, safe_half + 16.0, arena_size.y - safe_half - 16.0)
			for idx: int in range(_cells.size()):
				var c: Dictionary = _cells[idx]
				var pos: Vector2 = c["pos"]
				if _should_skip(pos, skip_center, skip_r_sq):
					continue
				var dy: float = absf(pos.y - safe_center)
				if dy >= safe_half:
					var d: float = maxf((dy - safe_half) / row_step, 0.0) * step_t
					_schedule_cell(idx, d, warn_t, act_t)

		BossConstants.HexPattern.CORRIDOR_V:
			var safe_center: float = float(params.get("safe_center", arena_size.x * 0.5))
			var safe_half: float = maxf(float(params.get("safe_half_width", 96.0)), MIN_CORRIDOR_HALF_WIDTH)
			safe_center = clampf(safe_center, safe_half + 16.0, arena_size.x - safe_half - 16.0)
			for idx: int in range(_cells.size()):
				var c: Dictionary = _cells[idx]
				var pos: Vector2 = c["pos"]
				if _should_skip(pos, skip_center, skip_r_sq):
					continue
				var dx: float = absf(pos.x - safe_center)
				if dx >= safe_half:
					var d: float = maxf((dx - safe_half) / col_step, 0.0) * step_t
					_schedule_cell(idx, d, warn_t, act_t)

		BossConstants.HexPattern.SPIRAL:
			var origin: Vector2 = params.get("origin", arena_size * 0.5)
			var inward: bool = bool(params.get("inward", false))
			var max_dist: float = maxf(arena_size.length() * 0.55, 1.0)
			var ring_span: float = HEX_RADIUS * 1.85
			for idx: int in range(_cells.size()):
				var c: Dictionary = _cells[idx]
				var pos: Vector2 = c["pos"]
				if _should_skip(pos, skip_center, skip_r_sq):
					continue
				var rel: Vector2 = pos - origin
				var dist: float = rel.length()
				var angle_norm: float = fposmod(rel.angle(), TAU) / TAU
				var ring_f: float = dist / ring_span
				if inward:
					ring_f = maxf((max_dist - dist) / ring_span, 0.0)
				var d: float = (ring_f + angle_norm) * step_t * 2.2
				_schedule_cell(idx, d, warn_t, act_t)

	queue_redraw()


func simulate_physics(delta: float, player_node: Node2D = null) -> void:
	if _busy_indices.is_empty():
		_active_tile_count = 0
		is_hazard_active = false
		return

	var active_count: int = 0
	var any_visible_or_changed: bool = false
	var i: int = _busy_indices.size() - 1
	while i >= 0:
		var idx: int = _busy_indices[i]
		var c: Dictionary = _cells[idx]
		var state: int = int(c["state"])
		var prev_state: int = state
		var rem_dt: float = delta

		if state == TileState.DELAYED:
			var delay_left: float = float(c["delay"]) - rem_dt
			if delay_left <= 0.0:
				c["delay"] = 0.0
				state = TileState.TELEGRAPH
				c["state"] = state
				c["timer"] = 0.0
				rem_dt = -delay_left
			else:
				c["delay"] = delay_left
				rem_dt = 0.0

		if state == TileState.TELEGRAPH and rem_dt > 0.0:
			var t: float = float(c["timer"]) + rem_dt
			var warn_t: float = float(c["warning_time"])
			if t >= warn_t:
				state = TileState.ACTIVE
				c["state"] = state
				c["timer"] = 0.0
				rem_dt = t - warn_t
			else:
				c["timer"] = t
				rem_dt = 0.0

		if state == TileState.ACTIVE:
			var t: float = float(c["timer"]) + rem_dt
			var act_t: float = float(c["active_time"])
			if t >= act_t:
				state = TileState.FADE
				c["state"] = state
				c["timer"] = 0.0
				rem_dt = t - act_t
			else:
				c["timer"] = t
				rem_dt = 0.0
				active_count += 1

		if state == TileState.FADE and rem_dt > 0.0:
			var t: float = float(c["timer"]) + rem_dt
			if t >= TILE_FADE_DURATION:
				state = TileState.IDLE
				c["state"] = state
				c["timer"] = 0.0
				_busy_indices.remove_at(i)
			else:
				c["timer"] = t
		elif state == TileState.IDLE:
			_busy_indices.remove_at(i)

		if state != TileState.DELAYED or state != prev_state:
			any_visible_or_changed = true
		i -= 1

	_active_tile_count = active_count
	is_hazard_active = active_count > 0

	if is_hazard_active:
		_check_player_overlap(player_node)

	if any_visible_or_changed:
		queue_redraw()


func _check_player_overlap(player_node: Node2D = null) -> void:
	var players: Array[Node2D] = BossConstants.collect_players(self, player_node)
	if players.is_empty():
		return
	var effective_r: float = HEX_RADIUS * 0.92
	for body: Node2D in players:
		var player_r: float = BossConstants.get_player_hit_radius(body)
		var p_pos: Vector2 = body.global_position
		for idx: int in _busy_indices:
			var c: Dictionary = _cells[idx]
			if int(c["state"]) != TileState.ACTIVE:
				continue
			var local_p: Vector2 = p_pos - Vector2(c["pos"])
			if BossConstants.circle_flat_hex_overlap(local_p, effective_r, player_r):
				BossConstants.apply_player_hit(body, parryable, hazard_kind)
				break


func _schedule_cell(idx: int, delay: float, warn_t: float, act_t: float) -> void:
	var c: Dictionary = _cells[idx]
	var was_idle: bool = (int(c["state"]) == TileState.IDLE)
	c["warning_time"] = warn_t
	c["active_time"] = act_t
	c["timer"] = 0.0
	if delay > 0.0001:
		c["delay"] = delay
		c["state"] = TileState.DELAYED
	else:
		c["delay"] = 0.0
		c["state"] = TileState.TELEGRAPH
	if was_idle:
		_busy_indices.append(idx)


func _should_skip(pos: Vector2, skip_center: Vector2, skip_r_sq: float) -> bool:
	return skip_r_sq > 0.0 and pos.distance_squared_to(skip_center) < skip_r_sq


func _build_unit_hex() -> void:
	_unit_hex.resize(6)
	for k: int in range(6):
		var a: float = float(k) * PI / 3.0
		_unit_hex[k] = Vector2(cos(a), sin(a))


func _rebuild_lattice() -> void:
	_cells.clear()
	_busy_indices.clear()
	_active_tile_count = 0
	is_hazard_active = false
	_max_col = 0
	_max_row = 0

	var col_step: float = 1.5 * HEX_RADIUS
	var row_step: float = sqrt(3.0) * HEX_RADIUS
	var outer_r: float = HEX_RADIUS * 0.94
	var cols: int = int(ceil((arena_size.x + HEX_RADIUS) / col_step)) + 1
	var rows: int = int(ceil((arena_size.y + HEX_RADIUS) / row_step)) + 1

	for col: int in range(cols):
		var x: float = HEX_RADIUS * 0.5 + float(col) * col_step
		var y_offset: float = row_step * 0.5 if (col % 2 == 1) else 0.0
		for row: int in range(rows):
			var y: float = HEX_RADIUS * 0.4 + float(row) * row_step + y_offset
			if x < -HEX_RADIUS * 0.6 or x > arena_size.x + HEX_RADIUS * 0.6:
				continue
			if y < -HEX_RADIUS * 0.6 or y > arena_size.y + HEX_RADIUS * 0.6:
				continue
			var cell_pos: Vector2 = Vector2(x, y)
			var outer_verts: PackedVector2Array = PackedVector2Array()
			outer_verts.resize(6)
			for k: int in range(6):
				outer_verts[k] = cell_pos + _unit_hex[k] * outer_r
			var outer_edges: PackedVector2Array = PackedVector2Array()
			outer_edges.resize(12)
			for k: int in range(6):
				outer_edges[k * 2] = outer_verts[k]
				outer_edges[k * 2 + 1] = outer_verts[(k + 1) % 6]
			_cells.append({
				"col": col,
				"row": row,
				"pos": cell_pos,
				"outer_verts": outer_verts,
				"outer_edges": outer_edges,
				"state": TileState.IDLE,
				"delay": 0.0,
				"timer": 0.0,
				"warning_time": 0.8,
				"active_time": 0.4,
			})
			_max_col = maxi(_max_col, col)
			_max_row = maxi(_max_row, row)


func _make_hex_pts(center: Vector2, radius: float, closed: bool) -> PackedVector2Array:
	var count: int = 7 if closed else 6
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(count)
	for k: int in range(6):
		pts[k] = center + _unit_hex[k] * radius
	if closed:
		pts[6] = pts[0]
	return pts


func _write_hex_meta(b: int, idx_i: int, col: Color) -> void:
	for k: int in range(6):
		_tri_cols[b + k] = col
	_tri_indices[idx_i] = b
	_tri_indices[idx_i + 1] = b + 1
	_tri_indices[idx_i + 2] = b + 2
	_tri_indices[idx_i + 3] = b
	_tri_indices[idx_i + 4] = b + 2
	_tri_indices[idx_i + 5] = b + 3
	_tri_indices[idx_i + 6] = b
	_tri_indices[idx_i + 7] = b + 3
	_tri_indices[idx_i + 8] = b + 4
	_tri_indices[idx_i + 9] = b
	_tri_indices[idx_i + 10] = b + 4
	_tri_indices[idx_i + 11] = b + 5


func _draw() -> void:
	if _busy_indices.is_empty():
		return

	var local_origin: Vector2 = to_local(Vector2.ZERO)
	var has_offset: bool = not local_origin.is_zero_approx()
	var outer_r: float = HEX_RADIUS * 0.94

	var n_busy: int = _busy_indices.size()
	_outer_rail_pts.resize(n_busy * 12)
	_outer_rail_cols.resize(n_busy * 6)
	_inner_rim_pts.resize(n_busy * 12)
	_inner_rim_cols.resize(n_busy * 6)
	_active_seam_pts.resize(n_busy * 12)
	_active_seam_cols.resize(n_busy * 6)
	_tri_pts.resize(n_busy * 6)
	_tri_cols.resize(n_busy * 6)
	_tri_indices.resize(n_busy * 12)

	var outer_pt_i: int = 0
	var outer_col_i: int = 0
	var inner_pt_i: int = 0
	var inner_col_i: int = 0
	var seam_pt_i: int = 0
	var seam_col_i: int = 0
	var tri_v_i: int = 0
	var tri_idx_i: int = 0

	var active_fill_col: Color = Color(0.84, 0.84, 0.84, 0.96)
	var active_seam_col: Color = Color(0.04, 0.04, 0.04, 0.95)

	# Pass 1: batch all hex polygon fills into triangle arrays while packing outline segments for Pass 2
	for idx: int in _busy_indices:
		var c: Dictionary = _cells[idx]
		var state: int = int(c["state"])
		if state == TileState.IDLE or state == TileState.DELAYED:
			continue
		var pos: Vector2 = Vector2(c["pos"]) + local_origin
		var outer_edges: PackedVector2Array = c["outer_edges"]

		if state == TileState.TELEGRAPH:
			var warn_t: float = maxf(float(c["warning_time"]), 0.001)
			var progress: float = clampf(float(c["timer"]) / warn_t, 0.0, 1.0)

			var inner_r: float = outer_r * lerpf(0.22, 0.94, ease(progress, 0.72))
			for k: int in range(6):
				var pt: Vector2 = pos + _unit_hex[k] * inner_r
				_scratch_hex[k] = pt
				_tri_pts[tri_v_i + k] = pt
			var fill_g: float = lerpf(0.16, 0.38, progress)
			_write_hex_meta(tri_v_i, tri_idx_i, Color(fill_g, fill_g, fill_g, lerpf(0.14, 0.34, progress)))
			tri_v_i += 6
			tri_idx_i += 12

			var out_col: Color = Color(0.42, 0.42, 0.42, lerpf(0.26, 0.56, progress))
			var in_col: Color = Color(0.68, 0.68, 0.68, lerpf(0.34, 0.72, progress))
			for k: int in range(6):
				var k2: int = k * 2
				if has_offset:
					_outer_rail_pts[outer_pt_i] = outer_edges[k2] + local_origin
					_outer_rail_pts[outer_pt_i + 1] = outer_edges[k2 + 1] + local_origin
				else:
					_outer_rail_pts[outer_pt_i] = outer_edges[k2]
					_outer_rail_pts[outer_pt_i + 1] = outer_edges[k2 + 1]
				_outer_rail_cols[outer_col_i] = out_col
				outer_pt_i += 2
				outer_col_i += 1

				_inner_rim_pts[inner_pt_i] = _scratch_hex[k]
				_inner_rim_pts[inner_pt_i + 1] = _scratch_hex[(k + 1) % 6]
				_inner_rim_cols[inner_col_i] = in_col
				inner_pt_i += 2
				inner_col_i += 1

		elif state == TileState.ACTIVE:
			var outer_verts: PackedVector2Array = c["outer_verts"]
			if has_offset:
				for k: int in range(6):
					_tri_pts[tri_v_i + k] = outer_verts[k] + local_origin
			else:
				for k: int in range(6):
					_tri_pts[tri_v_i + k] = outer_verts[k]
			_write_hex_meta(tri_v_i, tri_idx_i, active_fill_col)
			tri_v_i += 6
			tri_idx_i += 12

			for k: int in range(6):
				var k2: int = k * 2
				if has_offset:
					_active_seam_pts[seam_pt_i] = outer_edges[k2] + local_origin
					_active_seam_pts[seam_pt_i + 1] = outer_edges[k2 + 1] + local_origin
				else:
					_active_seam_pts[seam_pt_i] = outer_edges[k2]
					_active_seam_pts[seam_pt_i + 1] = outer_edges[k2 + 1]
				_active_seam_cols[seam_col_i] = active_seam_col
				seam_pt_i += 2
				seam_col_i += 1

		elif state == TileState.FADE:
			var fade_t: float = clampf(float(c["timer"]) / maxf(TILE_FADE_DURATION, 0.001), 0.0, 1.0)
			var alpha: float = pow(1.0 - fade_t, 1.5) * 0.65
			var shrink_r: float = outer_r * lerpf(1.0, 0.72, fade_t)
			for k: int in range(6):
				_tri_pts[tri_v_i + k] = pos + _unit_hex[k] * shrink_r
			_write_hex_meta(tri_v_i, tri_idx_i, Color(0.48, 0.48, 0.48, alpha))
			tri_v_i += 6
			tri_idx_i += 12

	if tri_idx_i >= 3:
		_tri_pts.resize(tri_v_i)
		_tri_cols.resize(tri_v_i)
		_tri_indices.resize(tri_idx_i)
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _tri_indices, _tri_pts, _tri_cols)

	# Pass 2: batched outline multilines (max 3 draw calls total, antialiased=false for zero AA-edge triangle bloat)
	if outer_pt_i >= 2:
		_outer_rail_pts.resize(outer_pt_i)
		_outer_rail_cols.resize(outer_col_i)
		draw_multiline_colors(_outer_rail_pts, _outer_rail_cols, 1.4, false)
	if inner_pt_i >= 2:
		_inner_rim_pts.resize(inner_pt_i)
		_inner_rim_cols.resize(inner_col_i)
		draw_multiline_colors(_inner_rim_pts, _inner_rim_cols, 1.3, false)
	if seam_pt_i >= 2:
		_active_seam_pts.resize(seam_pt_i)
		_active_seam_cols.resize(seam_col_i)
		draw_multiline_colors(_active_seam_pts, _active_seam_cols, 2.4, false)
