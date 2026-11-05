extends Area2D

enum Phase {
	TELEGRAPH,
	ACTIVE,
	FADE_OUT,
}

const DEFAULT_LENGTH: float = 3200.0
const DEFAULT_WIDTH: float = 44.0
const PLAYER_HIT_RADIUS: float = 12.0

const TELEGRAPH_COLOR: Color = Color(0.32, 0.32, 0.32, 0.55)
const TELEGRAPH_LINE_COLOR: Color = Color(0.62, 0.62, 0.62, 0.85)
const ACTIVE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const FADE_COLOR: Color = Color(0.75, 0.75, 0.75, 0.6)

var telegraph_duration: float = 1.0
var active_duration: float = 0.35
var fade_duration: float = 0.2
var beam_width: float = DEFAULT_WIDTH
var beam_length: float = DEFAULT_LENGTH

var current_phase: Phase = Phase.TELEGRAPH
var phase_timer: float = 0.0
var is_hazard_active: bool = false

@onready var beam_visual: Polygon2D = $BeamVisual
@onready var center_line: Polygon2D = $CenterLine
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_rebuild_geometry()
	_enter_phase(Phase.TELEGRAPH)


func configure(
	spawn_pos: Vector2,
	angle_radians: float,
	width: float = DEFAULT_WIDTH,
	warning_time: float = 1.0,
	active_time: float = 0.35
) -> void:
	global_position = spawn_pos
	rotation = angle_radians
	beam_width = width
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
			beam_visual.color = Color(0.32, 0.32, 0.32, lerpf(0.28, 0.56, progress))
			beam_visual.scale = Vector2.ONE
			center_line.scale = Vector2(1.0, lerpf(1.0, maxf(beam_width / 3.0, 1.0), pow(progress, 1.6)))
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
			beam_visual.scale.y = lerpf(1.0, 0.0, fade_progress)
			beam_visual.color = Color(0.75, 0.75, 0.75, lerpf(0.8, 0.0, fade_progress))
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
			beam_visual.color = TELEGRAPH_COLOR
			beam_visual.scale = Vector2.ONE
			center_line.visible = true
			center_line.scale = Vector2.ONE
			center_line.color = TELEGRAPH_LINE_COLOR
		Phase.ACTIVE:
			is_hazard_active = true
			collision_shape.disabled = false
			beam_visual.color = ACTIVE_COLOR
			beam_visual.scale = Vector2.ONE
			center_line.visible = false
			SoundManager.play_sfx(&"laser")
			_check_player_overlap()
		Phase.FADE_OUT:
			is_hazard_active = false
			collision_shape.disabled = true
			beam_visual.color = FADE_COLOR
			center_line.visible = false
	queue_redraw()


func _rebuild_geometry() -> void:
	beam_visual.polygon = Shapes.rect(Vector2(beam_length, beam_width))
	center_line.polygon = Shapes.rect(Vector2(beam_length, 3.0))
	var rect_shape: RectangleShape2D = RectangleShape2D.new()
	rect_shape.size = Vector2(beam_length, beam_width)
	collision_shape.shape = rect_shape


func _draw() -> void:
	var half_len: float = beam_length * 0.5
	var half_w: float = beam_width * 0.5
	if current_phase == Phase.TELEGRAPH:
		var progress: float = clampf(phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
		var rail_col: Color = Color(0.90, 0.90, 0.90, 0.38 + 0.52 * progress)
		draw_line(Vector2(-half_len, -half_w), Vector2(half_len, -half_w), rail_col, 1.6, true)
		draw_line(Vector2(-half_len, half_w), Vector2(half_len, half_w), rail_col, 1.6, true)
	elif current_phase == Phase.ACTIVE:
		var edge_col: Color = Color(1.0, 1.0, 1.0, 0.95)
		draw_line(Vector2(-half_len, -half_w), Vector2(half_len, -half_w), edge_col, 1.5, true)
		draw_line(Vector2(-half_len, half_w), Vector2(half_len, half_w), edge_col, 1.5, true)


func _check_player_overlap() -> void:
	if not is_hazard_active:
		return
	for node: Node in get_tree().get_nodes_in_group("player"):
		var body: Node2D = node as Node2D
		if body != null and _is_within_beam(body):
			body.take_damage(1)
			return


func _is_within_beam(body: Node2D) -> bool:
	var local_pos: Vector2 = to_local(body.global_position)
	return (
		absf(local_pos.x) <= beam_length * 0.5 + PLAYER_HIT_RADIUS
		and absf(local_pos.y) <= beam_width * 0.5 + PLAYER_HIT_RADIUS
	)


func _on_body_entered(body: Node2D) -> void:
	if is_hazard_active and body != null and body.is_in_group("player") and _is_within_beam(body):
		body.take_damage(1)
