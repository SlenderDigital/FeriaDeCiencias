class_name PatternController
extends RefCounted
## PatternController — Spawnea patrones rítmicos basados en el chart y level_chart.
## Usa downbeat/bars/phrases del análisis para coreografiar.

var chart: ChartData
var wall_active: bool = false   # lo setea Gameplay: hay un muro en pantalla
# Tamaño del área de juego real (lo setea Gameplay desde el viewport).
# Afecta lanes, centros y gaps: con esto la mano alcanza TODA la pantalla.
var play_size: Vector2 = Vector2(1280, 720)
# --- Nivel determinista: mismo track -> mismo nivel, siempre ---
# El azar global (randf/randi) se reemplaza por un RNG con seed derivada
# del id del track, y la coreografía de muros se deduce del número de
# compás (beat_idx / 4): el nivel sale de la canción, no del azar.
var bpm: float = 120.0
var beat_len: float = 0.5          # 60 / bpm
var _rng := RandomNumberGenerator.new()
var _last_wall_dir: Vector2 = Vector2.ZERO  # anti-repetición de dirección
var _last_wall_t: float = -100.0   # t del ultimo muro emitido (cooldown)
# Rojo de peligro: TODO lo que daña es rojo, sin excepciones. El color del
# track queda para la nave/HUD/ambiente; rojo = no lo toques.
const DANGER_RED: Color = Color(1.0, 0.2, 0.3, 1.0)

func _init(c: ChartData, size: Vector2 = Vector2(1280, 720), p_bpm: float = 120.0, seed_val: int = 0) -> void:
	chart = c
	play_size = size
	bpm = p_bpm
	beat_len = 60.0 / maxf(bpm, 1.0)
	_rng.seed = seed_val

## Elección determinista de un elemento del pool con el RNG del track.
func _pick(arr: Array):
	return arr[_rng.randi_range(0, arr.size() - 1)]

## Posición x en grilla de carriles: u∈[0,1] -> x dentro del ancho real,
## con márgenes del 9% a cada lado (misma envolvente de spawns de siempre).
func _lane_x(u: float) -> float:
	return play_size.x * (0.09 + 0.82 * clampf(u, 0.0, 1.0))

func spawns_at(t: float, beat_idx: int, base_color: Color) -> Array[Dictionary]:
	var sec := _current_section(t)
	if sec.is_empty():
		return []
	var out: Array[Dictionary] = []
	var energy: float = float(sec.get("energy", 0.5))
	var density: float = float(sec.get("density", 0.5))
	var pool: Array = sec.get("pattern_pool", ["saw"])
	var bp: int = beat_idx % 4

	# --- Base: el patrón principal del beat, del pool de la sección ---
	# Determinista: el "azar" sale del RNG semillado por track (misma canción
	# -> misma secuencia de patrones, siempre).
	if not pool.is_empty() and _rng.randf() <= density:
		var pattern: String = _pick(pool)
		for s in _build_pattern(pattern, t, base_color, beat_idx):
			out.append(s)

	# --- Acentos musicales (la dificultad sigue a la batería) ---
	# Mientras un muro esta en pantalla, se silencian los rojos de acento:
	# el pasillo del hueco debe quedar limpio para reaccionar
	if not wall_active:
		# Hits de snare (beats 2 y 4) => sierra acento en secciones con drive
		if (bp == 1 or bp == 3) and energy >= 0.55 and _rng.randf() <= 0.6:
			out.append(_saw(_rng.randf_range(play_size.x * 0.15, play_size.x * 0.85), Color(1, 0.2, 0.3, 1)))

	return out

# --- NUEVO: Usar downbeat/bars/phrases para coreografiar ---
func spawns_at_downbeat(t: float, beat_idx: int, base_color: Color) -> Array[Dictionary]:
	"""Llamado en cada downbeat (cada 4 beats) — patrones grandes."""
	if not chart.downbeat[beat_idx]:
		return []
	# Las secciones tranquilas no lanzan muros: la energía manda la dificultad
	var sec := _current_section(t)
	if not sec.is_empty() and float(sec.get("energy", 0.5)) < 0.45:
		return []
	return _build_pattern("stripe_wall", t, Color(1, 0.2, 0.3, 1), beat_idx)

