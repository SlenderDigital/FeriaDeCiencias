@tool
extends Node2D
## Pair of closing monochrome arena walls with a traversable safe gap.
##
## The pair telegraphs its crush zones and safe gap corridor with geometric
## brackets and compression chevrons, slides in from opposite edges with heavy
## piston backing, slams into a hold window with impact feedback, then retracts.

signal wall_slammed(gap_world_center: Vector2, axis: int)

enum WallAxis {
	HORIZONTAL = 0, # walls slide in from left and right, gap is vertical
	VERTICAL = 1,   # walls slide in from top and bottom, gap is horizontal
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

var hazard_type: int = 6
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
var contact_count: int = 0
var slam_count: int = 0
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
	_resolve_nodes()
	add_to_group("closing_walls")
	add_to_group("hazards")
	if damage_a != null and not damage_a.body_entered.is_connected(_on_damage_body_entered):
		damage_a.body_entered.connect(_on_damage_body_entered)
	if damage_b != null and not damage_b.body_entered.is_connected(_on_damage_body_entered):
		damage_b.body_entered.connect(_on_damage_body_entered)
	_arena_size = _get_arena_size()
	_build_layout()
	_enter_phase(Phase.TELEGRAPH)


## Configures the wall pair. gap_center is measured on the gap axis (x for a
## horizontal pair, y for a vertical pair).
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
	_resolve_nodes()
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
	slam_count = 0
	_slam_flash = 0.0
	_build_layout()
	_enter_phase(Phase.TELEGRAPH)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances the wall pair by delta seconds. Safe for deterministic tests.
func simulate_physics(delta: float) -> void:
	var safe_delta: float = maxf(delta, 0.0)
	phase_timer += safe_delta
	if _slam_flash > 0.0:
		_slam_flash = maxf(0.0, _slam_flash - safe_delta * 3.8)
	match current_phase:
		Phase.TELEGRAPH:
			_update_telegraph()
			_wall_a_position(_wall_a_start)
			_wall_b_position(_wall_b_start)
			if phase_timer >= warning_time:
				_enter_phase(Phase.CLOSING)
		Phase.CLOSING:
			var progress: float = clampf(phase_timer / maxf(close_time, 0.001), 0.0, 1.0)
			var eased: float = ease(progress, 0.55)
			_wall_a_position(_wall_a_start.lerp(_wall_a_target, eased))
			_wall_b_position(_wall_b_start.lerp(_wall_b_target, eased))
			_check_overlap(safe_delta)
			if progress >= 1.0:
				_wall_a_position(_wall_a_target)
				_wall_b_position(_wall_b_target)
				_enter_phase(Phase.HOLD)
		Phase.HOLD:
			_update_hold_visual()
			_check_overlap(safe_delta)
			if phase_timer >= hold_time:
				_enter_phase(Phase.RETRACTING)
		Phase.RETRACTING:
			var progress: float = clampf(phase_timer / maxf(retract_time, 0.001), 0.0, 1.0)
			var eased: float = ease(progress, 0.4)
			_wall_a_position(_wall_a_target.lerp(_wall_a_start, eased))
			_wall_b_position(_wall_b_target.lerp(_wall_b_start, eased))
			if progress >= 1.0:
				_enter_phase(Phase.FADE_OUT)
		Phase.FADE_OUT:
			var progress: float = clampf(phase_timer / FADE_TIME, 0.0, 1.0)
			modulate.a = 1.0 - progress
			if progress >= 1.0:
				_enter_phase(Phase.DONE)
				_despawn()
		Phase.DONE:
			pass
	queue_redraw()


func _build_layout() -> void:
	_arena_size = _get_arena_size()
	var span_x: float = _arena_size.x
	var span_y: float = _arena_size.y
	var half_gap: float = gap_size * 0.5
	var hurt_margin: float = 2.0

