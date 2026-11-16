extends "res://scripts/level.gd"

var _healed_phase_5: bool = false
var _healed_phase_7: bool = false
var _last_boss_phase: int = 1
var _boss_signals_connected: bool = false

@onready var boss_container: Node2D = $BossContainer
@onready var boss: Area2D = $BossContainer/Boss


func _ready() -> void:
	level_duration = GameManager.BOSS_LEVEL_DURATION
	if boss_container != null and beam_container != null and boss_container.get_index() > beam_container.get_index():
		move_child(boss_container, beam_container.get_index())
	_connect_boss_signals()
	super._ready()


func _resolve_difficulty() -> int:
	return GameManager.Difficulty.BOSS


func _start_music() -> void:
	SoundManager.play_boss_music(1.0)


func restart_level() -> void:
	_healed_phase_5 = false
	_healed_phase_7 = false
	_last_boss_phase = 1
	super.restart_level()
	hud.configure_boss_hud(true, GameManager.BOSS_TOTAL_PHASES)
	hud.update_boss_phase(1, GameManager.BOSS_TOTAL_PHASES)
	if boss != null and boss.has_method("reset_boss"):
		boss.reset_boss(_arena_size)


func _update_spawning(delta: float) -> void:
	if boss != null and boss.has_method("simulate_boss"):
		boss.simulate_boss(delta, elapsed_time, _arena_size, player)
	_check_boss_phase_and_heals()


func _update_music_reactivity() -> void:
	if not SoundManager.is_music_playing():
		return
	var beat_idx: int = int(floor(elapsed_time / SoundManager.BEAT_DURATION))
	var section: int = SoundManager.get_boss_section(elapsed_time)
	var beat_phase: float = SoundManager.get_beat_phase(elapsed_time)
	var beat_energy: float = SoundManager.get_boss_beat_intensity(elapsed_time)

	if beat_energy <= 0.001:
		_last_music_beat_idx = maxi(_last_music_beat_idx, beat_idx)
		current_music_section = section
		arena_grid.pulse_strength = 0.0
		arena_grid.set_music_state(0.0, 0.0, current_music_section)
		return

	if beat_idx > _last_music_beat_idx:
		_last_music_beat_idx = beat_idx
		var base_pulse: float = 0.26 if (beat_idx % 4 == 0) else 0.13
		arena_grid.pulse(base_pulse * beat_energy)

	if section != current_music_section:
		current_music_section = section
		if section > 0 and beat_energy > 0.45:
			var high_energy: bool = section >= 5
			var max_r: float = 260.0 if high_energy else 190.0
			arena_fx.spawn_ring(_arena_size * 0.5, 24.0, max_r, 0.48, Color(0.82, 0.82, 0.82, 0.45), 2.2)
			arena_grid.pulse(0.58 if high_energy else 0.42)

	arena_grid.set_music_state(beat_phase, beat_energy, current_music_section)


func trigger_level_complete() -> void:
	if not is_level_running:
		return
	if boss != null and boss.has_method("shatter"):
		boss.shatter()
	if arena_fx != null:
		var shatter_pos: Vector2 = boss.global_position if boss != null else _arena_size * 0.5
		arena_fx.spawn_ring(shatter_pos, 24.0, 260.0, 0.65, Color(1.0, 1.0, 1.0, 0.95), 3.0)
		arena_fx.spawn_burst(shatter_pos, 24, 340.0, Color(0.95, 0.95, 0.95, 1.0), 0.55, 14.0, 2.5)
	hud.update_boss_phase(GameManager.BOSS_TOTAL_PHASES, GameManager.BOSS_TOTAL_PHASES)
	super.trigger_level_complete()


func _build_victory_subtitle(is_record: bool, rank: int) -> String:
	var badge: String = " ★ NEW RECORD! ★" if is_record else ""
	var rank_str: String = " [Rank #%d]" % rank if rank > 0 else ""
	return "%s: BOSS DEFEATED! All 8/8 Phases (%.1fs)%s%s" % [GameManager.get_player_name(), level_duration, badge, rank_str]


