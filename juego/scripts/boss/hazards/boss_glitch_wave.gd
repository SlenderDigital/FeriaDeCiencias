class_name BossGlitchWave
extends Node2D

# Phase 8 Signature Special: THE CHROMATIC GLITCH WAVE.
# The ONLY boss hazard permitted vibrant RGB chromatic aberration colors,
# rendered 100% procedurally inside _draw() with zero child nodes.

signal glitch_parried(wave_pos: Vector2)
signal glitch_started()
signal glitch_ended()

enum Phase {
	TELEGRAPH = 0,
	ACTIVE = 1,
	SHATTER_PURGE = 2,
	FADE_OUT = 3,
}

const COL_MAGENTA: Color = Color(1.0, 0.16, 0.52, 1.0)
const COL_CYAN: Color = Color(0.0, 0.94, 1.0, 1.0)
const COL_YELLOW: Color = Color(1.0, 0.90, 0.05, 1.0)
const COL_WHITE: Color = Color(1.0, 1.0, 1.0, 1.0)
const COL_VOID: Color = Color(0.04, 0.04, 0.04, 1.0)

const MIN_GAP_SIZE: float = 145.0
const SHATTER_DURATION: float = 0.28
const FADE_DURATION: float = 0.22
const GLITCH_SLICE_COUNT: int = 24

var is_hazard_active: bool = false
var parryable: bool = true
var hazard_kind: StringName = &"glitch_wave"

var current_phase: int = Phase.TELEGRAPH
var phase_timer: float = 0.0

var _arena_size: Vector2 = BossConstants.ARENA_REF
var _sweep_dir: Vector2 = Vector2.RIGHT
var _perp_dir: Vector2 = Vector2.DOWN
var _warning_time: float = 0.9375
var _sweep_time: float = 1.65
var _wave_thickness: float = 74.0
var _gap_size: float = 148.0
var _gap_wobble: float = 68.0

var _sweep_min: float = 0.0
var _sweep_max: float = 1152.0
var _perp_min: float = 0.0
var _perp_max: float = 648.0
var _sweep_start: float = -37.0
var _sweep_end: float = 1189.0
var _current_sweep: float = -37.0
var _base_gap_perp: float = 324.0
var _current_gap_perp: float = 324.0

var _glitch_time: float = 0.0
var _ended_emitted: bool = false
var _queued_free: bool = false
var _slice_seeds: Array[float] = []
var _shatter_shards: Array[Dictionary] = []
var _scratch_quad: PackedVector2Array = PackedVector2Array()
var _rail_pts: PackedVector2Array = PackedVector2Array()
var _chev_pts: PackedVector2Array = PackedVector2Array()
var _chev_yellow_pts: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_scratch_quad.resize(4)
	add_to_group("boss_hazards")
	_init_slice_seeds()


func _ready() -> void:
	if not is_in_group("boss_hazards"):
		add_to_group("boss_hazards")
	queue_redraw()


func _physics_process(delta: float) -> void:
	simulate_physics(delta)


