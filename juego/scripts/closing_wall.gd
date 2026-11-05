extends Node2D

signal wall_slammed(gap_world_center: Vector2, axis: int)

enum WallAxis {
	HORIZONTAL = 0,
	VERTICAL = 1,
}

enum Phase {
	TELEGRAPH,
	CLOSING,
	HOLD,
	RETRACTING,
	FADE_OUT,
	DONE,
}

const DEFAULT_GAP_SIZE: float = 132.0
const MIN_GAP_SIZE: float = 112.0
const DEFAULT_THICKNESS: float = 46.0
const DEFAULT_WARNING: float = 1.35
const DEFAULT_CLOSE_TIME: float = 0.62
const DEFAULT_HOLD_TIME: float = 1.15
const DEFAULT_RETRACT_TIME: float = 0.55
const FADE_TIME: float = 0.20
const OVERLAP_CHECK_INTERVAL: float = 0.08

var wall_axis: WallAxis = WallAxis.HORIZONTAL
var current_phase: Phase = Phase.TELEGRAPH
var phase_timer: float = 0.0
var gap_center: float = 0.0
var gap_size: float = DEFAULT_GAP_SIZE
var wall_thickness: float = DEFAULT_THICKNESS
var warning_time: float = DEFAULT_WARNING
var close_time: float = DEFAULT_CLOSE_TIME
var hold_time: float = DEFAULT_HOLD_TIME
var retract_time: float = DEFAULT_RETRACT_TIME
var is_hazard_active: bool = false

var _overlap_timer: float = 0.0
var _slam_flash: float = 0.0
var _arena_size: Vector2 = Vector2(1152.0, 648.0)
var _wall_a_start: Vector2 = Vector2.ZERO
var _wall_a_target: Vector2 = Vector2.ZERO
var _wall_b_start: Vector2 = Vector2.ZERO
var _wall_b_target: Vector2 = Vector2.ZERO
var _wall_size: Vector2 = Vector2(46.0, 648.0)

@onready var telegraph_a: Polygon2D = $TelegraphA
@onready var telegraph_b: Polygon2D = $TelegraphB
@onready var wall_a: AnimatableBody2D = $WallA
@onready var wall_b: AnimatableBody2D = $WallB
@onready var visual_a: Polygon2D = $WallA/Visual
@onready var visual_b: Polygon2D = $WallB/Visual
@onready var edge_a: Polygon2D = $WallA/Edge
@onready var edge_b: Polygon2D = $WallB/Edge
@onready var damage_a: Area2D = $WallA/DamageArea
@onready var damage_b: Area2D = $WallB/DamageArea
@onready var shape_a: CollisionShape2D = $WallA/CollisionShape2D
@onready var shape_b: CollisionShape2D = $WallB/CollisionShape2D
@onready var damage_shape_a: CollisionShape2D = $WallA/DamageArea/DamageShape
@onready var damage_shape_b: CollisionShape2D = $WallB/DamageArea/DamageShape


func _ready() -> void:
	damage_a.body_entered.connect(_on_damage_body_entered)
	damage_b.body_entered.connect(_on_damage_body_entered)
	_arena_size = _get_arena_size()
	_build_layout()
	_enter_phase(Phase.TELEGRAPH)


func configure(
	axis: int = WallAxis.HORIZONTAL,
	gap_center_position: float = 324.0,
	requested_gap: float = DEFAULT_GAP_SIZE,
	requested_thickness: float = DEFAULT_THICKNESS,
	warning: float = DEFAULT_WARNING,
	closing_time: float = DEFAULT_CLOSE_TIME,
	hold_duration: float = DEFAULT_HOLD_TIME,
	retracting_time: float = DEFAULT_RETRACT_TIME
) -> void:
	_arena_size = _get_arena_size()
	wall_axis = WallAxis.HORIZONTAL if axis == WallAxis.HORIZONTAL else WallAxis.VERTICAL
	var span: float = _arena_size.x if wall_axis == WallAxis.HORIZONTAL else _arena_size.y
	gap_center = clampf(gap_center_position, MIN_GAP_SIZE * 0.5 + 24.0, span - MIN_GAP_SIZE * 0.5 - 24.0)
	gap_size = clampf(requested_gap, MIN_GAP_SIZE, minf(span * 0.55, 240.0)) if span > 0.0 else maxf(requested_gap, MIN_GAP_SIZE)
	wall_thickness = maxf(requested_thickness, 20.0)
	warning_time = maxf(warning, 0.4)
	close_time = maxf(closing_time, 0.25)
	hold_time = maxf(hold_duration, 0.25)
	retract_time = maxf(retracting_time, 0.20)
	_slam_flash = 0.0
	_build_layout()
	_enter_phase(Phase.TELEGRAPH)
	queue_redraw()


