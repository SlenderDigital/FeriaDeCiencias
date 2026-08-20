extends Control
## PatchCable — Animated patch cable from clock source to selected module's GATE jack.
## Draws a curved bezier with flowing dash pattern on beat.

var from_pos: Vector2 = Vector2.ZERO
var to_pos: Vector2 = Vector2.ZERO
var dash_offset: float = 0.0
var is_seated: bool = false
var seat_progress: float = 0.0

signal cable_seated

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false

func show_cable(from: Vector2, to: Vector2, animate: bool = true) -> void:
	from_pos = from
	to_pos = to
	visible = true
	if animate:
		is_seated = false
		seat_progress = 0.0
	else:
		is_seated = true
		seat_progress = 1.0

func hide_cable() -> void:
	visible = false
	is_seated = false
	seat_progress = 0.0

func _process(delta: float) -> void:
	if not visible:
		return
	
	# Animate seating
	if not is_seated:
		seat_progress += delta * 3.0
		if seat_progress >= 1.0:
			seat_progress = 1.0
			is_seated = true
			cable_seated.emit()
	
	# Animate dash flow (voltage moving)
	dash_offset += delta * 120.0
	if dash_offset > 100.0:
		dash_offset = 0.0
	
	queue_redraw()

func _draw() -> void:
	if from_pos == Vector2.ZERO and to_pos == Vector2.ZERO:
		return
	
	# Compute bezier curve
	var ctrl_offset = abs(to_pos.x - from_pos.x) * 0.4
	var ctrl1 = from_pos + Vector2(ctrl_offset, 0)
	var ctrl2 = to_pos - Vector2(ctrl_offset, 0)
	
	# Color
	var col = Color(0.55, 0.9, 0.15, 1.0)  # signal green
	if not is_seated:
		col.a = 0.5
	
	# Draw bezier
	var points = PackedVector2Array()
	for i in range(21):
		var t = float(i) / 20.0
		var pt = _cubic_bezier(from_pos, ctrl1, ctrl2, to_pos, t)
		points.append(pt)
	
	# Draw cable body
	draw_polyline(points, col, 3.0)
	
	# Draw voltage dash flow (only when seated)
	if is_seated:
		_draw_dash_flow(points, col)
	
	# Draw jack connectors at ends
	_draw_jack_connector(from_pos, true)
	_draw_jack_connector(to_pos, false)

func _cubic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u = 1.0 - t
	var tt = t * t
	var uu = u * u
	var uuu = uu * u
	var ttt = tt * t
	return p0 * uuu + p1 * (3.0 * uu * t) + p2 * (3.0 * u * tt) + p3 * ttt

func _draw_dash_flow(points: PackedVector2Array, col: Color) -> void:
	# Compute total length
	var total_len: float = 0.0
	for i in range(points.size() - 1):
		total_len += points[i].distance_to(points[i + 1])
	
	if total_len < 10.0:
		return
	
	var dash_len = 16.0
	var gap_len = 12.0
	var period = dash_len + gap_len
	var start_offset = fmod(dash_offset, period)
	
	var dist = -start_offset
	var draw_dash = false
	
	for i in range(points.size() - 1):
		var a = points[i]
		var b = points[i + 1]
		var seg_len = a.distance_to(b)
		var dir = (b - a).normalized()
		
		while dist < seg_len:
			if dist < 0.0:
				dist += period
				draw_dash = not draw_dash
				continue
			
			if draw_dash:
				var dash_end = min(dist + dash_len, seg_len)
				var p1 = a + dir * max(0.0, dist)
				var p2 = a + dir * dash_end
				draw_line(p1, p2, Color(col.r, col.g, col.b, 0.9), 4.0)
				dist = dash_end
			else:
				dist += gap_len
			
			if dist >= seg_len:
				dist -= seg_len
				draw_dash = not draw_dash

func _draw_jack_connector(pos: Vector2, is_source: bool) -> void:
	var r = 8.0
	var col = Color(0.55, 0.9, 0.15, 1.0)
	if not is_seated:
		col.a = 0.5
	
	draw_circle(pos, r, col)
	draw_circle(pos, r * 0.6, Color(0.08, 0.08, 0.12, 1.0))
	draw_circle(pos, r * 0.85, Color(0.4, 0.4, 0.5, 1.0))