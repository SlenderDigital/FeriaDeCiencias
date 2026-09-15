extends SceneTree
## Debug: verificar si los .ogg cargan como AudioStream válido y cómo se comporta
## el AudioStreamPlayer al reproducirlos (playing / finished / get_playback_position).

func _init() -> void:
	for audio in [
		"res://assets/music/first_light.ogg",
		"res://assets/music/mechanical_wall.ogg",
		"res://assets/music/relentless_drive.ogg",
	]:
		var s := load(audio) as AudioStream
		print("LOAD ", audio, " -> ", s, "  (class=", (s.get_class() if s else "NULL"), ")")

	# Reproducir uno y mirar los flags los primeros frames
	var player := AudioStreamPlayer.new()
	root.add_child(player)
	player.stream = load("res://assets/music/first_light.ogg") as AudioStream
	print("BEFORE play: playing=", player.playing, " finished=", player.finished)
	player.play()
	print("JUST PLAYED: playing=", player.playing, " finished=", player.finished)
	await create_timer(0.2).timeout
	print("AFTER 0.2s: playing=", player.playing, " finished=", player.finished, " pos=", player.get_playback_position())
	await create_timer(0.5).timeout
	print("AFTER 0.7s: playing=", player.playing, " finished=", player.finished, " pos=", player.get_playback_position())
	quit(0)