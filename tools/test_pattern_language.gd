extends SceneTree
## test_pattern_language.gd — T9: la coherencia entre tipos de "enemigos"
## tiene que ser REAL, no un archivo muerto.
##
## El reporte fue "no hay coherencia entre los tipos". La respuesta de JSAB
## es una jerarquía: todo lo letal comparte un lenguaje (rojo + núcleo blanco
## HDR) y cada patrón se diferencia por SILUETA. Este test verifica que esa
## jerarquía existe, está registrada y está CONECTADA al dibujo.
##
## RED si el registro no existe, si un patrón no está, o si la lethality no
## ordena el dibujo como se afirma.

func _initialize() -> void:
	var fails: Array[String] = []

	# 1) El registro existe y cubre TODOS los patrones que el juego emite.
	var logic: GDScript = load("res://scripts/PatternLanguage.gd")
	if logic == null:
		fails.append("RED: PatternLanguage.gd no existe")
		_finish(fails)
		return
	var reg: Dictionary = logic.REGISTRY
	var required: Array[String] = [
		"spoke_fan", "laser_sweep", "waveform_wall", "squeeze_corridor",
		"pulse_rings", "mini_ring", "mini_fan", "stripe_wall",
		"saw", "saw_pair", "saw_weave", "homing", "drifter", "drifter_swarm",
		"perimeter", "closing_perimeter", "laser_telegraph", "laser_beam",
	]
	for r in required:
		if not reg.has(r):
			fails.append("patrón sin registrar en la jerarquía: %s" % r)

	# 2) Lethality en rango y con sentido: un setpiece mata más que un latido.
	for key in reg.keys():
		var e: Dictionary = reg[key]
		var leth: float = float(e.get("lethality", -1.0))
		if leth < 0.0 or leth > 1.0:
			fails.append("%s: lethality %.2f fuera de rango" % [key, leth])
		if str(e.get("silhouette", "")).is_empty():
			fails.append("%s: sin silueta (no se distingue de sus pares)" % key)
		if str(e.get("name", "")).is_empty():
			fails.append("%s: sin nombre legible" % key)
	# los anclas deben matar más que la decoración
	for anchor in ["spoke_fan", "laser_sweep", "stripe_wall", "waveform_wall"]:
		for ammo in ["saw", "drifter", "mini_ring", "mini_fan"]:
			if float(logic.lethality_of(anchor)) <= float(logic.lethality_of(ammo)):
				fails.append("jerarquía rota: %s (%.2f) no mata más que %s (%.2f)" % [
					anchor, float(logic.lethality_of(anchor)),
					ammo, float(logic.lethality_of(ammo))])

	# 3) El ORDEN DE DIBUJO pone lo letal encima (draw_sort).
	var layer: Array[Dictionary] = [
		{"type": "saw"},        # lethality 0.5 -> abajo
		{"type": "spoke_fan"},  # lethality 1.0 -> arriba
		{"type": "drifter"},    # lethality 0.4 -> abajo
	]
	layer.sort_custom(logic.draw_sort)
	var first_type: String = str(layer[0].get("type", ""))
	var last_type: String = str(layer[layer.size() - 1].get("type", ""))
	if float(logic.lethality_of(first_type)) >= float(logic.lethality_of(last_type)):
		fails.append("draw_sort no ordena: primero=%s(%.2f) último=%s(%.2f)" % [
			first_type, float(logic.lethality_of(first_type)),
			last_type, float(logic.lethality_of(last_type))])

	# 4) ESTÁ CONECTADO de verdad: Gameplay lo preloadea y lo USA.
	var src: String = FileAccess.get_file_as_string("res://scripts/Gameplay.gd")
	if not src.contains("preload(\"res://scripts/PatternLanguage.gd\")"):
		fails.append("Gameplay no preloadea PatternLanguage (código muerto)")
	if not src.contains("_PatternLanguage.draw_sort"):
		fails.append("Gameplay no USA draw_sort: el orden de lethalidad no está conectado")
	if not src.contains("_PatternLanguage.lethality_of"):
		fails.append("Gameplay no USA lethality_of: la jerarquía no llega al dibujo")

	# 5) Y la regla de color: la decoración NO puede usar rojo (rompería
	#    "rojo = mata"). Verificamos el fondo.
	var bg: String = FileAccess.get_file_as_string("res://scripts/NeonBackground.gd")
	var part_line: String = ""
	for line in bg.split("\n"):
		if line.strip_edges().begins_with("var col: Color = grid_color if"):
			part_line = line
			break
	if part_line.is_empty():
		fails.append("no se encontró la línea de color de partículas en NeonBackground")
	elif part_line.contains("accent_color"):
		fails.append("las partículas usan accent_color (ROJO/MAGENTA): rompe 'rojo = mata'")

	_finish(fails)

func _finish(fails: Array[String]) -> void:
	if fails.is_empty():
		print("[LANG] PASS — 18 patrones con jerarquía, silueta y lethality; orden de lethalidad conectado; decoración sin rojo")
		quit(0)
	else:
		for f in fails:
			print("[LANG] FAIL: %s" % f)
		quit(1)
