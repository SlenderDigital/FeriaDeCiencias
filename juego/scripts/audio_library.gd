extends RefCounted
## Procedural monochrome audio library.
##
## All streams are synthesized in memory so the project keeps zero external
## audio assets. Streams are cached statically and can be prewarmed before a
## scene transition to keep level entry hitch-free.

const MIX_RATE: int = 22050
const MUSIC_BPM: float = 128.0
const BEAT_DURATION: float = 60.0 / MUSIC_BPM
const STEP_DURATION: float = BEAT_DURATION * 0.25
const STEP_SAMPLES: int = 2584
const STEPS_PER_BAR: int = 16
const BAR_SAMPLES: int = STEP_SAMPLES * STEPS_PER_BAR
const BAR_DURATION: float = float(BAR_SAMPLES) / float(MIX_RATE)
const TOTAL_MUSIC_BARS: int = 24

enum MusicSection {
	INTRO = 0,
	VERSE = 1,
	CHORUS = 2,
	BREAKDOWN = 3,
	CLIMAX = 4,
	FINALE = 5,
}

static var _cache: Dictionary = {}


## Builds every stream once. Call from a deferred menu callback so the one-time
## synthesis cost is paid while the player is still in the menu.
static func prewarm() -> void:
	menu()
	hit()
	laser()
	explosion()
	shield_on()
	shield_block()
	shield_break()
	enemy_fire()
	enemy_lunge()
	wall_slam()
	saw_bounce()
	victory()
	game_over()
	music()


static func menu() -> AudioStreamWAV:
	return _cached(&"menu", _make_menu)


static func hit() -> AudioStreamWAV:
	return _cached(&"hit", _make_hit)


static func laser() -> AudioStreamWAV:
	return _cached(&"laser", _make_laser)


static func explosion() -> AudioStreamWAV:
	return _cached(&"explosion", _make_explosion)


static func shield_on() -> AudioStreamWAV:
	return _cached(&"shield_on", _make_shield_on)


static func shield_block() -> AudioStreamWAV:
	return _cached(&"shield_block", _make_shield_block)


static func shield_break() -> AudioStreamWAV:
	return _cached(&"shield_break", _make_shield_break)


static func enemy_fire() -> AudioStreamWAV:
	return _cached(&"enemy_fire", _make_enemy_fire)


static func enemy_lunge() -> AudioStreamWAV:
	return _cached(&"enemy_lunge", _make_enemy_lunge)


static func wall_slam() -> AudioStreamWAV:
	return _cached(&"wall_slam", _make_wall_slam)


static func saw_bounce() -> AudioStreamWAV:
	return _cached(&"saw_bounce", _make_saw_bounce)


static func victory() -> AudioStreamWAV:
	return _cached(&"victory", _make_victory)


static func game_over() -> AudioStreamWAV:
	return _cached(&"game_over", _make_game_over)


static func music() -> AudioStreamWAV:
	return _cached(&"music", _make_music)


## Returns the active musical section (0..5) at the given level elapsed time in seconds.
static func get_music_section(elapsed_seconds: float) -> int:
	var wrapped: float = fposmod(maxf(elapsed_seconds, 0.0), float(TOTAL_MUSIC_BARS) * BAR_DURATION)
	var bar_idx: int = clampi(int(floor(wrapped / BAR_DURATION)), 0, TOTAL_MUSIC_BARS - 1)
	if bar_idx < 4:
		return MusicSection.INTRO
	if bar_idx < 8:
		return MusicSection.VERSE
	if bar_idx < 12:
		return MusicSection.CHORUS
	if bar_idx < 16:
		return MusicSection.BREAKDOWN
	if bar_idx < 22:
		return MusicSection.CLIMAX
	return MusicSection.FINALE


## Returns a human-readable label for the musical section active at elapsed_seconds.
static func get_music_section_name(elapsed_seconds: float) -> String:
	match get_music_section(elapsed_seconds):
		MusicSection.INTRO:
			return "IGNITION"
		MusicSection.VERSE:
			return "VECTOR DRIVE"
		MusicSection.CHORUS:
			return "HIGH VOLTAGE"
		MusicSection.BREAKDOWN:
			return "EYE OF THE STORM"
		MusicSection.CLIMAX:
			return "HYPERDRIVE"
		_:
			return "APEX FINALE"


## Returns the fractional beat phase in [0.0, 1.0) at elapsed_seconds (128 BPM).
static func get_beat_phase(elapsed_seconds: float) -> float:
	var t: float = maxf(elapsed_seconds, 0.0)
	return fposmod(t, BEAT_DURATION) / BEAT_DURATION


