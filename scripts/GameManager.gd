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

# Tracks Data
const TRACKS: Array[Dictionary] = [
	{
		"id": "track_1",
		"name": "Cyber Genesis",
		"artist": "SynthPulse",
		"bpm": 128,
		"difficulty": "Principiante",
		"difficulty_stars": 1,
		"duration": "2:15",
		"color": Color(0.0, 0.94, 1.0, 1.0), # Cyan
		"secondary_color": Color(0.1, 0.4, 0.9, 1.0),
		"description": "Patrones rítmicos estables ideales para acostumbrarse al control por gestos."
	},
	{
		"id": "track_2",
		"name": "Neon Rush",
		"artist": "CyberWave",
		"bpm": 145,
		"difficulty": "Intermedio",
		"difficulty_stars": 2,
		"duration": "2:40",
		"color": Color(1.0, 0.0, 0.55, 1.0), # Magenta
		"secondary_color": Color(0.6, 0.0, 1.0, 1.0),
		"description": "Velocidad acelerada con ráfagas dobles de proyectiles y obstáculos cruzados."
	},
	{
		"id": "track_3",
		"name": "Overdrive Pulse",
		"artist": "Neural Beat",
		"bpm": 170,
		"difficulty": "Avanzado",
		"difficulty_stars": 3,
		"duration": "3:10",
		"color": Color(1.0, 0.85, 0.0, 1.0), # Gold
		"secondary_color": Color(1.0, 0.2, 0.0, 1.0),
		"description": "Desafío extremo de reflejos y movimiento continuo al ritmo máximo."
	}
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
var control_mode: String = MODE_KEYBOARD
var hand_sensitivity: float = 1.2
var camera_flipped: bool = true

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

# High Scores per Track ID
var high_scores: Dictionary = {
	"track_1": 12500,
	"track_2": 8400,
	"track_3": 0
}

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	print("[GameManager] Inicializado correctamente.")

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
		return true
	return false

func change_scene(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
