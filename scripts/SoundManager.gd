extends Node
## SoundManager — Procedural UI Audio Generator for Abstract Pulse
## Generates crisp synth audio effects for UI hovering, clicking, level launches, and rhythmic beats.

var audio_player_ui: AudioStreamPlayer
var audio_player_beat: AudioStreamPlayer

# Cache of generated AudioStreams
var sfx_hover: AudioStreamWAV
var sfx_click: AudioStreamWAV
var sfx_launch: AudioStreamWAV
var sfx_beat: AudioStreamWAV
var sfx_back: AudioStreamWAV

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	audio_player_ui = AudioStreamPlayer.new()
	audio_player_ui.name = "AudioPlayerUI"
	audio_player_ui.bus = "Master"
	add_child(audio_player_ui)
	
	audio_player_beat = AudioStreamPlayer.new()
	audio_player_beat.name = "AudioPlayerBeat"
	audio_player_beat.bus = "Master"
	add_child(audio_player_beat)
	
	_generate_audio_streams()
	print("[SoundManager] Generador de audio procedural listo.")

func _generate_audio_streams() -> void:
	sfx_hover = _create_synth_tone(880.0, 0.04, 0.15, "sine")     # High A note, short pip
	sfx_click = _create_synth_tone(1320.0, 0.08, 0.35, "square")   # Crisp synth click
	sfx_launch = _create_synth_sweep(220.0, 880.0, 0.4, 0.4)      # Rising synth sweep
	sfx_back = _create_synth_sweep(660.0, 330.0, 0.12, 0.25)      # Falling tone
	sfx_beat = _create_synth_tone(120.0, 0.08, 0.5, "sine")       # Deep bass kick pulse

func play_hover() -> void:
	if sfx_hover and _get_sfx_enabled():
		_play_stream(audio_player_ui, sfx_hover, -12.0)

func play_click() -> void:
	if sfx_click and _get_sfx_enabled():
		_play_stream(audio_player_ui, sfx_click, -6.0)

func play_back() -> void:
	if sfx_back and _get_sfx_enabled():
		_play_stream(audio_player_ui, sfx_back, -8.0)

func play_launch() -> void:
	if sfx_launch and _get_sfx_enabled():
		_play_stream(audio_player_ui, sfx_launch, -3.0)

func play_beat() -> void:
	if sfx_beat and _get_sfx_enabled():
		_play_stream(audio_player_beat, sfx_beat, -8.0)

func _play_stream(player: AudioStreamPlayer, stream: AudioStream, volume_db: float = 0.0) -> void:
	player.stream = stream
	player.volume_db = volume_db
	player.play()

func _get_sfx_enabled() -> bool:
	if Engine.has_singleton("GameManager") or GameManager != null:
		return GameManager.sfx_volume > 0.01
	return true

## Generates a PCM 16-bit sine or square synth tone
func _create_synth_tone(freq: float, duration: float, volume: float = 0.3, wave_type: String = "sine") -> AudioStreamWAV:
	var sample_rate: int = 22050
	var total_samples: int = int(sample_rate * duration)
	var byte_data: PackedByteArray = PackedByteArray()
	byte_data.resize(total_samples * 2) # 16-bit PCM (2 bytes per sample)
	
	for i in range(total_samples):
		var t: float = float(i) / float(sample_rate)
		# Envelope fade-out to prevent pops
		var envelope: float = 1.0 - (float(i) / float(total_samples))
		envelope = envelope * envelope
		
		var sample_val: float = 0.0
		if wave_type == "sine":
			sample_val = sin(TAU * freq * t)
		elif wave_type == "square":
			sample_val = 1.0 if sin(TAU * freq * t) >= 0 else -1.0
			
		sample_val *= volume * envelope
		var int_val: int = int(clamp(sample_val * 32767.0, -32768.0, 32767.0))
		
		# 16-bit Little Endian
		byte_data[i * 2] = int_val & 0xFF
		byte_data[i * 2 + 1] = (int_val >> 8) & 0xFF
		
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = byte_data
	return stream

## Generates a frequency sweep synth tone (e.g. rising level launch sound)
func _create_synth_sweep(start_freq: float, end_freq: float, duration: float, volume: float = 0.3) -> AudioStreamWAV:
	var sample_rate: int = 22050
	var total_samples: int = int(sample_rate * duration)
	var byte_data: PackedByteArray = PackedByteArray()
	byte_data.resize(total_samples * 2)
	
	var phase: float = 0.0
	for i in range(total_samples):
		var progress: float = float(i) / float(total_samples)
		var current_freq: float = lerp(start_freq, end_freq, progress)
		phase += TAU * current_freq / float(sample_rate)
		
		var envelope: float = sin(progress * PI) # Smooth bell curve envelope
		var sample_val: float = sin(phase) * volume * envelope
		var int_val: int = int(clamp(sample_val * 32767.0, -32768.0, 32767.0))
		
		byte_data[i * 2] = int_val & 0xFF
		byte_data[i * 2 + 1] = (int_val >> 8) & 0xFF
		
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = byte_data
	return stream