func _physics_process(delta: float) -> void:
	simulate_physics(delta)


func simulate_physics(delta: float) -> void:
	var safe_delta: float = maxf(delta, 0.0)
	phase_timer += safe_delta
	if _slam_flash > 0.0:
		_slam_flash = maxf(0.0, _slam_flash - safe_delta * 3.8)
	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(warning_time, 0.001), 0.0, 1.0)
			var pulse: float = 0.5 + 0.5 * sin(phase_timer * 11.0)
			var alpha: float = 0.16 + 0.16 * pulse + 0.10 * progress
			for telegraph: Polygon2D in [telegraph_a, telegraph_b]:
				telegraph.visible = true
				telegraph.color = Color(0.62, 0.62, 0.62, alpha)
			wall_a.global_position = _wall_a_start
			wall_b.global_position = _wall_b_start
			if phase_timer >= warning_time:
				_enter_phase(Phase.CLOSING)
		Phase.CLOSING:
			var progress: float = clampf(phase_timer / maxf(close_time, 0.001), 0.0, 1.0)
			var eased: float = ease(progress, 0.55)
			wall_a.global_position = _wall_a_start.lerp(_wall_a_target, eased)
			wall_b.global_position = _wall_b_start.lerp(_wall_b_target, eased)
			_check_overlap(safe_delta)
			if progress >= 1.0:
				wall_a.global_position = _wall_a_target
				wall_b.global_position = _wall_b_target
				_enter_phase(Phase.HOLD)
		Phase.HOLD:
			var pulse: float = 0.5 + 0.5 * sin(phase_timer * 18.0)
			var white: float = clampf(0.82 + 0.18 * pulse + 0.18 * _slam_flash, 0.0, 1.0)
			var body_g: float = 0.08 + 0.14 * _slam_flash
			for wall_visual: Polygon2D in [visual_a, visual_b]:
				wall_visual.color = Color(body_g, body_g, body_g, 0.98)
			for wall_edge: Polygon2D in [edge_a, edge_b]:
				wall_edge.color = Color(white, white, white, 1.0)
			_check_overlap(safe_delta)
			if phase_timer >= hold_time:
				_enter_phase(Phase.RETRACTING)
		Phase.RETRACTING:
			var progress: float = clampf(phase_timer / maxf(retract_time, 0.001), 0.0, 1.0)
			var eased: float = ease(progress, 0.4)
			wall_a.global_position = _wall_a_target.lerp(_wall_a_start, eased)
			wall_b.global_position = _wall_b_target.lerp(_wall_b_start, eased)
			if progress >= 1.0:
				_enter_phase(Phase.FADE_OUT)
		Phase.FADE_OUT:
			var progress: float = clampf(phase_timer / FADE_TIME, 0.0, 1.0)
			modulate.a = 1.0 - progress
			if progress >= 1.0:
				_enter_phase(Phase.DONE)
				queue_free()
		Phase.DONE:
			pass
	queue_redraw()


