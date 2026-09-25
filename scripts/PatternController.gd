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
# easy_mode: First Light usa una timeline propia con encounters claros;
# mantiene velocidad/margen-tutorial, pero si incluye muros, láseres y
# perimeter como breakthroughs didacticos.
var easy_mode: bool = false
var _rng := RandomNumberGenerator.new()
var _last_wall_dir: Vector2 = Vector2.ZERO  # anti-repetición de dirección
var _last_wall_t: float = -100.0   # t del ultimo muro emitido (cooldown)
var _last_wall_end: float = -100.0  # t en que termino el ultimo muro (warn+active)
var _last_gap_u: float = 1.0  # indice del ultimo hueco EMITIDO: el siguiente queda a max 1 carril
## --- SETPIECE DIRECTOR (estilo JSAB, plan 2026-09-24) ---
## Un setpiece = coreografía multi-beat: lista de fases con offset en BEATS
## desde el beat ancla. El phrase beat agenda; cada spawns_at posterior emite
## las fases que vencen. Así un encuentro EVOLUCIONA durante la frase en vez
## de ser un spawn suelto — "algo pasa" en cada frase.
## Fase: {"at": int, "emit": String, "params": Dictionary} — emit es una key
## de _build_pattern o "" (fase marcadora: Task 3 la llena).
const SETPIECE_SCRIPTS: Dictionary = {
	"laser_sweep_v1": [
		{"at": 0, "emit": "laser_telegraph", "params": {}},
		{"at": 3, "emit": "", "params": {"marker": "beam_active"}},
	],
	"sweep_build_v1": [
		{"at": 0, "emit": "laser_sweep", "params": {}},
	],
	## T4: el breakdown abre con el muro de ONDA (la "arena invertida" del
	## video): el espacio se cierra desde abajo y el juego se lee al revés.
	"wave_breakdown_v1": [
		{"at": 0, "emit": "waveform_wall", "params": {}},
	],
	## T2: el drop abre con el abanico de rayos (la "ancla" JSAB) y el láser
	## llega después: dos anclas en la misma frase, lectura escalonada.
	"drop_opener_v1": [
		{"at": 0, "emit": "spoke_fan", "params": {}},
	],
	## T5: el CLÍMAX (drop2) encadena dos anclas en la misma frase: el abanico
	## abre y, 4 beats más tarde, el corredor aprieta el espacio que quedó.
	"climax_squeeze_v1": [
		{"at": 0, "emit": "spoke_fan", "params": {}},
		{"at": 4, "emit": "squeeze_corridor", "params": {}},
	],
	## T6: el outro cierra con los anillos — el espacio se cierra en círculos
	## mientras la música se apaga (el final se siente, no se anuncia).
	"outro_rings_v1": [
		{"at": 0, "emit": "pulse_rings", "params": {}},
	],
	## Fallbacks heredados del setpiece viejo (breakdown los sigue usando).
	"closing_perimeter_v1": [
		{"at": 0, "emit": "closing_perimeter", "params": {}},
	],
}
## Qué script toca por sección (la energía manda; intro/outro no agendan).
const SETPIECE_BY_SECTION: Dictionary = {
	"build": "sweep_build_v1",
	"drop": "drop_opener_v1",
	"drop2": "climax_squeeze_v1",
	"breakdown": "wave_breakdown_v1",
	"outro": "outro_rings_v1",
}
var _active_setpiece: Dictionary = {}   # {script_key, anchor_beat}
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

	# --- DIRECTOR + bomba de fases en UN solo lugar (spawns_at) ---
	# Gameplay llama spawns_at_phrase DESPUÉS de spawns_at dentro del mismo
	# beat, así que agendar ahí perdía la fase 0 del ancla. El director
	# vive entero acá: en phrase beats (mod 16) agenda; en cada beat emite
	# las fases que vencen.
	var director_out: Array[Dictionary] = _director_pump(t, beat_idx, base_color)
	if not director_out.is_empty():
		out.append_array(director_out)

	# --- Base: el patrón principal del beat, del pool de la sección ---
	# Determinista: el "azar" sale del RNG semillado por track (misma canción
	# -> misma secuencia de patrones, siempre).
	# Muro en pantalla: compas limpio. Ni el pool ni el fallback a saw
	# spawnean (las sierras cayendo sobre la banda roja ensucian la
	# lectura). El muro coreografiado sale por spawns_at_downbeat, que
	# tiene su propio camino y no pasa por aca.
	if wall_active:
		return out
	# First Light tiene una coreografia propia: cada compas tiene una intencion
	# diferente en vez de sortear entre el mismo circulo rojo una y otra vez.
	if easy_mode:
		# La CADENCIA sigue a la energía de la sección: intro/outro respiran
		# (1 encuentro cada 2 compases), build/breakdown marcan el compás,
		# drops aprietan. Un solo helper decide — nada de rangos hardcodeados.
		var intent := _section_intent(t)
		var cadence: int = int(intent["bars_per_encounter"])
		# Mientras un SETPIECE vive, ES el encuentro de esas barras: ni
		# encuentros ni acentos se apilan encima (JSAB limpia el campo
		# alrededor de sus anclas para que se lean).
		var setpiece_live: bool = not _active_setpiece.is_empty()
		var on_encounter_beat: bool = not setpiece_live and beat_idx % (4 * cadence) == 0
		# Acentos de snare en drops (beats 2 y 4): el nivel aprieta donde la
		# batería aprieta — solo si no hay coreografía en curso.
		var on_accent_beat: bool = not setpiece_live and bool(intent["accent_beats"]) and (beat_idx % 4 == 1 or beat_idx % 4 == 3)
		if not on_encounter_beat and not on_accent_beat:
			return out   # (las fases del director ya viven en out)
		var spawns_fl: Array[Dictionary] = []
		# Las fases del DIRECTOR viajan con el retorno del easy_mode: el beat
		# ancla (encuentro) no puede descartarlas.
		spawns_fl.append_array(out)
		if on_encounter_beat:
			spawns_fl.append_array(_build_pattern(_first_light_pattern(beat_idx, t), t, base_color, beat_idx))
		if on_accent_beat:
			spawns_fl.append(_saw(_rng.randf_range(play_size.x * 0.15, play_size.x * 0.85), DANGER_RED, t))
		return spawns_fl
	if not pool.is_empty() and _rng.randf() <= density:
		var pattern: String = _pick(pool)
		# Un muro a la vez: si el pool trae stripe_wall/hazard_wall mientras hay
		# uno en pantalla, se salta (el hueco debe quedar limpio y legible).
		if wall_active and (pattern == "stripe_wall" or pattern == "hazard_wall"):
			pattern = "saw"
		for s in _build_pattern(pattern, t, base_color, beat_idx):
			out.append(s)

	# --- Acentos musicales (la dificultad sigue a la batería) ---
	# Mientras un muro esta en pantalla, se silencian los rojos de acento:
	# el pasillo del hueco debe quedar limpio para reaccionar
	if not wall_active:
		# Hits de snare (beats 2 y 4) => sierra acento. En easy_mode no hay sorpresas.
		if not easy_mode and (bp == 1 or bp == 3) and energy >= 0.62 and _rng.randf() <= 0.6:
			out.append(_saw(_rng.randf_range(play_size.x * 0.15, play_size.x * 0.85), Color(1, 0.2, 0.3, 1), t))

	return out

