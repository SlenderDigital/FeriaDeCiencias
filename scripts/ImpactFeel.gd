class_name ImpactFeel
extends RefCounted
## ImpactFeel — el impacto se SIENTE (JSAB T8). Motor puro: trauma de
## cámara (shake), flash blanco y hit-stop. El juego y el test headless usan
## ESTE MISMO código, así que lo que el test prueba es lo que se siente.
##
## REGLA DE ORO: el hit-stop congela la ESCENA, nunca el reloj de la música.
## La canción es la fuente de verdad (song_time = get_playback_position());
## si el hit-stop lo tocara, todo el nivel se desincronizaría.

## El hit-stop NUNCA toca el reloj de audio: la canción sigue sonando y el
## reloj del nivel sigue avanzando aunque la escena se congele.
const FREEZES_MUSIC_CLOCK: bool = false
## Tope duro del hit-stop: 50ms. Más que eso se siente como un tirón, no
## como un golpe.
const MAX_HITSTOP_SEC: float = 0.05
## El trauma decae a cero en esteMany beats (2 = el "golpe" se disipa rápido,
## como en JSAB: el impacto es un latido, no un temblor largo).
const DECAY_BEATS: float = 2.0

## Un impacto nuevo: trauma + flash, escalados por la energía de la sección.
## kind_scale: 1.0 = setpiece ancla, 0.45 = mini-jab (puntuación, no momento).
static func new_impact(energy: float, section_energy: float, kind_scale: float = 1.0) -> Dictionary:
	var e: float = clampf(energy, 0.0, 1.0)
	var se: float = clampf(section_energy, 0.0, 1.0)
	# el trauma escala con la energía de la sección (un golpe en el breakdown
	# no se siente como un golpe en el drop) y con el tipo de evento.
	var trauma: float = clampf((0.22 + 0.68 * se) * e * kind_scale, 0.0, 1.0)
	var flash: float = clampf((0.10 + 0.45 * se) * e * kind_scale, 0.0, 1.0)
	# las bases viajan con el estado: un impacto nuevo RE-ARMA el decaimiento
	# (si no, el trauma del golpe anterior seguiría decaendo el nuevo).
	return {"trauma": trauma, "flash": flash, "shake_time": 0.0, "energy": se,
		"_base_trauma": trauma, "_base_flash": flash}

## Un paso: decae trauma y flash hasta cero en exactamente DECAY_BEATS.
## Se decae sobre el VALOR INICIAL del impacto, no sobre un span fijo: así
## un golpe de 0.3 y uno de 1.0 duran ambos 2 beats (el "golpe" se disipa,
## no se estira en proporción a su fuerza).
static func step(st: Dictionary, delta: float, beat_len: float) -> Dictionary:
	var decay_span: float = maxf(DECAY_BEATS * beat_len, 0.001)
	# Si el estado nunca fue armeado (el llamador no pasó por arm()), la base
	# es el trauma/flash ACTUAL: el primer step no debe perder un decaimiento.
	if not st.has("_base_trauma"):
		st["_base_trauma"] = float(st.get("trauma", 0.0))
		st["_base_flash"] = float(st.get("flash", 0.0))
		st["shake_time"] = 0.0
	var t_ratio: float = clampf(float(st.get("shake_time", 0.0)) / decay_span, 0.0, 1.0)
	# el impacto original se guarda para decaer proporcionalmente a él
	var base_trauma: float = float(st.get("_base_trauma", 0.0))
	var base_flash: float = float(st.get("_base_flash", 0.0))
	st["trauma"] = maxf(0.0, base_trauma * (1.0 - t_ratio))
	# flash: se va antes que el temblor (el blanco desaparece primero)
	st["flash"] = maxf(0.0, base_flash * clampf(1.0 - t_ratio * 1.6, 0.0, 1.0))
	st["shake_time"] = float(st.get("shake_time", 0.0)) + delta
	return st

## Preparar un estado de impacto listo para step() (guarda las bases del
## decaimiento). Lo llama Gameplay al DETECTAR una activación.
static func arm(st: Dictionary) -> Dictionary:
	st["_base_trauma"] = float(st.get("trauma", 0.0))
	st["_base_flash"] = float(st.get("flash", 0.0))
	st["shake_time"] = 0.0
	return st

## Pide una pausa de impacto. Se APLICA sólo si:
##   - hay iframes (o sea: es un golpe real contra el jugador, no un telegraph)
##   - no hay ya una pausa viva (nunca se apila)
##   - la duración respeta el tope duro
## Devuelve {applied, remaining}: `applied` es la duración a congelar AHORA
## (0 = no congelar) y `remaining` es lo que queda de la pausa previa — el
## llamador lo pasa de vuelta en el siguiente frame, y así es imposible
## apilar dos pausas.
static func request_hitstop(dur: float, has_iframes: bool, remaining: float) -> Dictionary:
	var capped: float = clampf(dur, 0.0, MAX_HITSTOP_SEC)
	if not has_iframes:
		return {"applied": 0.0, "remaining": maxf(remaining, 0.0)}
	if remaining > 0.0:
		# ya hay una pausa viva: NO se apila, sólo se informa que sigue
		return {"applied": 0.0, "remaining": remaining}
	return {"applied": capped, "remaining": capped}

## Desplazamiento de cámara por trauma (ruido determinista, no aleatorio:
## el temblor debe ser reproducible frame a frame). max_offset en px.
static func shake_offset(st: Dictionary, max_offset: float = 26.0) -> Vector2:
	var trauma: float = clampf(float(st.get("trauma", 0.0)), 0.0, 1.0)
	if trauma <= 0.001:
		return Vector2.ZERO
	var t: float = float(st.get("shake_time", 0.0))
	# dos senos incomensurables = temblor orgánico sin librerias
	var x: float = sin(t * 47.0) * 0.6 + sin(t * 23.0) * 0.4
	var y: float = sin(t * 41.0 + 1.3) * 0.6 + sin(t * 19.0 + 0.7) * 0.4
	return Vector2(x, y) * (max_offset * trauma * trauma)
