extends Control

const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard"]

@onready var decor_beam_a: Polygon2D = $DecorativeShapes/DecorBeamA
@onready var decor_beam_b: Polygon2D = $DecorativeShapes/DecorBeamB
@onready var decor_square: Polygon2D = $DecorativeShapes/DecorSquare
@onready var ambient_particles: CPUParticles2D = $AmbientParticles
@onready var best_label: Label = $CenterContainer/MenuBox/BestLabel
@onready var name_edit: LineEdit = $CenterContainer/MenuBox/NameEdit
@onready var difficulty_button: Button = $CenterContainer/MenuBox/DifficultyButton
@onready var play_button: Button = $CenterContainer/MenuBox/PlayButton
@onready var records_button: Button = $CenterContainer/MenuBox/RecordsButton
@onready var credits_button: Button = $CenterContainer/MenuBox/CreditsButton
@onready var quit_button: Button = $CenterContainer/MenuBox/QuitButton
@onready var tracker_progress_box: VBoxContainer = $TrackerProgressBox
@onready var tracker_status_label: Label = $TrackerProgressBox/TrackerStatusLabel
@onready var tracker_bar_bg: ColorRect = $TrackerProgressBox/TrackerBarBg
@onready var tracker_bar_fill: ColorRect = $TrackerProgressBox/TrackerBarBg/TrackerBarFill
@onready var records_panel: ColorRect = $RecordsPanel
@onready var records_player_label: Label = $RecordsPanel/RecordsCenter/RecordsBox/Content/RecordsPlayerLabel
@onready var records_highest_label: Label = $RecordsPanel/RecordsCenter/RecordsBox/Content/RecordsHighestLabel
@onready var records_easy_label: Label = $RecordsPanel/RecordsCenter/RecordsBox/Content/RecordsEasyLabel
@onready var records_normal_label: Label = $RecordsPanel/RecordsCenter/RecordsBox/Content/RecordsNormalLabel
@onready var records_hard_label: Label = $RecordsPanel/RecordsCenter/RecordsBox/Content/RecordsHardLabel
@onready var records_close_button: Button = $RecordsPanel/RecordsCenter/RecordsBox/Content/RecordsCloseButton

