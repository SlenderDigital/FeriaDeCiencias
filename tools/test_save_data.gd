extends SceneTree
## Test headless de persistencia: GameManager guarda/carga récord y settings
## en user://abstract_pulse.cfg (equivalente Godot del "ScriptableObject").
## No toca _ready (fullscreen/display): solo save_data/load_data/save_score.

const GM: GDScript = preload("res://scripts/GameManager.gd")
const PATH: String = "user://abstract_pulse.cfg"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var fails: Array[String] = []
	# Backup del save real (si existe) para dejar la máquina como estaba.
	var had_file: bool = FileAccess.file_exists(PATH)
	var backup: PackedByteArray = PackedByteArray()
	if had_file:
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			backup = f.get_buffer(f.get_length())
			f.close()

	var gm1: Node = GM.new()
	root.add_child(gm1)
	gm1.high_scores = {"level_first_light": 80}
	gm1.master_volume = 0.5
	gm1.music_volume = 0.6
	gm1.sfx_volume = 0.7
	gm1.save_data()
	if not FileAccess.file_exists(PATH):
		fails.append("save_data no creó " + PATH)

	var gm2: Node = GM.new()
	root.add_child(gm2)
	gm2.load_data()
	if int(gm2.get_high_score("level_first_light")) != 80:
		fails.append("load: récord= %s (esperaba 80)" % gm2.get_high_score("level_first_light"))
	if absf(float(gm2.master_volume) - 0.5) > 0.001 or absf(float(gm2.music_volume) - 0.6) > 0.001 or absf(float(gm2.sfx_volume) - 0.7) > 0.001:
		fails.append("load: volúmenes no volvieron (%.2f %.2f %.2f)" % [gm2.master_volume, gm2.music_volume, gm2.sfx_volume])

	# save_score: menor no pisa, mayor sí (y persiste).
	if gm2.save_score("level_first_light", 50):
		fails.append("save_score(50) con récord 80 devolvió true")
	if int(gm2.get_high_score("level_first_light")) != 80:
		fails.append("save_score(50) pisó el récord")
	if not gm2.save_score("level_first_light", 90):
		fails.append("save_score(90) con récord 80 devolvió false")
	var gm3: Node = GM.new()
	root.add_child(gm3)
	gm3.load_data()
	if int(gm3.get_high_score("level_first_light")) != 90:
		fails.append("récord 90 no persistió (leo %s)" % gm3.get_high_score("level_first_light"))

	# Restore: dejar el save como estaba antes del test.
	if had_file:
		var w := FileAccess.open(PATH, FileAccess.WRITE)
		if w:
			w.store_buffer(backup)
			w.close()
	else:
		DirAccess.remove_absolute(PATH)

	gm1.queue_free()
	gm2.queue_free()
	gm3.queue_free()
	if fails.is_empty():
		print("[SAVE] PASS — récord + settings persisten en user:// y save_score respeta máximo")
		quit(0)
	else:
		print("[SAVE] FAIL: ", "; ".join(fails))
		quit(1)