func _build_game_over_subtitle(is_record: bool, rank: int) -> String:
	var badge: String = " ★ NEW RECORD! ★" if is_record else ""
	var rank_str: String = " [Rank #%d]" % rank if rank > 0 else ""
	var phase: int = _get_current_boss_phase()
	return "%s: Survived to Phase %d/8 (%.1fs)%s%s" % [GameManager.get_player_name(), phase, elapsed_time, badge, rank_str]


func _connect_boss_signals() -> void:
	if _boss_signals_connected:
		return
	_boss_signals_connected = true
	if player != null:
		player.shield_blocked.connect(_on_boss_player_shield_blocked)
		player.damaged.connect(_on_boss_player_damaged)
	if boss == null:
		return
	boss.request_beam.connect(spawn_beam)
	boss.request_circle.connect(spawn_circle)
	boss.request_projectile.connect(spawn_projectile)
	boss.request_exploder.connect(spawn_exploder)
	boss.request_saw.connect(spawn_saw)
	boss.request_closing_wall.connect(spawn_closing_wall)
	boss.request_enemy.connect(spawn_enemy)
	boss.request_clear_hazards.connect(_clear_hazards)
	boss.boss_slammed.connect(_on_boss_slammed)
	boss.phase_changed.connect(_on_boss_phase_changed)


func _get_current_boss_phase() -> int:
	if boss != null and "current_phase" in boss:
		return clampi(int(boss.current_phase), 1, GameManager.BOSS_TOTAL_PHASES)
	return GameManager.get_boss_phase_for_time(elapsed_time, false)


func _check_boss_phase_and_heals() -> void:
	if not is_level_running:
		return
	var cur_phase: int = _get_current_boss_phase()
	if cur_phase != _last_boss_phase:
		_on_boss_phase_changed(cur_phase)
	if elapsed_time >= 60.0 and elapsed_time < 90.0 and not _healed_phase_5:
		_apply_phase_heal(5)
	if elapsed_time >= 90.0 and not _healed_phase_7:
		_apply_phase_heal(7)


func _on_boss_phase_changed(new_phase: int) -> void:
	if not is_level_running:
		return
	var clamped_phase: int = clampi(new_phase, 1, GameManager.BOSS_TOTAL_PHASES)
	if clamped_phase == _last_boss_phase:
		return
	_last_boss_phase = clamped_phase
	hud.update_boss_phase(clamped_phase, GameManager.BOSS_TOTAL_PHASES)
	if clamped_phase > 1:
		SoundManager.play_sfx(&"boss_phase", -2.0)
	if clamped_phase == 5 and not _healed_phase_5:
		_apply_phase_heal(5)
	elif clamped_phase == 7 and not _healed_phase_7:
		_apply_phase_heal(7)


func _apply_phase_heal(phase: int) -> void:
	if not is_level_running:
		return
	if phase == 5:
		if _healed_phase_5:
			return
		_healed_phase_5 = true
	elif phase == 7:
		if _healed_phase_7:
			return
		_healed_phase_7 = true
	else:
		return
	if player != null and player.is_active and player.current_hp > 0:
		player.heal(1, true)
		GameManager.report_live_telemetry(elapsed_time, level_duration, player.current_hp, player.MAX_HP)
		if arena_fx != null:
			arena_fx.spawn_ring(player.global_position, 14.0, 92.0, 0.48, Color(1.0, 1.0, 1.0, 0.92), 2.4)
			arena_fx.spawn_burst(player.global_position, 14, 210.0, Color(0.95, 0.95, 0.95, 1.0), 0.36, 9.0, 1.8)


func _on_boss_slammed(at_position: Vector2, strength: float) -> void:
	arena_grid.pulse(clampf(strength, 0.15, 1.0))
	trigger_screen_shake(clampf(strength * 6.0, 1.8, 7.0), 0.20)
	if arena_fx != null:
		arena_fx.spawn_ring(at_position, 16.0, 76.0, 0.32, Color(0.92, 0.92, 0.92, 0.85), 2.2)


func _on_boss_player_shield_blocked() -> void:
	if is_level_running and boss != null and boss.has_method("on_player_shield_blocked"):
		boss.on_player_shield_blocked()


func _on_boss_player_damaged(_amount: int) -> void:
	if is_level_running and boss != null and boss.has_method("on_player_damaged"):
		boss.on_player_damaged()