var selected_difficulty: int = GameManager.Difficulty.NORMAL
var _anim_time: float = 0.0
var _square_pos: Vector2 = Vector2(210.0, 160.0)
var _square_vel: Vector2 = Vector2(135.0, 95.0)
var _tracker_progress_value: float = 0.08
var _tracker_done_hold_timer: float = 0.0
var _tracker_fade_alpha: float = 1.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	selected_difficulty = GameManager.selected_difficulty
	_update_difficulty_button_text()

	name_edit.text = GameManager.get_player_name()
	best_label.text = GameManager.get_best_summary()

	name_edit.text_submitted.connect(_on_name_submitted)
	name_edit.focus_exited.connect(_commit_player_name)
	difficulty_button.pressed.connect(_on_difficulty_pressed)
	play_button.pressed.connect(_on_play_pressed)
	records_button.pressed.connect(_on_records_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	records_close_button.pressed.connect(_on_records_close_pressed)

	for btn: Button in [difficulty_button, records_button, credits_button, quit_button, records_close_button]:
		UiStyle.add_hover_pop(btn)
	play_button.mouse_entered.connect(func() -> void: SoundManager.play_ui_hover())

	_start_play_pulse()
	_update_tracker_progress(0.0)
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()
	play_button.grab_focus()


func _process(delta: float) -> void:
	_anim_time += delta
	var view: Vector2 = get_viewport_rect().size
	var margin: float = 34.0
	_square_pos += _square_vel * delta
	if _square_pos.x < margin or _square_pos.x > view.x - margin:
		_square_pos.x = clampf(_square_pos.x, margin, view.x - margin)
		_square_vel.x = -_square_vel.x
	if _square_pos.y < margin or _square_pos.y > view.y - margin:
		_square_pos.y = clampf(_square_pos.y, margin, view.y - margin)
		_square_vel.y = -_square_vel.y

	decor_square.position = _square_pos
	decor_square.rotation = _anim_time * 0.65
	var sq_gray: float = 0.24 + 0.06 * sin(_anim_time * 2.4)
	decor_square.color = Color(sq_gray, sq_gray, sq_gray, 0.65)

	var pulse_a: float = 0.16 + 0.06 * sin(_anim_time * 2.0)
	decor_beam_a.color = Color(pulse_a, pulse_a, pulse_a, 1.0)
	var pulse_b: float = 0.12 + 0.05 * cos(_anim_time * 1.6)
	decor_beam_b.color = Color(pulse_b, pulse_b, pulse_b, 1.0)

	_update_tracker_progress(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and records_panel.visible:
		_on_records_close_pressed()


func set_difficulty(mode: int) -> void:
	selected_difficulty = posmod(mode, DIFFICULTY_NAMES.size())
	GameManager.set_difficulty(selected_difficulty)
	_update_difficulty_button_text()


func get_difficulty_name() -> String:
	return DIFFICULTY_NAMES[posmod(selected_difficulty, DIFFICULTY_NAMES.size())]


func _update_difficulty_button_text() -> void:
	difficulty_button.text = "Difficulty: %s" % get_difficulty_name()


func _on_difficulty_pressed() -> void:
	SoundManager.play_ui_click()
	set_difficulty((selected_difficulty + 1) % DIFFICULTY_NAMES.size())


func _on_play_pressed() -> void:
	SoundManager.play_ui_click()
	_commit_player_name()
	GameManager.start_level(selected_difficulty)


func _on_quit_pressed() -> void:
	SoundManager.play_ui_click()
	HandTrackingClient.stop_tracker_process()
	get_tree().quit()


func _on_credits_pressed() -> void:
	SoundManager.play_ui_click()
	_commit_player_name()
	GameManager.go_to_credits()


func _on_records_pressed() -> void:
	SoundManager.play_ui_click()
	_commit_player_name()
	_refresh_records_display()
	records_panel.visible = true
	records_close_button.grab_focus()


func _on_records_close_pressed() -> void:
	SoundManager.play_ui_click()
	records_panel.visible = false
	records_button.grab_focus()


func _on_name_submitted(_text: String) -> void:
	_commit_player_name()
	name_edit.release_focus()
	play_button.grab_focus()


func _commit_player_name() -> void:
	GameManager.set_player_name(name_edit.text)
	name_edit.text = GameManager.get_player_name()


func _refresh_records_display() -> void:
	records_player_label.text = "PLAYER: %s" % GameManager.get_player_name().to_upper()
	records_highest_label.text = GameManager.get_best_summary()
	records_easy_label.text = _format_record_line(0, "EASY  ")
	records_normal_label.text = _format_record_line(1, "NORMAL")
	records_hard_label.text = _format_record_line(2, "HARD  ")


func _format_record_line(diff_idx: int, diff_name: String) -> String:
	if GameManager.save_data == null:
		return "%s:  No runs recorded" % diff_name
	var rec: Dictionary = GameManager.save_data.get_record(diff_idx)
	if rec.is_empty():
		return "%s:  No runs recorded" % diff_name
	if bool(rec.get("completed", false)):
		return "%s:  COMPLETED (45.0s) ★" % diff_name
	return "%s:  Survived %.1fs" % [diff_name, float(rec.get("time", 0.0))]


func _start_play_pulse() -> void:
	play_button.pivot_offset = play_button.size * 0.5
	play_button.resized.connect(func() -> void: play_button.pivot_offset = play_button.size * 0.5)
	var normal_box: StyleBoxFlat = play_button.get_theme_stylebox("normal") as StyleBoxFlat
	var tw: Tween = create_tween().set_loops()
	tw.set_parallel(true)
	tw.tween_property(play_button, "scale", Vector2.ONE * 1.06, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if normal_box != null:
		tw.tween_property(normal_box, "shadow_size", 18, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(normal_box, "shadow_color:a", 0.5, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_property(play_button, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if normal_box != null:
		tw.parallel().tween_property(normal_box, "shadow_size", 0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.parallel().tween_property(normal_box, "shadow_color:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_resized() -> void:
	var view: Vector2 = get_viewport_rect().size
	decor_beam_a.position = Vector2(view.x * 0.5, view.y * 0.28)
	decor_beam_b.position = Vector2(view.x * 0.5, view.y * 0.77)
	ambient_particles.position = Vector2(view.x * 0.5, view.y + 12.0)
	ambient_particles.emission_rect_extents = Vector2(view.x * 0.5, 4.0)


func _update_tracker_progress(delta: float) -> void:
	var info: Dictionary = HandTrackingClient.get_startup_progress_info()
	var target_progress: float = clampf(float(info.get("progress", 0.08)), 0.0, 1.0)
	var label_str: String = str(info.get("text", "HAND TRACKER: STARTING..."))
	var is_done: bool = bool(info.get("done", false))
	var is_failed: bool = bool(info.get("failed", false))

	_tracker_progress_value = move_toward(_tracker_progress_value, target_progress, delta * 1.8) if delta > 0.0 else target_progress
	if tracker_status_label.text != label_str:
		tracker_status_label.text = label_str

	var fill_gray: float = 0.45 if is_failed else (1.0 if is_done else 0.88)
	tracker_bar_fill.size = Vector2(tracker_bar_bg.size.x * _tracker_progress_value, tracker_bar_bg.size.y)
	tracker_bar_fill.color = Color(fill_gray, fill_gray, fill_gray, 1.0)

	if is_done:
		_tracker_done_hold_timer += maxf(0.0, delta)
		if _tracker_done_hold_timer >= 1.5:
			_tracker_fade_alpha = maxf(0.0, _tracker_fade_alpha - maxf(0.0, delta) * 2.0)
	else:
		_tracker_done_hold_timer = 0.0
		_tracker_fade_alpha = 1.0

	tracker_progress_box.modulate = Color(1.0, 1.0, 1.0, _tracker_fade_alpha)
	tracker_progress_box.visible = _tracker_fade_alpha > 0.01
