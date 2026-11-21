class_name BossConstants
extends RefCounted

const BPM: float = 128.0
const BEAT_DURATION: float = 60.0 / BPM
const BEATS_PER_BAR: int = 4
const BARS_PER_PHASE: int = 8
const BEATS_PER_PHASE: int = 32
const TOTAL_PHASES: int = 8
const TOTAL_BEATS: int = 256
const PHASE_DURATION: float = 15.0
const TOTAL_DURATION: float = 120.0
const ARENA_REF: Vector2 = Vector2(1152.0, 648.0)

const BOSS_PLAYER_SCALE: float = 0.78
const BOSS_BODY_RADIUS: float = 30.0
const BOSS_HAND_RADIUS: float = 19.0

const PARRY_WINDOW_SEC: float = 0.32
const PARRY_COOLDOWN_SEC: float = 0.36
const PARRY_SHIELD_REFUND: float = 0.35

const BEAM_WIDTH: float = 26.0
const WHEEL_BEAM_WIDTH: float = 22.0
const BULLET_RADIUS: float = 6.5
const CIRCLE_RADIUS: float = 54.0
const HEX_RADIUS: float = 44.0
const SPIKE_RADIUS: float = 18.0
const PISTON_THICKNESS: float = 34.0

const SQRT3_HALF: float = 0.8660254037844386

enum MinionType {
	THREAD_SPIDER = 0,
	ORBIT_SPECTER = 1,
	BORDER_SNAPPER = 2,
}

enum HexPattern {
	WAVE_LR = 0,
	WAVE_TB = 1,
	CHECKER_A = 2,
	CHECKER_B = 3,
	BORDER_RING = 4,
	CORRIDOR_H = 5,
	CORRIDOR_V = 6,
	SPIRAL = 7,
}


static func get_player_hit_radius(player: Node2D) -> float:
	if player == null:
		return 12.0 * BOSS_PLAYER_SCALE
	return 12.0 * clampf(player.scale.x, 0.5, 1.5)


static func collect_players(host: Node, explicit_player: Node2D = null) -> Array[Node2D]:
	var result: Array[Node2D] = []
	if explicit_player != null and is_instance_valid(explicit_player):
		result.append(explicit_player)
	if host != null and host.is_inside_tree():
		var tree: SceneTree = host.get_tree()
		if tree != null:
			for node: Node in tree.get_nodes_in_group("player"):
				var body: Node2D = node as Node2D
				if body != null and is_instance_valid(body) and not result.has(body):
					result.append(body)
	return result


static func apply_player_hit(player: Node2D, is_parryable: bool, kind: StringName = &"") -> void:
	if player == null or not is_instance_valid(player):
		return
	player.set_meta(&"last_hit_parryable", is_parryable)
	player.set_meta(&"last_hit_hazard_kind", kind)
	if player.has_method(&"take_damage"):
		player.take_damage(1)


