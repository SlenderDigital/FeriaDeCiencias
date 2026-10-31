@tool
extends Area2D
## Autonomous, non-destructible monochrome geometric enemy threat.
##
## Four distinct archetypes share one deterministic state machine:
## - CHASER: Swept-wing predator that weaves in pursuit, locks on with a dual-rail
##   trajectory telegraph, and lunges at high speed with afterimage echoes.
## - TURRET: Hexagonal artillery bastion that paints a multi-ray spread fan before
##   firing rhythmic projectile volleys with recoil shockwaves.
## - ORBITER: Star-diamond satellite with revolving sub-blades that circles the
##   player and periodically fires inward tangent pulse shots so it cannot be ignored.
## - PULSAR: 8-pointed precision lancer that slides to mid-range and fires high-speed
##   focused lance bursts.
## Every enemy telegraphs its arrival with a geometric reticle and is disabled during that warning.

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

var hazard_type: int = 4
var enemy_type: int = EnemyType.CHASER
var current_phase: Phase = Phase.SPAWN
var phase_timer: float = 0.0
var age: float = 0.0
var lifetime: float = DEFAULT_LIFETIME
var warning_time: float = DEFAULT_WARNING
var speed_scale: float = 1.0
var is_hazard_active: bool = false
var contact_count: int = 0
var projectiles_fired: int = 0
var lunge_count: int = 0
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
	_resolve_nodes()
	_arena_size = _get_arena_size()
	add_to_group("enemies")
	add_to_group("hazards")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_configure_common_visuals()
	_build_visual()
	_enter_phase(Phase.SPAWN)


## Configures a new enemy. Call after adding the enemy to the scene tree.
func configure_enemy(
	type: int = EnemyType.CHASER,
	spawn_pos: Vector2 = Vector2.ZERO,
	target: Node2D = null,
	requested_speed_scale: float = 1.0,
	warning: float = DEFAULT_WARNING,
	max_lifetime: float = DEFAULT_LIFETIME
) -> void:
	_resolve_nodes()
	_arena_size = _get_arena_size()
	enemy_type = clampi(type, EnemyType.CHASER, EnemyType.PULSAR)
	global_position = spawn_pos
	target_node = target
	speed_scale = clampf(requested_speed_scale, 0.75, 1.45)
	warning_time = maxf(warning, 0.35)
	lifetime = maxf(max_lifetime, warning_time + 1.0)
	age = 0.0
	phase_timer = 0.0
	contact_count = 0
	projectiles_fired = 0
	lunge_count = 0
	_volley_count = 0
	_recoil = 0.0
	_afterimages.clear()
	_afterimage_timer = 0.0
	_chaser_state = ChaserState.CHASE
	_lunge_cooldown = 0.85
	_fire_timer = 0.95
	_orbiter_fire_timer = ORBITER_FIRE_INTERVAL
	_orbit_angle = 0.0
	_orbit_radius = ORBITER_RADIUS_DISTANCE
	_target_position = _get_target_position()
	_orbit_center = _target_position
	if target_node != null:
		_orbit_center = target_node.global_position
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
	if trail != null:
		trail.clear_points()
	visible = true
	modulate = Color.WHITE
	scale = Vector2.ONE * 0.45
	if target_node != null:
		_chaser_state = ChaserState.CHASE
	_build_visual()
	_enter_phase(Phase.SPAWN)
	queue_redraw()


func set_target_node(target: Node2D) -> void:
	target_node = target
	_target_position = _get_target_position()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances the enemy by delta seconds. Safe for deterministic tests.
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
			_update_spawn_visual()
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
				_despawn()
	_update_trail()
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
			# Track slightly during early windup, then lock direction hard in the last 35%
			if progress < 0.65:
				var to_target_w: Vector2 = _target_position - global_position
				if to_target_w.length_squared() > 1.0:
					_lunge_direction = _lunge_direction.lerp(to_target_w.normalized(), minf(delta * 6.0, 1.0)).normalized()
					rotation = _lunge_direction.angle()
			# Recoil crouch back slightly before springing forward
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
				lunge_count += 1
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
				_afterimages.append({
					"pos": global_position,
					"rot": rotation,
					"life": 0.18,
					"max_life": 0.18,
				})
			if phase_timer >= lunge_duration:
				_chaser_state = ChaserState.CHASE
				_lunge_cooldown = 1.95 / maxf(speed_scale, 0.75)
				phase_timer = 0.0
	_constrain_to_arena(CHASER_RADIUS + 4.0)


