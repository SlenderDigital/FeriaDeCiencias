extends SceneTree
## test_damage_coherence.gd — T10: el daño es el que declara el enemigo.
##
## Reportado por el usuario: "a veces toco algo y mi vida no baja" y "algunos
## enemigos hacen menos daño que otros, no sé si es intencional". Sí era un
## bug, y estaba en la aritmética:
##
##     dmg = 12 (easy) * abs(hit_health_bonus) / 18     <- MAL
##
## El número del enemigo se USABA COMO MULTIPLICADOR, así que un setpiece que
## pedía 18 clavaba 12 y una sierra que pedía 15 clavaba 10. El daño no venía
## del enemigo: venía de una división accidental. Por eso algunos pegaban
## menos y otros parecían no pegar.
##
## Este test verifica el contrato correcto:
##   1) todo peligro declara un daño explícito
##   2) el daño se aplica tal cual (abs), sin reescalar
##   3) la jerarquía es coherente: setpiece > proyectil > mini-jab
##   4) ningún enemigo cuesta más de 1/8 de la vida del tutorial
##      (o sea: el tutorial perdona al menos 8 golpes)

func _initialize() -> void:
	var fails: Array[String] = []

	var song := ProceduralSong.new(1337, 128.0)
	var chart := song.build_chart()
	var controller := PatternController.new(chart, Vector2(1280, 720), 128.0, 1337)
	controller.easy_mode = true

	# 1+3) Todos los patrones del chart declaran daño coherente
	var expected: Dictionary = {
		# setpieces: un momento del nivel, pegan fuerte pero justo
		"spoke_fan": 12.0, "laser_sweep": 12.0, "waveform_wall": 12.0,
		"squeeze_corridor": 12.0, "pulse_rings": 12.0, "stripe_wall": 12.0,
		# proyectiles sueltos: pican menos
		"saw": 10.0, "drifter": 10.0, "homing": 10.0, "hazard": 10.0,
		# mini-jabs: puntuación, no amenaza
		"mini_ring": 8.0, "mini_fan": 8.0,
	}
	for key in expected.keys():
		var sp: Array[Dictionary] = controller._build_pattern(str(key), 0.0, Color.WHITE, 0, {}, 7)
		if sp.is_empty():
			continue  # no todas las claves son patrones reales
		var d: Dictionary = sp[0]
		if not d.has("hit_health_bonus"):
			fails.append("%s no declara hit_health_bonus (el daño sería un default sin razón)" % key)
			continue
		var declared: float = absf(float(d["hit_health_bonus"]))
		var want: float = float(expected[key])
		if absf(declared - want) > 0.01:
			fails.append("%s declara %.0f de daño, esperaba %.0f" % [key, declared, want])

	# 2) Gameplay aplica el daño TAL CUAL: sin la división que lo rompía.
	var src: String = FileAccess.get_file_as_string("res://scripts/Gameplay.gd")
	if src.contains("absf(source_bonus) / 18.0"):
		fails.append("Gameplay sigue tratando hit_health_bonus como multiplicador (la división rota)")
	if not src.contains("dmg: float = source_bonus if source_bonus != 0.0"):
		fails.append("Gameplay no aplica el daño declarado tal cual")

	# 4) Ningún enemigo puede costar más de 1/8 de la vida del tutorial.
	const EASY_HP: float = 125.0
	const MAX_FRACTION: float = 0.125
	var worst: float = 0.0
	var worst_key: String = ""
	for k2 in expected.keys():
		var v: float = float(expected[k2])
		if v > worst:
			worst = v
			worst_key = str(k2)
	if worst > EASY_HP * MAX_FRACTION:
		fails.append("%s cuesta %.0f de %.0f HP = 1/%.1f golpes: el tutorial no perdona" % [
			worst_key, worst, EASY_HP, EASY_HP / worst])
	# y la jerarquía se lee de abajo hacia arriba
	var j_d: float = float(expected["mini_ring"])
	var p_d: float = float(expected["saw"])
	var s_d: float = float(expected["spoke_fan"])
	if not (j_d < p_d and p_d < s_d):
		fails.append("la jerarquía de daño no es monótona: jab < proyectil < setpiece")

	_finish(fails)

func _finish(fails: Array[String]) -> void:
	if fails.is_empty():
		print("[DMG] PASS — el daño es el que declara cada enemigo (8/10/12), sin reescalar, y el tutorial perdona 10+ golpes")
		quit(0)
	else:
		for f in fails:
			print("[DMG] FAIL: %s" % f)
		quit(1)
