class_name BossPistonWall
extends Node2D

signal piston_slammed(impact_pos: Vector2, inward_normal: Vector2)

enum Phase {
	TELEGRAPH = 0,
	SLAM = 1,
	HOLD = 2,
	RETRACT = 3,
}

var is_hazard_active: bool = false
var parryable: bool = false
var hazard_kind: StringName = &"piston_wall"

var current_phase: int = Phase.TELEGRAPH
var phase_timer: float = 0.0
var current_extension: float = 0.0

var _arena_size: Vector2 = BossConstants.ARENA_REF
var _side: StringName = &"left"
var _span_start: float = 0.0
var _span_end: float = 240.0
var _reach: float = 240.0
var _warning_time: float = 0.9375
var _slam_time: float = 0.14
var _hold_time: float = 0.35
var _retract_time: float = 0.28
var _inward_normal: Vector2 = Vector2.RIGHT
var _impact_pos: Vector2 = Vector2.ZERO
var _slam_flash: float = 0.0
var _queued_free: bool = false
var _rail_pts: PackedVector2Array = PackedVector2Array()
var _chev_pts: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	add_to_group("boss_hazards")


func _ready() -> void:
	if not is_in_group("boss_hazards"):
		add_to_group("boss_hazards")
	queue_redraw()


func _physics_process(delta: float) -> void:
	simulate_physics(delta)


func configure(
	arena_size: Vector2,
	side: StringName,
	span_start: float,
	span_end: float,
	reach: float,
	warning_time: float,
	slam_time: float = 0.14,
	hold_time: float = 0.35,
	retract_time: float = 0.28,
	is_parryable: bool = false
) -> void:
	global_position = Vector2.ZERO
	_arena_size = arena_size
	_side = side
	_span_start = minf(span_start, span_end)
	_span_end = maxf(span_start, span_end)
	_reach = maxf(reach, BossConstants.PISTON_THICKNESS)
	_warning_time = maxf(warning_time, 0.001)
	_slam_time = maxf(slam_time, 0.01)
	_hold_time = maxf(hold_time, 0.01)
	_retract_time = maxf(retract_time, 0.01)
	parryable = is_parryable

	var mid_span: float = (_span_start + _span_end) * 0.5
	match _side:
		&"right":
			_inward_normal = Vector2.LEFT
			_impact_pos = Vector2(_arena_size.x - _reach, mid_span)
		&"top":
			_inward_normal = Vector2.DOWN
			_impact_pos = Vector2(mid_span, _reach)
		&"bottom":
			_inward_normal = Vector2.UP
			_impact_pos = Vector2(mid_span, _arena_size.y - _reach)
		_:
			_side = &"left"
			_inward_normal = Vector2.RIGHT
			_impact_pos = Vector2(_reach, mid_span)

	current_phase = Phase.TELEGRAPH
	phase_timer = 0.0
	current_extension = 0.0
	_slam_flash = 0.0
	is_hazard_active = false
	queue_redraw()


func get_piston_rect(extension: float = -1.0) -> Rect2:
	var ext: float = current_extension if extension < 0.0 else extension
	var span_len: float = maxf(_span_end - _span_start, 2.0)
	match _side:
		&"right":
			return Rect2(_arena_size.x - ext, _span_start, ext, span_len)
		&"top":
			return Rect2(_span_start, 0.0, span_len, ext)
		&"bottom":
			return Rect2(_span_start, _arena_size.y - ext, span_len, ext)
		_:
			return Rect2(0.0, _span_start, ext, span_len)


