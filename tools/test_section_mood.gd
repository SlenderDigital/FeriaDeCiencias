extends SceneTree
## test_section_mood.gd — Tarea 5 (headless): los visuales siguen la sección.
## Contrato: NeonBackground._current_grid_color() cambia con la energía y el
## breakdown se enfría; Gameplay expone section_energy/section_name (los
## alimenta _process desde el chart real). Se prueba el plumbing con valores
## de las 6 secciones reales de First Light.

func _initialize() -> void:
	var fails: Array[String] = []

	var bg_script: GDScript = load("res://scripts/NeonBackground.gd")
	var bg: Control = bg_script.new()
	root.add_child(bg)
	var beat_len: float = 60.0 / 128.0
	bg.set_song_clock(1.0, beat_len)  # activar modo canción (como Gameplay)

	# Energías reales de ProceduralSong: intro .35 build .6 drop .85
	# breakdown .5 drop2 .9 outro .3
	var cases := [
		["intro", 0.35], ["build", 0.6], ["drop", 0.85],
		["breakdown", 0.5], ["drop2", 0.9], ["outro", 0.3],
	]
	var lums: Array[float] = []
	var grid_default: Color = bg.grid_color
	for c in cases:
		bg.set_section_mood(c[1], c[0])
		var col: Color = bg._current_grid_color()
		var lum: float = 0.2126 * col.r + 0.7152 * col.g + 0.0722 * col.b
		lums.append(lum)
		# Breakdown: azul frío — B manda claramente sobre R.
		if c[0] == "breakdown":
			if not (col.b > col.r * 1.8):
				fails.append("breakdown no es frío: %s" % str(col))
			# Y más tenue que el drop.
			if lum >= lums[2]:  # drop lum
				fails.append("breakdown (%.2f) no es más tenue que drop (%.2f)" % [lum, lums[2]])
	# Monotonía de brillo con la energía (excepto breakdown, que se enfría):
	# drop2 > drop > build > intro > outro en luminancia de grilla.
	if not (lums[4] > lums[2]):
		fails.append("drop2 (%.3f) no supera a drop (%.3f)" % [lums[4], lums[2]])
	if not (lums[2] > lums[1]):
		fails.append("drop (%.3f) no supera a build (%.3f)" % [lums[2], lums[1]])
	if not (lums[1] > lums[0]):
		fails.append("build (%.3f) no supera a intro (%.3f)" % [lums[1], lums[0]])
	if not (lums[0] > lums[5]):
		fails.append("intro (%.3f) no supera a outro (%.3f)" % [lums[0], lums[5]])

	# clear_song_clock restaura el mood neutro (menú).
	bg.clear_song_clock()
	var col_after: Color = bg._current_grid_color()
	if col_after != grid_default:
		fails.append("clear no restaura grid_color: %s vs %s" % [str(col_after), str(grid_default)])

	bg.queue_free()

	if fails.is_empty():
		print("[MOOD] PASS — brillo monótono con energía, breakdown frío, clear restaura")
		quit(0)
	else:
		for f in fails:
			print("[MOOD] FAIL: %s" % f)
		quit(1)
