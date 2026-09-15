extends SceneTree
## Test headless del HUD de vida: instancia Gameplay.tscn y valida la barra
## (tipo, rango, valores y color del relleno segun nivel de vida).

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var fails: Array[String] = []
	var packed: PackedScene = load("res://scenes/Gameplay.tscn")
	var gp: Node = packed.instantiate()
	root.add_child(gp)
	await process_frame
	await process_frame

	var hb: ProgressBar = gp.health_bar
	if hb == null:
		print("[HUD_TEST] FAIL: health_bar es null")
		quit(1)
		return
	if hb.get_class() != "ProgressBar":
		fails.append("tipo=%s (esperaba ProgressBar)" % hb.get_class())
	if hb.max_value != 100.0:
		fails.append("max_value=%s" % hb.max_value)
	if hb.show_percentage:
		fails.append("show_percentage=true")

	# Casos: [vida, chequeo del color del relleno]
	for c in [[80.0, "verde"], [45.0, "ambar"], [20.0, "rojo"]]:
		gp.health = c[0]
		gp._update_health_hud()
		if absf(hb.value - c[0]) > 0.01:
			fails.append("vida=%s -> bar.value=%s" % [c[0], hb.value])
		var fill: StyleBoxFlat = hb.get_theme_stylebox("fill")
		var bg: StyleBoxFlat = hb.get_theme_stylebox("background")
		if fill == null or bg == null:
			fails.append("vida=%s sin stylebox fill/background" % c[0])
			continue
		var col: Color = fill.bg_color
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

	if fails.is_empty():
		print("[HUD_TEST] PASS: barra tipo ProgressBar, rango 0-100, sin porcentaje, colores verde/ambar/rojo OK")
		quit(0)
	else:
		print("[HUD_TEST] FAIL: ", "; ".join(fails))
		quit(1)