## Timeline de encuentros de First Light — DIRIGIDA POR LA SECCIÓN (T8).
## El nombre/energía de la sección del chart manda; el "compás dentro de la
## sección" elige la variación. Cero rangos de compás absolutos: si la canción
## cambia (drop más corto, breakdown más largo...), el nivel la SIGUE.
## Recibe t para ubicar la sección (beat_idx solo da el compás dentro de ella).
func _first_light_pattern(beat_idx: int, t: float = -1.0) -> String:
	var bar: int = beat_idx / 4
	var sname: String = ""
	if t >= 0.0:
		sname = str(_section_intent(t)["name"])
	# Fallback determinista (sin t): recorre las secciones por compás como
	# están definidas en el chart — sigue siendo estructura, no constantes.
	if sname.is_empty():
		sname = _section_name_of_bar(bar)
	var in_sec: int = bar - _section_start_bar(bar)
	# SETPIECE MANDA: mientras una coreografía vive, los muros del pool se
	# saltan — dos anclas a la vez no se leen (el bot se comió 4 muros en el
	# drop mientras esquivaba el abanico). El setpiece ES el momento.
	var setpiece_live: bool = not _active_setpiece.is_empty()
	match sname:
		"intro":
			return ["saw", "saw_pair"][in_sec % 2]
		"build":
			var build := ["saw_pair", "saw", "saw_weave"]
			return build[in_sec % build.size()]
		"drop", "drop2":
			# El drop ENSEÑA el muro; el clímax agrega homing. El primer
			# compás de la sección abre con muro (lección clara de entrada),
			# salvo que la coreografía del setpiece esté en curso.
			var drop := ["stripe_wall", "saw_pair", "saw", "saw_weave", "saw_pair"]
			if in_sec == 0 and not setpiece_live:
				return "stripe_wall"
			var seq: Array = drop.duplicate()
			if sname == "drop2" and in_sec % 4 == 1:
				seq[in_sec % seq.size()] = "homing"
			var pick: String = str(seq[in_sec % seq.size()])
			if setpiece_live and (pick == "stripe_wall" or pick == "hazard_wall"):
				pick = "saw_pair"   # variación viva sin apilar un segundo ancla
			return pick
		"breakdown":
			var bd := ["saw", "saw_pair", "saw", "saw_weave"]
			return bd[in_sec % bd.size()]
		_:
			var outro := ["saw", "saw_pair"]
			return outro[in_sec % outro.size()]

## Nombre de la sección del chart que contiene el compás bar (estructura
## real: chart.sections en beats; bar*4 cae dentro).
func _section_name_of_bar(bar: int) -> String:
	var beat: int = clampi(bar * 4, 0, chart.beat_times.size() - 1)
	var t: float = chart.beat_times[beat]
	return str(_section_intent(t)["name"])

## Compás absoluto donde EMPIEZA la sección que contiene bar.
func _section_start_bar(bar: int) -> int:
	var sname := _section_name_of_bar(bar)
	for s in chart.level_sections:
		if str(s.get("name", "")) == sname:
			return int(float(s.get("start", 0.0)) / maxf(beat_len * 4.0, 0.001))
	return 0

