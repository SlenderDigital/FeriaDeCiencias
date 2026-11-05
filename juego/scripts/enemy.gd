extends Area2D

signal fire_projectile(origin: Vector2, direction: Vector2, speed: float, radius: float)
signal enemy_lunged(origin: Vector2, direction: Vector2)
signal enemy_despawned(origin: Vector2)

enum EnemyType {
	CHASER = 0,
	TURRET = 1,
	ORBITER = 2,
	PULSAR = 3,
}

enum Phase {
	SPAWN,
	ACTIVE,
	FADE_OUT,
}

enum ChaserState {
	CHASE,
	WINDUP,
	LUNGE,
}

const CHASER_RADIUS: float = 22.0
const TURRET_RADIUS: float = 25.0
const ORBITER_RADIUS: float = 21.0
const PULSAR_RADIUS: float = 23.0
const CHASER_CHASE_SPEED: float = 126.0
const CHASER_LUNGE_SPEED: float = 490.0
const ORBITER_RADIUS_DISTANCE: float = 168.0
const ORBITER_ANGULAR_SPEED: float = 1.32
const ORBITER_FIRE_INTERVAL: float = 1.85
const ORBITER_AIM_TIME: float = 0.42
const TURRET_FIRE_INTERVAL: float = 2.15
const TURRET_AIM_TIME: float = 0.55
const PULSAR_MOVE_SPEED: float = 135.0
const PULSAR_FIRE_INTERVAL: float = 2.05
const PULSAR_AIM_TIME: float = 0.52
const CONTACT_CHECK_INTERVAL: float = 0.12
const FADE_TIME: float = 0.24
const DEFAULT_WARNING: float = 0.85
const DEFAULT_LIFETIME: float = 7.0
const PROJECTILE_SPAWN_RADIUS: float = 28.0

var enemy_type: int = EnemyType.CHASER
var current_phase: Phase = Phase.SPAWN
var phase_timer: float = 0.0
var age: float = 0.0
var lifetime: float = DEFAULT_LIFETIME
var warning_time: float = DEFAULT_WARNING
var speed_scale: float = 1.0
var is_hazard_active: bool = false
var target_node: Node2D = null

var _target_position: Vector2 = Vector2.ZERO
var _chaser_state: ChaserState = ChaserState.CHASE
var _lunge_cooldown: float = 0.0
var _lunge_direction: Vector2 = Vector2.RIGHT
var _fire_timer: float = 0.0
var _volley_count: int = 0
var _orbiter_fire_timer: float = ORBITER_FIRE_INTERVAL
var _orbit_center: Vector2 = Vector2.ZERO
var _orbit_angle: float = 0.0
var _orbit_radius: float = ORBITER_RADIUS_DISTANCE
var _contact_check_timer: float = 0.0
var _arena_size: Vector2 = Vector2(1152.0, 648.0)
var _recoil: float = 0.0
var _afterimages: Array[Dictionary] = []
var _afterimage_timer: float = 0.0

@onready var outer_polygon: Polygon2D = $OuterPolygon
@onready var void_polygon: Polygon2D = $VoidPolygon
@onready var core_polygon: Polygon2D = $CorePolygon
@onready var aim_line: Line2D = $AimLine
@onready var trail: Line2D = $Trail
@onready var ring: Line2D = $Ring
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_arena_size = _get_arena_size()
	body_entered.connect(_on_body_entered)
	_build_visual()
	_enter_phase(Phase.SPAWN)


