class_name Enemy
extends CharacterBody3D
## Patrol Soldier: idle -> chase -> attack (telegraph, strike, recovery) -> stagger -> dead.
## Only one enemy holds the attack token at a time; the rest circle at range.

## Emitted when an attack windup begins (audio / telegraph cues).
signal swing_started
## Emitted for every hit that reaches this enemy; dodged is true when it sidestepped instead.
signal was_hit(dodged: bool)
signal defeated
## Emitted for every landed hit with the real damage (after weapon scaling), the impact point, and
## whether it killed. Effects (sparks, damage numbers) listen to this.
signal damaged(amount: float, position: Vector3, was_kill: bool)

enum State { IDLE, CHASE, ATTACK, STAGGER, DEAD }

const FPS: float = 60.0
const WINDUP_COLOR: Color = Color(1.0, 0.15, 0.1)
const DODGE_COLOR: Color = Color(0.3, 0.55, 1.0)
const TOKEN_TIMEOUT: float = 3.0
const DODGE_SPEED: float = 9.0
const DODGE_DURATION: float = 0.25

static var _token_holders: Array[int] = []
static var _alive: int = 0

@export var display_name: String = "Soldier"
@export var hit_points: float = 60.0
@export var swing_path: String = "res://resources/attacks/enemy_swing.tres"
@export var body_color: Color = Color(0.55, 0.25, 0.2)
@export var body_scale: float = 1.0
@export_range(0.0, 1.0) var stagger_resist: float = 0.0
@export var cooldown_min: float = 1.0
@export var cooldown_max: float = 1.6
@export_range(0.0, 1.0) var dodge_chance: float = 0.0
@export var loot_table_path: String = ""

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
var _dodge_flash_time: float = 0.0
var _dodge_time: float = 0.0
var _counted: bool = false
var _strafe_sign: float = 1.0
var _token_age: float = 0.0


func _ready() -> void:
	add_to_group("enemies")
	_counted = true
	_alive += 1
	_swing = load(swing_path) as AttackData
	_material = StandardMaterial3D.new()
	_material.albedo_color = body_color
	_mesh.material_override = _material
	_visual_root.scale = Vector3.ONE * body_scale
	_strafe_sign = 1.0 if get_instance_id() % 2 == 0 else -1.0
	_health.max_health = hit_points
	_health.health = hit_points
	_health.died.connect(_die)
	_health.changed.connect(_on_health_changed)
	_on_health_changed(_health.health, _health.max_health)


func _uncount() -> void:
	if _counted:
		_counted = false
		_alive -= 1


func _exit_tree() -> void:
	_uncount()
	_release_token()


func is_dead() -> bool:
	return state == State.DEAD


## Wave spawns start hostile instead of waiting to notice the player.
func aggro() -> void:
	state = State.CHASE
	_cooldown = randf_range(0.3, 1.0)


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
	var limit := 1 if _alive <= 2 else 2
	if _token_holders.size() < limit:
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
	if _dodge_time > 0.0:
		_dodge_time -= delta  # keep the sidestep velocity set in _sidestep()
		return
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
	swing_started.emit()


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
		_finish_attack(randf_range(cooldown_min, cooldown_max))


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
	_dodge_flash_time -= delta
	if _flash_time > 0.0:
		_material.albedo_color = Color.WHITE
	elif _dodge_flash_time > 0.0:
		_material.albedo_color = DODGE_COLOR
	elif state == State.ATTACK and _attack_frames < _swing.startup_frames:
		_material.albedo_color = WINDUP_COLOR  # telegraph
	else:
		_material.albedo_color = body_color


# --- damage ----------------------------------------------------------------

func receive_hit(attack: AttackData, from_position: Vector3, damage_scale: float = 1.0) -> bool:
	if state == State.DEAD:
		return false
	if state == State.CHASE and dodge_chance > 0.0 and randf() < dodge_chance:
		_sidestep(from_position)
		was_hit.emit(true)
		return false
	var interrupts := _hit_interrupts(attack)
	if interrupts:
		var away := global_position - from_position
		away.y = 0.0
		away = away.normalized() if away.length_squared() > 0.001 else Vector3.BACK
		var knockback := attack.knockback * (1.0 - stagger_resist * 0.5)
		velocity.x = away.x * knockback
		velocity.z = away.z * knockback
	_flash_time = 0.08
	var dealt := attack.damage * damage_scale
	_health.take_damage(dealt)
	damaged.emit(dealt, global_position + Vector3(0.0, 1.1 * body_scale, 0.0), state == State.DEAD)
	was_hit.emit(false)
	if state != State.DEAD:
		_on_damaged()
		if interrupts and state != State.DEAD:
			_hitbox.deactivate()
			_weapon_pivot.visible = false
			_release_token()
			_stagger_time = attack.stagger_time * (1.0 - stagger_resist)
			state = State.STAGGER
	return true


## Override: return false for hits that should not interrupt (super armor).
func _hit_interrupts(_attack: AttackData) -> bool:
	return true


## Override: called after a landed hit that did not kill (phase changes, rage, ...).
func _on_damaged() -> void:
	pass


func _sidestep(from_position: Vector3) -> void:
	var to_attacker := from_position - global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.001:
		to_attacker = Vector3.FORWARD
	var side := Vector3(-to_attacker.z, 0.0, to_attacker.x).normalized() * _strafe_sign
	_move_horizontal(side, DODGE_SPEED)
	_dodge_time = DODGE_DURATION
	_material.albedo_color = DODGE_COLOR
	_dodge_flash_time = 0.2
	_cooldown = minf(_cooldown, 0.3)


func _on_health_changed(current: float, maximum: float) -> void:
	var filled := ceili(current / maximum * 10.0)
	_label.text = "%s [%s%s]" % [display_name, "#".repeat(filled), "-".repeat(10 - filled)]


func _drop_loot() -> void:
	if loot_table_path == "":
		return
	var table := load(loot_table_path) as LootTable
	var item := table.roll() if table else null
	if item:
		# Deferred: the Pickup is an Area3D and must not be added inside a physics callback.
		Pickup.spawn.call_deferred(get_parent(), item, Vector3(global_position.x, 0.0, global_position.z))


func _die() -> void:
	state = State.DEAD
	defeated.emit()
	_release_token()
	_hitbox.deactivate()
	remove_from_group("enemies")
	_uncount()
	_weapon_pivot.visible = false
	_label.visible = false
	_material.albedo_color = Color(0.2, 0.2, 0.2)
	set_deferred("collision_layer", 0)  # nobody collides with the body; it still lands on the floor
	_drop_loot()
	var tween := create_tween()
	tween.tween_property(_visual_root, "rotation_degrees:x", -90.0, 0.35)
	tween.tween_interval(1.5)
	tween.tween_callback(queue_free)
