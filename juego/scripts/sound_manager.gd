extends Node

const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"SFX"
const SFX_POOL_SIZE: int = 8

const MIX_RATE: int = 22050
const MUSIC_BPM: float = 128.0
const BEAT_DURATION: float = 60.0 / MUSIC_BPM
const BAR_SAMPLES: int = 2584 * 16
const BAR_DURATION: float = float(BAR_SAMPLES) / float(MIX_RATE)
const TOTAL_MUSIC_BARS: int = 24
const BOSS_TOTAL_BARS: int = 64
const BOSS_TOTAL_PHASES: int = 8
const BOSS_PHASE_DURATION: float = 15.0
const BOSS_TOTAL_DURATION: float = 120.0
const BOSS_SILENCE_START: float = 156.0 * BEAT_DURATION  # 73.125s (Bar 39 Beat 0)
const BOSS_SILENCE_END: float = 158.0 * BEAT_DURATION    # 74.0625s (Bar 39 Beat 2)
const BOSS_SHATTER_START: float = 252.0 * BEAT_DURATION  # 118.125s (Bar 63 Beat 0)
const BOSS_TAIL_SILENCE_START: float = 119.95

enum MusicSection {
	INTRO = 0,
	VERSE = 1,
	CHORUS = 2,
	BREAKDOWN = 3,
	CLIMAX = 4,
	FINALE = 5,
}

const SFX_STREAMS: Dictionary = {
	&"menu": preload("res://assets/audio/menu.wav"),
	&"hit": preload("res://assets/audio/hit.wav"),
	&"laser": preload("res://assets/audio/laser.wav"),
	&"explosion": preload("res://assets/audio/explosion.wav"),
	&"shield_on": preload("res://assets/audio/shield_on.wav"),
	&"shield_block": preload("res://assets/audio/shield_block.wav"),
	&"shield_break": preload("res://assets/audio/shield_break.wav"),
	&"enemy_fire": preload("res://assets/audio/enemy_fire.wav"),
	&"enemy_lunge": preload("res://assets/audio/enemy_lunge.wav"),
	&"wall_slam": preload("res://assets/audio/wall_slam.wav"),
	&"saw_bounce": preload("res://assets/audio/saw_bounce.wav"),
	&"victory": preload("res://assets/audio/victory.wav"),
	&"game_over": preload("res://assets/audio/game_over.wav"),
	&"boss_roar": preload("res://assets/audio/boss_roar.wav"),
	&"boss_phase": preload("res://assets/audio/boss_phase.wav"),
}

const MUSIC_STREAM: AudioStreamWAV = preload("res://assets/audio/music.wav")
const BOSS_INTRO_STREAM: AudioStreamWAV = preload("res://assets/audio/boss_intro.wav")
const BOSS_MUSIC_STREAM: AudioStreamWAV = preload("res://assets/audio/boss_music.wav")

var music_player: AudioStreamPlayer = null
var _music_playing: bool = false
var _last_boss_clock_time: float = 0.0
var _sfx_pool: Array[AudioStreamPlayer] = []
var _pool_cursor: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(BUS_MUSIC)
	_ensure_bus(BUS_SFX)

	var stream: AudioStreamWAV = MUSIC_STREAM
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	if stream.loop_end <= 0:
		stream.loop_end = int(stream.get_length() * float(MIX_RATE))

	music_player = AudioStreamPlayer.new()
	music_player.name = "MusicPlayer"
	music_player.bus = BUS_MUSIC
	music_player.stream = stream
	add_child(music_player)

	for i: int in range(SFX_POOL_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.bus = BUS_SFX
		add_child(p)
		_sfx_pool.append(p)

	if GameManager.save_data != null:
		set_music_volume(GameManager.save_data.music_volume)
		set_sfx_volume(GameManager.save_data.sfx_volume)


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, BUS_MASTER)


func play_sfx(sfx: Variant, volume_db: float = 0.0) -> void:
	var stream: AudioStream = null
	if sfx is AudioStream:
		stream = sfx
	elif sfx is StringName or sfx is String:
		stream = SFX_STREAMS.get(StringName(sfx)) as AudioStream
	if stream == null or _sfx_pool.is_empty():
		return

	var chosen: AudioStreamPlayer = null
	for p: AudioStreamPlayer in _sfx_pool:
		if not p.playing:
			chosen = p
			break
	if chosen == null:
		chosen = _sfx_pool[_pool_cursor]
		_pool_cursor = (_pool_cursor + 1) % _sfx_pool.size()
	chosen.stream = stream
	chosen.volume_db = volume_db
	chosen.play()


