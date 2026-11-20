extends CanvasLayer

signal retry_requested
signal main_menu_requested

var _hud_timer_bucket: int = -1
var _last_shield_ratio: float = -1.0
var _last_shield_state: String = ""
var _last_shield_sec_bucket: int = -1
var _last_hand_state: int = -1
var _last_hand_label: String = ""
var _last_hand_pulse_bucket: int = -1
var _current_hp: int = 3
var _hp_flash_timer: float = 0.0
var _hp_pulse_time: float = 0.0
var _boss_hud_enabled: bool = false
var _boss_total_phases: int = 8
var _boss_ticks: Array[ColorRect] = []
var boss_phase_label: Label = null
var shield_time_label: Label = null
var _top_left_pill: ColorRect = null
var _top_right_pill: ColorRect = null
var _intro_view_size: Vector2 = Vector2(1152.0, 648.0)
var _intro_top_bar: ColorRect = null
var _intro_bottom_bar: ColorRect = null
var _intro_skip_label: Label = null
var _intro_banner: Control = null
var _intro_backdrop: ColorRect = null
var _intro_top_rule: ColorRect = null
var _intro_bottom_rule: ColorRect = null
var _intro_title_label: Label = null
var _intro_subtitle_label: Label = null

@onready var hud_root: Control = $HUDRoot
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
	set_process(false)
	game_over_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level_complete_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	retry_button.pressed.connect(func() -> void: retry_requested.emit())
	replay_button.pressed.connect(func() -> void: retry_requested.emit())
	game_over_menu_button.pressed.connect(func() -> void: main_menu_requested.emit())
	complete_menu_button.pressed.connect(func() -> void: main_menu_requested.emit())

	_ensure_top_left_pill()

	shield_time_label = Label.new()
	shield_time_label.name = "ShieldTimeLabel"
	shield_time_label.position = Vector2(shield_bg.position.x + shield_bg.size.x + 8.0, shield_bg.position.y - 5.0)
	shield_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield_time_label.add_theme_font_size_override("font_size", 13)
	shield_time_label.add_theme_color_override("font_color", Color.WHITE)
	shield_time_label.text = "1.7s"
	hud_root.add_child(shield_time_label)

	for i: int in range(2):
		var tick: ColorRect = ColorRect.new()
		tick.name = "ShieldTick%d" % (i + 1)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.color = Color(0.06, 0.06, 0.06, 0.85)
		tick.z_index = 1
		tick.position = Vector2(roundf(shield_bg.size.x * float(i + 1) / 3.0), 0.0)
		tick.size = Vector2(1.0, shield_bg.size.y)
		shield_bg.add_child(tick)

	var vp: Viewport = get_viewport()
	if vp != null:
		var vr: Vector2 = vp.get_visible_rect().size
		if vr.x > 0.0 and vr.y > 0.0:
			_intro_view_size = vr
	_setup_boss_intro_overlay()


func _process(delta: float) -> void:
	_hp_flash_timer = maxf(0.0, _hp_flash_timer - delta * 2.5)
	_hp_pulse_time += delta
	var gray: float = 1.0
	if _hp_flash_timer > 0.0:
		var flash_blink: bool = int(_hp_flash_timer * 12.0) % 2 == 0
		gray = 0.42 if flash_blink else 1.0
	elif _current_hp == 1:
		gray = 0.825 + 0.175 * sin(_hp_pulse_time * 10.0)
	hp_label.add_theme_color_override("font_color", Color(gray, gray, gray, 1.0))
	if _hp_flash_timer <= 0.0 and _current_hp != 1:
		hp_label.add_theme_color_override("font_color", Color.WHITE)
		set_process(false)