## Returns the instantaneous rhythmic intensity in [0.15, 1.0] at elapsed_seconds.
static func get_beat_intensity(elapsed_seconds: float) -> float:
	var section: int = get_music_section(elapsed_seconds)
	var beat_phase: float = get_beat_phase(elapsed_seconds)
	var kick_env: float = pow(1.0 - beat_phase, 2.2)
	var base_energy: float = 0.45
	match section:
		MusicSection.INTRO:
			base_energy = 0.42
		MusicSection.VERSE:
			base_energy = 0.64
		MusicSection.CHORUS:
			base_energy = 0.78
		MusicSection.BREAKDOWN:
			var wrapped: float = fposmod(maxf(elapsed_seconds, 0.0), float(TOTAL_MUSIC_BARS) * BAR_DURATION)
			var bar_idx: int = int(floor(wrapped / BAR_DURATION))
			base_energy = 0.30 if bar_idx < 14 else 0.72
		MusicSection.CLIMAX:
			base_energy = 0.92
		MusicSection.FINALE:
			base_energy = 1.0
	return clampf(base_energy * (0.62 + 0.38 * kick_env), 0.15, 1.0)


static func _cached(id: StringName, maker: Callable) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id] as AudioStreamWAV
	var stream: AudioStreamWAV = maker.call() as AudioStreamWAV
	_cache[id] = stream
	return stream


static func _new_wav(sample_count: int, loop: bool) -> AudioStreamWAV:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	wav.loop_begin = 0
	wav.loop_end = sample_count if loop else 0
	wav.data = PackedByteArray()
	return wav


static func _write_sample(data: PackedByteArray, index: int, sample: float) -> void:
	data.encode_s16(index * 2, clampi(int(round(clampf(sample, -1.0, 1.0) * 32767.0)), -32768, 32767))


static func _make_menu() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.07)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = 660.0 if progress < 0.45 else 880.0
		phase += TAU * freq / float(MIX_RATE)
		var wave: float = 0.75 * sin(phase) + 0.25 * signf(sin(phase))
		var env: float = minf(progress * 20.0, 1.0) * pow(1.0 - progress, 1.5)
		_write_sample(data, i, wave * env * 0.45)
	wav.data = data
	return wav


static func _make_hit() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.18)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(320.0, 75.0, progress)
		phase += TAU * freq / float(MIX_RATE)
		var tone: float = 0.65 * signf(sin(phase)) + 0.35 * sin(phase * 0.5)
		var noise: float = sin(float(i * 127 + 31) * 0.43) * cos(float(i * 73) * 0.19)
		var env: float = pow(1.0 - progress, 1.6)
		_write_sample(data, i, (tone * 0.7 + noise * 0.3 * (1.0 - progress)) * env * 0.6)
	wav.data = data
	return wav


static func _make_laser() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.16)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(1080.0, 240.0, pow(progress, 0.65))
		phase += TAU * freq / float(MIX_RATE)
		var wave: float = 0.65 * sin(phase) + 0.35 * sin(phase * 2.0)
		var env: float = minf(progress * 18.0, 1.0) * pow(1.0 - progress, 1.35)
		_write_sample(data, i, wave * env * 0.42)
	wav.data = data
	return wav


static func _make_explosion() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.28)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(165.0, 38.0, pow(progress, 0.55))
		phase += TAU * freq / float(MIX_RATE)
		var sub_bass: float = sin(phase) + 0.4 * signf(sin(phase * 0.5))
		var rumble: float = sin(float(i * 97 + 19) * 0.37) * cos(float(i * 53 + 7) * 0.23)
		var env: float = pow(1.0 - progress, 1.45)
		_write_sample(data, i, (sub_bass * 0.6 + rumble * 0.4) * env * 0.55)
	wav.data = data
	return wav


static func _make_shield_on() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.14)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(260.0, 620.0, progress)
		phase += TAU * freq / float(MIX_RATE)
		var env: float = minf(progress * 12.0, 1.0) * pow(1.0 - progress, 0.9)
		_write_sample(data, i, (sin(phase) * 0.6 + sin(phase * 1.5) * 0.4) * env * 0.28)
	wav.data = data
	return wav


static func _make_shield_block() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.12)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(880.0, 180.0, progress)
		phase += TAU * freq / float(MIX_RATE)
		var metal: float = 0.55 * sin(phase) + 0.45 * signf(sin(phase * 2.7))
		var noise: float = sin(float(i * 211 + 7) * 0.61) * 0.25
		var env: float = minf(progress * 40.0, 1.0) * pow(1.0 - progress, 2.0)
		_write_sample(data, i, (metal + noise) * env * 0.34)
	wav.data = data
	return wav


static func _make_shield_break() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.26)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(540.0, 58.0, pow(progress, 0.7))
		phase += TAU * freq / float(MIX_RATE)
		var glass: float = sin(phase) + 0.35 * sin(phase * 3.1)
		var noise: float = sin(float(i * 157 + 43) * 0.47)
		var env: float = pow(1.0 - progress, 1.3)
		_write_sample(data, i, (glass * 0.65 + noise * 0.35) * env * 0.32)
	wav.data = data
	return wav


