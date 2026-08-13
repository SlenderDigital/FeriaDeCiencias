extends Control
## MainMenu — Main Menu Controller for Abstract Pulse
## Manages sub-panels, audio feedback, track selection, control scheme configuration, visual upgrades, settings, and game launch.

# Sub-Panels Nodes
@onready var main_buttons_container: Control = $Layout/Content/SideNav
@onready var song_select_panel: Control = $Layout/Content/Panels/SongSelectPanel
@onready var controls_panel: Control = $Layout/Content/Panels/ControlsPanel
@onready var upgrades_panel: Control = $Layout/Content/Panels/UpgradesPanel
@onready var settings_panel: Control = $Layout/Content/Panels/SettingsPanel
@onready var credits_panel: Control = $Layout/Content/Panels/CreditsPanel

# Header & Info UI Nodes
@onready var title_label: Label = $Layout/Header/TitleContainer/Title
@onready var status_label: Label = $Layout/Header/StatusContainer/StatusLabel
@onready var control_mode_badge: Label = $Layout/Header/StatusContainer/ControlBadge

# Track Select UI Nodes
@onready var track_buttons_container: Container = $Layout/Content/Panels/SongSelectPanel/VBox/TrackList
@onready var track_title_label: Label = $Layout/Content/Panels/SongSelectPanel/VBox/Details/TrackTitle
@onready var track_info_label: Label = $Layout/Content/Panels/SongSelectPanel/VBox/Details/TrackInfo
@onready var track_desc_label: Label = $Layout/Content/Panels/SongSelectPanel/VBox/Details/TrackDesc
@onready var track_highscore_label: Label = $Layout/Content/Panels/SongSelectPanel/VBox/Details/HighScoreLabel
@onready var btn_play_level: Button = $Layout/Content/Panels/SongSelectPanel/VBox/Details/BtnPlayLevel

# Controls Panel UI Nodes
@onready var btn_mode_mediapipe: Button = $Layout/Content/Panels/ControlsPanel/VBox/ModeContainer/BtnMediaPipe
@onready var btn_mode_keyboard: Button = $Layout/Content/Panels/ControlsPanel/VBox/ModeContainer/BtnKeyboard
@onready var hand_test_box: Control = $Layout/Content/Panels/ControlsPanel/VBox/TestBoxContainer/TestBox
@onready var hand_test_cursor: ColorRect = $Layout/Content/Panels/ControlsPanel/VBox/TestBoxContainer/TestBox/HandCursor

# Upgrades UI Nodes
@onready var ship_preview_rect: ColorRect = $Layout/Content/Panels/UpgradesPanel/VBox/PreviewContainer/ShipPreview

# Settings UI Nodes
@onready var slider_master: HSlider = $Layout/Content/Panels/SettingsPanel/VBox/Grid/SliderMaster
@onready var slider_music: HSlider = $Layout/Content/Panels/SettingsPanel/VBox/Grid/SliderMusic
@onready var slider_sfx: HSlider = $Layout/Content/Panels/SettingsPanel/VBox/Grid/SliderSFX
@onready var check_fullscreen: CheckButton = $Layout/Content/Panels/SettingsPanel/VBox/Grid/CheckFullscreen

var active_panel: Control = null
var selected_track_idx: int = 0
var title_time: float = 0.0

func _ready() -> void:
	_setup_button_audio()
	_update_control_badge()
	_populate_track_list()
	_select_track_ui(0)
	_update_upgrades_preview()
	_show_panel(song_select_panel) # Open Song Select by default
	
	if GameManager:
		slider_master.value = GameManager.master_volume
		slider_music.value = GameManager.music_volume
		slider_sfx.value = GameManager.sfx_volume

func _process(delta: float) -> void:
	# Subtle rhythmic pulse on the title text color
	title_time += delta * 3.0
	if title_label:
		var glow: float = 0.85 + 0.15 * sin(title_time)
		var base_col: Color = Color(0.0, 0.94, 1.0, 1.0)
		if GameManager and GameManager.get_current_track().has("color"):
			base_col = GameManager.get_current_track()["color"]
		title_label.add_theme_color_override("font_color", Color(base_col.r * glow, base_col.g * glow, base_col.b * glow, 1.0))
		
	# Interactive hand test box update when Controls panel is active
	if active_panel == controls_panel and hand_test_box and hand_test_cursor:
		var box_rect: Rect2 = hand_test_box.get_global_rect()
		var m_pos: Vector2 = get_global_mouse_position()
		var local_pos: Vector2 = m_pos - box_rect.position
		local_pos.x = clamp(local_pos.x, 10, box_rect.size.x - 10)
		local_pos.y = clamp(local_pos.y, 10, box_rect.size.y - 10)
		hand_test_cursor.position = local_pos - hand_test_cursor.size * 0.5

func _setup_button_audio() -> void:
	# Connect mouse hover & press signals to all buttons recursively
	_connect_audio_recursive(self)

func _connect_audio_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			child.mouse_entered.connect(func(): if SoundManager: SoundManager.play_hover())
			child.pressed.connect(func(): if SoundManager: SoundManager.play_click())
		_connect_audio_recursive(child)

func _show_panel(panel: Control) -> void:
	song_select_panel.visible = (panel == song_select_panel)
	controls_panel.visible = (panel == controls_panel)
	upgrades_panel.visible = (panel == upgrades_panel)
	settings_panel.visible = (panel == settings_panel)
	credits_panel.visible = (panel == credits_panel)
	active_panel = panel