func configure_enemy(
	type: int = EnemyType.CHASER,
	spawn_pos: Vector2 = Vector2.ZERO,
	target: Node2D = null,
	requested_speed_scale: float = 1.0,
	warning: float = DEFAULT_WARNING,
	max_lifetime: float = DEFAULT_LIFETIME
) -> void:
	_arena_size = _get_arena_size()
	enemy_type = clampi(type, EnemyType.CHASER, EnemyType.PULSAR)
	global_position = spawn_pos
	target_node = target
	speed_scale = clampf(requested_speed_scale, 0.75, 1.45)
	warning_time = maxf(warning, 0.35)
	lifetime = maxf(max_lifetime, warning_time + 1.0)
	age = 0.0
	phase_timer = 0.0
	_volley_count = 0
	_recoil = 0.0
	_afterimages.clear()
	_afterimage_timer = 0.0
	_chaser_state = ChaserState.CHASE
	_lunge_cooldown = 0.85
	_fire_timer = 0.95
	_orbiter_fire_timer = ORBITER_FIRE_INTERVAL
	_target_position = _get_target_position()
	_orbit_center = _target_position
	_orbit_angle = (global_position - _orbit_center).angle()
	_orbit_radius = clampf(global_position.distance_to(_orbit_center), 150.0, 280.0)

	if enemy_type == EnemyType.TURRET:
		_fire_timer = 1.05
		rotation = 0.0
	elif enemy_type == EnemyType.PULSAR:
		_fire_timer = 1.10
		rotation = (_target_position - global_position).angle()
	else:
		rotation = (_target_position - global_position).angle()

	trail.clear_points()
	visible = true
	modulate = Color.WHITE
	scale = Vector2.ONE * 0.45
	_build_visual()
	_enter_phase(Phase.SPAWN)
	queue_redraw()


func set_target_node(target: Node2D) -> void:
	target_node = target
	_target_position = _get_target_position()


func _physics_process(delta: float) -> void:
	simulate_physics(delta)


func simulate_physics(delta: float) -> void:
	var safe_delta: float = maxf(delta, 0.0)
	phase_timer += safe_delta
	age += safe_delta
	if _recoil > 0.0:
		_recoil = maxf(0.0, _recoil - safe_delta * 4.2)

	for i: int in range(_afterimages.size() - 1, -1, -1):
		_afterimages[i]["life"] = float(_afterimages[i]["life"]) - safe_delta
		if float(_afterimages[i]["life"]) <= 0.0:
			_afterimages.remove_at(i)

	if target_node != null and is_instance_valid(target_node):
		_target_position = target_node.global_position

	match current_phase:
		Phase.SPAWN:
			var progress: float = clampf(phase_timer / maxf(warning_time, 0.001), 0.0, 1.0)
			var pulse: float = 0.5 + 0.5 * sin(progress * TAU * 3.0)
			scale = Vector2.ONE * lerpf(0.45, 1.0, ease(progress, 0.65))
			modulate.a = 0.52 + 0.42 * pulse
			aim_line.visible = false
			if phase_timer >= warning_time:
				_enter_phase(Phase.ACTIVE)
		Phase.ACTIVE:
			match enemy_type:
				EnemyType.CHASER:
					_simulate_chaser(safe_delta)
				EnemyType.TURRET:
					_simulate_turret(safe_delta)
				EnemyType.ORBITER:
					_simulate_orbiter(safe_delta)
				EnemyType.PULSAR:
					_simulate_pulsar(safe_delta)
			_check_contact(safe_delta)
			if age >= lifetime:
				_enter_phase(Phase.FADE_OUT)
		Phase.FADE_OUT:
			var progress: float = clampf(phase_timer / FADE_TIME, 0.0, 1.0)
			modulate.a = 1.0 - progress
			scale = Vector2.ONE * lerpf(1.0, 0.25, progress)
			if progress >= 1.0:
				enemy_despawned.emit(global_position)
				queue_free()

	trail.visible = current_phase == Phase.ACTIVE and enemy_type != EnemyType.TURRET
	if trail.visible:
		trail.add_point(global_position)
		var max_pts: int = 14 if (enemy_type == EnemyType.CHASER and _chaser_state == ChaserState.LUNGE) else 10
		while trail.get_point_count() > max_pts:
			trail.remove_point(0)

	_update_core_motion(safe_delta)
	queue_redraw()


