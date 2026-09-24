extends SceneTree
## test_render_budget.gd — Tarea 7 (headless): presupuesto de render de la
## canción. Renderiza con la RATE actual del script y mide el tiempo; imprime
## [BUDGET] PASS/FAIL contra el umbral del plan (~2s al arrancar). No cambia
## nada por sí mismo — es la medición con la que se decide la Tarea 7.

const BUDGET_S: float = 2.0

func _initialize() -> void:
	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var t0_msec: int = Time.get_ticks_msec()
	var stream: AudioStreamWAV = song.render_audio()
	var elapsed_s: float = (Time.get_ticks_msec() - t0_msec) / 1000.0
	var ok := elapsed_s <= BUDGET_S and chart.beat_times.size() == 224
	print("[BUDGET] %s — RATE=%d Hz, render=%.2fs (umbral %.1fs), %d samples, peak=%d" % [
		"PASS" if ok else "FAIL", song.RATE, elapsed_s, BUDGET_S,
		stream.data.size() / 2, song.last_peak])
	quit(0 if ok else 1)
