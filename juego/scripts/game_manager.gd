extends Node

signal state_changed(new_state: int)
signal difficulty_changed(new_difficulty: int)
signal record_updated(difficulty: int, time_survived: float, completed: bool)
signal player_name_changed(new_name: String)
signal preview_name_changed(preview_name: String)
signal live_telemetry_updated(elapsed: float, duration: float, hp: int, max_hp: int)

enum State {
	MENU = 0,
	PLAYING = 1,
	GAME_OVER = 2,
	COMPLETE = 3,
	CREDITS = 4,
}

enum Difficulty {
	EASY = 0,
	NORMAL = 1,
	HARD = 2,
	BOSS = 3,
}

const SAVE_PATH: String = "user://save_data.tres"
const DEV_SAVE_PATH: String = "res://data/save_data.tres"
const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
const LEVEL_SCENE: String = "res://scenes/level.tscn"
const BOSS_LEVEL_SCENE: String = "res://scenes/boss_level.tscn"
const CREDITS_SCENE: String = "res://scenes/credits.tscn"
const SPECTATOR_VIEW_SCRIPT: GDScript = preload("res://scripts/spectator_ranking_view.gd")
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard", "Boss"]
const BOSS_TOTAL_PHASES: int = 8
const BOSS_PHASE_DURATION: float = 15.0
const BOSS_LEVEL_DURATION: float = 120.0
const MAX_NAME_LENGTH: int = 12
const SCREEN_POLL_INTERVAL: float = 1.0

var state: int = State.MENU
var selected_difficulty: int = Difficulty.NORMAL
var active_run_difficulty: int = Difficulty.NORMAL
var save_data: SaveData = null
var save_path: String = SAVE_PATH

var spectator_window: Window = null
var spectator_view: Control = null
## 0 = auto (open when >=2 monitors), 1 = forced ON (F10), -1 = forced OFF (F10)
var spectator_override_mode: int = 0
var _screen_poll_timer: float = 0.0
var _last_detected_screens: int = -1
var _test_screen_count_override: int = -1
var _last_telemetry_bucket: int = -1
var _last_telemetry_hp: int = -1
var _last_telemetry_max_hp: int = -1
var _last_telemetry_duration: float = -1.0


func _ready() -> void:
	load_game()
	if not ResourceLoader.exists(save_path):
		save_game()
	call_deferred("evaluate_spectator_display")


func _process(delta: float) -> void:
	_screen_poll_timer += delta
	if _screen_poll_timer >= SCREEN_POLL_INTERVAL:
		_screen_poll_timer = 0.0
		var count: int = get_available_screen_count()
		if count != _last_detected_screens:
			evaluate_spectator_display()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F10:
			toggle_spectator_window()
			get_viewport().set_input_as_handled()


func get_available_screen_count() -> int:
	if _test_screen_count_override >= 0:
		return _test_screen_count_override
	return maxi(1, DisplayServer.get_screen_count())


func set_test_screen_count_override(count: int) -> void:
	_test_screen_count_override = count
	evaluate_spectator_display()


func get_secondary_screen_index() -> int:
	var count: int = get_available_screen_count()
	if count < 2:
		return -1
	if _test_screen_count_override >= 2:
		return 1
	var main_screen: int = DisplayServer.window_get_current_screen(DisplayServer.MAIN_WINDOW_ID)
	for idx: int in range(count):
		if idx != main_screen:
			return idx
	return 1


func is_spectator_window_active() -> bool:
	return spectator_window != null and is_instance_valid(spectator_window) and spectator_window.visible


func evaluate_spectator_display() -> void:
	var count: int = get_available_screen_count()
	_last_detected_screens = count
	var should_show: bool = false
	if spectator_override_mode == 1:
		should_show = true
	elif spectator_override_mode == -1:
		should_show = false
	else:
		should_show = count >= 2 and DisplayServer.get_name() != "headless"
		if _test_screen_count_override >= 2:
			should_show = true

	if should_show:
		_open_or_place_spectator_window()
	else:
		_close_spectator_window()


