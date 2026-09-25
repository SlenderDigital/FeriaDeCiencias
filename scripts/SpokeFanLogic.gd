class_name SpokeFanLogic
extends RefCounted
## SpokeFanLogic — física pura del patrón spoke_fan (JSAB T2). Sin escena,
## sin nodos: Gameplay delega acá el step/colisión/ángulos para que el test
## headless pruebe EXACTAMENTE lo que corre el juego.

## Un paso de simulación: avanza state_time, rota el abanico y resuelve el
## ciclo telegraph -> active -> fade -> done (umbrales en BEATS).
static func step(fan: Dictionary, delta: float, beat_len: float) -> Dictionary:
	fan["state_time"] = float(fan.get("state_time", 0.0)) + delta
	var st: String = str(fan.get("state", "telegraph"))
	var st_t: float = float(fan.get("state_time", 0.0))
	if st == "telegraph" and st_t >= float(fan.get("telegraph_beats", 2)) * beat_len:
		fan["state"] = "active"
		fan["state_time"] = 0.0
		fan["is_hazard"] = true
	elif st == "active" and st_t >= float(fan.get("active_beats", 4)) * beat_len:
		fan["state"] = "fade"
		fan["state_time"] = 0.0
		fan["is_hazard"] = false
	elif st == "fade" and st_t >= float(fan.get("fade_beats", 2)) * beat_len:
		fan["state"] = "done"
		fan["is_hazard"] = false
	return fan

## Ángulo total de rotación actual (fase inicial + velocidad × tiempo total
## de vida del patrón — la rotación NO se resetea entre estados).
static func rotation_at(fan: Dictionary) -> float:
	var life: float = _total_time(fan)
	return float(fan.get("rot_phase", 0.0)) + float(fan.get("rot_speed", 0.0)) * life

## Tiempo total de vida acumulado (telegraph+active+fade parciales).
static func _total_time(fan: Dictionary) -> float:
	var st: String = str(fan.get("state", "telegraph"))
	var st_t: float = float(fan.get("state_time", 0.0))
	if st == "telegraph":
		return st_t
	if st == "active":
		return float(fan.get("telegraph_beats", 2)) * _bl(fan) + st_t
	if st == "fade":
		return (float(fan.get("telegraph_beats", 2)) + float(fan.get("active_beats", 4))) * _bl(fan) + st_t
	return (float(fan.get("telegraph_beats", 2)) + float(fan.get("active_beats", 4)) + float(fan.get("fade_beats", 2))) * _bl(fan)

static func _bl(fan: Dictionary) -> float:
	return float(fan.get("beat_len", 0.46875))

## Ángulo del CENTRO del hueco (rota con el abanico).
static func gap_start_angle(fan: Dictionary) -> float:
	var n: int = int(fan.get("spokes", 8))
	var gap: int = int(fan.get("gap_spokes", 2))
	# El hueco ocupa los rayos [gap_first, gap_first+gap); su centro:
	var gap_first: int = int(fan.get("gap_first", 0))
	var mid_spoke: float = float(gap_first) + float(gap) * 0.5 - 0.5
	return rotation_at(fan) + mid_spoke * (TAU / float(n))

## Colisión jugador-vs-rayo. Solo en active; dentro del radio; ángulo del
## jugador sobre un rayo sólido (ancho del rayo ~26px => halfwidth angular).
## El OJO del hub (dist < EYE_RADIUS) es seguro SIEMPRE — y es GRANDE (~90px):
## cerca del hub los rayos son angularmente enormes (atan2(13, 34) ~ 21°),
## así que un ojo chico no puede ser seguro; JSAB usa un ojo generoso.
const EYE_RADIUS: float = 90.0
static func hits_player(fan: Dictionary, player: Vector2) -> bool:
	if str(fan.get("state", "")) != "active":
		return false
	var hub: Vector2 = fan["pos"]
	var d: Vector2 = player - hub
	var dist: float = d.length()
	if dist > float(fan["radius"]) or dist < EYE_RADIUS:
		return false   # dentro del ojo del hub es seguro (el ojo del huracán)
	var ang: float = atan2(d.y, d.x)
	var n: int = int(fan.get("spokes", 8))
	var gap: int = int(fan.get("gap_spokes", 2))
	var gap_first: int = int(fan.get("gap_first", 0))
	var rot: float = rotation_at(fan)
	# Ancho angular del rayo: ~13px de halfwidth, medido en el PUNTO más
	# cercano del jugador al rayo (borde interno del rayo a EYE_RADIUS +
	# halfwidth): el ojo (dist < 34) es seguro de verdad.
	var spoke_half: float = atan2(13.0, maxf(dist, EYE_RADIUS + 13.0))
	var spoke_arc: float = TAU / float(n)
	# El hueco ocupa [gap_first, gap_first+gap) mod n. Un rayo k es sólido
	# si k no cae en el arco del hueco.
	var rel: float = fposmod(ang - rot, TAU)
	var k_f: float = rel / spoke_arc
	# Distancia angular del jugador al centro de cada rayo cercano:
	for k in range(-1, 2):
		var kk: int = (int(round(k_f)) + k) % n
		if kk < 0:
			kk += n
		var in_gap: bool = false
		for g in range(gap):
			if (gap_first + g) % n == kk:
				in_gap = true
				break
		if in_gap:
			continue
		var center: float = float(kk) * spoke_arc
		var dist_ang: float = absf(fposmod(rel - center + PI, TAU) - PI)
		if dist_ang < spoke_half:
			return true
	return false
