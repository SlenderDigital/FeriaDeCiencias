extends "res://scripts/level.gd"

const INTRO_FULL_DURATION: float = 4.0 * BossConstants.BEAT_DURATION
const INTRO_RETRY_DURATION: float = 0.45
const INTRO_DISMISS_DURATION: float = 0.32

var is_intro_active: bool = false
var _intro_timer: float = 0.0
var _intro_duration: float = INTRO_FULL_DURATION
var _intro_quick_mode: bool = false
var _intro_slam_fired: bool = false
var _intro_hands_fired: bool = false
var _intro_dismiss_timer: float = 0.0
var _is_retry_restart: bool = false
var _intro_skip_guard: float = 0.0

var _healed_phase_5: bool = false
var _healed_phase_7: bool = false
var _last_healed_phase: int = 1
var _last_boss_phase: int = 1
var _boss_signals_connected: bool = false

var _last_shield_raise_time: float = -10.0
var _parry_cooldown: float = 0.0
var total_parries: int = 0

var _gravity_target_active: bool = false
var _gravity_base_target: Vector2 = Vector2.ZERO
var _gravity_last_applied_target: Vector2 = Vector2.ZERO

var boss_hazard_layer: Node2D = null
var boss_hex_grid: BossHexGrid = null
var boss_bullet_manager: BossBulletManager = null
var boss_choreographer: BossChoreographer = null

@onready var boss_container: Node2D = $BossContainer
@onready var boss: Area2D = $BossContainer/Boss


func _ready() -> void:
	level_duration = GameManager.BOSS_LEVEL_DURATION
	_setup_boss_layers()
	_connect_boss_signals()
	super._ready()


func _setup_boss_layers() -> void:
	if boss_hazard_layer == null:
		boss_hazard_layer = Node2D.new()
		boss_hazard_layer.name = "BossHazardLayer"
		add_child(boss_hazard_layer)
		if arena_grid != null:
			move_child(boss_hazard_layer, arena_grid.get_index() + 1)

	if boss_hex_grid == null:
		boss_hex_grid = BossHexGrid.new()
		boss_hex_grid.name = "BossHexGrid"
		boss_hazard_layer.add_child(boss_hex_grid)

	if boss_bullet_manager == null:
		boss_bullet_manager = BossBulletManager.new()
		boss_bullet_manager.name = "BossBulletManager"
		boss_bullet_manager.z_index = 1
		boss_hazard_layer.add_child(boss_bullet_manager)

	if boss_container != null and beam_container != null and boss_container.get_index() > beam_container.get_index():
		move_child(boss_container, beam_container.get_index())

	if boss_choreographer == null:
		boss_choreographer = BossChoreographer.new()
		boss_choreographer.setup(self, boss, beam_container, boss_hex_grid, boss_bullet_manager, arena_fx, arena_grid)


func _resolve_difficulty() -> int:
	return GameManager.Difficulty.BOSS


func _start_music() -> void:
	if DisplayServer.get_name() == "headless":
		SoundManager.play_boss_music(1.0)


func _on_retry_pressed() -> void:
	_is_retry_restart = true
	super._on_retry_pressed()
	_is_retry_restart = false


func restart_level() -> void:
	is_intro_active = false
	_intro_timer = 0.0
	_intro_duration = INTRO_FULL_DURATION
	_intro_quick_mode = false
	_intro_slam_fired = false
	_intro_hands_fired = false
	_intro_dismiss_timer = 0.0
	_intro_skip_guard = 0.0
	_healed_phase_5 = false
	_healed_phase_7 = false
	_last_healed_phase = 1
	_last_boss_phase = 1
	_last_shield_raise_time = -10.0
	_parry_cooldown = 0.0
	total_parries = 0
	_gravity_target_active = false
	_gravity_base_target = Vector2.ZERO
	_gravity_last_applied_target = Vector2.ZERO

	super.restart_level()

	if player != null:
		player.scale = Vector2(BossConstants.BOSS_PLAYER_SCALE, BossConstants.BOSS_PLAYER_SCALE)

	hud.configure_boss_hud(true, GameManager.BOSS_TOTAL_PHASES)
	hud.update_boss_phase(1, GameManager.BOSS_TOTAL_PHASES)
	if hud != null and hud.has_method("set_controls_hint_alpha"):
		hud.set_controls_hint_alpha(1.0)

	if boss_hex_grid != null:
		boss_hex_grid.set_arena_size(_arena_size)
		boss_hex_grid.clear()
	if boss_bullet_manager != null:
		boss_bullet_manager.arena_size = _arena_size
		boss_bullet_manager.clear()
	if boss != null and boss.has_method("reset_boss"):
		boss.reset_boss(_arena_size)
	if boss_choreographer != null:
		boss_choreographer.reset()
	if hud != null and hud.has_method(&"hide_boss_intro"):
		hud.hide_boss_intro()
	if DisplayServer.get_name() != "headless":
		start_intro(_is_retry_restart)