func configure(
	arena_size: Vector2,
	direction: Vector2,
	warning_time: float = 0.9375,
	sweep_time: float = 1.65,
	wave_thickness: float = 74.0,
	gap_center_ratio: float = 0.5,
	gap_size: float = 148.0,
	gap_wobble: float = 68.0,
	is_parryable: bool = true
) -> void:
	global_position = Vector2.ZERO
	_arena_size = arena_size
	_sweep_dir = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	_perp_dir = Vector2(-_sweep_dir.y, _sweep_dir.x)
	if absf(_sweep_dir.x) >= absf(_sweep_dir.y):
		if _perp_dir.y < 0.0:
			_perp_dir = -_perp_dir
	else:
		if _perp_dir.x < 0.0:
			_perp_dir = -_perp_dir
	_warning_time = maxf(warning_time, 0.001)
	_sweep_time = maxf(sweep_time, 0.1)
	_wave_thickness = maxf(wave_thickness, 24.0)
	_gap_size = maxf(gap_size, MIN_GAP_SIZE)
	_gap_wobble = maxf(gap_wobble, 0.0)
	parryable = is_parryable

	# Project arena corners onto sweep & transverse axes so any direction works cleanly
	var corners: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(_arena_size.x, 0.0),
		Vector2(0.0, _arena_size.y),
		_arena_size,
	]
	_sweep_min = INF
	_sweep_max = -INF
	_perp_min = INF
	_perp_max = -INF
	for c: Vector2 in corners:
		var s: float = c.dot(_sweep_dir)
		var p: float = c.dot(_perp_dir)
		_sweep_min = minf(_sweep_min, s)
		_sweep_max = maxf(_sweep_max, s)
		_perp_min = minf(_perp_min, p)
		_perp_max = maxf(_perp_max, p)

	var half_t: float = _wave_thickness * 0.5
	_sweep_start = _sweep_min - half_t
	_sweep_end = _sweep_max + half_t
	_current_sweep = _sweep_start

	var perp_span: float = maxf(_perp_max - _perp_min, _gap_size + 40.0)
	var pad: float = minf(_gap_size * 0.62, perp_span * 0.42)
	_base_gap_perp = lerpf(_perp_min + pad, _perp_max - pad, clampf(gap_center_ratio, 0.1, 0.9))
	_current_gap_perp = _eval_gap_perp(0.0)

	current_phase = Phase.TELEGRAPH
	phase_timer = 0.0
	_glitch_time = 0.0
	_ended_emitted = false
	is_hazard_active = false
	_shatter_shards.clear()
	_init_slice_seeds()
	queue_redraw()


func get_wave_center() -> Vector2:
	return _sweep_dir * _current_sweep + _perp_dir * _current_gap_perp


func purge_by_parry() -> void:
	if _queued_free or current_phase == Phase.SHATTER_PURGE or current_phase == Phase.FADE_OUT:
		return
	is_hazard_active = false
	current_phase = Phase.SHATTER_PURGE
	phase_timer = 0.0
	_spawn_shatter_shards()
	BossConstants.play_sfx(self, &"shield_block", -1.0)
	glitch_parried.emit(get_wave_center())
	_emit_ended_once()
	queue_redraw()


func simulate_physics(delta: float, player_node: Node2D = null) -> void:
	if _queued_free:
		return

	_glitch_time += delta
	phase_timer += delta

	match current_phase:
		Phase.TELEGRAPH:
			is_hazard_active = false
			if phase_timer >= _warning_time:
				current_phase = Phase.ACTIVE
				phase_timer = 0.0
				_current_sweep = _sweep_start
				is_hazard_active = true
				BossConstants.play_sfx(self, &"boss_phase", -4.0)
				glitch_started.emit()
				_check_player_overlap(player_node)

		Phase.ACTIVE:
			var progress: float = clampf(phase_timer / maxf(_sweep_time, 0.001), 0.0, 1.0)
			_current_sweep = lerpf(_sweep_start, _sweep_end, progress)
			_current_gap_perp = _eval_gap_perp(progress)
			_check_player_overlap(player_node)
			if phase_timer >= _sweep_time:
				current_phase = Phase.FADE_OUT
				phase_timer = 0.0
				is_hazard_active = false
				_emit_ended_once()

		Phase.SHATTER_PURGE:
			is_hazard_active = false
			for sh: Dictionary in _shatter_shards:
				sh["pos"] = Vector2(sh["pos"]) + Vector2(sh["vel"]) * delta
				sh["vel"] = Vector2(sh["vel"]) * (1.0 - minf(delta * 4.5, 0.85))
			if phase_timer >= SHATTER_DURATION:
				_queued_free = true
				queue_free()
				return

		Phase.FADE_OUT:
			is_hazard_active = false
			if phase_timer >= FADE_DURATION:
				_queued_free = true
				queue_free()
				return

	queue_redraw()


func _emit_ended_once() -> void:
	if not _ended_emitted:
		_ended_emitted = true
		glitch_ended.emit()


func _check_player_overlap(player_node: Node2D = null) -> void:
	if not is_hazard_active:
		return
	var players: Array[Node2D] = BossConstants.collect_players(self, player_node)
	var half_t: float = _wave_thickness * 0.5
	var half_gap: float = _gap_size * 0.5
	for body: Node2D in players:
		var player_r: float = BossConstants.get_player_hit_radius(body)
		var p_pos: Vector2 = body.global_position
		var s_coord: float = p_pos.dot(_sweep_dir)
		var p_coord: float = p_pos.dot(_perp_dir)
		if absf(s_coord - _current_sweep) <= half_t + player_r:
			var safe_inside_gap: bool = absf(p_coord - _current_gap_perp) <= maxf(half_gap - player_r, 0.0)
			if not safe_inside_gap:
				BossConstants.apply_player_hit(body, parryable, hazard_kind)