func toggle_spectator_window() -> bool:
	if is_spectator_window_active():
		spectator_override_mode = -1
	else:
		spectator_override_mode = 1
	evaluate_spectator_display()
	return is_spectator_window_active()


func _open_or_place_spectator_window() -> void:
	var root_win: Window = get_tree().root
	if DisplayServer.get_name() != "headless":
		root_win.gui_embed_subwindows = false

	var created: bool = false
	if spectator_window == null or not is_instance_valid(spectator_window):
		spectator_window = Window.new()
		spectator_window.name = "SpectatorRankingWindow"
		spectator_window.title = "Shapes & Beams — Live Ranking"
		spectator_window.close_requested.connect(func() -> void:
			spectator_override_mode = -1
			_close_spectator_window()
		)
		spectator_view = SPECTATOR_VIEW_SCRIPT.new() as Control
		spectator_window.add_child(spectator_view)
		root_win.add_child(spectator_window)
		created = true

	var secondary_screen: int = get_secondary_screen_index()
	if secondary_screen >= 0 and DisplayServer.get_name() != "headless":
		spectator_window.unfocusable = true
		spectator_window.borderless = true
		spectator_window.current_screen = secondary_screen
		spectator_window.mode = Window.MODE_FULLSCREEN
	else:
		spectator_window.unfocusable = false
		spectator_window.borderless = false
		if created:
			spectator_window.size = Vector2i(960, 540)

	spectator_window.visible = true
	if spectator_view != null and spectator_view.has_method("refresh_all"):
		spectator_view.call("refresh_all")


func _close_spectator_window() -> void:
	if spectator_window != null and is_instance_valid(spectator_window):
		spectator_window.visible = false
		if spectator_window.get_parent() != null:
			spectator_window.get_parent().remove_child(spectator_window)
		spectator_window.free()
	spectator_window = null
	spectator_view = null


func get_absolute_save_path() -> String:
	return ProjectSettings.globalize_path(save_path)


func open_save_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path("user://"))


func load_game() -> void:
	save_data = null
	if ResourceLoader.exists(save_path):
		var loaded: Resource = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if loaded is SaveData:
			save_data = loaded
	if save_data == null and ResourceLoader.exists(DEV_SAVE_PATH):
		var dev_loaded: Resource = ResourceLoader.load(DEV_SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		if dev_loaded is SaveData:
			save_data = dev_loaded.duplicate() as SaveData
	if save_data == null:
		save_data = SaveData.new()
	save_data.sync_active_profile(MAX_NAME_LENGTH)


func save_game() -> Error:
	if save_data == null:
		return ERR_UNCONFIGURED
	var err: Error = ResourceSaver.save(save_data, save_path)
	if err == OK and save_path == SAVE_PATH and OS.is_debug_build() and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://data")):
		ResourceSaver.save(save_data, DEV_SAVE_PATH)
	return err


func set_state(new_state: int) -> void:
	if new_state == state:
		return
	state = new_state
	_last_telemetry_bucket = -1
	_last_telemetry_hp = -1
	_last_telemetry_max_hp = -1
	_last_telemetry_duration = -1.0
	state_changed.emit(state)


func set_difficulty(mode: int) -> void:
	var clamped: int = clampi(mode, Difficulty.EASY, Difficulty.HARD)
	if state == State.MENU:
		active_run_difficulty = clamped
	if clamped == selected_difficulty:
		return
	selected_difficulty = clamped
	difficulty_changed.emit(selected_difficulty)


func get_player_name() -> String:
	return save_data.player_name if save_data != null else "PLAYER"


func set_player_name(new_name: String) -> void:
	if save_data == null:
		return
	save_data.set_active_player(new_name, MAX_NAME_LENGTH)
	save_game()
	player_name_changed.emit(save_data.player_name)


func notify_preview_player_name(raw_name: String) -> void:
	preview_name_changed.emit(SaveData.clean_player_name(raw_name, MAX_NAME_LENGTH))


func report_live_telemetry(elapsed: float, duration: float, hp: int, max_hp: int) -> void:
	var bucket: int = int(floor(maxf(elapsed, 0.0) * 10.0))
	var force_boundary: bool = elapsed <= 0.001 or elapsed >= duration
	if (
		not force_boundary
		and bucket == _last_telemetry_bucket
		and hp == _last_telemetry_hp
		and max_hp == _last_telemetry_max_hp
		and is_equal_approx(duration, _last_telemetry_duration)
	):
		return
	_last_telemetry_bucket = bucket
	_last_telemetry_hp = hp
	_last_telemetry_max_hp = max_hp
	_last_telemetry_duration = duration
	live_telemetry_updated.emit(elapsed, duration, hp, max_hp)


func get_difficulty_name(difficulty: int = selected_difficulty) -> String:
	return DIFFICULTY_NAMES[clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)]


