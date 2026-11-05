extends Area2D

signal bounced(at_position: Vector2, normal: Vector2)

enum SawMode {
	BOUNCE = 0,
	PATROL = 1,
}

enum Phase {
	TELEGRAPH,
	ACTIVE,
	FADE_OUT,
}

const DEFAULT_RADIUS: float = 32.0
const DEFAULT_SPEED: float = 230.0
const DEFAULT_WARNING: float = 0.65
const DEFAULT_LIFETIME: float = 6.0
const MAX_BOUNCES: int = 3

const TELEGRAPH_COLOR: Color = Color(0.30, 0.30, 0.30, 0.42)
const ACTIVE_COLOR: Color = Color(0.96, 0.96, 0.96, 1.0)

var saw_mode: SawMode = SawMode.BOUNCE
var current_phase: Phase = Phase.TELEGRAPH
var phase_timer: float = 0.0
var age: float = 0.0
var lifetime: float = DEFAULT_LIFETIME
var warning_time: float = DEFAULT_WARNING
var fade_time: float = 0.22
var is_hazard_active: bool = false
var saw_radius: float = DEFAULT_RADIUS
var velocity: Vector2 = Vector2.RIGHT
var spin_speed: float = 8.4
var bounces_remaining: int = MAX_BOUNCES
var patrol_base_y: float = 0.0
var _bounce_flash: float = 0.0
var _inner_gear_angle: float = 0.0

@onready var glow: Polygon2D = $Glow
@onready var blade: Polygon2D = $Blade
@onready var hub: Polygon2D = $Hub
@onready var trail: Line2D = $Trail
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


func configure(
	mode: int = SawMode.BOUNCE,
	spawn_pos: Vector2 = Vector2.ZERO,
	direction: Vector2 = Vector2.RIGHT,
	speed: float = DEFAULT_SPEED,
	radius: float = DEFAULT_RADIUS,
	warning: float = DEFAULT_WARNING,
	max_lifetime: float = DEFAULT_LIFETIME
) -> void:
	global_position = spawn_pos
	saw_mode = clampi(mode, 0, 1) as SawMode
	var dir: Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	velocity = dir * maxf(speed, 40.0)
	saw_radius = maxf(radius, 16.0)
	warning_time = maxf(warning, 0.15)
	lifetime = maxf(max_lifetime, warning_time + 0.5)
	patrol_base_y = spawn_pos.y
	age = 0.0
	bounces_remaining = MAX_BOUNCES
	_bounce_flash = 0.0
	_inner_gear_angle = 0.0
	rotation = 0.0
	trail.clear_points()
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)
	queue_redraw()


func _physics_process(delta: float) -> void:
	simulate_physics(delta)


func simulate_physics(delta: float) -> void:
	var safe_delta: float = maxf(delta, 0.0)
	age += safe_delta
	phase_timer += safe_delta
	var spin_mult: float = 0.38 if current_phase == Phase.TELEGRAPH else 1.0
	rotation += spin_speed * safe_delta * spin_mult
	_inner_gear_angle -= spin_speed * 1.45 * safe_delta * spin_mult
	if _bounce_flash > 0.0:
		_bounce_flash = maxf(0.0, _bounce_flash - safe_delta * 4.5)

	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(warning_time, 0.001), 0.0, 1.0)
			var pulse: float = 0.5 + 0.5 * sin(progress * TAU * 2.5)
			scale = Vector2.ONE * lerpf(0.72, 1.0, ease(progress, 0.65))
			var gray: float = lerpf(0.36, 0.68, pulse)
			blade.color = Color(gray, gray, gray, 0.9)
			glow.color = Color(0.38, 0.38, 0.38, 0.14 + 0.16 * pulse)
			if phase_timer >= warning_time:
				_enter_phase(Phase.ACTIVE)
		Phase.ACTIVE:
			_update_active_motion(safe_delta)
			scale = Vector2.ONE * (1.0 + 0.14 * _bounce_flash)
			_check_player_overlap()
			if age >= lifetime:
				_enter_phase(Phase.FADE_OUT)
		Phase.FADE_OUT:
			var progress: float = clampf(phase_timer / maxf(fade_time, 0.001), 0.0, 1.0)
			scale = Vector2.ONE * lerpf(1.0, 0.25, progress)
			modulate.a = 1.0 - progress
			if phase_timer >= fade_time:
				queue_free()

	if trail.visible:
		trail.add_point(global_position)
		if trail.get_point_count() > 11:
			trail.remove_point(0)
	queue_redraw()


