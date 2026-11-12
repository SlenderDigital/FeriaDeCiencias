class_name SpectatorRankingView
extends Control
## Big-screen Kiosk / Spectator Ranking Dashboard designed for distance readability.
##
## Uses oversized high-contrast typography and a 2-board layout (Global Standings +
## Featured/Active Difficulty Tier) that automatically scales font sizes to the
## monitor resolution so spectators can read every rank, name, and time from far away.

const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard"]
const TOP_LIMIT: int = 8
const TIER_CYCLE_INTERVAL: float = 6.0

var background: ColorRect = null
var root_margin: MarginContainer = null
var main_vbox: VBoxContainer = null
var header_panel: PanelContainer = null
var title_label: Label = null
var mode_badge_label: Label = null
var now_playing_panel: PanelContainer = null
var now_playing_style: StyleBoxFlat = null
var player_label: Label = null
var best_rank_label: Label = null
var status_label: Label = null
var hp_label: Label = null
var progress_bg: ColorRect = null
var progress_fill: ColorRect = null
var record_banner_label: Label = null
var columns_grid: GridContainer = null

var _column_panels: Dictionary = {}
var _column_headers: Dictionary = {}
var _column_lists: Dictionary = {}
var _column_styles: Dictionary = {}

var _preview_player_name: String = ""
var _live_elapsed: float = 0.0
var _live_duration: float = 45.0
var _live_hp: int = 3
var _live_max_hp: int = 3
var _record_flash_timer: float = 0.0
var _pulse_time: float = 0.0
var _tier_cycle_timer: float = 0.0
var _cycled_difficulty: int = 2
var _ui_scale: float = 1.0


func _init() -> void:
	name = "SpectatorRankingView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	_build_ui()


func _ready() -> void:
	_preview_player_name = GameManager.get_player_name()
	_cycled_difficulty = GameManager.selected_difficulty
	GameManager.player_name_changed.connect(_on_player_name_changed)
	GameManager.preview_name_changed.connect(_on_preview_name_changed)
	GameManager.difficulty_changed.connect(_on_difficulty_changed)
	GameManager.state_changed.connect(_on_state_changed)
	GameManager.record_updated.connect(_on_record_updated)
	GameManager.live_telemetry_updated.connect(_on_live_telemetry_updated)
	resized.connect(_on_resized)
	_on_resized()
	refresh_all()


func _process(delta: float) -> void:
	_pulse_time += delta
	if _record_flash_timer > 0.0:
		_record_flash_timer = maxf(0.0, _record_flash_timer - delta)
		var flash_val: float = 0.24 + 0.16 * (0.5 + 0.5 * sin(_pulse_time * 12.0))
		if now_playing_style != null:
			now_playing_style.bg_color = Color(flash_val, flash_val, flash_val, 1.0)
			now_playing_style.border_color = Color.WHITE
		if _record_flash_timer <= 0.0:
			record_banner_label.visible = false
			if now_playing_style != null:
				now_playing_style.bg_color = Color(0.08, 0.08, 0.08, 1.0)
				now_playing_style.border_color = Color(0.90, 0.90, 0.90, 1.0)

	# When in Menu/Credits, gently cycle the right-hand tier board so spectators from
	# afar can see Easy, Normal, and Hard leaderboards in giant text.
	if GameManager.state != GameManager.State.PLAYING:
		_tier_cycle_timer += delta
		if _tier_cycle_timer >= TIER_CYCLE_INTERVAL:
			_tier_cycle_timer = 0.0
			_cycled_difficulty = posmod(_cycled_difficulty - 1, 3)
			_update_visible_tier_columns()


