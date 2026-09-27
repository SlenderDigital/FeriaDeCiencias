extends SceneTree
## test_song_pulse.gd — Tarea 6 (headless): la canción MEJORADA cumple su
## contrato audible: (1) sidechain — curva de duck: cae a (1-depth) en el
## golpe y se recupera exponencial; la MEZCLA sin bombo bombea (A/B contra
## sc_depth=0); (2) redoble de caja creciente antes de cada drop (A/B del
## último compás pre-drop contra un compás normal del build); (3) arp de
## corcheas en los compases 3-4 de la intro (A/B contra 1-2); (4) sin
## clipping (peak < 32767); (5) el chart no cambia (el nivel sigue igual).

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var bl: float = song.beat_interval
	var stream: AudioStreamWAV = song.render_audio()
	var data: PackedByteArray = stream.data
	var rate: int = stream.mix_rate

	# (0) peak: sin clipping, mezcla no apagada
	if song.last_peak >= 32767:
		fails.append("clipping: peak=%d" % song.last_peak)
	if song.last_peak < 12000:
		fails.append("mezcla sospechosamente baja: peak=%d" % song.last_peak)

	# Helper: RMS de una ventana [t0,t1) de la mezcla final.
	var rms := func(d: PackedByteArray, t0: float, t1: float) -> float:
		var i0: int = int(t0 * rate)
		var i1: int = int(t1 * rate)
		var acc: float = 0.0
		var cnt: int = 0
		for i in range(i0, i1):
			var v: int = d[i * 2] | (d[i * 2 + 1] << 8)
			if v >= 32768:
				v -= 65536
			acc += float(v) * float(v)
			cnt += 1
		return sqrt(acc / float(maxi(cnt, 1)))

	# (1a) Curva de duck: en el golpe cae a ~0.4; a 1 beat se recupera >0.95.
	var g0: float = song._duck_gain_at(0.0, 0.0)
	var g_mid: float = song._duck_gain_at(bl * 0.5, 0.0)
	var g1: float = song._duck_gain_at(bl, 0.0)
	if absf(g0 - (1.0 - song.sc_depth)) > 0.02:
		fails.append("duck: en golpe=%.3f, esperaba %.3f" % [g0, 1.0 - song.sc_depth])
	if not (g0 < g_mid and g_mid < g1 and g1 > 0.9):
		fails.append("duck: no recupera (g0=%.3f g_mid=%.3f g1=%.3f)" % [g0, g_mid, g1])

	# (1b) A/B de la MEZCLA FINAL: mismo song con sidechain apagado; el RMS de
	# la banda SIN bombo (corchea offbeat, t=bl*0.5..bl*0.9 del drop) debe
	# ser MENOR con sidechain que sin él — el duck la aplasta tras el golpe.
	var drop_bar_t: float = 12 * 4 * bl
	var with_sc: float = rms.call(data, drop_bar_t + bl * 0.5, drop_bar_t + bl * 0.9)
	var song_flat := ProceduralSong.new(1337, 128.0)
	song_flat.sc_depth = 0.0
	var stream_flat: AudioStreamWAV = song_flat.render_audio()
	var without_sc: float = rms.call(stream_flat.data, drop_bar_t + bl * 0.5, drop_bar_t + bl * 0.9)
	if with_sc >= without_sc * 0.97:
		fails.append("sidechain: banda offbeat con SC (%.0f) no baja vs sin SC (%.0f)" % [with_sc, without_sc])

	# (2) REDOBLE PRE-DROP: RMS por cuarto dentro del último compás antes del
	# drop debe CRECER (crescendo del redoble) y su último cuarto superar el
	# del compás previo (A/B contra bar 10: mismo contenido base, sin redoble).
	var fill_q: Array[float] = []
	for q in range(4):
		fill_q.append(rms.call(data, 11 * 4 * bl + q * bl, 11 * 4 * bl + (q + 1) * bl))
	if not (fill_q[0] < fill_q[3] * 0.95 and fill_q[3] > fill_q[0] * 1.05):
		fails.append("redoble pre-drop: sin crescendo %s" % str(fill_q))
	var prev_q_last: float = rms.call(data, 11 * 4 * bl - bl, 11 * 4 * bl)
	if fill_q[3] < prev_q_last * 1.05:
		fails.append("redoble pre-drop: último cuarto %.0f no supera al compás previo %.0f" % [fill_q[3], prev_q_last])

	# (3) ARP DE INTRO: compases 3-4 (con arp) vs 1-2 (pad+bombo solos).
	var intro_arp_rms: float = rms.call(data, 2 * 4 * bl, 4 * 4 * bl)
	var intro_base_rms: float = rms.call(data, 0.5, 2 * 4 * bl)
	if intro_arp_rms < intro_base_rms * 1.05:
		fails.append("arp intro: RMS %.0f no supera al pad solo %.0f" % [intro_arp_rms, intro_base_rms])

	# (4) Estructura intacta.
	if chart.beat_times.size() != 224:
		fails.append("chart cambió: %d beats (esperaba 224)" % chart.beat_times.size())

	if fails.is_empty():
		print("[SONG] PASS — sidechain bombea (curva+A/B), redoble pre-drop, arp de intro, peak=%d sin clip" % song.last_peak)
		quit(0)
	else:
		for f in fails:
			print("[SONG] FAIL: %s" % f)
		quit(1)