func _ensure_top_left_pill() -> void:
	if _top_left_pill == null or not is_instance_valid(_top_left_pill):
		_top_left_pill = ColorRect.new()
		_top_left_pill.name = "TopLeftPill"
		_top_left_pill.position = Vector2(16.0, 22.0)
		_top_left_pill.size = Vector2(228.0, 66.0)
		_top_left_pill.color = Color(0.02, 0.02, 0.02, 0.78)
		_top_left_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_top_left_pill.z_index = -1
		hud_root.add_child(_top_left_pill)


func reset(duration: float) -> void:
	_hud_timer_bucket = -1
	_last_shield_ratio = -1.0
	_last_shield_state = ""
	_last_shield_sec_bucket = -1
	_current_hp = 3
	_hp_flash_timer = 0.0
	_hp_pulse_time = 0.0
	hp_label.add_theme_color_override("font_color", Color.WHITE)
	set_process(false)
	game_over_panel.visible = false
	level_complete_panel.visible = false
	hide_boss_intro()
	set_controls_hint_alpha(1.0)
	update_timer(0.0, duration)
	update_hp(3, 3)


func set_controls_hint_alpha(alpha: float) -> void:
	if controls_hint_label != null:
		controls_hint_label.modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))


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
	if new_hp != _current_hp:
		_hp_flash_timer = 1.0
	_current_hp = new_hp
	if _current_hp != 1:
		_hp_pulse_time = 0.0
	set_process(_hp_flash_timer > 0.0 or _current_hp == 1)
	if _hp_flash_timer <= 0.0 and _current_hp != 1:
		hp_label.add_theme_color_override("font_color", Color.WHITE)


func update_shield(ratio: float, is_active: bool, is_exhausted: bool, max_seconds: float = 1.65) -> void:
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

	var remaining_sec: float = clamped_ratio * max_seconds
	var sec_tenths: int = int(round(remaining_sec * 10.0))
	if shield_time_label != null and (sec_tenths != _last_shield_sec_bucket or state_text != _last_shield_state):
		shield_time_label.text = "%.1fs" % (float(sec_tenths) / 10.0)
		var time_gray: float = 1.0 if (is_active or clamped_ratio >= 0.999) else (0.48 if is_exhausted else 0.74)
		shield_time_label.add_theme_color_override("font_color", Color(time_gray, time_gray, time_gray, 1.0))
		_last_shield_sec_bucket = sec_tenths

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
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		_intro_view_size = viewport_size
	if viewport_size.x > 48.0:
		progress_bg.size.x = viewport_size.x - 48.0
	_layout_boss_ticks()
	if viewport_size.x > 160.0:
		timer_label.position.x = viewport_size.x - 150.0
		if _top_right_pill != null and is_instance_valid(_top_right_pill):
			_top_right_pill.position.x = timer_label.position.x - 10.0
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
	_layout_boss_intro_overlay()