func play_music(pitch_scale: float = 1.0) -> void:
	_music_playing = true
	if music_player == null:
		return
	music_player.pitch_scale = pitch_scale
	music_player.stream = MUSIC_STREAM
	music_player.stop()
	music_player.play(0.0)


func play_boss_intro(pitch_scale: float = 1.0) -> void:
	_music_playing = true
	_last_boss_clock_time = 0.0
	var intro_stream: AudioStreamWAV = BOSS_INTRO_STREAM
	if intro_stream != null:
		intro_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	if music_player == null:
		return
	music_player.pitch_scale = pitch_scale
	music_player.stream = intro_stream
	music_player.stop()
	music_player.play(0.0)


func play_boss_music(pitch_scale: float = 1.0) -> void:
	_music_playing = true
	_last_boss_clock_time = 0.0
	if music_player == null:
		return
	music_player.pitch_scale = pitch_scale
	music_player.stream = BOSS_MUSIC_STREAM
	music_player.stop()
	music_player.play(0.0)


func get_boss_playback_time(fallback_elapsed: float) -> float:
	if DisplayServer.get_name() == "headless" or music_player == null or not _music_playing or not music_player.playing or music_player.stream != BOSS_MUSIC_STREAM:
		return maxf(fallback_elapsed, 0.0)
	var raw: float = music_player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	var clamped: float = clampf(raw, 0.0, BOSS_TOTAL_DURATION)
	var candidate: float = clamped if absf(clamped - fallback_elapsed) <= 0.35 else clampf(fallback_elapsed, 0.0, BOSS_TOTAL_DURATION)
	_last_boss_clock_time = maxf(_last_boss_clock_time, candidate)
	return _last_boss_clock_time


func stop_music() -> void:
	_music_playing = false
	if music_player != null:
		music_player.stop()


func is_music_playing() -> bool:
	return _music_playing


func play_ui_click() -> void:
	play_sfx(&"menu")


func play_ui_hover() -> void:
	play_sfx(&"menu", -14.0)


func set_music_volume(linear: float) -> void:
	_set_bus_linear(BUS_MUSIC, linear)
	if GameManager.save_data != null:
		GameManager.save_data.music_volume = clampf(linear, 0.0, 1.0)


func set_sfx_volume(linear: float) -> void:
	_set_bus_linear(BUS_SFX, linear)
	if GameManager.save_data != null:
		GameManager.save_data.sfx_volume = clampf(linear, 0.0, 1.0)


func get_music_volume() -> float:
	return _get_bus_linear(BUS_MUSIC)


func get_sfx_volume() -> float:
	return _get_bus_linear(BUS_SFX)


func _set_bus_linear(bus_name: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var clamped: float = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clamped) if clamped > 0.0 else -80.0)


func _get_bus_linear(bus_name: StringName) -> float:
	var idx: int = AudioServer.get_bus_index(bus_name)
	return db_to_linear(AudioServer.get_bus_volume_db(idx)) if idx != -1 else 0.0


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


static func get_beat_phase(elapsed_seconds: float) -> float:
	return fposmod(maxf(elapsed_seconds, 0.0), BEAT_DURATION) / BEAT_DURATION


static func get_beat_intensity(elapsed_seconds: float) -> float:
	var section: int = get_music_section(elapsed_seconds)
	var kick_env: float = pow(1.0 - get_beat_phase(elapsed_seconds), 2.2)
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
			base_energy = 0.30 if int(floor(wrapped / BAR_DURATION)) < 14 else 0.72
		MusicSection.CLIMAX:
			base_energy = 0.92
		MusicSection.FINALE:
			base_energy = 1.0
	return clampf(base_energy * (0.62 + 0.38 * kick_env), 0.15, 1.0)


static func get_boss_section(elapsed_seconds: float) -> int:
	var clamped: float = clampf(elapsed_seconds, 0.0, BOSS_TOTAL_DURATION - 0.0001)
	return clampi(int(floor(clamped / BOSS_PHASE_DURATION)), 0, BOSS_TOTAL_PHASES - 1)


