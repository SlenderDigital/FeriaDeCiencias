class_name PilotLogic
extends RefCounted
## PilotLogic — el piloto automático que juega el nivel (T9).
##
## Existe para poder VERIFICAR el juego de verdad: sin nadie al volante la
## partida muere sola al ~49% y no hay gameplay que mirar ni evaluar.
##
## No es una heurística nueva ni una copia de la colisión: elige un punto y
## tools/test_pilot.gd lo valida contra las MISMAS funciones que usa el
## juego. Si el punto estuviera en un peligro, el test falla.

const PLAY_MIN_X: float = 40.0
const PLAY_MAX_X: float = 1240.0
const PLAY_MIN_Y: float = 150.0
const PLAY_MAX_Y: float = 640.0
const MAX_SPEED: float = 550.0

## Un paso de movimiento acotado: nunca teletransporta.
static func steer_step(from: Vector2, desired: Vector2, speed: float, delta: float) -> Vector2:
	var to: Vector2 = desired - from
	var step_len: float = minf(speed * delta, to.length())
	if to.length() <= 0.01:
		return from
	return from + to.normalized() * step_len

## El punto seguro para un objetivo concreto. Cada tipo de setpiece tiene su
## lectura (el hub, el hueco, la cresta, el bolsillo) — la misma que un humano
## haría leyendo el aviso.
static func safe_point(obj: Dictionary) -> Vector2:
	return safe_point_verified(obj, _read_point(obj))

## Lectura "ingenua" de cada patrón: un punto candidato por tipo. Sirve como
## punto de partida; safe_point_verified lo corrige si cae en un peligro.
static func _read_point(obj: Dictionary) -> Vector2:
	var ty: String = str(obj.get("type", ""))
	match ty:
		"spoke_fan":
			return _spoke_fan_point(obj)
		"laser_sweep":
			return _sweep_point(obj)
		"waveform_wall":
			return _waveform_point(obj)
		"squeeze_corridor":
			return _squeeze_point(obj)
		"pulse_rings":
			return _rings_point(obj)
		"mini_ring":
			return _rings_point(obj)
		"mini_fan":
			return _spoke_fan_point(obj)
	return _default_point(obj)

## El piloto ESCANEA la pantalla como un humano: prueba la lectura y, si la
## colisión real dice que es un peligro, prueba candidatos alternativos
## (esquinas, bandas libres) y devuelve el primero que la MISMA función de
## colisión del juego marca como seguro. Sin esto el piloto se ponía
## exactamente en el arco del barrido (2 golpes sólo por eso).
static func safe_point_verified(obj: Dictionary, first_guess: Vector2) -> Vector2:
	if not _is_hit(obj, first_guess):
		return first_guess
	var hub: Vector2 = obj.get("pos", Vector2(640, 400))
	var ty: String = str(obj.get("type", ""))
	# Candidatos: en rings de radio variable alrededor del hub + rejilla del
	# área jugable. El primero seguro gana (el más cercano a la lectura).
	var cands: Array[Vector2] = []
	var r0: float = 120.0
	var r1: float = 420.0
	for r_i in range(6):
		var rr: float = lerpf(r0, r1, float(r_i) / 5.0)
		for a_i in range(16):
			var aa: float = TAU * float(a_i) / 16.0
			cands.append(_clamp_play(hub + Vector2.from_angle(aa) * rr))
	for gx in [160.0, 380.0, 640.0, 900.0, 1120.0]:
		for gy in [220.0, 400.0, 560.0]:
			cands.append(Vector2(gx, gy))
	for c in cands:
		if not _is_hit(obj, c):
			return c
	# Ninguno libre (patrón tapado): al menos alejamos del hub.
	return _clamp_play(hub + Vector2(0, -260.0) if hub.y > 360.0 else hub + Vector2(0, 260.0))

## El punto seguro PREDICTIVO: no basta con que el destino sea libre AHORA —
## el jugador tarda en llegar y el haz sigue barriendo. Esta función exige
## que el destino siga siendo libre dentro de N frames (el tiempo de viaje),
## que es exactamente lo que hace un humano que ve venir el haz.
static func safe_point_eta(obj: Dictionary, from: Vector2, speed: float, frame_dt: float) -> Vector2:
	var first_guess: Vector2 = _read_point(obj)
	if not _safe_eta(obj, first_guess, from, speed, frame_dt):
		# buscar un destino que siga libre al llegar
		var hub: Vector2 = obj.get("pos", Vector2(640, 400))
		for r_i in range(7):
			for a_i in range(20):
				var rr: float = lerpf(110.0, 430.0, float(r_i) / 6.0)
				var aa: float = TAU * float(a_i) / 20.0
				var c: Vector2 = _clamp_play(hub + Vector2.from_angle(aa) * rr)
				if _safe_eta(obj, c, from, speed, frame_dt):
					return c
		for gx in [160.0, 380.0, 640.0, 900.0, 1120.0]:
			for gy in [220.0, 400.0, 560.0]:
				var g: Vector2 = Vector2(gx, gy)
				if _safe_eta(obj, g, from, speed, frame_dt):
					return g
		# si nada sobrevive al viaje, ir al más lejano del peligro actual
		var best_far: Vector2 = first_guess
		var best_d: float = -1.0
		for a_i in range(20):
			var aa2: float = TAU * float(a_i) / 20.0
			var c2: Vector2 = _clamp_play(hub + Vector2.from_angle(aa2) * 300.0)
			var d2: float = c2.distance_to(hub)
			if d2 > best_d:
				best_d = d2
				best_far = c2
		return best_far
	return first_guess