static func _make_music() -> AudioStreamWAV:
	# Full 24-bar (45.0-second) 128 BPM progressive electronic level composition.
	# 24 bars * 16 steps/bar = 384 sixteenth-note steps * 2584 samples/step = 992,256 samples.
	var total_steps: int = TOTAL_MUSIC_BARS * STEPS_PER_BAR
	var total_samples: int = total_steps * STEP_SAMPLES
	var wav: AudioStreamWAV = _new_wav(total_samples, true)

	# 1. Pre-synthesize 1-step (2584-sample) drum kit combinations:
	# 0=SILENT, 1=KICK, 2=HAT_CLOSED, 3=HAT_OPEN, 4=SNARE_HAT, 5=KICK_HAT,
	# 6=KICK_CRASH, 7=TOM_HIGH, 8=TOM_LOW, 9=SNARE_ROLL
	var drum_bank: Array[PackedFloat32Array] = []
	drum_bank.resize(10)
	for d_id: int in range(10):
		drum_bank[d_id] = _synth_drum_step(d_id)

	# 2. Pre-synthesize resonant analog bass 16th-note plucks for each pitch ID:
	# 0=SILENT, 1=A1(55.0), 2=C2(65.41), 3=D2(73.42), 4=E2(82.41), 5=F2(87.31), 6=G2(98.0),
	# 7=G#2(103.83), 8=A2(110.0), 9=C3(130.81), 10=D3(146.83), 11=E3(164.81), 12=F3(174.61), 13=G3(196.0)
	var bass_freqs: Array[float] = [
		0.0, 55.00, 65.41, 73.42, 82.41, 87.31, 98.00,
		103.83, 110.00, 130.81, 146.83, 164.81, 174.61, 196.00
	]
	var bass_bank: Array[PackedFloat32Array] = []
	bass_bank.resize(bass_freqs.size())
	for b_id: int in range(bass_freqs.size()):
		bass_bank[b_id] = _synth_bass_step(bass_freqs[b_id])

	# 3. Pre-synthesize 6 polyphonic sidechain-pumped chord pads across the 4 substeps of a beat:
	# Chords: 0=Am9, 1=Fmaj7, 2=Cmaj7, 3=G6, 4=Dm9, 5=E7
	var chord_voicings: Array = [
		[220.00, 261.63, 329.63, 493.88], # 0: Am9
		[174.61, 220.00, 261.63, 329.63], # 1: Fmaj7
		[261.63, 329.63, 392.00, 493.88], # 2: Cmaj7
		[196.00, 246.94, 293.66, 329.63], # 3: G6
		[146.83, 220.00, 293.66, 349.23], # 4: Dm9
		[164.81, 207.65, 246.94, 293.66], # 5: E7
	]
	var pad_bank: Array = []
	pad_bank.resize(chord_voicings.size())
	for c_id: int in range(chord_voicings.size()):
		var substeps: Array[PackedFloat32Array] = []
		substeps.resize(4)
		for sub: int in range(4):
			substeps[sub] = _synth_pad_substep(chord_voicings[c_id], sub)
		pad_bank[c_id] = substeps

	# 4. Pre-synthesize crystalline FM arpeggiator plucks & detuned dual-saw lead notes:
	# Pitch table (0=REST):
	# 1=A3(220.0), 2=B3(246.94), 3=C4(261.63), 4=D4(293.66), 5=E4(329.63), 6=F4(349.23),
	# 7=G4(392.0), 8=G#4(415.30), 9=A4(440.0), 10=B4(493.88), 11=C5(523.25), 12=D5(587.33),
	# 13=E5(659.25), 14=F5(698.46), 15=G5(783.99), 16=G#5(830.61), 17=A5(880.0), 18=B5(987.77), 19=C6(1046.50)
	var melodic_freqs: Array[float] = [
		0.0,
		220.00, 246.94, 261.63, 293.66, 329.63, 349.23,
		392.00, 415.30, 440.00, 493.88, 523.25, 587.33,
		659.25, 698.46, 783.99, 830.61, 880.00, 987.77, 1046.50
	]
	var arp_bank: Array[PackedFloat32Array] = []
	var lead_bank: Array[PackedFloat32Array] = []
	arp_bank.resize(melodic_freqs.size())
	lead_bank.resize(melodic_freqs.size())
	for m_id: int in range(melodic_freqs.size()):
		arp_bank[m_id] = _synth_arp_step(melodic_freqs[m_id])
		lead_bank[m_id] = _synth_lead_step(melodic_freqs[m_id])

	# 5. Musical Score Definitions Across 24 Bars (Bars 0..23):
	# Chord per bar (24 bars):
	var bar_chords: Array[int] = [
		0, 1, 2, 3,          # Bars 0..3:   INTRO (Am9 - Fmaj7 - Cmaj7 - G6)
		0, 1, 4, 5,          # Bars 4..7:   VERSE (Am9 - Fmaj7 - Dm9 - E7)
		1, 3, 2, 0,          # Bars 8..11:  CHORUS (Fmaj7 - G6 - Cmaj7 - Am9)
		0, 1, 4, 5,          # Bars 12..15: BREAKDOWN & RISER (Am9 - Fmaj7 - Dm9 - E7)
		0, 1, 2, 3, 4, 5,    # Bars 16..21: CLIMAX DROP (Am9 - Fmaj7 - Cmaj7 - G6 - Dm9 - E7)
		1, 5,                # Bars 22..23: FINALE TURNAROUND (Fmaj7 - E7 -> resolves to Am9)
	]

	# Drum 16-step patterns (8 patterns):
	var drum_patterns: Array = [
		# 0: Intro groove (4-on-floor kick + 16th hats)
		[5, 2, 2, 2,  5, 2, 3, 2,  5, 2, 2, 2,  5, 2, 3, 2],
		# 1: Intro Bar-3 fill
		[5, 2, 2, 2,  5, 2, 3, 2,  7, 7, 8, 8,  4, 9, 9, 6],
		# 2: Main Electro Groove A (Kick, Snare on 2&4, offbeat Open Hats)
		[6, 2, 3, 2,  4, 2, 3, 5,  5, 2, 3, 2,  4, 2, 3, 2],
		# 3: Main Electro Groove B (with syncopated pickup & mini-fill)
		[5, 2, 3, 2,  4, 2, 3, 5,  5, 2, 3, 5,  4, 2, 7, 8],
		# 4: Chorus High-Energy Groove + Bar-11 transition fill
		[6, 2, 3, 5,  4, 2, 3, 2,  5, 5, 3, 2,  4, 7, 8, 9],
		# 5: Breakdown Minimal Heartbeat (Bars 12..13)
		[1, 0, 2, 0,  0, 0, 1, 0,  2, 0, 0, 0,  4, 0, 2, 0],
		# 6: Riser Snare Build-up (Bars 14..15)
		[5, 4, 5, 4,  5, 4, 5, 4,  9, 9, 9, 9,  9, 9, 9, 6],
		# 7: Climax Hyperdrive Drop
		[6, 2, 3, 5,  4, 2, 3, 5,  5, 2, 3, 5,  4, 3, 4, 9],
	]

	# Bass root/octave pairs per chord [low_id, high_id, fifth_id]:
	var chord_bass_pairs: Array = [
		[1, 8, 4],   # 0: Am (A1, A2, E2)
		[5, 12, 9],  # 1: F  (F2, F3, C3)
		[2, 9, 6],   # 2: C  (C2, C3, G2)
		[6, 13, 10], # 3: G  (G2, G3, D3)
		[3, 10, 8],  # 4: Dm (D2, D3, A2)
		[4, 11, 7],  # 5: E7 (E2, E3, G#2)
	]

	# Arpeggiator 16-step pitch patterns per chord (0..5):
	var chord_arp_patterns: Array = [
		[1, 3, 5, 9,  5, 3, 9, 11, 9, 5, 3, 5,  9, 11, 13, 9], # 0: Am9
		[6, 9, 11, 13, 11, 9, 13, 14, 13, 11, 9, 11, 13, 14, 13, 9], # 1: Fmaj7
		[3, 5, 7, 11, 7, 5, 11, 13, 11, 7, 5, 7, 11, 13, 15, 11], # 2: Cmaj7
		[7, 10, 12, 15, 12, 10, 15, 13, 12, 10, 7, 10, 12, 13, 12, 10], # 3: G6
		[4, 6, 9, 12, 9, 6, 12, 13, 12, 9, 6, 9, 12, 14, 12, 9], # 4: Dm9
		[5, 8, 10, 12, 10, 8, 12, 13, 12, 10, 8, 10, 12, 16, 13, 10], # 5: E7
	]

	# Lead melody patterns (16 steps per bar for each of the 24 bars):
	var bar_leads: Array = [
		# Bars 0..1: Intro atmospheric space (arpeggio & bass lead the intro)
		[0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0],
		[0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  9, 0, 11, 13],
		# Bars 2..3: Intro melodic call & ascending launch fill
		[13, 13, 0, 11, 9, 0, 5, 0,  9, 11, 13, 0, 12, 0, 11, 9],
		[10, 0, 12, 0,  13, 0, 15, 0, 12, 13, 14, 15, 16, 17, 18, 17],
		# Bars 4..7: VERSE — Signature "Shapes & Beams" A-Theme
		[9, 9, 11, 13,  13, 11, 9, 0,  13, 13, 15, 17, 15, 13, 11, 0],
		[14, 14, 13, 11, 9, 11, 13, 0,  11, 9, 6, 9,   11, 13, 11, 9],
		[12, 12, 14, 17, 14, 12, 9, 0,  12, 13, 14, 12, 13, 11, 9, 11],
		[13, 13, 12, 10, 8, 10, 13, 0,  8, 10, 12, 13,  16, 13, 16, 17],
		# Bars 8..11: CHORUS — High-Voltage Anthemic Hook B-Theme
		[14, 14, 13, 11, 14, 17, 14, 0, 13, 14, 15, 17, 15, 14, 13, 11],
		[15, 15, 13, 12, 10, 12, 15, 0, 12, 13, 15, 18, 17, 15, 13, 12],
		[11, 11, 13, 15, 19, 17, 15, 0, 15, 13, 11, 13, 15, 17, 15, 13],
		[9, 11, 13, 17,  16, 13, 11, 9, 12, 13, 14, 15, 16, 17, 16, 13],
		# Bars 12..13: BREAKDOWN — Crystalline Contemplative Theme
		[17, 0, 13, 0,  11, 0, 9, 0,   10, 0, 11, 0,  13, 0, 9, 0],
		[14, 0, 13, 0,  11, 0, 9, 0,   11, 0, 13, 0,  14, 0, 13, 0],
		# Bars 14..15: RISER BUILD-UP — Accelerating Harmonic Climb
		[9, 0, 10, 0,   11, 0, 12, 0,  13, 11, 12, 13, 14, 12, 13, 14],
		[13, 14, 15, 16, 14, 15, 16, 17, 15, 16, 17, 18, 16, 17, 18, 19],
		# Bars 16..21: CLIMAX DROP — Hyperdrive Anthem
		[17, 17, 15, 13, 17, 19, 17, 15, 13, 15, 17, 15, 13, 11, 9, 13],
		[14, 14, 13, 11, 14, 17, 15, 14, 13, 14, 13, 11, 9, 11, 13, 15],
		[19, 19, 17, 15, 13, 15, 17, 0,  15, 17, 19, 17, 15, 13, 11, 13],
		[15, 15, 13, 12, 10, 12, 15, 17, 18, 17, 15, 13, 12, 13, 15, 17],
		[14, 12, 9, 12,  14, 17, 14, 12, 14, 15, 17, 14, 17, 19, 17, 14],
		[16, 13, 10, 13, 16, 17, 16, 13, 12, 13, 16, 17, 18, 17, 16, 17],
		# Bars 22..23: FINALE — Apex Resolution & Loop Turnaround
		[14, 13, 11, 13, 14, 17, 15, 13, 14, 15, 17, 19, 17, 15, 14, 13],
		[16, 13, 12, 10, 12, 13, 16, 17, 13, 16, 17, 18, 19, 17, 16, 17],
	]

	# 6. Assemble all 384 steps using cached step PCM buffers + dotted-8th lead delay!
	var step_pcm_cache: Dictionary = {}
	var song_data: PackedByteArray = PackedByteArray()
	var prev_leads: Array[int] = [0, 0, 0]

	for bar_idx: int in range(TOTAL_MUSIC_BARS):
		var chord_id: int = bar_chords[bar_idx]
		var bass_pair: Array = chord_bass_pairs[chord_id]
		var arp_pat: Array = chord_arp_patterns[chord_id]
		var lead_pat: Array = bar_leads[bar_idx]

		# Select drum pattern and mix levels for this bar's section:
		var drum_pat_idx: int = 2
		var mix_mode: int = 1 # 0=Intro, 1=Verse, 2=Chorus, 3=Breakdown, 4=Buildup, 5=Climax
		if bar_idx < 3:
			drum_pat_idx = 0
			mix_mode = 0
		elif bar_idx == 3:
			drum_pat_idx = 1
			mix_mode = 0
		elif bar_idx < 8:
			drum_pat_idx = 2 if (bar_idx % 2 == 0) else 3
			mix_mode = 1
		elif bar_idx < 11:
			drum_pat_idx = 2 if (bar_idx % 2 == 0) else 3
			mix_mode = 2
		elif bar_idx == 11:
			drum_pat_idx = 4
			mix_mode = 2
		elif bar_idx < 14:
			drum_pat_idx = 5
			mix_mode = 3
		elif bar_idx < 16:
			drum_pat_idx = 6
			mix_mode = 4
		elif bar_idx < 23:
			drum_pat_idx = 7 if (bar_idx % 2 == 0) else 3
			mix_mode = 5
		else:
			drum_pat_idx = 4
			mix_mode = 5

		var drum_pat: Array = drum_patterns[drum_pat_idx]

		for step_in_bar: int in range(STEPS_PER_BAR):
			var drum_id: int = int(drum_pat[step_in_bar])
			var beat_substep: int = step_in_bar % 4

			# Dynamic octave-jumping bass pattern:
			var bass_id: int = 0
			if mix_mode == 3:
				# Breakdown: deep sustained root hits on beat 1 and 3
				bass_id = int(bass_pair[0]) if (step_in_bar == 0 or step_in_bar == 8) else 0
			elif beat_substep == 0:
				bass_id = int(bass_pair[0])
			elif beat_substep == 2:
				bass_id = int(bass_pair[1])
			elif beat_substep == 3 and (mix_mode >= 2 or step_in_bar >= 12):
				bass_id = int(bass_pair[2])
			else:
				bass_id = int(bass_pair[0]) if mix_mode == 5 else 0

			var arp_id: int = int(arp_pat[step_in_bar])
			var lead_id: int = int(lead_pat[step_in_bar])
			var delay_lead_id: int = prev_leads[0]
			prev_leads[0] = prev_leads[1]
			prev_leads[1] = prev_leads[2]
			prev_leads[2] = lead_id

			var cache_key: String = "%d:%d:%d:%d:%d:%d:%d:%d" % [
				drum_id, bass_id, chord_id, beat_substep, arp_id, lead_id, delay_lead_id, mix_mode
			]
			var step_bytes: PackedByteArray
			if step_pcm_cache.has(cache_key):
				step_bytes = step_pcm_cache[cache_key] as PackedByteArray
			else:
				step_bytes = _mix_music_step(
					drum_bank[drum_id],
					bass_bank[bass_id],
					pad_bank[chord_id][beat_substep],
					arp_bank[arp_id],
					lead_bank[lead_id],
					lead_bank[delay_lead_id],
					mix_mode
				)
				step_pcm_cache[cache_key] = step_bytes
			song_data.append_array(step_bytes)

	wav.data = song_data
	return wav


