extends Control
## MainMenu — Menú principal simplificado de Abstract Pulse.
## Navegación por mouse/teclado (nativo Godot) con soporte de control manual
## vía MediaPipe (HandTrackingClient autoload).
##
## Cuando la mano está activa (HandTrackingClient.has_hand == true), la palma
## actúa como cursor: moverse sobre un botón lo resalta; quedarse quieto 0.5 s
## lo selecciona (dwell click). Los sliders de volumen se controlan
## arrastrándolos horizontalmente con la mano.

# ------------------------------------------------------------------ referencias UI
@onready var title_label: Label = $Layout/Header/TitleContainer/Title

@onready var song_select_panel: Control = $Layout/Content/Panels/SongSelectPanel
@onready var settings_panel: Control = $Layout/Content/Panels/SettingsPanel

@onready var track_title_label: Label = $Layout/Content/Panels/SongSelectPanel/VBox/Details/TrackTitle
@onready var track_info_label: Label = $Layout/Content/Panels/SongSelectPanel/VBox/Details/TrackInfo
@onready var track_desc_label: Label = $Layout/Content/Panels/SongSelectPanel/VBox/Details/TrackDesc
@onready var track_highscore_label: Label = $Layout/Content/Panels/SongSelectPanel/VBox/Details/HighScoreLabel

@onready var slider_master: HSlider = $Layout/Content/Panels/SettingsPanel/VBox/Grid/SliderMaster
@onready var slider_music: HSlider = $Layout/Content/Panels/SettingsPanel/VBox/Grid/SliderMusic
@onready var slider_sfx: HSlider = $Layout/Content/Panels/SettingsPanel/VBox/Grid/SliderSFX
@onready var check_fullscreen: CheckButton = $Layout/Content/Panels/SettingsPanel/VBox/Grid/CheckFullscreen

var active_panel: Control = null
var title_time: float = 0.0

# ------------------------------------------------------------------ estado mano
const DWELL_TIME := 0.5       # segundos quietos sobre un botón para disparar click
const VIEWPORT_W := 1280.0
const VIEWPORT_H := 720.0

var _hand_pos: Vector2 = Vector2.ZERO
var _hand_btn: Control = null    # botón que la palma está señalando ahora
var _prev_hand_btn: Control = null
var _dwell_acc: float = 0.0
var _hand_active: bool = false  # ¿tiene sentido usar mano ahora? (hand detected + steady)

# --- cursor visual de mano ---
var _cursor: ColorRect


# ------------------------------------------------------------------ ciclo de vida
func _ready() -> void:
	_setup_button_audio()
	_select_track_ui(0)
	_show_panel(song_select_panel)
	_hand_btn = null
	_dwell_acc = 0.0
	if GameManager:
		slider_master.value = GameManager.master_volume
		slider_music.value = GameManager.music_volume
		slider_sfx.value = GameManager.sfx_volume
	
	# Crear cursor visual simple para la mano (ColorRect con shader radial)
	_cursor = ColorRect.new()
	_cursor.name = "HandCursor"
	_cursor.color = Color(0.0, 0.94, 1.0, 0.0)  # invisible al inicio (alpha 0)
	_cursor.custom_minimum_size = Vector2(32, 32)
	_cursor.anchor_left = 0.0
	_cursor.anchor_top = 0.0
	_cursor.anchor_right = 0.0
	_cursor.anchor_bottom = 0.0
	_cursor.offset_left = -16
	_cursor.offset_top = -16
	_cursor.offset_right = 16
	_cursor.offset_bottom = 16
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.visible = false
	_cursor.z_index = 1000
	# Shader radial para que parezca un círculo suave
	var shader_code = "shader_type canvas_item;\nvoid fragment() {\n    vec2 center = vec2(0.5, 0.5);\n    float dist = length(UV - center);\n    float alpha = smoothstep(0.5, 0.0, dist) * 0.9;\n    COLOR = vec4(0.0, 0.94, 1.0, alpha);\n}"
	var shader = Shader.new()
	shader.code = shader_code
	var shader_mat = ShaderMaterial.new()
	shader_mat.shader = shader
	_cursor.material = shader_mat
	add_child(_cursor)