func _simulate_turret(delta: float) -> void:
	aim_line.points = PackedVector2Array()
	var to_target: Vector2 = _target_position - global_position
	var aim_dir: Vector2 = to_target.normalized() if to_target.length_squared() > 0.001 else Vector2.DOWN
	# Subtle menacing hover around anchor
	global_position += Vector2(cos(age * 1.9), sin(age * 2.5)) * 10.0 * delta
	_constrain_to_arena(TURRET_RADIUS + 6.0)
	_fire_timer -= delta
	if _fire_timer <= TURRET_AIM_TIME:
		aim_line.visible = true
		var aim_len: float = minf(to_target.length(), 460.0) if to_target.length_squared() > 1.0 else 320.0
		aim_line.points = PackedVector2Array([Vector2.ZERO, aim_dir.rotated(-rotation) * aim_len])
		var aim_progress: float = clampf(1.0 - _fire_timer / TURRET_AIM_TIME, 0.0, 1.0)
		var g: float = 0.55 + 0.42 * aim_progress
		aim_line.default_color = Color(g, g, g, 0.48 + 0.44 * aim_progress)
	else:
		aim_line.visible = false
	if _fire_timer <= 0.0:
		_fire_timer = TURRET_FIRE_INTERVAL / maxf(speed_scale, 0.75)
		var spread: float = 0.20 if _volley_count % 2 == 0 else 0.12
		var proj_speed: float = (300.0 if _volley_count % 2 == 0 else 345.0) * speed_scale
		for offset: float in [-spread, 0.0, spread]:
			var dir: Vector2 = aim_dir.rotated(offset)
			fire_projectile.emit(global_position + dir * PROJECTILE_SPAWN_RADIUS, dir, proj_speed, 8.5)
			projectiles_fired += 1
		_volley_count += 1
		_recoil = 1.0
		core_polygon.scale = Vector2.ONE * 1.42


func _simulate_orbiter(delta: float) -> void:
	_orbit_center = _orbit_center.move_toward(_target_position, 82.0 * delta)
	_orbit_radius = move_toward(_orbit_radius, ORBITER_RADIUS_DISTANCE, 46.0 * delta)
	_orbit_angle += ORBITER_ANGULAR_SPEED * speed_scale * delta
	var radius_pulse: float = _orbit_radius * (1.0 + 0.10 * sin(age * 2.4))
	radius_pulse = clampf(radius_pulse, 125.0, 290.0)
	global_position = _orbit_center + Vector2.from_angle(_orbit_angle) * radius_pulse
	_constrain_to_arena(ORBITER_RADIUS + 6.0)
	rotation += 2.1 * delta

	_orbiter_fire_timer -= delta
	var to_target: Vector2 = _target_position - global_position
	var inward_dir: Vector2 = to_target.normalized() if to_target.length_squared() > 0.001 else Vector2.from_angle(_orbit_angle + PI)
	if _orbiter_fire_timer <= ORBITER_AIM_TIME:
		aim_line.visible = true
		var aim_progress: float = clampf(1.0 - _orbiter_fire_timer / ORBITER_AIM_TIME, 0.0, 1.0)
		var local_aim: Vector2 = inward_dir.rotated(-rotation) * minf(to_target.length(), 220.0)
		aim_line.points = PackedVector2Array([Vector2.ZERO, local_aim])
		var g: float = 0.56 + 0.38 * aim_progress
		aim_line.default_color = Color(g, g, g, 0.42 + 0.45 * aim_progress)
	else:
		aim_line.visible = false

	if _orbiter_fire_timer <= 0.0:
		_orbiter_fire_timer = ORBITER_FIRE_INTERVAL / maxf(speed_scale, 0.75)
		fire_projectile.emit(global_position + inward_dir * (ORBITER_RADIUS + 6.0), inward_dir, 285.0 * speed_scale, 8.0)
		projectiles_fired += 1
		_recoil = 0.75
		core_polygon.scale = Vector2.ONE * 1.35