func _simulate_chaser(delta: float) -> void:
	match _chaser_state:
		ChaserState.CHASE:
			_lunge_cooldown = maxf(0.0, _lunge_cooldown - delta)
			var to_target: Vector2 = _target_position - global_position
			var distance: float = to_target.length()
			var dir: Vector2 = to_target.normalized() if distance > 0.001 else Vector2.RIGHT
			var perp: Vector2 = Vector2(-dir.y, dir.x) * sin(age * 6.5) * 22.0
			var desired: Vector2 = (dir * CHASER_CHASE_SPEED + perp) * speed_scale if distance > 6.0 else Vector2.ZERO
			global_position += desired * delta
			if distance > 0.001:
				rotation = lerp_angle(rotation, dir.angle(), minf(9.5 * delta, 1.0))
			scale = scale.move_toward(Vector2.ONE, delta * 6.0)
			aim_line.visible = false
			if _lunge_cooldown <= 0.0 and distance < 540.0:
				_chaser_state = ChaserState.WINDUP
				phase_timer = 0.0
				_lunge_direction = dir
		ChaserState.WINDUP:
			var windup_duration: float = 0.44 / maxf(speed_scale, 0.75)
			var progress: float = clampf(phase_timer / maxf(windup_duration, 0.001), 0.0, 1.0)
			if progress < 0.65:
				var to_target_w: Vector2 = _target_position - global_position
				if to_target_w.length_squared() > 1.0:
					_lunge_direction = _lunge_direction.lerp(to_target_w.normalized(), minf(delta * 6.0, 1.0)).normalized()
					rotation = _lunge_direction.angle()
			global_position -= _lunge_direction * 24.0 * (1.0 - progress) * delta
			scale = Vector2(lerpf(1.0, 0.80, progress), lerpf(1.0, 1.24, progress))
			core_polygon.scale = Vector2.ONE * (1.0 + 0.42 * progress)
			outer_polygon.color = Color(0.98, 0.98, 0.98, 1.0)
			aim_line.visible = true
			var local_lunge: Vector2 = _lunge_direction.rotated(-rotation)
			var lunge_reach: float = CHASER_LUNGE_SPEED * speed_scale * 0.26
			aim_line.points = PackedVector2Array([Vector2.ZERO, local_lunge * lunge_reach])
			var line_gray: float = lerpf(0.58, 0.96, progress)
			aim_line.default_color = Color(line_gray, line_gray, line_gray, lerpf(0.48, 0.88, progress))
			if phase_timer >= windup_duration:
				_chaser_state = ChaserState.LUNGE
				phase_timer = 0.0
				rotation = _lunge_direction.angle()
				_recoil = 0.85
				enemy_lunged.emit(global_position, _lunge_direction)
		ChaserState.LUNGE:
			var lunge_duration: float = 0.26
			var progress_l: float = clampf(phase_timer / lunge_duration, 0.0, 1.0)
			var burst_curve: float = 1.18 - 0.35 * progress_l
			global_position += _lunge_direction * CHASER_LUNGE_SPEED * speed_scale * burst_curve * delta
			scale = Vector2(lerpf(1.34, 1.0, progress_l), lerpf(0.74, 1.0, progress_l))
			aim_line.visible = false
			_afterimage_timer -= delta
			if _afterimage_timer <= 0.0:
				_afterimage_timer = 0.042
				_afterimages.append({"pos": global_position, "rot": rotation, "life": 0.18, "max_life": 0.18})
			if phase_timer >= lunge_duration:
				_chaser_state = ChaserState.CHASE
				_lunge_cooldown = 1.95 / maxf(speed_scale, 0.75)
				phase_timer = 0.0
	_constrain_to_arena(CHASER_RADIUS + 4.0)