	if wall_axis == WallAxis.HORIZONTAL:
		_wall_size = Vector2(wall_thickness, span_y + wall_thickness * 2.0)
		_wall_a_target = Vector2(gap_center - half_gap - wall_thickness * 0.5, span_y * 0.5)
		_wall_b_target = Vector2(gap_center + half_gap + wall_thickness * 0.5, span_y * 0.5)
		_wall_a_start = Vector2(-wall_thickness * 0.5 - hurt_margin, span_y * 0.5)
		_wall_b_start = Vector2(span_x + wall_thickness * 0.5 + hurt_margin, span_y * 0.5)
		_build_wall_visuals(true)
	else:
		_wall_size = Vector2(span_x + wall_thickness * 2.0, wall_thickness)
		_wall_a_target = Vector2(span_x * 0.5, gap_center - half_gap - wall_thickness * 0.5)
		_wall_b_target = Vector2(span_x * 0.5, gap_center + half_gap + wall_thickness * 0.5)
		_wall_a_start = Vector2(span_x * 0.5, -wall_thickness * 0.5 - hurt_margin)
		_wall_b_start = Vector2(span_x * 0.5, span_y + wall_thickness * 0.5 + hurt_margin)
		_build_wall_visuals(false)

	_wall_a_position(_wall_a_start)
	_wall_b_position(_wall_b_start)
	_apply_rect_shape(shape_a, _wall_size)
	_apply_rect_shape(shape_b, _wall_size)
	_apply_rect_shape(damage_shape_a, _wall_size)
	_apply_rect_shape(damage_shape_b, _wall_size)
	_update_telegraph_visuals()


func _build_wall_visuals(horizontal: bool) -> void:
	z_index = -3
	var wall_poly: PackedVector2Array = _rect_polygon(_wall_size)
	var edge_size: float = 6.0
	var edge_poly: PackedVector2Array
	if horizontal:
		edge_poly = _rect_polygon(Vector2(edge_size, _wall_size.y))
	else:
		edge_poly = _rect_polygon(Vector2(_wall_size.x, edge_size))
	for wall_visual: Polygon2D in [visual_a, visual_b]:
		if wall_visual != null:
			wall_visual.polygon = wall_poly
			wall_visual.color = Color(0.14, 0.14, 0.14, 0.98)
	for wall_edge: Polygon2D in [edge_a, edge_b]:
		if wall_edge != null:
			wall_edge.polygon = edge_poly
			wall_edge.color = Color(0.95, 0.95, 0.95, 1.0)
	if edge_a != null:
		edge_a.position = Vector2(_wall_size.x * 0.5 - edge_size * 0.5, 0.0) if horizontal else Vector2(0.0, _wall_size.y * 0.5 - edge_size * 0.5)
	if edge_b != null:
		edge_b.position = Vector2(-_wall_size.x * 0.5 + edge_size * 0.5, 0.0) if horizontal else Vector2(0.0, -_wall_size.y * 0.5 + edge_size * 0.5)
	if telegraph_a != null:
		telegraph_a.polygon = wall_poly
		telegraph_a.z_index = -1
	if telegraph_b != null:
		telegraph_b.polygon = wall_poly
		telegraph_b.z_index = -1


func _update_telegraph() -> void:
	var progress: float = clampf(phase_timer / maxf(warning_time, 0.001), 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(phase_timer * 11.0)
	var alpha: float = 0.16 + 0.16 * pulse + 0.10 * progress
	for telegraph: Polygon2D in [telegraph_a, telegraph_b]:
		if telegraph == null:
			continue
		telegraph.visible = true
		telegraph.color = Color(0.62, 0.62, 0.62, alpha)
	if wall_a != null:
		wall_a.modulate = Color(1.0, 1.0, 1.0, 0.42)
	if wall_b != null:
		wall_b.modulate = Color(1.0, 1.0, 1.0, 0.42)
	_wall_a_position(_wall_a_start)
	_wall_b_position(_wall_b_start)


func _update_hold_visual() -> void:
	var pulse: float = 0.5 + 0.5 * sin(phase_timer * 18.0)
	var white: float = clampf(0.82 + 0.18 * pulse + 0.18 * _slam_flash, 0.0, 1.0)
	for wall_visual: Polygon2D in [visual_a, visual_b]:
		if wall_visual != null:
			var body_g: float = 0.08 + 0.14 * _slam_flash
			wall_visual.color = Color(body_g, body_g, body_g, 0.98)
	for wall_edge: Polygon2D in [edge_a, edge_b]:
		if wall_edge != null:
			wall_edge.color = Color(white, white, white, 1.0)


func _update_telegraph_visuals() -> void:
	if telegraph_a != null:
		telegraph_a.position = _wall_a_target
	if telegraph_b != null:
		telegraph_b.position = _wall_b_target


func _enter_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_timer = 0.0
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			_set_damage_enabled(false)
			modulate.a = 1.0
			for wall_node: Node2D in [wall_a, wall_b]:
				if wall_node != null:
					wall_node.visible = false
			_update_telegraph_visuals()
		Phase.CLOSING:
			is_hazard_active = true
			_set_damage_enabled(true)
			for wall_node: Node2D in [wall_a, wall_b]:
				if wall_node != null:
					wall_node.visible = true
					wall_node.modulate = Color.WHITE
			_hide_telegraphs()
			_check_overlap(0.0)
		Phase.HOLD:
			is_hazard_active = true
			_set_damage_enabled(true)
			_hide_telegraphs()
			_slam_flash = 1.0
			slam_count += 1
			wall_slammed.emit(get_gap_center(), wall_axis)
			_check_overlap(0.0)
		Phase.RETRACTING:
			is_hazard_active = false
			_set_damage_enabled(false)
		Phase.FADE_OUT:
			is_hazard_active = false
			_set_damage_enabled(false)
		Phase.DONE, _:
			is_hazard_active = false
			_set_damage_enabled(false)
	queue_redraw()


func _draw() -> void:
	var span_x: float = _arena_size.x
	var span_y: float = _arena_size.y
	var half_gap: float = gap_size * 0.5
	var half_thick: float = wall_thickness * 0.5

	if current_phase == Phase.TELEGRAPH:
		var progress: float = clampf(phase_timer / maxf(warning_time, 0.001), 0.0, 1.0)
		var rail_col: Color = Color(0.88, 0.88, 0.88, 0.32 + 0.48 * progress)
		if wall_axis == WallAxis.HORIZONTAL:
			var left_limit: float = gap_center - half_gap
			var right_limit: float = gap_center + half_gap
			draw_line(Vector2(left_limit, 0.0), Vector2(left_limit, span_y), rail_col, 2.0, true)
			draw_line(Vector2(right_limit, 0.0), Vector2(right_limit, span_y), rail_col, 2.0, true)
			# Inward compression chevrons showing sweep trajectory toward the target bars
			for row: int in range(5):
				var y_pos: float = span_y * (0.16 + 0.17 * float(row))
				var slide_a: float = lerpf(28.0, maxf(32.0, left_limit - 18.0), progress)
				var slide_b: float = lerpf(span_x - 28.0, minf(span_x - 32.0, right_limit + 18.0), progress)
				draw_line(Vector2(slide_a - 10.0, y_pos - 8.0), Vector2(slide_a, y_pos), rail_col, 2.0, true)
				draw_line(Vector2(slide_a - 10.0, y_pos + 8.0), Vector2(slide_a, y_pos), rail_col, 2.0, true)
				draw_line(Vector2(slide_b + 10.0, y_pos - 8.0), Vector2(slide_b, y_pos), rail_col, 2.0, true)
				draw_line(Vector2(slide_b + 10.0, y_pos + 8.0), Vector2(slide_b, y_pos), rail_col, 2.0, true)
		else:
			var top_limit: float = gap_center - half_gap
			var bot_limit: float = gap_center + half_gap
			draw_line(Vector2(0.0, top_limit), Vector2(span_x, top_limit), rail_col, 2.0, true)
			draw_line(Vector2(0.0, bot_limit), Vector2(span_x, bot_limit), rail_col, 2.0, true)
			for col_idx: int in range(6):
				var x_pos: float = span_x * (0.14 + 0.144 * float(col_idx))
				var slide_t: float = lerpf(24.0, maxf(28.0, top_limit - 16.0), progress)
				var slide_b2: float = lerpf(span_y - 24.0, minf(span_y - 28.0, bot_limit + 16.0), progress)
				draw_line(Vector2(x_pos - 8.0, slide_t - 10.0), Vector2(x_pos, slide_t), rail_col, 2.0, true)
				draw_line(Vector2(x_pos + 8.0, slide_t - 10.0), Vector2(x_pos, slide_t), rail_col, 2.0, true)
				draw_line(Vector2(x_pos - 8.0, slide_b2 + 10.0), Vector2(x_pos, slide_b2), rail_col, 2.0, true)
				draw_line(Vector2(x_pos + 8.0, slide_b2 + 10.0), Vector2(x_pos, slide_b2), rail_col, 2.0, true)
		return

	if current_phase in [Phase.CLOSING, Phase.HOLD, Phase.RETRACTING, Phase.FADE_OUT] and wall_a != null and wall_b != null:
		var rib_col: Color = Color(0.45 + 0.35 * _slam_flash, 0.45 + 0.35 * _slam_flash, 0.45 + 0.35 * _slam_flash, 0.78)
		var tooth_col: Color = Color(0.94, 0.94, 0.94, 0.92)
		if wall_axis == WallAxis.HORIZONTAL:
			var a_outer: float = wall_a.global_position.x - half_thick
			var a_inner: float = wall_a.global_position.x + half_thick
			var b_inner: float = wall_b.global_position.x - half_thick
			var b_outer: float = wall_b.global_position.x + half_thick
			for r_idx: int in range(7):
				var ry: float = span_y * (0.08 + 0.14 * float(r_idx))
				if a_inner > 0.0:
					draw_line(Vector2(maxf(0.0, a_outer), ry), Vector2(a_inner, ry), rib_col, 2.0, true)
					draw_line(Vector2(a_inner - 5.0, ry - 5.0), Vector2(a_inner, ry), tooth_col, 2.0, true)
					draw_line(Vector2(a_inner - 5.0, ry + 5.0), Vector2(a_inner, ry), tooth_col, 2.0, true)
				if b_inner < span_x:
					draw_line(Vector2(b_inner, ry), Vector2(minf(span_x, b_outer), ry), rib_col, 2.0, true)
					draw_line(Vector2(b_inner + 5.0, ry - 5.0), Vector2(b_inner, ry), tooth_col, 2.0, true)
					draw_line(Vector2(b_inner + 5.0, ry + 5.0), Vector2(b_inner, ry), tooth_col, 2.0, true)
			if _slam_flash > 0.01:
				var f_col: Color = Color(1.0, 1.0, 1.0, 0.72 * _slam_flash)
				draw_line(Vector2(a_inner, 0.0), Vector2(a_inner, span_y), f_col, 4.0, true)
				draw_line(Vector2(b_inner, 0.0), Vector2(b_inner, span_y), f_col, 4.0, true)
		else:
			var a_outer_y: float = wall_a.global_position.y - half_thick
			var a_inner_y: float = wall_a.global_position.y + half_thick
			var b_inner_y: float = wall_b.global_position.y - half_thick
			var b_outer_y: float = wall_b.global_position.y + half_thick
			for c_idx: int in range(9):
				var cx: float = span_x * (0.06 + 0.11 * float(c_idx))
				if a_inner_y > 0.0:
					draw_line(Vector2(cx, maxf(0.0, a_outer_y)), Vector2(cx, a_inner_y), rib_col, 2.0, true)
					draw_line(Vector2(cx - 5.0, a_inner_y - 5.0), Vector2(cx, a_inner_y), tooth_col, 2.0, true)
					draw_line(Vector2(cx + 5.0, a_inner_y - 5.0), Vector2(cx, a_inner_y), tooth_col, 2.0, true)
				if b_inner_y < span_y:
					draw_line(Vector2(cx, b_inner_y), Vector2(cx, minf(span_y, b_outer_y)), rib_col, 2.0, true)
					draw_line(Vector2(cx - 5.0, b_inner_y + 5.0), Vector2(cx, b_inner_y), tooth_col, 2.0, true)
					draw_line(Vector2(cx + 5.0, b_inner_y + 5.0), Vector2(cx, b_inner_y), tooth_col, 2.0, true)
			if _slam_flash > 0.01:
				var f_col2: Color = Color(1.0, 1.0, 1.0, 0.72 * _slam_flash)
				draw_line(Vector2(0.0, a_inner_y), Vector2(span_x, a_inner_y), f_col2, 4.0, true)
				draw_line(Vector2(0.0, b_inner_y), Vector2(span_x, b_inner_y), f_col2, 4.0, true)


func _hide_telegraphs() -> void:
	for telegraph: Polygon2D in [telegraph_a, telegraph_b]:
		if telegraph != null:
			telegraph.visible = false


func _set_damage_enabled(enabled: bool) -> void:
	if damage_a != null:
		damage_a.monitoring = enabled
		damage_a.monitorable = enabled
	if damage_b != null:
		damage_b.monitoring = enabled
		damage_b.monitorable = enabled
	if damage_shape_a != null:
		damage_shape_a.disabled = not enabled
	if damage_shape_b != null:
		damage_shape_b.disabled = not enabled


func _wall_a_position(position_value: Vector2) -> void:
	if wall_a != null:
		wall_a.global_position = position_value


func _wall_b_position(position_value: Vector2) -> void:
	if wall_b != null:
		wall_b.global_position = position_value


func _check_overlap(delta: float) -> void:
	if delta > 0.0:
		_overlap_timer -= delta
		if _overlap_timer > 0.0:
			return
	_overlap_timer = OVERLAP_CHECK_INTERVAL
	if not is_inside_tree() or not is_hazard_active:
		return
	for damage_area: Area2D in [damage_a, damage_b]:
		if damage_area == null:
			continue
		for body: Node2D in damage_area.get_overlapping_bodies():
			if body.is_in_group("player") and body.has_method("take_damage"):
				body.call("take_damage", 1)
				contact_count += 1
				return


func _on_damage_body_entered(body: Node2D) -> void:
	if not is_hazard_active or body == null:
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.call("take_damage", 1)
		contact_count += 1


func _get_arena_size() -> Vector2:
	if is_inside_tree():
		var rect_size: Vector2 = get_viewport_rect().size
		if rect_size.x > 0.0 and rect_size.y > 0.0:
			return rect_size
	return Vector2(1152.0, 648.0)


## Returns the traversable gap width in pixels.
func get_gap_size() -> float:
	return gap_size


## Returns the current world-space centre of the gap.
func get_gap_center() -> Vector2:
	if wall_axis == WallAxis.HORIZONTAL:
		return Vector2(gap_center, _arena_size.y * 0.5)
	return Vector2(_arena_size.x * 0.5, gap_center)


func _apply_rect_shape(shape_node: CollisionShape2D, size: Vector2) -> void:
	if shape_node == null:
		return
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = size
	shape_node.shape = rect


func _rect_polygon(size: Vector2) -> PackedVector2Array:
	var half: Vector2 = size * 0.5
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])