func _init_slice_seeds() -> void:
	_slice_seeds.resize(GLITCH_SLICE_COUNT)
	for i: int in range(GLITCH_SLICE_COUNT):
		_slice_seeds[i] = fposmod(sin(float(i + 1) * 12.9898) * 43758.5453, 1.0)


func _spawn_shatter_shards() -> void:
	_shatter_shards.clear()
	var count: int = 28
	var span: float = _perp_max - _perp_min
	for i: int in range(count):
		var frac: float = float(i) / float(count)
		var p_val: float = _perp_min + span * frac
		var origin: Vector2 = _sweep_dir * _current_sweep + _perp_dir * p_val
		var jitter_a: float = (fposmod(float(i) * 0.618, 1.0) - 0.5) * 1.4
		var burst_dir: Vector2 = (_sweep_dir * (1.0 if i % 2 == 0 else -1.0)).rotated(jitter_a)
		var speed: float = 280.0 + 360.0 * fposmod(float(i) * 0.382, 1.0)
		var col: Color = COL_MAGENTA
		if i % 3 == 1:
			col = COL_CYAN
		elif i % 3 == 2:
			col = COL_YELLOW
		_shatter_shards.append({
			"pos": origin,
			"vel": burst_dir * speed,
			"size": 10.0 + 14.0 * fposmod(float(i) * 0.713, 1.0),
			"color": col,
		})


