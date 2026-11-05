extends Area2D

const DEFAULT_SPEED: float = 390.0
const DEFAULT_RADIUS: float = 10.0
const VIEWPORT_DESPAWN_MARGIN: float = 64.0
const PLAYER_HIT_RADIUS: float = 12.0

var projectile_velocity: Vector2 = Vector2.RIGHT * DEFAULT_SPEED
var projectile_radius: float = DEFAULT_RADIUS
var is_hazard_active: bool = true

@onready var body_visual: Polygon2D = $BodyVisual
@onready var core_visual: Polygon2D = $CoreVisual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_rebuild_geometry()


func configure(
	spawn_pos: Vector2,
	direction: Vector2,
	speed: float = DEFAULT_SPEED,
	radius: float = DEFAULT_RADIUS
) -> void:
	global_position = spawn_pos
	var dir: Vector2 = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	projectile_velocity = dir * speed
	projectile_radius = maxf(radius, 4.0)
	rotation = dir.angle()
	is_hazard_active = true
	collision_shape.disabled = false
	_rebuild_geometry()
	_check_player_overlap()
	queue_redraw()


func _physics_process(delta: float) -> void:
	global_position += projectile_velocity * delta
	_check_player_overlap()
	if _is_outside_viewport():
		is_hazard_active = false
		collision_shape.disabled = true
		queue_free()
	queue_redraw()


func _rebuild_geometry() -> void:
	body_visual.polygon = Shapes.projectile(projectile_radius)
	core_visual.position = Vector2(projectile_radius * 0.14, 0.0)
	core_visual.polygon = Shapes.circle(projectile_radius * 0.44, 10)
	var circle_shape: CircleShape2D = CircleShape2D.new()
	circle_shape.radius = projectile_radius
	collision_shape.shape = circle_shape


func _draw() -> void:
	var r: float = projectile_radius
	draw_colored_polygon(PackedVector2Array([Vector2(-r * 0.2, -r * 0.72), Vector2(-r * 3.1, 0.0), Vector2(-r * 0.2, r * 0.72)]), Color(0.65, 0.65, 0.65, 0.28))
	draw_colored_polygon(PackedVector2Array([Vector2(-r * 0.1, -r * 0.42), Vector2(-r * 1.9, 0.0), Vector2(-r * 0.1, r * 0.42)]), Color(0.92, 0.92, 0.92, 0.55))
	draw_circle(Vector2.ZERO, r * 1.42, Color(0.88, 0.88, 0.88, 0.18))
	draw_circle(Vector2(r * 0.12, 0.0), r * 0.36, Color(0.08, 0.08, 0.08, 0.92))


func _is_outside_viewport() -> bool:
	var arena: Vector2 = get_viewport_rect().size
	return (
		global_position.x < -VIEWPORT_DESPAWN_MARGIN
		or global_position.x > arena.x + VIEWPORT_DESPAWN_MARGIN
		or global_position.y < -VIEWPORT_DESPAWN_MARGIN
		or global_position.y > arena.y + VIEWPORT_DESPAWN_MARGIN
	)


func _check_player_overlap() -> void:
	if not is_hazard_active:
		return
	for node: Node in get_tree().get_nodes_in_group("player"):
		var body: Node2D = node as Node2D
		if body != null and global_position.distance_to(body.global_position) <= projectile_radius + PLAYER_HIT_RADIUS:
			body.take_damage(1)
			return


func _on_body_entered(body: Node2D) -> void:
	if is_hazard_active and body != null and body.is_in_group("player"):
		body.take_damage(1)
