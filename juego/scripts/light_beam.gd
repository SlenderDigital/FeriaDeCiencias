@tool
extends Area2D
## Unified monochrome primitive 2D hazard entity.
## Consolidates four hazard behaviors into a single scene/script:
## 0. BEAM: Edge-to-edge rectangular light beam (telegraph -> solid white active -> fade out).
## 1. CIRCLE: Multi-pattern filling circle (center-out, outside-in, or angular sweep fill -> active burst -> fade out).
## 2. PROJECTILE: Un-telegraphed solid-white projectile with directional comet tail and immediate active collision, despawning outside viewport.
## 3. EXPLODER: Stationary pulsing arena telegraph with radial spike indicators that detonates into a radial burst of active projectiles.

signal exploder_detonated(at_position: Vector2)

enum Phase {
	TELEGRAPH,
	ACTIVE,
	FADE_OUT,
}

enum HazardType {
	BEAM = 0,
	CIRCLE = 1,
	PROJECTILE = 2,
	EXPLODER = 3,
}

enum CircleFillMode {
	CENTER_OUT = 0,
	OUTSIDE_IN = 1,
	ANGULAR_SWEEP = 2,
}

const DEFAULT_LENGTH: float = 3200.0
const DEFAULT_WIDTH: float = 44.0
const DEFAULT_CIRCLE_RADIUS: float = 78.0
const DEFAULT_PROJECTILE_RADIUS: float = 10.0
const DEFAULT_PROJECTILE_SPEED: float = 390.0
const DEFAULT_EXPLODER_RADIUS: float = 24.0
const DEFAULT_EXPLODER_BURST_COUNT: int = 8
const CIRCLE_SEGMENTS: int = 32
const VIEWPORT_DESPAWN_MARGIN: float = 64.0
const AudioLibrary: GDScript = preload("res://scripts/audio_library.gd")

static var _burst_scene: PackedScene = null

const TELEGRAPH_COLOR: Color = Color(0.32, 0.32, 0.32, 0.55)
const TELEGRAPH_LINE_COLOR: Color = Color(0.62, 0.62, 0.62, 0.85)
const CIRCLE_SHADOW_COLOR: Color = Color(0.28, 0.28, 0.28, 0.45)
const CIRCLE_FILL_COLOR: Color = Color(0.88, 0.88, 0.88, 0.85)
const ACTIVE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const FADE_COLOR: Color = Color(0.75, 0.75, 0.75, 0.6)

@export var telegraph_duration: float = 1.0
@export var active_duration: float = 0.35
@export var fade_duration: float = 0.2
@export var beam_width: float = DEFAULT_WIDTH
@export var beam_length: float = DEFAULT_LENGTH

var hazard_type: HazardType = HazardType.BEAM
var circle_fill_mode: CircleFillMode = CircleFillMode.CENTER_OUT
var circle_radius: float = DEFAULT_CIRCLE_RADIUS
var projectile_velocity: Vector2 = Vector2.ZERO
var projectile_radius: float = DEFAULT_PROJECTILE_RADIUS
var exploder_radius: float = DEFAULT_EXPLODER_RADIUS
var exploder_burst_count: int = DEFAULT_EXPLODER_BURST_COUNT
var exploder_projectile_speed: float = DEFAULT_PROJECTILE_SPEED
var has_detonated: bool = false
var _arena_size_cache: Vector2 = Vector2(1152.0, 648.0)

var current_phase: Phase = Phase.TELEGRAPH
var phase_timer: float = 0.0
var is_hazard_active: bool = false
var sfx_play_count: int = 0
var last_sfx_played: StringName = &""

@onready var beam_visual: Polygon2D = $BeamVisual
@onready var center_line: Polygon2D = $CenterLine
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sfx_player: AudioStreamPlayer = $SfxPlayer


func _ready() -> void:
	_resolve_nodes()
	add_to_group("light_beams")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_arena_size_cache = _read_arena_size()
	_rebuild_geometry()
	if hazard_type == HazardType.PROJECTILE:
		_enter_phase(Phase.ACTIVE)
	else:
		_enter_phase(Phase.TELEGRAPH)


