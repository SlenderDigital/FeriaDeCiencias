extends SceneTree
## test_structure_follow.gd — Tarea 8 (headless): la coreografía lee la
## ESTRUCTURA de la canción desde el chart, no rangos de compás hardcodeados.
## Prueba del plan: acortar el drop de 16 a 8 compases y verificar que el
## nivel sigue a la sección — el breakdown empieza donde la CANCIÓN dice,
## no donde una constante vieja lo espera. Sin editar el nivel.

func _initialize() -> void:
	var fails: Array[String] = []

	# --- Canción alterada: drop de 16 -> 8 compases (44 compases total) ---
	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	# Parche estructural directo sobre el chart (lo que haría un cambio en
	# ProceduralSong._build_structure): recortar el drop a la mitad.
	var drop_sec: Dictionary = {}
	for s in chart.level_sections:
		if str(s["name"]) == "drop":
			drop_sec = s
	if drop_sec.is_empty():
		fails.append("no se encontró la sección drop")
		return _finish(fails)
	var half_len: float = (float(drop_sec["end"]) - float(drop_sec["start"])) * 0.5
	var new_end: float = float(drop_sec["end"]) - half_len
	drop_sec["end"] = new_end
	# El breakdown debe correr donde ahora queda el hueco: mover su start.
	for s in chart.level_sections:
		if str(s["name"]) == "breakdown":
			s["start"] = new_end
			s["end"] = float(s["end"]) - half_len
		elif str(s["name"]) in ["drop2", "outro"]:
			s["start"] = float(s["start"]) - half_len
			s["end"] = float(s["end"]) - half_len
	# Beats: truncar donde acaba el outro nuevo.
	var last_end: float = 0.0
	for s in chart.level_sections:
		last_end = maxf(last_end, float(s["end"]))
	var keep_beats: int = 0
	for i in range(chart.beat_times.size()):
		if chart.beat_times[i] < last_end:
			keep_beats += 1
	chart.beat_times.resize(keep_beats)
	chart.downbeat.resize(keep_beats)

	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true

	# --- El nivel SIGUE: en cada beat de encuentro, el patrón debe ser de la
	# sección que la CANCIÓN dice que está sonando ahí ---
	# Bar 16-19 (mitad del drop viejo): con el drop corto, eso ya es
	# BREAKDOWN. Si el nivel estuviera hardcodeado, tiraría stripe_wall ahí
	# (drop viejo abría con muro en su bar 12; el breakdown NO tira muros).
	var t_breakdown_start: float = new_end + 0.1
	var beats_checked: int = 0
	for i in range(chart.beat_times.size()):
		var t: float = chart.beat_times[i]
		if t < t_breakdown_start or t >= t_breakdown_start + 4.0 * 4 * (60.0 / 128.0):
			continue  # solo los primeros 4 compases tras el nuevo límite
		if i % 4 != 0:
			continue
		var pat: String = controller._first_light_pattern(i, t)
		if pat == "stripe_wall":
			fails.append("bar %d tras drop corto: patrón %s — muro en pleno BREAKDOWN (hardcode sobrevive)" % [i / 4, pat])
		beats_checked += 1
	if beats_checked < 3:
		fails.append("pocos compases verificados (%d) — el test no ejercita la zona" % beats_checked)

	# --- Y el drop corto sigue SIENDO drop: su primer compás abre con muro ---
	var drop_first_bar: int = int(float(drop_sec["start"]) / (4.0 * (60.0 / 128.0)))
	var first_beat: int = drop_first_bar * 4
	if first_beat < chart.beat_times.size():
		var pat0: String = controller._first_light_pattern(first_beat, chart.beat_times[first_beat])
		if pat0 != "stripe_wall":
			fails.append("drop bar %d abre con %s, esperaba stripe_wall" % [drop_first_bar, pat0])

	_finish(fails)

func _finish(fails: Array[String]) -> void:
	if fails.is_empty():
		print("[STRUCT] PASS — el nivel sigue a la estructura alterada (drop 16→8) sin ediciones")
		quit(0)
	else:
		for f in fails:
			print("[STRUCT] FAIL: %s" % f)
		quit(1)
