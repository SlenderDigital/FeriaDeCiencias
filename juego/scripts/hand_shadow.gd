extends Node2D

const PALM_POLYGON_INDICES: Array[int] = [0, 1, 5, 9, 13, 17]
const THUMB_BONE_INDICES: Array[int] = [0, 1, 2, 3, 4]
const INDEX_BONE_INDICES: Array[int] = [0, 5, 6, 7, 8]
const MIDDLE_BONE_INDICES: Array[int] = [0, 9, 10, 11, 12]
const RING_BONE_INDICES: Array[int] = [0, 13, 14, 15, 16]
const PINKY_BONE_INDICES: Array[int] = [0, 17, 18, 19, 20]
const PALM_BRIDGE_INDICES: Array[int] = [1, 5, 9, 13, 17, 0]
const FINGERTIP_INDICES: Array[int] = [4, 8, 12, 16, 20]
const FINGER_MID_INDICES: Array[int] = [2, 3, 6, 7, 10, 11, 14, 15, 18, 19]
const SHIELD_HULL_INDICES: Array[int] = [12, 8, 4, 3, 2, 0, 18, 19, 20, 16]
const SHIELD_BASE_RADIUS: float = 56.0

var alpha: float = 0.0
var pulse: float = 0.0
var shield_morph: float = 0.0
var is_shield_visual_active: bool = false

var _last_landmarks_2d: PackedVector2Array = PackedVector2Array()
var _last_revision: int = -1
var _last_fist: bool = false
var _last_pulse_bucket: int = -1
var _last_morph_bucket: int = -1
var _last_energy_bucket: int = -1
var _last_flash_bucket: int = -1
var _last_exhausted: bool = false
var _geometry_dirty: bool = true

@onready var shield_hull_polygon: Polygon2D = $ShieldHullPolygon
@onready var shield_hull_border: Line2D = $ShieldHullBorder
@onready var palm_polygon: Polygon2D = $PalmPolygon
@onready var thumb_bone: Line2D = $ThumbBone
@onready var index_bone: Line2D = $IndexBone
@onready var middle_bone: Line2D = $MiddleBone
@onready var ring_bone: Line2D = $RingBone
@onready var pinky_bone: Line2D = $PinkyBone
@onready var palm_bridge_bone: Line2D = $PalmBridgeBone
@onready var fingertip_4: Polygon2D = $Fingertip4
@onready var fingertip_8: Polygon2D = $Fingertip8
@onready var fingertip_12: Polygon2D = $Fingertip12
@onready var fingertip_16: Polygon2D = $Fingertip16
@onready var fingertip_20: Polygon2D = $Fingertip20