func _resolve_nodes() -> void:
	if beam_visual == null:
		beam_visual = get_node_or_null("BeamVisual") as Polygon2D
	if center_line == null:
		center_line = get_node_or_null("CenterLine") as Polygon2D
	if collision_shape == null:
		collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if sfx_player == null:
		sfx_player = get_node_or_null("SfxPlayer") as AudioStreamPlayer
	if sfx_player != null and sfx_player.stream == null:
		sfx_player.stream = AudioLibrary.laser()


## Configures the hazard as an edge-to-edge rectangular light beam (default backward-compatible contract).
func configure(
	spawn_pos: Vector2,
	angle_radians: float,
	width: float = DEFAULT_WIDTH,
	warning_time: float = 1.0,
	active_time: float = 0.35
) -> void:
	_resolve_nodes()
	hazard_type = HazardType.BEAM
	global_position = spawn_pos
	rotation = angle_radians
	beam_width = width
	telegraph_duration = warning_time
	active_duration = active_time
	sfx_play_count = 0
	last_sfx_played = &""
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)
	queue_redraw()


## Configures the hazard as a filling circle with one of three fill patterns:
## 0 = CENTER_OUT, 1 = OUTSIDE_IN, 2 = ANGULAR_SWEEP.
func configure_circle(
	spawn_pos: Vector2,
	radius: float = DEFAULT_CIRCLE_RADIUS,
	fill_mode: int = CircleFillMode.CENTER_OUT,
	warning_time: float = 1.0,
	active_time: float = 0.35
) -> void:
	_resolve_nodes()
	hazard_type = HazardType.CIRCLE
	circle_radius = maxf(radius, 8.0)
	circle_fill_mode = clampi(fill_mode, 0, 2)
	global_position = spawn_pos
	rotation = 0.0
	telegraph_duration = warning_time
	active_duration = active_time
	sfx_play_count = 0
	last_sfx_played = &""
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)
	queue_redraw()


## Configures the hazard as an un-telegraphed solid-white projectile with immediate active collision.
func configure_projectile(
	spawn_pos: Vector2,
	direction: Vector2,
	speed: float = DEFAULT_PROJECTILE_SPEED,
	radius: float = DEFAULT_PROJECTILE_RADIUS
) -> void:
	_resolve_nodes()
	hazard_type = HazardType.PROJECTILE
	global_position = spawn_pos
	var dir: Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	projectile_velocity = dir * speed
	projectile_radius = maxf(radius, 4.0)
	rotation = dir.angle()
	sfx_play_count = 0
	last_sfx_played = &""
	_rebuild_geometry()
	_enter_phase(Phase.ACTIVE)
	queue_redraw()


## Configures the hazard as a stationary pulsing arena object that detonates into radial projectiles.
func configure_exploder(
	spawn_pos: Vector2,
	warning_time: float = 1.0,
	burst_count: int = DEFAULT_EXPLODER_BURST_COUNT,
	projectile_speed: float = DEFAULT_PROJECTILE_SPEED,
	radius: float = DEFAULT_EXPLODER_RADIUS
) -> void:
	_resolve_nodes()
	hazard_type = HazardType.EXPLODER
	global_position = spawn_pos
	rotation = 0.0
	telegraph_duration = warning_time
	exploder_burst_count = maxi(burst_count, 3)
	exploder_projectile_speed = projectile_speed
	exploder_radius = maxf(radius, 8.0)
	has_detonated = false
	sfx_play_count = 0
	last_sfx_played = &""
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	simulate_physics(delta)


## Advances the hazard lifecycle and movement by delta seconds.
func simulate_physics(delta: float) -> void:
	phase_timer += delta

	match hazard_type:
		HazardType.BEAM:
			_simulate_beam(delta)
		HazardType.CIRCLE:
			_simulate_circle(delta)
		HazardType.PROJECTILE:
			_simulate_projectile(delta)
		HazardType.EXPLODER:
			_simulate_exploder(delta)
	queue_redraw()