func _simulate_turret(delta: float) -> void:
	var to_target: Vector2 = _target_position - global_position
	var aim_dir: Vector2 = to_target.normalized() if to_target.length_squared() > 0.001 else Vector2.DOWN
	global_position += Vector2(cos(age * 1.9), sin(age * 2.5)) * 10.0 * delta
	_constrain_to_arena(TURRET_RADIUS + 6.0)
	_fire_timer -= delta
	if _fire_timer <= TURRET_AIM_TIME:
		var aim_len: float = minf(to_target.length(), 460.0) if to_target.length_squared() > 1.0 else 320.0
		_set_aim_line(aim_dir, aim_len, 1.0 - _fire_timer / TURRET_AIM_TIME)
	else:
		aim_line.visible = false
	if _fire_timer <= 0.0:
		_fire_timer = TURRET_FIRE_INTERVAL / maxf(speed_scale, 0.75)
		var spread: float = 0.20 if _volley_count % 2 == 0 else 0.12
		var proj_speed: float = (300.0 if _volley_count % 2 == 0 else 345.0) * speed_scale
		for offset: float in [-spread, 0.0, spread]:
			var dir: Vector2 = aim_dir.rotated(offset)
			fire_projectile.emit(global_position + dir * PROJECTILE_SPAWN_RADIUS, dir, proj_speed, 8.5)
		_volley_count += 1
		_recoil = 1.0
		core_polygon.scale = Vector2.ONE * 1.42


func _simulate_orbiter(delta: float) -> void:
	_orbit_center = _orbit_center.move_toward(_target_position, 82.0 * delta)
	_orbit_radius = move_toward(_orbit_radius, ORBITER_RADIUS_DISTANCE, 46.0 * delta)
	_orbit_angle += ORBITER_ANGULAR_SPEED * speed_scale * delta
	var radius_pulse: float = clampf(_orbit_radius * (1.0 + 0.10 * sin(age * 2.4)), 125.0, 290.0)
	global_position = _orbit_center + Vector2.from_angle(_orbit_angle) * radius_pulse
	_constrain_to_arena(ORBITER_RADIUS + 6.0)
	rotation += 2.1 * delta

	_orbiter_fire_timer -= delta
	var to_target: Vector2 = _target_position - global_position
	var inward_dir: Vector2 = to_target.normalized() if to_target.length_squared() > 0.001 else Vector2.from_angle(_orbit_angle + PI)
	if _orbiter_fire_timer <= ORBITER_AIM_TIME:
		_set_aim_line(inward_dir, minf(to_target.length(), 220.0), 1.0 - _orbiter_fire_timer / ORBITER_AIM_TIME)
	else:
		aim_line.visible = false

	if _orbiter_fire_timer <= 0.0:
		_orbiter_fire_timer = ORBITER_FIRE_INTERVAL / maxf(speed_scale, 0.75)
		fire_projectile.emit(global_position + inward_dir * (ORBITER_RADIUS + 6.0), inward_dir, 285.0 * speed_scale, 8.0)
		_recoil = 0.75
		core_polygon.scale = Vector2.ONE * 1.35


func _simulate_pulsar(delta: float) -> void:
	var to_target: Vector2 = _target_position - global_position
	var dist: float = to_target.length()
	var dir: Vector2 = to_target.normalized() if dist > 0.001 else Vector2.RIGHT
	var tangent: Vector2 = Vector2(-dir.y, dir.x)
	var radial_push: float = -0.85 if dist < 210.0 else (0.75 if dist > 310.0 else 0.0)
	var move_vec: Vector2 = (tangent * 0.85 + dir * radial_push).normalized() * PULSAR_MOVE_SPEED * speed_scale
	if _fire_timer > PULSAR_AIM_TIME * 0.65:
		global_position += move_vec * delta
	_constrain_to_arena(PULSAR_RADIUS + 6.0)
	rotation = lerp_angle(rotation, dir.angle(), minf(8.0 * delta, 1.0))

	_fire_timer -= delta
	if _fire_timer <= PULSAR_AIM_TIME:
		var aim_progress: float = clampf(1.0 - _fire_timer / PULSAR_AIM_TIME, 0.0, 1.0)
		_set_aim_line(dir, minf(maxf(dist, 240.0), 520.0), aim_progress)
		core_polygon.scale = Vector2.ONE * (1.0 + 0.35 * aim_progress)
	else:
		aim_line.visible = false

	if _fire_timer <= 0.0:
		_fire_timer = PULSAR_FIRE_INTERVAL / maxf(speed_scale, 0.75)
		fire_projectile.emit(global_position + dir * PROJECTILE_SPAWN_RADIUS, dir, 410.0 * speed_scale, 9.0)
		fire_projectile.emit(global_position + dir.rotated(-0.26) * PROJECTILE_SPAWN_RADIUS, dir.rotated(-0.26), 310.0 * speed_scale, 7.5)
		fire_projectile.emit(global_position + dir.rotated(0.26) * PROJECTILE_SPAWN_RADIUS, dir.rotated(0.26), 310.0 * speed_scale, 7.5)
		_recoil = 1.0
		core_polygon.scale = Vector2.ONE * 1.45