func update_from_tracker(tracker: Node, delta: float, arena_size: Vector2, player: Node = null) -> void:
	var has_tracked_hand: bool = tracker != null and bool(tracker.has_hand)
	var is_fist_held: bool = tracker != null and bool(tracker.is_fist)

	if has_tracked_hand:
		var revision: int = int(tracker.landmark_revision)
		if revision != _last_revision:
			_geometry_dirty = true
			_last_revision = revision
			var mirrored: PackedVector2Array = tracker.get_mirrored_landmarks_2d()
			if mirrored.size() == 21:
				_last_landmarks_2d = mirrored
		if is_fist_held and not _last_fist:
			pulse = 1.0
			_geometry_dirty = true
	else:
		is_fist_held = false

	var energy_ratio: float = 1.0
	var is_exhausted: bool = false
	var block_flash: float = 0.0
	var activation_flash: float = 0.0
	var shield_active: bool = is_fist_held

	if player != null:
		energy_ratio = float(player.get_shield_energy_ratio())
		is_exhausted = bool(player.shield_exhausted)
		block_flash = float(player.shield_block_flash)
		activation_flash = float(player.shield_activation_flash)
		shield_active = has_tracked_hand and (
			bool(player.is_shielding)
			or (is_fist_held and not is_exhausted and energy_ratio > 0.0)
		)

	is_shield_visual_active = shield_active

	if shield_active:
		shield_morph = clampf(maxf(0.95, shield_morph + maxf(0.016, delta) * 12.0), 0.0, 1.0)
	else:
		shield_morph = maxf(0.0, shield_morph - maxf(0.016, delta) * 7.5)

	if pulse > 0.0:
		pulse = maxf(0.0, pulse - maxf(0.0, delta) * 3.8)

	if has_tracked_hand:
		alpha = clampf(maxf(0.55, alpha + maxf(0.016, delta) * 6.0), 0.0, 1.0)
	else:
		alpha = maxf(0.0, alpha - maxf(0.0, delta) * 3.2)

	modulate = Color(1.0, 1.0, 1.0, alpha)
	visible = alpha > 0.001 and _last_landmarks_2d.size() == 21
	if _last_landmarks_2d.size() < 21:
		_last_fist = is_fist_held
		shield_hull_polygon.visible = false
		shield_hull_border.visible = false
		return

	var pulse_bucket: int = int(pulse * 20.0)
	var morph_bucket: int = int(shield_morph * 25.0)
	var energy_bucket: int = int(energy_ratio * 25.0)
	var flash_bucket: int = int((block_flash + activation_flash) * 20.0)
	var dirty: bool = (
		_geometry_dirty
		or is_fist_held != _last_fist
		or pulse_bucket != _last_pulse_bucket
		or morph_bucket != _last_morph_bucket
		or energy_bucket != _last_energy_bucket
		or flash_bucket != _last_flash_bucket
		or is_exhausted != _last_exhausted
	)
	_last_fist = is_fist_held
	if not dirty:
		return
	_last_pulse_bucket = pulse_bucket
	_last_morph_bucket = morph_bucket
	_last_energy_bucket = energy_bucket
	_last_flash_bucket = flash_bucket
	_last_exhausted = is_exhausted
	_geometry_dirty = false

	var screen_pts: PackedVector2Array = PackedVector2Array()
	screen_pts.resize(21)
	for i: int in range(21):
		var norm_pt: Vector2 = _last_landmarks_2d[i]
		screen_pts[i] = Vector2(norm_pt.x * arena_size.x, norm_pt.y * arena_size.y)

	var palm_center_screen: Vector2 = Vector2.ZERO
	for p_idx: int in [0, 5, 9, 13, 17]:
		palm_center_screen += screen_pts[p_idx]
	palm_center_screen /= 5.0

	if shield_morph > 0.001:
		var thumb_side: float = -1.0 if screen_pts[4].x <= screen_pts[20].x else 1.0
		var shield_r: float = SHIELD_BASE_RADIUS * (1.0 + 0.08 * block_flash + 0.05 * activation_flash - 0.04 * (1.0 - energy_ratio))
		var shield_pts: PackedVector2Array = _build_shield_landmarks(palm_center_screen, shield_r, thumb_side)
		for i: int in range(21):
			screen_pts[i] = screen_pts[i].lerp(shield_pts[i], shield_morph)
	else:
		var contract_factor: float = clampf(pulse * 0.25 + (0.12 if is_fist_held else 0.0), 0.0, 0.35)
		if contract_factor > 0.0:
			for tip_idx: int in FINGERTIP_INDICES:
				screen_pts[tip_idx] = screen_pts[tip_idx].lerp(palm_center_screen, contract_factor)

	var low_energy: float = 0.0 if energy_ratio > 0.25 else (1.0 - energy_ratio / 0.25)
	var flicker: float = 1.0 - 0.25 * low_energy * (0.5 + 0.5 * sin(energy_ratio * 90.0))

	var show_hull: bool = shield_morph > 0.02 or block_flash > 0.01
	shield_hull_polygon.visible = show_hull
	shield_hull_border.visible = show_hull
	if show_hull:
		var hull_expand: float = 1.05 + 0.08 * block_flash + 0.04 * activation_flash
		var hull_pts: PackedVector2Array = PackedVector2Array()
		hull_pts.resize(SHIELD_HULL_INDICES.size())
		for i: int in range(SHIELD_HULL_INDICES.size()):
			var pt: Vector2 = screen_pts[SHIELD_HULL_INDICES[i]]
			hull_pts[i] = palm_center_screen + (pt - palm_center_screen) * hull_expand
		shield_hull_polygon.polygon = hull_pts
		shield_hull_border.points = hull_pts

		var hull_gray: float = clampf(0.74 + 0.20 * energy_ratio + 0.12 * block_flash, 0.0, 1.0)
		var hull_fill_alpha: float = clampf((0.18 + 0.16 * block_flash + 0.10 * activation_flash) * shield_morph * flicker, 0.0, 0.65)
		shield_hull_polygon.color = Color(hull_gray, hull_gray, hull_gray, hull_fill_alpha)

		var border_gray: float = clampf(0.82 + 0.18 * energy_ratio + 0.15 * block_flash, 0.0, 1.0)
		var border_alpha: float = clampf((0.68 + 0.30 * block_flash + 0.15 * activation_flash) * maxf(shield_morph, block_flash) * flicker, 0.0, 1.0)
		shield_hull_border.default_color = Color(border_gray, border_gray, border_gray, border_alpha)
		shield_hull_border.width = 3.8 + 2.2 * block_flash + 1.0 * activation_flash

	var palm_verts: PackedVector2Array = PackedVector2Array()
	palm_verts.resize(PALM_POLYGON_INDICES.size())
	for i: int in range(PALM_POLYGON_INDICES.size()):
		palm_verts[i] = screen_pts[PALM_POLYGON_INDICES[i]]
	palm_polygon.polygon = palm_verts

	var base_palm_gray: float = 0.12 if (is_exhausted and is_fist_held) else lerpf(0.18, 0.40, pulse)
	var shield_palm_gray: float = clampf((0.56 + 0.22 * energy_ratio + 0.22 * block_flash) * flicker, 0.0, 1.0)
	var palm_gray: float = lerpf(base_palm_gray, shield_palm_gray, shield_morph)
	var palm_alpha: float = lerpf(0.42, 0.68 + 0.18 * block_flash, shield_morph)
	palm_polygon.color = Color(palm_gray, palm_gray, palm_gray, palm_alpha)
	palm_polygon.light_mask = 0 if shield_morph > 0.25 else 2

	_set_bone_points(thumb_bone, screen_pts, THUMB_BONE_INDICES)
	_set_bone_points(index_bone, screen_pts, INDEX_BONE_INDICES)
	_set_bone_points(middle_bone, screen_pts, MIDDLE_BONE_INDICES)
	_set_bone_points(ring_bone, screen_pts, RING_BONE_INDICES)
	_set_bone_points(pinky_bone, screen_pts, PINKY_BONE_INDICES)
	_set_bone_points(palm_bridge_bone, screen_pts, PALM_BRIDGE_INDICES)

	var base_bone_gray: float = 0.24 if (is_exhausted and is_fist_held) else lerpf(0.38, 0.78, pulse)
	var shield_bone_gray: float = clampf((0.86 + 0.14 * energy_ratio + 0.15 * block_flash) * flicker, 0.0, 1.0)
	var bone_gray: float = lerpf(base_bone_gray, shield_bone_gray, shield_morph)
	var bone_alpha: float = lerpf(0.68, 0.94, shield_morph)
	var bone_width: float = lerpf(3.0, 5.0 + 1.8 * block_flash, shield_morph)
	var active_light_mask: int = 0 if shield_morph > 0.25 else 2

	for bone_line: Line2D in [thumb_bone, index_bone, middle_bone, ring_bone, pinky_bone]:
		bone_line.default_color = Color(bone_gray, bone_gray, bone_gray, bone_alpha)
		bone_line.width = bone_width
		bone_line.light_mask = active_light_mask

	var bridge_gray: float = lerpf(0.28, shield_bone_gray * 0.92, shield_morph)
	palm_bridge_bone.default_color = Color(bridge_gray, bridge_gray, bridge_gray, lerpf(0.55, 0.88, shield_morph))
	palm_bridge_bone.width = lerpf(2.0, 3.8 + 1.2 * block_flash, shield_morph)
	palm_bridge_bone.light_mask = active_light_mask

	var tip_nodes: Array[Polygon2D] = [fingertip_4, fingertip_8, fingertip_12, fingertip_16, fingertip_20]
	var tip_boost: float = maxf(shield_morph, maxf(pulse, 0.5 if is_fist_held else 0.0))
	var tip_gray: float = 0.42 if (is_exhausted and is_fist_held and shield_morph <= 0.05) else lerpf(0.76, 1.0, tip_boost)
	var tip_scale: float = 1.0 + maxf(0.45 * pulse, 0.42 * shield_morph + 0.25 * block_flash)
	for i: int in range(FINGERTIP_INDICES.size()):
		var tip_node: Polygon2D = tip_nodes[i]
		tip_node.position = screen_pts[FINGERTIP_INDICES[i]]
		tip_node.color = Color(tip_gray, tip_gray, tip_gray, lerpf(0.88, 1.0, shield_morph))
		tip_node.scale = Vector2(tip_scale, tip_scale)
		tip_node.light_mask = active_light_mask