func _setup_boss_intro_overlay() -> void:
	_intro_top_bar = ColorRect.new()
	_intro_top_bar.name = "IntroTopBar"
	_intro_top_bar.color = Color(0.02, 0.02, 0.02, 0.96)
	_intro_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_top_bar.z_index = 5
	_intro_top_bar.visible = false
	hud_root.add_child(_intro_top_bar)

	_intro_bottom_bar = ColorRect.new()
	_intro_bottom_bar.name = "IntroBottomBar"
	_intro_bottom_bar.color = Color(0.02, 0.02, 0.02, 0.96)
	_intro_bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_bottom_bar.z_index = 5
	_intro_bottom_bar.visible = false
	hud_root.add_child(_intro_bottom_bar)

	_intro_skip_label = Label.new()
	_intro_skip_label.name = "IntroSkipLabel"
	_intro_skip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_skip_label.add_theme_font_size_override("font_size", 12)
	_intro_skip_label.add_theme_color_override("font_color", Color(0.58, 0.58, 0.58, 0.9))
	_intro_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_skip_label.text = "SPACE / CLICK TO SKIP"
	_intro_bottom_bar.add_child(_intro_skip_label)

	_intro_banner = Control.new()
	_intro_banner.name = "IntroBanner"
	_intro_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_banner.z_index = 6
	_intro_banner.visible = false
	hud_root.add_child(_intro_banner)

	_intro_backdrop = ColorRect.new()
	_intro_backdrop.name = "IntroBackdrop"
	_intro_backdrop.color = Color(0.02, 0.02, 0.02, 0.86)
	_intro_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_banner.add_child(_intro_backdrop)

	_intro_top_rule = ColorRect.new()
	_intro_top_rule.name = "IntroTopRule"
	_intro_top_rule.color = Color(1.0, 1.0, 1.0, 1.0)
	_intro_top_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_banner.add_child(_intro_top_rule)

	_intro_bottom_rule = ColorRect.new()
	_intro_bottom_rule.name = "IntroBottomRule"
	_intro_bottom_rule.color = Color(1.0, 1.0, 1.0, 1.0)
	_intro_bottom_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_banner.add_child(_intro_bottom_rule)

	_intro_title_label = Label.new()
	_intro_title_label.name = "IntroTitleLabel"
	_intro_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_title_label.add_theme_font_size_override("font_size", 40)
	_intro_title_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_intro_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_title_label.text = "THE ARCHITECT"
	_intro_banner.add_child(_intro_title_label)

	_intro_subtitle_label = Label.new()
	_intro_subtitle_label.name = "IntroSubtitleLabel"
	_intro_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_subtitle_label.add_theme_font_size_override("font_size", 14)
	_intro_subtitle_label.add_theme_color_override("font_color", Color(0.80, 0.80, 0.80, 1.0))
	_intro_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_subtitle_label.text = "8 PHASES  ·  SURVIVE 120s"
	_intro_banner.add_child(_intro_subtitle_label)

	_layout_boss_intro_overlay()


func _layout_boss_intro_overlay() -> void:
	if _intro_top_bar == null or not is_instance_valid(_intro_top_bar):
		return
	var vw: float = _intro_view_size.x
	var vh: float = _intro_view_size.y
	var bar_h: float = 58.0
	var banner_h: float = 98.0

	_intro_top_bar.size = Vector2(vw, bar_h)
	_intro_bottom_bar.size = Vector2(vw, bar_h)
	_intro_skip_label.position = Vector2(0.0, (bar_h - 18.0) * 0.5)
	_intro_skip_label.size = Vector2(vw, 20.0)

	_intro_banner.position = Vector2(0.0, (vh - banner_h) * 0.5)
	_intro_banner.size = Vector2(vw, banner_h)
	_intro_banner.pivot_offset = Vector2(vw * 0.5, banner_h * 0.5)

	_intro_backdrop.position = Vector2.ZERO
	_intro_backdrop.size = Vector2(vw, banner_h)
	_intro_top_rule.position.y = 0.0
	_intro_top_rule.size.y = 2.0
	_intro_bottom_rule.position.y = banner_h - 2.0
	_intro_bottom_rule.size.y = 2.0
	if _intro_top_rule.size.x <= 0.0:
		_intro_top_rule.position.x = 0.0
		_intro_top_rule.size.x = vw
		_intro_bottom_rule.position.x = 0.0
		_intro_bottom_rule.size.x = vw

	_intro_title_label.position = Vector2(0.0, 12.0)
	_intro_title_label.size = Vector2(vw, 50.0)
	_intro_subtitle_label.position = Vector2(0.0, 64.0)
	_intro_subtitle_label.size = Vector2(vw, 24.0)


func hide_boss_intro() -> void:
	if _intro_top_bar != null and is_instance_valid(_intro_top_bar):
		_intro_top_bar.visible = false
		_intro_top_bar.modulate = Color.WHITE
	if _intro_bottom_bar != null and is_instance_valid(_intro_bottom_bar):
		_intro_bottom_bar.visible = false
		_intro_bottom_bar.modulate = Color.WHITE
	if _intro_banner != null and is_instance_valid(_intro_banner):
		_intro_banner.visible = false
		_intro_banner.scale = Vector2.ONE
		_intro_banner.modulate = Color.WHITE


