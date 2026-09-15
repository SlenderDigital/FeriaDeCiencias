class_name ProceduralLevelGenerator
extends RefCounted
## ProceduralLevelGenerator — Modular procedural pattern generator for Abstract Pulse
## Algorithmically generates rhythm hazards and enemy wave patterns based on seed & song timing.
## Sin targets: todo lo que genera es peligro (esquivar es el único juego).

var current_seed: int = 1337
var rng: RandomNumberGenerator
# Ancho del área de juego (lo setea Gameplay desde el viewport).
var play_w: float = 1280.0

func _init(seed_value: int = 1337, width: float = 1280.0) -> void:
	current_seed = seed_value
	play_w = width
	rng = RandomNumberGenerator.new()
	rng.seed = current_seed

func set_seed(new_seed: int) -> void:
	current_seed = new_seed
	rng.seed = current_seed

## Calculates current difficulty intensity factor (0.8 to 2.2) based on level progression (0.0 to 1.0)
func get_intensity_multiplier(progress: float) -> float:
	if progress < 0.2:
		# Intro phase
		return lerp(0.8, 1.1, progress / 0.2)
	elif progress < 0.6:
		# Main buildup phase
		return lerp(1.1, 1.6, (progress - 0.2) / 0.4)
	elif progress < 0.85:
		# Overdrive climax phase
		return lerp(1.6, 2.2, (progress - 0.6) / 0.25)
	else:
		# Outro phase
		return lerp(2.2, 1.2, (progress - 0.85) / 0.15)

## Returns current wave phase name for HUD display
func get_phase_name(progress: float) -> String:
	if progress < 0.2:
		return "FASE 1: INICIACIÓN"
	elif progress < 0.6:
		return "FASE 2: RITMO CONTINUO"
	elif progress < 0.85:
		return "FASE 3: CLÍMAX NEÓN"
	else:
		return "FASE FINAL: ESCAPE"

## Generates a list of hazard objects to spawn at the current beat
func generate_beat_spawn(song_time: float, total_duration: float, base_color: Color) -> Array[Dictionary]:
	var progress: float = clamp(song_time / total_duration, 0.0, 1.0)
	var intensity: float = get_intensity_multiplier(progress)
	var spawned: Array[Dictionary] = []
	var hazard_col: Color = Color(1.0, 0.2, 0.3, 1.0) # Red hazard

	# Determine pattern type procedurally
	var pattern_roll: float = rng.randf()

	if progress < 0.15:
		# Simple single drops
		spawned.append(_create_hazard_dict(rng.randf_range(play_w * 0.09, play_w * 0.91), intensity, hazard_col))
	elif pattern_roll < 0.45:
		# Single drop with slight angle
		var x_pos: float = rng.randf_range(play_w * 0.12, play_w * 0.88)
		spawned.append(_create_hazard_dict(x_pos, intensity, hazard_col))
	elif pattern_roll < 0.75:
		# Double lane drop
		var lane_1: float = rng.randf_range(play_w * 0.08, play_w * 0.45)
		var lane_2: float = rng.randf_range(play_w * 0.55, play_w * 0.92)
		spawned.append(_create_hazard_dict(lane_1, intensity, hazard_col))
		spawned.append(_create_hazard_dict(lane_2, intensity, hazard_col))
	elif pattern_roll < 0.90:
		# Red Hazard barrier pulse (player must dodge!)
		var hazard_x: float = rng.randf_range(play_w * 0.15, play_w * 0.85)
		spawned.append(_create_hazard_dict(hazard_x, intensity * 1.1, hazard_col))
	else:
		# Triple beat burst
		for i in range(3):
			var burst_x: float = rng.randf_range(play_w * (0.12 + i * 0.24), play_w * (0.27 + i * 0.24))
			spawned.append(_create_hazard_dict(burst_x, intensity * 0.9, hazard_col))

	return spawned

func _create_hazard_dict(x_pos: float, intensity: float, color: Color) -> Dictionary:
	var base_speed: float = 180.0 * intensity
	var speed_variation: float = rng.randf_range(-20.0, 40.0)
	var dir_x: float = rng.randf_range(-30.0, 30.0)

	return {
		"pos": Vector2(x_pos, -30.0),
		"vel": Vector2(dir_x, base_speed + speed_variation),
		"radius": rng.randf_range(24.0, 32.0),
		"color": color,
		"is_hazard": true,
		"hit_health_bonus": -25.0 # Hitting hazard hurts!
	}