func _build_shield_landmarks(center: Vector2, r: float, s: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(21)

	# Bottom point of the crest shield (wrist #0)
	pts[0] = center + Vector2(0.0, r * 0.98)

	# Inner crest core (#1, #5, #9, #13, #17)
	pts[1] = center + Vector2(s * r * 0.52, r * 0.14)
	pts[5] = center + Vector2(s * r * 0.44, -r * 0.44)
	pts[9] = center + Vector2(0.0, -r * 0.58)
	pts[13] = center + Vector2(-s * r * 0.44, -r * 0.44)
	pts[17] = center + Vector2(-s * r * 0.52, r * 0.14)

	# Thumb flank & shoulder corner (#2, #3, #4)
	pts[2] = center + Vector2(s * r * 0.56, r * 0.58)
	pts[3] = center + Vector2(s * r * 0.86, r * 0.10)
	pts[4] = center + Vector2(s * r * 0.96, -r * 0.42)

	# Index rib & top-left crown peak (#6, #7, #8)
	pts[6] = center + Vector2(s * r * 0.96, -r * 0.42)
	pts[7] = center + Vector2(s * r * 0.50, -r * 0.68)
	pts[8] = center + Vector2(s * r * 0.56, -r * 0.96)

	# Middle spine & top-center apex (#10, #11, #12)
	pts[10] = center + Vector2(0.0, -r * 0.20)
	pts[11] = center + Vector2(0.0, -r * 0.78)
	pts[12] = center + Vector2(0.0, -r * 1.05)

	# Ring rib & top-right crown peak (#14, #15, #16)
	pts[14] = center + Vector2(-s * r * 0.96, -r * 0.42)
	pts[15] = center + Vector2(-s * r * 0.50, -r * 0.68)
	pts[16] = center + Vector2(-s * r * 0.56, -r * 0.96)

	# Pinky flank & shoulder corner (#18, #19, #20)
	pts[18] = center + Vector2(-s * r * 0.56, r * 0.58)
	pts[19] = center + Vector2(-s * r * 0.86, r * 0.10)
	pts[20] = center + Vector2(-s * r * 0.96, -r * 0.42)

	return pts


func _set_bone_points(line: Line2D, screen_pts: PackedVector2Array, indices: Array[int]) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(indices.size())
	for i: int in range(indices.size()):
		pts[i] = screen_pts[indices[i]]
	line.points = pts
