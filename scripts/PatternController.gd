class_name PatternController
extends RefCounted
## PatternController — Spawnea patrones rítmicos basados en el chart y level_chart.
## Usa downbeat/bars/phrases del análisis para coreografiar.

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

# --- NUEVO: Usar downbeat/bars/phrases para coreografiar ---
func spawns_at_downbeat(t: float, beat_idx: int, base_color: Color) -> Array[Dictionary]:
	"""Llamado en cada downbeat (cada 4 beats) — patrones grandes."""
	if not chart.downbeat[beat_idx]:
		return []
	return _build_pattern("stripe_wall", 0, Color(1, 0.2, 0.3, 1))

func spawns_at_bar(t: float, beat_idx: int, base_color: Color) -> Array[Dictionary]:
	"""Llamado en cada bar (cada 4 beats) — variaciones."""
	if beat_idx % 4 != 0:
		return []
	var pool = ["double_lane", "triple_burst"]
	var pattern = pool[randi() % pool.size()]
	return _build_pattern(pattern, 0, Color(1, 0.2, 0.3, 1))

func spawns_at_phrase(t: float, beat_idx: int, base_color: Color) -> Array[Dictionary]:
	"""Llamado en cada phrase (cada 16 beats) — setpieces / nuevo mech."""
	if beat_idx % 16 != 0:
		return []
	# Setpiece especial: closing perimeter o laser telegraph
	var patterns = ["closing_perimeter", "laser_telegraph"]
	var pattern = patterns[randi() % patterns.size()]
	return _build_pattern(pattern, 0, Color(1, 0.2, 0.3, 1))

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
		"hazard_wall":
			out.append(_hazard(randf_range(200, 1080)))
		"triple_burst":
			for i in range(3):
				out.append(_target(randf_range(150 + i * 300, 350 + i * 300), base))
		# --- NUEVOS PATRONES ---
		"radial_burst":
			for i in range(8):
				var angle = TAU * i / 8.0
				out.append(_target_radial(640, 360, angle, base))
		"stripe_wall":
			# Tres bandas horizontales con hueco central
			for i in range(3):
				var gap_y = 240 + i * 160
				out.append(_stripe_band(gap_y, base))
		"saw":
			var x = randf_range(200, 1080)
			out.append(_saw(x, base))
		"drifter_swarm":
			for i in range(5):
				var x = randf_range(100, 1180)
				out.append(_drifter(x, base))
		"laser_telegraph":
			var x = randf_range(200, 1080)
			out.append(_laser_telegraph(x))
		"homing":
			var x = randf_range(200, 1080)
			out.append(_homing(x, base))
		"closing_perimeter":
			# Círculo de spiked balls que se cierra
			for i in range(12):
				var angle = TAU * i / 12.0
				out.append(_perimeter_ball(640, 360, angle))
		_:
			push_warning("PatternController: unknown pattern '%s'" % pattern)
			return []
	return out

# --- Helpers para nuevos patrones ---
func _target(x: float, c: Color) -> Dictionary:
	return {"pos": Vector2(x, -30.0), "vel": Vector2(randf_range(-30, 30), 180.0),
		"radius": randf_range(18, 26), "color": c, "is_hazard": false, "points": 100, "type": "target"}

func _hazard(x: float) -> Dictionary:
	return {"pos": Vector2(x, -30.0), "vel": Vector2(0, 200.0),
		"radius": randf_range(24, 32), "color": Color(1.0, 0.2, 0.3, 1.0), "is_hazard": true, "hit_health_bonus": -25.0, "type": "hazard"}

func _target_radial(cx: float, cy: float, angle: float, c: Color) -> Dictionary:
	var dir = Vector2(cos(angle), sin(angle))
	return {"pos": Vector2(cx, cy), "vel": dir * 300.0,
		"radius": randf_range(18, 24), "color": c, "is_hazard": false, "points": 150, "type": "target"}

func _stripe_band(gap_y: float, c: Color) -> Dictionary:
	# Banda con franjas diagonales, hueco en gap_y
	return {"pos": Vector2(0, gap_y - 100), "vel": Vector2(0, 150.0),
		"radius": 100, "color": c, "is_hazard": true, "hit_health_bonus": -20.0, "type": "stripe_wall"}

func _saw(x: float, c: Color) -> Dictionary:
	return {"pos": Vector2(x, -50.0), "vel": Vector2(randf_range(-50, 50), 120.0),
		"radius": 30, "color": c, "is_hazard": true, "hit_health_bonus": -30.0, "type": "saw"}

func _drifter(x: float, c: Color) -> Dictionary:
	# Anillo con púas que deriva y rota
	return {"pos": Vector2(x, -30.0), "vel": Vector2(randf_range(-40, 40), 80.0),
		"radius": 28, "color": c, "is_hazard": true, "hit_health_bonus": -25.0, "type": "drifter"}

func _laser_telegraph(x: float) -> Dictionary:
	# Telegraph de 1 beat -> luego dispara
	return {"pos": Vector2(x, 0), "vel": Vector2(0, 0),
		"radius": 12, "color": Color(1, 0.8, 0, 1), "is_hazard": false,
		"type": "laser_telegraph", "telegraph_time": 1.0, "fired": false}

func _homing(x: float, c: Color) -> Dictionary:
	return {"pos": Vector2(x, -30.0), "vel": Vector2(0, 250.0),
		"radius": 20, "color": c, "is_hazard": false, "points": 200, "type": "homing"}

func _perimeter_ball(cx: float, cy: float, angle: float) -> Dictionary:
	var dir = Vector2(cos(angle), sin(angle))
	return {"pos": Vector2(cx, cy) + dir * 500, "vel": -dir * 100.0,
		"radius": 40, "color": Color(1, 0.2, 0.3, 1), "is_hazard": true, "hit_health_bonus": -40.0, "type": "perimeter"}