# ------------------------------------------------------------------ input nativo (mouse/teclado)
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			HandlerMouseClick(event.position)
	elif event is InputEventMouseMotion:
		pass
	elif event is InputEventKey:
		if event.pressed:
			HandleKeyboardInput(event.keycode)


func HandlerMouseClick(pos: Vector2) -> void:
	var btn: Control = HitTestButtonAt(pos)
	if btn:
		ClickButton(btn)


func HandleKeyboardInput(key: Key) -> void:
	match key:
		KEY_UP, KEY_W:
			NavigateFocus(-1)
		KEY_DOWN, KEY_S:
			NavigateFocus(1)
		KEY_LEFT, KEY_A:
			NavigatePanel(-1)
		KEY_RIGHT, KEY_D:
			NavigatePanel(1)
		KEY_ENTER, KEY_SPACE:
			ActivateFocusedButton()
		KEY_ESCAPE, KEY_F4:
			if Input.is_key_pressed(KEY_ALT):
				get_tree().quit()
			elif GameManager and GameManager.fullscreen_enabled:
				GameManager.fullscreen_enabled = false
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		KEY_F11:
			if GameManager:
				GameManager.fullscreen_enabled = not GameManager.fullscreen_enabled
				print("[MainMenu] F11 pressed, fullscreen_enabled = ", GameManager.fullscreen_enabled)
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if GameManager.fullscreen_enabled else DisplayServer.WINDOW_MODE_WINDOWED)
				print("[MainMenu] window_set_mode called")


# ------------------------------------------------------------------ temporizador de hand
func _process(delta: float) -> void:
	title_time += delta * 3.0
	if title_label:
		var glow := 0.85 + 0.15 * sin(title_time)
		var base := Color(0.0, 0.94, 1.0, 1.0)
		if GameManager and GameManager.get_current_track().has("color"):
			base = GameManager.get_current_track()["color"]
		title_label.add_theme_color_override("font_color", Color(base.r * glow, base.g * glow, base.b * glow, 1.0))

	if HandTrackingClient and HandTrackingClient.has_hand:
		var palm := HandTrackingClient.get_palm_center()      # Vector2 normalizado (0..1), X espejada
		if palm.x >= 0.0 and palm.x <= 1.0 and palm.y >= 0.0 and palm.y <= 1.0:
			var pos := palm * Vector2(VIEWPORT_W, VIEWPORT_H)
			_hand_pos = pos
			_hand_active = true
			# Mover cursor visual
			if _cursor:
				_cursor.position = pos
				_cursor.visible = true
			UpdateHandState(delta)
			# Arrastre continuo de sliders si la mano está sobre uno
			var slider := _get_slider_under_hand()
			if slider:
				HandleSliderInteraction(slider)
		else:
			_hand_active = false
			_hand_btn = null
			_dwell_acc = 0.0
			if _cursor:
				_cursor.visible = false
	else:
		_hand_active = false
		_hand_btn = null
		_dwell_acc = 0.0
		if _cursor:
			_cursor.visible = false


# ------------------------------------------------------------------ lógica de mano
func UpdateHandState(delta: float) -> void:
	var btn := HitTestButtonAt(_hand_pos)
	if btn != _hand_btn:
		_hand_btn = btn
		_dwell_acc = 0.0

	if _hand_btn:
		_dwell_acc += delta
		if _dwell_acc >= DWELL_TIME:
			_dwell_acc = 0.0
			ClickButton(_hand_btn)
			_hand_btn = null
	else:
		_dwell_acc = 0.0

	UpdateButtonVisuals()


# ------------------------------------------------------------------ hit test
func HitTestButtonAt(pos: Vector2) -> Control:
	var best: Control = null
	var best_dist := 1e9
	for b in CollectVisibleButtons():
		var r: Rect2 = b.get_global_rect()
		if r.has_point(pos):
			return b
		var d := r.position.distance_squared_to(pos)
		if d < best_dist:
			best_dist = d
			best = b
	return best


func CollectVisibleButtons() -> Array:
	var out := []
	CollectVisibleButtonsRec(self, out)
	return out