## ¿El punto sigue libre cuando el jugador llegue? Muestrea el viaje.
static func _safe_eta(obj: Dictionary, to: Vector2, from: Vector2, speed: float, frame_dt: float) -> bool:
	var d: float = from.distance_to(to)
	var steps: int = clampi(int(ceil(d / maxf(speed * frame_dt, 1.0))) + 1, 1, 40)
	var p: Vector2 = from
	for i in range(steps):
		p = from.lerp(to, float(i + 1) / float(steps))
		if _is_hit(obj, p):
			return false
	return true

## La MISMA colisión que usa el juego, sin copia.
static func _is_hit(obj: Dictionary, p: Vector2) -> bool:
	var ty: String = str(obj.get("type", ""))
	match ty:
		"spoke_fan", "mini_fan":
			return SpokeFanLogic.hits_player(obj, p)
		"laser_sweep":
			return SweepLogic.hits_player(obj, p)
		"waveform_wall":
			return WaveformLogic.hits_player(obj, p)
		"squeeze_corridor":
			return SqueezeLogic.hits_player(obj, p)
		"pulse_rings", "mini_ring":
			return PulseRingsLogic.hits_player(obj, p)
		"saw", "homing", "drifter", "saw_pair", "saw_weave", "drifter_swarm", "perimeter":
			if obj.has("pos"):
				return p.distance_to(obj["pos"]) < 80.0
	return false

## El ojo del hub (90px) es SIEMPRE seguro en el abanico: el destino natural
## cuando no se puede ganar la carrera contra el hueco.
static func _spoke_fan_point(obj: Dictionary) -> Vector2:
	var hub: Vector2 = obj["pos"]
	return _clamp_play(Vector2(hub.x, hub.y) + Vector2(0, 40))

## Fuera del haz: detrás del hub, donde el barrido no pasa nunca (el hub está
## fuera de pantalla, así que el refugio es el borde).
static func _sweep_point(obj: Dictionary) -> Vector2:
	var hub: Vector2 = obj["pos"]
	var dir_out: Vector2 = (Vector2(640, 360) - hub).normalized()
	return _clamp_play(hub + dir_out * 40.0)

## La onda sube desde abajo: arriba de la cresta, en el trough más cercano.
static func _waveform_point(obj: Dictionary) -> Vector2:
	var cols: int = int(obj.get("columns", 8))
	var colw: float = float(obj.get("col_w", 100.0))
	var peak: float = float(obj.get("peak_line", 400.0))
	# el punto más alto (menor Y) es el más seguro: el trough del perfil
	var x: float = play_center_x()
	var best_x: float = x
	var best_h: float = 1e9
	for c in range(cols):
		var cx: float = (float(c) + 0.5) * colw
		var h: float = WaveformLogic.column_height(obj, c)
		if h < best_h:
			best_h = h
			best_x = cx
	return _clamp_play(Vector2(best_x, maxf(peak - 90.0, PLAY_MIN_Y)))

## El bolsillo del corredor: su centro, con altura de jugador.
static func _squeeze_point(obj: Dictionary) -> Vector2:
	var c: float = SqueezeLogic.gap_center(obj)
	return _clamp_play(Vector2(c, 560.0))

## El hueco del anillo, en un radio comodo (ni en el hub ni fuera de la
## pantalla).
static func _rings_point(obj: Dictionary) -> Vector2:
	var hub: Vector2 = obj["pos"]
	var g: float = PulseRingsLogic.gap_angle(obj)
	var r: float = maxf(PulseRingsLogic.ring_radius(obj, 0) * 0.7, 120.0)
	return _clamp_play(hub + Vector2.from_angle(g) * r)

static func _default_point(obj: Dictionary) -> Vector2:
	if obj.has("pos"):
		var p: Vector2 = obj["pos"]
		if p != Vector2.ZERO:
			return _clamp_play(p)
	return Vector2(640, 560)

static func play_center_x() -> float:
	return 640.0

static func _clamp_play(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, PLAY_MIN_X, PLAY_MAX_X), clampf(p.y, PLAY_MIN_Y, PLAY_MAX_Y))