func _build_ui() -> void:
	background = ColorRect.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.015, 0.015, 0.015, 1.0)
	add_child(background)

	root_margin = MarginContainer.new()
	root_margin.name = "RootMargin"
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", 24)
	root_margin.add_theme_constant_override("margin_top", 20)
	root_margin.add_theme_constant_override("margin_right", 24)
	root_margin.add_theme_constant_override("margin_bottom", 20)
	add_child(root_margin)

	main_vbox = VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 14)
	root_margin.add_child(main_vbox)

	header_panel = PanelContainer.new()
	header_panel.name = "HeaderPanel"
	var header_style: StyleBoxFlat = _make_box_style(0.05, 1.0, 3, 18, 14)
	header_panel.add_theme_stylebox_override("panel", header_style)
	main_vbox.add_child(header_panel)

	var header_vbox: VBoxContainer = VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 10)
	header_panel.add_child(header_vbox)

	var top_bar: HBoxContainer = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 16)
	header_vbox.add_child(top_bar)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.text = "SHAPES & BEAMS   •   LIVE LEADERBOARD"
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.add_theme_font_size_override("font_size", 32)
	top_bar.add_child(title_label)

	mode_badge_label = Label.new()
	mode_badge_label.name = "ModeBadgeLabel"
	mode_badge_label.text = "LIVE SPECTATOR SCREEN"
	mode_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mode_badge_label.add_theme_color_override("font_color", Color(0.76, 0.76, 0.76, 1.0))
	mode_badge_label.add_theme_font_size_override("font_size", 18)
	top_bar.add_child(mode_badge_label)

	now_playing_panel = PanelContainer.new()
	now_playing_panel.name = "NowPlayingPanel"
	now_playing_style = _make_box_style(0.09, 0.90, 2, 16, 12)
	now_playing_panel.add_theme_stylebox_override("panel", now_playing_style)
	header_vbox.add_child(now_playing_panel)

	var np_vbox: VBoxContainer = VBoxContainer.new()
	np_vbox.add_theme_constant_override("separation", 8)
	now_playing_panel.add_child(np_vbox)

	var np_top_row: HBoxContainer = HBoxContainer.new()
	np_top_row.add_theme_constant_override("separation", 20)
	np_vbox.add_child(np_top_row)

	player_label = Label.new()
	player_label.name = "NowPlayingPlayerLabel"
	player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_label.text = "NOW PLAYING: PLAYER"
	player_label.add_theme_color_override("font_color", Color.WHITE)
	player_label.add_theme_font_size_override("font_size", 28)
	np_top_row.add_child(player_label)

	best_rank_label = Label.new()
	best_rank_label.name = "NowPlayingBestLabel"
	best_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	best_rank_label.text = "No runs yet"
	best_rank_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	best_rank_label.add_theme_font_size_override("font_size", 24)
	np_top_row.add_child(best_rank_label)

	var np_status_row: HBoxContainer = HBoxContainer.new()
	np_status_row.add_theme_constant_override("separation", 20)
	np_vbox.add_child(np_status_row)

	status_label = Label.new()
	status_label.name = "NowPlayingStatusLabel"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.text = "STATUS: IN MENU"
	status_label.add_theme_color_override("font_color", Color(0.86, 0.86, 0.86, 1.0))
	status_label.add_theme_font_size_override("font_size", 21)
	np_status_row.add_child(status_label)

	hp_label = Label.new()
	hp_label.name = "NowPlayingHPLabel"
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_label.text = "HP: ■ ■ ■ (3/3)"
	hp_label.add_theme_color_override("font_color", Color.WHITE)
	hp_label.add_theme_font_size_override("font_size", 22)
	np_status_row.add_child(hp_label)

	progress_bg = ColorRect.new()
	progress_bg.name = "LiveProgressBg"
	progress_bg.custom_minimum_size = Vector2(0.0, 14.0)
	progress_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bg.color = Color(0.20, 0.20, 0.20, 1.0)
	np_vbox.add_child(progress_bg)

	progress_fill = ColorRect.new()
	progress_fill.name = "LiveProgressFill"
	progress_fill.position = Vector2.ZERO
	progress_fill.size = Vector2(0.0, 14.0)
	progress_fill.color = Color.WHITE
	progress_bg.add_child(progress_fill)

	record_banner_label = Label.new()
	record_banner_label.name = "RecordBannerLabel"
	record_banner_label.visible = false
	record_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	record_banner_label.text = "★ NEW PERSONAL RECORD! ★"
	record_banner_label.add_theme_color_override("font_color", Color.WHITE)
	record_banner_label.add_theme_font_size_override("font_size", 26)
	np_vbox.add_child(record_banner_label)

	columns_grid = GridContainer.new()
	columns_grid.name = "ColumnsGrid"
	columns_grid.columns = 2
	columns_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns_grid.add_theme_constant_override("h_separation", 18)
	columns_grid.add_theme_constant_override("v_separation", 16)
	main_vbox.add_child(columns_grid)

	var col_configs: Array = [
		[-1, "GLOBAL TOP RANKING"],
		[2, "HARD TIER RANKING"],
		[1, "NORMAL TIER RANKING"],
		[0, "EASY TIER RANKING"],
	]
	for cfg: Array in col_configs:
		var filter_id: int = int(cfg[0])
		var col_title: String = str(cfg[1])
		var col_panel: PanelContainer = PanelContainer.new()
		col_panel.name = "Column_%d" % filter_id
		col_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var col_style: StyleBoxFlat = _make_box_style(0.05, 0.85, 3, 16, 14)
		col_panel.add_theme_stylebox_override("panel", col_style)
		columns_grid.add_child(col_panel)

		var col_vbox: VBoxContainer = VBoxContainer.new()
		col_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col_vbox.add_theme_constant_override("separation", 10)
		col_panel.add_child(col_vbox)

		var col_header: Label = Label.new()
		col_header.name = "ColumnHeader"
		col_header.text = col_title
		col_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col_header.add_theme_color_override("font_color", Color.WHITE)
		col_header.add_theme_font_size_override("font_size", 26)
		col_vbox.add_child(col_header)

		var sep: HSeparator = HSeparator.new()
		var sep_style: StyleBoxLine = StyleBoxLine.new()
		sep_style.color = Color(0.55, 0.55, 0.55, 1.0)
		sep_style.thickness = 2
		sep.add_theme_stylebox_override("separator", sep_style)
		col_vbox.add_child(sep)

		var scroll: ScrollContainer = ScrollContainer.new()
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col_vbox.add_child(scroll)

		var list_vbox: VBoxContainer = VBoxContainer.new()
		list_vbox.name = "List"
		list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_vbox.add_theme_constant_override("separation", 8)
		scroll.add_child(list_vbox)

		_column_panels[filter_id] = col_panel
		_column_headers[filter_id] = col_header
		_column_lists[filter_id] = list_vbox
		_column_styles[filter_id] = col_style


