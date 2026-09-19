class_name ProceduralSong
extends RefCounted
## ProceduralSong — Compone UNA canción completa (síntesis PCM) y su chart.
## Una sola fuente de datos (BPM, estructura de compases, energía por sección,
## progresión armónica) genera el audio Y el nivel: la sincronía es exacta
## porque ambos comparten los mismos enteros (beats/downbeats/frases/sections).

## --- Parámetros globales de la composición ---
const RATE: int = 12000                # mono 12kHz, estética chiptune, render rápido
const BARS_PER_PHRASE: int = 4
# Progresión vi-IV-I-V (Am - F - C - G): movimiento armónico real.
# Cada entrada es la tríada [raíz, tercera, quinta] en semitonos relativos a A2.
const CHORD_PROG: Array = [
	[0.0, 3.0, 7.0],   # Am  (A, C, E)
	[-4.0, 0.0, 3.0],  # F   (F, A, C)
	[3.0, 7.0, 10.0],  # C   (C, E, G)
	[-2.0, 2.0, 5.0],  # G   (G, B, D)
]
const A2: float = 110.0
# Motivo del lead (2 compases, 16 pasos de corchea): índices a la tríada del
# compás [0=raíz, 1=tercera, 2=quinta, 3=octava]. Siempre en la armonía porque
# usa los tonos del acorde; la variación de octava sale del índice de compás
# (determinista: mismo seed -> misma canción).
# Contorno: subida raíz->3ra->5ta->octava, toque alto, respuesta descendente.
const LEAD_MOTIF: Array = [0, 1, 2, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 2, 0]

var bpm: float = 128.0
var beat_interval: float = 0.46875
var bar_len: float = 1.875
var total_bars: int = 0
var total_beats: int = 0
var duration: float = 0.0
var sections: Array[Dictionary] = []   # {name,start_bar,bars,energy}
var _noise_state: int = 0

func _noise_next() -> float:
	## LCG determinista propio (independiente del RNG global del juego)
	_noise_state = (_noise_state * 1103515245 + 12345) & 0x7FFFFFFF
	var r: float = float(_noise_state) / 2147483648.0
	return r * 2.0 - 1.0

func _init(seed: int, bpm_val: float = 128.0) -> void:
	bpm = bpm_val
	beat_interval = 60.0 / bpm
	bar_len = beat_interval * 4.0
	_noise_state = 1337 ^ int(seed)
	_build_structure()

func _build_structure() -> void:
	## Estructura: intro -> build -> drop -> breakdown -> drop2 -> outro
	sections = []
	_add_section("intro", 4, 0.35)
	_add_section("build", 8, 0.6)
	_add_section("drop", 16, 0.85)
	_add_section("breakdown", 8, 0.5)
	_add_section("drop2", 16, 0.9)
	_add_section("outro", 4, 0.3)
	total_bars = 0
	for s in sections:
		total_bars += int(s["bars"])
	total_beats = total_bars * 4
	duration = float(total_bars) * bar_len

func _add_section(name: String, bars: int, energy: float) -> void:
	var start_bar: int = 0
	for s in sections:
		start_bar += int(s["bars"])
	sections.append({
		"name": name, "start_bar": start_bar, "bars": bars, "energy": energy
	})

func _bar_start(bar: int) -> float:
	return float(bar) * bar_len

func _chord_of_bar(bar: int) -> Array:
	## Triada del compas: la progresion (Am-F-C-G) cambia de acorde cada 2 compases.
	return CHORD_PROG[(bar / 2) % CHORD_PROG.size()]

func _section_of_bar(bar: int) -> Dictionary:
	for s in sections:
		var sb: int = int(s["start_bar"])
		var nb: int = int(s["bars"])
		if bar >= sb and bar < sb + nb:
			return s
	return sections[sections.size() - 1]