func start_intro(quick_mode: bool = false) -> void:
	is_intro_active = true
	_intro_quick_mode = quick_mode
	_intro_timer = 0.0
	_intro_duration = INTRO_RETRY_DURATION if quick_mode else INTRO_FULL_DURATION
	_intro_slam_fired = false
	_intro_hands_fired = false
	_intro_skip_guard = 0.0
	_intro_dismiss_timer = 0.0
	elapsed_time = 0.0
	if boss != null and boss.has_method(&"set_intro_state"):
		boss.set_intro_state(true, 0.0, _arena_size, quick_mode)
	if hud != null and hud.has_method(&"update_boss_intro"):
		hud.update_boss_intro(true, 0.0, 0.0, quick_mode)
	if not quick_mode:
		SoundManager.play_boss_intro(1.0)


func skip_intro() -> void:
	if is_intro_active:
		_finish_intro()


func _finish_intro() -> void:
	if not is_intro_active:
		return
	is_intro_active = false
	_intro_dismiss_timer = INTRO_DISMISS_DURATION
	if boss != null and boss.has_method(&"set_intro_state"):
		boss.set_intro_state(false, 1.0, _arena_size, false)
	if hud != null and hud.has_method(&"update_boss_intro"):
		hud.update_boss_intro(false, 1.0, 0.0, _intro_quick_mode)
	SoundManager.play_boss_music(1.0)
	arena_grid.pulse(0.65)


func _unhandled_input(event: InputEvent) -> void:
	if is_intro_active and _intro_skip_guard >= 0.30:
		if event.is_action_pressed("shield") or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
			skip_intro()
			var vp: Viewport = get_viewport()
			if vp != null:
				vp.set_input_as_handled()


func simulate_physics(delta: float) -> void:
	if is_intro_active:
		_sync_hand_tracking_to_gameplay(delta)
		hud.update_shield(player.get_shield_energy_ratio(), player.is_shielding, player.shield_exhausted)
		if not is_level_running:
			return
		var dt: float = maxf(delta, 0.0)
		_intro_timer += dt
		_intro_skip_guard += dt
		var p: float = clampf(_intro_timer / maxf(_intro_duration, 0.001), 0.0, 1.0)
		if boss != null and boss.has_method(&"set_intro_state"):
			boss.set_intro_state(true, p, _arena_size, _intro_quick_mode)
		if hud != null and hud.has_method(&"update_boss_intro"):
			hud.update_boss_intro(true, p, 0.0, _intro_quick_mode)

		var s_vec: Vector2 = Vector2(_arena_size.x / 1152.0, _arena_size.y / 648.0)
		var center_pos: Vector2 = Vector2(576.0 * s_vec.x, 152.0 * s_vec.y)
		var slam_p: float = 0.45 if _intro_quick_mode else 0.50
		if not _intro_slam_fired and p >= slam_p:
			_intro_slam_fired = true
			if arena_fx != null:
				arena_fx.spawn_ring(center_pos, 18.0, 140.0, 0.42, Color(0.96, 0.96, 0.96, 0.92), 2.6)
				arena_fx.spawn_burst(center_pos, 14, 240.0, Color(0.92, 0.92, 0.92, 1.0), 0.36, 10.0, 2.0)
			arena_grid.pulse(0.85)
			trigger_screen_shake(4.8, 0.22)
			if _intro_quick_mode:
				SoundManager.play_sfx(&"wall_slam", -4.0)

		if not _intro_quick_mode and not _intro_hands_fired and p >= 0.64:
			_intro_hands_fired = true
			if arena_fx != null:
				arena_fx.spawn_ring(center_pos + Vector2(-112.0 * s_vec.x, 18.0 * s_vec.y), 10.0, 62.0, 0.30, Color(0.94, 0.94, 0.94, 0.85), 2.0)
				arena_fx.spawn_ring(center_pos + Vector2(112.0 * s_vec.x, 18.0 * s_vec.y), 10.0, 62.0, 0.30, Color(0.94, 0.94, 0.94, 0.85), 2.0)

		if _intro_timer >= _intro_duration:
			_finish_intro()
		return

	if _intro_dismiss_timer > 0.0:
		_intro_dismiss_timer = maxf(0.0, _intro_dismiss_timer - maxf(delta, 0.0))
		var dismiss_t: float = 1.0 - (_intro_dismiss_timer / INTRO_DISMISS_DURATION)
		if hud != null and hud.has_method(&"update_boss_intro"):
			hud.update_boss_intro(false, 1.0, dismiss_t, _intro_quick_mode)

	super.simulate_physics(delta)


