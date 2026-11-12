extends Control

const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard"]

@onready var decor_beam_a: Polygon2D = $DecorativeShapes/DecorBeamA
@onready var decor_beam_b: Polygon2D = $DecorativeShapes/DecorBeamB
@onready var decor_square: Polygon2D = $DecorativeShapes/DecorSquare
@onready var ambient_particles: CPUParticles2D = $AmbientParticles
@onready var menu_box: VBoxContainer = $CenterContainer/MenuBox
@onready var title_label: Label = $CenterContainer/MenuBox/TitleLabel
@onready var subtitle_label: Label = $CenterContainer/MenuBox/SubtitleLabel
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
@onready var records_box: PanelContainer = $RecordsPanel/RecordsCenter/RecordsBox
@onready var records_content: VBoxContainer = $RecordsPanel/RecordsCenter/RecordsBox/Content
@onready var records_title_label: Label = $RecordsPanel/RecordsCenter/RecordsBox/Content/Title
@onready var records_player_label: Label = $RecordsPanel/RecordsCenter/RecordsBox/Content/RecordsPlayerLabel
@onready var records_highest_label: Label = $RecordsPanel/RecordsCenter/RecordsBox/Content/RecordsHighestLabel
@onready var personal_stats_box: BoxContainer = $RecordsPanel/RecordsCenter/RecordsBox/Content/PersonalStatsBox
@onready var records_easy_label: Label = $RecordsPanel/RecordsCenter/RecordsBox/Content/PersonalStatsBox/RecordsEasyLabel
@onready var records_normal_label: Label = $RecordsPanel/RecordsCenter/RecordsBox/Content/PersonalStatsBox/RecordsNormalLabel
@onready var records_hard_label: Label = $RecordsPanel/RecordsCenter/RecordsBox/Content/PersonalStatsBox/RecordsHardLabel
@onready var filter_row: HBoxContainer = $RecordsPanel/RecordsCenter/RecordsBox/Content/FilterRow
@onready var filter_all_button: Button = $RecordsPanel/RecordsCenter/RecordsBox/Content/FilterRow/FilterAllButton
@onready var filter_easy_button: Button = $RecordsPanel/RecordsCenter/RecordsBox/Content/FilterRow/FilterEasyButton
@onready var filter_normal_button: Button = $RecordsPanel/RecordsCenter/RecordsBox/Content/FilterRow/FilterNormalButton
@onready var filter_hard_button: Button = $RecordsPanel/RecordsCenter/RecordsBox/Content/FilterRow/FilterHardButton
@onready var leaderboard_scroll: ScrollContainer = $RecordsPanel/RecordsCenter/RecordsBox/Content/LeaderboardScroll
@onready var leaderboard_list: VBoxContainer = $RecordsPanel/RecordsCenter/RecordsBox/Content/LeaderboardScroll/LeaderboardList
@onready var records_close_button: Button = $RecordsPanel/RecordsCenter/RecordsBox/Content/RecordsCloseButton