## --- Generador del chart (mismos datos -> mismo nivel) ---
func build_chart() -> ChartData:
	var cd := ChartData.new()
	cd.bpm = bpm
	cd.duration = duration
	for b in range(total_bars):
		var bar_t: float = _bar_start(b)
		for k in range(4):
			cd.beat_times.append(bar_t + float(k) * beat_interval)
			cd.downbeat.append(k == 0)
		cd.bars.append(b * 4)
		if b % BARS_PER_PHRASE == 0:
			cd.phrases.append(b * 4)
	for s in sections:
		var s0: float = _bar_start(int(s["start_bar"]))
		var s1: float = _bar_start(int(s["start_bar"]) + int(s["bars"]))
		var energy: float = float(s["energy"])
		cd.sections.append({"name": s["name"], "start": s0, "end": s1, "energy": energy})
		cd.level_sections.append(_level_section(s["name"], s0, s1, energy))
	for p in cd.phrases:
		var sp_pattern: String = "closing_perimeter"
		if (p / 4) % 8 == 0:
			sp_pattern = "laser_telegraph"
		cd.setpieces.append({
			"beat": p, "bar": p / 4, "time": cd.beat_times[p],
			"pattern": sp_pattern
		})
	cd._validate()
	return cd

func _level_section(name: String, s0: float, s1: float, energy: float) -> Dictionary:
	## Convierte energía musical en dificultad: pools y densidad coreografiados.
	## Sin targets: todo lo que spawnea es peligro (esquivar es el único juego).
	if energy < 0.45:
		return {"name": name, "start": s0, "end": s1, "energy": energy,
			"pattern_pool": ["saw"], "density": 0.3}
	elif energy < 0.65:
		return {"name": name, "start": s0, "end": s1, "energy": energy,
			"pattern_pool": ["saw", "drifter_swarm"], "density": 0.5}
	elif energy < 0.8:
		return {"name": name, "start": s0, "end": s1, "energy": energy,
			"pattern_pool": ["stripe_wall", "saw", "drifter_swarm"], "density": 0.62}
	return {"name": name, "start": s0, "end": s1, "energy": energy,
		"pattern_pool": ["stripe_wall", "saw", "drifter_swarm", "homing", "hazard_wall"], "density": 0.75}

