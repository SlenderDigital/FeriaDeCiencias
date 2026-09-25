class_name SqueezeLogic
extends RefCounted
## SqueezeLogic — física pura del corredor bilateral (JSAB T5). Dos paredes
## que aprietan el espacio jugable. El juego y el test headless usan ESTOS
## mismos pasos/anchos/colisiones.

## Un paso: telegraph -> active -> fade -> done (umbrales en BEATS).
static func step(sc: Dictionary, delta: float, beat_len: float) -> Dictionary:
	sc["state_time"] = float(sc.get("state_time", 0.0)) + delta
	var st: String = str(sc.get("state", "telegraph"))
	var st_t: float = float(sc.get("state_time", 0.0))
	if st == "telegraph" and st_t >= float(sc.get("telegraph_beats", 2)) * beat_len:
		sc["state"] = "active"
		sc["state_time"] = 0.0
		sc["is_hazard"] = true
	elif st == "active" and st_t >= float(sc.get("active_beats", 4)) * beat_len:
		sc["state"] = "fade"
		sc["state_time"] = 0.0
		sc["is_hazard"] = false
	elif st == "fade" and st_t >= float(sc.get("fade_beats", 2)) * beat_len:
		sc["state"] = "done"
		sc["is_hazard"] = false
	return sc

## Progreso del cierre 0..1 (0 en telegraph/fade-decay, 1 = bolsillo mínimo).
static func close_factor(sc: Dictionary) -> float:
	var st: String = str(sc.get("state", "telegraph"))
	var bl: float = float(sc.get("beat_len", 0.46875))
	if st == "telegraph":
		# el aviso ya insinúa el cierre (12% visible desde el frame 1)
		return 0.12 * clampf(float(sc.get("state_time", 0.0)) / maxf(float(sc.get("telegraph_beats", 2)) * bl, 0.001), 0.0, 1.0)
	if st == "fade":
		return 1.0 - clampf(float(sc.get("state_time", 0.0)) / maxf(float(sc.get("fade_beats", 2)) * bl, 0.001), 0.0, 1.0)
	if st == "done":
		return 0.0
	var prog: float = clampf(float(sc.get("state_time", 0.0)) / (float(sc.get("active_beats", 4)) * bl), 0.0, 1.0)
	return prog * prog * (3.0 - 2.0 * prog)   # easeInOut: aprieta y frena en el beat

## Ancho del pasillo LIBRE ahora (nunca baja de min_gap: la fairness que
## garantiza que el nivel aprieta pero no mata).
static func gap_size(sc: Dictionary) -> float:
	var start_gap: float = float(sc.get("start_gap", 1000.0))
	var min_gap: float = float(sc.get("min_gap", 420.0))
	return maxf(min_gap, start_gap - (start_gap - min_gap) * close_factor(sc))

## Centro del pasillo ahora: el punto medio se desplaza hacia el de destino
## conforme se cierra (las dos paredes seteinclinan, no viajan en paralelo).
static func gap_center(sc: Dictionary) -> float:
	var mid: float = float(sc.get("play_w", 1280.0)) * 0.5
	var drift: float = float(sc.get("gap_drift", 0.0))
	return mid + drift * close_factor(sc)

## Posición de la banda izquierda/derecha (su borde interior).
static func band_inner_edges(sc: Dictionary) -> Vector2:
	var g: float = gap_size(sc)
	var c: float = gap_center(sc)
	return Vector2(c - g * 0.5, c + g * 0.5)

## Colisión: dentro de la banda izquierda o derecha => hit. Sólo active.
static func hits_player(sc: Dictionary, player: Vector2) -> bool:
	if str(sc.get("state", "")) != "active":
		return false
	var edges: Vector2 = band_inner_edges(sc)
	var half: float = float(sc.get("band_half", 46.0))
	return player.x <= edges.x or player.x >= edges.y
