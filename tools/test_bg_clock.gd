extends SceneTree
## test_bg_clock.gd — Tarea 1 (headless): el fondo debe pulsar con el reloj
## REAL de la canción (set_song_clock) y NO llamar a SoundManager.play_beat()
## en modo canción. Al liberar el reloj, el fallback del menú vuelve a pulsar.
## NOTA: el cuerpo vive en _initialize() (no en _init): los autoloads
## (GameManager/SoundManager) se registran DESPUÉS del _init del SceneTree
## custom, y NeonBackground.gd los referencia — compilarlo antes fallaría.
## Se asertan CONTADORES (no anillos): sin viewport real los anillos se
## cullean al instante (max_radius=0), pero los contadores son el contrato.

func _initialize() -> void:
	var fails: Array[String] = []

	# --- Test 1: contrato del NeonBackground en modo canción ---
	var bg_script: GDScript = load("res://scripts/NeonBackground.gd")
	var bg: Control = bg_script.new()
	root.add_child(bg)
	var beat_len: float = 60.0 / 128.0

	# Modo canción: alimentar beats 0..4. La activación consume el índice 0
	# (set_song_clock inicializa _last_beat_idx), así que cada beat NUEVO
	# emite un pulso: índices 1,2,3,4 => 4 pulsos, cero sonido.
	for i in range(5):
		bg.set_song_clock(float(i) * beat_len + 0.01, beat_len)
		bg._process(0.016)
	if bg.song_clock_pulses != 4:
		fails.append("song-clock: esperaba 4 pulsos (idx 1..4), hubo %d" % bg.song_clock_pulses)
	if bg.song_clock_sound_calls != 0:
		fails.append("song-clock: no debe llamar play_beat (hubo %d)" % bg.song_clock_sound_calls)

	# Mismo beat repetido: sin pulsos extra (el índice no avanza).
	var pulses_before: int = bg.song_clock_pulses
	bg.set_song_clock(4.0 * beat_len + 0.02, beat_len)
	bg._process(0.016)
	if bg.song_clock_pulses != pulses_before:
		fails.append("song-clock: pulso duplicado dentro del mismo beat")
	bg.queue_free()

	# --- Test 2: fallback del menú tras clear_song_clock ---
	var bg2: Control = bg_script.new()
	root.add_child(bg2)
	bg2.set_song_clock(0.001, beat_len)
	bg2.clear_song_clock()
	# Simular ~2s de frames del menú (130 × 16ms = 2.08s ÷ 0.46875 ≈ 4 beats):
	# el acumulador propio debe volver a disparar (sonido del menú), y el
	# contador de pulsos de canción debe quedar en 0.
	for i in range(130):
		bg2._process(0.016)
	if bg2.song_clock_pulses != 0:
		fails.append("fallback: song_clock_pulses debe ser 0 tras clear (hubo %d)" % bg2.song_clock_pulses)
	if bg2.song_clock_sound_calls < 3:
		fails.append("fallback: el metrónomo del menú no disparó (sonidos=%d, esperaba >=3)" % bg2.song_clock_sound_calls)
	bg2.queue_free()

	if fails.is_empty():
		print("[BG-CLOCK] PASS — song-clock pulsa con la canción, sin doble golpe; fallback del menú intacto")
		quit(0)
	else:
		for f in fails:
			print("[BG-CLOCK] FAIL: %s" % f)
		quit(1)