func update_boss_intro(active: bool, progress: float, dismiss_t: float = 0.0, quick_mode: bool = false) -> void:
	if _intro_top_bar == null or not is_instance_valid(_intro_top_bar):
		return
	_layout_boss_intro_overlay()
	var vw: float = _intro_view_size.x
	var vh: float = _intro_view_size.y
	var bar_h: float = 58.0

	if active and not quick_mode:
		var p: float = clampf(progress, 0.0, 1.0)
		var bar_t: float = ease(clampf(p / 0.18, 0.0, 1.0), 0.35)
		_intro_top_bar.visible = true
		_intro_bottom_bar.visible = true
		_intro_top_bar.modulate = Color.WHITE
		_intro_bottom_bar.modulate = Color.WHITE
		_intro_top_bar.position = Vector2(0.0, lerpf(-bar_h, 0.0, bar_t))
		_intro_bottom_bar.position = Vector2(0.0, lerpf(vh, vh - bar_h, bar_t))
		_intro_skip_label.visible = true

		if p < 0.52:
			_intro_banner.visible = false
		else:
			_intro_banner.visible = true
			var slash_t: float = ease(clampf((p - 0.52) / 0.14, 0.0, 1.0), 0.35)
			_intro_banner.scale = Vector2(1.0, lerpf(0.08, 1.0, slash_t))
			_intro_banner.modulate = Color(1.0, 1.0, 1.0, clampf((p - 0.52) / 0.06, 0.0, 1.0))
			var rule_w: float = vw * lerpf(0.18, 1.0, slash_t)
			var rule_x: float = (vw - rule_w) * 0.5
			_intro_top_rule.position.x = rule_x
			_intro_top_rule.size.x = rule_w
			_intro_bottom_rule.position.x = rule_x
			_intro_bottom_rule.size.x = rule_w
		return

	if active and quick_mode:
		_intro_top_bar.visible = false
		_intro_bottom_bar.visible = false
		var p: float = clampf(progress, 0.0, 1.0)
		if p < 0.35:
			_intro_banner.visible = false
		else:
			_intro_banner.visible = true
			var flash_t: float = clampf((p - 0.35) / 0.65, 0.0, 1.0)
			var alpha: float = clampf(flash_t / 0.25, 0.0, 1.0) if flash_t < 0.5 else sin(flash_t * PI)
			_intro_banner.scale = Vector2(1.0, lerpf(0.75, 1.0, minf(flash_t * 3.0, 1.0)))
			_intro_banner.modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
			_intro_top_rule.position.x = 0.0
			_intro_top_rule.size.x = vw
			_intro_bottom_rule.position.x = 0.0
			_intro_bottom_rule.size.x = vw
		return

	var dt_norm: float = clampf(dismiss_t, 0.0, 1.0)
	if dt_norm >= 1.0:
		hide_boss_intro()
		return

	var out_t: float = ease(dt_norm, 2.0)
	if not quick_mode:
		_intro_top_bar.visible = true
		_intro_bottom_bar.visible = true
		_intro_top_bar.position = Vector2(0.0, lerpf(0.0, -bar_h, out_t))
		_intro_bottom_bar.position = Vector2(0.0, lerpf(vh - bar_h, vh, out_t))
		_intro_top_bar.modulate = Color(1.0, 1.0, 1.0, 1.0 - out_t * 0.5)
		_intro_bottom_bar.modulate = Color(1.0, 1.0, 1.0, 1.0 - out_t * 0.5)
	else:
		_intro_top_bar.visible = false
		_intro_bottom_bar.visible = false

	_intro_banner.visible = true
	_intro_banner.scale = Vector2(1.0, lerpf(1.0, 0.05, out_t))
	_intro_banner.modulate = Color(1.0, 1.0, 1.0, 1.0 - out_t)
	var rule_w: float = vw * (1.0 - out_t)
	var rule_x: float = (vw - rule_w) * 0.5
	_intro_top_rule.position.x = rule_x
	_intro_top_rule.size.x = rule_w
	_intro_bottom_rule.position.x = rule_x
	_intro_bottom_rule.size.x = rule_w