func spawns_at_bar(t: float, beat_idx: int, base_color: Color) -> Array[Dictionary]:
	"""Llamado en cada bar (cada 4 beats) — variaciones coreografiadas."""
	if beat_idx % 4 != 0:
		return []
	# Mientras hay muro, la barra es el muro: no apilar mas rojos
	if wall_active:
		return []
	var sec := _current_section(t)
	var energy: float = 0.5
	if not sec.is_empty():
		energy = float(sec.get("energy", 0.5))
	var pattern: String = "saw"
	if energy < 0.55:
		pattern = "saw"
	elif energy < 0.75:
		pattern = _pick(["saw", "drifter_swarm"])
	else:
		pattern = _pick(["saw", "drifter_swarm", "homing", "hazard_wall"])
	return _build_pattern(pattern, 0, base_color, beat_idx)

func spawns_at_phrase(t: float, beat_idx: int, base_color: Color) -> Array[Dictionary]:
	"""Llamado en cada phrase (cada 16 beats) — setpieces / nuevo mech."""
	if beat_idx % 16 != 0:
		return []
	# Los setpieces solo aparecen cuando la música lo pide (no en el intro)
	var sec := _current_section(t)
	if not sec.is_empty() and float(sec.get("energy", 0.5)) < 0.5:
		return []
	# Setpiece especial: closing perimeter o laser telegraph
	var pattern: String = _pick(["closing_perimeter", "laser_telegraph"])
	return _build_pattern(pattern, 0, Color(1, 0.2, 0.3, 1), beat_idx)

func _current_section(t: float) -> Dictionary:
	for s in chart.level_sections:
		var start: float = float(s.get("start", 0.0))
		var end: float = float(s.get("end", 1e9))
		if t >= start and t < end:
			return s
	return {}

