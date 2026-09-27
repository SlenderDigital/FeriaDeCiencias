class_name WaveformLogic
extends RefCounted
## WaveformLogic — física pura del muro de onda (JSAB T4). Sin nodos: el
## juego y el test headless usan ESTOS mismos pasos/alturas/colisiones.

## Un paso: avanza state_time y resuelve telegraph -> active -> fade -> done
## (umbrales en BEATS). En active, el factor de subida es 0 -> 1 sobre la
## ventana active (la onda emerge del fondo y llega a su cresta al final).
static func step(wf: Dictionary, delta: float, beat_len: float) -> Dictionary:
	wf["state_time"] = float(wf.get("state_time", 0.0)) + delta
	var st: String = str(wf.get("state", "telegraph"))
	var st_t: float = float(wf.get("state_time", 0.0))
	if st == "telegraph" and st_t >= float(wf.get("telegraph_beats", 2)) * beat_len:
		wf["state"] = "active"
		wf["state_time"] = 0.0
		wf["is_hazard"] = true
	elif st == "active" and st_t >= float(wf.get("active_beats", 4)) * beat_len:
		wf["state"] = "fade"
		wf["state_time"] = 0.0
		wf["is_hazard"] = false
	elif st == "fade" and st_t >= float(wf.get("fade_beats", 2)) * beat_len:
		wf["state"] = "done"
		wf["is_hazard"] = false
	return wf

## Progreso de subida 0..1 (0 en telegraph/fade-decay, 1 al final de active).
static func rise_factor(wf: Dictionary) -> float:
	var st: String = str(wf.get("state", "telegraph"))
	var bl: float = float(wf.get("beat_len", 0.46875))
	if st == "telegraph":
		# El aviso ya insinúa el perfil COMPLETO (con amplitud legible) desde
		# el frame 1: el jugador tiene que poder ver DÓNDE pasa la onda antes
		# de que llegue. Antes arrancaba en 0.12 y crecía: a t=0 la forma era
		# una banda lisa (space-bunny: "no parece una onda").
		return lerpf(0.30, 0.42, clampf(float(wf.get("state_time", 0.0)) / maxf(float(wf.get("telegraph_beats", 2)) * bl, 0.001), 0.0, 1.0))
	if st == "fade":
		return 1.0 - clampf(float(wf.get("state_time", 0.0)) / maxf(float(wf.get("fade_beats", 2)) * bl, 0.001), 0.0, 1.0)
	if st == "done":
		return 0.0
	var prog: float = clampf(float(wf.get("state_time", 0.0)) / (float(wf.get("active_beats", 4)) * bl), 0.0, 1.0)
	return prog * prog * (3.0 - 2.0 * prog)   # easeInOut: emerge y asienta en el beat

## Altura (Y en pantalla) de la columna index: perfil senoidal desfasado,
## emerging desde base_line, acotado por peak_line. El trough (wave=0)
## queda en base_line y la cresta (wave=1) llega a peak_line.
static func column_height(wf: Dictionary, index: int) -> float:
	var base: float = float(wf.get("base_line", 600.0))
	var peak: float = float(wf.get("peak_line", 430.0))
	var cols: int = int(wf.get("columns", 8))
	var cycles: float = float(wf.get("wave_cycles", 2.0))
	var phase: float = float(wf.get("wave_phase", 0.0))
	var u: float = (float(index) + 0.5) / float(cols)
	# perfil: 0 en los troughs, 1 en las crestas
	var wave: float = 0.5 + 0.5 * sin(u * TAU * cycles + phase)
	var r: float = rise_factor(wf)
	# T9: la amplitud de la onda es legible TODO el tiempo. Antes el perfil se
	# escalaba por rise y, con rise chico, la diferencia trough-cresta era de
	# 1px: el "muro de onda" parecía una línea recta (lo señaló space-bunny).
	# Ahora la forma ya está completa y rise sólo la despliega desde abajo.
	var shaped: float = lerpf(0.35, 1.0, wave)   # aun en telegraph hay forma
	return minf(base - (base - peak) * shaped * r, base)

## Colisión: el jugador está dentro de la columna si su Y está por DEBAJO
## de la altura de la columna en su X, y sólo en active.
static func hits_player(wf: Dictionary, player: Vector2) -> bool:
	if str(wf.get("state", "")) != "active":
		return false
	var cols: int = int(wf.get("columns", 8))
	var col_w: float = float(wf.get("col_w", 100.0))
	var idx: int = clampi(int(player.x / maxf(col_w, 1.0)), 0, cols - 1)
	var h: float = column_height(wf, idx)
	return player.y > h - 10.0