func _get_featured_difficulty() -> int:
	if GameManager.state == GameManager.State.PLAYING:
		return GameManager.selected_difficulty
	return _cycled_difficulty


func _update_visible_tier_columns() -> void:
	var featured: int = _get_featured_difficulty()
	for filter_id: int in [-1, 2, 1, 0]:
		var panel: PanelContainer = _column_panels.get(filter_id) as PanelContainer
		if panel == null:
			continue
		panel.visible = (filter_id == -1 or filter_id == featured)


func refresh_all() -> void:
	_refresh_header()
	_refresh_columns()
	_update_visible_tier_columns()


func _refresh_header() -> void:
	var active_name: String = _preview_player_name if not _preview_player_name.is_empty() else GameManager.get_player_name()
	var cleaned_name: String = SaveData.clean_player_name(active_name, GameManager.MAX_NAME_LENGTH)
	var diff_name: String = GameManager.get_difficulty_name(GameManager.selected_difficulty).to_upper()
	player_label.text = "PLAYER: %s   [%s]" % [cleaned_name.to_upper(), diff_name]

	var best_str: String = GameManager.get_best_summary(cleaned_name)
	var global_rank: int = GameManager.get_player_rank(-1, cleaned_name)
	best_rank_label.text = "%s   •   RANK #%d" % [best_str, global_rank] if global_rank > 0 else best_str

	var screens: int = GameManager.get_available_screen_count()
	mode_badge_label.text = "DUAL DISPLAY (%d SCREENS)" % screens if screens >= 2 else "SPECTATOR DISPLAY (F10)"

	_update_live_run_widgets()