func _clear_hazards() -> void:
	super._clear_hazards()
	if boss_hex_grid != null:
		boss_hex_grid.clear()
	if boss_bullet_manager != null:
		boss_bullet_manager.clear()
	if boss_choreographer != null:
		boss_choreographer.clear_transient_refs()


func _on_viewport_resized() -> void:
	super._on_viewport_resized()
	if boss_hex_grid != null:
		boss_hex_grid.set_arena_size(_arena_size)
	if boss_bullet_manager != null:
		boss_bullet_manager.arena_size = _arena_size


func _update_spawning(delta: float) -> void:
	_parry_cooldown = maxf(0.0, _parry_cooldown - maxf(delta, 0.0))
	var song_time: float = SoundManager.get_boss_playback_time(elapsed_time)

	# Step existing hazards BEFORE dispatching new cues on this tick so newly spawned
	# telegraphs with warning_time = (impact_beat - song_beat) * BEAT_DURATION don't
	# jump 1 frame early in headless manual simulate_physics() loops.
	if not Engine.is_in_physics_frame():
		if boss_hex_grid != null:
			boss_hex_grid.simulate_physics(delta, player)
		if boss_bullet_manager != null:
			boss_bullet_manager.simulate_physics(delta, _arena_size, player)
		if beam_container != null:
			var children: Array[Node] = beam_container.get_children()
			for child: Node in children:
				if not is_instance_valid(child) or child.is_queued_for_deletion():
					continue
				if child.has_method(&"simulate_physics"):
					child.simulate_physics(delta, player)
				elif child.is_in_group("boss_filling_circle") and child.has_method(&"_physics_process"):
					child._physics_process(delta)

	if boss_choreographer != null:
		boss_choreographer.advance(delta, song_time, _arena_size, player)

	if boss != null and boss.has_method("simulate_boss"):
		boss.simulate_boss(delta, song_time, _arena_size, player)

	_apply_gravity_well_pull(delta)
	_check_boss_phase_and_heals()


