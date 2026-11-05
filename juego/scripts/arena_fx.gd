extends Node2D

const DEFAULT_SHARD_COLOR: Color = Color(0.92, 0.92, 0.92, 1.0)

var _shards: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_process(false)


func spawn_burst(
	origin: Vector2,
	count: int = 10,
	speed: float = 260.0,
	shard_color: Color = DEFAULT_SHARD_COLOR,
	duration: float = 0.38,
	shard_length: float = 9.0,
	width: float = 2.0
) -> void:
	spawn_directional_burst(origin, Vector2.RIGHT, PI, count, speed, shard_color, duration, shard_length, width)


func spawn_directional_burst(
	origin: Vector2,
	direction: Vector2,
	spread_radians: float = 0.85,
	count: int = 8,
	speed: float = 240.0,
	shard_color: Color = DEFAULT_SHARD_COLOR,
	duration: float = 0.30,
	shard_length: float = 8.5,
	width: float = 2.0
) -> void:
	if count <= 0:
		return
	var base_angle: float = direction.angle() if direction.length_squared() > 0.001 else 0.0
	for i: int in range(mini(count, 40)):
		var angle: float = base_angle + _rng.randf_range(-spread_radians, spread_radians)
		var shard_speed: float = speed * _rng.randf_range(0.55, 1.25)
		_shards.append({
			"pos": origin,
			"vel": Vector2.from_angle(angle) * shard_speed,
			"life": duration * _rng.randf_range(0.75, 1.15),
			"max_life": duration,
			"length": shard_length * _rng.randf_range(0.7, 1.25),
			"color": shard_color,
			"width": width,
		})
	set_process(true)
	queue_redraw()


func spawn_ring(
	origin: Vector2,
	start_radius: float = 8.0,
	end_radius: float = 70.0,
	duration: float = 0.42,
	ring_color: Color = DEFAULT_SHARD_COLOR,
	width: float = 2.0
) -> void:
	_rings.append({
		"pos": origin,
		"start_radius": start_radius,
		"end_radius": end_radius,
		"life": duration,
		"max_life": duration,
		"color": ring_color,
		"width": width,
	})
	set_process(true)
	queue_redraw()


func clear() -> void:
	_shards.clear()
	_rings.clear()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	for i: int in range(_shards.size() - 1, -1, -1):
		var s: Dictionary = _shards[i]
		s["life"] = float(s["life"]) - delta
		if float(s["life"]) <= 0.0:
			_shards.remove_at(i)
			continue
		s["pos"] = Vector2(s["pos"]) + Vector2(s["vel"]) * delta
		s["vel"] = Vector2(s["vel"]) * (1.0 - minf(3.2 * delta, 0.9))

	for i: int in range(_rings.size() - 1, -1, -1):
		_rings[i]["life"] = float(_rings[i]["life"]) - delta
		if float(_rings[i]["life"]) <= 0.0:
			_rings.remove_at(i)

	queue_redraw()
	if _shards.is_empty() and _rings.is_empty():
		set_process(false)


func _draw() -> void:
	for shard: Dictionary in _shards:
		var alpha: float = clampf(float(shard["life"]) / maxf(float(shard["max_life"]), 0.001), 0.0, 1.0)
		var col: Color = shard["color"]
		col.a *= alpha
		var pos: Vector2 = shard["pos"]
		var vel: Vector2 = shard["vel"]
		var dir: Vector2 = vel.normalized() if vel.length_squared() > 0.001 else Vector2.RIGHT
		draw_line(pos, pos - dir * float(shard["length"]), col, float(shard["width"]), true)

	for ring: Dictionary in _rings:
		var progress: float = 1.0 - clampf(float(ring["life"]) / maxf(float(ring["max_life"]), 0.001), 0.0, 1.0)
		var radius: float = lerpf(float(ring["start_radius"]), float(ring["end_radius"]), ease(progress, 0.35))
		var col: Color = ring["color"]
		col.a *= pow(1.0 - progress, 1.2)
		draw_arc(ring["pos"], radius, 0.0, TAU, 40, col, float(ring["width"]), true)
