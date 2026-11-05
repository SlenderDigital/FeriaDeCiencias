extends Area2D

enum Phase {
	TELEGRAPH,
	ACTIVE,
	FADE_OUT,
}

enum FillMode {
	CENTER_OUT = 0,
	OUTSIDE_IN = 1,
	ANGULAR_SWEEP = 2,
}

const DEFAULT_RADIUS: float = 78.0
const CIRCLE_SEGMENTS: int = 32
const PLAYER_HIT_RADIUS: float = 12.0

const SHADOW_COLOR: Color = Color(0.28, 0.28, 0.28, 0.45)
const FILL_COLOR: Color = Color(0.88, 0.88, 0.88, 0.85)
const ACTIVE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const FADE_COLOR: Color = Color(0.75, 0.75, 0.75, 0.6)

var circle_radius: float = DEFAULT_RADIUS
var fill_mode: int = FillMode.CENTER_OUT
var telegraph_duration: float = 1.0
var active_duration: float = 0.35
var fade_duration: float = 0.2

var current_phase: Phase = Phase.TELEGRAPH
var phase_timer: float = 0.0
var is_hazard_active: bool = false

@onready var shadow_visual: Polygon2D = $ShadowVisual
@onready var fill_visual: Polygon2D = $FillVisual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


func configure(
	spawn_pos: Vector2,
	radius: float = DEFAULT_RADIUS,
	mode: int = FillMode.CENTER_OUT,
	warning_time: float = 1.0,
	active_time: float = 0.35
) -> void:
	global_position = spawn_pos
	circle_radius = maxf(radius, 8.0)
	fill_mode = clampi(mode, 0, 2)
	telegraph_duration = warning_time
	active_duration = active_time
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)
	queue_redraw()


func _physics_process(delta: float) -> void:
	phase_timer += delta
	match current_phase:
		Phase.TELEGRAPH:
			var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
			_update_fill_visual(progress)
			if phase_timer >= telegraph_duration:
				_enter_phase(Phase.ACTIVE)
		Phase.ACTIVE:
			_check_player_overlap()
			if phase_timer >= active_duration:
				_enter_phase(Phase.FADE_OUT)
		Phase.FADE_OUT:
			var fade_progress: float = clampf(phase_timer / maxf(fade_duration, 0.001), 0.0, 1.0)
			shadow_visual.scale = Vector2.ONE * lerpf(1.0, 0.0, fade_progress)
			shadow_visual.color = Color(0.75, 0.75, 0.75, lerpf(0.8, 0.0, fade_progress))
			if phase_timer >= fade_duration:
				queue_free()
	queue_redraw()


func _enter_phase(new_phase: Phase) -> void:
	current_phase = new_phase
	phase_timer = 0.0
	match new_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			collision_shape.disabled = true
			shadow_visual.color = SHADOW_COLOR
			shadow_visual.scale = Vector2.ONE
			fill_visual.visible = true
			fill_visual.color = FILL_COLOR
			_update_fill_visual(0.0)
		Phase.ACTIVE:
			is_hazard_active = true
			collision_shape.disabled = false
			shadow_visual.color = ACTIVE_COLOR
			shadow_visual.scale = Vector2.ONE
			fill_visual.visible = false
			SoundManager.play_sfx(&"laser")
			_check_player_overlap()
		Phase.FADE_OUT:
			is_hazard_active = false
			collision_shape.disabled = true
			shadow_visual.color = FADE_COLOR
			fill_visual.visible = false
	queue_redraw()


func _rebuild_geometry() -> void:
	shadow_visual.polygon = Shapes.circle(circle_radius, CIRCLE_SEGMENTS)
	fill_visual.polygon = PackedVector2Array()
	var circle_shape: CircleShape2D = CircleShape2D.new()
	circle_shape.radius = circle_radius
	collision_shape.shape = circle_shape


func _update_fill_visual(progress: float) -> void:
	var clamped: float = clampf(progress, 0.0, 1.0)
	match fill_mode:
		FillMode.CENTER_OUT:
			fill_visual.polygon = Shapes.circle(maxf(circle_radius * clamped, 1.0), CIRCLE_SEGMENTS)
		FillMode.OUTSIDE_IN:
			fill_visual.polygon = Shapes.annulus(circle_radius * (1.0 - clamped), circle_radius, CIRCLE_SEGMENTS)
		FillMode.ANGULAR_SWEEP:
			fill_visual.polygon = Shapes.sector(circle_radius, TAU * clamped, CIRCLE_SEGMENTS)


func _draw() -> void:
	if current_phase == Phase.TELEGRAPH:
		var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
		var rim_col: Color = Color(0.86, 0.86, 0.86, 0.36 + 0.48 * progress)
		draw_arc(Vector2.ZERO, circle_radius, 0.0, TAU, 40, rim_col, 2.0, true)
		for i: int in range(8):
			var d: Vector2 = Vector2.from_angle(TAU * float(i) / 8.0)
			draw_line(d * (circle_radius - 5.0), d * (circle_radius + 5.0), rim_col, 1.8, true)
	elif current_phase == Phase.ACTIVE:
		var progress_a: float = clampf(phase_timer / maxf(active_duration, 0.001), 0.0, 1.0)
		var halo_r: float = circle_radius * (1.06 + 0.24 * progress_a)
		draw_arc(Vector2.ZERO, halo_r, 0.0, TAU, 44, Color(1.0, 1.0, 1.0, 0.65 * (1.0 - progress_a)), 3.0, true)


func _check_player_overlap() -> void:
	if not is_hazard_active:
		return
	for node: Node in get_tree().get_nodes_in_group("player"):
		var body: Node2D = node as Node2D
		if body != null and global_position.distance_to(body.global_position) <= circle_radius + PLAYER_HIT_RADIUS:
			body.take_damage(1)
			return


func _on_body_entered(body: Node2D) -> void:
	if is_hazard_active and body != null and body.is_in_group("player"):
		body.take_damage(1)