func CollectVisibleButtonsRec(n: Node, out: Array) -> void:
	if n is Button and n.visible:
		out.append(n)
	elif n is CheckButton and n.visible:
		out.append(n)
	elif n is HSlider and n.visible:
		out.append(n)
	for c in n.get_children():
		CollectVisibleButtonsRec(c, out)


func _get_slider_under_hand() -> HSlider:
	var palm := HandTrackingClient.get_palm_center()
	if palm.x < 0.0 or palm.x > 1.0 or palm.y < 0.0 or palm.y > 1.0:
		return null
	var pos := palm * Vector2(VIEWPORT_W, VIEWPORT_H)
	for b in CollectVisibleButtons():
		if b is HSlider:
			var r: Rect2 = b.get_global_rect()
			if r.has_point(pos) or (pos.y >= r.position.y - 15 and pos.y <= r.position.y + r.size.y + 15):
				return b
	return null


# ------------------------------------------------------------------ acciones
func ClickButton(btn: Control) -> void:
	if btn == $Layout/Content/SideNav/BtnNavPlay:
		_on_btn_nav_play_pressed()
	elif btn == $Layout/Content/SideNav/BtnNavSettings:
		_on_btn_nav_settings_pressed()
	elif btn == $Layout/Content/SideNav/BtnNavExit:
		_on_btn_nav_exit_pressed()
	elif btn == $Layout/Content/Panels/SongSelectPanel/VBox/TrackButtons/BtnTrack0:
		_on_btn_track_0_pressed()
	elif btn == $Layout/Content/Panels/SongSelectPanel/VBox/TrackButtons/BtnTrack1:
		_on_btn_track_1_pressed()
	elif btn == $Layout/Content/Panels/SongSelectPanel/VBox/TrackButtons/BtnTrack2:
		_on_btn_track_2_pressed()
	elif btn == $Layout/Content/Panels/SongSelectPanel/VBox/Details/BtnPlayLevel:
		_on_btn_play_level_pressed()
	elif btn == check_fullscreen:
		_on_check_fullscreen_toggled(not check_fullscreen.is_pressed())
	elif btn is HSlider:
		HandleSliderInteraction(btn)
	elif btn is CheckButton:
		_on_check_fullscreen_toggled(not check_fullscreen.is_pressed())
	else:
		if btn is Button:
			btn.pressed.emit()


func ActivateFocusedButton() -> void:
	if _hand_btn:
		ClickButton(_hand_btn)
		_hand_btn = null


func UpdateButtonVisuals() -> void:
	# Indicador visual simple: cambiar font_color del botón focalizado.
	# Guardamos el botón previo para resetear su color.
	if _hand_btn and _hand_btn != _prev_hand_btn:
		if _prev_hand_btn and (_prev_hand_btn is Button or _prev_hand_btn is CheckButton):
			_prev_hand_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		if _hand_btn is Button or _hand_btn is CheckButton:
			_hand_btn.add_theme_color_override("font_color", Color(0.0, 0.94, 1.0, 1.0))
		_prev_hand_btn = _hand_btn
	elif not _hand_btn and _prev_hand_btn:
		if _prev_hand_btn is Button or _prev_hand_btn is CheckButton:
			_prev_hand_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		_prev_hand_btn = null


func HandleSliderInteraction(slider: HSlider) -> void:
	# El clic simple en un slider lo activa; luego el movimiento de mano lo arrastra.
	# En esta versión, el arrastre se maneja en _process cuando la mano está sobre el slider.
	var palm := HandTrackingClient.get_palm_center()
	var pos := palm * Vector2(VIEWPORT_W, VIEWPORT_H)
	var r: Rect2 = slider.get_global_rect()
	if r.has_point(pos) or (pos.y >= r.position.y - 15 and pos.y <= r.position.y + r.size.y + 15):
		var range := slider.max_value - slider.min_value
		var t := clampf((pos.x - r.position.x) / r.size.x, 0.0, 1.0)
		var value := slider.min_value + t * range
		slider.value = value
		if slider == slider_master:
			_on_slider_master_value_changed(value)
		elif slider == slider_music:
			_on_slider_music_value_changed(value)
		elif slider == slider_sfx:
			_on_slider_sfx_value_changed(value)


