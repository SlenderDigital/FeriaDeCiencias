extends SceneTree
## test_mini_jabs.gd — Tarea 7 del plan JSAB (headless): los MINI-JABS.
## La respuesta directa a "nothing happens": en las barras de alta energía y
## SIN setpiece activo, la pantalla SIEMPRE tiene algo (un anillo expansivo
## mínimo o un abanico de 3 rayos). Contrato:
## 1) spawns_at_bar emite un mini-jab en barras de alta energía cuando no hay
##    setpiece vivo.
## 2) easy_mode (tutorial) NO queda mudo: es la vía por la que el juego
##    arranca, así que también emite jabs (antes devolvía [] siempre).
## 3) INVARIANTE CENTRAL: ningún tramo de 2 compases (8 beats) de sección de
##    alta energía queda sin nada en pantalla (ni setpiece ni jab).
## 4) Un mini-jab es inocuo: nace is_hazard=false, dura poco y no se
##    accumulates (no apila más de 2 jabs vivos).

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var bl: float = song.beat_interval
	var max_beats: int = chart.beat_times.size()

	# --- Simulación completa del nivel en easy_mode, como el E2E ---
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true
	var next_beat: int = 0
	# id -> (die_time, kind) para el setpiece/jab tracker
	var live_kinds: Array[Array] = []    # [die_time, kind]
	var last_activity_beat: int = -99
	var idle_violations: Array[String] = []
	var max_concurrent_jabs: int = 0
	var jab_count: int = 0
	var setpiece_beats: Array[int] = []
	var high_energy_streak: int = 0
	var high_energy_start: int = -1

	while next_beat < max_beats:
		var t: float = chart.beat_times[next_beat]
		var sec: Dictionary = controller._current_section(t)
		var sec_name: String = str(sec.get("name", ""))
		var energy: float = float(sec.get("energy", 0.0)) if not sec.is_empty() else 0.0
		var is_high: bool = energy >= 0.7

		# Podar lo que ya murió
		var kept: Array[Array] = []
		for e in live_kinds:
			if float(e[0]) > t:
				kept.append(e)
		live_kinds = kept

		controller.wall_active = false
		var sp: Array[Dictionary] = controller.spawns_at(t, next_beat, Color.WHITE)
		if next_beat % 4 == 0:
			sp.append_array(controller.spawns_at_bar(t, next_beat, Color.WHITE))

		# Clasificar lo que nació
		var born_anchor := false
		var born_jab := 0
		for s in sp:
			var ty: String = str(s.get("type", ""))
			var is_setpiece: bool = bool(s.get("setpiece_phase", false))
			var mini: bool = bool(s.get("mini_jab", false))
			if is_setpiece or mini:
				# duración estimada: telegraph+active+fade en beats
				var dur_beats: int = int(s.get("telegraph_beats", 0)) + int(s.get("active_beats", 0)) + int(s.get("fade_beats", 0))
				var dur: float = float(maxi(dur_beats, 1)) * bl
				live_kinds.append([t + dur, ty])
				if is_setpiece:
					born_anchor = true
					setpiece_beats.append(next_beat)
				else:
					born_jab += 1
					jab_count += 1
				last_activity_beat = next_beat
				# 4) mini-jab nace inocuo
				if mini and bool(s.get("is_hazard", true)):
					fails.append("mini-jab %s nace peligroso (debe ser aviso inocuo)" % ty)
		var jabs_live: int = 0
		for e in live_kinds:
			if str(e[1]) in ["mini_ring", "mini_fan"]:
				jabs_live += 1
		max_concurrent_jabs = maxi(max_concurrent_jabs, jabs_live)

		# 3) invariante: 2 compases (8 beats) de alta energía sin nada
		if is_high:
			if high_energy_streak == 0:
				high_energy_start = next_beat
			high_energy_streak += 1
		else:
			high_energy_streak = 0
			high_energy_start = -1
		if is_high and not born_anchor and not born_jab and live_kinds.is_empty():
			if next_beat - high_energy_start >= 8:
				idle_violations.append("bar %d (t=%.1f, %s): 8+ beats de alta energía sin nada" % [next_beat, t, sec_name])

		next_beat += 1

	# --- Veredictos ---
	if not controller.has_method("_mini_jab") and not fails.is_empty():
		fails.append("RED: _mini_jab no existe")
	if jab_count == 0:
		fails.append("RED: no se emitió NINGÚN mini-jab en toda la partida (la pantalla sigue muda)")
	if not idle_violations.is_empty():
		for v in idle_violations.slice(0, 4):
			fails.append("idle: %s" % v)
		fails.append("... %d tramos mudos en total" % idle_violations.size())
	if setpiece_beats.is_empty():
		fails.append("RED: ni una sola ancla de setpiece en toda la partida")
	if max_concurrent_jabs > 2:
		fails.append("se apilaron %d mini-jabs vivos (máx 2: no debe saturar)" % max_concurrent_jabs)
	if fails.is_empty():
		print("[JABS] PASS — %d mini-jabs, %d anclas, máximo %d simultáneos, cero tramos mudos de 2 compases" % [jab_count, setpiece_beats.size(), max_concurrent_jabs])
		quit(0)
	else:
		for f in fails:
			print("[JABS] FAIL: %s" % f)
		quit(1)