func _make_oriented_quad(s0: float, s1: float, p0: float, p1: float, offset: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	_scratch_quad[0] = _sweep_dir * s0 + _perp_dir * p0 + offset
	_scratch_quad[1] = _sweep_dir * s1 + _perp_dir * p0 + offset
	_scratch_quad[2] = _sweep_dir * s1 + _perp_dir * p1 + offset
	_scratch_quad[3] = _sweep_dir * s0 + _perp_dir * p1 + offset
	return _scratch_quad


func _eval_gap_perp(progress: float) -> float:
	var p: float = clampf(progress, 0.0, 1.0)
	var wobble: float = sin(p * TAU * 1.25) * _gap_wobble
	var min_gap_c: float = _perp_min + _gap_size * 0.56
	var max_gap_c: float = _perp_max - _gap_size * 0.56
	return clampf(_base_gap_perp + wobble, min_gap_c, max_gap_c)


func _eval_gap_perp_at_sweep(sweep_coord: float) -> float:
	var p: float = clampf((sweep_coord - _sweep_start) / maxf(_sweep_end - _sweep_start, 0.001), 0.0, 1.0)
	return _eval_gap_perp(p)


func _append_wave_corridor_rails(segments: int, dash_len: float, gap_len: float, anim_phase: float) -> void:
	_rail_pts.resize(0)
	var half_gap: float = _gap_size * 0.5
	var n_segs: int = maxi(segments, 1)
	var arc_lo: float = 0.0
	var arc_hi: float = 0.0
	var prev_s: float = _sweep_min
	var prev_c: float = _eval_gap_perp_at_sweep(prev_s)
	var prev_lo: Vector2 = _sweep_dir * prev_s + _perp_dir * (prev_c - half_gap)
	var prev_hi: Vector2 = _sweep_dir * prev_s + _perp_dir * (prev_c + half_gap)

	for i: int in range(1, n_segs + 1):
		var t: float = float(i) / float(n_segs)
		var cur_s: float = lerpf(_sweep_min, _sweep_max, t)
		var cur_c: float = _eval_gap_perp_at_sweep(cur_s)
		var cur_lo: Vector2 = _sweep_dir * cur_s + _perp_dir * (cur_c - half_gap)
		var cur_hi: Vector2 = _sweep_dir * cur_s + _perp_dir * (cur_c + half_gap)
		_rail_pts = BossConstants.append_dashed_line_pts(_rail_pts, prev_lo, cur_lo, dash_len, gap_len, anim_phase + arc_lo)
		_rail_pts = BossConstants.append_dashed_line_pts(_rail_pts, prev_hi, cur_hi, dash_len, gap_len, anim_phase + arc_hi)
		arc_lo += prev_lo.distance_to(cur_lo)
		arc_hi += prev_hi.distance_to(cur_hi)
		prev_lo = cur_lo
		prev_hi = cur_hi


func _draw() -> void:
	match current_phase:
		Phase.TELEGRAPH:
			_draw_telegraph()
		Phase.ACTIVE:
			_draw_active()
		Phase.SHATTER_PURGE:
			_draw_shatter_purge()
		Phase.FADE_OUT:
			_draw_fade_out()


func _draw_telegraph() -> void:
	var progress: float = clampf(phase_timer / maxf(_warning_time, 0.001), 0.0, 1.0)
	var flicker: float = 0.68 + 0.32 * sin(_glitch_time * 52.0)
	var entry_gap: float = _eval_gap_perp(0.0)
	var gap_lo: float = entry_gap - _gap_size * 0.5
	var gap_hi: float = entry_gap + _gap_size * 0.5

	# RGB chromatic scanline rails across the entry band
	var band_depth: float = lerpf(28.0, _wave_thickness * 0.95, ease(progress, 0.6))
	var s0: float = _sweep_min
	var s1: float = _sweep_min + band_depth

	var mag_col: Color = Color(COL_MAGENTA.r, COL_MAGENTA.g, COL_MAGENTA.b, (0.28 + 0.45 * progress) * flicker)
	var cyn_col: Color = Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, (0.28 + 0.45 * progress) * flicker)
	var yel_col: Color = Color(COL_YELLOW.r, COL_YELLOW.g, COL_YELLOW.b, (0.22 + 0.42 * progress) * flicker)

	var wings: Array[Vector2] = [Vector2(_perp_min, gap_lo), Vector2(gap_hi, _perp_max)]
	for w: Vector2 in wings:
		if w.y - w.x <= 2.0:
			continue
		draw_colored_polygon(_make_oriented_quad(s0, s1, w.x, w.y, -_sweep_dir * 5.0 - _perp_dir * 3.0), mag_col)
		draw_colored_polygon(_make_oriented_quad(s0, s1, w.x, w.y, _sweep_dir * 5.0 + _perp_dir * 3.0), cyn_col)

	# Flickering RGB chromatic scanline rails spanning the arena
	var rail_s: float = lerpf(_sweep_min + 220.0, _sweep_min + 14.0, progress)
	var a0: Vector2 = _sweep_dir * rail_s + _perp_dir * _perp_min
	var a1: Vector2 = _sweep_dir * rail_s + _perp_dir * _perp_max
	draw_line(a0 - _sweep_dir * 6.0, a1 - _sweep_dir * 6.0, mag_col, 2.2, true)
	draw_line(a0 + _sweep_dir * 6.0, a1 + _sweep_dir * 6.0, cyn_col, 2.2, true)
	draw_line(a0, a1, yel_col, 1.6, true)

	# Converging glitch blocks signaling exact sweep direction (polygons first, chevrons batched)
	var block_s: float = lerpf(_sweep_min + 180.0, _sweep_min + 24.0, progress)
	_chev_pts.resize(0)
	for i: int in range(10):
		var frac: float = (float(i) + 0.5) / 10.0
		var p_val: float = lerpf(_perp_min, _perp_max, frac)
		if p_val > gap_lo - 10.0 and p_val < gap_hi + 10.0:
			continue
		var j_off: float = sin(_glitch_time * 38.0 + float(i) * 2.1) * 14.0
		var b_col: Color = COL_MAGENTA if i % 3 == 0 else (COL_CYAN if i % 3 == 1 else COL_YELLOW)
		b_col.a = 0.45 + 0.45 * progress
		draw_colored_polygon(_make_oriented_quad(block_s + j_off, block_s + j_off + 18.0, p_val - 12.0, p_val + 12.0), b_col)
		_chev_pts = BossConstants.append_double_chevron_pts(_chev_pts, _sweep_dir * (s1 + 18.0) + _perp_dir * p_val, _sweep_dir, 8.5)

	if _chev_pts.size() >= 2:
		draw_multiline(_chev_pts, Color(1.0, 1.0, 1.0, 0.42 + 0.50 * progress), 1.6, true)

	# Exact sinusoidal safe-corridor wave rails (24 segments across _sweep_min.._sweep_max)
	var gap_col: Color = Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, 0.45 + 0.45 * progress)
	_append_wave_corridor_rails(24, 14.0, 10.0, _glitch_time * 90.0)
	if _rail_pts.size() >= 2:
		draw_multiline(_rail_pts, gap_col, 1.8, true)


