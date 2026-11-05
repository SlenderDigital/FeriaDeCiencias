extends Control

@onready var decor_square: Polygon2D = $DecorSquare
@onready var ambient_particles: CPUParticles2D = $AmbientParticles
@onready var clip: Control = $ScrollClip
@onready var column: VBoxContainer = $ScrollClip/CreditsColumn
@onready var back_button: Button = $BackButton

var _scroll_time: float = 0.0
var _scroll_tween: Tween = null


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	UiStyle.add_hover_pop(back_button)
	back_button.pressed.connect(_on_back_pressed)
	back_button.grab_focus()
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()
	_start_scroll()


func _process(delta: float) -> void:
	_scroll_time += delta
	decor_square.rotation = _scroll_time * 0.4
	var g: float = 0.10 + 0.05 * sin(_scroll_time * 1.4)
	decor_square.color = Color(g, g, g, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()


func _on_resized() -> void:
	var view: Vector2 = get_viewport_rect().size
	decor_square.position = view * 0.5
	decor_square.scale = Vector2.ONE * clampf(view.y / 648.0, 0.6, 2.0)
	ambient_particles.position = Vector2(view.x * 0.5, view.y + 10.0)
	ambient_particles.emission_rect_extents = Vector2(view.x * 0.5, 4.0)
	column.size.x = clip.size.x
	column.position.x = 0.0


func _start_scroll() -> void:
	await get_tree().process_frame
	column.size.x = clip.size.x
	var view_h: float = clip.size.y
	var col_h: float = column.get_combined_minimum_size().y
	column.position.y = view_h
	if _scroll_tween != null:
		_scroll_tween.kill()
	_scroll_tween = create_tween().set_loops()
	_scroll_tween.tween_property(column, "position:y", -col_h, (view_h + col_h) / 48.0).from(view_h)


func _on_back_pressed() -> void:
	SoundManager.play_ui_click()
	GameManager.go_to_menu()
