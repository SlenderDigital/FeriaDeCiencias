extends Node

signal state_changed(new_state: int)
signal record_updated(difficulty: int, time_survived: float, completed: bool)
signal player_name_changed(new_name: String)

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
}

const SAVE_PATH: String = "user://save_data.tres"
const DEV_SAVE_PATH: String = "res://data/save_data.tres"
const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
const LEVEL_SCENE: String = "res://scenes/level.tscn"
const CREDITS_SCENE: String = "res://scenes/credits.tscn"
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard"]
const MAX_NAME_LENGTH: int = 12

var state: int = State.MENU
var selected_difficulty: int = Difficulty.NORMAL
var save_data: SaveData = null
var save_path: String = SAVE_PATH


func _ready() -> void:
	load_game()
	if not ResourceLoader.exists(save_path):
		save_game()


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


func save_game() -> Error:
	if save_data == null:
		return ERR_UNCONFIGURED
	var err: Error = ResourceSaver.save(save_data, save_path)
	if err == OK and OS.is_debug_build() and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://data")):
		ResourceSaver.save(save_data, DEV_SAVE_PATH)
	return err


func set_state(new_state: int) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)


func set_difficulty(mode: int) -> void:
	selected_difficulty = clampi(mode, Difficulty.EASY, Difficulty.HARD)


func get_player_name() -> String:
	return save_data.player_name if save_data != null else "PLAYER"


func set_player_name(new_name: String) -> void:
	if save_data == null:
		return
	var cleaned: String = new_name.strip_edges().left(MAX_NAME_LENGTH)
	save_data.player_name = "PLAYER" if cleaned.is_empty() else cleaned
	save_game()
	player_name_changed.emit(save_data.player_name)


func get_difficulty_name(difficulty: int = selected_difficulty) -> String:
	return DIFFICULTY_NAMES[clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)]


func report_result(difficulty: int, time_survived: float, completed: bool) -> bool:
	if save_data == null:
		return false
	var improved: bool = save_data.submit_result(difficulty, time_survived, completed)
	if improved:
		save_game()
		record_updated.emit(difficulty, time_survived, completed)
	set_state(State.COMPLETE if completed else State.GAME_OVER)
	return improved


func get_best_summary() -> String:
	if save_data == null:
		return "No runs yet"
	var record: Dictionary = save_data.get_highest_record()
	if record.is_empty():
		return "No runs yet"
	var status: String = "COMPLETED" if bool(record.get("completed", false)) else "%.1fs" % float(record.get("time", 0.0))
	return "BEST  %s  -  %s" % [get_difficulty_name(int(record.get("difficulty", 0))).to_upper(), status]


func go_to_menu() -> void:
	set_state(State.MENU)
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func start_level(difficulty: int = selected_difficulty) -> void:
	set_difficulty(difficulty)
	set_state(State.PLAYING)
	get_tree().change_scene_to_file(LEVEL_SCENE)


func go_to_credits() -> void:
	set_state(State.CREDITS)
	get_tree().change_scene_to_file(CREDITS_SCENE)
