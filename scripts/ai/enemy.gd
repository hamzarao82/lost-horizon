class_name Enemy
extends CharacterBody3D
## Patrol Soldier: idle -> chase -> attack (telegraph, strike, recovery) -> stagger -> dead.
## Only one enemy holds the attack token at a time; the rest circle at range.

enum State { IDLE, CHASE, ATTACK, STAGGER, DEAD }

const FPS: float = 60.0
const SWING_PATH: String = "res://resources/attacks/enemy_swing.tres"
const BASE_COLOR: Color = Color(0.55, 0.25, 0.2)
const WINDUP_COLOR: Color = Color(1.0, 0.15, 0.1)
const TOKEN_TIMEOUT: float = 3.0

static var _token_holders: Array[int] = []

@export var move_speed: float = 3.2
@export var detection_range: float = 14.0
@export var lose_range: float = 24.0
@export var attack_range: float = 1.9
@export var ring_distance: float = 3.4
@export var turn_speed: float = 8.0

@onready var _health: HealthComponent = $HealthComponent
@onready var _visual_root: Node3D = $VisualRoot
@onready var _mesh: MeshInstance3D = $VisualRoot/MeshInstance3D
@onready var _weapon_pivot: Node3D = $VisualRoot/WeaponPivot
@onready var _hitbox: Hitbox = $VisualRoot/WeaponPivot/Hitbox
@onready var _label: Label3D = $HealthLabel

var state: State = State.IDLE

var _swing: AttackData
var _material: StandardMaterial3D
var _player: Player
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _cooldown: float = 0.5
var _attack_frames: float = 0.0
var _stagger_time: float = 0.0
var _flash_time: float = 0.0
var _strafe_sign: float = 1.0
var _token_age: float = 0.0


func _ready() -> void:
	add_to_group("enemies")
	_swing = load(SWING_PATH) as AttackData
	_material = StandardMaterial3D.new()
	_material.albedo_color = BASE_COLOR
	_mesh.material_override = _material
	_strafe_sign = 1.0 if get_instance_id() % 2 == 0 else -1.0
	_health.died.connect(_die)
	_health.changed.connect(_on_health_changed)
	_on_health_changed(_health.health, _health.max_health)


func _exit_tree() -> void:
	_release_token()


func is_dead() -> bool:
	return state == State.DEAD


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if state == State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		move_and_slide()
		return
	_cooldown -= delta
	match state:
		State.IDLE:
			_state_idle()
		State.CHASE:
			_state_chase(delta)
		State.ATTACK:
			_state_attack(delta)
		State.STAGGER:
			_state_stagger(delta)
	_update_color(delta)
	move_and_slide()


# --- helpers ---------------------------------------------------------------

func _target() -> Player:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null or _player.is_dead():
		return null
	return _player


func _flat_to(target: Node3D) -> Vector3:
	var to := target.global_position - global_position
	to.y = 0.0
	return to


func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return
	var yaw := atan2(-direction.x, -direction.z)
	_visual_root.rotation.y = lerp_angle(_visual_root.rotation.y, yaw, turn_speed * delta)


func _move_horizontal(direction: Vector3, speed: float) -> void:
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed


func _has_token() -> bool:
	return _token_holders.has(get_instance_id())


func _try_take_token() -> bool:
	if _has_token():
		return true
	if _token_holders.is_empty():
		_token_holders.append(get_instance_id())
		_token_age = 0.0
		return true
	return false


func _release_token() -> void:
	_token_holders.erase(get_instance_id())


# --- states ----------------------------------------------------------------

func _state_idle() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	var player := _target()
	if player and _flat_to(player).length() <= detection_range:
		state = State.CHASE