func _simulate_pulsar(delta: float) -> void:
	var to_target: Vector2 = _target_position - global_position
	var dist: float = to_target.length()
	var dir: Vector2 = to_target.normalized() if dist > 0.001 else Vector2.RIGHT
	var tangent: Vector2 = Vector2(-dir.y, dir.x)
	var radial_push: float = 0.0
	if dist < 210.0:
		radial_push = -0.85
	elif dist > 310.0:
		radial_push = 0.75
	var move_vec: Vector2 = (tangent * 0.85 + dir * radial_push).normalized() * PULSAR_MOVE_SPEED * speed_scale
	if _fire_timer > PULSAR_AIM_TIME * 0.65:
		global_position += move_vec * delta
	_constrain_to_arena(PULSAR_RADIUS + 6.0)
	rotation = lerp_angle(rotation, dir.angle(), minf(8.0 * delta, 1.0))

	_fire_timer -= delta
	if _fire_timer <= PULSAR_AIM_TIME:
		aim_line.visible = true
		var aim_progress: float = clampf(1.0 - _fire_timer / PULSAR_AIM_TIME, 0.0, 1.0)
		var local_dir: Vector2 = dir.rotated(-rotation)
		aim_line.points = PackedVector2Array([Vector2.ZERO, local_dir * minf(maxf(dist, 240.0), 520.0)])
		var g: float = 0.60 + 0.38 * aim_progress
		aim_line.default_color = Color(g, g, g, 0.50 + 0.45 * aim_progress)
		core_polygon.scale = Vector2.ONE * (1.0 + 0.35 * aim_progress)
	else:
		aim_line.visible = false

	if _fire_timer <= 0.0:
		_fire_timer = PULSAR_FIRE_INTERVAL / maxf(speed_scale, 0.75)
		# High-speed precision center lance + 2 angled flankers
		fire_projectile.emit(global_position + dir * PROJECTILE_SPAWN_RADIUS, dir, 410.0 * speed_scale, 9.0)
		fire_projectile.emit(global_position + dir.rotated(-0.26) * PROJECTILE_SPAWN_RADIUS, dir.rotated(-0.26), 310.0 * speed_scale, 7.5)
		fire_projectile.emit(global_position + dir.rotated(0.26) * PROJECTILE_SPAWN_RADIUS, dir.rotated(0.26), 310.0 * speed_scale, 7.5)
		projectiles_fired += 3
		_recoil = 1.0
		core_polygon.scale = Vector2.ONE * 1.45


func _enter_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_timer = 0.0
	match new_phase:
		Phase.SPAWN:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			scale = Vector2.ONE * 0.45
			modulate = Color(1.0, 1.0, 1.0, 0.52)
			aim_line.visible = false
			outer_polygon.color = Color(0.52, 0.52, 0.52, 0.9)
			if void_polygon != null:
				void_polygon.color = Color(0.08, 0.08, 0.08, 0.9)
			core_polygon.color = Color(0.78, 0.78, 0.78, 0.9)
			ring.visible = false
		Phase.ACTIVE:
			is_hazard_active = true
			scale = Vector2.ONE
			modulate = Color.WHITE
			if collision_shape != null:
				collision_shape.disabled = false
			outer_polygon.color = Color(0.92, 0.92, 0.92, 1.0)
			if void_polygon != null:
				void_polygon.color = Color(0.06, 0.06, 0.06, 1.0)
			core_polygon.color = Color.WHITE
			ring.visible = enemy_type == EnemyType.ORBITER or enemy_type == EnemyType.PULSAR
			_chaser_state = ChaserState.CHASE
			_lunge_cooldown = 1.0
			phase_timer = 0.0
		Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			aim_line.visible = false
			ring.visible = false
	queue_redraw()