## --- Síntesis: renderiza la canción a PCM 16-bit ---
func render_audio() -> AudioStreamWAV:
	print("[ProceduralSong] Componiendo %.0fs @ %dHz (%d compases)..." % [duration, RATE, total_bars])
	var total_samples: int = int(RATE * (duration + 0.8))
	var buf_kick := _new_buf(total_samples)
	var buf_drum := _new_buf(total_samples)   # snare + hats + riser/crash
	var buf_bass := _new_buf(total_samples)
	var buf_lead := _new_buf(total_samples)
	var buf_pad := _new_buf(total_samples)

	for b in range(total_bars):
		var sec := _section_of_bar(b)
		var energy: float = float(sec.get("energy", 0.5))
		var sname: String = String(sec.get("name", ""))
		var bar_t: float = _bar_start(b)
		var chord: Array = _chord_of_bar(b)
		var root_f: float = A2 * pow(2.0, float(chord[0]) / 12.0)
		var third_f: float = A2 * pow(2.0, float(chord[1]) / 12.0)
		var fifth_f: float = A2 * pow(2.0, float(chord[2]) / 12.0)

		# KICK: 4-piso en drops; intro/outro/breakdown solo en 1 y 3
		if energy >= 0.6:
			for k in range(4):
				_render_kick(buf_kick, bar_t + float(k) * beat_interval)
		else:
			_render_kick(buf_kick, bar_t)
			_render_kick(buf_kick, bar_t + 2.0 * beat_interval)

		# SNARE en 2 y 4 (el breakdown respira sin caja)
		if energy >= 0.5 and sname != "breakdown":
			_render_snare(buf_drum, bar_t + beat_interval)
			_render_snare(buf_drum, bar_t + 3.0 * beat_interval)

		# HATS: corcheas + OPEN HAT en el offbeat (soul del drop EDM)
		if energy >= 0.45:
			for k in range(8):
				_render_hat(buf_drum, bar_t + float(k) * beat_interval * 0.5, energy * 0.7)
			if energy >= 0.75:
				_render_ohat(buf_drum, bar_t + beat_interval * 0.5)
				_render_ohat(buf_drum, bar_t + beat_interval * 2.5)
		if energy >= 0.8:
			for k in range(16):
				_render_hat(buf_drum, bar_t + float(k) * beat_interval * 0.25, energy * 0.35)

		# BASS offbeat EDM: el kick lleva el beat, el bajo empuja en los "y"
		var bass_amp: float = 0.85 + 0.4 * energy
		for k in range(8):
			if k % 2 == 0:
				continue
			var bf: float = root_f
			if k == 7 and energy >= 0.6:
				bf = fifth_f  # empuje a la quinta antes del compas siguiente
			_render_bass(buf_bass, bar_t + float(k) * beat_interval * 0.5, bf, bass_amp)

		# ARP sobre el ACORDE (root-3ra-5ta-3ra, +1 octava por beat)
		var lead_gain: float = clampf((energy - 0.42) / 0.45, 0.0, 1.0)
		if lead_gain > 0.01:
			var oct_shift: int = 12 if sname == "drop2" else 0
			for k in range(16):
				var deg: int = [0, 1, 2, 1][k % 4]
				var octv: int = ((k / 4) % 2) * 12
				var f: float = A2 * 2.0 * pow(2.0, (float(chord[deg]) + float(octv + oct_shift)) / 12.0)
				_render_lead(buf_lead, bar_t + float(k) * beat_interval * 0.25, f, lead_gain)

		# PAD: TRIADA completa (root + 3ra + 5ta)
		var pad_gain: float = 1.0 - energy * 0.4
		_render_pad3(buf_pad, bar_t, bar_len, [root_f, third_f * 2.0, fifth_f * 2.0], pad_gain)

		# RISER: ultimo compas antes de cada drop (tension -> impacto)
		if b + 1 < total_bars:
			var nxt := _section_of_bar(b + 1)
			if String(nxt.get("name", "")) in ["drop", "drop2"] and int(nxt.get("start_bar", -1)) == b + 1:
				_render_riser(buf_drum, bar_t, bar_len)
		# IMPACTO: crash + bombo grave en la entrada de drop/drop2
		if sname in ["drop", "drop2"] and int(sec.get("start_bar", -1)) == b:
			_render_crash(buf_drum, bar_t)
			_render_impact(buf_kick, bar_t)

		# HOOK del lead: 2 compases on / 2 off en build y breakdown (pregunta),
		# siempre on en drop/drop2 (estribillo). En intro/outro calla: el tema
		# respira y el hook entra como novedad en el build.
		if sname == "build" or sname == "breakdown":
			if b % 4 < 2:
				_render_lead2(buf_lead, b, bar_t, bar_len, chord)
		elif sname == "drop" or sname == "drop2":
			_render_lead2(buf_lead, b, bar_t, bar_len, chord)

	# --- Mezcla final con headroom y fade global ---
	var master: float = 0.66
	var buf_out := _new_buf(total_samples)
	var peak: int = 0
	for i in range(total_samples):
		var idx: int = i * 2
		var v: int = _s16(buf_kick, idx) + _s16(buf_drum, idx) + _s16(buf_bass, idx)
		v += _s16(buf_lead, idx) + _s16(buf_pad, idx)
		var t: float = float(i) / float(RATE)
		var fade: float = 1.0
		if t < 0.5:
			fade = t / 0.5
		var rem: float = duration + 0.8 - t
		if rem < 1.0:
			fade = minf(fade, rem / 1.0)
		var sv: float = float(v) * master * fade
		var out_v: int = int(clampf(sv, -32767.0, 32767.0))
		peak = maxi(peak, absi(out_v))
		_w16(buf_out, idx, out_v)

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = buf_out
	print("[ProceduralSong] Lista: %d muestras, %.1fs, peak=%d/32767." % [total_samples, duration, peak])
	return stream