func _update_active_motion(delta: float) -> void:
	global_position += velocity * delta
	var arena: Vector2 = get_viewport_rect().size
	if arena.x <= 0.0 or arena.y <= 0.0:
		arena = Vector2(1152.0, 648.0)
	var margin: float = saw_radius + 4.0

	if saw_mode == SawMode.PATROL:
		var patrol_bounced: bool = false
		var patrol_normal: Vector2 = Vector2.ZERO
		if global_position.x < margin and velocity.x < 0.0:
			global_position.x = margin
			velocity.x = -velocity.x
			patrol_bounced = true
			patrol_normal = Vector2.RIGHT
		elif global_position.x > arena.x - margin and velocity.x > 0.0:
			global_position.x = arena.x - margin
			velocity.x = -velocity.x
			patrol_bounced = true
			patrol_normal = Vector2.LEFT
		global_position.y = patrol_base_y + sin(age * 2.6) * 28.0
		if patrol_bounced:
			_bounce_flash = 0.85
			bounced.emit(global_position, patrol_normal)
		return

	var did_bounce: bool = false
	var bounce_normal: Vector2 = Vector2.ZERO
	if global_position.x < margin and velocity.x < 0.0:
		global_position.x = margin
		velocity.x = -velocity.x
		did_bounce = true
		bounce_normal += Vector2.RIGHT
	elif global_position.x > arena.x - margin and velocity.x > 0.0:
		global_position.x = arena.x - margin
		velocity.x = -velocity.x
		did_bounce = true
		bounce_normal += Vector2.LEFT
	if global_position.y < margin and velocity.y < 0.0:
		global_position.y = margin
		velocity.y = -velocity.y
		did_bounce = true
		bounce_normal += Vector2.DOWN
	elif global_position.y > arena.y - margin and velocity.y > 0.0:
		global_position.y = arena.y - margin
		velocity.y = -velocity.y
		did_bounce = true
		bounce_normal += Vector2.UP

	if did_bounce:
		bounces_remaining -= 1
		_bounce_flash = 1.0
		bounced.emit(global_position, bounce_normal.normalized() if bounce_normal.length_squared() > 0.001 else Vector2.UP)
		if bounces_remaining <= 0:
			_enter_phase(Phase.FADE_OUT)


func _enter_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_timer = 0.0
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			collision_shape.disabled = true
			glow.color = TELEGRAPH_COLOR
			blade.color = Color(0.36, 0.36, 0.36, 0.85)
			hub.color = Color(0.12, 0.12, 0.12, 0.92)
			trail.visible = false
			scale = Vector2.ONE * 0.72
			modulate.a = 1.0
		Phase.ACTIVE:
			is_hazard_active = true
			scale = Vector2.ONE
			modulate.a = 1.0
			collision_shape.disabled = false
			glow.color = Color(0.65, 0.65, 0.65, 0.18)
			blade.color = ACTIVE_COLOR
			hub.color = Color(0.08, 0.08, 0.08, 1.0)
			trail.visible = true
			_check_player_overlap()
		Phase.FADE_OUT:
			is_hazard_active = false
			collision_shape.disabled = true
			trail.visible = false
	queue_redraw()


func _rebuild_geometry() -> void:
	var r: float = saw_radius
	glow.polygon = Shapes.circle(r * 1.24, 28)
	blade.polygon = Shapes.saw(r, 16, 0.70)
	hub.polygon = Shapes.circle(r * 0.48, 20)
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = r * 0.92
	collision_shape.shape = circle


func _draw() -> void:
	var r: float = saw_radius
	var inv_scale: float = 1.0 / maxf(scale.x, 0.25)

	var inner_col: Color = Color(0.92, 0.92, 0.92, 0.92 if current_phase == Phase.ACTIVE else 0.55)
	draw_arc(Vector2.ZERO, r * 0.34, 0.0, TAU, 24, inner_col, 1.8, true)
	for i: int in range(6):
		var spoke_ang: float = _inner_gear_angle + TAU * float(i) / 6.0
		var d: Vector2 = Vector2.from_angle(spoke_ang)
		draw_line(d * (r * 0.14), d * (r * 0.34), inner_col, 1.8, true)
	draw_circle(Vector2.ZERO, r * 0.13, Color(1.0, 1.0, 1.0, 0.95 if current_phase == Phase.ACTIVE else 0.6))

	if saw_mode == SawMode.BOUNCE and current_phase == Phase.ACTIVE:
		for b_idx: int in range(maxi(bounces_remaining, 0)):
			var pip_ang: float = _inner_gear_angle + TAU * float(b_idx) / float(MAX_BOUNCES)
			draw_circle(Vector2.from_angle(pip_ang) * (r * 0.56), 2.4, Color(0.10, 0.10, 0.10, 0.95))

	if _bounce_flash > 0.01:
		var flash_r: float = lerpf(r * 1.05, r * 1.55, 1.0 - _bounce_flash)
		draw_arc(Vector2.ZERO, flash_r, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.78 * _bounce_flash), 2.5, true)

	if current_phase == Phase.TELEGRAPH:
		var progress: float = clampf(phase_timer / maxf(warning_time, 0.001), 0.0, 1.0)
		var ring_col: Color = Color(0.84, 0.84, 0.84, 0.36 + 0.44 * progress)
		draw_arc(Vector2.ZERO, r * inv_scale * 1.12, 0.0, TAU, 36, ring_col, 1.8 * inv_scale, true)
		var move_dir: Vector2 = (velocity.normalized() if velocity.length_squared() > 0.001 else Vector2.RIGHT).rotated(-rotation)
		var perp: Vector2 = Vector2(-move_dir.y, move_dir.x)
		var arrow_start: Vector2 = move_dir * (r * 1.18 * inv_scale)
		var arrow_len: float = (62.0 + 26.0 * progress) * inv_scale
		var arrow_tip: Vector2 = arrow_start + move_dir * arrow_len
		draw_line(arrow_start, arrow_tip, ring_col, 2.2 * inv_scale, true)
		draw_line(arrow_tip, arrow_tip - move_dir * (12.0 * inv_scale) + perp * (8.0 * inv_scale), ring_col, 2.2 * inv_scale, true)
		draw_line(arrow_tip, arrow_tip - move_dir * (12.0 * inv_scale) - perp * (8.0 * inv_scale), ring_col, 2.2 * inv_scale, true)


func _check_player_overlap() -> void:
	if not is_hazard_active:
		return
	for body: Node2D in get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(1)
			return


func _on_body_entered(body: Node2D) -> void:
	if is_hazard_active and body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(1)
