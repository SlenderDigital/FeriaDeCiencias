extends Node2D

const PALM_POLYGON_INDICES: Array[int] = [0, 1, 5, 9, 13, 17]
const THUMB_BONE_INDICES: Array[int] = [0, 1, 2, 3, 4]
const INDEX_BONE_INDICES: Array[int] = [0, 5, 6, 7, 8]
const MIDDLE_BONE_INDICES: Array[int] = [0, 9, 10, 11, 12]
const RING_BONE_INDICES: Array[int] = [0, 13, 14, 15, 16]
const PINKY_BONE_INDICES: Array[int] = [0, 17, 18, 19, 20]
const PALM_BRIDGE_INDICES: Array[int] = [1, 5, 9, 13, 17, 0]
const FINGERTIP_INDICES: Array[int] = [4, 8, 12, 16, 20]

var alpha: float = 0.0
var pulse: float = 0.0

var _last_landmarks_2d: PackedVector2Array = PackedVector2Array()
var _last_revision: int = -1
var _last_fist: bool = false
var _last_pulse_bucket: int = -1
var _geometry_dirty: bool = true

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


func update_from_tracker(tracker: Node, delta: float, arena_size: Vector2) -> void:
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
		return

	var pulse_bucket: int = int(pulse * 20.0)
	var dirty: bool = _geometry_dirty or is_fist_held != _last_fist or pulse_bucket != _last_pulse_bucket
	_last_fist = is_fist_held
	if not dirty:
		return
	_last_pulse_bucket = pulse_bucket
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

	var contract_factor: float = clampf(pulse * 0.25 + (0.12 if is_fist_held else 0.0), 0.0, 0.35)
	if contract_factor > 0.0:
		for tip_idx: int in FINGERTIP_INDICES:
			screen_pts[tip_idx] = screen_pts[tip_idx].lerp(palm_center_screen, contract_factor)

	var palm_verts: PackedVector2Array = PackedVector2Array()
	palm_verts.resize(PALM_POLYGON_INDICES.size())
	for i: int in range(PALM_POLYGON_INDICES.size()):
		palm_verts[i] = screen_pts[PALM_POLYGON_INDICES[i]]
	palm_polygon.polygon = palm_verts
	var palm_gray: float = lerpf(0.18, 0.40, pulse)
	palm_polygon.color = Color(palm_gray, palm_gray, palm_gray, 0.42)

	_set_bone_points(thumb_bone, screen_pts, THUMB_BONE_INDICES)
	_set_bone_points(index_bone, screen_pts, INDEX_BONE_INDICES)
	_set_bone_points(middle_bone, screen_pts, MIDDLE_BONE_INDICES)
	_set_bone_points(ring_bone, screen_pts, RING_BONE_INDICES)
	_set_bone_points(pinky_bone, screen_pts, PINKY_BONE_INDICES)
	_set_bone_points(palm_bridge_bone, screen_pts, PALM_BRIDGE_INDICES)

	var bone_gray: float = lerpf(0.38, 0.78, pulse)
	for bone_line: Line2D in [thumb_bone, index_bone, middle_bone, ring_bone, pinky_bone]:
		bone_line.default_color = Color(bone_gray, bone_gray, bone_gray, 0.68)

	var tip_nodes: Array[Polygon2D] = [fingertip_4, fingertip_8, fingertip_12, fingertip_16, fingertip_20]
	var tip_gray: float = lerpf(0.76, 1.0, maxf(pulse, 0.5 if is_fist_held else 0.0))
	var tip_scale: float = 1.0 + 0.45 * pulse
	for i: int in range(FINGERTIP_INDICES.size()):
		var tip_node: Polygon2D = tip_nodes[i]
		tip_node.position = screen_pts[FINGERTIP_INDICES[i]]
		tip_node.color = Color(tip_gray, tip_gray, tip_gray, 0.88)
		tip_node.scale = Vector2(tip_scale, tip_scale)


func _set_bone_points(line: Line2D, screen_pts: PackedVector2Array, indices: Array[int]) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(indices.size())
	for i: int in range(indices.size()):
		pts[i] = screen_pts[indices[i]]
	line.points = pts