static func play_sfx(host: Node, sfx_name: StringName, volume_db: float = 0.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	var tree: SceneTree = host.get_tree()
	if tree == null or tree.root == null:
		return
	var sm: Node = tree.root.get_node_or_null(^"SoundManager")
	if sm != null and sm.has_method(&"play_sfx"):
		sm.play_sfx(sfx_name, volume_db)


static func circle_rect_overlap(center: Vector2, radius: float, rect: Rect2) -> bool:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	var clamped_x: float = clampf(center.x, rect.position.x, rect.position.x + rect.size.x)
	var clamped_y: float = clampf(center.y, rect.position.y, rect.position.y + rect.size.y)
	var dx: float = center.x - clamped_x
	var dy: float = center.y - clamped_y
	return (dx * dx + dy * dy) <= radius * radius


static func circle_flat_hex_overlap(local_p: Vector2, hex_radius: float, circle_radius: float) -> bool:
	var max_r: float = hex_radius + circle_radius
	if local_p.length_squared() > max_r * max_r:
		return false
	var ax: float = absf(local_p.x)
	var ay: float = absf(local_p.y)
	var apothem_plus: float = hex_radius * SQRT3_HALF + circle_radius
	if ay > apothem_plus:
		return false
	if (ax * SQRT3_HALF + ay * 0.5) > apothem_plus:
		return false
	return true


static func append_dashed_line_pts(
	out: PackedVector2Array,
	from: Vector2,
	to: Vector2,
	dash_len: float = 12.0,
	gap_len: float = 8.0,
	phase_offset: float = 0.0
) -> PackedVector2Array:
	var diff: Vector2 = to - from
	var total_len: float = diff.length()
	if total_len <= 0.001:
		return out
	var dir: Vector2 = diff / total_len
	var stride: float = maxf(dash_len + gap_len, 2.0)
	var cursor: float = -fposmod(phase_offset, stride)
	var est_segs: int = int(ceil((total_len - cursor) / stride)) + 2
	var write_idx: int = out.size()
	out.resize(write_idx + maxi(est_segs, 2) * 2)
	while cursor < total_len:
		var seg_start: float = maxf(cursor, 0.0)
		var seg_end: float = minf(cursor + dash_len, total_len)
		if seg_end > seg_start:
			out[write_idx] = from + dir * seg_start
			out[write_idx + 1] = from + dir * seg_end
			write_idx += 2
		cursor += stride
	if write_idx != out.size():
		out.resize(write_idx)
	return out


static func append_double_chevron_pts(
	out: PackedVector2Array,
	pos: Vector2,
	dir: Vector2,
	size: float
) -> PackedVector2Array:
	var fwd: Vector2 = dir.normalized() if dir.length_squared() > 0.0001 else Vector2.RIGHT
	var side: Vector2 = Vector2(-fwd.y, fwd.x)
	var write_idx: int = out.size()
	out.resize(write_idx + 8)
	for k: int in range(2):
		var base: Vector2 = pos - fwd * (float(k) * size * 0.65)
		var tip: Vector2 = base + fwd * (size * 0.55)
		var left_pt: Vector2 = base - fwd * (size * 0.35) + side * (size * 0.65)
		var right_pt: Vector2 = base - fwd * (size * 0.35) - side * (size * 0.65)
		out[write_idx] = left_pt
		out[write_idx + 1] = tip
		out[write_idx + 2] = right_pt
		out[write_idx + 3] = tip
		write_idx += 4
	return out


static func draw_dashed_line(
	canvas: CanvasItem,
	from: Vector2,
	to: Vector2,
	color: Color,
	width: float = 1.5,
	dash_len: float = 12.0,
	gap_len: float = 8.0,
	phase_offset: float = 0.0
) -> void:
	var pts: PackedVector2Array = append_dashed_line_pts(PackedVector2Array(), from, to, dash_len, gap_len, phase_offset)
	if pts.size() >= 2:
		canvas.draw_multiline(pts, color, width, true)


static func draw_dashed_circle(
	canvas: CanvasItem,
	center: Vector2,
	radius: float,
	color: Color,
	width: float = 1.5,
	segments: int = 24,
	dash_ratio: float = 0.55,
	angle_offset: float = 0.0
) -> void:
	if radius <= 0.5:
		return
	var count: int = maxi(segments, 6)
	var step: float = TAU / float(count)
	var arc_len: float = step * clampf(dash_ratio, 0.1, 0.9)
	var sub_step: float = arc_len / 3.0
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(count * 6)
	var idx: int = 0
	for i: int in range(count):
		var a0: float = angle_offset + step * float(i)
		var p0: Vector2 = center + Vector2.from_angle(a0) * radius
		var p1: Vector2 = center + Vector2.from_angle(a0 + sub_step) * radius
		var p2: Vector2 = center + Vector2.from_angle(a0 + sub_step * 2.0) * radius
		var p3: Vector2 = center + Vector2.from_angle(a0 + arc_len) * radius
		pts[idx] = p0
		pts[idx + 1] = p1
		pts[idx + 2] = p1
		pts[idx + 3] = p2
		pts[idx + 4] = p2
		pts[idx + 5] = p3
		idx += 6
	if pts.size() >= 2:
		canvas.draw_multiline(pts, color, width, true)


static func draw_double_chevron(
	canvas: CanvasItem,
	pos: Vector2,
	dir: Vector2,
	size: float,
	color: Color,
	width: float = 1.8
) -> void:
	var pts: PackedVector2Array = append_double_chevron_pts(PackedVector2Array(), pos, dir, size)
	if pts.size() >= 2:
		canvas.draw_multiline(pts, color, width, true)