func _set_aim_line(world_dir: Vector2, length: float, raw_progress: float) -> void:
	aim_line.visible = true
	var aim_progress: float = clampf(raw_progress, 0.0, 1.0)
	aim_line.points = PackedVector2Array([Vector2.ZERO, world_dir.rotated(-rotation) * length])
	var g: float = 0.56 + 0.40 * aim_progress
	aim_line.default_color = Color(g, g, g, 0.45 + 0.45 * aim_progress)


func _enter_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_timer = 0.0
	match new_phase:
		Phase.SPAWN:
			is_hazard_active = false
			collision_shape.disabled = true
			scale = Vector2.ONE * 0.45
			modulate = Color(1.0, 1.0, 1.0, 0.52)
			aim_line.visible = false
			outer_polygon.color = Color(0.52, 0.52, 0.52, 0.9)
			void_polygon.color = Color(0.08, 0.08, 0.08, 0.9)
			core_polygon.color = Color(0.78, 0.78, 0.78, 0.9)
			ring.visible = false
		Phase.ACTIVE:
			is_hazard_active = true
			scale = Vector2.ONE
			modulate = Color.WHITE
			collision_shape.disabled = false
			outer_polygon.color = Color(0.92, 0.92, 0.92, 1.0)
			void_polygon.color = Color(0.06, 0.06, 0.06, 1.0)
			core_polygon.color = Color.WHITE
			ring.visible = enemy_type == EnemyType.ORBITER or enemy_type == EnemyType.PULSAR
			_chaser_state = ChaserState.CHASE
			_lunge_cooldown = 1.0
		Phase.FADE_OUT:
			is_hazard_active = false
			collision_shape.disabled = true
			aim_line.visible = false
			ring.visible = false
	queue_redraw()


func _update_core_motion(delta: float) -> void:
	if current_phase != Phase.ACTIVE:
		return
	match enemy_type:
		EnemyType.TURRET:
			core_polygon.rotation += 2.1 * delta
			void_polygon.rotation -= 1.0 * delta
			outer_polygon.rotation -= 0.75 * delta
			core_polygon.scale = core_polygon.scale.move_toward(Vector2.ONE, delta * 3.2)
			scale = Vector2.ONE * (1.0 - 0.08 * _recoil)
		EnemyType.ORBITER:
			core_polygon.rotation -= 2.8 * delta
			void_polygon.rotation += 1.4 * delta
			outer_polygon.rotation += 1.4 * delta
			ring.rotation += 2.4 * delta
			core_polygon.scale = core_polygon.scale.move_toward(Vector2.ONE, delta * 3.5)
		EnemyType.PULSAR:
			core_polygon.rotation += 3.2 * delta
			void_polygon.rotation -= 1.6 * delta
			ring.rotation -= 2.0 * delta
			core_polygon.scale = core_polygon.scale.move_toward(Vector2.ONE, delta * 3.5)
			scale = Vector2.ONE * (1.0 - 0.07 * _recoil)
		EnemyType.CHASER:
			core_polygon.rotation += 1.4 * delta
			core_polygon.scale = core_polygon.scale.move_toward(Vector2.ONE, delta * 4.2)


