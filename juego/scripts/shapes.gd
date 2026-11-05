class_name Shapes
extends RefCounted


static func rect(size: Vector2) -> PackedVector2Array:
	var half: Vector2 = size * 0.5
	return PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])


static func diamond(radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(radius, 0.0),
		Vector2(0.0, -radius),
		Vector2(-radius, 0.0),
		Vector2(0.0, radius),
	])


static func circle(radius: float, segments: int = 24, angle_offset: float = 0.0) -> PackedVector2Array:
	var count: int = maxi(segments, 3)
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(count)
	for i: int in range(count):
		pts[i] = Vector2.from_angle(angle_offset + TAU * float(i) / float(count)) * radius
	return pts


static func annulus(inner_radius: float, outer_radius: float, segments: int = 32) -> PackedVector2Array:
	if inner_radius <= 0.5:
		return circle(outer_radius, segments)
	var count: int = maxi(segments, 6)
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in range(count + 1):
		pts.append(Vector2.from_angle(TAU * float(i) / float(count)) * outer_radius)
	for i: int in range(count, -1, -1):
		pts.append(Vector2.from_angle(TAU * float(i) / float(count)) * inner_radius)
	return pts


static func sector(radius: float, sweep_angle: float, segments: int = 32) -> PackedVector2Array:
	if sweep_angle <= 0.02:
		return PackedVector2Array([Vector2.ZERO, Vector2(radius, 0.0), Vector2.from_angle(0.02) * radius])
	if sweep_angle >= TAU - 0.001:
		return circle(radius, segments)
	var count: int = maxi(int(ceil(float(segments) * (sweep_angle / TAU))), 2)
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2.ZERO)
	for i: int in range(count + 1):
		var angle: float = -PI * 0.5 + (sweep_angle * float(i)) / float(count)
		pts.append(Vector2.from_angle(angle) * radius)
	return pts


static func star(outer_r: float, inner_r: float, points_count: int) -> PackedVector2Array:
	var total: int = maxi(points_count * 2, 6)
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(total)
	for i: int in range(total):
		var r: float = outer_r if i % 2 == 0 else inner_r
		pts[i] = Vector2.from_angle(TAU * float(i) / float(total)) * r
	return pts


static func saw(radius: float, teeth: int = 16, inner_ratio: float = 0.70) -> PackedVector2Array:
	var total: int = maxi(teeth * 2, 8)
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(total)
	for i: int in range(total):
		var cant: float = -0.045 if i % 2 == 0 else 0.03
		var r: float = radius if i % 2 == 0 else radius * inner_ratio
		pts[i] = Vector2.from_angle(TAU * float(i) / float(total) + cant) * r
	return pts


static func swept_triangle(radius: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(radius * 1.12, 0.0),
		Vector2(-radius * 0.76, -radius * 0.88),
		Vector2(-radius * 0.38, -radius * 0.26),
		Vector2(-radius * 0.68, 0.0),
		Vector2(-radius * 0.38, radius * 0.26),
		Vector2(-radius * 0.76, radius * 0.88),
	])


static func projectile(radius: float) -> PackedVector2Array:
	var count: int = 12
	var pts: PackedVector2Array = PackedVector2Array()
	pts.resize(count)
	for i: int in range(count):
		var dir_vec: Vector2 = Vector2.from_angle(TAU * float(i) / float(count))
		var x_scale: float = 1.28 if dir_vec.x >= 0.0 else 1.45
		pts[i] = Vector2(dir_vec.x * radius * x_scale, dir_vec.y * radius * 0.86)
	return pts
