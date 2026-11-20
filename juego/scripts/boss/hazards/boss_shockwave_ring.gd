class_name BossShockwaveRing
extends Node2D

signal wave_activated(origin: Vector2, mode: int)

enum WaveMode {
	RING = 0,
	TIDAL_WAVE = 1,
}

enum Phase {
	TELEGRAPH = 0,
	ACTIVE = 1,
	FADE_OUT = 2,
}

const FADE_DURATION: float = 0.20
const MIN_TIDAL_GAP: float = 130.0

var is_hazard_active: bool = false
var parryable: bool = true
var hazard_kind: StringName = &"shockwave_ring"

var wave_mode: int = WaveMode.RING
var current_phase: int = Phase.TELEGRAPH
var phase_timer: float = 0.0
var current_radius: float = 24.0
var current_wave_coord: float = 0.0

var _start_radius: float = 24.0
var _end_radius: float = 640.0
var _thickness: float = 26.0
var _warning_time: float = 0.75
var _travel_time: float = 1.25

var _arena_size: Vector2 = BossConstants.ARENA_REF
var _side: StringName = &"left"
var _gap_center: float = 324.0
var _gap_size: float = 148.0
var _start_coord: float = 0.0
var _end_coord: float = 1152.0
var _queued_free: bool = false
var _spoke_pts: PackedVector2Array = PackedVector2Array()
var _chev_pts: PackedVector2Array = PackedVector2Array()
var _rail_pts: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	add_to_group("boss_hazards")


func _ready() -> void:
	if not is_in_group("boss_hazards"):
		add_to_group("boss_hazards")
	queue_redraw()


func _physics_process(delta: float) -> void:
	simulate_physics(delta)


func configure_ring(
	origin: Vector2,
	start_radius: float,
	end_radius: float,
	thickness: float,
	warning_time: float,
	travel_time: float,
	is_parryable: bool = true
) -> void:
	wave_mode = WaveMode.RING
	hazard_kind = &"shockwave_ring"
	global_position = origin
	_start_radius = maxf(start_radius, 4.0)
	_end_radius = maxf(end_radius, _start_radius + 8.0)
	_thickness = maxf(thickness, 6.0)
	_warning_time = maxf(warning_time, 0.001)
	_travel_time = maxf(travel_time, 0.05)
	parryable = is_parryable
	current_radius = _start_radius
	current_phase = Phase.TELEGRAPH
	phase_timer = 0.0
	is_hazard_active = false
	queue_redraw()


func configure_tidal_wave(
	arena_size: Vector2,
	side: StringName,
	thickness: float,
	gap_center: float,
	gap_size: float,
	warning_time: float,
	travel_time: float,
	is_parryable: bool = true
) -> void:
	wave_mode = WaveMode.TIDAL_WAVE
	hazard_kind = &"tidal_wave"
	global_position = Vector2.ZERO
	_arena_size = arena_size
	_side = side
	_thickness = maxf(thickness, 12.0)
	_gap_size = maxf(gap_size, MIN_TIDAL_GAP)
	_warning_time = maxf(warning_time, 0.001)
	_travel_time = maxf(travel_time, 0.05)
	parryable = is_parryable

	var half_t: float = _thickness * 0.5
	var is_horizontal_sweep: bool = (_side == &"left" or _side == &"right")
	var span_len: float = _arena_size.y if is_horizontal_sweep else _arena_size.x
	var margin: float = minf(_gap_size * 0.55, span_len * 0.45)
	_gap_center = clampf(gap_center, margin, span_len - margin)

	match _side:
		&"right":
			_start_coord = _arena_size.x + half_t
			_end_coord = -half_t
		&"top":
			_start_coord = -half_t
			_end_coord = _arena_size.y + half_t
		&"bottom":
			_start_coord = _arena_size.y + half_t
			_end_coord = -half_t
		_:
			_side = &"left"
			_start_coord = -half_t
			_end_coord = _arena_size.x + half_t

	current_wave_coord = _start_coord
	current_phase = Phase.TELEGRAPH
	phase_timer = 0.0
	is_hazard_active = false
	queue_redraw()


func simulate_physics(delta: float, player_node: Node2D = null) -> void:
	if _queued_free:
		return

	phase_timer += delta

	match current_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if phase_timer >= _warning_time:
				current_phase = Phase.ACTIVE
				phase_timer = 0.0
				is_hazard_active = true
				current_radius = _start_radius
				current_wave_coord = _start_coord
				BossConstants.play_sfx(self, &"wall_slam", -6.0)
				wave_activated.emit(_get_emit_origin(), wave_mode)
				_check_player_overlap(player_node)
		Phase.ACTIVE:
			var progress: float = clampf(phase_timer / maxf(_travel_time, 0.001), 0.0, 1.0)
			if wave_mode == WaveMode.RING:
				current_radius = lerpf(_start_radius, _end_radius, progress)
			else:
				current_wave_coord = lerpf(_start_coord, _end_coord, progress)
			_check_player_overlap(player_node)
			if phase_timer >= _travel_time:
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