func _build_visual() -> void:
	var radius: float = _get_radius_for_type()
	match enemy_type:
		EnemyType.TURRET:
			outer_polygon.polygon = Shapes.star(radius, radius * 0.84, 6)
			void_polygon.polygon = Shapes.circle(radius * 0.66, 6)
			core_polygon.polygon = Shapes.swept_triangle(radius * 0.44)
		EnemyType.ORBITER:
			outer_polygon.polygon = Shapes.star(radius, radius * 0.54, 4)
			void_polygon.polygon = Shapes.diamond(radius * 0.62)
			core_polygon.polygon = Shapes.diamond(radius * 0.38)
		EnemyType.PULSAR:
			outer_polygon.polygon = Shapes.star(radius, radius * 0.48, 8)
			void_polygon.polygon = Shapes.circle(radius * 0.56, 8)
			core_polygon.polygon = Shapes.diamond(radius * 0.40)
		_:
			outer_polygon.polygon = Shapes.swept_triangle(radius)
			void_polygon.polygon = Shapes.swept_triangle(radius * 0.66)
			core_polygon.polygon = Shapes.swept_triangle(radius * 0.42)

	var ring_radius: float = radius * (1.85 if enemy_type == EnemyType.ORBITER else 1.55)
	ring.points = Shapes.circle(ring_radius, 24)

	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius * 0.92
	collision_shape.shape = circle


