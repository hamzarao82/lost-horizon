class_name Player
extends CharacterBody3D
## Camera-relative movement, dodge with i-frames, light/heavy combo attacks.

signal stamina_changed(current: float, maximum: float)

enum State { FREE, DODGE, ATTACK, HIT, DEAD }

const FPS: float = 60.0
const CHAIN_PATHS: Array[String] = [
	"res://resources/attacks/light_1.tres",
	"res://resources/attacks/light_2.tres",
	"res://resources/attacks/heavy_1.tres",
]
const HEAVY_INDEX: int = 2
const AIM_ASSIST_RANGE: float = 4.0

## Tests turn this off; they drive actions without a captured mouse.
static var require_mouse_capture: bool = true

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 6.0
@export var acceleration: float = 40.0
@export var air_acceleration: float = 12.0
@export var turn_speed: float = 14.0

@export var max_stamina: float = 100.0
@export var stamina_regen: float = 30.0
@export var stamina_regen_delay: float = 0.6
@export var dodge_speed: float = 11.0
@export var dodge_duration: float = 0.38
@export var dodge_iframes: float = 0.18
@export var dodge_stamina: float = 20.0
@export var input_buffer: float = 0.2

@onready var health: HealthComponent = $HealthComponent
@onready var _visual_root: Node3D = $VisualRoot
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _weapon_pivot: Node3D = $VisualRoot/WeaponPivot
@onready var _hitbox: Hitbox = $VisualRoot/WeaponPivot/Hitbox

var state: State = State.FREE
var stamina: float = 100.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _chain: Array[AttackData] = []
var _stamina_delay: float = 0.0
var _buffer: StringName = &""
var _buffer_time: float = 0.0
var _dodge_time: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _attack_idx: int = -1
var _attack_frames: float = 0.0
var _hit_time: float = 0.0


func _ready() -> void:
	add_to_group("player")
	HitStop.reset()
	for path in CHAIN_PATHS:
		_chain.append(load(path) as AttackData)
	stamina = max_stamina
	health.died.connect(_die)
	_hitbox.hit.connect(_on_hit_landed)


func is_invulnerable() -> bool:
	return state == State.DODGE and _dodge_time < dodge_iframes


func is_dead() -> bool:
	return state == State.DEAD


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_poll_input(delta)
	_regen_stamina(delta)
	match state:
		State.FREE:
			_state_free(delta)
		State.DODGE:
			_state_dodge(delta)
		State.ATTACK:
			_state_attack(delta)
		State.HIT:
			_state_hit(delta)
		State.DEAD:
			_decelerate(delta, 20.0)
	_visual_root.scale.y = 0.6 if state == State.DODGE else 1.0
	_weapon_pivot.visible = state == State.ATTACK
	move_and_slide()


# --- input -----------------------------------------------------------------

func _poll_input(delta: float) -> void:
	_buffer_time -= delta
	if _buffer_time <= 0.0:
		_buffer = &""
	# The click that (re)captures the mouse must not also swing the weapon.
	var attacks_allowed := not require_mouse_capture or TouchControls.touch_active \
			or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if Input.is_action_just_pressed("dodge"):
		_set_buffer(&"dodge")
	elif attacks_allowed and Input.is_action_just_pressed("attack_heavy"):
		_set_buffer(&"heavy")
	elif attacks_allowed and Input.is_action_just_pressed("attack_light"):
		_set_buffer(&"light")


func _set_buffer(kind: StringName) -> void:
	_buffer = kind
	_buffer_time = input_buffer


func _input_direction() -> Vector3:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var yaw_basis := Basis(Vector3.UP, _camera_pivot.global_rotation.y)
	return yaw_basis * Vector3(input_dir.x, 0.0, input_dir.y)


func _regen_stamina(delta: float) -> void:
	_stamina_delay -= delta
	if _stamina_delay <= 0.0 and stamina < max_stamina:
		_set_stamina(minf(stamina + stamina_regen * delta, max_stamina))


func _spend_stamina(amount: float) -> void:
	_set_stamina(stamina - amount)
	_stamina_delay = stamina_regen_delay


func _set_stamina(value: float) -> void:
	stamina = value
	stamina_changed.emit(stamina, max_stamina)


# --- states ----------------------------------------------------------------

func _state_free(delta: float) -> void:
	var direction := _input_direction()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var accel := acceleration if is_on_floor() else air_acceleration
	var target := direction * speed
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if direction.length_squared() > 0.001:
		_turn_toward(direction, delta)
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	match _buffer:
		&"dodge":
			_try_dodge()
		&"light":
			_start_attack(0)
		&"heavy":
			_start_attack(HEAVY_INDEX)


func _state_dodge(delta: float) -> void:
	_dodge_time += delta
	var speed := dodge_speed * lerpf(1.0, 0.35, clampf(_dodge_time / dodge_duration, 0.0, 1.0))
	velocity.x = _dodge_dir.x * speed
	velocity.z = _dodge_dir.z * speed
	if _dodge_time >= dodge_duration:
		state = State.FREE