func _update_live_run_widgets() -> void:
	var st: int = GameManager.state
	var ratio: float = 0.0
	match st:
		GameManager.State.PLAYING:
			var remaining: float = maxf(0.0, _live_duration - _live_elapsed)
			status_label.text = "LIVE RUN: %.1fs / %.0fs   (%.1fs LEFT)" % [_live_elapsed, _live_duration, remaining]
			hp_label.visible = true
			var blocks: String = ""
			for i: int in range(_live_max_hp):
				blocks += "■ " if i < _live_hp else "□ "
			hp_label.text = "HP: %s(%d/%d)" % [blocks, _live_hp, _live_max_hp]
			ratio = clampf(_live_elapsed / maxf(_live_duration, 0.001), 0.0, 1.0)
		GameManager.State.COMPLETE:
			status_label.text = "★ LEVEL COMPLETE — SURVIVED FULL 45.0s! ★"
			hp_label.visible = false
			ratio = 1.0
		GameManager.State.GAME_OVER:
			status_label.text = "LAST RUN: %.1fs   •   NEXT PLAYER STEP UP!" % _live_elapsed
			hp_label.visible = false
			ratio = clampf(_live_elapsed / maxf(_live_duration, 0.001), 0.0, 1.0)
		_:
			status_label.text = "ENTER YOUR NAME TO COMPETE FOR #1"
			hp_label.visible = false
			ratio = 0.0

	var bar_w: float = maxf(progress_bg.size.x, 160.0)
	var bar_h: float = progress_bg.custom_minimum_size.y
	progress_fill.size = Vector2(bar_w * ratio, bar_h)


func _refresh_columns() -> void:
	var active_name: String = _preview_player_name if not _preview_player_name.is_empty() else GameManager.get_player_name()
	var cleaned_name: String = SaveData.clean_player_name(active_name, GameManager.MAX_NAME_LENGTH)
	var active_diff: int = GameManager.selected_difficulty

	var row_font_size: int = clampi(int(round(24.0 * _ui_scale)), 20, 36)
	var top_row_font_size: int = clampi(int(round(27.0 * _ui_scale)), 22, 40)
	var badge_font_size: int = clampi(int(round(20.0 * _ui_scale)), 17, 30)

	for filter_id: int in [-1, 2, 1, 0]:
		var style: StyleBoxFlat = _column_styles.get(filter_id) as StyleBoxFlat
		if style != null:
			var border_g: float = 1.0 if (filter_id == -1 or filter_id == active_diff) else 0.72
			style.border_color = Color(border_g, border_g, border_g, 1.0)
			style.bg_color = Color(0.06, 0.06, 0.06, 1.0)

		var list_vbox: VBoxContainer = _column_lists.get(filter_id) as VBoxContainer
		if list_vbox == null:
			continue
		for child: Node in list_vbox.get_children():
			list_vbox.remove_child(child)
			child.free()

		var entries: Array[Dictionary] = GameManager.get_leaderboard(filter_id, cleaned_name)
		if entries.is_empty():
			var empty_lbl: Label = Label.new()
			empty_lbl.name = "EmptyColumnLabel"
			empty_lbl.text = "NO SCORES YET\nPLAY A RUN TO CLAIM #1!"
			empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_lbl.add_theme_color_override("font_color", Color(0.62, 0.62, 0.62, 1.0))
			empty_lbl.add_theme_font_size_override("font_size", row_font_size)
			list_vbox.add_child(empty_lbl)
			continue

		var top_count: int = mini(entries.size(), TOP_LIMIT)
		var current_entry_outside_top: Dictionary = {}
		for i: int in range(entries.size()):
			var entry: Dictionary = entries[i]
			if i < top_count:
				list_vbox.add_child(_create_entry_row(entry, filter_id < 0, row_font_size, top_row_font_size, badge_font_size))
			elif bool(entry.get("is_current", false)):
				current_entry_outside_top = entry

		if not current_entry_outside_top.is_empty():
			var dots_lbl: Label = Label.new()
			dots_lbl.name = "PinnedEllipsis"
			dots_lbl.text = "•   •   •"
			dots_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dots_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 1.0))
			dots_lbl.add_theme_font_size_override("font_size", badge_font_size)
			list_vbox.add_child(dots_lbl)
			var pinned_row: PanelContainer = _create_entry_row(
				current_entry_outside_top,
				filter_id < 0,
				row_font_size,
				top_row_font_size,
				badge_font_size
			)
			pinned_row.name = "PinnedCurrentPlayerRow"
			list_vbox.add_child(pinned_row)