func _draw() -> void:
	var radius: float = _get_radius_for_type()
	var inv_scale: float = 1.0 / maxf(scale.x, 0.25)
	var aura_alpha: float = 0.22 if current_phase == Phase.ACTIVE else 0.10
	draw_arc(Vector2.ZERO, radius * 1.24, 0.0, TAU, 32, Color(0.88, 0.88, 0.88, aura_alpha), 1.6, true)

	if current_phase == Phase.SPAWN:
		var progress: float = clampf(phase_timer / maxf(warning_time, 0.001), 0.0, 1.0)
		var outer_r: float = lerpf(radius * 2.1, radius * 1.05, progress) * inv_scale
		var reticle_col: Color = Color(0.78, 0.78, 0.78, 0.35 + 0.45 * progress)
		draw_arc(Vector2.ZERO, outer_r, 0.0, TAU, 36, reticle_col, 1.6 * inv_scale, true)
		draw_arc(Vector2.ZERO, radius * inv_scale, 0.0, TAU * progress, 32, Color(0.95, 0.95, 0.95, 0.75), 2.2 * inv_scale, true)
		for i: int in range(4):
			var dir: Vector2 = Vector2.from_angle(TAU * 0.25 * float(i) + progress * PI * 0.5)
			draw_line(dir * (outer_r - 5.0 * inv_scale), dir * (outer_r + 6.0 * inv_scale), reticle_col, 2.0 * inv_scale, true)
		return

	if current_phase != Phase.ACTIVE:
		return

	match enemy_type:
		EnemyType.CHASER:
			for ghost: Dictionary in _afterimages:
				var life_ratio: float = clampf(float(ghost["life"]) / maxf(float(ghost["max_life"]), 0.001), 0.0, 1.0)
				var world_offset: Vector2 = Vector2(ghost["pos"]) - global_position
				var local_pos: Vector2 = world_offset.rotated(-rotation) / Vector2(maxf(scale.x, 0.2), maxf(scale.y, 0.2))
				var ghost_poly: PackedVector2Array = Shapes.swept_triangle(radius * (0.72 + 0.22 * life_ratio))
				for i: int in range(ghost_poly.size()):
					ghost_poly[i] = ghost_poly[i] + local_pos
				draw_colored_polygon(ghost_poly, Color(0.88, 0.88, 0.88, 0.28 * life_ratio))

			var thrust_len: float = radius * (0.95 if _chaser_state == ChaserState.LUNGE else 0.45 + 0.15 * sin(age * 24.0))
			var flame_pts: PackedVector2Array = PackedVector2Array([
				Vector2(-radius * 0.62, -radius * 0.24),
				Vector2(-radius * 0.62 - thrust_len, 0.0),
				Vector2(-radius * 0.62, radius * 0.24),
			])
			draw_colored_polygon(flame_pts, Color(0.95, 0.95, 0.95, 0.72 if _chaser_state == ChaserState.LUNGE else 0.42))

			if _chaser_state == ChaserState.WINDUP:
				var windup_duration: float = 0.44 / maxf(speed_scale, 0.75)
				var progress: float = clampf(phase_timer / maxf(windup_duration, 0.001), 0.0, 1.0)
				var local_dir: Vector2 = _lunge_direction.rotated(-rotation)
				var perp: Vector2 = Vector2(-local_dir.y, local_dir.x)
				var reach: float = CHASER_LUNGE_SPEED * speed_scale * 0.26
				var rail_half: float = lerpf(radius * 0.95, radius * 0.48, progress)
				var rail_col: Color = Color(0.85, 0.85, 0.85, 0.28 + 0.42 * progress)
				draw_line(perp * rail_half, local_dir * reach + perp * rail_half, rail_col, 1.5, true)
				draw_line(-perp * rail_half, local_dir * reach - perp * rail_half, rail_col, 1.5, true)
				var tip: Vector2 = local_dir * reach
				draw_line(tip, tip - local_dir * 14.0 + perp * 10.0, Color(0.96, 0.96, 0.96, 0.82), 2.2, true)
				draw_line(tip, tip - local_dir * 14.0 - perp * 10.0, Color(0.96, 0.96, 0.96, 0.82), 2.2, true)
				draw_arc(Vector2.ZERO, lerpf(radius * 1.75, radius * 1.05, progress), 0.0, TAU, 28, rail_col, 2.0, true)

		EnemyType.TURRET:
			var ring_r: float = radius * 1.34
			draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 36, Color(0.62, 0.62, 0.62, 0.38), 1.5, true)
			for i: int in range(6):
				var d: Vector2 = Vector2.from_angle(outer_polygon.rotation + TAU * float(i) / 6.0)
				draw_line(d * (ring_r - 3.5), d * (ring_r + 4.5), Color(0.88, 0.88, 0.88, 0.65), 2.0, true)
			if _fire_timer <= TURRET_AIM_TIME:
				var aim_progress: float = clampf(1.0 - _fire_timer / TURRET_AIM_TIME, 0.0, 1.0)
				var to_target: Vector2 = _target_position - global_position
				var aim_dir: Vector2 = (to_target.normalized() if to_target.length_squared() > 0.001 else Vector2.DOWN).rotated(-rotation)
				var spread: float = 0.20 if _volley_count % 2 == 0 else 0.12
				var ray_len: float = minf(maxf(to_target.length(), 220.0), 420.0)
				var side_col: Color = Color(0.78, 0.78, 0.78, 0.25 + 0.45 * aim_progress)
				for side_offset: float in [-spread, spread]:
					var s_dir: Vector2 = aim_dir.rotated(side_offset)
					draw_line(s_dir * PROJECTILE_SPAWN_RADIUS, s_dir * ray_len, side_col, 1.6, true)
					draw_circle(s_dir * PROJECTILE_SPAWN_RADIUS, 3.2 + 2.0 * aim_progress, Color(0.95, 0.95, 0.95, 0.75 * aim_progress))
				draw_circle(aim_dir * PROJECTILE_SPAWN_RADIUS, 3.8 + 2.2 * aim_progress, Color(1.0, 1.0, 1.0, 0.85 * aim_progress))
				draw_arc(Vector2.ZERO, lerpf(radius * 1.85, radius * 1.02, aim_progress), 0.0, TAU, 32, Color(0.95, 0.95, 0.95, 0.35 + 0.5 * aim_progress), 2.0, true)

		EnemyType.ORBITER:
			var sat_orbit_r: float = radius * 1.85
			for i: int in range(3):
				var sat_ang: float = ring.rotation + TAU * float(i) / 3.0
				var sat_pos: Vector2 = Vector2.from_angle(sat_ang) * sat_orbit_r
				var tangent: Vector2 = Vector2(-sin(sat_ang), cos(sat_ang))
				var normal: Vector2 = Vector2.from_angle(sat_ang)
				draw_colored_polygon(PackedVector2Array([
					sat_pos + tangent * 7.5,
					sat_pos + normal * 4.2,
					sat_pos - tangent * 7.5,
					sat_pos - normal * 4.2,
				]), Color(0.94, 0.94, 0.94, 0.92))
			if _orbiter_fire_timer <= ORBITER_AIM_TIME:
				var aim_p: float = clampf(1.0 - _orbiter_fire_timer / ORBITER_AIM_TIME, 0.0, 1.0)
				draw_arc(Vector2.ZERO, lerpf(sat_orbit_r, radius, aim_p), 0.0, TAU, 24, Color(0.95, 0.95, 0.95, 0.55 * aim_p), 2.0, true)

		EnemyType.PULSAR:
			draw_arc(Vector2.ZERO, radius * 1.25, age * 2.0, age * 2.0 + PI * 1.4, 24, Color(0.82, 0.82, 0.82, 0.55), 1.8, true)
			if _fire_timer <= PULSAR_AIM_TIME:
				var aim_p: float = clampf(1.0 - _fire_timer / PULSAR_AIM_TIME, 0.0, 1.0)
				var to_target: Vector2 = _target_position - global_position
				var aim_dir: Vector2 = (to_target.normalized() if to_target.length_squared() > 0.001 else Vector2.RIGHT).rotated(-rotation)
				var flank_col: Color = Color(0.75, 0.75, 0.75, 0.30 + 0.40 * aim_p)
				for off: float in [-0.26, 0.26]:
					var f_dir: Vector2 = aim_dir.rotated(off)
					draw_line(f_dir * PROJECTILE_SPAWN_RADIUS, f_dir * 210.0, flank_col, 1.4, true)
				draw_arc(Vector2.ZERO, lerpf(radius * 1.9, radius * 0.95, aim_p), 0.0, TAU, 28, Color(0.98, 0.98, 0.98, 0.4 + 0.5 * aim_p), 2.2, true)