func _update_spawn_visual() -> void:
	var progress: float = clampf(phase_timer / maxf(warning_time, 0.001), 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(progress * TAU * 3.0)
	scale = Vector2.ONE * lerpf(0.45, 1.0, ease(progress, 0.65))
	modulate.a = 0.52 + 0.42 * pulse
	if aim_line.visible:
		aim_line.visible = false


func _update_core_motion(delta: float) -> void:
	if current_phase != Phase.ACTIVE:
		return
	match enemy_type:
		EnemyType.TURRET:
			core_polygon.rotation += 2.1 * delta
			if void_polygon != null:
				void_polygon.rotation -= 1.0 * delta
			outer_polygon.rotation -= 0.75 * delta
			core_polygon.scale = core_polygon.scale.move_toward(Vector2.ONE, delta * 3.2)
			scale = Vector2.ONE * (1.0 - 0.08 * _recoil)
		EnemyType.ORBITER:
			core_polygon.rotation -= 2.8 * delta
			if void_polygon != null:
				void_polygon.rotation += 1.4 * delta
			outer_polygon.rotation += 1.4 * delta
			ring.rotation += 2.4 * delta
			core_polygon.scale = core_polygon.scale.move_toward(Vector2.ONE, delta * 3.5)
		EnemyType.PULSAR:
			core_polygon.rotation += 3.2 * delta
			if void_polygon != null:
				void_polygon.rotation -= 1.6 * delta
			ring.rotation -= 2.0 * delta
			core_polygon.scale = core_polygon.scale.move_toward(Vector2.ONE, delta * 3.5)
			scale = Vector2.ONE * (1.0 - 0.07 * _recoil)
		EnemyType.CHASER:
			core_polygon.rotation += 1.4 * delta
			core_polygon.scale = core_polygon.scale.move_toward(Vector2.ONE, delta * 4.2)


func _update_trail() -> void:
	if trail == null:
		return
	trail.visible = current_phase == Phase.ACTIVE and enemy_type != EnemyType.TURRET
	if not trail.visible:
		return
	trail.add_point(global_position)
	var max_pts: int = 14 if (enemy_type == EnemyType.CHASER and _chaser_state == ChaserState.LUNGE) else 10
	while trail.get_point_count() > max_pts:
		trail.remove_point(0)


func _configure_common_visuals() -> void:
	if aim_line != null:
		aim_line.width = 2.0
		aim_line.default_color = Color(0.65, 0.65, 0.65, 0.6)
		aim_line.visible = false
	if trail != null:
		trail.top_level = true
		trail.width = 6.5
		trail.default_color = Color(0.65, 0.65, 0.65, 0.34)
		var width_curve: Curve = Curve.new()
		width_curve.add_point(Vector2(0.0, 0.08))
		width_curve.add_point(Vector2(0.65, 0.62))
		width_curve.add_point(Vector2(1.0, 1.0))
		trail.width_curve = width_curve
		var grad: Gradient = Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.65, 1.0])
		grad.colors = PackedColorArray([
			Color(0.35, 0.35, 0.35, 0.0),
			Color(0.68, 0.68, 0.68, 0.24),
			Color(0.92, 0.92, 0.92, 0.52),
		])
		trail.gradient = grad
		trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
		trail.end_cap_mode = Line2D.LINE_CAP_ROUND
		trail.visible = false
	if ring != null:
		ring.width = 2.0
		ring.default_color = Color(0.62, 0.62, 0.62, 0.48)
		ring.closed = true
		ring.visible = false


func _build_visual() -> void:
	var radius: float = _get_radius_for_type()

	if outer_polygon != null:
		outer_polygon.z_index = -3
		match enemy_type:
			EnemyType.TURRET:
				outer_polygon.polygon = _build_notched_hexagon(radius)
			EnemyType.ORBITER:
				outer_polygon.polygon = _build_star_diamond(radius, radius * 0.54)
			EnemyType.PULSAR:
				outer_polygon.polygon = _build_star_polygon(radius, radius * 0.48, 8)
			_:
				outer_polygon.polygon = _build_triangle(radius)

	if void_polygon != null:
		void_polygon.z_index = -2
		match enemy_type:
			EnemyType.TURRET:
				void_polygon.polygon = _build_regular_polygon(radius * 0.66, 6)
			EnemyType.ORBITER:
				void_polygon.polygon = _build_diamond(radius * 0.62)
			EnemyType.PULSAR:
				void_polygon.polygon = _build_regular_polygon(radius * 0.56, 8)
			_:
				void_polygon.polygon = _build_triangle(radius * 0.66)

	if core_polygon != null:
		core_polygon.z_index = -1
		match enemy_type:
			EnemyType.TURRET:
				core_polygon.polygon = _build_triangle(radius * 0.44)
			EnemyType.ORBITER:
				core_polygon.polygon = _build_diamond(radius * 0.38)
			EnemyType.PULSAR:
				core_polygon.polygon = _build_diamond(radius * 0.40)
			_:
				core_polygon.polygon = _build_triangle(radius * 0.42)

	if ring != null:
		var ring_radius: float = radius * (1.85 if enemy_type == EnemyType.ORBITER else 1.55)
		var points: PackedVector2Array = PackedVector2Array()
		for i: int in range(24):
			points.append(Vector2.from_angle(TAU * float(i) / 24.0) * ring_radius)
		ring.points = points

	if collision_shape != null:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = radius * 0.92
		collision_shape.shape = circle


