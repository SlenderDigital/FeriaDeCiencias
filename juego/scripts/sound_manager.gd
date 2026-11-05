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
}

const MUSIC_STREAM: AudioStreamWAV = preload("res://assets/audio/music.wav")

var music_player: AudioStreamPlayer = null
var _music_playing: bool = false
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