func _get_radius_for_type() -> float:
	match enemy_type:
		EnemyType.TURRET:
			return TURRET_RADIUS
		EnemyType.ORBITER:
			return ORBITER_RADIUS
		EnemyType.PULSAR:
			return PULSAR_RADIUS
		_:
			return CHASER_RADIUS


func _get_arena_size() -> Vector2:
	var rect_size: Vector2 = get_viewport_rect().size
	if rect_size.x > 0.0 and rect_size.y > 0.0:
		return rect_size
	return Vector2(1152.0, 648.0)


func _constrain_to_arena(margin: float) -> void:
	global_position.x = clampf(global_position.x, margin, maxf(margin, _arena_size.x - margin))
	global_position.y = clampf(global_position.y, margin, maxf(margin, _arena_size.y - margin))


func _get_target_position() -> Vector2:
	if target_node != null and is_instance_valid(target_node):
		return target_node.global_position
	return _arena_size * 0.5


func _check_contact(delta: float) -> void:
	_contact_check_timer -= delta
	if _contact_check_timer > 0.0:
		return
	_contact_check_timer = CONTACT_CHECK_INTERVAL
	if not is_hazard_active:
		return
	for body: Node2D in get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(1)
			return


func _on_body_entered(body: Node2D) -> void:
	if is_hazard_active and body != null and body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(1)