func _create_entry_row(
	entry: Dictionary,
	show_diff_badge: bool,
	row_font_size: int,
	top_row_font_size: int,
	badge_font_size: int
) -> PanelContainer:
	var rank: int = int(entry.get("rank", 1))
	var p_name: String = str(entry.get("player_name", "PLAYER")).to_upper()
	var diff_idx: int = int(entry.get("difficulty", 0))
	var diff_str: String = DIFFICULTY_NAMES[clampi(diff_idx, 0, DIFFICULTY_NAMES.size() - 1)].to_upper()
	var completed: bool = bool(entry.get("completed", false))
	var time_val: float = float(entry.get("time", 0.0))
	var is_current: bool = bool(entry.get("is_current", false))
	var is_podium: bool = rank <= 3
	var f_size: int = top_row_font_size if (is_podium or is_current) else row_font_size

	var row: PanelContainer = PanelContainer.new()
	row.name = "RankRow_%d" % rank
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg_g: float = 0.24 if is_current else (0.15 if rank == 1 else (0.11 if is_podium else 0.07))
	var border_g: float = 1.0 if (is_current or rank == 1) else (0.82 if is_podium else 0.38)
	var border_w: int = 3 if (is_current or rank == 1) else 2
	var pad_x: int = int(round(14.0 * _ui_scale))
	var pad_y: int = int(round(9.0 * _ui_scale))
	row.add_theme_stylebox_override("panel", _make_box_style(bg_g, border_g, border_w, pad_x, pad_y))

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", int(round(14.0 * _ui_scale)))
	row.add_child(hbox)

	var rank_lbl: Label = Label.new()
	rank_lbl.custom_minimum_size = Vector2(float(f_size) * 2.3, 0.0)
	rank_lbl.text = "#%d" % rank
	var rank_g: float = 1.0 if (is_podium or is_current) else 0.85
	rank_lbl.add_theme_color_override("font_color", Color(rank_g, rank_g, rank_g, 1.0))
	rank_lbl.add_theme_font_size_override("font_size", f_size)
	hbox.add_child(rank_lbl)

	var name_lbl: Label = Label.new()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	name_lbl.text = "%s%s" % [p_name, "  ◀ YOU" if is_current else ""]
	var name_g: float = 1.0 if (is_current or is_podium) else 0.92
	name_lbl.add_theme_color_override("font_color", Color(name_g, name_g, name_g, 1.0))
	name_lbl.add_theme_font_size_override("font_size", f_size)
	hbox.add_child(name_lbl)

	if show_diff_badge:
		var badge_lbl: Label = Label.new()
		badge_lbl.custom_minimum_size = Vector2(float(badge_font_size) * 4.4, 0.0)
		badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge_lbl.text = "[%s]" % diff_str
		badge_lbl.add_theme_color_override("font_color", Color(0.84, 0.84, 0.84, 1.0))
		badge_lbl.add_theme_font_size_override("font_size", badge_font_size)
		hbox.add_child(badge_lbl)

	var score_lbl: Label = Label.new()
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.text = "COMPLETED ★" if completed else "%.1fs" % time_val
	var score_g: float = 1.0 if (completed or is_current) else 0.90
	score_lbl.add_theme_color_override("font_color", Color(score_g, score_g, score_g, 1.0))
	score_lbl.add_theme_font_size_override("font_size", f_size)
	hbox.add_child(score_lbl)

	return row