static func _mix_music_step(
	drum_buf: PackedFloat32Array,
	bass_buf: PackedFloat32Array,
	pad_buf: PackedFloat32Array,
	arp_buf: PackedFloat32Array,
	lead_buf: PackedFloat32Array,
	delay_buf: PackedFloat32Array,
	mix_mode: int
) -> PackedByteArray:
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(STEP_SAMPLES * 2)

	var drum_gain: float = 0.52
	var bass_gain: float = 0.42
	var pad_gain: float = 0.26
	var arp_gain: float = 0.24
	var lead_gain: float = 0.38
	var delay_gain: float = 0.12

	match mix_mode:
		0: # Intro
			drum_gain = 0.44
			bass_gain = 0.38
			pad_gain = 0.22
			arp_gain = 0.28
			lead_gain = 0.30
			delay_gain = 0.10
		1: # Verse
			drum_gain = 0.52
			bass_gain = 0.42
			pad_gain = 0.26
			arp_gain = 0.20
			lead_gain = 0.40
			delay_gain = 0.12
		2: # Chorus
			drum_gain = 0.56
			bass_gain = 0.45
			pad_gain = 0.28
			arp_gain = 0.25
			lead_gain = 0.44
			delay_gain = 0.14
		3: # Breakdown
			drum_gain = 0.28
			bass_gain = 0.30
			pad_gain = 0.34
			arp_gain = 0.30
			lead_gain = 0.34
			delay_gain = 0.16
		4: # Riser Build-up
			drum_gain = 0.54
			bass_gain = 0.40
			pad_gain = 0.30
			arp_gain = 0.28
			lead_gain = 0.42
			delay_gain = 0.14
		5: # Climax Drop & Finale
			drum_gain = 0.60
			bass_gain = 0.48
			pad_gain = 0.30
			arp_gain = 0.27
			lead_gain = 0.46
			delay_gain = 0.15

	for i: int in range(STEP_SAMPLES):
		var raw: float = (
			drum_buf[i] * drum_gain
			+ bass_buf[i] * bass_gain
			+ pad_buf[i] * pad_gain
			+ arp_buf[i] * arp_gain
			+ lead_buf[i] * lead_gain
			+ delay_buf[i] * delay_gain
		)
		# Soft-knee studio mastering limiter
		var limited: float = clampf((raw / (1.0 + 0.45 * absf(raw))) * 0.92, -0.99, 0.99)
		pcm.encode_s16(i * 2, int(limited * 32767.0))
	return pcm