func _get_emit_origin() -> Vector2:
	if wave_mode == WaveMode.RING:
		return global_position
	match _side:
		&"right":
			return Vector2(_arena_size.x, _gap_center)
		&"top":
			return Vector2(_gap_center, 0.0)
		&"bottom":
			return Vector2(_gap_center, _arena_size.y)
		_:
			return Vector2(0.0, _gap_center)


func _get_tidal_rects(coord: float) -> Array[Rect2]:
	var half_t: float = _thickness * 0.5
	var gap_lo: float = maxf(_gap_center - _gap_size * 0.5, 0.0)
	var gap_hi: float = _gap_center + _gap_size * 0.5
	var rects: Array[Rect2] = []
	if _side == &"left" or _side == &"right":
		if gap_lo > 0.5:
			rects.append(Rect2(coord - half_t, 0.0, _thickness, gap_lo))
		if gap_hi < _arena_size.y - 0.5:
			rects.append(Rect2(coord - half_t, gap_hi, _thickness, _arena_size.y - gap_hi))
	else:
		if gap_lo > 0.5:
			rects.append(Rect2(0.0, coord - half_t, gap_lo, _thickness))
		if gap_hi < _arena_size.x - 0.5:
			rects.append(Rect2(gap_hi, coord - half_t, _arena_size.x - gap_hi, _thickness))
	return rects


func _check_player_overlap(player_node: Node2D = null) -> void:
	if not is_hazard_active:
		return
	var players: Array[Node2D] = BossConstants.collect_players(self, player_node)
	var half_t: float = _thickness * 0.5
	if wave_mode == WaveMode.RING:
		for body: Node2D in players:
			var player_r: float = BossConstants.get_player_hit_radius(body)
			var dist: float = body.global_position.distance_to(global_position)
			if absf(dist - current_radius) <= half_t + player_r:
				BossConstants.apply_player_hit(body, parryable, hazard_kind)
	else:
		var rects: Array[Rect2] = _get_tidal_rects(current_wave_coord)
		for body: Node2D in players:
			var player_r: float = BossConstants.get_player_hit_radius(body)
			var p_pos: Vector2 = body.global_position
			for rect: Rect2 in rects:
				if BossConstants.circle_rect_overlap(p_pos, player_r, rect):
					BossConstants.apply_player_hit(body, parryable, hazard_kind)
					break


func _draw() -> void:
	if wave_mode == WaveMode.RING:
		_draw_ring()
	else:
		_draw_tidal_wave()


