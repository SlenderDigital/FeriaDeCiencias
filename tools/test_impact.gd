extends SceneTree
## test_impact.gd — Tarea 8 del plan JSAB (headless): el impacto se SIENTE.
## Contrato:
## 1) Cada setpiece marca sus activaciones con `just_activated` (para que
##    Gameplay enganche flash + trauma sin acoplar el motor a la lógica).
## 2) ImpactFeel.gd (motor puro): el trauma dekampe en el beat, la
##    intensidad escala con la energía de la sección y DECAE a cero en
##    exactamente 2 beats; el flash es un valor 0..1 que también decae.
## 3) El hit-stop NUNCA desincroniza el reloj: la canción sigue siendo la
##    fuente de verdad (get_playback_position), el hit-stop congela SÓLO la
##    escena — y nunca se apila (un golpe = una pausa).
## 4) Justicia del hit-stop: máximo 0.05s, y sólo con iframes activos (nunca
##    durante un telegraph, nunca dos veces seguidas sin iframe).

func _initialize() -> void:
	var fails: Array[String] = []

	# --- 1) Los setpieces marcan just_activated ---
	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var bl: float = song.beat_interval
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true
	var saw_flag := false
	for b in [16, 32, 64, 128, 208]:
		controller.wall_active = false
		var sp: Array[Dictionary] = controller.spawns_at(chart.beat_times[b], b, Color.WHITE)
		for s in sp:
			if bool(s.get("setpiece_phase", false)) or bool(s.get("mini_jab", false)):
				saw_flag = true
				if not s.has("just_activated"):
					fails.append("setpiece/jab sin just_activated: %s" % str(s.get("type", "")))
	if not saw_flag:
		fails.append("RED: no salió ningún setpiece para inspeccionar")

	# --- 2) MOTOR ImpactFeel ---
	var logic: GDScript = load("res://scripts/ImpactFeel.gd")
	if logic == null:
		fails.append("RED: ImpactFeel.gd no existe")
		_finish(fails)
		return

	# 2a) un impacto de setpiece: trauma que escala con la energía
	var im: Dictionary = logic.new_impact(1.0, 0.85)   # (energy, section_energy)
	var t_max: float = float(im["trauma"])
	if t_max <= 0.0 or t_max > 1.0:
		fails.append("trauma fuera de rango (0..1]: %.3f" % t_max)
	var low: Dictionary = logic.new_impact(1.0, 0.30)
	if float(low["trauma"]) >= t_max:
		fails.append("el trauma NO escala con la energía (0.30 -> %.3f >= 0.85 -> %.3f)" % [float(low["trauma"]), t_max])
	if float(im["flash"]) <= 0.0:
		fails.append("sin flash: el impacto no se ve")

	# 2b) el trauma DECAE a cero en exactamente 2 beats
	var st: Dictionary = {"trauma": t_max, "flash": float(im["flash"]), "shake_time": 0.0, "energy": 0.85}
	var elapsed: float = 0.0
	var dt: float = 1.0 / 60.0
	var guard: int = 0
	var zero_at: float = -1.0
	while guard < 1000:
		guard += 1
		logic.step(st, dt, bl)
		elapsed += dt
		if zero_at < 0.0 and float(st["trauma"]) <= 0.001:
			zero_at = elapsed
		if elapsed > 3.0 * bl:
			break
	if zero_at < 0.0:
		fails.append("el trauma nunca llega a cero")
	else:
		var beats_to_zero: float = zero_at / bl
		if beats_to_zero < 1.7 or beats_to_zero > 2.4:
			fails.append("el trauma dura %.2f beats (debe ser ~2)" % beats_to_zero)
	if float(st["flash"]) > 0.001:
		fails.append("el flash no decayó a cero (%.3f)" % float(st["flash"]))
	# 2c) el trauma NUNCA crece solo (monótono decreciente)
	var st2: Dictionary = {"trauma": 0.8, "flash": 0.5, "shake_time": 0.0, "energy": 0.8}
	var prev: float = 0.8
	var grew := false
	for i in range(int(2.0 * bl / dt) + 10):
		logic.step(st2, dt, bl)
		if float(st2["trauma"]) > prev + 0.001:
			grew = true
		prev = float(st2["trauma"])
	if grew:
		fails.append("el trauma CRECIÓ sin impacto (debe ser sólo decaimiento)")

	# --- 3) hit-stop: congela la ESCENA, no la canción, y no se apila ---
	# song_time viene de la posición de reproducción del audio: un hit-stop
	# que lo alterara desincronizaría todo el nivel. Verificamos el contrato
	# declarativo del motor.
	var ss: GDScript = load("res://scripts/ImpactFeel.gd")
	var freeze_music: bool = bool(logic.get("FREEZES_MUSIC_CLOCK"))
	if freeze_music:
		fails.append("FREEZES_MUSIC_CLOCK = true: el hit-stop no puede tocar el reloj de audio")
	var max_stop: float = float(logic.get("MAX_HITSTOP_SEC"))
	if max_stop <= 0.0 or max_stop > 0.05:
		fails.append("MAX_HITSTOP_SEC = %.3f (debe ser >0 y <= 0.05)" % max_stop)

	# --- 4) la pausa se pide con iframes y no se apila ---
	var hs: Dictionary = logic.request_hitstop(0.02, true, 0.0)    # (dur, iframes, remaining)
	if float(hs["applied"]) <= 0.0:
		fails.append("un hit con iframes no pidió hit-stop")
	var hs2: Dictionary = logic.request_hitstop(0.02, true, float(hs["remaining"]))
	if float(hs2["applied"]) > 0.0:
		fails.append("el hit-stop se APILÓ (ya había una pausa viva)")
	var hs3: Dictionary = logic.request_hitstop(0.02, false, 0.0)  # sin iframes = durante telegraph
	if float(hs3["applied"]) > 0.0:
		fails.append("hit-stop pedido sin iframes (durante un telegraph no debe congelar)")

	# --- 5) REGRESIÓN DEL FREEZE INFINITO (bug real, cazado en T9) ---
	# El hit-stop congela con delta=0. Si su propio contador se decrementara
	# con ESE delta, nunca llegaría a cero y el juego quedaría congelado
	# para siempre. Gameplay lo resuelve con un TIMESTAMP real
	# (_hitstop_until); este test verifica que el patrón peligroso no volvió.
	var src: String = FileAccess.get_file_as_string("res://scripts/Gameplay.gd")
	if src.contains("_hitstop_remaining"):
		fails.append("Gameplay volvió a _hitstop_remaining (contado con delta = freeze infinito)")
	if not src.contains("_hitstop_until"):
		fails.append("Gameplay no usa el timestamp real _hitstop_until")
	var real_freeze: Dictionary = logic.request_hitstop(0.05, true, 0.0)
	if float(real_freeze["applied"]) != float(logic.MAX_HITSTOP_SEC):
		fails.append("la pausa aplicada no dura exactamente MAX_HITSTOP_SEC")

	_finish(fails)

func _finish(fails: Array[String]) -> void:
	if fails.is_empty():
		print("[IMPACT] PASS — trauma escala y decae en 2 beats, flash decae, hit-stop no apila ni toca el reloj de audio")
		quit(0)
	else:
		for f in fails:
			print("[IMPACT] FAIL: %s" % f)
		quit(1)