func simulate_physics(delta: float, player_node: Node2D = null) -> void:
	if _queued_free:
		return

	phase_timer += delta
	_slam_flash = maxf(0.0, _slam_flash - delta * 5.0)

	match current_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			current_extension = 0.0
			if phase_timer >= _warning_time:
				current_phase = Phase.SLAM
				phase_timer = 0.0
				is_hazard_active = true
		Phase.SLAM:
			is_hazard_active = true
			var t: float = clampf(phase_timer / maxf(_slam_time, 0.001), 0.0, 1.0)
			current_extension = _reach * ease(t, 0.35)
			_check_player_overlap(player_node)
			if phase_timer >= _slam_time:
				current_extension = _reach
				_slam_flash = 1.0
				BossConstants.play_sfx(self, &"wall_slam", -5.0)
				piston_slammed.emit(_impact_pos, _inward_normal)
				current_phase = Phase.HOLD
				phase_timer = 0.0
				_check_player_overlap(player_node)
		Phase.HOLD:
			is_hazard_active = true
			current_extension = _reach
			_check_player_overlap(player_node)
			if phase_timer >= _hold_time:
				current_phase = Phase.RETRACT
				phase_timer = 0.0
				is_hazard_active = false
		Phase.RETRACT:
			is_hazard_active = false
			var t: float = clampf(phase_timer / maxf(_retract_time, 0.001), 0.0, 1.0)
			current_extension = _reach * (1.0 - ease(t, 1.6))
			if phase_timer >= _retract_time:
				_queued_free = true
				queue_free()
				return

	queue_redraw()


func _check_player_overlap(player_node: Node2D = null) -> void:
	if not is_hazard_active or current_extension <= 0.5:
		return
	var rect: Rect2 = get_piston_rect()
	var players: Array[Node2D] = BossConstants.collect_players(self, player_node)
	for body: Node2D in players:
		var player_r: float = BossConstants.get_player_hit_radius(body)
		if BossConstants.circle_rect_overlap(body.global_position, player_r, rect):
			BossConstants.apply_player_hit(body, parryable, hazard_kind)


