class_name PatternController
extends RefCounted
## Instantiates patterns along the beat grid based on authored level_sections.

var chart: ChartData

func _init(c: ChartData) -> void:
	chart = c

func spawns_at(t: float, base_color: Color) -> Array[Dictionary]:
	var sec := _current_section(t)
	if sec.is_empty():
		return []
	var density: float = float(sec.get("density", 0.5))
	var pool: Array = sec.get("pattern_pool", ["single_target"])
	if pool.is_empty():
		return []
	if randf() > density:
		return []
	var pattern: String = pool[randi() % pool.size()]
	return _build_pattern(pattern, t, base_color)

func _current_section(t: float) -> Dictionary:
	for s in chart.level_sections:
		var start: float = float(s.get("start", 0.0))
		var end: float = float(s.get("end", 1e9))
		if t >= start and t < end:
			return s
	return {}

func _build_pattern(pattern: String, t: float, base: Color) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match pattern:
		"single_target":
			out.append(_target(randf_range(120, 1160), base))
		"double_lane":
			out.append(_target(randf_range(100, 580), base))
			out.append(_target(randf_range(700, 1180), base))
		"hazard_wall":   # red hazard, player must NOT hit
			out.append(_hazard(randf_range(200, 1080)))
		"triple_burst":
			for i in range(3):
				out.append(_target(randf_range(150 + i * 300, 350 + i * 300), base))
		_:
			push_warning("PatternController: unknown pattern '%s'" % pattern)
			return []
	return out

func _target(x: float, c: Color) -> Dictionary:
	return {"pos": Vector2(x, -30.0), "vel": Vector2(randf_range(-30, 30), 180.0),
		"radius": randf_range(18, 26), "color": c, "is_hazard": false, "points": 100}

func _hazard(x: float) -> Dictionary:
	return {"pos": Vector2(x, -30.0), "vel": Vector2(0, 200.0),
		"radius": randf_range(24, 32), "color": Color(1.0, 0.2, 0.3, 1.0), "is_hazard": true, "hit_health_bonus": -25.0}