func _draw_active() -> void:
	var half_t: float = _wave_thickness * 0.5
	var s0: float = _current_sweep - half_t
	var s1: float = _current_sweep + half_t
	var gap_lo: float = _current_gap_perp - _gap_size * 0.5
	var gap_hi: float = _current_gap_perp + _gap_size * 0.5
	var wings: Array[Vector2] = [Vector2(_perp_min, gap_lo), Vector2(gap_hi, _perp_max)]

	# 0. Persistent faint sinusoidal guide rails tracing exact corridor trajectory
	_append_wave_corridor_rails(24, 14.0, 10.0, _glitch_time * 90.0)
	if _rail_pts.size() >= 2:
		draw_multiline(_rail_pts, Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, 0.30), 1.5, true)

	# 1. Animated scanline echo trail behind crest
	for echo_i: int in range(1, 5):
		var trail_shift: float = float(echo_i) * (_wave_thickness * 0.58)
		var echo_alpha: float = 0.34 / float(echo_i)
		var echo_col: Color = COL_MAGENTA if echo_i % 2 == 1 else COL_CYAN
		echo_col.a = echo_alpha
		var es0: float = s0 - trail_shift
		var es1: float = s0 - trail_shift + _wave_thickness * 0.32
		for w: Vector2 in wings:
			if w.y - w.x <= 2.0:
				continue
			draw_colored_polygon(_make_oriented_quad(es0, es1, w.x, w.y), echo_col)

	# 2. Chromatic RGB aberration split silhouettes (Magenta / Cyan / Yellow / White core)
	var chroma_shift: float = 7.5 + 3.5 * sin(_glitch_time * 42.0)
	var mag_off: Vector2 = -_sweep_dir * chroma_shift - _perp_dir * 3.0
	var cyn_off: Vector2 = _sweep_dir * chroma_shift + _perp_dir * 3.0

	for w: Vector2 in wings:
		if w.y - w.x <= 2.0:
			continue
		# Magenta & Cyan shifted silhouettes
		draw_colored_polygon(_make_oriented_quad(s0, s1, w.x, w.y, mag_off), Color(COL_MAGENTA.r, COL_MAGENTA.g, COL_MAGENTA.b, 0.86))
		draw_colored_polygon(_make_oriented_quad(s0, s1, w.x, w.y, cyn_off), Color(COL_CYAN.r, COL_CYAN.g, COL_CYAN.b, 0.86))
		# Stark white reality-tear core
		draw_colored_polygon(_make_oriented_quad(s0 + 6.0, s1 - 6.0, w.x, w.y), Color(1.0, 1.0, 1.0, 0.96))
		# Dark inner glitch fracture stripe
		draw_colored_polygon(_make_oriented_quad(_current_sweep - 5.0, _current_sweep + 5.0, w.x, w.y), Color(0.05, 0.05, 0.05, 0.72))

	# 3. Jittering frequency glitch slices snapping across the wave
	var total_p: float = _perp_max - _perp_min
	var slice_h: float = total_p / float(GLITCH_SLICE_COUNT)
	var tick: float = floor(_glitch_time * 24.0)
	for i: int in range(GLITCH_SLICE_COUNT):
		var p_a: float = _perp_min + float(i) * slice_h
		var p_b: float = p_a + slice_h * 0.72
		var p_mid: float = (p_a + p_b) * 0.5
		if p_mid > gap_lo - 4.0 and p_mid < gap_hi + 4.0:
			continue
		var h: float = fposmod(sin(_slice_seeds[i] * 73.1 + tick * 1.97) * 43758.5, 1.0)
		if h < 0.42:
			continue
		var jitter_s: float = (h - 0.5) * 46.0
		var slice_col: Color = COL_YELLOW if h > 0.78 else (COL_MAGENTA if i % 2 == 0 else COL_CYAN)
		slice_col.a = 0.88
		draw_colored_polygon(_make_oriented_quad(s0 + jitter_s, s1 + jitter_s * 0.6, p_a, p_b), slice_col)

	# 4. Clearly framed shifting safe gap brackets (batched)
	var bracket_s0: float = s0 - 10.0
	var bracket_s1: float = s1 + 10.0
	_rail_pts.resize(4)
	_chev_pts.resize(4)
	var lo_start: Vector2 = _sweep_dir * bracket_s0 + _perp_dir * gap_lo
	var lo_end: Vector2 = _sweep_dir * bracket_s1 + _perp_dir * gap_lo
	var hi_start: Vector2 = _sweep_dir * bracket_s0 + _perp_dir * gap_hi
	var hi_end: Vector2 = _sweep_dir * bracket_s1 + _perp_dir * gap_hi
	_rail_pts[0] = lo_start
	_rail_pts[1] = lo_end
	_rail_pts[2] = hi_start
	_rail_pts[3] = hi_end
	_chev_pts[0] = lo_start + _perp_dir * 4.0
	_chev_pts[1] = lo_end + _perp_dir * 4.0
	_chev_pts[2] = hi_start - _perp_dir * 4.0
	_chev_pts[3] = hi_end - _perp_dir * 4.0
	draw_multiline(_rail_pts, COL_WHITE, 3.0, true)
	draw_multiline(_chev_pts, COL_CYAN, 2.0, true)

	# 5. Bright double-chevron parry rim along leading crest (batched)
	if parryable:
		var lead_s: float = s1 + 10.0
		_chev_yellow_pts.resize(0)
		_chev_pts.resize(0)
		for w: Vector2 in wings:
			var p_cur: float = w.x + 26.0
			while p_cur < w.y - 18.0:
				var c_pos: Vector2 = _sweep_dir * lead_s + _perp_dir * p_cur
				_chev_yellow_pts = BossConstants.append_double_chevron_pts(_chev_yellow_pts, c_pos - _sweep_dir * 3.0, _sweep_dir, 9.0)
				_chev_pts = BossConstants.append_double_chevron_pts(_chev_pts, c_pos, _sweep_dir, 9.0)
				p_cur += 52.0
		if _chev_yellow_pts.size() >= 2:
			draw_multiline(_chev_yellow_pts, COL_YELLOW, 2.0, true)
		if _chev_pts.size() >= 2:
			draw_multiline(_chev_pts, COL_WHITE, 1.8, true)


