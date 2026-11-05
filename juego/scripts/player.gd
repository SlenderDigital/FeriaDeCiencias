extends CharacterBody2D

signal hp_changed(new_hp: int, max_hp: int)
signal damaged(amount: int)
signal died
signal shield_changed(active: bool)
signal shield_blocked
signal shield_broken

const MAX_HP: int = 3
const MOVE_SPEED: float = 420.0
const MOVE_ACCELERATION: float = 9000.0
const TARGET_FOLLOW_SPEED: float = 950.0
const TARGET_STOP_DISTANCE: float = 4.0
const HIT_INVINCIBILITY_DURATION: float = 1.2
const PLAYER_HALF_SIZE: float = 14.0

const SHIELD_MAX_ENERGY: float = 1.0
const SHIELD_DRAIN_PER_SEC: float = 1.0 / 1.65
const SHIELD_RECHARGE_PER_SEC: float = 1.0 / 1.35
const SHIELD_RECHARGE_DELAY: float = 0.40
const SHIELD_BLOCK_FEEDBACK_COOLDOWN: float = 0.12
const SHIELD_BREAK_GRACE: float = 0.35

var current_hp: int = MAX_HP
var is_active: bool = true
var is_shielding: bool = false
var shield_held: bool = false
var shield_energy: float = SHIELD_MAX_ENERGY
var shield_exhausted: bool = false
var shield_recharge_timer: float = 0.0
var shield_block_feedback_timer: float = 0.0
var shield_block_flash: float = 0.0
var hit_invincibility_timer: float = 0.0
var hit_flash_timer: float = 0.0
var shield_activation_flash: float = 0.0
var _shield_require_release: bool = false

var target_position: Vector2 = Vector2.ZERO
var use_target_position: bool = false
var external_tracking_active: bool = false

@onready var player_glow: Polygon2D = $PlayerGlow
@onready var player_light: PointLight2D = $PlayerLight
@onready var outer_polygon: Polygon2D = $OuterPolygon
@onready var inner_polygon: Polygon2D = $InnerPolygon
@onready var shield_ring: Line2D = $ShieldRing
@onready var shield_glow: Polygon2D = $ShieldGlow