func configure_boss_hud(enabled: bool, total_phases: int = 8) -> void:
	_boss_hud_enabled = enabled
	_boss_total_phases = maxi(total_phases, 1)
	var desired_ticks: int = maxi(_boss_total_phases - 1, 0)
	if _boss_ticks.size() != desired_ticks:
		for old_tick: ColorRect in _boss_ticks:
			if old_tick != null and is_instance_valid(old_tick):
				old_tick.queue_free()
		_boss_ticks.clear()
		for i: int in range(desired_ticks):
			var tick: ColorRect = ColorRect.new()
			tick.name = "BossPhaseTick%d" % (i + 1)
			tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tick.color = Color(0.05, 0.05, 0.05, 1.0)
			tick.z_index = 1
			progress_bg.add_child(tick)
			_boss_ticks.append(tick)

	for tick: ColorRect in _boss_ticks:
		if tick != null and is_instance_valid(tick):
			tick.visible = enabled

	_ensure_top_left_pill()
	_top_left_pill.size = Vector2(228.0, 92.0) if enabled else Vector2(228.0, 66.0)
	_top_left_pill.visible = true

	if _top_right_pill == null or not is_instance_valid(_top_right_pill):
		_top_right_pill = ColorRect.new()
		_top_right_pill.name = "TopRightPill"
		_top_right_pill.position = Vector2(timer_label.position.x - 10.0, 22.0)
		_top_right_pill.size = Vector2(142.0, 34.0)
		_top_right_pill.color = Color(0.02, 0.02, 0.02, 0.78)
		_top_right_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_top_right_pill.z_index = -1
		hud_root.add_child(_top_right_pill)
	_top_right_pill.position.x = timer_label.position.x - 10.0
	_top_right_pill.visible = enabled

	if boss_phase_label == null or not is_instance_valid(boss_phase_label):
		boss_phase_label = Label.new()
		boss_phase_label.name = "BossPhaseLabel"
		boss_phase_label.position = Vector2(24.0, 90.0)
		boss_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		boss_phase_label.add_theme_font_size_override("font_size", 14)
		boss_phase_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88, 1.0))
		hud_root.add_child(boss_phase_label)

	boss_phase_label.visible = enabled
	_layout_boss_ticks()
	if enabled and boss_phase_label.text.is_empty():
		update_boss_phase(1, _boss_total_phases)


func update_boss_phase(phase: int, total_phases: int = 8, status_suffix: String = "") -> void:
	if boss_phase_label == null or not is_instance_valid(boss_phase_label):
		configure_boss_hud(true, total_phases)
	var safe_total: int = maxi(total_phases, 1)
	var clamped_phase: int = clampi(phase, 1, safe_total)
	boss_phase_label.text = "PHASE %d / %d%s" % [clamped_phase, safe_total, status_suffix]


func _layout_boss_ticks() -> void:
	if _boss_ticks.is_empty() or progress_bg == null:
		return
	var bar_w: float = progress_bg.size.x
	var bar_h: float = progress_bg.size.y
	var total: float = float(maxi(_boss_total_phases, 1))
	for i: int in range(_boss_ticks.size()):
		var tick: ColorRect = _boss_ticks[i]
		if tick == null or not is_instance_valid(tick):
			continue
		var frac: float = float(i + 1) / total
		tick.position = Vector2(roundf(bar_w * frac) - 1.0, -1.0)
		tick.size = Vector2(2.0, bar_h + 2.0)
