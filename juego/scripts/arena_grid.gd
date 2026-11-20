extends Node2D

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

var _minor_lines: PackedVector2Array = PackedVector2Array()
var _major_lines: PackedVector2Array = PackedVector2Array()
var _crosshair_lines: PackedVector2Array = PackedVector2Array()
var _center_crosshair_lines: PackedVector2Array = PackedVector2Array()
var _corner_tick_lines: PackedVector2Array = PackedVector2Array()
var _beat_bar_dirs: PackedVector2Array = PackedVector2Array()
var _beat_bar_pts: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	set_process(false)
	_rebuild_cached_geometry()
	queue_redraw()


func set_arena_size(new_size: Vector2) -> void:
	if new_size.x > 0.0 and new_size.y > 0.0:
		arena_size = new_size
		_rebuild_cached_geometry()
		queue_redraw()


func set_music_state(phase: float, energy: float, section: int) -> void:
	var next_phase: float = clampf(phase, 0.0, 1.0)
	var next_energy: float = clampf(energy, 0.0, 1.0)
	var next_section: int = maxi(section, 0)
	if (
		absf(beat_phase - next_phase) <= 0.002
		and absf(beat_energy - next_energy) <= 0.002
		and next_section == music_section
	):
		return
	beat_phase = next_phase
	beat_energy = next_energy
	music_section = next_section
	queue_redraw()


func pulse(strength: float = 0.5) -> void:
	pulse_strength = clampf(maxf(pulse_strength, strength), 0.0, 1.0)
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	pulse_strength = maxf(0.0, pulse_strength - delta * 2.6)
	queue_redraw()
	if pulse_strength <= 0.0:
		set_process(false)


func _rebuild_cached_geometry() -> void:
	if _beat_bar_dirs.size() != 8:
		_beat_bar_dirs.resize(8)
		for i: int in range(8):
			_beat_bar_dirs[i] = Vector2.from_angle(TAU * float(i) / 8.0)
	if _beat_bar_pts.size() != 16:
		_beat_bar_pts.resize(16)

	_minor_lines.clear()
	_major_lines.clear()
	_crosshair_lines.clear()
	_center_crosshair_lines.clear()
	_corner_tick_lines.clear()

	var width: float = arena_size.x
	var height: float = arena_size.y
	if width <= 1.0 or height <= 1.0:
		return

	var col_idx: int = 1
	var x: float = GRID_SPACING
	while x < width - 1.0:
		if col_idx % 2 == 0:
			_major_lines.append(Vector2(x, 0.0))
			_major_lines.append(Vector2(x, height))
		else:
			_minor_lines.append(Vector2(x, 0.0))
			_minor_lines.append(Vector2(x, height))
		x += GRID_SPACING
		col_idx += 1

	var row_idx: int = 1
	var y: float = GRID_SPACING
	while y < height - 1.0:
		if row_idx % 2 == 0:
			_major_lines.append(Vector2(0.0, y))
			_major_lines.append(Vector2(width, y))
		else:
			_minor_lines.append(Vector2(0.0, y))
			_minor_lines.append(Vector2(width, y))
		y += GRID_SPACING
		row_idx += 1

	var gx: float = GRID_SPACING * 2.0
	while gx < width - 1.0:
		var gy: float = GRID_SPACING * 2.0
		while gy < height - 1.0:
			_crosshair_lines.append(Vector2(gx - 3.0, gy))
			_crosshair_lines.append(Vector2(gx + 3.0, gy))
			_crosshair_lines.append(Vector2(gx, gy - 3.0))
			_crosshair_lines.append(Vector2(gx, gy + 3.0))
			gy += GRID_SPACING * 2.0
		gx += GRID_SPACING * 2.0

	var center: Vector2 = arena_size * 0.5
	_center_crosshair_lines.append(Vector2(center.x, center.y - 22.0))
	_center_crosshair_lines.append(Vector2(center.x, center.y + 22.0))
	_center_crosshair_lines.append(Vector2(center.x - 22.0, center.y))
	_center_crosshair_lines.append(Vector2(center.x + 22.0, center.y))

	for corner: Vector2 in [Vector2.ZERO, Vector2(width, 0.0), Vector2(0.0, height), Vector2(width, height)]:
		var x_dir: float = 1.0 if corner.x < width * 0.5 else -1.0
		var y_dir: float = 1.0 if corner.y < height * 0.5 else -1.0
		_corner_tick_lines.append(corner)
		_corner_tick_lines.append(corner + Vector2(20.0 * x_dir, 0.0))
		_corner_tick_lines.append(corner)
		_corner_tick_lines.append(corner + Vector2(0.0, 20.0 * y_dir))


func _draw() -> void:
	var width: float = arena_size.x
	var height: float = arena_size.y
	if width <= 1.0 or height <= 1.0:
		return

	var minor_color: Color = Color(BASE_GRID.r, BASE_GRID.g, BASE_GRID.b, 0.55 + 0.25 * pulse_strength)
	var major_color: Color = Color(MAJOR_GRID.r, MAJOR_GRID.g, MAJOR_GRID.b, 0.65 + 0.30 * pulse_strength)

	if _minor_lines.size() >= 2:
		draw_multiline(_minor_lines, minor_color, 1.0)
	if _major_lines.size() >= 2:
		draw_multiline(_major_lines, major_color, 1.0)

	var node_col: Color = Color(0.16, 0.16, 0.16, 0.55 + 0.30 * pulse_strength)
	if _crosshair_lines.size() >= 2:
		draw_multiline(_crosshair_lines, node_col, 1.0)

	var center: Vector2 = arena_size * 0.5
	var eff_pulse: float = clampf(pulse_strength + beat_energy * 0.28, 0.0, 1.0)
	var center_gray: float = 0.11 + 0.19 * eff_pulse
	var center_color: Color = Color(center_gray, center_gray, center_gray, 0.86)
	var min_dim: float = minf(width, height)
	var outer_r: float = min_dim * (0.16 + 0.014 * eff_pulse)
	var inner_r: float = min_dim * (0.075 + 0.008 * beat_energy)
	if _center_crosshair_lines.size() >= 2:
		draw_multiline(_center_crosshair_lines, center_color, 1.0)
	draw_arc(center, outer_r, 0.0, TAU, 48, center_color, 1.2, true)
	draw_arc(center, inner_r, 0.0, TAU, 8, center_color, 1.1, true)

	if beat_energy > 0.05:
		var wave_r: float = lerpf(inner_r, outer_r * 1.16, beat_phase)
		var wave_alpha: float = (1.0 - beat_phase) * beat_energy * 0.42
		draw_arc(center, wave_r, 0.0, TAU, 40, Color(0.55, 0.55, 0.55, wave_alpha), 1.2, true)
		var bar_len: float = 5.0 + 10.0 * beat_energy
		for i: int in range(8):
			var dir: Vector2 = _beat_bar_dirs[i]
			_beat_bar_pts[i * 2] = center + dir * outer_r
			_beat_bar_pts[i * 2 + 1] = center + dir * (outer_r + bar_len * (1.0 if i % 2 == 0 else 0.55))
		if _beat_bar_pts.size() >= 2:
			draw_multiline(_beat_bar_pts, center_color, 1.3, true)

	var border: Color = BASE_BORDER.lerp(PULSE_COLOR, pulse_strength * 0.68)
	draw_rect(Rect2(Vector2.ONE, arena_size - Vector2.ONE * 2.0), border, false, 2.0)
	var tick_color: Color = Color(border.r, border.g, border.b, 0.92)
	if _corner_tick_lines.size() >= 2:
		draw_multiline(_corner_tick_lines, tick_color, 3.0)
