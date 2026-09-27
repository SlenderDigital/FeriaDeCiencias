extends Node
## GameManager — Global Autoload for Abstract Pulse
## Manages game state, tracks, control modes, visual upgrades, volume settings, and scene transitions.

signal track_selected(track_data: Dictionary)
signal control_mode_changed(mode: String)
signal upgrade_changed(type: String, value: String)
signal volume_changed(bus: String, value: float)

# Control Modes
const MODE_MEDIAPIPE: String = "MediaPipe"
const MODE_KEYBOARD: String = "KeyboardMouse"
const MODE_ARROWS: String = "KeyboardMouse"
const MODE_HANDS: String = "MediaPipe"

# Tracks Data — MVP de un solo nivel: First Light (procedural).
# Los niveles 2-3 (Mechanical Wall, Relentless Drive) se eliminaron para
# concentrar el polish en una sola experiencia jugable.
const TRACKS: Array[Dictionary] = [
	{
		"id": "level_first_light",
		"name": "First Light",
		"artist": "Abstract Pulse",
		"bpm": 128,
		"difficulty": "Principiante",
		"difficulty_stars": 1,
		"duration": "1:45",
		"color": Color(0.2, 0.8, 1, 1),
		"secondary_color": Color(0.1, 0.4, 0.9, 1.0),
		"description": "Tema compuesto por el motor: la canción y el nivel nacen de los mismos datos.",
		"procedural": true
	},
]

# Color Palettes for Ship / Visual Upgrades
const SHIP_PALETTES: Dictionary = {
	"cyan_neon": {
		"name": "Cyan Neon",
		"main": Color(0.0, 0.94, 1.0, 1.0),
		"glow": Color(0.0, 0.5, 1.0, 0.8)
	},
	"cyber_magenta": {
		"name": "Cyber Magenta",
		"main": Color(1.0, 0.0, 0.55, 1.0),
		"glow": Color(0.8, 0.0, 0.9, 0.8)
	},
	"gold_flare": {
		"name": "Gold Flare",
		"main": Color(1.0, 0.85, 0.0, 1.0),
		"glow": Color(1.0, 0.4, 0.0, 0.8)
	},
	"emerald_matrix": {
		"name": "Emerald Matrix",
		"main": Color(0.0, 1.0, 0.5, 1.0),
		"glow": Color(0.0, 0.8, 0.2, 0.8)
	}
}

# Current State
var current_track_index: int = 0
var control_mode: String = MODE_ARROWS
var hand_sensitivity: float = 1.2
var camera_flipped: bool = true
var procedural_seed: int = 1337

# Upgrades Equipped
var equipped_ship_palette: String = "cyan_neon"
var equipped_trail_style: String = "neon_pulse"
var equipped_shield_style: String = "cyan_ring"

# Settings
var master_volume: float = 0.8
var music_volume: float = 0.8
var sfx_volume: float = 0.9
var fullscreen_enabled: bool = false
var bloom_enabled: bool = true

# Persistencia (equivalente Godot del "ScriptableObject" pedido: datos del
# juego guardados en disco). Récord, volúmenes y fullscreen sobreviven al
# cierre en user://abstract_pulse.cfg.
const SAVE_PATH: String = "user://abstract_pulse.cfg"

# High Scores per Track ID (progreso 0-100; 0 = sin récord todavía)
var high_scores: Dictionary = {
	"level_first_light": 0,
}

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	load_data()
	print("[GameManager] Inicializado correctamente.")
	# Fullscreen-on-start: el juego se juega con la mano frente a la pantalla,
	# no hay mouse disponible; arrancar ya en fullscreen (main_scene boot).
	# GODOT_WINDOWED=1 lo desactiva (verificación, capturas y corridas
	# automatizadas: el fullscreen puede no tener display disponible y el
	# proceso muere al cambiar de modo).
	fullscreen_enabled = OS.get_environment("GODOT_WINDOWED") != "1"
	if fullscreen_enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		await get_tree().process_frame
		await get_tree().process_frame
		var scr: Vector2i = DisplayServer.screen_get_size()
		if scr.x > 0 and scr.y > 0 and DisplayServer.window_get_size() != scr:
			DisplayServer.window_set_size(scr)
		print("[GameManager] fullscreen aplicado, tamaño=", DisplayServer.window_get_size())
	else:
		print("[GameManager] modo ventana (GODOT_WINDOWED=1), tamaño=", DisplayServer.window_get_size())

func get_current_track() -> Dictionary:
	if current_track_index >= 0 and current_track_index < TRACKS.size():
		return TRACKS[current_track_index]
	return TRACKS[0]

func select_track(index: int) -> void:
	if index >= 0 and index < TRACKS.size():
		current_track_index = index
		track_selected.emit(TRACKS[current_track_index])
		print("[GameManager] Canción seleccionada: ", TRACKS[current_track_index]["name"])

func set_control_mode(mode: String) -> void:
	control_mode = mode
	control_mode_changed.emit(mode)
	print("[GameManager] Modo de control cambiado a: ", mode)

func set_equipped_palette(palette_key: String) -> void:
	if SHIP_PALETTES.has(palette_key):
		equipped_ship_palette = palette_key
		upgrade_changed.emit("palette", palette_key)

func get_high_score(track_id: String) -> int:
	return high_scores.get(track_id, 0)

func save_score(track_id: String, score: int) -> bool:
	var current_best: int = get_high_score(track_id)
	if score > current_best:
		high_scores[track_id] = score
		save_data()
		return true
	return false

## Guarda récord, volúmenes y flags en disco. Se llama al cerrar un récord,
## al cambiar settings y al salir al menú (barato: un archivo INI chico).
func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("records", "high_scores", high_scores)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("video", "fullscreen", fullscreen_enabled)
	cfg.set_value("video", "bloom", bloom_enabled)
	var err: Error = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("[GameManager] no se pudo guardar %s (err %d)" % [SAVE_PATH, err])

## Carga lo guardado; si no hay archivo (primera vez), quedan los defaults.
func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	high_scores = dict_int(cfg.get_value("records", "high_scores", high_scores))
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	fullscreen_enabled = bool(cfg.get_value("video", "fullscreen", fullscreen_enabled))
	bloom_enabled = bool(cfg.get_value("video", "bloom", bloom_enabled))
	_apply_volumes()

## Las claves de un ConfigFile vuelven como String: normaliza a {String: int}.
static func dict_int(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		out[str(k)] = int(d[k])
	return out

## Empuja los volúmenes cargados al AudioServer (buses Master/Music/SFX).
func _apply_volumes() -> void:
	var buses: Dictionary = {"Master": master_volume, "Music": music_volume, "SFX": sfx_volume}
	for bus in buses.keys():
		var idx: int = AudioServer.get_bus_index(str(bus))
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(float(buses[bus]), 0.01, 1.0)))

func change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