func _draw_shatter_purge() -> void:
	var t: float = clampf(phase_timer / maxf(SHATTER_DURATION, 0.001), 0.0, 1.0)
	var inv: float = 1.0 - t
	# Monochrome-restoring burst ring at wave center
	var center: Vector2 = get_wave_center()
	draw_arc(center, lerpf(24.0, 260.0, ease(t, 0.35)), 0.0, TAU, 48, Color(1.0, 1.0, 1.0, inv * 0.95), 4.0 * inv + 1.0, true)

	# Shards rapidly desaturate from RGB glitch colors back into stark monochrome white!
	var desat: float = clampf(t * 2.2, 0.0, 1.0)
	for sh: Dictionary in _shatter_shards:
		var pos: Vector2 = sh["pos"]
		var sz: float = float(sh["size"]) * inv
		if sz <= 0.5:
			continue
		var src_col: Color = sh["color"]
		var col: Color = src_col.lerp(COL_WHITE, desat)
		col.a = inv
		draw_rect(Rect2(pos - Vector2(sz, sz * 0.45), Vector2(sz * 2.0, sz * 0.9)), col, true)


func _draw_fade_out() -> void:
	var t: float = clampf(phase_timer / maxf(FADE_DURATION, 0.001), 0.0, 1.0)
	var inv: float = 1.0 - t
	var half_t: float = _wave_thickness * 0.5 * inv
	if half_t <= 0.5:
		return
	var gap_lo: float = _current_gap_perp - _gap_size * 0.5
	var gap_hi: float = _current_gap_perp + _gap_size * 0.5
	var wings: Array[Vector2] = [Vector2(_perp_min, gap_lo), Vector2(gap_hi, _perp_max)]
	for w: Vector2 in wings:
		if w.y - w.x <= 2.0:
			continue
		draw_colored_polygon(
			_make_oriented_quad(_current_sweep - half_t, _current_sweep + half_t, w.x, w.y),
			Color(1.0, 1.0, 1.0, inv * 0.72)
		)