func _state_attack(delta: float) -> void:
	var data := _chain[_attack_idx]
	_attack_frames += delta * FPS
	var active_start := float(data.startup_frames)
	var active_end := active_start + data.active_frames
	var total := active_end + data.recovery_frames

	if _attack_frames < active_end:
		var facing := -_visual_root.global_transform.basis.z
		velocity.x = facing.x * data.lunge_speed
		velocity.z = facing.z * data.lunge_speed
	else:
		_decelerate(delta, 30.0)

	var in_active := _attack_frames >= active_start and _attack_frames < active_end
	if in_active and not _hitbox.is_active():
		_hitbox.activate(data, self)
	elif not in_active and _hitbox.is_active():
		_hitbox.deactivate()

	_update_weapon_visual(data, active_end)

	if _attack_frames >= active_end:
		if _buffer == &"dodge":
			if _try_dodge():
				return
		elif _buffer == &"light" or _buffer == &"heavy":
			var next := _next_attack(_buffer == &"heavy")
			if next < 0:
				_buffer = &""  # end of chain: don't carry the press into a fresh attack
			elif _start_attack(next):
				return
	if _attack_frames >= total:
		_end_attack()


func _state_hit(delta: float) -> void:
	_hit_time -= delta
	_decelerate(delta, 20.0)
	if _hit_time <= 0.0:
		state = State.FREE


func _decelerate(delta: float, rate: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, rate * delta)
	velocity.z = move_toward(velocity.z, 0.0, rate * delta)


func _turn_toward(direction: Vector3, delta: float) -> void:
	var target_yaw := atan2(-direction.x, -direction.z)
	_visual_root.rotation.y = lerp_angle(_visual_root.rotation.y, target_yaw, turn_speed * delta)


# --- dodge -----------------------------------------------------------------

func _try_dodge() -> bool:
	_buffer = &""
	if stamina < dodge_stamina:
		return false
	_spend_stamina(dodge_stamina)
	var dir := _input_direction()
	if dir.length_squared() > 0.001:
		_visual_root.rotation.y = atan2(-dir.x, -dir.z)
	else:
		dir = _visual_root.global_transform.basis.z  # back-step
	_dodge_dir = dir.normalized()
	_dodge_time = 0.0
	_end_attack()
	state = State.DODGE
	return true


# --- attacks ---------------------------------------------------------------

func _next_attack(heavy: bool) -> int:
	if heavy:
		return HEAVY_INDEX if _attack_idx != HEAVY_INDEX else -1
	return _attack_idx + 1 if _attack_idx < HEAVY_INDEX else -1


func _start_attack(idx: int) -> bool:
	var data := _chain[idx]
	_buffer = &""
	if stamina < data.stamina_cost:
		return false
	_spend_stamina(data.stamina_cost)
	_face_attack_direction()
	_hitbox.deactivate()
	_attack_idx = idx
	_attack_frames = 0.0
	state = State.ATTACK
	return true


func _end_attack() -> void:
	_hitbox.deactivate()
	_attack_idx = -1
	if state == State.ATTACK:
		state = State.FREE


func _face_attack_direction() -> void:
	var dir := _input_direction()
	var best_dist := AIM_ASSIST_RANGE
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead():
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			dir = enemy.global_position - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		_visual_root.rotation.y = atan2(-dir.x, -dir.z)


func _update_weapon_visual(data: AttackData, active_end: float) -> void:
	var p := clampf(_attack_frames / active_end, 0.0, 1.0)
	var arc := deg_to_rad(data.swing_arc) * (-1.0 if data.swing_flip else 1.0)
	_weapon_pivot.rotation.y = lerpf(arc * 0.5, -arc * 0.5, p)


func _on_hit_landed(_body: Node3D, attack: AttackData) -> void:
	HitStop.trigger(attack.hit_stop)
	_add_camera_trauma(attack.shake)


func _add_camera_trauma(amount: float) -> void:
	var cam := get_tree().get_first_node_in_group("camera_controller") as CameraController
	if cam:
		cam.add_trauma(amount)


# --- taking damage ---------------------------------------------------------

func receive_hit(attack: AttackData, from_position: Vector3) -> bool:
	if state == State.DEAD or is_invulnerable():
		return false
	var away := global_position - from_position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else Vector3.BACK
	_hitbox.deactivate()
	_attack_idx = -1
	_buffer = &""
	velocity.x = away.x * attack.knockback
	velocity.z = away.z * attack.knockback
	health.take_damage(attack.damage)
	if state != State.DEAD:
		state = State.HIT
		_hit_time = attack.stagger_time
	_add_camera_trauma(attack.shake * 1.5)
	return true


func _die() -> void:
	state = State.DEAD
	_hitbox.deactivate()
	get_tree().create_timer(2.0, true, false, true).timeout.connect(get_tree().reload_current_scene)