func _make_box_style(bg_gray: float, border_gray: float, border_w: int, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.content_margin_left = float(pad_x)
	s.content_margin_right = float(pad_x)
	s.content_margin_top = float(pad_y)
	s.content_margin_bottom = float(pad_y)
	s.bg_color = Color(bg_gray, bg_gray, bg_gray, 1.0)
	s.border_width_left = border_w
	s.border_width_top = border_w
	s.border_width_right = border_w
	s.border_width_bottom = border_w
	s.border_color = Color(border_gray, border_gray, border_gray, 1.0)
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_right = 3
	s.corner_radius_bottom_left = 3
	return s


func _on_player_name_changed(new_name: String) -> void:
	_preview_player_name = new_name
	refresh_all()


func _on_preview_name_changed(preview_name: String) -> void:
	_preview_player_name = preview_name
	refresh_all()


func _on_difficulty_changed(new_diff: int) -> void:
	_cycled_difficulty = new_diff
	_tier_cycle_timer = 0.0
	refresh_all()


func _on_state_changed(_new_state: int) -> void:
	_cycled_difficulty = GameManager.selected_difficulty
	_tier_cycle_timer = 0.0
	refresh_all()


func _on_record_updated(difficulty: int, time_survived: float, completed: bool) -> void:
	_record_flash_timer = 4.5
	_cycled_difficulty = difficulty
	var diff_str: String = GameManager.get_difficulty_name(difficulty).to_upper()
	var score_str: String = "COMPLETED (45.0s)" if completed else "%.1fs" % time_survived
	record_banner_label.text = "★ NEW RECORD BY %s ON %s: %s! ★" % [GameManager.get_player_name().to_upper(), diff_str, score_str]
	record_banner_label.visible = true
	refresh_all()


func _on_live_telemetry_updated(elapsed: float, duration: float, hp: int, max_hp: int) -> void:
	_live_elapsed = elapsed
	_live_duration = duration
	_live_hp = hp
	_live_max_hp = max_hp
	_update_live_run_widgets()


func _on_resized(viewport_override: Vector2 = Vector2.ZERO) -> void:
	var view: Vector2 = viewport_override if (viewport_override.x > 0.0 and viewport_override.y > 0.0) else size
	if view.x <= 0.0 or view.y <= 0.0:
		view = get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		view = Vector2(1280.0, 720.0)

	_ui_scale = clampf(minf(view.x / 1152.0, view.y / 648.0), 0.78, 1.65)
	columns_grid.columns = 2 if view.x >= 720.0 else 1

	title_label.add_theme_font_size_override("font_size", clampi(int(round(32.0 * _ui_scale)), 20, 48))
	mode_badge_label.add_theme_font_size_override("font_size", clampi(int(round(18.0 * _ui_scale)), 13, 26))
	player_label.add_theme_font_size_override("font_size", clampi(int(round(30.0 * _ui_scale)), 18, 44))
	best_rank_label.add_theme_font_size_override("font_size", clampi(int(round(25.0 * _ui_scale)), 16, 38))
	status_label.add_theme_font_size_override("font_size", clampi(int(round(22.0 * _ui_scale)), 15, 34))
	hp_label.add_theme_font_size_override("font_size", clampi(int(round(24.0 * _ui_scale)), 16, 36))
	record_banner_label.add_theme_font_size_override("font_size", clampi(int(round(28.0 * _ui_scale)), 18, 42))
	progress_bg.custom_minimum_size.y = clampf(round(14.0 * _ui_scale), 10.0, 22.0)

	var col_hdr_size: int = clampi(int(round(28.0 * _ui_scale)), 20, 42)
	for hdr: Variant in _column_headers.values():
		if hdr is Label:
			(hdr as Label).add_theme_font_size_override("font_size", col_hdr_size)

	var pad_x: int = clampi(int(round(24.0 * _ui_scale)), 12, 40)
	var pad_y: int = clampi(int(round(18.0 * _ui_scale)), 10, 32)
	root_margin.add_theme_constant_override("margin_left", pad_x)
	root_margin.add_theme_constant_override("margin_right", pad_x)
	root_margin.add_theme_constant_override("margin_top", pad_y)
	root_margin.add_theme_constant_override("margin_bottom", pad_y)

	_refresh_columns()
	_update_visible_tier_columns()
	_update_live_run_widgets()