func _build_layout() -> void:
	_arena_size = _get_arena_size()
	var span_x: float = _arena_size.x
	var span_y: float = _arena_size.y
	var half_gap: float = gap_size * 0.5
	var hurt_margin: float = 2.0
	var horizontal: bool = wall_axis == WallAxis.HORIZONTAL

	if horizontal:
		_wall_size = Vector2(wall_thickness, span_y + wall_thickness * 2.0)
		_wall_a_target = Vector2(gap_center - half_gap - wall_thickness * 0.5, span_y * 0.5)
		_wall_b_target = Vector2(gap_center + half_gap + wall_thickness * 0.5, span_y * 0.5)
		_wall_a_start = Vector2(-wall_thickness * 0.5 - hurt_margin, span_y * 0.5)
		_wall_b_start = Vector2(span_x + wall_thickness * 0.5 + hurt_margin, span_y * 0.5)
	else:
		_wall_size = Vector2(span_x + wall_thickness * 2.0, wall_thickness)
		_wall_a_target = Vector2(span_x * 0.5, gap_center - half_gap - wall_thickness * 0.5)
		_wall_b_target = Vector2(span_x * 0.5, gap_center + half_gap + wall_thickness * 0.5)
		_wall_a_start = Vector2(span_x * 0.5, -wall_thickness * 0.5 - hurt_margin)
		_wall_b_start = Vector2(span_x * 0.5, span_y + wall_thickness * 0.5 + hurt_margin)

	var wall_poly: PackedVector2Array = Shapes.rect(_wall_size)
	var edge_size: float = 6.0
	var edge_poly: PackedVector2Array = Shapes.rect(Vector2(edge_size, _wall_size.y) if horizontal else Vector2(_wall_size.x, edge_size))

	for wall_visual: Polygon2D in [visual_a, visual_b]:
		wall_visual.polygon = wall_poly
		wall_visual.color = Color(0.14, 0.14, 0.14, 0.98)
	for wall_edge: Polygon2D in [edge_a, edge_b]:
		wall_edge.polygon = edge_poly
		wall_edge.color = Color(0.95, 0.95, 0.95, 1.0)

	var edge_offset: Vector2 = Vector2(_wall_size.x * 0.5 - edge_size * 0.5, 0.0) if horizontal else Vector2(0.0, _wall_size.y * 0.5 - edge_size * 0.5)
	edge_a.position = edge_offset
	edge_b.position = -edge_offset

	telegraph_a.polygon = wall_poly
	telegraph_b.polygon = wall_poly
	telegraph_a.position = _wall_a_target
	telegraph_b.position = _wall_b_target

	wall_a.global_position = _wall_a_start
	wall_b.global_position = _wall_b_start
	for shape_node: CollisionShape2D in [shape_a, shape_b, damage_shape_a, damage_shape_b]:
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = _wall_size
		shape_node.shape = rect


func _enter_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_timer = 0.0
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			_set_damage_enabled(false)
			modulate.a = 1.0
			wall_a.visible = false
			wall_b.visible = false
			telegraph_a.position = _wall_a_target
			telegraph_b.position = _wall_b_target
		Phase.CLOSING:
			is_hazard_active = true
			_set_damage_enabled(true)
			wall_a.visible = true
			wall_b.visible = true
			wall_a.modulate = Color.WHITE
			wall_b.modulate = Color.WHITE
			telegraph_a.visible = false
			telegraph_b.visible = false
			_check_overlap(0.0)
		Phase.HOLD:
			is_hazard_active = true
			_set_damage_enabled(true)
			telegraph_a.visible = false
			telegraph_b.visible = false
			_slam_flash = 1.0
			wall_slammed.emit(get_gap_center(), wall_axis)
			_check_overlap(0.0)
		Phase.RETRACTING, Phase.FADE_OUT, Phase.DONE, _:
			is_hazard_active = false
			_set_damage_enabled(false)
	queue_redraw()


