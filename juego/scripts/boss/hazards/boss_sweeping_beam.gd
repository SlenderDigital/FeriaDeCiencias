class_name BossSweepingBeam
extends Node2D

signal beam_activated(origin: Vector2, beam_count: int)

enum Phase {
	TELEGRAPH = 0,
	ACTIVE = 1,
	FADE_OUT = 2,
}

const FADE_DURATION: float = 0.20

var is_hazard_active: bool = false
var parryable: bool = false
var hazard_kind: StringName = &"sweeping_beam"

var current_phase: int = Phase.TELEGRAPH
var phase_timer: float = 0.0
var current_angle: float = 0.0
var beam_count: int = 1
var beam_width: float = BossConstants.BEAM_WIDTH
var beam_length: float = 2600.0

var _warning_time: float = 0.9375
var _active_time: float = 0.45
var _angular_speed: float = 0.0
var _sweep_velocity: Vector2 = Vector2.ZERO
var _reverse_at_active_time: float = -1.0
var _reversed: bool = false
var _follow_node: Node2D = null
var _queued_free: bool = false
var _scratch_quad: PackedVector2Array = PackedVector2Array()
var _rail_pts: PackedVector2Array = PackedVector2Array()
var _filament_pts: PackedVector2Array = PackedVector2Array()
var _tick_pts: PackedVector2Array = PackedVector2Array()
var _chev_pts: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_scratch_quad.resize(4)
	add_to_group("boss_hazards")


func _ready() -> void:
	if not is_in_group("boss_hazards"):
		add_to_group("boss_hazards")
	queue_redraw()


func _physics_process(delta: float) -> void:
	simulate_physics(delta)


func configure(
	origin: Vector2,
	start_angle: float,
	p_beam_count: int = 1,
	width: float = 24.0,
	warning_time: float = 0.9375,
	active_time: float = 0.45,
	angular_speed: float = 0.0,
	sweep_velocity: Vector2 = Vector2.ZERO,
	reverse_at_active_time: float = -1.0,
	follow_node: Node2D = null,
	length: float = 2600.0,
	is_parryable: bool = false
) -> void:
	global_position = origin
	current_angle = start_angle
	beam_count = maxi(p_beam_count, 1)
	beam_width = maxf(width, 4.0)
	_warning_time = maxf(warning_time, 0.001)
	_active_time = maxf(active_time, 0.01)
	_angular_speed = angular_speed
	_sweep_velocity = sweep_velocity
	_reverse_at_active_time = reverse_at_active_time
	_reversed = false
	_follow_node = follow_node
	beam_length = maxf(length, 64.0)
	parryable = is_parryable
	current_phase = Phase.TELEGRAPH
	phase_timer = 0.0
	is_hazard_active = false
	queue_redraw()


func get_spoke_angle(spoke_idx: int) -> float:
	# Full through-lines spaced evenly across PI:
	# beam_count=1 -> 1 full through-beam (180 deg)
	# beam_count=2 -> 4-way cross (+ / X, 90 deg spacing)
	# beam_count=3 -> 6-beam wheel (60 deg spacing)
	return current_angle + PI * float(spoke_idx) / float(beam_count)


func simulate_physics(delta: float, player_node: Node2D = null) -> void:
	if _queued_free:
		return

	if _follow_node != null and is_instance_valid(_follow_node):
		global_position = _follow_node.global_position

	phase_timer += delta

	match current_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if phase_timer >= _warning_time:
				current_phase = Phase.ACTIVE
				phase_timer = 0.0
				is_hazard_active = true
				BossConstants.play_sfx(self, &"laser", -4.0)
				beam_activated.emit(global_position, beam_count)
				_check_player_overlap(player_node)
		Phase.ACTIVE:
			if _reverse_at_active_time >= 0.0 and not _reversed and phase_timer >= _reverse_at_active_time:
				_reversed = true
				_angular_speed = -_angular_speed
				_sweep_velocity = -_sweep_velocity
			current_angle += _angular_speed * delta
			if _follow_node == null:
				global_position += _sweep_velocity * delta
			_check_player_overlap(player_node)
			if phase_timer >= _active_time:
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


func _check_player_overlap(player_node: Node2D = null) -> void:
	if not is_hazard_active:
		return
	var players: Array[Node2D] = BossConstants.collect_players(self, player_node)
	var half_len: float = beam_length * 0.5
	var half_w: float = beam_width * 0.5
	for body: Node2D in players:
		var player_r: float = BossConstants.get_player_hit_radius(body)
		var rel: Vector2 = body.global_position - global_position
		for i: int in range(beam_count):
			var dir: Vector2 = Vector2.from_angle(get_spoke_angle(i))
			var along: float = absf(rel.dot(dir))
			var perp: float = absf(rel.cross(dir))
			if along <= half_len + player_r and perp <= half_w + player_r:
				BossConstants.apply_player_hit(body, parryable, hazard_kind)
				break