func _ready() -> void:
	Shapes.apply_radial_glow(player_glow)
	shield_glow.polygon = Shapes.circle(22.0, 32)
	shield_ring.points = Shapes.circle(22.0, 32)
	target_position = global_position
	_shield_require_release = Input.is_action_pressed("shield")
	_update_visuals(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if is_active and event is InputEventMouseMotion and not external_tracking_active:
		set_target_position((event as InputEventMouseMotion).position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		shield_held = false
		if Input.is_action_pressed("shield"):
			Input.action_release("shield")
			_shield_require_release = true
		if is_shielding:
			is_shielding = false
			shield_changed.emit(false)


func _physics_process(delta: float) -> void:
	if not is_active:
		velocity = Vector2.ZERO
		return

	hit_invincibility_timer = maxf(0.0, hit_invincibility_timer - delta)
	hit_flash_timer = maxf(0.0, hit_flash_timer - delta * 4.0)
	shield_block_flash = maxf(0.0, shield_block_flash - delta * 5.0)
	shield_activation_flash = maxf(0.0, shield_activation_flash - delta * 4.0)
	shield_block_feedback_timer = maxf(0.0, shield_block_feedback_timer - delta)

	var keyboard_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if keyboard_dir.length_squared() > 0.001 and not external_tracking_active:
		use_target_position = false

	var raw_keyboard_shield: bool = Input.is_action_pressed("shield")
	if _shield_require_release:
		if not raw_keyboard_shield:
			_shield_require_release = false
		raw_keyboard_shield = false

	_update_shield(shield_held or raw_keyboard_shield, delta)
	_move_player(delta, keyboard_dir)
	_constrain_to_viewport()
	_update_visuals(delta)


func _move_player(delta: float, keyboard_dir: Vector2) -> void:
	if use_target_position:
		var to_target: Vector2 = target_position - global_position
		var distance: float = to_target.length()
		if distance > TARGET_STOP_DISTANCE:
			var desired_speed: float = minf(TARGET_FOLLOW_SPEED, distance / maxf(delta, 0.001))
			velocity = (to_target / distance) * desired_speed
		else:
			global_position = target_position
			velocity = Vector2.ZERO
			return
	else:
		velocity = velocity.move_toward(keyboard_dir * MOVE_SPEED, MOVE_ACCELERATION * delta)

	if Engine.is_in_physics_frame():
		move_and_slide()
	else:
		global_position += velocity * delta


func _update_shield(held: bool, delta: float) -> void:
	if held and not shield_exhausted and shield_energy > 0.0:
		if not is_shielding:
			shield_activation_flash = 1.0
			SoundManager.play_sfx(&"shield_on", -3.0)
			shield_changed.emit(true)
		is_shielding = true
		shield_energy = maxf(0.0, shield_energy - SHIELD_DRAIN_PER_SEC * delta)
		shield_recharge_timer = SHIELD_RECHARGE_DELAY
		if shield_energy <= 0.0:
			is_shielding = false
			shield_exhausted = true
			hit_invincibility_timer = maxf(hit_invincibility_timer, SHIELD_BREAK_GRACE)
			SoundManager.play_sfx(&"shield_break", -3.0)
			shield_changed.emit(false)
			shield_broken.emit()
		return

	if is_shielding:
		is_shielding = false
		shield_changed.emit(false)
	if held:
		return
	shield_exhausted = false
	if shield_energy >= SHIELD_MAX_ENERGY:
		return
	if shield_recharge_timer > 0.0:
		shield_recharge_timer = maxf(0.0, shield_recharge_timer - delta)
		return
	shield_energy = minf(SHIELD_MAX_ENERGY, shield_energy + SHIELD_RECHARGE_PER_SEC * delta)


func set_shield_held(held: bool) -> void:
	shield_held = held


func get_shield_energy_ratio() -> float:
	return clampf(shield_energy / SHIELD_MAX_ENERGY, 0.0, 1.0)


func set_target_position(new_target: Vector2, is_external: bool = false) -> void:
	var view: Vector2 = get_viewport_rect().size
	target_position = Vector2(
		clampf(new_target.x, PLAYER_HALF_SIZE, view.x - PLAYER_HALF_SIZE),
		clampf(new_target.y, PLAYER_HALF_SIZE, view.y - PLAYER_HALF_SIZE)
	)
	use_target_position = true
	if is_external:
		external_tracking_active = true


func set_normalized_target_position(normalized_target: Vector2) -> void:
	var view: Vector2 = get_viewport_rect().size
	set_target_position(normalized_target * view, true)


func release_external_tracking() -> void:
	external_tracking_active = false
	shield_held = false
	velocity = Vector2.ZERO
	if is_shielding:
		is_shielding = false
		shield_changed.emit(false)
	use_target_position = false
	target_position = global_position


func is_invincible() -> bool:
	return is_shielding or hit_invincibility_timer > 0.0


func take_damage(amount: int = 1) -> void:
	if not is_active or amount <= 0 or current_hp <= 0:
		return
	if is_shielding:
		shield_block_flash = 1.0
		if shield_block_feedback_timer <= 0.0:
			shield_block_feedback_timer = SHIELD_BLOCK_FEEDBACK_COOLDOWN
			SoundManager.play_sfx(&"shield_block", -3.0)
			shield_blocked.emit()
		return
	if hit_invincibility_timer > 0.0:
		return

	current_hp = maxi(0, current_hp - amount)
	hit_invincibility_timer = HIT_INVINCIBILITY_DURATION
	hit_flash_timer = 1.0
	SoundManager.play_sfx(&"hit")
	damaged.emit(amount)
	hp_changed.emit(current_hp, MAX_HP)

	if current_hp <= 0:
		is_active = false
		is_shielding = false
		shield_held = false
		velocity = Vector2.ZERO
		died.emit()
	_update_visuals(0.0)


func reset_player(spawn_position: Vector2) -> void:
	global_position = spawn_position
	target_position = spawn_position
	use_target_position = false
	external_tracking_active = false
	velocity = Vector2.ZERO
	current_hp = MAX_HP
	is_active = true
	is_shielding = false
	shield_held = false
	shield_energy = SHIELD_MAX_ENERGY
	shield_exhausted = false
	shield_recharge_timer = 0.0
	shield_block_feedback_timer = 0.0
	shield_block_flash = 0.0
	shield_activation_flash = 0.0
	hit_invincibility_timer = 0.0
	hit_flash_timer = 0.0
	_shield_require_release = Input.is_action_pressed("shield")
	hp_changed.emit(current_hp, MAX_HP)
	shield_changed.emit(false)
	_update_visuals(0.0)


func _constrain_to_viewport() -> void:
	var view: Vector2 = get_viewport_rect().size
	global_position.x = clampf(global_position.x, PLAYER_HALF_SIZE, view.x - PLAYER_HALF_SIZE)
	global_position.y = clampf(global_position.y, PLAYER_HALF_SIZE, view.y - PLAYER_HALF_SIZE)


func _update_visuals(_delta: float) -> void:
	outer_polygon.scale = Vector2.ONE * (1.0 + hit_flash_timer * 0.16)
	var blink_on: bool = hit_invincibility_timer > 0.0 and not is_shielding and (int(hit_invincibility_timer * 16.0) % 2 == 0)
	outer_polygon.color = Color(0.35, 0.35, 0.35, 1.0) if blink_on else Color.WHITE

	var shield_boost: float = 0.28 if is_shielding else 0.0
	var flash_boost: float = 0.35 * shield_block_flash + 0.25 * shield_activation_flash + 0.22 * hit_flash_timer
	var dim_factor: float = 0.55 if blink_on else 1.0

	player_glow.visible = is_active
	var glow_alpha: float = clampf((0.42 + shield_boost * 0.5 + flash_boost) * dim_factor, 0.0, 0.92)
	player_glow.color = Color(1.0, 1.0, 1.0, glow_alpha)
	player_glow.scale = Vector2.ONE * (1.0 + (0.22 if is_shielding else 0.0) + 0.25 * shield_block_flash + 0.16 * shield_activation_flash + 0.12 * hit_flash_timer)

	player_light.enabled = is_active
	player_light.energy = (0.85 + shield_boost + flash_boost * 1.4) * dim_factor
	player_light.texture_scale = 2.5 + (0.35 if is_shielding else 0.0) + 0.40 * shield_block_flash + 0.25 * shield_activation_flash

	shield_glow.visible = is_shielding or shield_block_flash > 0.0 or shield_activation_flash > 0.0
	if shield_glow.visible:
		var low_energy: float = 0.0 if shield_energy > 0.25 else (1.0 - shield_energy / 0.25)
		var flicker: float = 1.0 - 0.25 * low_energy * (0.5 + 0.5 * sin(shield_energy * 90.0))
		shield_glow.color = Color(0.72, 0.72, 0.72, (0.10 + 0.10 * shield_block_flash + 0.08 * shield_activation_flash) * flicker)
		shield_glow.scale = Vector2.ONE * (1.0 + 0.18 * shield_block_flash + 0.10 * shield_activation_flash)

	shield_ring.visible = is_shielding or shield_block_flash > 0.0 or shield_activation_flash > 0.0
	if shield_ring.visible:
		var ring_scale: float = 1.0 + 0.08 * shield_activation_flash - 0.05 * (1.0 - get_shield_energy_ratio()) + 0.10 * shield_block_flash
		shield_ring.scale = Vector2.ONE * ring_scale
		var ring_gray: float = 0.72 + 0.28 * get_shield_energy_ratio()
		var ring_alpha: float = 0.55 + 0.35 * shield_block_flash if is_shielding else shield_block_flash
		shield_ring.default_color = Color(ring_gray, ring_gray, ring_gray, ring_alpha)

	inner_polygon.visible = current_hp < 3
	if current_hp == 2:
		inner_polygon.scale = Vector2(0.45, 0.45)
	elif current_hp == 1:
		inner_polygon.scale = Vector2(0.75, 0.75)
	else:
		inner_polygon.scale = Vector2(0.9, 0.9)
