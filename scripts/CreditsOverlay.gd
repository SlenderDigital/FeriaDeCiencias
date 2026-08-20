extends Control
## CreditsOverlay — Slides down from top rail when info icon clicked.

@onready var panel: PanelContainer = $Panel
@onready var btn_close: Button = $Panel/VBox/BtnClose

func _ready() -> void:
	visible = false
	panel.visible = false

func show_overlay() -> void:
	visible = true
	panel.visible = true
	panel.global_position = Vector2(get_viewport_rect().size.x * 0.5, -panel.size.y * 0.5)
	var tween = create_tween()
	tween.tween_property(panel, "global_position:y", get_viewport_rect().size.y * 0.5 - panel.size.y * 0.5, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_overlay() -> void:
	var tween = create_tween()
	tween.tween_property(panel, "global_position:y", -panel.size.y * 0.5, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(close_complete)

func close_complete() -> void:
	visible = false
	panel.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide_overlay()