# --- NUEVO: Usar downbeat/bars/phrases para coreografiar ---
func spawns_at_downbeat(t: float, beat_idx: int, base_color: Color) -> Array[Dictionary]:
	"""Llamado en cada downbeat (cada 4 beats) — patrones grandes."""
	if not chart.downbeat[beat_idx]:
		return []
	# En easy_mode (nivel 1) no hay muros de downbeat.
	if easy_mode:
		return []
	# Las secciones tranquilas no lanzan muros: la energía manda la dificultad
	var sec := _current_section(t)
	if not sec.is_empty() and float(sec.get("energy", 0.5)) < 0.45:
		return []
	# JSAB: mientras un SETPIECE vive, ES el momento — los muros grandes no
	# se apilan encima (el campo se limpia alrededor de las anclas).
	if not _active_setpiece.is_empty():
		return []
	return _build_pattern("stripe_wall", t, Color(1, 0.2, 0.3, 1), beat_idx)

func spawns_at_bar(t: float, beat_idx: int, base_color: Color) -> Array[Dictionary]:
	if easy_mode:
		return []
	if wall_active:
		return []
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
	return _build_pattern(pattern, t, base_color, beat_idx)

func spawns_at_phrase(t: float, beat_idx: int, base_color: Color) -> Array[Dictionary]:
	"""Llamado en cada phrase (cada 16 beats) — setpieces / nuevo mech."""
	if beat_idx % 16 != 0:
		return []
	# Los setpieces solo aparecen cuando la música lo pide (no en el intro).
	# NOTA: el director AGENDA desde spawns_at (ver _director_pump); esta
	# función queda como gancho de compatibilidad para llamadas externas
	# (tests viejos) — el scheduling real ya no pasa por acá.
	var sec := _current_section(t)
	if not sec.is_empty() and float(sec.get("energy", 0.5)) < 0.5:
		return []
	return []

## Director JSAB: agenda en phrase beats y emite las fases que vencen en el
## beat actual. TODO dentro de spawns_at para que el orden de Gameplay
## (spawns_at primero, spawns_at_phrase después) no pierda la fase 0.
func _director_pump(t: float, beat_idx: int, base_color: Color) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# 1) Emisión: fases del setpiece activo que vencen en ESTE beat.
	if not _active_setpiece.is_empty():
		out.append_array(_emit_setpiece_phases(t, beat_idx, base_color))
	# 2) Agenda: phrase beat de sección con script propio, sin setpiece
	#    activo, y SIN MURO en pantalla (entrada limpia: JSAB nunca abre su
	#    ancla sobre un mulo que barre — el jugador lee el aviso, no pelea
	#    dos cosas a la vez). El MAPA manda sobre la energía: el outro tiene
	#    un script (los anillos del final) aunque sea la sección más calma.
	if beat_idx % 16 == 0 and _active_setpiece.is_empty() and not wall_active:
		var sec := _current_section(t)
		if not sec.is_empty() and not SETPIECE_BY_SECTION.get(str(sec.get("name", "")), "").is_empty():
			var script_key: String = str(SETPIECE_BY_SECTION.get(str(sec.get("name", "")), ""))
			if not easy_mode:
				script_key = "laser_sweep_v1" if _rng.randf() < 0.5 else "closing_perimeter_v1"
			if not script_key.is_empty():
				_active_setpiece = {"script_key": script_key, "anchor_beat": beat_idx}
				# La fase 0 vence ahora mismo: emitirla ya.
				out.append_array(_emit_setpiece_phases(t, beat_idx, base_color))
	return out

## Emite las fases del setpiece activo que vencen en este beat y cierra la
## coreografía cuando pasó la última fase + 2 beats. Spawn de fase lleva la
## clave "setpiece_phase" (la bomba del test la filtra con eso).
func _emit_setpiece_phases(t: float, beat_idx: int, base_color: Color) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var script: Array = SETPIECE_SCRIPTS.get(str(_active_setpiece.get("script_key", "")), [])
	if script.is_empty():
		_active_setpiece = {}
		return out
	var offset: int = beat_idx - int(_active_setpiece.get("anchor_beat", -999))
	var last_at: int = 0
	for ph in script:
		last_at = maxi(last_at, int(ph.get("at", 0)))
	if offset < 0 or offset > last_at + 2:
		_active_setpiece = {}
		return out
	for ph in script:
		if int(ph.get("at", -1)) != offset:
			continue
		var emit_key: String = str(ph.get("emit", ""))
		if emit_key.is_empty():
			continue   # fase marcadora (Task 3 la llena)
		# VARIACIÓN por invocación (anti-hardcode): el RNG semillado del track
		# decide los params de la fase — mismo track => misma variación, pero
		# CADA setpiece de la partida es distinto (hub, radios, gap, giro).
		var phase_params: Dictionary = ph.get("params", {})
		var spawn_seed: int = int(_active_setpiece.get("anchor_beat", 0)) * 131 + offset
		for s in _build_pattern(emit_key, t, DANGER_RED, beat_idx, phase_params, spawn_seed):
			s["setpiece_phase"] = true
			out.append(s)
	return out