func _draw() -> void:
	var target_rect: Rect2 = get_piston_rect(_reach)
	var is_h: bool = (_side == &"left" or _side == &"right")

	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(_warning_time, 0.001), 0.0, 1.0)
			var zone_col: Color = Color(0.36, 0.36, 0.36, lerpf(0.15, 0.34, progress))
			var rail_col: Color = Color(0.92, 0.92, 0.92, lerpf(0.50, 0.96, progress))
			draw_rect(target_rect, zone_col, true)

			# Laser-rail warning boundaries
			var tl: Vector2 = target_rect.position
			var tr: Vector2 = target_rect.position + Vector2(target_rect.size.x, 0.0)
			var bl: Vector2 = target_rect.position + Vector2(0.0, target_rect.size.y)
			var br: Vector2 = target_rect.position + target_rect.size
			var dash_p: float = phase_timer * 64.0
			_rail_pts.resize(0)
			_rail_pts = BossConstants.append_dashed_line_pts(_rail_pts, tl, tr, 14.0, 10.0, dash_p)
			_rail_pts = BossConstants.append_dashed_line_pts(_rail_pts, bl, br, 14.0, 10.0, -dash_p)
			_rail_pts = BossConstants.append_dashed_line_pts(_rail_pts, tl, bl, 14.0, 10.0, dash_p)
			_rail_pts = BossConstants.append_dashed_line_pts(_rail_pts, tr, br, 14.0, 10.0, -dash_p)
			if _rail_pts.size() >= 2:
				draw_multiline(_rail_pts, rail_col, 1.8, true)

			# Advancing countdown charge bar showing exact timing to slam
			var charge_ext: float = _reach * progress
			var charge_rect: Rect2 = get_piston_rect(maxf(charge_ext, 6.0))
			draw_rect(charge_rect, Color(0.78, 0.78, 0.78, lerpf(0.18, 0.42, progress)), true)
			var edge_rect: Rect2 = get_piston_rect(maxf(_reach * progress * 0.22, 5.0))
			draw_rect(edge_rect, Color(0.96, 0.96, 0.96, lerpf(0.48, 0.92, progress)), true)

			# Impact line preview at full reach + inward chevrons
			var impact_col: Color = Color(1.0, 1.0, 1.0, lerpf(0.48, 0.96, progress))
			var chev_col: Color = Color(0.90, 0.90, 0.90, lerpf(0.46, 0.92, progress))
			_chev_pts.resize(0)
			if is_h:
				var ix: float = _reach if _side == &"left" else (_arena_size.x - _reach)
				draw_line(Vector2(ix, _span_start), Vector2(ix, _span_end), impact_col, 2.4, true)
				var cx: float = (_reach * 0.52) if _side == &"left" else (_arena_size.x - _reach * 0.52)
				var cy: float = _span_start + 48.0
				while cy <= _span_end - 32.0:
					_chev_pts = BossConstants.append_double_chevron_pts(_chev_pts, Vector2(cx, cy), _inward_normal, 9.0)
					cy += 96.0
			else:
				var iy: float = _reach if _side == &"top" else (_arena_size.y - _reach)
				draw_line(Vector2(_span_start, iy), Vector2(_span_end, iy), impact_col, 2.4, true)
				var cy_v: float = (_reach * 0.52) if _side == &"top" else (_arena_size.y - _reach * 0.52)
				var cx_v: float = _span_start + 48.0
				while cx_v <= _span_end - 32.0:
					_chev_pts = BossConstants.append_double_chevron_pts(_chev_pts, Vector2(cx_v, cy_v), _inward_normal, 9.0)
					cx_v += 96.0
			if _chev_pts.size() >= 2:
				draw_multiline(_chev_pts, chev_col, 1.8, true)

		Phase.SLAM, Phase.HOLD:
			if current_extension <= 0.5:
				return
			var rect: Rect2 = get_piston_rect()
			var head_thick: float = minf(current_extension, BossConstants.PISTON_THICKNESS)

			# Mechanical piston body
			draw_rect(rect, Color(0.86, 0.86, 0.86, 0.96), true)

			# Inner geometric cross-bracing on shaft
			var shaft_inset: Rect2 = rect.grow(-6.0)
			if shaft_inset.size.x > 8.0 and shaft_inset.size.y > 8.0:
				draw_rect(shaft_inset, Color(0.16, 0.16, 0.16, 0.92), true)
				_rail_pts.resize(4)
				_rail_pts[0] = shaft_inset.position
				_rail_pts[1] = shaft_inset.position + shaft_inset.size
				_rail_pts[2] = Vector2(shaft_inset.position.x + shaft_inset.size.x, shaft_inset.position.y)
				_rail_pts[3] = Vector2(shaft_inset.position.x, shaft_inset.position.y + shaft_inset.size.y)
				draw_multiline(_rail_pts, Color(0.48, 0.48, 0.48, 0.70), 1.6, true)

			# Stark white leading piston head plate
			var head_rect: Rect2
			match _side:
				&"right":
					head_rect = Rect2(rect.position.x, rect.position.y, head_thick, rect.size.y)
				&"top":
					head_rect = Rect2(rect.position.x, rect.position.y + rect.size.y - head_thick, rect.size.x, head_thick)
				&"bottom":
					head_rect = Rect2(rect.position.x, rect.position.y, rect.size.x, head_thick)
				_:
					head_rect = Rect2(rect.position.x + rect.size.x - head_thick, rect.position.y, head_thick, rect.size.y)
			draw_rect(head_rect, Color(1.0, 1.0, 1.0, 1.0), true)
			draw_rect(rect, Color(1.0, 1.0, 1.0, 1.0), false, 2.0)

			# Impact shock flash line on slam
			if _slam_flash > 0.01:
				var flash_col: Color = Color(1.0, 1.0, 1.0, _slam_flash * 0.9)
				if is_h:
					var fx: float = rect.position.x + rect.size.x if _side == &"left" else rect.position.x
					draw_line(Vector2(fx, _span_start - 10.0), Vector2(fx, _span_end + 10.0), flash_col, 4.0 * _slam_flash + 1.5, true)
				else:
					var fy: float = rect.position.y + rect.size.y if _side == &"top" else rect.position.y
					draw_line(Vector2(_span_start - 10.0, fy), Vector2(_span_end + 10.0, fy), flash_col, 4.0 * _slam_flash + 1.5, true)

		Phase.RETRACT:
			if current_extension <= 0.5:
				return
			var fade_t: float = clampf(phase_timer / maxf(_retract_time, 0.001), 0.0, 1.0)
			var rect: Rect2 = get_piston_rect()
			var alpha: float = (1.0 - fade_t) * 0.65
			draw_rect(rect, Color(0.50, 0.50, 0.50, alpha), true)
			draw_rect(rect, Color(0.78, 0.78, 0.78, alpha), false, 1.5)