func _draw_ring() -> void:
	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(_warning_time, 0.001), 0.0, 1.0)
			var pulse: float = 0.5 + 0.5 * sin(phase_timer * 20.0)
			var preview_r: float = _start_radius + 8.0 * pulse
			BossConstants.draw_dashed_circle(
				self,
				Vector2.ZERO,
				preview_r,
				Color(0.90, 0.90, 0.90, lerpf(0.50, 0.96, progress)),
				2.2,
				28,
				0.58,
				phase_timer * 1.4
			)
			var charge_r: float = lerpf(_start_radius * 2.1 + 34.0, _start_radius, progress)
			draw_arc(Vector2.ZERO, charge_r, 0.0, TAU, 48, Color(0.96, 0.96, 0.96, lerpf(0.45, 0.95, progress)), 2.0, true)
			var expand_hint_r: float = _start_radius + 44.0 * progress
			BossConstants.draw_dashed_circle(
				self,
				Vector2.ZERO,
				expand_hint_r,
				Color(0.76, 0.76, 0.76, lerpf(0.32, 0.62, progress)),
				1.4,
				24,
				0.45,
				-phase_timer * 1.1
			)
			_spoke_pts.resize(16)
			_chev_pts.resize(0)
			for i: int in range(8):
				var a: float = float(i) * TAU / 8.0 + phase_timer * 0.8
				var dir: Vector2 = Vector2.from_angle(a)
				_spoke_pts[i * 2] = dir * _start_radius
				_spoke_pts[i * 2 + 1] = dir * charge_r
				if parryable:
					_chev_pts = BossConstants.append_double_chevron_pts(_chev_pts, dir * (_start_radius + 16.0), dir, 8.0)
			draw_multiline(_spoke_pts, Color(0.86, 0.86, 0.86, lerpf(0.42, 0.88, progress)), 1.4, true)
			if parryable and _chev_pts.size() >= 2:
				draw_multiline(_chev_pts, Color(0.94, 0.94, 0.94, lerpf(0.50, 0.96, progress)), 1.7, true)

		Phase.ACTIVE:
			var half_t: float = _thickness * 0.5
			var segs: int = clampi(int(current_radius * 0.24), 40, 68)
			# Trailing soft monochrome echo ring
			var trail_r: float = maxf(current_radius - _thickness * 0.95, 4.0)
			draw_arc(Vector2.ZERO, trail_r, 0.0, TAU, segs, Color(0.62, 0.62, 0.62, 0.32), maxf(_thickness * 0.35, 3.0), true)
			# Outer soft halo
			draw_arc(Vector2.ZERO, current_radius, 0.0, TAU, segs, Color(0.88, 0.88, 0.88, 0.22), _thickness * 1.38, true)
			# Main crisp white shockwave band
			draw_arc(Vector2.ZERO, current_radius, 0.0, TAU, segs, Color(1.0, 1.0, 1.0, 0.98), _thickness, true)
			# Dark inner contrast groove
			draw_arc(Vector2.ZERO, current_radius, 0.0, TAU, segs, Color(0.10, 0.10, 0.10, 0.82), maxf(_thickness * 0.18, 2.0), true)

			# Double-chevron parryable rim
			if parryable:
				var chev_count: int = clampi(int(current_radius / 26.0), 8, 28)
				var rim_r: float = current_radius + half_t + 6.0
				_chev_pts.resize(0)
				for i: int in range(chev_count):
					var a: float = float(i) * TAU / float(chev_count) + phase_timer * 0.9
					var dir: Vector2 = Vector2.from_angle(a)
					_chev_pts = BossConstants.append_double_chevron_pts(_chev_pts, dir * rim_r, dir, 7.5)
				if _chev_pts.size() >= 2:
					draw_multiline(_chev_pts, Color(1.0, 1.0, 1.0, 0.95), 1.6, true)

		Phase.FADE_OUT:
			var fade_t: float = clampf(phase_timer / maxf(FADE_DURATION, 0.001), 0.0, 1.0)
			var w: float = _thickness * (1.0 - fade_t)
			if w > 0.5:
				draw_arc(Vector2.ZERO, current_radius + fade_t * 14.0, 0.0, TAU, 64, Color(0.82, 0.82, 0.82, (1.0 - fade_t) * 0.75), w, true)