func _draw() -> void:
	var vis_half_len: float = minf(beam_length * 0.5, 1450.0)
	var half_w: float = beam_width * 0.5

	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(_warning_time, 0.001), 0.0, 1.0)
			var rail_alpha: float = lerpf(0.48, 0.95, progress)
			var rail_col: Color = Color(0.88, 0.88, 0.88, rail_alpha)
			var band_col: Color = Color(0.32, 0.32, 0.32, lerpf(0.14, 0.32, progress))
			var fill_half: float = half_w * progress
			var fill_col: Color = Color(0.76, 0.76, 0.76, lerpf(0.12, 0.34, progress))
			var filament_offset: float = half_w * (1.0 - ease(progress, 0.60))
			var filament_g: float = lerpf(0.72, 1.0, progress)
			var filament_col: Color = Color(filament_g, filament_g, filament_g, lerpf(0.60, 0.98, progress))
			var tick_col: Color = Color(0.92, 0.92, 0.92, lerpf(0.45, 0.92, progress))
			var dash_phase: float = phase_timer * 70.0

			_rail_pts.resize(0)
			_filament_pts.resize(0)
			_tick_pts.resize(0)

			# Pass 1: emit all spoke quads while accumulating dashed rails, filaments & ticks
			for i: int in range(beam_count):
				var angle: float = get_spoke_angle(i)
				var dir: Vector2 = Vector2.from_angle(angle)
				var side: Vector2 = Vector2(-dir.y, dir.x)
				var p0: Vector2 = -dir * vis_half_len
				var p1: Vector2 = dir * vis_half_len

				# Full-width warning corridor fill
				_scratch_quad[0] = p0 - side * half_w
				_scratch_quad[1] = p1 - side * half_w
				_scratch_quad[2] = p1 + side * half_w
				_scratch_quad[3] = p0 + side * half_w
				draw_colored_polygon(_scratch_quad, band_col)

				# Expanding center charge fill showing countdown progress
				if fill_half > 0.6:
					_scratch_quad[0] = p0 - side * fill_half
					_scratch_quad[1] = p1 - side * fill_half
					_scratch_quad[2] = p1 + side * fill_half
					_scratch_quad[3] = p0 + side * fill_half
					draw_colored_polygon(_scratch_quad, fill_col)

				# High-contrast dashed outer rails
				_rail_pts = BossConstants.append_dashed_line_pts(_rail_pts, p0 - side * half_w, p1 - side * half_w, 16.0, 10.0, dash_phase)
				_rail_pts = BossConstants.append_dashed_line_pts(_rail_pts, p0 + side * half_w, p1 + side * half_w, 16.0, 10.0, -dash_phase)

				# Converging inner filaments + cross-ticks locking onto centerline
				if filament_offset > 1.2:
					var f_idx: int = _filament_pts.size()
					_filament_pts.resize(f_idx + 4)
					_filament_pts[f_idx] = p0 - side * filament_offset
					_filament_pts[f_idx + 1] = p1 - side * filament_offset
					_filament_pts[f_idx + 2] = p0 + side * filament_offset
					_filament_pts[f_idx + 3] = p1 + side * filament_offset

					var tick_step: float = 140.0
					var tick_d: float = -560.0
					var t_idx: int = _tick_pts.size()
					_tick_pts.resize(t_idx + 9 * 4)
					while tick_d <= 560.0:
						var tc: Vector2 = dir * tick_d
						_tick_pts[t_idx] = tc - side * half_w
						_tick_pts[t_idx + 1] = tc - side * filament_offset
						_tick_pts[t_idx + 2] = tc + side * half_w
						_tick_pts[t_idx + 3] = tc + side * filament_offset
						t_idx += 4
						tick_d += tick_step
					if t_idx != _tick_pts.size():
						_tick_pts.resize(t_idx)
				else:
					var f_idx: int = _filament_pts.size()
					_filament_pts.resize(f_idx + 2)
					_filament_pts[f_idx] = p0
					_filament_pts[f_idx + 1] = p1

			# Pass 2: batched multilines + optional hub arc
			if _rail_pts.size() >= 2:
				draw_multiline(_rail_pts, rail_col, 1.8, true)
			if _filament_pts.size() >= 2:
				if filament_offset > 1.2:
					draw_multiline(_filament_pts, filament_col, 1.8, true)
				else:
					draw_multiline(_filament_pts, Color(1.0, 1.0, 1.0, 0.98), 3.0, true)
			if _tick_pts.size() >= 2:
				draw_multiline(_tick_pts, tick_col, 1.4, true)

			if beam_count > 1:
				var hub_r: float = lerpf(beam_width * 1.25, beam_width * 0.65, progress)
				draw_arc(Vector2.ZERO, hub_r, 0.0, TAU, 28, Color(0.92, 0.92, 0.92, lerpf(0.55, 0.96, progress)), 2.0, true)

		Phase.ACTIVE:
			var snap_flash: float = clampf(1.0 - phase_timer / 0.12, 0.0, 1.0)
			var bloom_half: float = half_w * (1.36 + 0.25 * snap_flash)
			var core_half: float = half_w * (1.0 + 0.10 * snap_flash)
			var bloom_col: Color = Color(0.90, 0.90, 0.90, 0.20 + 0.12 * snap_flash)
			var core_col: Color = Color(1.0, 1.0, 1.0, 1.0)

			_filament_pts.resize(beam_count * 2)
			_chev_pts.resize(0)

			# Pass 1: emit all spoke quads while accumulating center filaments & parry chevrons
			for i: int in range(beam_count):
				var angle: float = get_spoke_angle(i)
				var dir: Vector2 = Vector2.from_angle(angle)
				var side: Vector2 = Vector2(-dir.y, dir.x)
				var p0: Vector2 = -dir * vis_half_len
				var p1: Vector2 = dir * vis_half_len

				# Monochrome outer glow halo
				_scratch_quad[0] = p0 - side * bloom_half
				_scratch_quad[1] = p1 - side * bloom_half
				_scratch_quad[2] = p1 + side * bloom_half
				_scratch_quad[3] = p0 + side * bloom_half
				draw_colored_polygon(_scratch_quad, bloom_col)

				# Stark bright white core beam
				_scratch_quad[0] = p0 - side * core_half
				_scratch_quad[1] = p1 - side * core_half
				_scratch_quad[2] = p1 + side * core_half
				_scratch_quad[3] = p0 + side * core_half
				draw_colored_polygon(_scratch_quad, core_col)

				_filament_pts[i * 2] = p0
				_filament_pts[i * 2 + 1] = p1

				if parryable:
					var step: float = 96.0
					var offset: float = fposmod(phase_timer * 180.0, step)
					var dist: float = -700.0 + offset
					var chev_sz: float = minf(half_w * 0.72, 10.0)
					while dist <= 700.0:
						_chev_pts = BossConstants.append_double_chevron_pts(_chev_pts, dir * dist, dir, chev_sz)
						dist += step

			# Pass 2: batched center filaments & parry chevrons, then hub circles
			if _filament_pts.size() >= 2:
				draw_multiline(_filament_pts, Color(0.86, 0.86, 0.86, 0.45), maxf(beam_width * 0.14, 1.5), true)
			if parryable and _chev_pts.size() >= 2:
				draw_multiline(_chev_pts, Color(0.12, 0.12, 0.12, 0.9), 1.6, true)

			if beam_count > 1:
				draw_circle(Vector2.ZERO, half_w * 1.15, core_col)
				draw_circle(Vector2.ZERO, half_w * 0.45, Color(0.10, 0.10, 0.10, 0.85))

		Phase.FADE_OUT:
			var fade_t: float = clampf(phase_timer / maxf(FADE_DURATION, 0.001), 0.0, 1.0)
			var cur_half: float = half_w * (1.0 - fade_t)
			var alpha: float = (1.0 - fade_t) * 0.85
			if cur_half > 0.4:
				var fade_col: Color = Color(0.85, 0.85, 0.85, alpha)
				for i: int in range(beam_count):
					var angle: float = get_spoke_angle(i)
					var dir: Vector2 = Vector2.from_angle(angle)
					var side: Vector2 = Vector2(-dir.y, dir.x)
					var p0: Vector2 = -dir * vis_half_len
					var p1: Vector2 = dir * vis_half_len
					_scratch_quad[0] = p0 - side * cur_half
					_scratch_quad[1] = p1 - side * cur_half
					_scratch_quad[2] = p1 + side * cur_half
					_scratch_quad[3] = p0 + side * cur_half
					draw_colored_polygon(_scratch_quad, fade_col)