func _current_section(t: float) -> Dictionary:
	for s in chart.level_sections:
		var start: float = float(s.get("start", 0.0))
		var end: float = float(s.get("end", 1e9))
		if t >= start and t < end:
			return s
	return {}

## Intent de la sección activa en el tiempo t, derivado de su ENERGÍA (la del
## chart) — nunca de rangos de compás hardcodeados. Un solo helper para
## cadencia (T3), velocidad (T4), visuales (T5) y coreografía (T8).
## Devuelve: {
##   "name": String,             # nombre de la sección del chart
##   "energy": float,            # 0..1
##   "bars_per_encounter": int,  # 2 en intro/outro (energía baja), 1 en el resto
##   "accent_beats": bool,       # true solo en drops (energía >= 0.8)
## }
func _section_intent(t: float) -> Dictionary:
	var sec := _current_section(t)
	var name: String = str(sec.get("name", ""))
	var energy: float = float(sec.get("energy", 0.5))
	if name.is_empty():
		# Sin sección (fuera del chart): comportamiento previo conservador.
		return {"name": "", "energy": energy, "bars_per_encounter": 1, "accent_beats": false}
	return {
		"name": name,
		"energy": energy,
		"bars_per_encounter": 2 if energy < 0.45 else 1,
		"accent_beats": energy >= 0.8,
	}

func _build_pattern(pattern: String, t: float, base: Color, beat_idx: int = 0, params: Dictionary = {}, spawn_seed: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match pattern:
		"saw_pair":
			# Dos sierras en carriles opuestos: lectura de timing, no ruido.
			out.append(_lane_saw(0.25, -50.0, -28.0, t))
			out.append(_lane_saw(0.75, -50.0, 28.0, t))
		"saw_weave":
			# TresLinea con velocidades opuestas para crear una lectura de weaving.
			out.append(_lane_saw(0.18, -45.0, -62.0, t))
			out.append(_lane_saw(0.50, -85.0, 0.0, t))
			out.append(_lane_saw(0.82, -45.0, 62.0, t))
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
			# JUSTICIA: un muro a la vez. Si hay un muro en pantalla o el
			# anterior termino hace menos de 1 beat, no sale nada: los muros
			# nunca se solapan y cada hueco es 100% alcanzable.
			if wall_active or (t - _last_wall_end) < beat_len:
				return []
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
			# Cobertura: rango tangente = diagonal completa + margen.
			# En diagonal el bbox proyectado es mas chico que la pantalla
			# real y el rect girado dejaba esquinas sin cubrir.
			var need: float = play_size.length() + 200.0
			for cn: Vector2 in corners:
				var sv: float = cn.dot(n)
				var tv: float = cn.dot(t_dir)
				smin = minf(smin, sv)
				smax = maxf(smax, sv)
				tmin = minf(tmin, tv)
				tmax = maxf(tmax, tv)
			# Expandir simetrico: el rect girado cubre toda la pantalla.
			var span: float = tmax - tmin
			if span < need:
				var ex: float = (need - span) * 0.5
				tmin -= ex
				tmax += ex
			# Hueco alineado a carriles: la grilla vive en el eje de AVANCE (s),
			# con el mismo spacing que los carriles de targets (~1/10 del area).
			# El pasillo cae siempre sobre un carril de la misma grilla virtual.
			var span_len: float = smax - smin
			var lane_spacing: float = maxf(110.0, span_len / 10.0)
			var usable: float = span_len - 360.0
			# Hueco alcanzable: carriles recortados a la banda central (nunca
			# pegado al borde) y a maximo 1 carril del hueco anterior (nunca te
			# pide cruzar la arena entera). _last_gap_u guarda el indice previo.
			var n_lanes: int = maxi(int(usable / lane_spacing), 1)
			var want: int = (bar_idx * 3 + 1) % n_lanes
			var lo_c: int = mini(1, n_lanes - 1)
			var hi_c: int = maxi(n_lanes - 2, lo_c)
			var want_c: int = clampi(want, lo_c, hi_c)
			var prev_c: int = clampi(int(_last_gap_u), lo_c, hi_c)
			var gap_i: int = clampi(want_c, prev_c - 1, prev_c + 1)
			# (gap solo se registra al EMITIR, abajo: si el muro se salta por overlap,
			#  el siguiente keep usa el ultimo emitido de verdad)
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
				_last_gap_u = float(gap_i)
				_last_wall_end = t + (2.5 if easy_mode else 2.0) * beat_len + 2.0 * beat_len
				out.append(_stripe_band(n, t_dir, tmin, tmax, smin, gap_center - gap_half, gap_center, DANGER_RED, bar_idx, gap_i))
				out.append(_stripe_band(n, t_dir, tmin, tmax, gap_center + gap_half, smax, gap_center, DANGER_RED, bar_idx, gap_i))
		"saw":
			var x = _rng.randf_range(play_size.x * 0.15, play_size.x * 0.85)
			out.append(_saw(x, DANGER_RED, t))
		"drifter_swarm":
			for i in range(5):
				var x = _rng.randf_range(play_size.x * 0.08, play_size.x * 0.92)
				out.append(_drifter(x, DANGER_RED, t))
		"laser_telegraph":
			var x = _rng.randf_range(play_size.x * 0.15, play_size.x * 0.85)
			out.append(_laser_telegraph(x))
		"spoke_fan":
			out.append(_spoke_fan(t, beat_idx, params, spawn_seed))
		"laser_sweep":
			out.append(_laser_sweep(t, beat_idx, params, spawn_seed))
		"waveform_wall":
			out.append(_waveform_wall(t, beat_idx, params, spawn_seed))
		"squeeze_corridor":
			out.append(_squeeze_corridor(t, beat_idx, params, spawn_seed))
		"pulse_rings":
			out.append(_pulse_rings(t, beat_idx, params, spawn_seed))
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
	for s in out:
		s["encounter"] = pattern
	return out

# --- Helpers para nuevos patrones ---
func _hazard(x: float) -> Dictionary:
	return {"pos": Vector2(x, -30.0), "vel": Vector2(0, 200.0 * (0.85 if easy_mode else 1.0)),
		"radius": _rng.randf_range(24, 32), "color": Color(1.0, 0.2, 0.3, 1.0), "is_hazard": true, "hit_health_bonus": -15.0 if easy_mode else -25.0, "type": "hazard"}

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
		"state": "warning", "warn_time": (2.5 if easy_mode else 2.0) * beat_len, "active_time": 2.0 * beat_len, "fade_time": 0.5 * beat_len,
		"bar_idx": bar_idx, "lane_index": gap_i,
		"alpha": 1.0}

