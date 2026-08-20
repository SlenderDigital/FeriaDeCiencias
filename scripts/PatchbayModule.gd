extends Control
## PatchbayModule — One module panel in the rack (one track = one module).
## Builds its own visual children in _ready(): model label, BPM, stars, jack.
## Emits module_selected(track_index) when clicked/focused, patch_in when activated.

signal module_selected(track_index: int)
signal patch_in(track_index: int)

@export var track_index: int = 0

var model_label: Label
var bpm_label: Label
var stars_label: Label
var jack_container: Control

var track_data: Dictionary = {}
var is_selected: bool = false
var beat_pulse_t: float = 0.0
var ring_radius: float = 48.0
var ring_max_alpha: float = 0.0

func _ready() -> void:
	focus_mode = FOCUS_ALL
	_build_children()
	_setup_track_data()
	_connect_signals()

func _build_children() -> void:
	# Model name (top of module)
	model_label = Label.new()
	model_label.name = "ModelLabel"
	model_label.text = "MODULE"
	model_label.add_theme_font_size_override("font_size", 18)
	model_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1.0))
	model_label.anchor_left = 0.0
	model_label.anchor_right = 1.0
	model_label.anchor_top = 0.0
	model_label.anchor_bottom = 0.0
	model_label.offset_left = 0.0
	model_label.offset_right = 0.0
	model_label.offset_top = 28.0
	model_label.offset_bottom = 56.0
	model_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(model_label)
	
	# BPM (mono digits)
	bpm_label = Label.new()
	bpm_label.name = "BPMLabel"
	bpm_label.text = "000 BPM"
	bpm_label.add_theme_font_size_override("font_size", 24)
	bpm_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1.0))
	bpm_label.anchor_left = 0.0
	bpm_label.anchor_right = 1.0
	bpm_label.anchor_top = 0.0
	bpm_label.anchor_bottom = 0.0
	bpm_label.offset_left = 0.0
	bpm_label.offset_right = 0.0
	bpm_label.offset_top = 70.0
	bpm_label.offset_bottom = 100.0
	bpm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(bpm_label)
	
	# Stars (difficulty)
	stars_label = Label.new()
	stars_label.name = "StarsLabel"
	stars_label.text = "★"
	stars_label.add_theme_font_size_override("font_size", 16)
	stars_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.7))
	stars_label.anchor_left = 0.0
	stars_label.anchor_right = 1.0
	stars_label.anchor_top = 0.0
	stars_label.anchor_bottom = 0.0
	stars_label.offset_left = 0.0
	stars_label.offset_right = 0.0
	stars_label.offset_top = 108.0
	stars_label.offset_bottom = 130.0
	stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(stars_label)
	
	# Jack label (below the jack)
	jack_container = Label.new()
	jack_container.name = "JackContainer"
	jack_container.text = "GATE"
	jack_container.add_theme_font_size_override("font_size", 11)
	jack_container.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.4))
	jack_container.anchor_left = 0.0
	jack_container.anchor_right = 1.0
	jack_container.anchor_top = 1.0
	jack_container.anchor_bottom = 1.0
	jack_container.offset_left = 0.0
	jack_container.offset_right = 0.0
	jack_container.offset_top = -32.0
	jack_container.offset_bottom = -16.0
	jack_container.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(jack_container)

func _setup_track_data() -> void:
	if GameManager and GameManager.TRACKS.size() > track_index:
		track_data = GameManager.TRACKS[track_index]
		model_label.text = track_data["name"].to_upper()
		bpm_label.text = "%d BPM" % track_data["bpm"]
		var stars: int = track_data.get("difficulty_stars", 1)
		var star_str: String = ""
		for _i in range(stars):
			star_str += "★"
		stars_label.text = star_str
		var track_color = track_data["color"]
		jack_container.add_theme_color_override("font_color", track_color)

func _connect_signals() -> void:
	if GameManager and GameManager.has_signal("track_selected"):
		if not GameManager.track_selected.is_connected(_on_track_selected_global):
			GameManager.track_selected.connect(_on_track_selected_global)
	# Listen for beat from background
	var bg = get_parent().get_node_or_null("../Background")
	if bg and bg.has_signal("beat"):
		if not bg.beat.is_connected(_on_beat):
			bg.beat.connect(_on_beat)

