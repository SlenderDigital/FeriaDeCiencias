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


static func apply_radial_glow(
	poly: Polygon2D,
	radii: Array[float] = [14.0, 22.0, 32.0, 44.0, 56.0, 68.0, 80.0, 92.0],
	alphas: Array[float] = [0.62, 0.42, 0.25, 0.14, 0.07, 0.03, 0.008, 0.0],
	segments: int = 36,
	center_alpha: float = 0.85
) -> void:
	var verts: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	var colors: PackedColorArray = PackedColorArray([Color(1.0, 1.0, 1.0, center_alpha)])
	for r_idx: int in range(radii.size()):
		var radius: float = radii[r_idx]
		var alpha: float = alphas[r_idx]
		for s: int in range(segments):
			verts.append(Vector2.from_angle(TAU * float(s) / float(segments)) * radius)
			colors.append(Color(1.0, 1.0, 1.0, alpha))
	var polys: Array = []
	for s: int in range(segments):
		polys.append(PackedInt32Array([0, 1 + s, 1 + ((s + 1) % segments)]))
	for r_idx: int in range(radii.size() - 1):
		var inner_start: int = 1 + r_idx * segments
		var outer_start: int = 1 + (r_idx + 1) * segments
		for s: int in range(segments):
			var next_s: int = (s + 1) % segments
			polys.append(PackedInt32Array([
				inner_start + s,
				outer_start + s,
				outer_start + next_s,
				inner_start + next_s,
			]))
	poly.polygon = verts
	poly.polygons = polys
	poly.vertex_colors = colors

