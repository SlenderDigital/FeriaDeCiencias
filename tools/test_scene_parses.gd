extends SceneTree
## test_scene_parses.gd — GUARD de carga de escenas/scripts del juego.
##
## COBERTURA REAL (verificada con el bug reintroducido a propósito):
##   load() de los scripts + instantiate() de Gameplay/MainMenu.
##   Detecta: script inexistente, .tscn roto, instancia nula.
## NO CUBRE (y está medido, no supuesto): los errores de TIPOS en el cuerpo
## de un script ya cargado (p.ej. `var v: Vector2 = mi_metodo()`) — el load
## perezoso de Godot en modo --script no los ve. Para eso está el MCP del
## editor: project_run() arranca el juego de verdad y ESE parse estricto sí
## lo detecta ( Gameplay.gd:543 cayó justo así). Correr `project_run` tras
## tocar Gameplay.gd.
##
## Uso: godot --headless --script tools/test_scene_parses.gd

func _initialize() -> void:
	var fails: Array[String] = []
	for path in [
		"res://scripts/Gameplay.gd",
		"res://scripts/NeonBackground.gd",
		"res://scripts/PatternController.gd",
		"res://scripts/ProceduralSong.gd",
		"res://scripts/ChartData.gd",
		"res://scripts/SoundManager.gd",
		"res://scripts/GameManager.gd",
		"res://scripts/HandTrackingClient.gd",
		"res://scripts/MainMenu.gd",
		"res://scripts/SpokeFanLogic.gd",
		"res://scripts/SweepLogic.gd",
		"res://scripts/WaveformLogic.gd",
		"res://scripts/DevTools.gd",
		"res://scripts/SetpieceRenderer.gd",
	]:
		if load(path) == null:
			fails.append("no carga: %s (parse error o ruta)" % path)
	for scene_path in ["res://scenes/Gameplay.tscn", "res://scenes/MainMenu.tscn"]:
		var ps: PackedScene = load(scene_path)
		if ps == null:
			fails.append("no carga escena: %s" % scene_path)
			continue
		var inst: Node = ps.instantiate()
		if inst == null:
			fails.append("no instancia: %s" % scene_path)
		else:
			if inst.get_script() == null:
				fails.append("instancia sin script: %s" % scene_path)
			inst.free()
	if fails.is_empty():
		print("[PARSE] PASS — 14 scripts cargan + 2 escenas instancian (Gameplay y MainMenu)")
		quit(0)
	else:
		for f in fails:
			print("[PARSE] FAIL: %s" % f)
		quit(1)
