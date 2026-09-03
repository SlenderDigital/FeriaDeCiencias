extends Control
## MainMenu — Menú principal simplificado de Abstract Pulse.
## Dos secciones: Selección de Canción (la que se abre por defecto) y Configuración.

@onready var title_label: Label = $Layout/Header/TitleContainer/Title

# Panels
@onready var song_select_panel: Control = $Layout/Content/Panels/SongSelectPanel
@onready var settings_panel: Control = $Layout/Content/Panels/SettingsPanel

# Track detail & play
@onready var track_title_label: Label = $Layout/Content/Panels/SongSelectPanel/VBox/Details/TrackTitle
@onready var track_info_label: Label = $Layout/Content/Panels/SongSelectPanel/VBox/Details/TrackInfo
@onready var track_desc_label: Label = $Layout/Content/Panels/SongSelectPanel/VBox/Details/TrackDesc
@onready var track_highscore_label: Label = $Layout/Content/Panels/SongSelectPanel/VBox/Details/HighScoreLabel

# Settings
@onready var slider_master: HSlider = $Layout/Content/Panels/SettingsPanel/VBox/Grid/SliderMaster
@onready var slider_music: HSlider = $Layout/Content/Panels/SettingsPanel/VBox/Grid/SliderMusic
@onready var slider_sfx: HSlider = $Layout/Content/Panels/SettingsPanel/VBox/Grid/SliderSFX
@onready var check_fullscreen: CheckButton = $Layout/Content/Panels/SettingsPanel/VBox/Grid/CheckFullscreen

var active_panel: Control = null
var title_time: float = 0.0

func _ready() -> void:
	_setup_button_audio()
	_select_track_ui(0) # Show first track details by default
	_show_panel(song_select_panel)
	
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

func _setup_button_audio() -> void:
	# Sound on hover/press for all buttons, found recursively
	_connect_audio_recursive(self)

func _connect_audio_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			child.mouse_entered.connect(func(): if SoundManager: SoundManager.play_hover())
			child.pressed.connect(func(): if SoundManager: SoundManager.play_click())
		_connect_audio_recursive(child)

func _show_panel(panel: Control) -> void:
	song_select_panel.visible = (panel == song_select_panel)
	settings_panel.visible = (panel == settings_panel)
	active_panel = panel

# --- Navigation ---

func _on_btn_nav_play_pressed() -> void:
	_show_panel(song_select_panel)

func _on_btn_nav_settings_pressed() -> void:
	_show_panel(settings_panel)

func _on_btn_nav_exit_pressed() -> void:
	if SoundManager: SoundManager.play_back()
	get_tree().quit()

# --- Track selection (static buttons) ---

func _on_btn_track_0_pressed() -> void:
	_select_track_ui(0)

func _on_btn_track_1_pressed() -> void:
	_select_track_ui(1)

func _on_btn_track_2_pressed() -> void:
	_select_track_ui(2)

func _on_btn_track_3_pressed() -> void:
	_select_track_ui(3)

func _select_track_ui(index: int) -> void:
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
	if GameManager:
		GameManager.change_scene("res://scenes/Gameplay.tscn")

# --- Settings ---

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