func _state_chase(delta: float) -> void:
	var player := _target()
	if player == null or _flat_to(player).length() > lose_range:
		_release_token()
		state = State.IDLE
		return
	var to := _flat_to(player)
	var dist := to.length()
	var dir := to.normalized()
	_face(dir, delta)

	if _cooldown <= 0.0 and dist <= ring_distance + 1.0 and _try_take_token():
		pass
	if _has_token():
		_token_age += delta
		if _token_age > TOKEN_TIMEOUT:
			# Stuck behind something: give someone else a turn.
			_release_token()
			_cooldown = 1.0
		elif dist <= attack_range:
			_start_attack()
			return
		else:
			_move_horizontal(dir, move_speed)
			return

	# Waiting for a turn: hold a ring around the player.
	if dist > ring_distance + 0.6:
		_move_horizontal(dir, move_speed)
	elif dist < ring_distance - 0.6:
		_move_horizontal(-dir, move_speed * 0.6)
	else:
		var side := Vector3(-dir.z, 0.0, dir.x) * _strafe_sign
		_move_horizontal(side, move_speed * 0.5)


func _start_attack() -> void:
	state = State.ATTACK
	_attack_frames = 0.0
	_move_horizontal(Vector3.ZERO, 0.0)


func _state_attack(delta: float) -> void:
	_attack_frames += delta * FPS
	var active_start := float(_swing.startup_frames)
	var active_end := active_start + _swing.active_frames
	var total := active_end + _swing.recovery_frames

	var player := _target()
	if _attack_frames < active_start * 0.6 and player:
		_face(_flat_to(player).normalized(), delta)  # track during windup, then commit

	if _attack_frames >= active_start and _attack_frames < active_end:
		var facing := -_visual_root.global_transform.basis.z
		_move_horizontal(facing, _swing.lunge_speed)
		if not _hitbox.is_active():
			_hitbox.activate(_swing, self)
	else:
		_move_horizontal(Vector3.ZERO, 0.0)
		if _hitbox.is_active():
			_hitbox.deactivate()

	var p := clampf(_attack_frames / active_end, 0.0, 1.0)
	var arc := deg_to_rad(_swing.swing_arc)
	_weapon_pivot.rotation.y = lerpf(arc * 0.5, -arc * 0.5, p)
	_weapon_pivot.visible = _attack_frames < total - 4.0

	if _attack_frames >= total:
		_finish_attack(randf_range(1.0, 1.6))


func _finish_attack(cooldown: float) -> void:
	_hitbox.deactivate()
	_weapon_pivot.visible = false
	_release_token()
	_cooldown = cooldown
	state = State.CHASE


func _state_stagger(delta: float) -> void:
	_stagger_time -= delta
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
	if _stagger_time <= 0.0:
		_cooldown = maxf(_cooldown, 0.4)
		state = State.CHASE


func _update_color(delta: float) -> void:
	_flash_time -= delta
	if _flash_time > 0.0:
		_material.albedo_color = Color.WHITE
	elif state == State.ATTACK and _attack_frames < _swing.startup_frames:
		_material.albedo_color = WINDUP_COLOR  # telegraph
	else:
		_material.albedo_color = BASE_COLOR


# --- damage ----------------------------------------------------------------

func receive_hit(attack: AttackData, from_position: Vector3) -> bool:
	if state == State.DEAD:
		return false
	var away := global_position - from_position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else Vector3.BACK
	velocity.x = away.x * attack.knockback
	velocity.z = away.z * attack.knockback
	_flash_time = 0.08
	_health.take_damage(attack.damage)
	if state != State.DEAD:
		_hitbox.deactivate()
		_weapon_pivot.visible = false
		_release_token()
		_stagger_time = attack.stagger_time
		state = State.STAGGER
	return true


func _on_health_changed(current: float, maximum: float) -> void:
	var filled := ceili(current / maximum * 10.0)
	_label.text = "[%s%s]" % ["#".repeat(filled), "-".repeat(10 - filled)]


func _die() -> void:
	state = State.DEAD
	_release_token()
	_hitbox.deactivate()
	remove_from_group("enemies")
	_weapon_pivot.visible = false
	_label.visible = false
	_material.albedo_color = Color(0.2, 0.2, 0.2)
	set_deferred("collision_layer", 0)  # nobody collides with the body; it still lands on the floor
	var tween := create_tween()
	tween.tween_property(_visual_root, "rotation_degrees:x", -90.0, 0.35)
	tween.tween_interval(1.5)
	tween.tween_callback(queue_free)