func NavigateFocus(dir: int) -> void:
	var btns := CollectVisibleButtons()
	if btns.is_empty():
		return
	var idx := -1
	for i in range(btns.size()):
		if btns[i] == _hand_btn:
			idx = i
			break
	if idx < 0:
		idx = 0 if dir > 0 else btns.size() - 1
	else:
		idx = clamp(idx + dir, 0, btns.size() - 1)
	_hand_btn = btns[idx]
	_dwell_acc = 0.0
	UpdateButtonVisuals()


func NavigatePanel(dir: int) -> void:
	if dir == -1:
		_on_btn_nav_play_pressed()
	else:
		_on_btn_nav_settings_pressed()


func _on_btn_nav_play_pressed() -> void:
	_show_panel(song_select_panel)


func _on_btn_nav_settings_pressed() -> void:
	_show_panel(settings_panel)


func _on_btn_nav_exit_pressed() -> void:
	if SoundManager:
		SoundManager.play_back()
	get_tree().quit()


func _on_btn_track_0_pressed() -> void:
	_select_track_ui(0)


func _on_btn_track_1_pressed() -> void:
	_select_track_ui(1)


func _on_btn_track_2_pressed() -> void:
	_select_track_ui(2)


func _select_track_ui(index: int) -> void:
	if GameManager:
		GameManager.select_track(index)
		var track := GameManager.get_current_track()
		if track_title_label:
			track_title_label.text = track["name"].to_upper()
			track_title_label.add_theme_color_override("font_color", track["color"])
		if track_info_label:
			track_info_label.text = "Artista: %s  |  BPM: %d  |  Duración: %s" % [track["artist"], track["bpm"], track["duration"]]
		if track_desc_label:
			track_desc_label.text = track["description"]
		if track_highscore_label:
			track_highscore_label.text = "RÉCORD PERSONAL: %d PTS" % GameManager.get_high_score(track["id"])


func _on_btn_play_level_pressed() -> void:
	if SoundManager:
		SoundManager.play_launch()
	if GameManager:
		GameManager.change_scene("res://scenes/Gameplay.tscn")


# ------------------------------------------------------------------ sliders (nativo)
func _on_slider_master_value_changed(value: float) -> void:
	if GameManager:
		GameManager.master_volume = value
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(value))


func _on_slider_music_value_changed(value: float) -> void:
	if GameManager:
		GameManager.music_volume = value


func _on_slider_sfx_value_changed(value: float) -> void:
	if GameManager:
		GameManager.sfx_volume = value


func _on_check_fullscreen_toggled(toggled_on: bool) -> void:
	if GameManager:
		GameManager.fullscreen_enabled = toggled_on
	if toggled_on:
		print("[MainMenu] CheckFullscreen toggled ON")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		print("[MainMenu] window_set_mode FULLSCREEN called")
	else:
		print("[MainMenu] CheckFullscreen toggled OFF")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		print("[MainMenu] window_set_mode WINDOWED called")


# ------------------------------------------------------------------ audio hover/click
func _setup_button_audio() -> void:
	_connect_audio_recursive(self)


func _connect_audio_recursive(n: Node) -> void:
	for child in n.get_children():
		if child is Button:
			child.mouse_entered.connect(func(): if SoundManager: SoundManager.play_hover())
			child.pressed.connect(func(): if SoundManager: SoundManager.play_click())
			_connect_audio_recursive(child)
		elif child is CheckButton:
			child.toggled.connect(func(t): if SoundManager: SoundManager.play_click())
			child.mouse_entered.connect(func(): if SoundManager: SoundManager.play_hover())
			_connect_audio_recursive(child)


# ------------------------------------------------------------------ panel visibility
func _show_panel(panel: Control) -> void:
	song_select_panel.visible = (panel == song_select_panel)
	settings_panel.visible = (panel == settings_panel)
	active_panel = panel
	_hand_btn = null
	_dwell_acc = 0.0