## Beats de cruce para la sección activa en t: cuántos beats tarda un peligro
## en caer desde el borde superior hasta la zona del jugador (0.78 de alto).
## Siempre en la grilla audible (T4): entero, o medio beat en drop2 — la
## canción renderiza hats de corchea (y semicorchea con energy>=0.8) en drops,
## así que la llegada a contratiempo también cae sobre un golpe audible.
## Sección calma (energy<0.45) => 8 beats; resto => 6; drop2 => 5.5 (el
## clímax aprieta: +8.5% de velocidad, lectura musical intacta).
## easy_mode NO recorta los beats (el margen del tutorial viene de menos
## encuentros, no de sierras más lentas: la lectura rítmica debe ser igual).
func _crossing_beats(t: float) -> float:
	var intent := _section_intent(t)
	if float(intent["energy"]) < 0.45:
		return 8.0
	if str(intent["name"]) == "drop2":
		return 5.5
	return 6.0

## Velocidad vertical cuantizada a beats enteros de la sección en t, para un
## spawn que nace en y = spawn_y. La llegada a la zona del jugador (78% del
## alto) cae en un beat audible, sin importar la altura de origen del patrón
## (los lane_saw nacen a -45/-50/-85). Derivada del BPM y del viewport real.
func _quantized_vy_from(t: float, spawn_y: float) -> float:
	var travel: float = play_size.y * 0.78 - spawn_y
	var n_beats: float = _crossing_beats(t)
	return travel / (n_beats * beat_len)

func _lane_saw(u: float, y: float, vx: float, t: float = -1.0) -> Dictionary:
	var s: Dictionary = _saw(_lane_x(u), DANGER_RED)
	s["pos"] = Vector2(_lane_x(u), y)
	var vy: float = _quantized_vy_from(t, y) if t >= 0.0 else 120.0
	s["vel"] = Vector2(vx, vy)
	return s

func _saw(x: float, c: Color, t: float = -1.0) -> Dictionary:
	var vy: float = _quantized_vy_from(t, -50.0) if t >= 0.0 else 120.0 * (0.85 if easy_mode else 1.0)
	return {"pos": Vector2(x, -50.0), "vel": Vector2(_rng.randf_range(-50, 50), vy),
		"radius": 30, "color": c, "is_hazard": true, "hit_health_bonus": -20.0 if easy_mode else -30.0, "type": "saw"}

func _drifter(x: float, c: Color, t: float = -1.0) -> Dictionary:
	# Anillo con púas que deriva y rota
	var vy: float = _quantized_vy_from(t, -30.0) if t >= 0.0 else 80.0 * (0.85 if easy_mode else 1.0)
	return {"pos": Vector2(x, -30.0), "vel": Vector2(_rng.randf_range(-40, 40), vy),
		"radius": 28, "color": c, "is_hazard": true, "hit_health_bonus": -18.0 if easy_mode else -25.0, "type": "drifter"}

func _laser_telegraph(x: float) -> Dictionary:
	# Telegraph de 3 BEATS -> dispara un beam en DIRECCIÓN ALEATORIA.
	# Derivado del BPM real (no segundos fijos): el disparo cae sobre un
	# golpe audible de la canción. Al tocar alarma sonora: el jugador
	# SIEMPRE escucha el aviso. (Gameplay dispara el sonido al recibir el
	# spawn; aquí no tocamos autoloads para que el E2E headless compile
	# sin escena.)
	var dir := Vector2.from_angle(_rng.randf() * TAU)
	var anchor := Vector2(x, _rng.randf_range(play_size.y * 0.19, play_size.y * 0.81))
	var telegraph_beats: float = 3.0 * beat_len
	print("[LASER] telegraph spawn anchor=%s dir_angle=%.1f° fire_on_beat(%.3fs)" % [anchor, rad_to_deg(dir.angle()), telegraph_beats])
	return {"pos": anchor, "vel": Vector2(0, 0),
		"radius": 12, "color": Color(1, 0.8, 0, 1), "is_hazard": false,
		"type": "laser_telegraph", "telegraph_time": telegraph_beats, "telegraph_total": telegraph_beats,
		"fired": false, "beam_dir": dir}