func _draw() -> void:
	var radius: float = _get_radius_for_type()
	var inv_scale: float = 1.0 / maxf(scale.x, 0.25)

	# 1. Soft monochrome outer halo rings around the enemy silhouette
	var aura_alpha: float = 0.22 if current_phase == Phase.ACTIVE else 0.10
	draw_arc(Vector2.ZERO, radius * 1.24, 0.0, TAU, 32, Color(0.88, 0.88, 0.88, aura_alpha), 1.6, true)

	# 2. Spawn phase geometric lock-on reticle (drawn in unscaled world proportion)
	if current_phase == Phase.SPAWN:
		var progress: float = clampf(phase_timer / maxf(warning_time, 0.001), 0.0, 1.0)
		var outer_r: float = lerpf(radius * 2.1, radius * 1.05, progress) * inv_scale
		var reticle_col: Color = Color(0.78, 0.78, 0.78, 0.35 + 0.45 * progress)
		draw_arc(Vector2.ZERO, outer_r, 0.0, TAU, 36, reticle_col, 1.6 * inv_scale, true)
		draw_arc(Vector2.ZERO, radius * inv_scale, 0.0, TAU * progress, 32, Color(0.95, 0.95, 0.95, 0.75), 2.2 * inv_scale, true)
		for i: int in range(4):
			var ang: float = TAU * 0.25 * float(i) + progress * PI * 0.5
			var dir: Vector2 = Vector2.from_angle(ang)
			draw_line(dir * (outer_r - 5.0 * inv_scale), dir * (outer_r + 6.0 * inv_scale), reticle_col, 2.0 * inv_scale, true)
		return

	if current_phase != Phase.ACTIVE:
		return

	# 3. Active archetype-specific mechanical overlays & telegraphs
	match enemy_type:
		EnemyType.CHASER:
			_draw_chaser_details(radius)
		EnemyType.TURRET:
			_draw_turret_details(radius)
		EnemyType.ORBITER:
			_draw_orbiter_details(radius)
		EnemyType.PULSAR:
			_draw_pulsar_details(radius)


func _draw_chaser_details(radius: float) -> void:
	# Draw dash afterimages in local coordinates
	for ghost: Dictionary in _afterimages:
		var life_ratio: float = clampf(float(ghost["life"]) / maxf(float(ghost["max_life"]), 0.001), 0.0, 1.0)
		var world_offset: Vector2 = Vector2(ghost["pos"]) - global_position
		var local_pos: Vector2 = world_offset.rotated(-rotation) / Vector2(maxf(scale.x, 0.2), maxf(scale.y, 0.2))
		var ghost_poly: PackedVector2Array = _build_triangle(radius * (0.72 + 0.22 * life_ratio))
		for i: int in range(ghost_poly.size()):
			ghost_poly[i] = ghost_poly[i] + local_pos
		var g_alpha: float = 0.28 * life_ratio
		draw_colored_polygon(ghost_poly, Color(0.88, 0.88, 0.88, g_alpha))

	# Twin rear thruster flare & winglet accents
	var thrust_len: float = radius * (0.95 if _chaser_state == ChaserState.LUNGE else 0.45 + 0.15 * sin(age * 24.0))
	var flame_pts: PackedVector2Array = PackedVector2Array([
		Vector2(-radius * 0.62, -radius * 0.24),
		Vector2(-radius * 0.62 - thrust_len, 0.0),
		Vector2(-radius * 0.62, radius * 0.24),
	])
	draw_colored_polygon(flame_pts, Color(0.95, 0.95, 0.95, 0.72 if _chaser_state == ChaserState.LUNGE else 0.42))

	# Windup dual-rail corridor + lock-on target chevron
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
		# Chevron tip at lunge destination
		var tip: Vector2 = local_dir * reach
		draw_line(tip, tip - local_dir * 14.0 + perp * 10.0, Color(0.96, 0.96, 0.96, 0.82), 2.2, true)
		draw_line(tip, tip - local_dir * 14.0 - perp * 10.0, Color(0.96, 0.96, 0.96, 0.82), 2.2, true)
		draw_arc(Vector2.ZERO, lerpf(radius * 1.75, radius * 1.05, progress), 0.0, TAU, 28, rail_col, 2.0, true)


func _draw_turret_details(radius: float) -> void:
	# Tactical outer degree ring + 6 armor ticks
	var ring_r: float = radius * 1.34
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 36, Color(0.62, 0.62, 0.62, 0.38), 1.5, true)
	for i: int in range(6):
		var ang: float = outer_polygon.rotation + TAU * float(i) / 6.0
		var d: Vector2 = Vector2.from_angle(ang)
		draw_line(d * (ring_r - 3.5), d * (ring_r + 4.5), Color(0.88, 0.88, 0.88, 0.65), 2.0, true)

	# Multi-ray spread fan telegraph during TURRET_AIM_TIME
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
		# Contracting charge ring
		var charge_r: float = lerpf(radius * 1.85, radius * 1.02, aim_progress)
		draw_arc(Vector2.ZERO, charge_r, 0.0, TAU, 32, Color(0.95, 0.95, 0.95, 0.35 + 0.5 * aim_progress), 2.0, true)


