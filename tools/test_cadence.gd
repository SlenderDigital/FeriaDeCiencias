extends SceneTree
## test_cadence.gd — Tarea 3 (headless): la CADENCIA de spawns sigue a la
## energía de la sección del chart. First Light (ProceduralSong 128 BPM):
##   intro  (bars  0..3)  energía 0.35 → 1 encuentro cada 2 compases
##   outro  (bars 52..55) energía 0.30 → 1 encuentro cada 2 compases
##   drop   (bars 12..27) energía 0.85 → 1 por compás + acento en beats 2/4
##   drop2  (bars 36..51) energía 0.90 → 1 por compás + acento en beats 2/4
## El helper _section_intent es la única fuente de la cadencia.

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true
	var bl: float = chart.beat_times[1] - chart.beat_times[0]

	# Recorrer todos los beats (sin gates de muro: la cadencia se prueba sola;
	# los muros no alteran el gate de easy_mode) y registrar qué beats de la
	# ruta spawns_at emitieron algo.
	var emitting_beats: Dictionary = {}   # beat_idx -> spawn count vía spawns_at
	var accent_beats: Dictionary = {}     # beat_idx -> true si hubo saw de acento
	var next_beat_idx := 0
	var t_time := 0.0
	var dt := 0.05
	var max_beats := chart.beat_times.size()
	while next_beat_idx < max_beats and t_time <= chart.duration:
		while next_beat_idx < max_beats and chart.beat_times[next_beat_idx] <= t_time:
			controller.wall_active = false
			var s: Array[Dictionary] = controller.spawns_at(chart.beat_times[next_beat_idx], next_beat_idx, Color.WHITE)
			if not s.is_empty():
				emitting_beats[next_beat_idx] = s.size()
				# Acento = saw extra en beats 2/4 dentro del compás (bp 1 o 3)
				var bp: int = next_beat_idx % 4
				if bp == 1 or bp == 3:
					var saw_extra: int = 0
					for one in s:
						if one.get("type", "") == "saw":
							saw_extra += 1
					if saw_extra > 0:
						accent_beats[next_beat_idx] = true
			next_beat_idx += 1
		t_time += dt

	# --- Aserciones por sección (índices de BEAT; compás = 4 beats) ---
	# Intro: beats 0..15. Encuentros SOLO en downbeats de compases pares
	# (beat %8==0). Ningún otro beat de la intro puede emitir.
	for bi in range(0, 16):
		if bi % 8 == 0:
			if not emitting_beats.has(bi):
				fails.append("intro: beat %d (compás par) debería emitir y no emitió" % bi)
		else:
			if emitting_beats.has(bi):
				fails.append("intro: beat %d NO debería emitir (cadencia 2 compases) y emitió" % bi)
	# Outro: beats 208..223, misma regla.
	for bi in range(208, 224):
		if bi % 8 == 0:
			if not emitting_beats.has(bi):
				fails.append("outro: beat %d debería emitir y no emitió" % bi)
		else:
			if emitting_beats.has(bi):
				fails.append("outro: beat %d NO debería emitir y emitió" % bi)
	# Drop (beats 48..111) y drop2 (144..207): TODOS los downbeats emiten.
	for bi in range(48, 112):
		if bi % 4 == 0 and not emitting_beats.has(bi):
			fails.append("drop: downbeat %d debería emitir y no emitió" % bi)
	for bi in range(144, 208):
		if bi % 4 == 0 and not emitting_beats.has(bi):
			fails.append("drop2: downbeat %d debería emitir y no emitió" % bi)
	# Densidad relativa: drop debe tener ~2x más encuentros por compás que la
	# intro. Intro: 16 beats / 8 = 2 encuentros. Drop: 16 compases = 16 downbeats
	# (menos phrase beats que cuentan igual) => 16. Ratio esperado 8x en beats,
	# con gates de muro en el juego real baja, pero en este test sin muros debe
	# ser estrictamente mayor: drop_downbeat_count > intro_encounter_count.
	var drop_downbeats: int = 0
	for bi in range(48, 112):
		if bi % 4 == 0 and emitting_beats.has(bi):
			drop_downbeats += 1
	var intro_encounters: int = 0
	for bi in range(0, 16, 8):
		if emitting_beats.has(bi):
			intro_encounters += 1
	if drop_downbeats <= intro_encounters:
		fails.append("densidad: drop (%d) no supera a intro (%d)" % [drop_downbeats, intro_encounters])
	# Acentos: en drops, AL MENOS un acento en beats 2/4 del compás.
	var drop_accents: int = 0
	for bi in accent_beats:
		if bi >= 48 and bi < 112:
			drop_accents += 1
	if drop_accents == 0:
		fails.append("drop: sin acentos en beats 2/4 (energy>=0.8 debería apretar)")

	# --- Helper puro: _section_intent sobre tiempos reales del chart ---
	# intro t=1s -> bars_per_encounter 2, accent false
	# drop  t=30s -> 1, true ; drop2 t=80s -> 1, true ; outro t=100s -> 2, false
	var i_intro: Dictionary = controller._section_intent(1.0)
	var i_drop: Dictionary = controller._section_intent(30.0)
	var i_drop2: Dictionary = controller._section_intent(80.0)
	var i_outro: Dictionary = controller._section_intent(100.0)
	if int(i_intro["bars_per_encounter"]) != 2 or bool(i_intro["accent_beats"]):
		fails.append("intent intro: %s" % str(i_intro))
	if int(i_drop["bars_per_encounter"]) != 1 or not bool(i_drop["accent_beats"]):
		fails.append("intent drop: %s" % str(i_drop))
	if int(i_drop2["bars_per_encounter"]) != 1 or not bool(i_drop2["accent_beats"]):
		fails.append("intent drop2: %s" % str(i_drop2))
	if int(i_outro["bars_per_encounter"]) != 2 or bool(i_outro["accent_beats"]):
		fails.append("intent outro: %s" % str(i_outro))

	if fails.is_empty():
		print("[CADENCE] PASS — intro/outro 1/2 compases, drops 1/compás + acentos; helper OK")
		quit(0)
	else:
		for f in fails:
			print("[CADENCE] FAIL: %s" % f)
		quit(1)