## JSAB T3 — Láser que BARRE la pantalla (arquetipo 90s del video): hub en un
## borde/corner, haz que rota de ang_start a ang_end durante la ventana
## active. Telegraph 2 beats (muestra el ARCO completo a recorrer), active 4
## beats, fade 2. Fairness: <= 90°/beat (test-asserted), ancho de haz ~12px.
## Parametrizado como el spoke_fan: hub, ángulos y sentido por seed de ancla.
func _laser_sweep(t: float, beat_idx: int, params: Dictionary = {}, spawn_seed: int = -1) -> Dictionary:
	const TELEGRAPH_BEATS: int = 2
	const ACTIVE_BEATS: int = 4
	const FADE_BEATS: int = 2
	var vr := RandomNumberGenerator.new()
	vr.seed = 977 ^ spawn_seed if spawn_seed >= 0 else 977 ^ beat_idx
	# Hub en un lateral (izq/der alternado), altura banda central
	var side: float = -1.0 if vr.randf() < 0.5 else 1.0
	if params.has("side"):
		side = float(params["side"])
	var hub: Vector2 = Vector2(
		-60.0 if side < 0.0 else play_size.x + 60.0,
		play_size.y * vr.randf_range(0.25, 0.6))
	# Barrido: 60..90° total, de punta a punta de la pantalla, sentido
	# determinista por seed. ang_base apunta hacia adentro.
	var sweep_deg: float = vr.randf_range(60.0, 90.0)
	var ang_base: float = 0.0 if side < 0.0 else PI   # hacia adentro
	var spin: float = 1.0 if vr.randf() < 0.5 else -1.0
	if params.has("spin"):
		spin = float(params["spin"])
	var ang_start: float = ang_base - spin * deg_to_rad(sweep_deg) * 0.5
	var ang_end: float = ang_base + spin * deg_to_rad(sweep_deg) * 0.5
	return {
		"type": "laser_sweep", "pos": hub, "vel": Vector2.ZERO,
		"radius": 12.0, "beam_len": play_size.x * 1.35,
		"ang_start": ang_start, "ang_end": ang_end,
		"sweep_deg_per_beat": sweep_deg / float(ACTIVE_BEATS),
		"state": "telegraph", "state_time": 0.0,
		"telegraph_beats": TELEGRAPH_BEATS, "active_beats": ACTIVE_BEATS, "fade_beats": FADE_BEATS,
		"is_hazard": false, "hit_health_bonus": -20.0,
		"color": DANGER_RED, "setpiece_phase": true, "beat_len": beat_len,
	}

## JSAB T4 — Muro de ONDA que sube desde abajo (arquetipo 45s/1350s del
## video): una fila de columnas que crecen desde el borde inferior siguiendo
## un perfil senoidal desfasado por columna. Telegraph 2 / active 4 / fade 2.
## Fairness: la cresta queda ACOTADA (peak_line <= 62% del alto) dejando
## margen de reacción sobre la fila del jugador; el trough más bajo siempre
## cae por debajo del área (nunca se cierra entero el paso).
## Parametrizado por seed de ancla, como el resto de los setpieces.
func _waveform_wall(t: float, beat_idx: int, params: Dictionary = {}, spawn_seed: int = -1) -> Dictionary:
	const TELEGRAPH_BEATS: int = 2
	const ACTIVE_BEATS: int = 4
	const FADE_BEATS: int = 2
	var vr := RandomNumberGenerator.new()
	vr.seed = 613 ^ spawn_seed if spawn_seed >= 0 else 613 ^ beat_idx
	var columns: int = vr.randi_range(8, 14)
	if params.has("columns"):
		columns = clampi(int(params["columns"]), 6, 20)
	# Cresta: 0.48..0.60 del alto (nunca más: el jugador al 78% tiene 18% de
	# margen vertical para reaccionar desde el aviso).
	var peak_frac: float = vr.randf_range(0.48, 0.60)
	if params.has("peak_frac"):
		peak_frac = clampf(float(params["peak_frac"]), 0.35, 0.62)
	# Perfil: 1.5..3.5 ciclos a lo ancho + desfasamiento aleatorio.
	var cycles: float = vr.randf_range(1.5, 3.5)
	var phase: float = vr.randf_range(0.0, TAU)
	return {
		"type": "waveform_wall", "pos": Vector2.ZERO, "vel": Vector2.ZERO,
		"columns": columns, "col_w": play_size.x / float(columns),
		"wave_cycles": cycles, "wave_phase": phase, "wave_amp": peak_frac * 0.5,
		"base_line": play_size.y * (peak_frac + 0.18),   # trough bajo el área
		"peak_line": play_size.y * peak_frac,              # techo de la onda
		"peak_frac": peak_frac,
		"rise_beats": ACTIVE_BEATS,                        # toda la ventana activa
		"state": "telegraph", "state_time": 0.0,
		"telegraph_beats": TELEGRAPH_BEATS, "active_beats": ACTIVE_BEATS, "fade_beats": FADE_BEATS,
		"is_hazard": false, "hit_health_bonus": -18.0,
		"color": DANGER_RED, "setpiece_phase": true, "beat_len": beat_len,
	}