func _build_pattern(pattern: String, t: float, base: Color, beat_idx: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match pattern:
		"hazard_wall":
			out.append(_hazard(_lane_x(fposmod((beat_idx / 4) * 0.5, 1.0))))
		# --- NUEVOS PATRONES ---
		"stripe_wall":
			# Muro con UN hueco pasable, coreografiado por la MÚSICA:
			# - Dirección: rotación fija por compás (bar_idx), alterna lados
			#   (call & response), sin azar.
			# - Hueco: snapeado a la grilla de carriles tangencial (los mismos
			#   carriles donde viajan los targets).
			# - Ciclo: 2 beats warning -> 2 beats active -> 1/2 beat fade.
			#   El muro nace en un downbeat y libera el gate justo antes del
			#   siguiente compás.
			var dirs := [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
			# Coreografia por compas (bar_idx), sin azar: eje por fase de 4 en
			# compases pares; compas impar = mismo eje inclinado (diagonal).
			var bar_idx: int = beat_idx / 4
			# Inclinacion de compas impar: mismo eje rotado 45 grados, con signo
			# alterno por bar (bar 1: -45, bar 3: +45, bar 5: -45...): zigzag
			# visible sin azar, solo coreografia.
			var tilt_sign: float = -1.0 if bar_idx % 4 == 1 else (1.0 if bar_idx % 4 == 3 else 0.0)
			var ni: int = int(bar_idx / 2) % 4
			var tilted: bool = (bar_idx % 2 == 1)
			if _last_wall_dir != Vector2.ZERO and ni == 3:
				# Alterna el lado: excluye la dirección previa (rotación no
				# degenerada; la dirección repetida se pospone, no se azariza).
				var idx: int = (ni + 1) % 4
				if dirs[idx].is_equal_approx(_last_wall_dir):
					idx = (idx + 1) % 4
				ni = idx
			var n: Vector2 = dirs[ni]
			if tilted:
				# Compas impar: el eje gira 45 grados a izquierda/derecha segun el
				# signo del compas (zigzag determinista).
				n = dirs[ni].rotated(tilt_sign * deg_to_rad(45.0)).normalized()
			_last_wall_dir = n
			var t_dir := Vector2(-n.y, n.x)
			var corners := [Vector2.ZERO, Vector2(play_size.x, 0), Vector2(0, play_size.y), play_size]
			var smin := INF
			var smax := -INF
			var tmin := INF
			var tmax := -INF
			for cn: Vector2 in corners:
				var sv: float = cn.dot(n)
				var tv: float = cn.dot(t_dir)
				smin = minf(smin, sv)
				smax = maxf(smax, sv)
				tmin = minf(tmin, tv)
				tmax = maxf(tmax, tv)
			# Hueco alineado a carriles: la grilla vive en el eje de AVANCE (s),
			# con el mismo spacing que los carriles de targets (~1/10 del area).
			# El pasillo cae siempre sobre un carril de la misma grilla virtual.
			var span_len: float = smax - smin
			var lane_spacing: float = maxf(110.0, span_len / 10.0)
			var usable: float = span_len - 360.0
			var gap_i: int = (bar_idx * 3 + 1) % maxi(int(usable / lane_spacing), 1)
			var gap_center: float = smin + 180.0 + gap_i * lane_spacing
			gap_center = minf(gap_center, smax - 180.0)
			var gap_half := 90.0
			var dir_name := "down"
			if n.distance_squared_to(Vector2(0, 1)) < 0.01: dir_name = "down"
			elif n.distance_squared_to(Vector2(0, -1)) < 0.01: dir_name = "up"
			elif n.distance_squared_to(Vector2(1, 0)) < 0.01: dir_name = "right"
			elif n.distance_squared_to(Vector2(-1, 0)) < 0.01: dir_name = "left"
			elif tilted: dir_name = "diag" + ("L" if tilt_sign < 0.0 else "R")
			print("[WALL] spawn t=%.2f bar=%d dir=%s lane=%d gap_center=%.0f (smin=%.0f smax=%.0f)" % [t, bar_idx, dir_name, gap_i, gap_center, smin, smax])
			# Guard anti-doble-muro (punto UNICO de emision): cualquier ruta
			# (downbeat o pool de patrones) pasa por aca. Cooldown de 3 beats:
			# la musica manda el ritmo de muros, sin dobles a medio compas.
			if t - _last_wall_t >= 3.0 * beat_len:
				_last_wall_t = t
				out.append(_stripe_band(n, t_dir, tmin, tmax, smin, gap_center - gap_half, gap_center, DANGER_RED, bar_idx, gap_i))
				out.append(_stripe_band(n, t_dir, tmin, tmax, gap_center + gap_half, smax, gap_center, DANGER_RED, bar_idx, gap_i))
		"saw":
			var x = _rng.randf_range(play_size.x * 0.15, play_size.x * 0.85)
			out.append(_saw(x, DANGER_RED))
		"drifter_swarm":
			for i in range(5):
				var x = _rng.randf_range(play_size.x * 0.08, play_size.x * 0.92)
				out.append(_drifter(x, DANGER_RED))
		"laser_telegraph":
			var x = _rng.randf_range(play_size.x * 0.15, play_size.x * 0.85)
			out.append(_laser_telegraph(x))
		"homing":
			var x = _rng.randf_range(play_size.x * 0.15, play_size.x * 0.85)
			out.append(_homing(x, DANGER_RED))
		"closing_perimeter":
			# Círculo de spiked balls que se cierra
			for i in range(12):
				var angle = TAU * i / 12.0
				out.append(_perimeter_ball(play_size.x * 0.5, play_size.y * 0.5, angle))
		_:
			push_warning("PatternController: unknown pattern '%s'" % pattern)
			return []
	return out

# --- Helpers para nuevos patrones ---
func _hazard(x: float) -> Dictionary:
	return {"pos": Vector2(x, -30.0), "vel": Vector2(0, 200.0),
		"radius": _rng.randf_range(24, 32), "color": Color(1.0, 0.2, 0.3, 1.0), "is_hazard": true, "hit_health_bonus": -25.0, "type": "hazard"}

func _stripe_band(n: Vector2, t_dir: Vector2, tmin: float, tmax: float, s0: float, s1: float, gap_center: float, c: Color, bar_idx: int = 0, gap_i: int = 0) -> Dictionary:
	# Banda de muro orientada: cubre s ∈ [s0, s1] en el eje n (avance) y el
	# ancho completo de pantalla en el eje tangente t_dir. El render y la
	# colisión usan s0/s1 (proyecciones) + rot para dibujar el rect girado.
	var s_mid := (s0 + s1) * 0.5
	var t_mid := (tmin + tmax) * 0.5
	var center := t_dir * t_mid + n * s_mid
	return {
		"pos": center, "type": "stripe_wall", "is_hazard": true,
		"hit_health_bonus": -20.0, "color": c,
		"wall_n": n, "wall_t": t_dir,
		"s0": s0, "s1": s1,
		"size": Vector2(tmax - tmin, s1 - s0),
		"rot": t_dir.angle(),
		"gap_center": gap_center,
		"state": "warning", "warn_time": 2.0 * beat_len, "active_time": 2.0 * beat_len, "fade_time": 0.5 * beat_len,
		"bar_idx": bar_idx, "lane_index": gap_i,
		"alpha": 1.0}

func _saw(x: float, c: Color) -> Dictionary:
	return {"pos": Vector2(x, -50.0), "vel": Vector2(_rng.randf_range(-50, 50), 120.0),
		"radius": 30, "color": c, "is_hazard": true, "hit_health_bonus": -30.0, "type": "saw"}

func _drifter(x: float, c: Color) -> Dictionary:
	# Anillo con púas que deriva y rota
	return {"pos": Vector2(x, -30.0), "vel": Vector2(_rng.randf_range(-40, 40), 80.0),
		"radius": 28, "color": c, "is_hazard": true, "hit_health_bonus": -25.0, "type": "drifter"}

func _laser_telegraph(x: float) -> Dictionary:
	# Telegraph de 1.3s (~2+ beats) -> dispara un beam en DIRECCIÓN ALEATORIA.
	# Al tocar alarma sonora: el jugador SIEMPRE escucha el aviso.
	# (Gameplay dispara el sonido al recibir el spawn; aquí no tocamos
	# autoloads para que el E2E headless compile sin escena.)
	var dir := Vector2.from_angle(_rng.randf() * TAU)
	var anchor := Vector2(x, _rng.randf_range(play_size.y * 0.19, play_size.y * 0.81))
	print("[LASER] telegraph spawn anchor=%s dir_angle=%.1f°" % [anchor, rad_to_deg(dir.angle())])
	return {"pos": anchor, "vel": Vector2(0, 0),
		"radius": 12, "color": Color(1, 0.8, 0, 1), "is_hazard": false,
		"type": "laser_telegraph", "telegraph_time": 1.3, "telegraph_total": 1.3,
		"fired": false, "beam_dir": dir}

func _homing(x: float, c: Color) -> Dictionary:
	# Proyectil teledirigido: persigue al jugador (Gameplay maneja el chase).
	return {"pos": Vector2(x, -30.0), "vel": Vector2(0, 250.0),
		"radius": 20, "color": c, "is_hazard": true, "hit_health_bonus": -20.0, "type": "homing"}

func _perimeter_ball(cx: float, cy: float, angle: float) -> Dictionary:
	var dir = Vector2(cos(angle), sin(angle))
	return {"pos": Vector2(cx, cy) + dir * 500, "vel": -dir * 100.0,
		"radius": 40, "color": Color(1, 0.2, 0.3, 1), "is_hazard": true, "hit_health_bonus": -40.0, "type": "perimeter"}