var selected_difficulty: int = GameManager.Difficulty.NORMAL
var leaderboard_filter: int = -1
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
	_refresh_menu_best_label(name_edit.text)

	name_edit.text_changed.connect(_on_name_text_changed)
	name_edit.text_submitted.connect(_on_name_submitted)
	name_edit.focus_exited.connect(_commit_player_name)
	difficulty_button.pressed.connect(_on_difficulty_pressed)
	play_button.pressed.connect(_on_play_pressed)
	records_button.pressed.connect(_on_records_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	records_close_button.pressed.connect(_on_records_close_pressed)

	filter_all_button.pressed.connect(func() -> void: set_leaderboard_filter(-1))
	filter_easy_button.pressed.connect(func() -> void: set_leaderboard_filter(0))
	filter_normal_button.pressed.connect(func() -> void: set_leaderboard_filter(1))
	filter_hard_button.pressed.connect(func() -> void: set_leaderboard_filter(2))

	for btn: Button in [
		difficulty_button,
		records_button,
		credits_button,
		quit_button,
		records_close_button,
		filter_all_button,
		filter_easy_button,
		filter_normal_button,
		filter_hard_button,
	]:
		UiStyle.add_hover_pop(btn)
	play_button.mouse_entered.connect(func() -> void: SoundManager.play_ui_hover())

	_update_filter_buttons_style()
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


func _on_name_text_changed(new_text: String) -> void:
	_refresh_menu_best_label(new_text)


func _on_name_submitted(_text: String) -> void:
	_commit_player_name()
	name_edit.release_focus()
	play_button.grab_focus()


func _commit_player_name() -> void:
	GameManager.set_player_name(name_edit.text)
	name_edit.text = GameManager.get_player_name()
	_refresh_menu_best_label(name_edit.text)


func _refresh_menu_best_label(for_name: String) -> void:
	var summary: String = GameManager.get_best_summary(for_name)
	var rank: int = GameManager.get_player_rank(-1, for_name)
	if rank > 0:
		best_label.text = "%s   •   #%d" % [summary, rank]
	else:
		best_label.text = summary


func set_leaderboard_filter(filter_mode: int) -> void:
	SoundManager.play_ui_click()
	leaderboard_filter = clampi(filter_mode, -1, 2)
	_update_filter_buttons_style()
	_refresh_records_display()


func _update_filter_buttons_style() -> void:
	var filter_map: Array = [
		[-1, filter_all_button],
		[0, filter_easy_button],
		[1, filter_normal_button],
		[2, filter_hard_button],
	]
	for pair: Array in filter_map:
		var mode: int = int(pair[0])
		var btn: Button = pair[1] as Button
		if btn == null:
			continue
		var is_selected: bool = (leaderboard_filter == mode)
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.content_margin_left = 8.0
		style.content_margin_top = 6.0
		style.content_margin_right = 8.0
		style.content_margin_bottom = 6.0
		style.bg_color = Color(0.92, 0.92, 0.92, 1.0) if is_selected else Color(0.08, 0.08, 0.08, 1.0)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Color(1.0, 1.0, 1.0, 1.0) if is_selected else Color(0.55, 0.55, 0.55, 1.0)
		style.corner_radius_top_left = 2
		style.corner_radius_top_right = 2
		style.corner_radius_bottom_right = 2
		style.corner_radius_bottom_left = 2
		btn.add_theme_stylebox_override("normal", style)
		var fg: Color = Color(0.0, 0.0, 0.0, 1.0) if is_selected else Color(0.92, 0.92, 0.92, 1.0)
		btn.add_theme_color_override("font_color", fg)


func _refresh_records_display() -> void:
	var active_name: String = GameManager.get_player_name()
	var rank: int = GameManager.get_player_rank(leaderboard_filter, active_name)
	var rank_suffix: String = "  •  RANK #%d" % rank if rank > 0 else "  •  UNRANKED"
	records_player_label.text = "PLAYER: %s%s" % [active_name.to_upper(), rank_suffix]
	records_highest_label.text = GameManager.get_best_summary(active_name)
	records_easy_label.text = _format_record_line(0, "EASY")
	records_normal_label.text = _format_record_line(1, "NORMAL")
	records_hard_label.text = _format_record_line(2, "HARD")
	_rebuild_leaderboard_rows()


func _format_record_line(diff_idx: int, diff_name: String) -> String:
	if GameManager.save_data == null:
		return "%s:  No runs recorded" % diff_name
	var rec: Dictionary = GameManager.save_data.get_record(diff_idx)
	if rec.is_empty():
		return "%s:  No runs recorded" % diff_name
	if bool(rec.get("completed", false)):
		return "%s:  COMPLETED (45.0s) ★" % diff_name
	return "%s:  Survived %.1fs" % [diff_name, float(rec.get("time", 0.0))]


func _rebuild_leaderboard_rows() -> void:
	for child: Node in leaderboard_list.get_children():
		leaderboard_list.remove_child(child)
		child.free()

	var entries: Array[Dictionary] = GameManager.get_leaderboard(leaderboard_filter)
	if entries.is_empty():
		var empty_lbl: Label = Label.new()
		empty_lbl.name = "EmptyLeaderboardLabel"
		empty_lbl.text = "No player scores recorded in this category yet.\nEnter your username and press Play to set the #1 record!"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.add_theme_color_override("font_color", Color(0.62, 0.62, 0.62, 1.0))
		empty_lbl.add_theme_font_size_override("font_size", 13)
		leaderboard_list.add_child(empty_lbl)
		return

	var compact: bool = get_viewport_rect().size.x < 560.0
	for entry: Dictionary in entries:
		var rank: int = int(entry.get("rank", 1))
		var p_name: String = str(entry.get("player_name", "PLAYER"))
		var diff_idx: int = int(entry.get("difficulty", 0))
		var diff_str: String = DIFFICULTY_NAMES[clampi(diff_idx, 0, DIFFICULTY_NAMES.size() - 1)].to_upper()
		var completed: bool = bool(entry.get("completed", false))
		var time_val: float = float(entry.get("time", 0.0))
		var is_current: bool = bool(entry.get("is_current", false))

		var row_panel: PanelContainer = PanelContainer.new()
		row_panel.name = "RankRow_%d" % rank
		row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var row_style: StyleBoxFlat = StyleBoxFlat.new()
		row_style.content_margin_left = 10.0
		row_style.content_margin_top = 6.0
		row_style.content_margin_right = 10.0
		row_style.content_margin_bottom = 6.0
		var bg_gray: float = 0.18 if is_current else (0.11 if rank == 1 else 0.07)
		row_style.bg_color = Color(bg_gray, bg_gray, bg_gray, 1.0)
		var border_w: int = 2 if (is_current or rank == 1) else 1
		row_style.border_width_left = border_w
		row_style.border_width_top = border_w
		row_style.border_width_right = border_w
		row_style.border_width_bottom = border_w
		var border_gray: float = 1.0 if is_current else (0.78 if rank == 1 else 0.32)
		row_style.border_color = Color(border_gray, border_gray, border_gray, 1.0)
		row_style.corner_radius_top_left = 2
		row_style.corner_radius_top_right = 2
		row_style.corner_radius_bottom_right = 2
		row_style.corner_radius_bottom_left = 2
		row_panel.add_theme_stylebox_override("panel", row_style)

		var row_hbox: HBoxContainer = HBoxContainer.new()
		row_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_hbox.add_theme_constant_override("separation", 10)
		row_panel.add_child(row_hbox)

		var rank_lbl: Label = Label.new()
		rank_lbl.custom_minimum_size = Vector2(36.0 if compact else 46.0, 0.0)
		rank_lbl.text = "#%d" % rank
		var rank_gray: float = 1.0 if rank <= 3 else 0.78
		rank_lbl.add_theme_color_override("font_color", Color(rank_gray, rank_gray, rank_gray, 1.0))
		rank_lbl.add_theme_font_size_override("font_size", 13 if compact else 14)
		row_hbox.add_child(rank_lbl)

		var name_lbl: Label = Label.new()
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		name_lbl.text = "%s%s" % [p_name, " (YOU)" if is_current else ""]
		var name_gray: float = 1.0 if is_current else 0.90
		name_lbl.add_theme_color_override("font_color", Color(name_gray, name_gray, name_gray, 1.0))
		name_lbl.add_theme_font_size_override("font_size", 13 if compact else 14)
		row_hbox.add_child(name_lbl)

		if leaderboard_filter < 0:
			var tier_lbl: Label = Label.new()
			tier_lbl.custom_minimum_size = Vector2(58.0 if compact else 72.0, 0.0)
			tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tier_lbl.text = "[%s]" % diff_str
			tier_lbl.add_theme_color_override("font_color", Color(0.76, 0.76, 0.76, 1.0))
			tier_lbl.add_theme_font_size_override("font_size", 12 if compact else 13)
			row_hbox.add_child(tier_lbl)

		var score_lbl: Label = Label.new()
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		score_lbl.text = "COMPLETED (45.0s) ★" if completed else ("%.1fs" % time_val if compact else "Survived %.1fs" % time_val)
		var score_gray: float = 1.0 if completed else 0.85
		score_lbl.add_theme_color_override("font_color", Color(score_gray, score_gray, score_gray, 1.0))
		score_lbl.add_theme_font_size_override("font_size", 13 if compact else 14)
		row_hbox.add_child(score_lbl)

		leaderboard_list.add_child(row_panel)


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


func _on_resized(viewport_override: Vector2 = Vector2.ZERO) -> void:
	var view: Vector2 = viewport_override if (viewport_override.x > 0.0 and viewport_override.y > 0.0) else get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		view = Vector2(1152.0, 648.0)

	decor_beam_a.position = Vector2(view.x * 0.5, view.y * 0.28)
	decor_beam_b.position = Vector2(view.x * 0.5, view.y * 0.77)
	ambient_particles.position = Vector2(view.x * 0.5, view.y + 12.0)
	ambient_particles.emission_rect_extents = Vector2(view.x * 0.5, 4.0)

	var compact_h: bool = view.y < 540.0
	var compact_w: bool = view.x < 560.0
	var menu_w: float = clampf(view.x - 48.0, 240.0, 340.0)
	menu_box.custom_minimum_size.x = menu_w
	menu_box.add_theme_constant_override("separation", 8 if compact_h else 12)
	title_label.add_theme_font_size_override("font_size", 28 if (compact_w or compact_h) else 40)
	subtitle_label.add_theme_font_size_override("font_size", 13 if (compact_w or compact_h) else 16)

	var btn_h: float = 36.0 if compact_h else 46.0
	name_edit.custom_minimum_size = Vector2(minf(240.0, menu_w), 36.0 if compact_h else 42.0)
	for btn: Button in [difficulty_button, play_button, records_button, credits_button, quit_button]:
		btn.custom_minimum_size = Vector2(minf(240.0, menu_w), btn_h)
		btn.add_theme_font_size_override("font_size", 16 if compact_h else 19)

	var rec_w: float = clampf(view.x - 36.0, 290.0, 660.0)
	var rec_h: float = clampf(view.y - 36.0, 300.0, 540.0)
	records_box.custom_minimum_size = Vector2(rec_w, rec_h)
	records_content.add_theme_constant_override("separation", 6 if compact_h else 10)
	records_title_label.add_theme_font_size_override("font_size", 19 if compact_w else 24)
	personal_stats_box.vertical = rec_w < 500.0
	personal_stats_box.add_theme_constant_override("separation", 4 if personal_stats_box.vertical else 12)
	leaderboard_scroll.custom_minimum_size.y = clampf(rec_h - (270.0 if personal_stats_box.vertical else 230.0), 90.0, 260.0)
	records_close_button.custom_minimum_size = Vector2(minf(200.0, rec_w - 44.0), 36.0 if compact_h else 42.0)

	var tracker_w: float = clampf(view.x - 40.0, 180.0, 260.0)
	tracker_bar_bg.custom_minimum_size.x = tracker_w
	tracker_progress_box.offset_left = -tracker_w * 0.5
	tracker_progress_box.offset_right = tracker_w * 0.5

	if records_panel.visible:
		_rebuild_leaderboard_rows()


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
	var bar_w: float = maxf(tracker_bar_bg.size.x, tracker_bar_bg.custom_minimum_size.x)
	tracker_bar_fill.size = Vector2(bar_w * _tracker_progress_value, tracker_bar_bg.size.y)
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
