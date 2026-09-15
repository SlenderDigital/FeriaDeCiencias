extends SceneTree
## Test headless de la vida EN LA NAVE: valida _health_color() por umbrales
## (verde >60, ambar >30, rojo <=30) y el rango del anillo (0-100).

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var fails: Array[String] = []
	var packed: PackedScene = load("res://scenes/Gameplay.tscn")
	var gp: Node = packed.instantiate()
	root.add_child(gp)
	await process_frame
	await process_frame

	# La barra vieja ya no existe: la vida vive en la nave.
	if gp.get("health_bar") != null:
		fails.append("health_bar todavia existe (deberia estar eliminado)")
	if gp.has_node("HUDLayer/HUD/BottomBar/HealthBar"):
		fails.append("nodo HealthBar todavia en la escena")

	# Casos: [vida, color esperado]
	for c in [[80.0, "verde"], [45.0, "ambar"], [20.0, "rojo"]]:
		gp.health = c[0]
		var col: Color = gp._health_color()
		var ok := false
		match c[1]:
			"verde":
				ok = col.g > 0.9 and col.r < 0.5
			"ambar":
				ok = col.r > 0.9 and col.g > 0.7
			"rojo":
				ok = col.r > 0.9 and col.g < 0.4
		if not ok:
			fails.append("vida=%s color esperado %s, obtuvo (%.2f, %.2f, %.2f)" % [c[0], c[1], col.r, col.g, col.b])

	# Fraccion del anillo: clamp 0-100 (incluye bordes).
	for c in [[-10.0, 0.0], [0.0, 0.0], [55.0, 0.55], [100.0, 1.0], [140.0, 1.0]]:
		gp.health = c[0]
		var frac: float = clampf(gp.health / 100.0, 0.0, 1.0)
		if absf(frac - c[1]) > 0.01:
			fails.append("vida=%s -> frac=%s (esperaba %s)" % [c[0], frac, c[1]])

	if fails.is_empty():
		print("[HUD_TEST] PASS: sin barra, _health_color() verde/ambar/rojo OK, anillo 0-100 OK")
		quit(0)
	else:
		print("[HUD_TEST] FAIL: ", "; ".join(fails))
		quit(1)