static func get_boss_phase_for_time(time_survived: float, completed: bool = false) -> int:
	if completed:
		return BOSS_TOTAL_PHASES
	return clampi(int(floor(maxf(time_survived, 0.0) / BOSS_PHASE_DURATION)) + 1, 1, BOSS_TOTAL_PHASES)


func format_run_score(difficulty: int, time_survived: float, completed: bool, compact: bool = false) -> String:
	if difficulty == Difficulty.BOSS:
		if completed:
			return "8/8 PHASES ★" if compact else "COMPLETED (8/8) ★"
		var phase: int = get_boss_phase_for_time(time_survived, false)
		return "P%d/8 (%.1fs)" % [phase, time_survived] if compact else "Phase %d/8 (%.1fs)" % [phase, time_survived]
	if completed:
		return "COMPLETED ★" if compact else "COMPLETED (45.0s) ★"
	return "%.1fs" % time_survived if compact else "Survived %.1fs" % time_survived


func report_result(difficulty: int, time_survived: float, completed: bool) -> bool:
	if save_data == null:
		return false
	active_run_difficulty = clampi(difficulty, Difficulty.EASY, Difficulty.BOSS)
	var improved: bool = save_data.submit_result(difficulty, time_survived, completed)
	save_game()
	set_state(State.COMPLETE if completed else State.GAME_OVER)
	if improved:
		record_updated.emit(difficulty, time_survived, completed)
	elif spectator_view != null and is_instance_valid(spectator_view):
		spectator_view.call("refresh_all")
	return improved


func get_best_summary(for_player: String = "") -> String:
	if save_data == null:
		return "No runs yet"
	var record: Dictionary = save_data.get_highest_record(for_player)
	if record.is_empty():
		return "No runs yet"
	var diff: int = int(record.get("difficulty", 0))
	var completed: bool = bool(record.get("completed", false))
	var time_val: float = float(record.get("time", 0.0))
	var status: String
	if diff == Difficulty.BOSS:
		if completed:
			status = "COMPLETED (8/8)"
		else:
			var phase: int = get_boss_phase_for_time(time_val, false)
			status = "PHASE %d/8 (%.1fs)" % [phase, time_val]
	else:
		status = "COMPLETED" if completed else "%.1fs" % time_val
	return "BEST  %s  -  %s" % [get_difficulty_name(diff).to_upper(), status]


func get_leaderboard(difficulty_filter: int = -1, current_player_override: String = "") -> Array[Dictionary]:
	if save_data == null:
		return []
	return save_data.get_leaderboard(difficulty_filter, current_player_override)


func get_player_rank(difficulty_filter: int = -1, for_player: String = "") -> int:
	if save_data == null:
		return 0
	return save_data.get_player_rank(difficulty_filter, for_player)


func go_to_menu() -> void:
	active_run_difficulty = selected_difficulty
	set_state(State.MENU)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func start_level(difficulty: int = selected_difficulty) -> void:
	active_run_difficulty = clampi(difficulty, Difficulty.EASY, Difficulty.BOSS)
	if active_run_difficulty <= Difficulty.HARD:
		set_difficulty(active_run_difficulty)
	set_state(State.PLAYING)
	var target_scene: String = BOSS_LEVEL_SCENE if active_run_difficulty == Difficulty.BOSS else LEVEL_SCENE
	get_tree().change_scene_to_file(target_scene)


func go_to_credits() -> void:
	set_state(State.CREDITS)
	get_tree().change_scene_to_file(CREDITS_SCENE)