func _new_buf(total_samples: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	b.resize(total_samples * 2)
	return b

func _s16(buf: PackedByteArray, idx: int) -> int:
	var v: int = buf[idx] | (buf[idx + 1] << 8)
	if v >= 32768:
		v -= 65536
	return v

func _w16(buf: PackedByteArray, idx: int, v: int) -> void:
	buf[idx] = v & 0xFF
	buf[idx + 1] = (v >> 8) & 0xFF

## --- Instrumentos ---
func _render_kick(buf: PackedByteArray, t0: float) -> void:
	# Bombo: sine con drop 110->42Hz + transiente seco (el "downbeat" audible)
	var dur_s: float = 0.20
	var n: int = int(RATE * dur_s)
	var start_idx: int = int(t0 * float(RATE)) * 2
	var amp: float = 23000.0
	var phase: float = 0.0
	for i in range(n):
		var tt: float = float(i) / float(RATE)
		var prog: float = tt / dur_s
		var f: float = lerp(110.0, 42.0, prog)
		phase += TAU * f / float(RATE)
		if phase > TAU:
			phase -= TAU
		var env: float = exp(-8.0 * tt)
		var click: float = 0.0
		if tt < 0.006:
			click = 1.0 - tt / 0.006
		var sv: float = (sin(phase) * env * 0.85 + click * 0.4) * amp
		var idx: int = start_idx + i * 2
		var cur: int = _s16(buf, idx) + int(sv)
		_w16(buf, idx, clampi(cur, -32767, 32767))

func _render_snare(buf: PackedByteArray, t0: float) -> void:
	var dur_s: float = 0.12
	var n: int = int(RATE * dur_s)
	var start_idx: int = int(t0 * float(RATE)) * 2
	var amp: float = 11000.0
	for i in range(n):
		var tt: float = float(i) / float(RATE)
		var env: float = exp(-14.0 * tt)
		var body: float = sin(TAU * 190.0 * tt)
		var sv: float = (_noise_next() * 0.75 + body * 0.35) * env * amp
		var idx: int = start_idx + i * 2
		var cur: int = _s16(buf, idx) + int(sv)
		_w16(buf, idx, clampi(cur, -32767, 32767))

func _render_hat(buf: PackedByteArray, t0: float, gain: float) -> void:
	var dur_s: float = 0.045
	var n: int = int(RATE * dur_s)
	var start_idx: int = int(t0 * float(RATE)) * 2
	var amp: float = 9500.0 * gain
	for i in range(n):
		var tt: float = float(i) / float(RATE)
		var env: float = exp(-42.0 * tt)
		var sv: float = _noise_next() * env * amp * 0.28
		var idx: int = start_idx + i * 2
		var cur: int = _s16(buf, idx) + int(sv)
		_w16(buf, idx, clampi(cur, -32767, 32767))

func _render_bass(buf: PackedByteArray, t0: float, freq: float, gain: float) -> void:
	var dur_s: float = 0.15
	var n: int = int(RATE * dur_s)
	var start_idx: int = int(t0 * float(RATE)) * 2
	var amp: float = 11500.0 * gain
	var phase: float = 0.0
	for i in range(n):
		var tt: float = float(i) / float(RATE)
		phase += TAU * freq / float(RATE)
		if phase > TAU:
			phase -= TAU
		var env: float = exp(-13.0 * tt)
		var w: float = 1.0 if sin(phase) >= 0.0 else -1.0
		var sv: float = (w * 0.7 + sin(phase) * 0.3) * env * amp
		var idx: int = start_idx + i * 2
		var cur: int = _s16(buf, idx) + int(sv)
		_w16(buf, idx, clampi(cur, -32767, 32767))

func _render_lead2(buf: PackedByteArray, bar: int, t0: float, dur: float, chord: Array) -> void:
	## Hook principal: square con vibrato + eco de corchea con puntillo.
	## El motivo son indices a la triada del compas (LEAD_MOTIF): siempre en la
	## armonia. Determinista: la variacion de octava sale del indice de compas.
	var step_dur: float = dur / 8.0
	var echo_dur: float = step_dur * 1.5   # corchea con puntillo: el eco baila
	var start_idx: int = int(t0 * float(RATE)) * 2
	var echo_start: int = start_idx + int(echo_dur * float(RATE)) * 2
	var total_n: int = int(dur * float(RATE))
	var semi: Array = [float(chord[0]), float(chord[1]), float(chord[2])]
	# 2 compases de motivo, segunda vuelta una octava arriba (pregunta/respuesta)
	var octave_up: float = 12.0 if (bar % 4 >= 2) else 0.0
	var amp: float = 1500.0
	var vib_rate: float = 5.5
	var vib_depth: float = 0.35   # semitonos de vaiven
	for s in range(16):
		var deg: int = int(LEAD_MOTIF[s % LEAD_MOTIF.size()])
		var base_semi: float = semi[mini(deg, 2)] + (12.0 if deg >= 3 else 0.0)
		var note_semi: float = base_semi + octave_up
		var st0: int = start_idx + int((float(s) * step_dur) * float(RATE)) * 2
		var st1: int = start_idx + int((float(s + 1) * step_dur) * float(RATE)) * 2
		var phase: float = 0.0
		for idx in range(st0, st1, 2):
			var tt: float = float(idx - st0) / float(maxi(st1 - st0, 2))
			var vib: float = sin(TAU * vib_rate * float(idx - st0) / float(RATE)) * vib_depth
			phase += TAU * (A2 * pow(2.0, (note_semi + 12.0 + vib) / 12.0)) / float(RATE)
			if phase > TAU:
				phase -= TAU
			var sq: float = 0.6 if sin(phase) >= 0.0 else -0.6
			var env: float = minf(float(idx - st0) / (0.012 * float(RATE)), 1.0) * (1.0 - tt * 0.55)
			var sv: float = (sq + sin(phase * 0.5) * 0.25) * env * amp
			var cur: int = _s16(buf, idx) + int(sv)
			_w16(buf, idx, clampi(cur, -32767, 32767))
	# Eco: una repeticion atenuada (0.32) desplazada una corchea con puntillo
	var echo_n: int = mini(total_n * 2, (start_idx + total_n * 2) - echo_start)
	var di: int = 0
	while di < echo_n:
		var sidx: int = start_idx + di
		var didx: int = echo_start + di
		var sv: float = float(_s16(buf, sidx)) * 0.25
		var cur: int = _s16(buf, didx) + int(sv)
		_w16(buf, didx, clampi(cur, -32767, 32767))
		di += 2


func _render_lead(buf: PackedByteArray, t0: float, freq: float, gain: float) -> void:
	var dur_s: float = 0.11
	var n: int = int(RATE * dur_s)
	var start_idx: int = int(t0 * float(RATE)) * 2
	var amp: float = 8000.0 * gain
	var phase: float = 0.0
	var phase2: float = 0.0
	for i in range(n):
		var tt: float = float(i) / float(RATE)
		phase += TAU * freq / float(RATE)
		phase2 += TAU * freq * 1.005 / float(RATE)
		if phase > TAU:
			phase -= TAU
		if phase2 > TAU:
			phase2 -= TAU
		var env: float = exp(-22.0 * tt)
		var w1: float = 1.0 if sin(phase) >= 0.0 else -1.0
		var w2: float = 1.0 if sin(phase2) >= 0.0 else -1.0
		var sv: float = (w1 * 0.55 + w2 * 0.45) * env * amp
		var idx: int = start_idx + i * 2
		var cur: int = _s16(buf, idx) + int(sv)
		_w16(buf, idx, clampi(cur, -32767, 32767))

func _render_pad3(buf: PackedByteArray, t0: float, dur: float, freqs: Array, gain: float) -> void:
	## Pad con TRIADA completa (root + 3ra + 5ta): armonia real, no pedal vacio.
	var n: int = int(RATE * dur)
	var start_idx: int = int(t0 * float(RATE)) * 2
	var amp: float = 2200.0 * gain
	var nph: int = freqs.size()
	var phases: PackedFloat32Array = PackedFloat32Array()
	phases.resize(nph)
	for i in range(n):
		var tt: float = float(i) / float(RATE)
		var sv: float = 0.0
		for j in range(nph):
			phases[j] += TAU * float(freqs[j]) / float(RATE)
			if phases[j] > TAU:
				phases[j] -= TAU
			sv += sin(phases[j]) * (0.5 if j == 0 else 0.25)
		# Ataque 0.35s, release 0.25s al final del compas
		var env: float = minf(tt / 0.35, 1.0) * minf((dur - tt) / 0.25, 1.0)
		var out_v: float = sv * env * amp
		var idx: int = start_idx + i * 2
		var cur: int = _s16(buf, idx) + int(out_v)
		_w16(buf, idx, clampi(cur, -32767, 32767))

func _render_ohat(buf: PackedByteArray, t0: float) -> void:
	## Open hat: ruido con caida lenta (~0.16s), el "tss" que abre el groove.
	var dur_s: float = 0.16
	var n: int = int(RATE * dur_s)
	var start_idx: int = int(t0 * float(RATE)) * 2
	var amp: float = 5200.0
	for i in range(n):
		var tt: float = float(i) / float(RATE)
		var env: float = exp(-18.0 * tt)
		var sv: float = _noise_next() * env * amp
		var idx: int = start_idx + i * 2
		var cur: int = _s16(buf, idx) + int(sv)
		_w16(buf, idx, clampi(cur, -32767, 32767))

func _render_riser(buf: PackedByteArray, t0: float, dur: float) -> void:
	## Riser: ruido creciente + seno que sube 2 octavas durante el compas.
	var n: int = int(RATE * dur)
	var start_idx: int = int(t0 * float(RATE)) * 2
	var amp: float = 3400.0
	var phase: float = 0.0
	for i in range(n):
		var tt: float = float(i) / float(RATE)
		var prog: float = tt / dur
		var f: float = lerp(220.0, 880.0, prog * prog)
		phase += TAU * f / float(RATE)
		if phase > TAU:
			phase -= TAU
		var env: float = prog * prog
		var sv: float = (_noise_next() * 0.55 + sin(phase) * 0.45) * env * amp
		var idx: int = start_idx + i * 2
		var cur: int = _s16(buf, idx) + int(sv)
		_w16(buf, idx, clampi(cur, -32767, 32767))

func _render_crash(buf: PackedByteArray, t0: float) -> void:
	## Crash de entrada: ruido con caida larga (~0.9s).
	var dur_s: float = 0.9
	var n: int = int(RATE * dur_s)
	var start_idx: int = int(t0 * float(RATE)) * 2
	var amp: float = 4200.0
	for i in range(n):
		var tt: float = float(i) / float(RATE)
		var env: float = exp(-4.0 * tt)
		var sv: float = _noise_next() * env * amp
		var idx: int = start_idx + i * 2
		var cur: int = _s16(buf, idx) + int(sv)
		_w16(buf, idx, clampi(cur, -32767, 32767))

func _render_impact(buf: PackedByteArray, t0: float) -> void:
	## Impacto grave: bombo profundo 60->28Hz con cola larga.
	var dur_s: float = 0.55
	var n: int = int(RATE * dur_s)
	var start_idx: int = int(t0 * float(RATE)) * 2
	var amp: float = 18000.0
	var phase: float = 0.0
	for i in range(n):
		var tt: float = float(i) / float(RATE)
		var prog: float = tt / dur_s
		var f: float = lerp(60.0, 28.0, prog)
		phase += TAU * f / float(RATE)
		if phase > TAU:
			phase -= TAU
		var env: float = exp(-5.0 * tt)
		var sv: float = sin(phase) * env * amp
		var idx: int = start_idx + i * 2
		var cur: int = _s16(buf, idx) + int(sv)
		_w16(buf, idx, clampi(cur, -32767, 32767))