## JSAB T5 — CORREDOR que se cierra desde los costados (arquetipo 225s del
## video: dos paredes que aprietan el espacio jugable). Telegraph 2 / active 4
## / fade 2. La velocidad de cierre es BEAT-DERIVADA y el pasillo NUNCA baja
## de min_gap (fairness dura: siempre hay un bolsillo cómodo; el nivel
## aprieta pero no mata). Parametrizado por seed de ancla.
func _squeeze_corridor(t: float, beat_idx: int, params: Dictionary = {}, spawn_seed: int = -1) -> Dictionary:
	const TELEGRAPH_BEATS: int = 2
	const ACTIVE_BEATS: int = 4
	const FADE_BEATS: int = 2
	var vr := RandomNumberGenerator.new()
	vr.seed = 419 ^ spawn_seed if spawn_seed >= 0 else 419 ^ beat_idx
	# Pasillo inicial: 70..85% del ancho (aprieta de ahí, no de la nada).
	var start_frac: float = vr.randf_range(0.70, 0.85)
	# Bolsillo mínimo: 28..38% del ancho — SIEMPRE transitable.
	var min_frac: float = vr.randf_range(0.28, 0.38)
	if params.has("start_frac"):
		start_frac = clampf(float(params["start_frac"]), 0.4, 0.95)
	if params.has("min_frac"):
		min_frac = clampf(float(params["min_frac"]), 0.2, 0.6)
	# El centro del pasillo se desplaza un poco (no siempre al medio): el
	# jugador tiene que elegir dónde quedarse.
	var drift: float = vr.randf_range(-0.12, 0.12)
	return {
		"type": "squeeze_corridor", "pos": Vector2.ZERO, "vel": Vector2.ZERO,
		"play_w": play_size.x,
		"start_gap": play_size.x * start_frac,
		"min_gap": play_size.x * min_frac,
		"gap_center": play_size.x * (0.5 + drift),
		"gap_drift": play_size.x * drift,
		"band_half": 46.0,          # halfwidth visual de cada pared
		"close_beats": ACTIVE_BEATS,
		"state": "telegraph", "state_time": 0.0,
		"telegraph_beats": TELEGRAPH_BEATS, "active_beats": ACTIVE_BEATS, "fade_beats": FADE_BEATS,
		"is_hazard": false, "hit_health_bonus": -18.0,
		"color": DANGER_RED, "setpiece_phase": true, "beat_len": beat_len,
	}

## JSAB T6 — ANILLOS que se expanden desde el hub con un hueco rotante
## (arquetipo 1350s del video: el espacio se cierra en círculos). Telegraph 2 /
## active 4 / fade 2. El radio crece a velocidad BEAT-DERIVADA y CRUZA la fila
## del jugador (78% del alto) en un número entero de beats — misma regla de
## grilla que T4. El hueco >= 50° (fairness, test-asserted) y ROTA lento, así
## que el jugador debe viajar con él. Parametrizado por seed de ancla.
func _pulse_rings(t: float, beat_idx: int, params: Dictionary = {}, spawn_seed: int = -1) -> Dictionary:
	const TELEGRAPH_BEATS: int = 2
	const ACTIVE_BEATS: int = 4
	const FADE_BEATS: int = 2
	var vr := RandomNumberGenerator.new()
	vr.seed = 271 ^ spawn_seed if spawn_seed >= 0 else 271 ^ beat_idx
	var rings_n: int = vr.randi_range(2, 3)
	if params.has("rings"):
		rings_n = clampi(int(params["rings"]), 2, 5)
	# Hub en la banda central-alta (el espacio jugable es abajo).
	var hub: Vector2 = Vector2(play_size.x * vr.randf_range(0.35, 0.65), play_size.y * vr.randf_range(0.30, 0.45))
	var player_row: float = play_size.y * 0.78
	# Radio objetivo: el anillo tiene que CRUZAR la fila del jugador Y
	# seguir cerrando más allá (el espacio se cierra en círculos): desde el
	# hub a la fila y un 40% extra, con piso de 400px.
	var to_row: float = absf(player_row - hub.y)
	var target_radius: float = maxf(to_row * 1.4, 400.0)
	# El hueco: >= 50 grados.
	var gap_deg: float = vr.randf_range(50.0, 90.0)
	if params.has("gap_deg"):
		gap_deg = clampf(float(params["gap_deg"]), 50.0, 140.0)
	# El hueco rota lento (el jugador viaja con el hueco).
	var gap_spin: float = signf(vr.randf_range(0.15, 0.35))
	return {
		"type": "pulse_rings", "pos": hub, "vel": Vector2.ZERO,
		"rings": rings_n, "target_radius": target_radius,
		"player_row": player_row,
		"gap_angle": deg_to_rad(gap_deg), "gap_center": vr.randf_range(0.0, TAU),
		"gap_spin": gap_spin,
		"grow_beats": ACTIVE_BEATS,     # el anillo 0 cruza la fila en active_beats
		"state": "telegraph", "state_time": 0.0,
		"telegraph_beats": TELEGRAPH_BEATS, "active_beats": ACTIVE_BEATS, "fade_beats": FADE_BEATS,
		"is_hazard": false, "hit_health_bonus": -18.0,
		"color": DANGER_RED, "setpiece_phase": true, "beat_len": beat_len,
	}

