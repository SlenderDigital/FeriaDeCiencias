class_name SweepLogic
extends RefCounted
## SweepLogic — física pura del láser que barre (JSAB T3). Sin nodos:
## Gameplay y el test headless usan ESTOS mismos pasos/ángulos/colisión.

## Un paso: avanza state_time y resuelve telegraph -> active -> fade -> done
## (umbrales en BEATS, como todos los setpieces).
static func step(sw: Dictionary, delta: float, beat_len: float) -> Dictionary:
	sw["state_time"] = float(sw.get("state_time", 0.0)) + delta
	var st: String = str(sw.get("state", "telegraph"))
	var st_t: float = float(sw.get("state_time", 0.0))
	if st == "telegraph" and st_t >= float(sw.get("telegraph_beats", 2)) * beat_len:
		sw["state"] = "active"
		sw["state_time"] = 0.0
		sw["is_hazard"] = true
	elif st == "active" and st_t >= float(sw.get("active_beats", 4)) * beat_len:
		sw["state"] = "fade"
		sw["state_time"] = 0.0
		sw["is_hazard"] = false
	elif st == "fade" and st_t >= float(sw.get("fade_beats", 2)) * beat_len:
		sw["state"] = "done"
		sw["is_hazard"] = false
	return sw

## Ángulo del haz AHORA. En telegraph muestra ang_start (el arco se dibuja
## aparte); en active interpola linealmente ang_start->ang_end con el
## progreso de la ventana; en fade queda en ang_end (decae en alpha).
static func beam_angle(sw: Dictionary) -> float:
	var a0: float = float(sw.get("ang_start", 0.0))
	var a1: float = float(sw.get("ang_end", 0.0))
	var st: String = str(sw.get("state", "telegraph"))
	var bl: float = float(sw.get("beat_len", 0.46875))
	if st == "telegraph":
		return a0
	if st == "fade" or st == "done":
		return a1
	var prog: float = clampf(float(sw.get("state_time", 0.0)) / (float(sw.get("active_beats", 4)) * bl), 0.0, 1.0)
	# easing suave (easeInOut) para que arranque y frene EN el beat: el cruce
	# por el centro de la pantalla es legible, no un latigazo.
	var eased: float = prog * prog * (3.0 - 2.0 * prog)
	return a0 + (a1 - a0) * eased

## Colisión jugador-vs-haz. Solo en active; distancia perpendicular al
## SEMI-rayo (el haz nace en el hub y va beam_len hacia el ángulo actual).
static func hits_player(sw: Dictionary, player: Vector2) -> bool:
	if str(sw.get("state", "")) != "active":
		return false
	var hub: Vector2 = sw["pos"]
	var dir: Vector2 = Vector2.from_angle(beam_angle(sw))
	var to_p: Vector2 = player - hub
	var along: float = to_p.dot(dir)
	if along < 0.0 or along > float(sw.get("beam_len", 1700.0)):
		return false
	var perp: float = absf(to_p.dot(Vector2(-dir.y, dir.x)))
	return perp < 12.0 + 16.0   # halfwidth del haz + radio del jugador