func _apply_gravity_well_pull(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not player.is_active:
		return

	var wells: Array[BossGravityWell] = []
	if boss_choreographer != null:
		for w: BossGravityWell in boss_choreographer.get_active_gravity_wells():
			if w.is_hazard_active:
				wells.append(w)
	if beam_container != null:
		for child: Node in beam_container.get_children():
			if child is BossGravityWell and is_instance_valid(child) and not child.is_queued_for_deletion():
				var gw: BossGravityWell = child as BossGravityWell
				if gw.is_hazard_active and not wells.has(gw):
					wells.append(gw)

	var margin: float = player.PLAYER_HALF_SIZE
	if wells.is_empty():
		if _gravity_target_active:
			_gravity_target_active = false
			if player.use_target_position and player.target_position.distance_squared_to(_gravity_last_applied_target) < 1.0:
				player.target_position = _clamp_player_pos(_gravity_base_target, margin)
		return

	var total_pull: Vector2 = Vector2.ZERO
	for w: BossGravityWell in wells:
		total_pull += w.get_pull_displacement(player.global_position, delta, player.use_target_position)

	if total_pull.length_squared() <= 0.00001:
		return

	if player.use_target_position:
		if not _gravity_target_active or player.target_position.distance_squared_to(_gravity_last_applied_target) > 1.0:
			_gravity_base_target = player.target_position
		_gravity_target_active = true
		var pulled_target: Vector2 = _clamp_player_pos(_gravity_base_target + total_pull, margin)
		player.target_position = pulled_target
		_gravity_last_applied_target = pulled_target
	else:
		_gravity_target_active = false
		player.global_position = _clamp_player_pos(player.global_position + total_pull, margin)


func _clamp_player_pos(pos: Vector2, margin: float) -> Vector2:
	return Vector2(
		clampf(pos.x, margin, maxf(_arena_size.x - margin, margin)),
		clampf(pos.y, margin, maxf(_arena_size.y - margin, margin))
	)


func _update_music_reactivity() -> void:
	if not SoundManager.is_music_playing():
		return
	var song_time: float = SoundManager.get_boss_playback_time(elapsed_time)
	var beat_idx: int = int(floor(song_time / SoundManager.BEAT_DURATION))
	var section: int = SoundManager.get_boss_section(song_time)
	var beat_phase: float = SoundManager.get_beat_phase(song_time)
	var beat_energy: float = SoundManager.get_boss_beat_intensity(song_time)

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
		player.shield_changed.connect(_on_boss_player_shield_changed)
		player.shield_blocked.connect(_on_boss_player_shield_blocked)
		player.damaged.connect(_on_boss_player_damaged)
	if boss == null:
		return
	boss.request_clear_hazards.connect(_clear_hazards)
	boss.boss_slammed.connect(_on_boss_slammed)
	boss.boss_wall_slammed.connect(_on_boss_wall_slammed)
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
	while _last_healed_phase < cur_phase:
		_last_healed_phase += 1
		_apply_phase_heal(_last_healed_phase)


func _on_boss_phase_changed(new_phase: int) -> void:
	if not is_level_running:
		return
	var clamped_phase: int = clampi(new_phase, 1, GameManager.BOSS_TOTAL_PHASES)
	if clamped_phase == _last_boss_phase:
		return
	_last_boss_phase = clamped_phase
	hud.update_boss_phase(clamped_phase, GameManager.BOSS_TOTAL_PHASES)
	if hud != null and hud.has_method("set_controls_hint_alpha"):
		hud.set_controls_hint_alpha(1.0 if clamped_phase <= 1 else 0.15)
	if clamped_phase > 1:
		SoundManager.play_sfx(&"boss_phase", -2.0)
	while _last_healed_phase < clamped_phase:
		_last_healed_phase += 1
		_apply_phase_heal(_last_healed_phase)


func _apply_phase_heal(phase: int) -> void:
	if not is_level_running:
		return
	if phase < 2 or phase > GameManager.BOSS_TOTAL_PHASES:
		return
	var full_shield: bool = (phase == 5 or phase == 7)
	if phase == 5:
		_healed_phase_5 = true
	elif phase == 7:
		_healed_phase_7 = true
	if player != null and player.is_active and player.current_hp > 0:
		player.heal(1, full_shield)
		GameManager.report_live_telemetry(elapsed_time, level_duration, player.current_hp, player.MAX_HP)
		if arena_fx != null:
			if full_shield:
				arena_fx.spawn_ring(player.global_position, 14.0, 92.0, 0.48, Color(1.0, 1.0, 1.0, 0.92), 2.4)
				arena_fx.spawn_burst(player.global_position, 14, 210.0, Color(0.95, 0.95, 0.95, 1.0), 0.36, 9.0, 1.8)
			else:
				arena_fx.spawn_ring(player.global_position, 14.0, 64.0, 0.36, Color(0.90, 0.90, 0.90, 0.72), 2.0)


func _on_boss_slammed(at_position: Vector2, strength: float) -> void:
	arena_grid.pulse(clampf(strength, 0.15, 1.0))
	if (boss != null and bool(boss._shattered)) or strength >= 0.99:
		trigger_screen_shake(4.5, 0.22)
	else:
		trigger_screen_shake(clampf(strength * 3.8, 1.4, 3.6), 0.12)
	if arena_fx != null:
		arena_fx.spawn_ring(at_position, 16.0, 76.0, 0.32, Color(0.92, 0.92, 0.92, 0.85), 2.2)


func _on_boss_wall_slammed(wall_pos: Vector2, inward_normal: Vector2, strength: float) -> void:
	if arena_fx != null:
		arena_fx.spawn_directional_burst(wall_pos, inward_normal, deg_to_rad(56.0), 9, 300.0, Color(0.86, 0.86, 0.86, 0.85), 0.30, 10.0, 1.8)
		arena_fx.spawn_ring(wall_pos, 12.0, 84.0, 0.28, Color(0.90, 0.90, 0.90, 0.68), 2.0)
	arena_grid.pulse(clampf(strength * 0.72, 0.18, 0.75))
	trigger_screen_shake(clampf(strength * 4.2, 1.5, 3.8), 0.13)


func _on_boss_player_shield_changed(active: bool) -> void:
	if active and is_level_running:
		_last_shield_raise_time = elapsed_time


func _on_boss_player_shield_blocked() -> void:
	if not is_level_running:
		return
	if boss != null and boss.has_method("on_player_shield_blocked"):
		boss.on_player_shield_blocked()

	if player == null or not is_instance_valid(player):
		return

	var hit_parryable: bool = bool(player.get_meta(&"last_hit_parryable", true))
	var within_parry_window: bool = (
		(elapsed_time - _last_shield_raise_time) <= BossConstants.PARRY_WINDOW_SEC
		or player.shield_activation_flash > 0.20
	)
	var boss_dormant_collapse: bool = (
		boss != null
		and int(boss.acting_state) == int(boss.ActingState.FAKE_OUT_COLLAPSE)
		and not bool(boss._phase5_hands_awake)
	)
	if hit_parryable and within_parry_window and _parry_cooldown <= 0.0 and not boss_dormant_collapse:
		_execute_parry()


func _execute_parry() -> void:
	_parry_cooldown = BossConstants.PARRY_COOLDOWN_SEC
	total_parries += 1

	player.shield_energy = minf(player.SHIELD_MAX_ENERGY, player.shield_energy + BossConstants.PARRY_SHIELD_REFUND)
	player.shield_exhausted = false
	hud.update_shield(player.get_shield_energy_ratio(), player.is_shielding, player.shield_exhausted)

	if boss != null and boss.has_method("on_player_parried"):
		boss.on_player_parried(player.global_position)

	if player.has_meta(&"last_hit_hazard_kind") and StringName(player.get_meta(&"last_hit_hazard_kind")) == &"glitch_wave":
		_purge_active_glitch_waves()

	if arena_fx != null:
		var p_pos: Vector2 = player.global_position
		var b_pos: Vector2 = boss.global_position if boss != null else (_arena_size * 0.5)
		var to_boss: Vector2 = (b_pos - p_pos).normalized() if b_pos.distance_squared_to(p_pos) > 1.0 else Vector2.UP
		arena_fx.spawn_ring(p_pos, 18.0, 128.0, 0.36, Color(1.0, 1.0, 1.0, 1.0), 3.0)
		arena_fx.spawn_ring(p_pos.lerp(b_pos, 0.5), 10.0, 82.0, 0.30, Color(0.92, 0.92, 0.92, 0.85), 2.0)
		arena_fx.spawn_directional_burst(p_pos, to_boss, deg_to_rad(28.0), 16, 460.0, Color(1.0, 1.0, 1.0, 1.0), 0.34, 13.0, 2.2)

	arena_grid.pulse(0.75)
	trigger_screen_shake(3.8, 0.16)
	SoundManager.play_sfx(&"boss_phase", -4.0)


func _purge_active_glitch_waves() -> void:
	if boss_choreographer != null:
		boss_choreographer.purge_active_glitch_waves()
	if beam_container != null:
		for child: Node in beam_container.get_children():
			if child is BossGlitchWave and is_instance_valid(child) and not child.is_queued_for_deletion():
				(child as BossGlitchWave).purge_by_parry()


func _on_boss_player_damaged(_amount: int) -> void:
	if is_level_running and boss != null and boss.has_method("on_player_damaged"):
		boss.on_player_damaged()
