extends CanvasLayer

signal retry_requested
signal main_menu_requested

var _hud_timer_bucket: int = -1
var _last_shield_ratio: float = -1.0
var _last_shield_state: String = ""
var _last_hand_state: int = -1
var _last_hand_label: String = ""
var _last_hand_pulse_bucket: int = -1

@onready var progress_bg: ColorRect = $HUDRoot/ProgressBg
@onready var progress_fill: ColorRect = $HUDRoot/ProgressFill
@onready var hp_label: Label = $HUDRoot/HPLabel
@onready var shield_label: Label = $HUDRoot/ShieldLabel
@onready var shield_bg: ColorRect = $HUDRoot/ShieldBg
@onready var shield_fill: ColorRect = $HUDRoot/ShieldFill
@onready var timer_label: Label = $HUDRoot/TimerLabel
@onready var controls_hint_label: Label = $HUDRoot/ControlsHintLabel
@onready var hand_status_pill: ColorRect = $HUDRoot/HandStatusPill
@onready var hand_status_icon: Polygon2D = $HUDRoot/HandStatusPill/HandStatusIcon
@onready var hand_status_label: Label = $HUDRoot/HandStatusPill/HandStatusLabel
@onready var game_over_panel: ColorRect = $HUDRoot/GameOverPanel
@onready var game_over_box: VBoxContainer = $HUDRoot/GameOverPanel/VBoxContainer
@onready var game_over_subtitle: Label = $HUDRoot/GameOverPanel/VBoxContainer/GameOverSubtitle
@onready var retry_button: Button = $HUDRoot/GameOverPanel/VBoxContainer/RetryButton
@onready var game_over_menu_button: Button = $HUDRoot/GameOverPanel/VBoxContainer/GameOverMainMenuButton
@onready var level_complete_panel: ColorRect = $HUDRoot/LevelCompletePanel
@onready var level_complete_box: VBoxContainer = $HUDRoot/LevelCompletePanel/VBoxContainer
@onready var level_complete_subtitle: Label = $HUDRoot/LevelCompletePanel/VBoxContainer/LevelCompleteSubtitle
@onready var replay_button: Button = $HUDRoot/LevelCompletePanel/VBoxContainer/ReplayButton
@onready var complete_menu_button: Button = $HUDRoot/LevelCompletePanel/VBoxContainer/CompleteMainMenuButton


func _ready() -> void:
	game_over_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level_complete_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	retry_button.pressed.connect(func() -> void: retry_requested.emit())
	replay_button.pressed.connect(func() -> void: retry_requested.emit())
	game_over_menu_button.pressed.connect(func() -> void: main_menu_requested.emit())
	complete_menu_button.pressed.connect(func() -> void: main_menu_requested.emit())


func reset(duration: float) -> void:
	_hud_timer_bucket = -1
	_last_shield_ratio = -1.0
	_last_shield_state = ""
	game_over_panel.visible = false
	level_complete_panel.visible = false
	update_timer(0.0, duration)
	update_hp(3, 3)


func update_timer(elapsed: float, duration: float) -> void:
	var remaining: float = maxf(0.0, duration - elapsed)
	var tenths: int = int(round(remaining * 10.0))
	if tenths != _hud_timer_bucket:
		timer_label.text = "TIME: %.1fs" % remaining
		_hud_timer_bucket = tenths
	var ratio: float = clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	progress_fill.size.x = progress_bg.size.x * ratio


func update_hp(new_hp: int, max_hp: int) -> void:
	var blocks: String = ""
	for i: int in range(max_hp):
		blocks += "■ " if i < new_hp else "□ "
	hp_label.text = "HP: %s(%d/%d)" % [blocks, new_hp, max_hp]


func update_shield(ratio: float, is_active: bool, is_exhausted: bool) -> void:
	var clamped_ratio: float = clampf(ratio, 0.0, 1.0)
	var state_text: String = "SHIELD: READY"
	var state_gray: float = 0.82
	if is_active:
		state_text = "SHIELD: ACTIVE"
		state_gray = 1.0
	elif is_exhausted:
		state_text = "SHIELD: EMPTY"
		state_gray = 0.45
	elif clamped_ratio < 0.999:
		state_text = "SHIELD: RECHARGING"
		state_gray = 0.65

	if absf(clamped_ratio - _last_shield_ratio) > 0.008:
		shield_fill.size.x = maxf(0.0, shield_bg.size.x * clamped_ratio)
		var fill_gray: float = 0.42 if is_exhausted else lerpf(0.60, 1.0, clamped_ratio)
		shield_fill.color = Color(fill_gray, fill_gray, fill_gray, 1.0)
		_last_shield_ratio = clamped_ratio

	if state_text != _last_shield_state:
		shield_label.text = state_text
		shield_label.add_theme_color_override("font_color", Color(state_gray, state_gray, state_gray, 1.0))
		_last_shield_state = state_text


func update_hand_status(state: int, label_str: String, pulse: float) -> void:
	if hand_status_label.text != label_str:
		hand_status_label.text = label_str
	if state != _last_hand_state or label_str != _last_hand_label:
		match state:
			2:
				hand_status_label.add_theme_color_override("font_color", Color.WHITE)
				hand_status_icon.color = Color.WHITE
			1:
				hand_status_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1.0))
				hand_status_icon.color = Color(0.68, 0.68, 0.68, 1.0)
			_:
				hand_status_label.add_theme_color_override("font_color", Color(0.50, 0.50, 0.50, 1.0))
				hand_status_icon.color = Color(0.38, 0.38, 0.38, 1.0)
		var pill_gray: float = 0.16 if state == 2 else 0.12
		hand_status_pill.color = Color(pill_gray, pill_gray, pill_gray, 0.92)
		hand_status_icon.scale = Vector2.ONE

	var pulse_bucket: int = int(pulse * 8.0)
	if pulse_bucket != _last_hand_pulse_bucket:
		var icon_scale: float = 1.0 + 0.25 * pulse if state == 2 else 1.0
		hand_status_icon.scale = Vector2(icon_scale, icon_scale)

	_last_hand_state = state
	_last_hand_label = label_str
	_last_hand_pulse_bucket = pulse_bucket


func show_game_over(subtitle_text: String) -> void:
	game_over_subtitle.text = subtitle_text
	game_over_panel.visible = true
	retry_button.grab_focus()


func show_level_complete(subtitle_text: String) -> void:
	level_complete_subtitle.text = subtitle_text
	level_complete_panel.visible = true
	replay_button.grab_focus()


func sync_layout(viewport_size: Vector2) -> void:
	if viewport_size.x > 48.0:
		progress_bg.size.x = viewport_size.x - 48.0
	if viewport_size.x > 160.0:
		timer_label.position.x = viewport_size.x - 150.0
	if viewport_size.x > 240.0:
		hand_status_pill.position.x = (viewport_size.x - hand_status_pill.size.x) * 0.5
		hand_status_pill.position.y = 84.0 if viewport_size.x < 620.0 else 26.0
	if viewport_size.y > 40.0:
		controls_hint_label.position.y = viewport_size.y - 34.0
		controls_hint_label.size.x = maxf(200.0, viewport_size.x - 48.0)
		controls_hint_label.clip_text = viewport_size.x < 720.0
	var modal_half_w: float = clampf((viewport_size.x - 40.0) * 0.5, 140.0, 240.0)
	for box: VBoxContainer in [game_over_box, level_complete_box]:
		if box != null:
			box.custom_minimum_size.x = modal_half_w * 2.0
			box.offset_left = -modal_half_w
			box.offset_right = modal_half_w
