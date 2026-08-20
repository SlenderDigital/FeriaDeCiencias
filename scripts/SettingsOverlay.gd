extends Control
## SettingsOverlay — Slides down from top rail when gear icon clicked.

@onready var panel: PanelContainer = $Panel
@onready var slider_master: HSlider = $Panel/VBox/Grid/SliderMaster
@onready var slider_music: HSlider = $Panel/VBox/Grid/SliderMusic
@onready var slider_sfx: HSlider = $Panel/VBox/Grid/SliderSFX
@onready var check_fullscreen: CheckButton = $Panel/VBox/Grid/CheckFullscreen
@onready var btn_close: Button = $Panel/VBox/BtnClose

func _ready() -> void:
	visible = false
	panel.visible = false
	
	if GameManager:
		slider_master.value = GameManager.master_volume
		slider_music.value = GameManager.music_volume
		slider_sfx.value = GameManager.sfx_volume
		check_fullscreen.button_pressed = GameManager.fullscreen_enabled
	
	slider_master.value_changed.connect(_on_master_changed)
	slider_music.value_changed.connect(_on_music_changed)
	slider_sfx.value_changed.connect(_on_sfx_changed)
	check_fullscreen.toggled.connect(_on_fullscreen_toggled)

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

func _on_master_changed(value: float) -> void:
	if GameManager: GameManager.master_volume = value
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))

func _on_music_changed(value: float) -> void:
	if GameManager: GameManager.music_volume = value

func _on_sfx_changed(value: float) -> void:
	if GameManager: GameManager.sfx_volume = value

func _on_fullscreen_toggled(pressed: bool) -> void:
	if GameManager: GameManager.fullscreen_enabled = pressed
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide_overlay()