func _homing(x: float, c: Color) -> Dictionary:
	# Proyectil teledirigido: persigue al jugador (Gameplay maneja el chase).
	return {"pos": Vector2(x, -30.0), "vel": Vector2(0, 250.0 * (0.85 if easy_mode else 1.0)),
		"radius": 20, "color": c, "is_hazard": true, "hit_health_bonus": -15.0 if easy_mode else -20.0, "type": "homing"}

## JSAB T2 — Abanico de rayos rotando (arquetipo 30s/540s del video): hub
## central + N rayos, hueco de >= 2 rayos (siempre legible), ciclo
## telegraph(2 beats) -> active(4) -> fade(2). Todo beat-derivado.
## VARIACIÓN (anti-hardcode): cada invocación del director llega con params
## + spawn_seed — hub, radios, cantidad de rayos, hueco y sentido de giro
## salen del RNG determinista por ancla. Mismo nivel => mismos valores
## (reproducible), pero NO dos abanicos iguales en la partida.
## Fairness (assert en test_spoke_fan): gap>=2 SIEMPRE, rotación >= 8
## beats/giro SIEMPRE, nace inofensivo SIEMPRE — los rangos varían, los
## pisos no.
func _spoke_fan(t: float, beat_idx: int, params: Dictionary = {}, spawn_seed: int = -1) -> Dictionary:
	# Pisos de fairness (R3: un solo lugar, test-asserted)
	const MIN_GAP_SPOKES: int = 2
	const TELEGRAPH_BEATS: int = 2
	const ACTIVE_BEATS: int = 4
	const FADE_BEATS: int = 2
	const MIN_BEATS_PER_REV: float = 16.0
	# RNG de la invocación (semilla por ancla: determinista, no global)
	var vr := RandomNumberGenerator.new()
	vr.seed = 1337 ^ spawn_seed if spawn_seed >= 0 else 1337 ^ beat_idx
	# Rango seguro de hub: banda central (lejos de los bordes y del HUD)
	var hub_u: float = vr.randf_range(0.32, 0.68)
	var hub_v: float = vr.randf_range(0.30, 0.55)
	if params.has("hub_u"):
		hub_u = clampf(float(params["hub_u"]), 0.2, 0.8)
	if params.has("hub_v"):
		hub_v = clampf(float(params["hub_v"]), 0.2, 0.7)
	var hub: Vector2 = Vector2(play_size.x * hub_u, play_size.y * hub_v)
	# Rayos: 6..10; hueco: 2..3 (piso 2)
	var spokes: int = vr.randi_range(6, 10)
	var gap_spokes: int = maxi(MIN_GAP_SPOKES, vr.randi_range(2, 3))
	if params.has("spokes"):
		spokes = clampi(int(params["spokes"]), 6, 12)
	if params.has("gap_spokes"):
		gap_spokes = maxi(MIN_GAP_SPOKES, int(params["gap_spokes"]))
	# Radio y giro: el sentido alterna para que el jugador no automatice.
	# Radio generoso (JSAB: el abanico DOMINA la pantalla) pero acotado al
	# MIN(w,h) para que en pantallas anchas no salga de la arena.
	var radius_frac: float = vr.randf_range(0.55, 0.75)
	var spin_sign: float = 1.0 if vr.randf() < 0.5 else -1.0
	var beats_per_rev: float = vr.randf_range(MIN_BEATS_PER_REV, 24.0)
	if params.has("spin_sign"):
		spin_sign = float(params["spin_sign"])
	var gap_first: int = vr.randi_range(0, spokes - 1)
	return {
		"type": "spoke_fan", "pos": hub, "vel": Vector2.ZERO,
		"radius": minf(play_size.x, play_size.y) * radius_frac,
		"spokes": spokes, "gap_spokes": gap_spokes,
		"rot_speed": spin_sign * TAU / (beats_per_rev * beat_len),
		"rot_phase": float(beat_idx % 4) * (TAU / float(spokes)),
		"beats_per_rev": beats_per_rev,
		"state": "telegraph", "state_time": 0.0,
		"telegraph_beats": TELEGRAPH_BEATS, "active_beats": ACTIVE_BEATS, "fade_beats": FADE_BEATS,
		"is_hazard": false, "hit_health_bonus": -20.0,
		"color": DANGER_RED, "setpiece_phase": true,
		"gap_first": gap_first, "beat_len": beat_len,
	}

func _perimeter_ball(cx: float, cy: float, angle: float) -> Dictionary:
	var dir = Vector2(cos(angle), sin(angle))
	return {"pos": Vector2(cx, cy) + dir * 500, "vel": -dir * 100.0,
		"radius": 40, "color": Color(1, 0.2, 0.3, 1), "is_hazard": true, "hit_health_bonus": -40.0, "type": "perimeter"}
