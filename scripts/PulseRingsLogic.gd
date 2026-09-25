class_name PulseRingsLogic
extends RefCounted
## PulseRingsLogic — física pura de los anillos expansivos (JSAB T6). Anillos
## que crecen desde el hub con un hueco que ROTA. El juego y el test headless
## usan ESTOS mismos pasos/radios/colisiones.

## Un paso: telegraph -> active -> fade -> done (umbrales en BEATS).
static func step(pr: Dictionary, delta: float, beat_len: float) -> Dictionary:
	pr["state_time"] = float(pr.get("state_time", 0.0)) + delta
	var st: String = str(pr.get("state", "telegraph"))
	var st_t: float = float(pr.get("state_time", 0.0))
	if st == "telegraph" and st_t >= float(pr.get("telegraph_beats", 2)) * beat_len:
		pr["state"] = "active"
		pr["state_time"] = 0.0
		pr["is_hazard"] = true
	elif st == "active" and st_t >= float(pr.get("active_beats", 4)) * beat_len:
		pr["state"] = "fade"
		pr["state_time"] = 0.0
		pr["is_hazard"] = false
	elif st == "fade" and st_t >= float(pr.get("fade_beats", 2)) * beat_len:
		pr["state"] = "done"
		pr["is_hazard"] = false
	return pr

## Progreso de expansión 0..1: en telegraph 12% (el aviso ya insinúa el
## anillo), en active crece con easeInOut hasta 1 (el anillo 0 cruzó la fila
## del jugador al final de la ventana), en fade decae.
static func grow_factor(pr: Dictionary) -> float:
	var st: String = str(pr.get("state", "telegraph"))
	var bl: float = float(pr.get("beat_len", 0.46875))
	if st == "telegraph":
		return 0.12 * clampf(float(pr.get("state_time", 0.0)) / maxf(float(pr.get("telegraph_beats", 2)) * bl, 0.001), 0.0, 1.0)
	if st == "fade":
		return 1.0 - clampf(float(pr.get("state_time", 0.0)) / maxf(float(pr.get("fade_beats", 2)) * bl, 0.001), 0.0, 1.0)
	if st == "done":
		return 0.0
	var prog: float = clampf(float(pr.get("state_time", 0.0)) / (float(pr.get("active_beats", 4)) * bl), 0.0, 1.0)
	return prog * prog * (3.0 - 2.0 * prog)

## Radio del anillo index: los anillos salen espaciados (el 0 primero, el 1
## con retardo, etc). Todos crecen; ninguno se pasa del objetivo.
static func ring_radius(pr: Dictionary, index: int) -> float:
	var target: float = float(pr.get("target_radius", 500.0))
	var n: int = maxi(1, int(pr.get("rings", 2)))
	var stagger: float = float(index) * 0.22   # el anillo 1 va 22% detrás
	var local: float = clampf(grow_factor(pr) - stagger, 0.0, 1.0)
	# el anillo 0 es el que llega a target; los siguientes un poco más lejos
	var span: float = target * (1.0 + 0.30 * float(index))
	return span * local

## Ángulo del CENTRO del hueco ahora (rota lentamente con gap_spin).
static func gap_angle(pr: Dictionary) -> float:
	var st: String = str(pr.get("state", "telegraph"))
	var bl: float = float(pr.get("beat_len", 0.46875))
	var spin: float = float(pr.get("gap_spin", 0.2))
	var base: float = float(pr.get("gap_center", 0.0))
	# el hueco rota en el tiempo total de vida (no se resetea por estado)
	var life: float = _life_time(pr)
	return base + spin * life

static func _life_time(pr: Dictionary) -> float:
	var st: String = str(pr.get("state", "telegraph"))
	var st_t: float = float(pr.get("state_time", 0.0))
	var bl: float = float(pr.get("beat_len", 0.46875))
	if st == "telegraph":
		return st_t
	if st == "active":
		return float(pr.get("telegraph_beats", 2)) * bl + st_t
	return (float(pr.get("telegraph_beats", 2)) + float(pr.get("active_beats", 4))) * bl + st_t

## Ancho del anillo (banda) en px — gruesa y legible.
const RING_HALF_WIDTH: float = 13.0

## Colisión: el jugador está en un anillo si su radio cae dentro de la banda
## de ALGUN anillo Y su ángulo no está dentro del hueco. Solo en active.
static func hits_player(pr: Dictionary, player: Vector2) -> bool:
	if str(pr.get("state", "")) != "active":
		return false
	var hub: Vector2 = pr["pos"]
	var d: Vector2 = player - hub
	var dist: float = d.length()
	var ang: float = d.angle()
	var n: int = int(pr.get("rings", 2))
	for i in range(n):
		var r: float = ring_radius(pr, i)
		if r <= 1.0:
			continue
		if absf(dist - r) > RING_HALF_WIDTH + 16.0:
			continue
		# ¿el ángulo del jugador cae dentro del hueco?
		var g_ang: float = gap_angle(pr)
		var half_gap: float = float(pr.get("gap_angle", 1.0)) * 0.5
		var d_ang: float = absf(fposmod(ang - g_ang + PI, TAU) - PI)
		if d_ang < half_gap:
			return false   # dentro del hueco: seguro para ESE anillo
		return true
	return false
