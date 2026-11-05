extends Area2D

signal exploder_detonated(at_position: Vector2)

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile.tscn")
const DEFAULT_RADIUS: float = 24.0
const DEFAULT_BURST_COUNT: int = 8
const DEFAULT_PROJECTILE_SPEED: float = 390.0
const DEFAULT_PROJECTILE_RADIUS: float = 10.0

var telegraph_duration: float = 1.0
var exploder_radius: float = DEFAULT_RADIUS
var exploder_burst_count: int = DEFAULT_BURST_COUNT
var exploder_projectile_speed: float = DEFAULT_PROJECTILE_SPEED
var phase_timer: float = 0.0
var has_detonated: bool = false
var is_hazard_active: bool = false

@onready var outer_visual: Polygon2D = $OuterVisual
@onready var core_visual: Polygon2D = $CoreVisual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_rebuild_geometry()


func configure(
	spawn_pos: Vector2,
	warning_time: float = 1.0,
	burst_count: int = DEFAULT_BURST_COUNT,
	projectile_speed: float = DEFAULT_PROJECTILE_SPEED,
	radius: float = DEFAULT_RADIUS
) -> void:
	global_position = spawn_pos
	telegraph_duration = warning_time
	exploder_burst_count = maxi(burst_count, 3)
	exploder_projectile_speed = projectile_speed
	exploder_radius = maxf(radius, 8.0)
	phase_timer = 0.0
	has_detonated = false
	_rebuild_geometry()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if has_detonated:
		return
	phase_timer += delta
	var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
	var freq: float = lerpf(14.0, 28.0, progress)
	var wave: float = 0.5 + 0.5 * sin(phase_timer * freq)

	var pulse: float = 0.35 + 0.38 * wave
	outer_visual.color = Color(pulse, pulse, pulse, 0.78)
	outer_visual.scale = Vector2.ONE * lerpf(0.86, 1.16, wave)
	outer_visual.rotation += delta * (1.2 + 2.4 * progress)

	core_visual.scale = Vector2.ONE * lerpf(0.25, 1.0, progress)
	core_visual.color = Color(0.92, 0.92, 0.92, lerpf(0.45, 0.98, progress))
	core_visual.rotation -= delta * (1.8 + 3.0 * progress)

	if phase_timer >= telegraph_duration:
		_detonate()
	queue_redraw()


func _detonate() -> void:
	has_detonated = true
	var parent_node: Node = get_parent()
	if parent_node != null:
		for i: int in range(exploder_burst_count):
			var dir: Vector2 = Vector2.from_angle((TAU * float(i)) / float(exploder_burst_count))
			var proj: Area2D = PROJECTILE_SCENE.instantiate() as Area2D
			parent_node.add_child(proj)
			proj.configure(global_position, dir, exploder_projectile_speed, DEFAULT_PROJECTILE_RADIUS)

	exploder_detonated.emit(global_position)
	SoundManager.play_sfx(&"explosion")
	queue_free()


func _rebuild_geometry() -> void:
	var oct_poly: PackedVector2Array = Shapes.circle(exploder_radius, 8)
	outer_visual.polygon = oct_poly
	core_visual.polygon = oct_poly
	var circle_shape: CircleShape2D = CircleShape2D.new()
	circle_shape.radius = exploder_radius
	collision_shape.shape = circle_shape


func _draw() -> void:
	var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
	var r: float = exploder_radius
	var ring_r: float = lerpf(r * 2.1, r * 1.08, progress)
	var spike_col: Color = Color(0.90, 0.90, 0.90, 0.35 + 0.55 * progress)
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 32, spike_col, 1.8, true)
	for i: int in range(exploder_burst_count):
		var d: Vector2 = Vector2.from_angle((TAU * float(i)) / float(exploder_burst_count))
		draw_line(d * (r * 1.15), d * (r * (1.55 + 0.45 * progress)), spike_col, 2.0, true)