func _draw_tidal_wave() -> void:
	var sweep_dir: Vector2 = _get_tidal_sweep_dir()
	var is_h: bool = (_side == &"left" or _side == &"right")
	var gap_lo: float = maxf(_gap_center - _gap_size * 0.5, 0.0)
	var gap_hi: float = minf(_gap_center + _gap_size * 0.5, _arena_size.y if is_h else _arena_size.x)

	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(_warning_time, 0.001), 0.0, 1.0)
			var warn_depth: float = lerpf(22.0, 48.0, progress)
			var edge_col: Color = Color(0.92, 0.92, 0.92, lerpf(0.50, 0.96, progress))
			var fill_col: Color = Color(0.50, 0.50, 0.50, lerpf(0.18, 0.40, progress))
			var rail_col: Color = Color(0.84, 0.84, 0.84, lerpf(0.48, 0.90, progress))

			var edge_coord: float = 0.0
			if _side == &"right":
				edge_coord = _arena_size.x - warn_depth
			elif _side == &"bottom":
				edge_coord = _arena_size.y - warn_depth

			_rail_pts.resize(0)
			_chev_pts.resize(0)
			if is_h:
				if gap_lo > 1.0:
					var r1: Rect2 = Rect2(edge_coord, 0.0, warn_depth, gap_lo)
					draw_rect(r1, fill_col, true)
					draw_rect(r1, edge_col, false, 2.0)
				if gap_hi < _arena_size.y - 1.0:
					var r2: Rect2 = Rect2(edge_coord, gap_hi, warn_depth, _arena_size.y - gap_hi)
					draw_rect(r2, fill_col, true)
					draw_rect(r2, edge_col, false, 2.0)
				# Safe gap dotted rails across arena
				_rail_pts = BossConstants.append_dashed_line_pts(_rail_pts, Vector2(0.0, gap_lo), Vector2(_arena_size.x, gap_lo), 14.0, 10.0, phase_timer * 60.0)
				_rail_pts = BossConstants.append_dashed_line_pts(_rail_pts, Vector2(0.0, gap_hi), Vector2(_arena_size.x, gap_hi), 14.0, 10.0, phase_timer * 60.0)
				# Directional arrows
				var arrow_x: float = (warn_depth + 16.0) if _side == &"left" else (_arena_size.x - warn_depth - 16.0)
				for y_step: int in range(1, 7):
					var yy: float = _arena_size.y * float(y_step) / 7.0
					if yy > gap_lo - 10.0 and yy < gap_hi + 10.0:
						continue
					_chev_pts = BossConstants.append_double_chevron_pts(_chev_pts, Vector2(arrow_x, yy), sweep_dir, 8.5)
			else:
				if gap_lo > 1.0:
					var r1: Rect2 = Rect2(0.0, edge_coord, gap_lo, warn_depth)
					draw_rect(r1, fill_col, true)
					draw_rect(r1, edge_col, false, 2.0)
				if gap_hi < _arena_size.x - 1.0:
					var r2: Rect2 = Rect2(gap_hi, edge_coord, _arena_size.x - gap_hi, warn_depth)
					draw_rect(r2, fill_col, true)
					draw_rect(r2, edge_col, false, 2.0)
				_rail_pts = BossConstants.append_dashed_line_pts(_rail_pts, Vector2(gap_lo, 0.0), Vector2(gap_lo, _arena_size.y), 14.0, 10.0, phase_timer * 60.0)
				_rail_pts = BossConstants.append_dashed_line_pts(_rail_pts, Vector2(gap_hi, 0.0), Vector2(gap_hi, _arena_size.y), 14.0, 10.0, phase_timer * 60.0)
				var arrow_y: float = (warn_depth + 16.0) if _side == &"top" else (_arena_size.y - warn_depth - 16.0)
				for x_step: int in range(1, 9):
					var xx: float = _arena_size.x * float(x_step) / 9.0
					if xx > gap_lo - 10.0 and xx < gap_hi + 10.0:
						continue
					_chev_pts = BossConstants.append_double_chevron_pts(_chev_pts, Vector2(xx, arrow_y), sweep_dir, 8.5)
			if _rail_pts.size() >= 2:
				draw_multiline(_rail_pts, rail_col, 1.6, true)
			if _chev_pts.size() >= 2:
				draw_multiline(_chev_pts, edge_col, 1.8, true)

		Phase.ACTIVE:
			var rects: Array[Rect2] = _get_tidal_rects(current_wave_coord)
			var half_t: float = _thickness * 0.5
			_chev_pts.resize(0)
			for rect: Rect2 in rects:
				# Trailing monochrome echo
				var trail_rect: Rect2 = Rect2(rect.position - sweep_dir * (_thickness * 0.85), rect.size)
				draw_rect(trail_rect, Color(0.58, 0.58, 0.58, 0.28), true)
				# Main bright wave body
				draw_rect(rect, Color(1.0, 1.0, 1.0, 0.98), true)
				# Dark inner contrast stripe
				var inner_rect: Rect2 = rect.grow(-4.0)
				if inner_rect.size.x > 2.0 and inner_rect.size.y > 2.0:
					draw_rect(inner_rect, Color(0.14, 0.14, 0.14, 0.80), false, 2.0)

				# Double-chevron parryable crest along leading edge
				if parryable:
					if is_h:
						var lead_x: float = current_wave_coord + sweep_dir.x * (half_t + 8.0)
						var yy: float = rect.position.y + 24.0
						while yy < rect.position.y + rect.size.y - 16.0:
							_chev_pts = BossConstants.append_double_chevron_pts(_chev_pts, Vector2(lead_x, yy), sweep_dir, 8.0)
							yy += 46.0
					else:
						var lead_y: float = current_wave_coord + sweep_dir.y * (half_t + 8.0)
						var xx: float = rect.position.x + 24.0
						while xx < rect.position.x + rect.size.x - 16.0:
							_chev_pts = BossConstants.append_double_chevron_pts(_chev_pts, Vector2(xx, lead_y), sweep_dir, 8.0)
							xx += 46.0
			if parryable and _chev_pts.size() >= 2:
				draw_multiline(_chev_pts, Color(1.0, 1.0, 1.0, 0.95), 1.7, true)

		Phase.FADE_OUT:
			var fade_t: float = clampf(phase_timer / maxf(FADE_DURATION, 0.001), 0.0, 1.0)
			var rects: Array[Rect2] = _get_tidal_rects(current_wave_coord)
			for rect: Rect2 in rects:
				draw_rect(rect, Color(0.82, 0.82, 0.82, (1.0 - fade_t) * 0.65), true)


func _get_tidal_sweep_dir() -> Vector2:
	match _side:
		&"right":
			return Vector2.LEFT
		&"top":
			return Vector2.DOWN
		&"bottom":
			return Vector2.UP
		_:
			return Vector2.RIGHT