# --- Main Navigation Handlers ---

func _on_btn_nav_play_pressed() -> void:
	_show_panel(song_select_panel)

func _on_btn_nav_controls_pressed() -> void:
	_show_panel(controls_panel)

func _on_btn_nav_upgrades_pressed() -> void:
	_show_panel(upgrades_panel)

func _on_btn_nav_settings_pressed() -> void:
	_show_panel(settings_panel)

func _on_btn_nav_credits_pressed() -> void:
	_show_panel(credits_panel)

func _on_btn_nav_exit_pressed() -> void:
	if SoundManager: SoundManager.play_back()
	get_tree().quit()

# --- Track Selection Handlers ---

func _populate_track_list() -> void:
	if not track_buttons_container or not GameManager:
		return
		
	# Clear container
	for c in track_buttons_container.get_children():
		c.queue_free()
		
	for i in range(GameManager.TRACKS.size()):
		var track: Dictionary = GameManager.TRACKS[i]
		var btn: Button = Button.new()
		btn.text = "  %d. %s  (%s)" % [i + 1, track["name"], track["difficulty"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 48)
		
		var idx: int = i
		btn.pressed.connect(func(): _select_track_ui(idx))
		btn.mouse_entered.connect(func(): if SoundManager: SoundManager.play_hover())
		track_buttons_container.add_child(btn)

func _select_track_ui(index: int) -> void:
	selected_track_idx = index
	if GameManager:
		GameManager.select_track(index)
		var track: Dictionary = GameManager.get_current_track()
		
		if track_title_label:
			track_title_label.text = track["name"].to_upper()
			track_title_label.add_theme_color_override("font_color", track["color"])
		if track_info_label:
			track_info_label.text = "Artista: %s  |  BPM: %d  |  Duración: %s" % [track["artist"], track["bpm"], track["duration"]]
		if track_desc_label:
			track_desc_label.text = track["description"]
		if track_highscore_label:
			var hs: int = GameManager.get_high_score(track["id"])
			track_highscore_label.text = "RÉCORD PERSONAL: %d PTS" % hs

func _on_btn_play_level_pressed() -> void:
	if SoundManager:
		SoundManager.play_launch()
		
	# Transition to level gameplay scene
	if GameManager:
		GameManager.change_scene("res://scenes/Gameplay.tscn")

# --- Control Scheme Handlers ---

func _on_btn_mode_mediapipe_pressed() -> void:
	if GameManager:
		GameManager.set_control_mode(GameManager.MODE_MEDIAPIPE)
		_update_control_badge()

func _on_btn_mode_keyboard_pressed() -> void:
	if GameManager:
		GameManager.set_control_mode(GameManager.MODE_KEYBOARD)
		_update_control_badge()

func _update_control_badge() -> void:
	if not GameManager or not control_mode_badge:
		return
	if GameManager.control_mode == GameManager.MODE_MEDIAPIPE:
		control_mode_badge.text = "[ MEDIAPIPE HAND TRACKING ]"
		control_mode_badge.add_theme_color_override("font_color", Color(0.0, 1.0, 0.5, 1.0))
		if btn_mode_mediapipe: btn_mode_mediapipe.text = "✓ MEDIAPIPE (ACTIVO)"
		if btn_mode_keyboard: btn_mode_keyboard.text = "TECLADO + MOUSE"
	else:
		control_mode_badge.text = "[ TECLADO + MOUSE ]"
		control_mode_badge.add_theme_color_override("font_color", Color(0.0, 0.94, 1.0, 1.0))
		if btn_mode_mediapipe: btn_mode_mediapipe.text = "MEDIAPIPE HAND TRACKING"
		if btn_mode_keyboard: btn_mode_keyboard.text = "✓ TECLADO + MOUSE (ACTIVO)"

# --- Upgrades Handlers ---

func _on_btn_palette_cyan_pressed() -> void:
	if GameManager: GameManager.set_equipped_palette("cyan_neon")
	_update_upgrades_preview()

func _on_btn_palette_magenta_pressed() -> void:
	if GameManager: GameManager.set_equipped_palette("cyber_magenta")
	_update_upgrades_preview()

func _on_btn_palette_gold_pressed() -> void:
	if GameManager: GameManager.set_equipped_palette("gold_flare")
	_update_upgrades_preview()

func _on_btn_palette_emerald_pressed() -> void:
	if GameManager: GameManager.set_equipped_palette("emerald_matrix")
	_update_upgrades_preview()

func _update_upgrades_preview() -> void:
	if not GameManager or not ship_preview_rect:
		return
	var key: String = GameManager.equipped_ship_palette
	if GameManager.SHIP_PALETTES.has(key):
		var palette: Dictionary = GameManager.SHIP_PALETTES[key]
		ship_preview_rect.color = palette["main"]

# --- Settings Handlers ---

func _on_slider_master_value_changed(value: float) -> void:
	if GameManager: GameManager.master_volume = value
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))

func _on_slider_music_value_changed(value: float) -> void:
	if GameManager: GameManager.music_volume = value

func _on_slider_sfx_value_changed(value: float) -> void:
	if GameManager: GameManager.sfx_volume = value

func _on_check_fullscreen_toggled(toggled_on: bool) -> void:
	if GameManager: GameManager.fullscreen_enabled = toggled_on
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