static func _synth_drum_step(drum_id: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(STEP_SAMPLES)
	if drum_id == 0:
		return buf

	var has_kick: bool = drum_id in [1, 5, 6]
	var has_closed_hat: bool = drum_id in [2, 4, 5]
	var has_open_hat: bool = drum_id == 3
	var has_crash: bool = drum_id == 6
	var has_snare: bool = drum_id == 4
	var has_tom_hi: bool = drum_id == 7
	var has_tom_lo: bool = drum_id == 8
	var has_roll: bool = drum_id == 9

	var kick_phase: float = 0.0
	var snare_phase: float = 0.0
	var tom_phase: float = 0.0

	for i: int in range(STEP_SAMPLES):
		var p: float = float(i) / float(STEP_SAMPLES)
		var sample: float = 0.0

		if has_kick:
			var k_freq: float = 44.0 + 135.0 * pow(1.0 - p, 4.5)
			kick_phase += TAU * k_freq / float(MIX_RATE)
			var k_env: float = pow(1.0 - p, 1.45)
			var click: float = sin(float(i) * 0.42) * pow(maxf(0.0, 1.0 - p * 12.0), 2.0) * 0.35
			sample += (sin(kick_phase) * 0.95 + 0.25 * sin(kick_phase * 2.0) + click) * k_env

		if has_snare or has_roll:
			var local_p: float = fposmod(p * 2.0, 1.0) if has_roll else p
			var s_freq: float = lerpf(225.0, 118.0, minf(local_p * 2.5, 1.0))
			snare_phase += TAU * s_freq / float(MIX_RATE)
			var body_env: float = pow(1.0 - local_p, 2.2)
			var noise_env: float = pow(1.0 - local_p, 1.35)
			var noise: float = sin(float(i * 197 + 23) * 0.53) * cos(float(i * 89 + 11) * 0.31)
			sample += (sin(snare_phase) * 0.52 * body_env + noise * 0.72 * noise_env)

		if has_closed_hat:
			var h_env: float = pow(maxf(0.0, 1.0 - p * 3.4), 2.2)
			var metal: float = sin(float(i) * 1.42) * sin(float(i) * 2.17) + 0.5 * cos(float(i * 173) * 0.67)
			sample += metal * h_env * 0.34

		if has_open_hat or has_crash:
			var o_env: float = pow(1.0 - p, 0.85 if has_crash else 1.25)
			var shimmer: float = (
				sin(float(i) * 1.37) * cos(float(i) * 2.09)
				+ 0.6 * sin(float(i * 151 + 17) * 0.59)
			)
			sample += shimmer * o_env * (0.48 if has_crash else 0.38)

		if has_tom_hi or has_tom_lo:
			var t_start: float = 270.0 if has_tom_hi else 185.0
			var t_end: float = 115.0 if has_tom_hi else 76.0
			var t_freq: float = lerpf(t_start, t_end, pow(p, 0.6))
			tom_phase += TAU * t_freq / float(MIX_RATE)
			var t_env: float = pow(1.0 - p, 1.35)
			sample += (sin(tom_phase) + 0.25 * sin(tom_phase * 2.0)) * t_env * 0.85

		# Smooth 48-sample tail taper so step boundaries never click
		if i > STEP_SAMPLES - 48:
			sample *= float(STEP_SAMPLES - i) / 48.0
		buf[i] = sample
	return buf


static func _synth_bass_step(freq: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(STEP_SAMPLES)
	if freq <= 1.0:
		return buf

	var phase: float = 0.0
	for i: int in range(STEP_SAMPLES):
		var p: float = float(i) / float(STEP_SAMPLES)
		phase += TAU * freq / float(MIX_RATE)
		# Resonant low-pass filter sweep on each 16th-note pluck
		var cutoff_env: float = pow(1.0 - p, 2.4)
		var sub: float = sin(phase * 0.5) * 0.45
		var fund: float = sin(phase) * 0.70
		var harm2: float = sin(phase * 2.0) * (0.18 + 0.42 * cutoff_env)
		var harm3: float = sin(phase * 3.0) * (0.08 + 0.34 * cutoff_env)
		var harm4: float = sin(phase * 4.0) * (0.24 * cutoff_env * cutoff_env)
		var amp_env: float = minf(float(i) / 42.0, 1.0) * pow(1.0 - p * 0.65, 0.8)
		if i > STEP_SAMPLES - 56:
			amp_env *= float(STEP_SAMPLES - i) / 56.0
		buf[i] = (sub + fund + harm2 + harm3 + harm4) * amp_env * 0.68
	return buf


static func _synth_pad_substep(chord_freqs: Array, substep: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(STEP_SAMPLES)
	# Sidechain pumping curve across the 4 sixteenth-notes of each beat
	var sc_start: float = 0.24
	var sc_end: float = 0.52
	match substep:
		0:
			sc_start = 0.22
			sc_end = 0.54
		1:
			sc_start = 0.54
			sc_end = 0.88
		2:
			sc_start = 0.88
			sc_end = 1.00
		_:
			sc_start = 1.00
			sc_end = 0.76

	# Quantize each chord tone to an exact integer number of cycles per step so
	# phase(0) == phase(STEP_SAMPLES) == 0 mod TAU (100% click-free continuity).
	var step_base_freq: float = float(MIX_RATE) / float(STEP_SAMPLES)
	var q_freqs: Array[float] = []
	for f_var: Variant in chord_freqs:
		var raw_f: float = float(f_var)
		var cycles: float = maxf(1.0, round(raw_f / step_base_freq))
		q_freqs.append(cycles * step_base_freq)

	for i: int in range(STEP_SAMPLES):
		var p: float = float(i) / float(STEP_SAMPLES)
		var sidechain: float = lerpf(sc_start, sc_end, p)
		var t: float = float(i) / float(MIX_RATE)
		var voice_sum: float = 0.0
		for qf: float in q_freqs:
			var ph: float = TAU * qf * t
			voice_sum += sin(ph) * 0.72 + sin(ph * 2.0) * 0.20 + sin(ph * 3.0) * 0.08
		buf[i] = (voice_sum / float(maxi(q_freqs.size(), 1))) * sidechain
	return buf


static func _synth_arp_step(freq: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(STEP_SAMPLES)
	if freq <= 1.0:
		return buf

	var phase: float = 0.0
	for i: int in range(STEP_SAMPLES):
		var p: float = float(i) / float(STEP_SAMPLES)
		phase += TAU * freq / float(MIX_RATE)
		var fm_index: float = 0.85 * exp(-p * 7.5)
		var pluck: float = sin(phase + fm_index * sin(phase * 2.0)) + 0.30 * sin(phase * 3.0) * exp(-p * 10.0)
		var env: float = minf(float(i) / 28.0, 1.0) * exp(-p * 3.6)
		if i > STEP_SAMPLES - 48:
			env *= float(STEP_SAMPLES - i) / 48.0
		buf[i] = pluck * env * 0.75
	return buf


static func _synth_lead_step(freq: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(STEP_SAMPLES)
	if freq <= 1.0:
		return buf

	var phase_a: float = 0.0
	var phase_b: float = 0.0
	for i: int in range(STEP_SAMPLES):
		var p: float = float(i) / float(STEP_SAMPLES)
		# Expressive 5.5 Hz vibrato that blooms after the initial attack
		var vib: float = 1.0 + 0.0045 * sin(p * TAU * 1.4) * clampf((p - 0.25) * 1.33, 0.0, 1.0)
		phase_a += TAU * (freq * 0.9965 * vib) / float(MIX_RATE)
		phase_b += TAU * (freq * 1.0035 * vib) / float(MIX_RATE)
		var osc_a: float = sin(phase_a) + 0.45 * sin(phase_a * 2.0) + 0.25 * sin(phase_a * 3.0) + 0.12 * sin(phase_a * 4.0)
		var osc_b: float = sin(phase_b) + 0.45 * sin(phase_b * 2.0) + 0.25 * sin(phase_b * 3.0) + 0.12 * sin(phase_b * 4.0)
		var env: float = minf(float(i) / 36.0, 1.0) * pow(1.0 - p * 0.38, 0.65)
		if i > STEP_SAMPLES - 56:
			env *= float(STEP_SAMPLES - i) / 56.0
		buf[i] = (osc_a + osc_b) * 0.34 * env
	return buf


static func _make_victory() -> AudioStreamWAV:
	# Triumphant 4-note ascending A-major/minor-9th crystal fanfare
	var notes: Array[float] = [440.0, 523.25, 659.25, 880.0]
	var durations: Array[float] = [0.12, 0.12, 0.14, 0.42]
	var total_samples: int = int(MIX_RATE * 0.80)
	var wav: AudioStreamWAV = _new_wav(total_samples, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(total_samples * 2)
	var phase_a: float = 0.0
	var phase_b: float = 0.0
	var cursor: int = 0
	for n_idx: int in range(notes.size()):
		var seg_samples: int = int(MIX_RATE * durations[n_idx])
		if n_idx == notes.size() - 1:
			seg_samples = total_samples - cursor
		var freq: float = notes[n_idx]
		for j: int in range(seg_samples):
			var p: float = float(j) / float(maxi(seg_samples, 1))
			phase_a += TAU * freq / float(MIX_RATE)
			phase_b += TAU * (freq * 1.5) / float(MIX_RATE)
			var wave: float = 0.65 * sin(phase_a) + 0.25 * sin(phase_a * 2.0) + 0.20 * sin(phase_b)
			var env: float = minf(float(j) / 40.0, 1.0) * pow(1.0 - p, 0.85 if n_idx == 3 else 0.55)
			_write_sample(data, cursor + j, wave * env * 0.42)
		cursor += seg_samples
	wav.data = data
	return wav


static func _make_game_over() -> AudioStreamWAV:
	# Dramatic descending synth power-down resolve
	var sample_count: int = int(MIX_RATE * 0.58)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var p: float = float(i) / float(sample_count)
		var step_f: float = 329.63
		if p > 0.66:
			step_f = lerpf(196.0, 110.0, (p - 0.66) / 0.34)
		elif p > 0.33:
			step_f = 246.94
		phase += TAU * step_f / float(MIX_RATE)
		var wave: float = 0.60 * sin(phase) + 0.28 * sin(phase * 2.0) + 0.22 * sin(phase * 0.5)
		var env: float = minf(float(i) / 48.0, 1.0) * pow(1.0 - p, 0.95)
		_write_sample(data, i, wave * env * 0.44)
	wav.data = data
	return wav


static func _make_enemy_fire() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.11)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(920.0, 310.0, pow(progress, 0.55))
		phase += TAU * freq / float(MIX_RATE)
		var pulse: float = 0.6 * sin(phase) + 0.4 * signf(sin(phase * 1.5))
		var env: float = minf(progress * 28.0, 1.0) * pow(1.0 - progress, 1.65)
		_write_sample(data, i, pulse * env * 0.28)
	wav.data = data
	return wav


static func _make_enemy_lunge() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.15)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(190.0, 560.0, pow(progress, 0.75))
		phase += TAU * freq / float(MIX_RATE)
		var sweep: float = 0.7 * sin(phase) + 0.3 * sin(phase * 2.0)
		var air: float = sin(float(i * 173 + 19) * 0.51) * 0.22
		var env: float = minf(progress * 14.0, 1.0) * pow(1.0 - progress, 1.25)
		_write_sample(data, i, (sweep + air) * env * 0.26)
	wav.data = data
	return wav


static func _make_wall_slam() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.22)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(135.0, 42.0, pow(progress, 0.5))
		phase += TAU * freq / float(MIX_RATE)
		var thud: float = 0.75 * sin(phase) + 0.25 * signf(sin(phase * 0.5))
		var grit: float = sin(float(i * 113 + 29) * 0.39) * (1.0 - progress) * 0.3
		var env: float = minf(progress * 35.0, 1.0) * pow(1.0 - progress, 1.55)
		_write_sample(data, i, (thud + grit) * env * 0.42)
	wav.data = data
	return wav


static func _make_saw_bounce() -> AudioStreamWAV:
	var sample_count: int = int(MIX_RATE * 0.08)
	var wav: AudioStreamWAV = _new_wav(sample_count, false)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	for i: int in range(sample_count):
		var progress: float = float(i) / float(sample_count)
		var freq: float = lerpf(740.0, 420.0, progress)
		phase += TAU * freq / float(MIX_RATE)
		var ping: float = 0.65 * sin(phase) + 0.35 * sin(phase * 2.4)
		var env: float = minf(progress * 36.0, 1.0) * pow(1.0 - progress, 2.1)
		_write_sample(data, i, ping * env * 0.24)
	wav.data = data
	return wav