func _on_track_selected_global(track_dict: Dictionary) -> void:
	if track_dict.get("id") != track_data.get("id"):
		set_selected(false)

func _on_beat() -> void:
	if is_selected:
		ring_max_alpha = 1.0
		beat_pulse_t = 0.0

func _process(delta: float) -> void:
	if is_selected and ring_max_alpha > 0.0:
		beat_pulse_t += delta * 4.0
		ring_max_alpha = lerp(ring_max_alpha, 0.0, delta * 3.0)
		if ring_max_alpha < 0.02:
			ring_max_alpha = 0.0
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			_patch_in()

func _select() -> void:
	if not is_selected:
		set_selected(true)
		module_selected.emit(track_index)

func set_selected(selected: bool) -> void:
	is_selected = selected
	if is_selected:
		grab_focus()
		ring_max_alpha = 1.0
	else:
		ring_max_alpha = 0.0
	queue_redraw()

func _patch_in() -> void:
	patch_in.emit(track_index)

func _draw() -> void:
	var size = get_rect().size
	if size.x < 10 or size.y < 10:
		return
	
	var center = Vector2(size.x * 0.5, size.y * 0.42)
	
	# Module faceplate background
	var bg_color = Color(0.06, 0.06, 0.1, 1.0)
	draw_rect(Rect2(Vector2(0, 0), size), bg_color)
	
	# Border
	var border_color = Color(0.85, 0.85, 0.9, 0.3)
	var border_width = 2.0
	if is_selected:
		var track_color = track_data.get("color", Color(0, 0.94, 1, 1))
		border_color = track_color
		border_width = 3.0
	# Draw border as 4 lines
	draw_line(Vector2(0, 0), Vector2(size.x, 0), border_color, border_width)
	draw_line(Vector2(0, size.y), Vector2(size.x, size.y), border_color, border_width)
	draw_line(Vector2(0, 0), Vector2(0, size.y), border_color, border_width)
	draw_line(Vector2(size.x, 0), Vector2(size.x, size.y), border_color, border_width)
	
	# LED ring when selected
	if is_selected and ring_max_alpha > 0.01:
		var track_color = track_data.get("color", Color(0, 0.94, 1, 1))
		var pulse_radius = ring_radius + 20.0 * (1.0 - ring_max_alpha)
		var alpha = ring_max_alpha * 0.8
		var col = track_color
		col.a = alpha
		draw_arc(center, pulse_radius, 0, TAU, 32, col, 3.0)
		
		var steady_col = track_color
		steady_col.a = 0.4
		draw_arc(center, ring_radius, 0, TAU, 32, steady_col, 2.0)
	
	# Draw jack socket (3.5mm jack representation)
	var jack_pos = Vector2(size.x * 0.5, size.y - 50)
	var jack_r = 14.0
	var nut_color = Color(0.85, 0.85, 0.9, 0.4)
	if is_selected:
		nut_color = track_data.get("color", Color(0, 0.94, 1, 1))
	# Nut
	draw_circle(jack_pos, jack_r, nut_color)
	# Sleeve
	draw_circle(jack_pos, jack_r * 0.95, Color(0.2, 0.2, 0.25, 1.0))
	# Ring
	draw_circle(jack_pos, jack_r * 0.75, Color(0.4, 0.4, 0.5, 1.0))
	# Tip
	draw_circle(jack_pos, jack_r * 0.5, Color(0.08, 0.08, 0.12, 1.0))

	# Draw screw holes (4 corners)
	var hole_r = 3.0
	var margin = 10.0
	var corners = [
		Vector2(margin, margin),
		Vector2(size.x - margin, margin),
		Vector2(size.x - margin, size.y - margin),
		Vector2(margin, size.y - margin)
	]
	for c in corners:
		draw_circle(c, hole_r, Color(0.04, 0.04, 0.06, 1.0))
		draw_arc(c, hole_r + 1, 0, TAU, 12, Color(0.2, 0.2, 0.25, 1.0), 1.5)
	
	# Focus ring (distinct from selection)
	if has_focus():
		var focus_rect = Rect2(Vector2(2, 2), Vector2(size.x - 4, size.y - 4))
		var focus_col = Color(0.55, 0.9, 0.15, 1.0)
		focus_col.a = 0.6
		draw_rect(focus_rect, focus_col, false, 2.0)