func _simulate_beam(_delta: float) -> void:
	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				var pulse_alpha: float = lerpf(0.28, 0.56, progress)
				beam_visual.color = Color(0.32, 0.32, 0.32, pulse_alpha)
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				var max_core_scale: float = maxf(beam_width / 3.0, 1.0)
				var core_y: float = lerpf(1.0, max_core_scale, pow(progress, 1.6))
				center_line.scale = Vector2(1.0, core_y)
				var line_g: float = lerpf(0.62, 0.94, progress)
				center_line.color = Color(line_g, line_g, line_g, lerpf(0.65, 0.92, progress))
			if phase_timer >= telegraph_duration:
				_enter_phase(Phase.ACTIVE)

		Phase.ACTIVE:
			_check_player_overlap()
			if phase_timer >= active_duration:
				_enter_phase(Phase.FADE_OUT)

		Phase.FADE_OUT:
			var fade_progress: float = clampf(phase_timer / maxf(fade_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				beam_visual.scale.y = lerpf(1.0, 0.0, fade_progress)
				beam_visual.color = Color(0.75, 0.75, 0.75, lerpf(0.8, 0.0, fade_progress))
			if phase_timer >= fade_duration:
				_despawn()


func _simulate_circle(_delta: float) -> void:
	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			_update_circle_fill_visual(progress)
			if phase_timer >= telegraph_duration:
				_enter_phase(Phase.ACTIVE)

		Phase.ACTIVE:
			_check_player_overlap()
			if phase_timer >= active_duration:
				_enter_phase(Phase.FADE_OUT)

		Phase.FADE_OUT:
			var fade_progress: float = clampf(phase_timer / maxf(fade_duration, 0.001), 0.0, 1.0)
			if beam_visual != null:
				var s: float = lerpf(1.0, 0.0, fade_progress)
				beam_visual.scale = Vector2(s, s)
				beam_visual.color = Color(0.75, 0.75, 0.75, lerpf(0.8, 0.0, fade_progress))
			if phase_timer >= fade_duration:
				_despawn()


func _simulate_projectile(delta: float) -> void:
	global_position += projectile_velocity * delta
	_check_player_overlap()
	if _is_outside_viewport():
		is_hazard_active = false
		if collision_shape != null:
			collision_shape.disabled = true
		_despawn()


func _simulate_exploder(delta: float) -> void:
	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			var freq: float = lerpf(14.0, 28.0, progress)
			if beam_visual != null:
				var pulse: float = 0.35 + 0.38 * (0.5 + 0.5 * sin(phase_timer * freq))
				beam_visual.color = Color(pulse, pulse, pulse, 0.78)
				var s: float = lerpf(0.86, 1.16, 0.5 + 0.5 * sin(phase_timer * freq))
				beam_visual.scale = Vector2(s, s)
				beam_visual.rotation += delta * (1.2 + 2.4 * progress)
			if center_line != null:
				var core_scale: float = lerpf(0.25, 1.0, progress)
				center_line.scale = Vector2(core_scale, core_scale)
				center_line.color = Color(0.92, 0.92, 0.92, lerpf(0.45, 0.98, progress))
				center_line.rotation -= delta * (1.8 + 3.0 * progress)
			if phase_timer >= telegraph_duration:
				_detonate_exploder()

		Phase.FADE_OUT:
			_despawn()


func _detonate_exploder() -> void:
	if has_detonated:
		return
	has_detonated = true
	is_hazard_active = false
	if collision_shape != null:
		collision_shape.disabled = true

	var parent_node: Node = get_parent()
	if parent_node != null:
		if _burst_scene == null:
			_burst_scene = load("res://scenes/light_beam.tscn") as PackedScene
		var packed: PackedScene = _burst_scene
		if packed != null:
			for i: int in range(exploder_burst_count):
				var angle: float = (TAU * float(i)) / float(exploder_burst_count)
				var dir: Vector2 = Vector2.from_angle(angle)
				var proj: Area2D = packed.instantiate() as Area2D
				if proj != null:
					parent_node.add_child(proj)
					proj.call("configure_projectile", global_position, dir, exploder_projectile_speed, DEFAULT_PROJECTILE_RADIUS)

	exploder_detonated.emit(global_position)
	_play_hazard_sfx(&"explosion", AudioLibrary.explosion(), true)
	_enter_phase(Phase.FADE_OUT)
	_despawn()


func _enter_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_timer = 0.0

	match hazard_type:
		HazardType.BEAM:
			_enter_beam_phase(new_phase)
		HazardType.CIRCLE:
			_enter_circle_phase(new_phase)
		HazardType.PROJECTILE:
			_enter_projectile_phase(new_phase)
		HazardType.EXPLODER:
			_enter_exploder_phase(new_phase)
	queue_redraw()


func _enter_beam_phase(new_phase: Phase) -> void:
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = TELEGRAPH_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = true
				center_line.scale = Vector2.ONE
				center_line.color = TELEGRAPH_LINE_COLOR

		Phase.ACTIVE:
			is_hazard_active = true
			if collision_shape != null:
				collision_shape.disabled = false
			if beam_visual != null:
				beam_visual.color = ACTIVE_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = false
			_play_hazard_sfx(&"laser", AudioLibrary.laser(), false)
			_check_player_overlap()

		Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = FADE_COLOR
			if center_line != null:
				center_line.visible = false


func _enter_circle_phase(new_phase: Phase) -> void:
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = CIRCLE_SHADOW_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = true
				center_line.scale = Vector2.ONE
				center_line.color = CIRCLE_FILL_COLOR
			_update_circle_fill_visual(0.0)

		Phase.ACTIVE:
			is_hazard_active = true
			if collision_shape != null:
				collision_shape.disabled = false
			if beam_visual != null:
				beam_visual.color = ACTIVE_COLOR
				beam_visual.scale = Vector2.ONE
			if center_line != null:
				center_line.visible = false
			_play_hazard_sfx(&"laser", AudioLibrary.laser(), false)
			_check_player_overlap()

		Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = FADE_COLOR
			if center_line != null:
				center_line.visible = false


func _enter_projectile_phase(_new_phase: Phase) -> void:
	current_phase = Phase.ACTIVE
	is_hazard_active = true
	if collision_shape != null:
		collision_shape.disabled = false
	if beam_visual != null:
		beam_visual.color = ACTIVE_COLOR
		beam_visual.scale = Vector2.ONE
	if center_line != null:
		center_line.visible = true
		center_line.scale = Vector2.ONE
		center_line.color = Color(0.08, 0.08, 0.08, 0.94)
	_check_player_overlap()


func _enter_exploder_phase(new_phase: Phase) -> void:
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if beam_visual != null:
				beam_visual.color = TELEGRAPH_COLOR
				beam_visual.scale = Vector2.ONE
				beam_visual.rotation = 0.0
			if center_line != null:
				center_line.visible = true
				center_line.scale = Vector2(0.25, 0.25)
				center_line.color = CIRCLE_FILL_COLOR
				center_line.rotation = 0.0

		Phase.ACTIVE, Phase.FADE_OUT:
			is_hazard_active = false
			if collision_shape != null:
				collision_shape.disabled = true
			if center_line != null:
				center_line.visible = false


func _rebuild_geometry() -> void:
	match hazard_type:
		HazardType.BEAM:
			_rebuild_beam_geometry()
		HazardType.CIRCLE:
			_rebuild_circle_geometry()
		HazardType.PROJECTILE:
			_rebuild_projectile_geometry()
		HazardType.EXPLODER:
			_rebuild_exploder_geometry()


func _rebuild_beam_geometry() -> void:
	var half_len: float = beam_length * 0.5
	var half_width: float = beam_width * 0.5

	if beam_visual != null:
		beam_visual.polygon = PackedVector2Array([
			Vector2(-half_len, -half_width),
			Vector2(half_len, -half_width),
			Vector2(half_len, half_width),
			Vector2(-half_len, half_width),
		])

	if center_line != null:
		center_line.position = Vector2.ZERO
		center_line.polygon = PackedVector2Array([
			Vector2(-half_len, -1.5),
			Vector2(half_len, -1.5),
			Vector2(half_len, 1.5),
			Vector2(-half_len, 1.5),
		])

	if collision_shape != null:
		var rect_shape: RectangleShape2D = RectangleShape2D.new()
		rect_shape.size = Vector2(beam_length, beam_width)
		collision_shape.shape = rect_shape


func _rebuild_circle_geometry() -> void:
	var full_circle: PackedVector2Array = _build_circle_polygon(circle_radius, CIRCLE_SEGMENTS)
	if beam_visual != null:
		beam_visual.polygon = full_circle
	if center_line != null:
		center_line.position = Vector2.ZERO
		center_line.polygon = PackedVector2Array()
	if collision_shape != null:
		var circle_shape: CircleShape2D = CircleShape2D.new()
		circle_shape.radius = circle_radius
		collision_shape.shape = circle_shape


func _rebuild_projectile_geometry() -> void:
	var poly: PackedVector2Array = _build_projectile_polygon(projectile_radius)
	if beam_visual != null:
		beam_visual.polygon = poly
	if center_line != null:
		center_line.position = Vector2(projectile_radius * 0.14, 0.0)
		center_line.polygon = _build_circle_polygon(projectile_radius * 0.44, 10)
	if collision_shape != null:
		var circle_shape: CircleShape2D = CircleShape2D.new()
		circle_shape.radius = projectile_radius
		collision_shape.shape = circle_shape


func _rebuild_exploder_geometry() -> void:
	var oct_poly: PackedVector2Array = _build_circle_polygon(exploder_radius, 8)
	if beam_visual != null:
		beam_visual.polygon = oct_poly
	if center_line != null:
		center_line.position = Vector2.ZERO
		center_line.polygon = oct_poly
	if collision_shape != null:
		var circle_shape: CircleShape2D = CircleShape2D.new()
		circle_shape.radius = exploder_radius
		collision_shape.shape = circle_shape


func _draw() -> void:
	match hazard_type:
		HazardType.BEAM:
			_draw_beam_overlay()
		HazardType.CIRCLE:
			_draw_circle_overlay()
		HazardType.PROJECTILE:
			_draw_projectile_overlay()
		HazardType.EXPLODER:
			_draw_exploder_overlay()


func _draw_beam_overlay() -> void:
	var half_len: float = beam_length * 0.5
	var half_w: float = beam_width * 0.5
	if current_phase == Phase.TELEGRAPH:
		var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
		var rail_col: Color = Color(0.90, 0.90, 0.90, 0.38 + 0.52 * progress)
		# Crisp boundary rails pinned strictly to the exact hitbox edges [-half_w, +half_w]
		draw_line(Vector2(-half_len, -half_w), Vector2(half_len, -half_w), rail_col, 1.6, true)
		draw_line(Vector2(-half_len, half_w), Vector2(half_len, half_w), rail_col, 1.6, true)
	elif current_phase == Phase.ACTIVE:
		# Tight 1.5px edge highlight on the exact hitbox boundary (no false-hitbox rectangle outside [-half_w, +half_w])
		var edge_col: Color = Color(1.0, 1.0, 1.0, 0.95)
		draw_line(Vector2(-half_len, -half_w), Vector2(half_len, -half_w), edge_col, 1.5, true)
		draw_line(Vector2(-half_len, half_w), Vector2(half_len, half_w), edge_col, 1.5, true)


func _draw_circle_overlay() -> void:
	if current_phase == Phase.TELEGRAPH:
		var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
		var rim_col: Color = Color(0.86, 0.86, 0.86, 0.36 + 0.48 * progress)
		draw_arc(Vector2.ZERO, circle_radius, 0.0, TAU, 40, rim_col, 2.0, true)
		for i: int in range(8):
			var ang: float = TAU * float(i) / 8.0
			var d: Vector2 = Vector2.from_angle(ang)
			draw_line(d * (circle_radius - 5.0), d * (circle_radius + 5.0), rim_col, 1.8, true)
	elif current_phase == Phase.ACTIVE:
		var progress_a: float = clampf(phase_timer / maxf(active_duration, 0.001), 0.0, 1.0)
		var halo_r: float = circle_radius * (1.06 + 0.24 * progress_a)
		draw_arc(Vector2.ZERO, halo_r, 0.0, TAU, 44, Color(1.0, 1.0, 1.0, 0.65 * (1.0 - progress_a)), 3.0, true)


func _draw_projectile_overlay() -> void:
	if current_phase != Phase.ACTIVE:
		return
	var r: float = projectile_radius
	# Comet wake tail & outer aura + dark pinpoint core for high contrast
	var tail_outer: PackedVector2Array = PackedVector2Array([
		Vector2(-r * 0.2, -r * 0.72),
		Vector2(-r * 3.1, 0.0),
		Vector2(-r * 0.2, r * 0.72),
	])
	var tail_inner: PackedVector2Array = PackedVector2Array([
		Vector2(-r * 0.1, -r * 0.42),
		Vector2(-r * 1.9, 0.0),
		Vector2(-r * 0.1, r * 0.42),
	])
	draw_colored_polygon(tail_outer, Color(0.65, 0.65, 0.65, 0.28))
	draw_colored_polygon(tail_inner, Color(0.92, 0.92, 0.92, 0.55))
	draw_circle(Vector2.ZERO, r * 1.42, Color(0.88, 0.88, 0.88, 0.18))
	draw_circle(Vector2(r * 0.12, 0.0), r * 0.36, Color(0.08, 0.08, 0.08, 0.92))


func _draw_exploder_overlay() -> void:
	if current_phase != Phase.TELEGRAPH:
		return
	var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
	var r: float = exploder_radius
	var ring_r: float = lerpf(r * 2.1, r * 1.08, progress)
	var spike_col: Color = Color(0.90, 0.90, 0.90, 0.35 + 0.55 * progress)
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 32, spike_col, 1.8, true)
	# Draw 8 radial burst trajectory spikes matching the exact detonation directions
	for i: int in range(exploder_burst_count):
		var ang: float = (TAU * float(i)) / float(exploder_burst_count)
		var d: Vector2 = Vector2.from_angle(ang)
		var start_r: float = r * 1.15
		var end_r: float = r * (1.55 + 0.45 * progress)
		draw_line(d * start_r, d * end_r, spike_col, 2.0, true)


func _update_circle_fill_visual(progress: float) -> void:
	if center_line == null:
		return
	var clamped: float = clampf(progress, 0.0, 1.0)
	match circle_fill_mode:
		CircleFillMode.CENTER_OUT:
			var r: float = maxf(circle_radius * clamped, 1.0)
			center_line.polygon = _build_circle_polygon(r, CIRCLE_SEGMENTS)

		CircleFillMode.OUTSIDE_IN:
			var inner_r: float = circle_radius * (1.0 - clamped)
			center_line.polygon = _build_annulus_polygon(inner_r, circle_radius, CIRCLE_SEGMENTS)

		CircleFillMode.ANGULAR_SWEEP:
			var sweep_angle: float = TAU * clamped
			center_line.polygon = _build_sector_polygon(circle_radius, sweep_angle, CIRCLE_SEGMENTS)


func _build_projectile_polygon(radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var count: int = 12
	pts.resize(count)
	for i: int in range(count):
		var angle: float = (TAU * float(i)) / float(count)
		var dir_vec: Vector2 = Vector2.from_angle(angle)
		var x_scale: float = 1.28 if dir_vec.x >= 0.0 else 1.45
		var y_scale: float = 0.86
		pts[i] = Vector2(dir_vec.x * radius * x_scale, dir_vec.y * radius * y_scale)
	return pts


func _build_circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var count: int = maxi(segments, 3)
	pts.resize(count)
	for i: int in range(count):
		var angle: float = (TAU * float(i)) / float(count)
		pts[i] = Vector2.from_angle(angle) * radius
	return pts


func _build_annulus_polygon(inner_radius: float, outer_radius: float, segments: int) -> PackedVector2Array:
	if inner_radius <= 0.5:
		return _build_circle_polygon(outer_radius, segments)
	var count: int = maxi(segments, 6)
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(count + 1):
		var angle: float = (TAU * float(i)) / float(count)
		pts.append(Vector2.from_angle(angle) * outer_radius)
	for i: int in range(count, -1, -1):
		var angle: float = (TAU * float(i)) / float(count)
		pts.append(Vector2.from_angle(angle) * inner_radius)
	return pts


func _build_sector_polygon(radius: float, sweep_angle: float, segments: int) -> PackedVector2Array:
	if sweep_angle <= 0.02:
		return PackedVector2Array([
			Vector2.ZERO,
			Vector2(radius, 0.0),
			Vector2.from_angle(0.02) * radius,
		])
	if sweep_angle >= TAU - 0.001:
		return _build_circle_polygon(radius, segments)
	var count: int = maxi(int(ceil(float(segments) * (sweep_angle / TAU))), 2)
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2.ZERO)
	for i: int in range(count + 1):
		var angle: float = -PI * 0.5 + (sweep_angle * float(i)) / float(count)
		pts.append(Vector2.from_angle(angle) * radius)
	return pts


func _get_arena_size() -> Vector2:
	return _arena_size_cache


func _read_arena_size() -> Vector2:
	if is_inside_tree():
		var rect_size: Vector2 = get_viewport_rect().size
		if rect_size.x > 0.0 and rect_size.y > 0.0:
			return rect_size
	return Vector2(1152.0, 648.0)


func _is_outside_viewport() -> bool:
	var arena: Vector2 = _get_arena_size()
	return (
		global_position.x < -VIEWPORT_DESPAWN_MARGIN
		or global_position.x > arena.x + VIEWPORT_DESPAWN_MARGIN
		or global_position.y < -VIEWPORT_DESPAWN_MARGIN
		or global_position.y > arena.y + VIEWPORT_DESPAWN_MARGIN
	)


func _despawn() -> void:
	if is_inside_tree() and not Engine.is_editor_hint():
		queue_free()
	else:
		var p: Node = get_parent()
		if p != null:
			p.remove_child(self)
		queue_free()


func _check_player_overlap() -> void:
	if not is_hazard_active or not is_inside_tree():
		return
	for body: Node2D in get_overlapping_bodies():
		if body != null and body.is_in_group("player") and body.has_method("take_damage"):
			if _is_body_within_exact_hitbox(body):
				body.call("take_damage", 1)
				return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group("player"):
		var player_body: Node2D = node as Node2D
		if player_body != null and player_body.has_method("take_damage") and _is_body_within_exact_hitbox(player_body):
			player_body.call("take_damage", 1)
			return


func _is_body_within_exact_hitbox(body: Node2D) -> bool:
	var local_pos: Vector2 = to_local(body.global_position)
	const PLAYER_HIT_RADIUS: float = 12.0
	match hazard_type:
		HazardType.BEAM:
			return (
				absf(local_pos.x) <= beam_length * 0.5 + PLAYER_HIT_RADIUS
				and absf(local_pos.y) <= beam_width * 0.5 + PLAYER_HIT_RADIUS
			)
		HazardType.CIRCLE:
			return local_pos.length() <= circle_radius + PLAYER_HIT_RADIUS
		HazardType.PROJECTILE:
			return local_pos.length() <= projectile_radius + PLAYER_HIT_RADIUS
		_:
			return false


func _on_body_entered(body: Node2D) -> void:
	if is_hazard_active and body != null and body.is_in_group("player") and body.has_method("take_damage"):
		if _is_body_within_exact_hitbox(body):
			body.call("take_damage", 1)


func _play_hazard_sfx(sfx_name: StringName, stream: AudioStreamWAV, persist_on_despawn: bool) -> void:
	_resolve_nodes()
	sfx_play_count += 1
	last_sfx_played = sfx_name
	if sfx_player != null:
		sfx_player.stream = stream
	var parent_node: Node = get_parent()
	var level_node: Node = parent_node.get_parent() if parent_node != null else null
	if persist_on_despawn and level_node != null and level_node.has_method("play_hazard_sfx"):
		level_node.call("play_hazard_sfx", sfx_name, stream)
		return
	if is_inside_tree() and not Engine.is_editor_hint() and sfx_player != null:
		sfx_player.play()
