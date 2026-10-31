@tool
extends Node2D
## Subtle monochrome geometric arena grid, radar reticle, and border.
## Pulses brightly when the player blocks, takes a hit, or heavy threats slam,
## giving crisp spatial feedback without external textures.

const GRID_SPACING: float = 96.0
const BASE_GRID: Color = Color(0.06, 0.06, 0.06, 1.0)
const MAJOR_GRID: Color = Color(0.095, 0.095, 0.095, 1.0)
const BASE_BORDER: Color = Color(0.22, 0.22, 0.22, 1.0)
const PULSE_COLOR: Color = Color(0.94, 0.94, 0.94, 1.0)

var arena_size: Vector2 = Vector2(1152.0, 648.0)
var pulse_strength: float = 0.0
var beat_phase: float = 0.0
var beat_energy: float = 0.0
var music_section: int = 0


func _ready() -> void:
	set_process(false)
	queue_redraw()


## Updates the drawn arena extent (called by the level on resize).
func set_arena_size(new_size: Vector2) -> void:
	if new_size.x <= 0.0 or new_size.y <= 0.0:
		return
	arena_size = new_size
	queue_redraw()


## Updates beat-synchronized visual parameters from the level soundtrack.
func set_music_state(phase: float, energy: float, section: int) -> void:
	beat_phase = clampf(phase, 0.0, 1.0)
	beat_energy = clampf(energy, 0.0, 1.0)
	music_section = maxi(section, 0)
	queue_redraw()


## Briefly brightens the arena border and center reticle for impact feedback.
func pulse(strength: float = 0.5) -> void:
	pulse_strength = clampf(maxf(pulse_strength, strength), 0.0, 1.0)
	if not is_processing():
		set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	pulse_strength = maxf(0.0, pulse_strength - maxf(delta, 0.0) * 2.6)
	queue_redraw()
	if pulse_strength <= 0.0:
		set_process(false)


func _draw() -> void:
	var width: float = arena_size.x
	var height: float = arena_size.y
	if width <= 1.0 or height <= 1.0:
		return

	var minor_color: Color = BASE_GRID
	minor_color.a = 0.55 + 0.25 * pulse_strength
	var major_color: Color = MAJOR_GRID
	major_color.a = 0.65 + 0.30 * pulse_strength

	var col_idx: int = 1
	var x: float = GRID_SPACING
	while x < width - 1.0:
		var is_major_x: bool = (col_idx % 2 == 0)
		draw_line(Vector2(x, 0.0), Vector2(x, height), major_color if is_major_x else minor_color, 1.0)
		x += GRID_SPACING
		col_idx += 1

	var row_idx: int = 1
	var y: float = GRID_SPACING
	while y < height - 1.0:
		var is_major_y: bool = (row_idx % 2 == 0)
		draw_line(Vector2(0.0, y), Vector2(width, y), major_color if is_major_y else minor_color, 1.0)
		y += GRID_SPACING
		row_idx += 1

	# Subtle intersection crosshairs on major grid nodes
	var node_col: Color = Color(0.16, 0.16, 0.16, 0.55 + 0.30 * pulse_strength)
	var gx: float = GRID_SPACING * 2.0
	while gx < width - 1.0:
		var gy: float = GRID_SPACING * 2.0
		while gy < height - 1.0:
			draw_line(Vector2(gx - 3.0, gy), Vector2(gx + 3.0, gy), node_col, 1.0)
			draw_line(Vector2(gx, gy - 3.0), Vector2(gx, gy + 3.0), node_col, 1.0)
			gy += GRID_SPACING * 2.0
		gx += GRID_SPACING * 2.0

	# Center geometric radar emblem (breathes in sync with 128 BPM soundtrack)
	var center: Vector2 = Vector2(width * 0.5, height * 0.5)
	var eff_pulse: float = clampf(pulse_strength + beat_energy * 0.28, 0.0, 1.0)
	var center_gray: float = 0.11 + 0.19 * eff_pulse
	var center_color: Color = Color(center_gray, center_gray, center_gray, 0.86)
	var min_dim: float = minf(width, height)
	var outer_r: float = min_dim * (0.16 + 0.014 * eff_pulse)
	var inner_r: float = min_dim * (0.075 + 0.008 * beat_energy)
	draw_line(Vector2(center.x, center.y - 22.0), Vector2(center.x, center.y + 22.0), center_color, 1.0)
	draw_line(Vector2(center.x - 22.0, center.y), Vector2(center.x + 22.0, center.y), center_color, 1.0)
	draw_arc(center, outer_r, 0.0, TAU, 48, center_color, 1.2, true)
	draw_arc(center, inner_r, 0.0, TAU, 8, center_color, 1.1, true)

	# Expanding beat-wave ring inside the center radar emblem
	if beat_energy > 0.05:
		var wave_r: float = lerpf(inner_r, outer_r * 1.16, beat_phase)
		var wave_alpha: float = (1.0 - beat_phase) * beat_energy * 0.42
		draw_arc(center, wave_r, 0.0, TAU, 40, Color(0.55, 0.55, 0.55, wave_alpha), 1.2, true)
		var bar_len: float = 5.0 + 10.0 * beat_energy
		for i: int in range(8):
			var ang: float = TAU * float(i) / 8.0
			var dir: Vector2 = Vector2.from_angle(ang)
			draw_line(center + dir * outer_r, center + dir * (outer_r + bar_len * (1.0 if i % 2 == 0 else 0.55)), center_color, 1.3, true)

	# Arena border & corner brackets
	var border: Color = BASE_BORDER.lerp(PULSE_COLOR, pulse_strength * 0.68)
	draw_rect(Rect2(Vector2.ONE, arena_size - Vector2.ONE * 2.0), border, false, 2.0)
	var tick: float = 20.0
	var tick_color: Color = border
	tick_color.a = 0.92
	for corner: Vector2 in [Vector2(0.0, 0.0), Vector2(width, 0.0), Vector2(0.0, height), Vector2(width, height)]:
		var x_dir: float = 1.0 if corner.x < width * 0.5 else -1.0
		var y_dir: float = 1.0 if corner.y < height * 0.5 else -1.0
		draw_line(corner, corner + Vector2(tick * x_dir, 0.0), tick_color, 3.0)
		draw_line(corner, corner + Vector2(0.0, tick * y_dir), tick_color, 3.0)