func _draw() -> void:
	var horizontal: bool = wall_axis == WallAxis.HORIZONTAL
	var primary_span: float = _arena_size.x if horizontal else _arena_size.y
	var cross_span: float = _arena_size.y if horizontal else _arena_size.x
	var axis_vec: Vector2 = Vector2.RIGHT if horizontal else Vector2.DOWN
	var cross_vec: Vector2 = Vector2.DOWN if horizontal else Vector2.RIGHT
	var half_gap: float = gap_size * 0.5
	var half_thick: float = wall_thickness * 0.5

	if current_phase == Phase.TELEGRAPH:
		var progress: float = clampf(phase_timer / maxf(warning_time, 0.001), 0.0, 1.0)
		var rail_col: Color = Color(0.88, 0.88, 0.88, 0.32 + 0.48 * progress)
		var limit_a: float = gap_center - half_gap
		var limit_b: float = gap_center + half_gap
		draw_line(axis_vec * limit_a, axis_vec * limit_a + cross_vec * cross_span, rail_col, 2.0, true)
		draw_line(axis_vec * limit_b, axis_vec * limit_b + cross_vec * cross_span, rail_col, 2.0, true)

		var count: int = 5 if horizontal else 6
		for i: int in range(count):
			var cross_pos: float = cross_span * ((0.16 + 0.17 * float(i)) if horizontal else (0.14 + 0.144 * float(i)))
			var slide_a: float = lerpf(26.0, maxf(30.0, limit_a - 18.0), progress)
			var slide_b: float = lerpf(primary_span - 26.0, minf(primary_span - 30.0, limit_b + 18.0), progress)
			var tip_a: Vector2 = axis_vec * slide_a + cross_vec * cross_pos
			var tip_b: Vector2 = axis_vec * slide_b + cross_vec * cross_pos
			draw_line(tip_a - axis_vec * 10.0 - cross_vec * 8.0, tip_a, rail_col, 2.0, true)
			draw_line(tip_a - axis_vec * 10.0 + cross_vec * 8.0, tip_a, rail_col, 2.0, true)
			draw_line(tip_b + axis_vec * 10.0 - cross_vec * 8.0, tip_b, rail_col, 2.0, true)
			draw_line(tip_b + axis_vec * 10.0 + cross_vec * 8.0, tip_b, rail_col, 2.0, true)
		return

	if current_phase in [Phase.CLOSING, Phase.HOLD, Phase.RETRACTING, Phase.FADE_OUT]:
		var rib_col: Color = Color(0.45 + 0.35 * _slam_flash, 0.45 + 0.35 * _slam_flash, 0.45 + 0.35 * _slam_flash, 0.78)
		var tooth_col: Color = Color(0.94, 0.94, 0.94, 0.92)
		var pos_a: float = wall_a.global_position.x if horizontal else wall_a.global_position.y
		var pos_b: float = wall_b.global_position.x if horizontal else wall_b.global_position.y
		var a_outer: float = pos_a - half_thick
		var a_inner: float = pos_a + half_thick
		var b_inner: float = pos_b - half_thick
		var b_outer: float = pos_b + half_thick
		var rib_count: int = 7 if horizontal else 9

		for i: int in range(rib_count):
			var cross_c: float = cross_span * ((0.08 + 0.14 * float(i)) if horizontal else (0.06 + 0.11 * float(i)))
			if a_inner > 0.0:
				var tip_a: Vector2 = axis_vec * a_inner + cross_vec * cross_c
				draw_line(axis_vec * maxf(0.0, a_outer) + cross_vec * cross_c, tip_a, rib_col, 2.0, true)
				draw_line(tip_a - axis_vec * 5.0 - cross_vec * 5.0, tip_a, tooth_col, 2.0, true)
				draw_line(tip_a - axis_vec * 5.0 + cross_vec * 5.0, tip_a, tooth_col, 2.0, true)
			if b_inner < primary_span:
				var tip_b: Vector2 = axis_vec * b_inner + cross_vec * cross_c
				draw_line(tip_b, axis_vec * minf(primary_span, b_outer) + cross_vec * cross_c, rib_col, 2.0, true)
				draw_line(tip_b + axis_vec * 5.0 - cross_vec * 5.0, tip_b, tooth_col, 2.0, true)
				draw_line(tip_b + axis_vec * 5.0 + cross_vec * 5.0, tip_b, tooth_col, 2.0, true)
		if _slam_flash > 0.01:
			var f_col: Color = Color(1.0, 1.0, 1.0, 0.72 * _slam_flash)
			draw_line(axis_vec * a_inner, axis_vec * a_inner + cross_vec * cross_span, f_col, 4.0, true)
			draw_line(axis_vec * b_inner, axis_vec * b_inner + cross_vec * cross_span, f_col, 4.0, true)


func _set_damage_enabled(enabled: bool) -> void:
	for damage_area: Area2D in [damage_a, damage_b]:
		damage_area.monitoring = enabled
		damage_area.monitorable = enabled
	for damage_shape: CollisionShape2D in [damage_shape_a, damage_shape_b]:
		damage_shape.disabled = not enabled


func _check_overlap(delta: float) -> void:
	if delta > 0.0:
		_overlap_timer -= delta
		if _overlap_timer > 0.0:
			return
	_overlap_timer = OVERLAP_CHECK_INTERVAL
	if not is_hazard_active:
		return
	for damage_area: Area2D in [damage_a, damage_b]:
		for body: Node2D in damage_area.get_overlapping_bodies():
			if body.is_in_group("player") and body.has_method("take_damage"):
				body.take_damage(1)
				return


func _on_damage_body_entered(body: Node2D) -> void:
	if is_hazard_active and body != null and body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(1)


func _get_arena_size() -> Vector2:
	var rect_size: Vector2 = get_viewport_rect().size
	if rect_size.x > 0.0 and rect_size.y > 0.0:
		return rect_size
	return Vector2(1152.0, 648.0)


func get_gap_size() -> float:
	return gap_size


func get_gap_center() -> Vector2:
	if wall_axis == WallAxis.HORIZONTAL:
		return Vector2(gap_center, _arena_size.y * 0.5)
	return Vector2(_arena_size.x * 0.5, gap_center)