func _draw_orbiter_details(radius: float) -> void:
	# 3 orbiting satellite blades along the outer ring
	var sat_orbit_r: float = radius * 1.85
	for i: int in range(3):
		var sat_ang: float = ring.rotation + TAU * float(i) / 3.0
		var sat_pos: Vector2 = Vector2.from_angle(sat_ang) * sat_orbit_r
		var tangent: Vector2 = Vector2(-sin(sat_ang), cos(sat_ang))
		var normal: Vector2 = Vector2.from_angle(sat_ang)
		var blade_pts: PackedVector2Array = PackedVector2Array([
			sat_pos + tangent * 7.5,
			sat_pos + normal * 4.2,
			sat_pos - tangent * 7.5,
			sat_pos - normal * 4.2,
		])
		draw_colored_polygon(blade_pts, Color(0.94, 0.94, 0.94, 0.92))

	if _orbiter_fire_timer <= ORBITER_AIM_TIME:
		var aim_p: float = clampf(1.0 - _orbiter_fire_timer / ORBITER_AIM_TIME, 0.0, 1.0)
		draw_arc(Vector2.ZERO, lerpf(sat_orbit_r, radius, aim_p), 0.0, TAU, 24, Color(0.95, 0.95, 0.95, 0.55 * aim_p), 2.0, true)


func _draw_pulsar_details(radius: float) -> void:
	var inner_r: float = radius * 1.25
	draw_arc(Vector2.ZERO, inner_r, age * 2.0, age * 2.0 + PI * 1.4, 24, Color(0.82, 0.82, 0.82, 0.55), 1.8, true)
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


func _build_triangle(radius: float) -> PackedVector2Array:
	# Sleek swept-wing delta predator silhouette
	return PackedVector2Array([
		Vector2(radius * 1.12, 0.0),
		Vector2(-radius * 0.76, -radius * 0.88),
		Vector2(-radius * 0.38, -radius * 0.26),
		Vector2(-radius * 0.68, 0.0),
		Vector2(-radius * 0.38, radius * 0.26),
		Vector2(-radius * 0.76, radius * 0.88),
	])


func _build_diamond(radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(radius, 0.0),
		Vector2(0.0, -radius),
		Vector2(-radius, 0.0),
		Vector2(0.0, radius),
	])


func _build_star_diamond(outer_r: float, inner_r: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(8):
		var ang: float = TAU * float(i) / 8.0
		var r: float = outer_r if i % 2 == 0 else inner_r
		pts.append(Vector2.from_angle(ang) * r)
	return pts


func _build_star_polygon(outer_r: float, inner_r: float, points_count: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var total: int = maxi(points_count * 2, 6)
	for i: int in range(total):
		var ang: float = TAU * float(i) / float(total)
		var r: float = outer_r if i % 2 == 0 else inner_r
		pts.append(Vector2.from_angle(ang) * r)
	return pts


func _build_notched_hexagon(radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(12):
		var ang: float = TAU * float(i) / 12.0
		var r: float = radius if i % 2 == 0 else radius * 0.84
		pts.append(Vector2.from_angle(ang) * r)
	return pts


func _build_regular_polygon(radius: float, sides: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(maxi(sides, 3)):
		points.append(Vector2.from_angle(TAU * float(i) / float(sides)) * radius)
	return points


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
	if not is_inside_tree() or not is_hazard_active:
		return
	for body: Node2D in get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.call("take_damage", 1)
			contact_count += 1
			return


func _on_body_entered(body: Node2D) -> void:
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


func _despawn() -> void:
	if is_inside_tree() and not Engine.is_editor_hint():
		queue_free()
	else:
		var parent: Node = get_parent()
		if parent != null:
			parent.remove_child(self)
		queue_free()


func _resolve_nodes() -> void:
	outer_polygon = get_node_or_null("OuterPolygon") as Polygon2D
	void_polygon = get_node_or_null("VoidPolygon") as Polygon2D
	core_polygon = get_node_or_null("CorePolygon") as Polygon2D
	aim_line = get_node_or_null("AimLine") as Line2D
	trail = get_node_or_null("Trail") as Line2D
	ring = get_node_or_null("Ring") as Line2D
	collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