static func get_boss_beat_intensity(elapsed_seconds: float) -> float:
	var t: float = maxf(elapsed_seconds, 0.0)
	if t >= BOSS_SILENCE_START and t < BOSS_SILENCE_END:
		return 0.0
	if t >= BOSS_TAIL_SILENCE_START:
		return 0.0

	var section: int = get_boss_section(t)
	var beat_f: float = t / BEAT_DURATION
	var beat_idx: int = int(floor(beat_f))
	var bar_idx: int = int(floor(beat_f / 4.0))
	var beat_in_bar: int = beat_idx % 4
	var beat_phase: float = get_beat_phase(t)
	var kick_env: float = pow(1.0 - beat_phase, 2.2)

	match section:
		0:
			if bar_idx == 0:
				return clampf(0.35 + 0.13 * pow(1.0 - beat_phase, 3.0), 0.35, 0.48)
			var base_p1: float = 0.62
			if bar_idx == 7:
				var fill_u: float = clampf((t - 28.0 * BEAT_DURATION) / (4.0 * BEAT_DURATION), 0.0, 1.0)
				base_p1 = lerpf(0.62, 0.78, fill_u)
			return clampf(base_p1 * (0.62 + 0.38 * kick_env), 0.15, 1.0)
		1:
			if bar_idx == 8:
				if beat_idx <= 33:
					return 0.18
				var rise_u: float = clampf((t - 34.0 * BEAT_DURATION) / (2.0 * BEAT_DURATION), 0.0, 1.0)
				return lerpf(0.20, 0.80, rise_u)
			var base_p2: float = 0.82 if bar_idx == 15 else 0.74
			return clampf(base_p2 * (0.62 + 0.38 * kick_env), 0.15, 1.0)
		2:
			var base_p3: float = 0.86 if (beat_in_bar == 0 or beat_in_bar == 2) else 0.74
			if bar_idx == 23:
				base_p3 = 0.90
			return clampf(base_p3 * (0.62 + 0.38 * kick_env), 0.15, 1.0)
		3:
			var cyc_bar: int = bar_idx % 4
			if cyc_bar == 0:
				var drop_base: float = 0.88 if bar_idx == 28 else 0.86
				return clampf(drop_base * (0.62 + 0.38 * kick_env), 0.15, 1.0)
			if cyc_bar == 1:
				var sweep_start: float = float(bar_idx * 4) * BEAT_DURATION
				var sweep_u: float = clampf((t - sweep_start) / (4.0 * BEAT_DURATION), 0.0, 1.0)
				return clampf(lerpf(0.74, 0.80, sweep_u) * (0.62 + 0.38 * kick_env), 0.35, 1.0)
			var arp_start: float = float((bar_idx - (cyc_bar - 2)) * 4) * BEAT_DURATION
			var arp_u: float = clampf((t - arp_start) / (8.0 * BEAT_DURATION), 0.0, 1.0)
			return clampf(lerpf(0.80, 0.92, arp_u) * (0.62 + 0.38 * kick_env), 0.40, 1.0)
		4:
			if t < BOSS_SILENCE_START:
				if t < 130.0 * BEAT_DURATION:
					var dive_u: float = clampf((t - 128.0 * BEAT_DURATION) / (2.0 * BEAT_DURATION), 0.0, 1.0)
					return lerpf(0.66, 0.26, dive_u)
				if bar_idx == 38:
					var gl_u: float = clampf((t - 152.0 * BEAT_DURATION) / (4.0 * BEAT_DURATION), 0.0, 1.0)
					return lerpf(0.32, 0.72, gl_u)
				return clampf(0.30 * (0.85 + 0.15 * kick_env), 0.24, 0.34)
			if beat_idx == 158:
				return clampf(lerpf(0.55, 1.0, pow(1.0 - beat_phase, 1.6)), 0.55, 1.0)
			return lerpf(0.52, 0.94, beat_phase)
		5:
			return clampf(0.94 * (0.62 + 0.38 * kick_env), 0.15, 1.0)
		6:
			if beat_in_bar == 0:
				return clampf(0.96 * (0.45 + 0.55 * pow(1.0 - beat_phase, 1.8)), 0.35, 1.0)
			if beat_in_bar == 2:
				return clampf(0.84 * (0.36 + 0.64 * pow(1.0 - beat_phase, 3.0)), 0.28, 0.90)
			return clampf(0.32 + 0.06 * kick_env, 0.28, 0.40)
		7:
			if t >= BOSS_SHATTER_START:
				var fade_u: float = clampf(
					(BOSS_TAIL_SILENCE_START - t) / (BOSS_TAIL_SILENCE_START - BOSS_SHATTER_START),
					0.0,
					1.0
				)
				return clampf(fade_u, 0.0, 1.0)
			if bar_idx == 60:
				return clampf(0.52 * (0.70 + 0.30 * kick_env), 0.30, 0.60)
			if bar_idx == 62:
				var build_u: float = clampf((t - 248.0 * BEAT_DURATION) / (4.0 * BEAT_DURATION), 0.0, 1.0)
				return clampf(maxf(lerpf(0.84, 1.0, build_u), 0.78 + 0.22 * kick_env), 0.78, 1.0)
			var base_p8: float = 1.0 if bar_idx == 58 else 0.98
			return clampf(base_p8 * (0.65 + 0.35 * kick_env), 0.50, 1.0)

	return clampf(0.56 * (0.62 + 0.38 * kick_env), 0.15, 1.0)
