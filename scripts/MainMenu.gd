extends Control
## MainMenu — Patchbay world main menu for Abstract Pulse.
## Three module panels (one per track) rack-mounted. Selection shows patch cable from clock source to module's GATE jack. "PATCH IN" launches the level.

# Top rail
@onready var btn_settings: Button = $TopRail/BtnSettings
@onready var btn_credits: Button = $TopRail/BtnCredits
@onready var btn_exit: Button = $TopRail/BtnExit

# Rack
@onready var rack: HBoxContainer = $Rack
@onready var modules: Array = []

# Patch cable
@onready var patch_cable: Control = $PatchCable

# Selected module expansion (description + high score + PATCH IN CTA)
@onready var selected_expand: VBoxContainer = $SelectedModuleExpand
@onready var track_desc_label: Label = $SelectedModuleExpand/TrackDesc
@onready var high_score_label: Label = $SelectedModuleExpand/HighScore
@onready var btn_patch_in: Button = $SelectedModuleExpand/BtnPatchIn

# Overlays
@onready var settings_overlay: Control = $SettingsOverlay
@onready var credits_overlay: Control = $CreditsOverlay
@onready var exit_confirm: AcceptDialog = $ExitConfirm

var selected_track_index: int = -1

func _ready() -> void:
	# Connections are defined in MainMenu.tscn [connection] blocks
	pass
	
	# Collect modules and assign track indices
	var idx: int = 0
	for c in rack.get_children():
		if c.get_script() and c.get_script().resource_path.ends_with("PatchbayModule.gd"):
			# track_index is already set in .tscn
			modules.append(c)
			if c.has_signal("module_selected"):
				c.module_selected.connect(_on_module_selected)
			if c.has_signal("patch_in"):
				c.patch_in.connect(_on_module_patch_in)
			idx += 1
	
	# Connect patch cable
	if patch_cable and patch_cable.has_signal("cable_seated"):
		patch_cable.cable_seated.connect(_on_cable_seated)
	
	# Pre-select first track
	if modules.size() > 0:
		await get_tree().process_frame  # Wait for modules to be ready
		modules[0]._select()

func _on_module_selected(track_index: int) -> void:
	selected_track_index = track_index
	if GameManager:
		GameManager.select_track(track_index)
		var track: Dictionary = GameManager.get_current_track()
		track_desc_label.text = track.get("description", "")
		var hs: int = GameManager.get_high_score(track.get("id", "track_1"))
		high_score_label.text = "RÉCORD: %d PTS" % hs
		var track_color = track.get("color", Color(0.55, 0.9, 0.15, 1.0))
		high_score_label.add_theme_color_override("font_color", track_color)
	
	selected_expand.visible = true
	_show_patch_cable()

func _show_patch_cable() -> void:
	if selected_track_index < 0 or selected_track_index >= modules.size():
		return
	if not is_instance_valid(patch_cable):
		return
	var module_node: Control = modules[selected_track_index]
	if not is_instance_valid(module_node):
		return
	# Clock source: top rail left area
	var from: Vector2 = Vector2(140, 32)
	var to: Vector2 = Vector2(module_node.global_position.x + module_node.size.x * 0.5, module_node.global_position.y + module_node.size.y - 50)
	patch_cable.show_cable(from, to, true)

func _on_module_patch_in(track_index: int) -> void:
	# Double-click or Enter on module → launch
	selected_track_index = track_index
	_on_btn_patch_in_pressed()

func _on_btn_patch_in_pressed() -> void:
	if SoundManager: SoundManager.play_launch()
	if GameManager and selected_track_index >= 0:
		GameManager.select_track(selected_track_index)
		GameManager.change_scene("res://scenes/Gameplay.tscn")

func _on_cable_seated() -> void:
	# Visual feedback when cable snaps in
	if selected_track_index >= 0 and selected_track_index < modules.size():
		var module_node: Control = modules[selected_track_index]
		if is_instance_valid(module_node):
			module_node.set_selected(true)

# --- Top Rail Handlers ---

func _on_btn_settings_pressed() -> void:
	if SoundManager: SoundManager.play_click()
	if settings_overlay and settings_overlay.has_method("show_overlay"):
		settings_overlay.show_overlay()

func _on_btn_credits_pressed() -> void:
	if SoundManager: SoundManager.play_click()
	if credits_overlay and credits_overlay.has_method("show_overlay"):
		credits_overlay.show_overlay()

func _on_btn_exit_pressed() -> void:
	if SoundManager: SoundManager.play_back()
	exit_confirm.popup_centered()

func _on_exit_confirmed() -> void:
	get_tree().quit()

func _input(event: InputEvent) -> void:
	# Keyboard navigation between modules
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_LEFT and selected_track_index > 0:
			modules[selected_track_index - 1]._select()
		elif event.keycode == KEY_RIGHT and selected_track_index < modules.size() - 1:
			modules[selected_track_index + 1]._select()
		elif event.keycode == KEY_ENTER and selected_track_index >= 0:
			_on_btn_patch_in_pressed()