func _despawn() -> void:
	if is_inside_tree() and not Engine.is_editor_hint():
		queue_free()
	else:
		var parent: Node = get_parent()
		if parent != null:
			parent.remove_child(self)
		queue_free()


func _resolve_nodes() -> void:
	telegraph_a = get_node_or_null("TelegraphA") as Polygon2D
	telegraph_b = get_node_or_null("TelegraphB") as Polygon2D
	wall_a = get_node_or_null("WallA") as AnimatableBody2D
	wall_b = get_node_or_null("WallB") as AnimatableBody2D
	visual_a = get_node_or_null("WallA/Visual") as Polygon2D
	visual_b = get_node_or_null("WallB/Visual") as Polygon2D
	edge_a = get_node_or_null("WallA/Edge") as Polygon2D
	edge_b = get_node_or_null("WallB/Edge") as Polygon2D
	damage_a = get_node_or_null("WallA/DamageArea") as Area2D
	damage_b = get_node_or_null("WallB/DamageArea") as Area2D
	shape_a = get_node_or_null("WallA/CollisionShape2D") as CollisionShape2D
	shape_b = get_node_or_null("WallB/CollisionShape2D") as CollisionShape2D
	damage_shape_a = get_node_or_null("WallA/DamageArea/DamageShape") as CollisionShape2D
	damage_shape_b = get_node_or_null("WallB/DamageArea/DamageShape") as CollisionShape2D
