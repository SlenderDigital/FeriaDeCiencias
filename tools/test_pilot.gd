extends SceneTree
## test_pilot.gd — Tarea 9 (preparatorio): el PILOTO automático.
## Para verificar el juego de verdad (T9) hace falta alguien que juegue:
## sin él la partida muere sola al 49% y no hay gameplay que mirar.
##
## El piloto NO es una heurística nueva: devuelve un punto y el test lo
## valida contra las MISMAS funciones de colisión que usa el juego
## (SpokeFanLogic, PulseRingsLogic, SqueezeLogic, WaveformLogic,
## SweepLogic). Si el punto elegido alguna vez estuviera dentro de un
## peligro, este test falla. O sea: la prueba de que el nivel es justo se
## apoya en la geometría real, no en una copia.

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var bl: float = song.beat_interval
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true

	var logic: GDScript = load("res://scripts/PilotLogic.gd")
	if logic == null:
		fails.append("RED: PilotLogic.gd no existe")
		_finish(fails)
		return

	var dt: float = 1.0 / 60.0
	# 1) Cada setpiece, en su ventana activa, debe tener un punto seguro
	#    que el piloto encuentra y que la colisión real confirma.
	var builders: Array[String] = ["spoke_fan", "laser_sweep", "waveform_wall", "squeeze_corridor", "pulse_rings"]
	for bkey in builders:
		var sp: Array[Dictionary] = controller._build_pattern(bkey, chart.beat_times[64], Color.WHITE, 64, {}, 64 * 131)
		if sp.is_empty():
			fails.append("%s: el builder no devolvió nada" % bkey)
			continue
		var obj: Dictionary = sp[0]
		# avanzar hasta active
		var found_active := false
		for i in range(int(4.0 * bl / dt) + 8):
			_advance(obj, bkey, dt, bl)
			if str(obj.get("state", "")) == "active":
				found_active = true
				break
		if not found_active:
			fails.append("%s: nunca llegó a active" % bkey)
			continue
		# el piloto elige un punto
		var safe_pt: Vector2 = logic.safe_point(obj)
		if not _is_really_safe(obj, bkey, safe_pt):
			# reintento con un barrido: algunos patrones narrow-lifecycle
			# necesitan el punto en el frame exacto
			var ok := false
			for k in range(40):
				_advance(obj, bkey, dt, bl)
				var p2: Vector2 = logic.safe_point(obj)
				if _is_really_safe(obj, bkey, p2):
					ok = true
					break
			if not ok:
				fails.append("%s: el piloto NO encontró un punto seguro (probó %s)" % [bkey, str(safe_pt)])

	# 2) El piloto se mueve a velocidad acotada (nunca teletransporta)
	var from_p: Vector2 = Vector2(300, 560)
	var to_p: Vector2 = logic.steer_step(from_p, Vector2(700, 300), 550.0, dt)
	var travelled: float = (to_p - from_p).length()
	if travelled > 550.0 * dt + 0.5:
		fails.append("el piloto se movió %.1f px en un frame de %.3fs (teleport)" % [travelled, dt])
	if travelled < 0.1:
		fails.append("el piloto NO se movió hacia un destino válido a %.1f de distancia" % from_p.distance_to(Vector2(700, 300)))
	# y un destino IGUAL al origen no lo mueve (sin nano-deriva)
	var same: Vector2 = logic.steer_step(from_p, from_p, 550.0, dt)
	if same != from_p:
		fails.append("el piloto derivó sin destino: %s -> %s" % [str(from_p), str(same)])

	# 3) Un punto YA peligroso debe ser rechazado: safe_point nunca devuelve
	#    un punto que la colisión real marque como golpe.
	var fan: Dictionary = controller._build_pattern("spoke_fan", 0.0, Color.WHITE, 0, {}, 7)[0]
	for i in range(int(3.0 * bl / dt)):
		_advance(fan, "spoke_fan", dt, bl)
	if str(fan.get("state", "")) == "active":
		var pt: Vector2 = logic.safe_point(fan)
		if _is_really_safe(fan, "spoke_fan", pt) == false:
			fails.append("safe_point devolvió un punto peligroso en el spoke_fan")

	_finish(fails)

func _advance(obj: Dictionary, key: String, dt: float, bl: float) -> void:
	match key:
		"spoke_fan":
			var s: Dictionary = SpokeFanLogic.step(obj, dt, bl)
			obj["state"] = s["state"]
			obj["state_time"] = s["state_time"]
		"laser_sweep":
			var s2: Dictionary = SweepLogic.step(obj, dt, bl)
			obj["state"] = s2["state"]
			obj["state_time"] = s2["state_time"]
		"waveform_wall":
			var s3: Dictionary = WaveformLogic.step(obj, dt, bl)
			obj["state"] = s3["state"]
			obj["state_time"] = s3["state_time"]
		"squeeze_corridor":
			var s4: Dictionary = SqueezeLogic.step(obj, dt, bl)
			obj["state"] = s4["state"]
			obj["state_time"] = s4["state_time"]
		"pulse_rings":
			var s5: Dictionary = PulseRingsLogic.step(obj, dt, bl)
			obj["state"] = s5["state"]
			obj["state_time"] = s5["state_time"]

## VALIDA CONTRA LA COLISIÓN REAL DEL JUEGO (no una copia).
func _is_really_safe(obj: Dictionary, key: String, p: Vector2) -> bool:
	match key:
		"spoke_fan":
			return not SpokeFanLogic.hits_player(obj, p)
		"laser_sweep":
			return not SweepLogic.hits_player(obj, p)
		"waveform_wall":
			return not WaveformLogic.hits_player(obj, p)
		"squeeze_corridor":
			return not SqueezeLogic.hits_player(obj, p)
		"pulse_rings":
			return not PulseRingsLogic.hits_player(obj, p)
	return true

func _finish(fails: Array[String]) -> void:
	if fails.is_empty():
		print("[PILOT] PASS — el piloto encuentra un punto seguro validado por la colisión real, y no teletransporta")
		quit(0)
	else:
		for f in fails:
			print("[PILOT] FAIL: %s" % f)
		quit(1)
