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

# PATROL..RETURN (Milestone 3) are appended so the existing values never change; they are only entered
# by enemies that were given a PatrolRoute. Wave enemies and the Warden never are.
enum State { IDLE, CHASE, ATTACK, STAGGER, DEAD, PATROL, SUSPICIOUS, SEARCH, RETURN, RANGED_ATTACK }

const FPS: float = 60.0
const WINDUP_COLOR: Color = Color(1.0, 0.15, 0.1)
const DODGE_COLOR: Color = Color(0.3, 0.55, 1.0)
const TOKEN_TIMEOUT: float = 3.0
const DODGE_SPEED: float = 9.0
const DODGE_DURATION: float = 0.25

static var _token_holders: Array[int] = []
static var _alive: int = 0
## Enemies currently on patrol duty (any patrol state or chasing after leaving their route).
static var active_patrollers: int = 0

const PATROL_SPEED_FACTOR: float = 0.55
const SIGHT_RANGE: float = 13.0
const SIGHT_FOV_DEG: float = 130.0
const NOTICE_RANGE: float = 6.0       # a visible player this close is noticed at once
const SUSPICION_RATE: float = 1.6     # per second while a farther player stays visible
const HEAR_RADIUS: float = 12.0       # combat noise reaches patrols this far
## Opt-in (Blackwood encounters): when this enemy notices the player, enemies within ALLY_ALERT_RADIUS
## that have not noticed yet join the chase. One hop only, so the cost stays a single scan of the group.
@export var coordinate_alarm: bool = false
const ALLY_ALERT_RADIUS: float = 10.0
const SUSPICIOUS_TIMEOUT: float = 8.0
const RETURN_TIMEOUT: float = 14.0
const STUCK_SECONDS: float = 2.0
const ARRIVE_DISTANCE: float = 0.9

## Set by a PatrolGroup before the enemy enters the tree. null = ordinary enemy.
var patrol_route: PatrolRoute
var patrol_index: int = 0
@export var search_seconds: float = 5.0

var _patrol_step: int = 1
var _arrived: bool = false
var _wait_left: float = 0.0
var _suspicion: float = 0.0
var _last_known: Vector3 = Vector3.ZERO
var _state_time: float = 0.0
var _search_left: float = 0.0
var _stuck_time: float = 0.0
var _stuck_clock: float = 0.0
var _stuck_ref: Vector3 = Vector3.ZERO
var _patrol_counted: bool = false

@export var display_name: String = "Soldier"
@export var hit_points: float = 60.0
## Outgoing damage multiplier; EnemyScaling raises it with the player level. 1.0 = authored numbers.
var damage_mult: float = 1.0

@export var swing_path: String = "res://resources/attacks/enemy_swing.tres"
@export var body_color: Color = Color(0.55, 0.25, 0.2)
@export var body_scale: float = 1.0
@export_range(0.0, 1.0) var stagger_resist: float = 0.0
@export var cooldown_min: float = 1.0
@export var cooldown_max: float = 1.6
@export_range(0.0, 1.0) var dodge_chance: float = 0.0
@export var loot_table_path: String = ""
## Optional (Milestone 8): gives the enemy ranged behaviour (see scripts/ai/ranged). null = unchanged.
@export var ranged: RangedConfig

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
var _label_filled: int = -1
var _ranged_brain: RangedBrain


func _ready() -> void:
	add_to_group("enemies")
	_counted = true
	var progression := get_node_or_null("/root/Progression")
	if progression != null:
		EnemyScaling.apply(self, int(progression.level()))
	_alive += 1
	_swing = load(swing_path) as AttackData
	_material = StandardMaterial3D.new()
	_material.albedo_color = body_color
	_mesh.material_override = _material
	_visual_root.scale = Vector3.ONE * body_scale
	_strafe_sign = 1.0 if get_instance_id() % 2 == 0 else -1.0
	if ranged != null:
		_ranged_brain = RangedBrain.new(self, ranged)
	_health.max_health = hit_points
	_health.health = hit_points
	_health.died.connect(_die)
	_health.changed.connect(_on_health_changed)
	_on_health_changed(_health.health, _health.max_health)
	if patrol_route != null:
		_begin_patrol()


func _uncount() -> void:
	if _counted:
		_counted = false
		_alive -= 1


func _exit_tree() -> void:
	_uncount()
	_patrol_uncount()
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
			if _ranged_brain != null:
				_ranged_brain.chase(delta)
			else:
				_state_chase(delta)
		State.RANGED_ATTACK:
			if _ranged_brain != null:
				_ranged_brain.attack_tick(delta)
			else:
				state = State.CHASE
		State.ATTACK:
			_state_attack(delta)
		State.STAGGER:
			_state_stagger(delta)
		State.PATROL:
			_state_patrol(delta)
		State.SUSPICIOUS:
			_state_suspicious(delta)
		State.SEARCH:
			_state_search(delta)
		State.RETURN:
			_state_return(delta)
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
		_raise_alarm()


func _state_chase(delta: float) -> void:
	if _dodge_time > 0.0:
		_dodge_time -= delta  # keep the sidestep velocity set in _sidestep()
		return
	var player := _target()
	if player == null or _flat_to(player).length() > lose_range:
		_release_token()
		if _has_route():
			# A patrolling enemy that loses the player investigates, then goes back to its route.
			if player != null:
				_last_known = player.global_position
				_enter_suspicious()
			else:
				_begin_return()
		else:
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
			_hitbox.activate(_swing, self, damage_mult)
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
	elif state == State.RANGED_ATTACK and _ranged_brain != null and _ranged_brain.is_telegraphing():
		_material.albedo_color = WINDUP_COLOR  # ranged telegraph
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
	_make_noise(global_position)  # the fight is where the victim stands
	if state != State.DEAD:
		_on_damaged()
		if interrupts and state != State.DEAD:
			_hitbox.deactivate()
			_weapon_pivot.visible = false
			_release_token()
			_stagger_time = attack.stagger_time * (1.0 - stagger_resist)
			state = State.STAGGER
			if _ranged_brain != null:
				_ranged_brain.cancel()  # an interrupted telegraph or burst never fires
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
	var filled := clampi(ceili(current / maximum * 10.0), 0, 10)
	if filled == _label_filled:
		return  # Label3D re-shapes its text on every assignment; only rebuild when the bar moved
	_label_filled = filled
	_label.text = "%s [%s%s]" % [display_name, "#".repeat(filled), "-".repeat(10 - filled)]


## Materials and credits dropped on top of the gear table, by the tier the enemy's own table implies.
## Gear drop rates are unchanged; see docs/ITEMS_AND_ECONOMY.md for the resulting rates.
const BONUS_TABLES: Dictionary = {
	"soldier_loot": "res://resources/loot/enemy_regular.tres",
	"hunter_loot": "res://resources/loot/enemy_elite.tres",
	"heavy_loot": "res://resources/loot/enemy_elite.tres",
}


func _drop_bonus_loot() -> void:
	var key := loot_table_path.get_file().get_basename()
	if not BONUS_TABLES.has(key):
		return
	var table := load(BONUS_TABLES[key]) as LootTable
	var item := table.roll() if table else null
	if item:
		Pickup.spawn.call_deferred(get_parent(), item, Vector3(global_position.x + 0.8, 0.0, global_position.z))


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
	_patrol_uncount()
	_release_token()
	_hitbox.deactivate()
	if _ranged_brain != null:
		_ranged_brain.cancel()
	remove_from_group("enemies")
	_uncount()
	_weapon_pivot.visible = false
	_label.visible = false
	_material.albedo_color = Color(0.2, 0.2, 0.2)
	set_deferred("collision_layer", 0)  # nobody collides with the body; it still lands on the floor
	_drop_loot()
	_drop_bonus_loot()
	var tween := create_tween()
	tween.tween_property(_visual_root, "rotation_degrees:x", -90.0, 0.35)
	tween.tween_interval(1.5)
	tween.tween_callback(queue_free)


# --- patrol (Milestone 3) --------------------------------------------------
# Only used when a PatrolRoute was assigned. PATROL -> SUSPICIOUS -> SEARCH -> RETURN -> PATROL,
# and any of them -> CHASE (alert) when the player is noticed or the enemy is hit.

func _has_route() -> bool:
	return patrol_route != null and is_instance_valid(patrol_route)


## The route was freed (its group left the scene): fall back to an ordinary idle enemy.
func _drop_route() -> void:
	patrol_route = null
	_patrol_uncount()
	state = State.IDLE


func _begin_patrol() -> void:
	state = State.PATROL
	_arrived = false
	_suspicion = 0.0
	_stuck_time = 0.0
	if not _patrol_counted:
		_patrol_counted = true
		active_patrollers += 1


func _patrol_uncount() -> void:
	if _patrol_counted:
		_patrol_counted = false
		active_patrollers -= 1


func _sees_player() -> bool:
	var player := _target()
	if player == null:
		return false
	var facing := -_visual_root.global_transform.basis.z
	return DetectionComponent.can_see(self, player, facing, SIGHT_RANGE, SIGHT_FOV_DEG)


## Builds suspicion while the player is visible. Returns true once the player is noticed.
func _update_suspicion(delta: float) -> bool:
	var player := _target()
	if player != null and _sees_player():
		_last_known = player.global_position
		if _flat_to(player).length() <= NOTICE_RANGE:
			_suspicion = 1.0
		else:
			_suspicion += SUSPICION_RATE * delta
		return _suspicion >= 1.0
	_suspicion = maxf(_suspicion - 0.5 * delta, 0.0)
	return false


func _alert() -> void:
	_suspicion = 1.0
	_cooldown = minf(_cooldown, 0.4)
	state = State.CHASE
	_raise_alarm()


## Called by other enemies' hits: investigate where the fight was.
func hear(source: Vector3) -> void:
	if not _has_route():
		return
	if state == State.PATROL or state == State.RETURN or state == State.SEARCH:
		_last_known = source
		_enter_suspicious()


func _make_noise(source: Vector3) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var other := node as Enemy
		if other != null and other != self and other._has_route() \
				and other.global_position.distance_to(source) <= HEAR_RADIUS:
			other.hear(source)


func _enter_suspicious() -> void:
	state = State.SUSPICIOUS
	_state_time = 0.0
	_stuck_time = 0.0
	_stuck_clock = 0.0
	_stuck_ref = global_position


func _begin_return() -> void:
	state = State.RETURN
	_state_time = 0.0
	_stuck_time = 0.0
	_stuck_clock = 0.0
	_stuck_ref = global_position
	patrol_index = patrol_route.nearest_index(global_position)


## Walks toward a world point at `speed` and reports "no progress" through _stuck_time.
func _walk_to(target: Vector3, speed: float, delta: float) -> float:
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > 0.01:
		var dir := to / dist
		_face(dir, delta)
		_move_horizontal(dir, speed)
	_check_stuck(delta)
	return dist


func _check_stuck(delta: float) -> void:
	_stuck_clock += delta
	if _stuck_clock < 0.5:
		return
	var moved := Vector2(global_position.x - _stuck_ref.x, global_position.z - _stuck_ref.z).length()
	_stuck_time = _stuck_time + _stuck_clock if moved < 0.12 else 0.0
	_stuck_clock = 0.0
	_stuck_ref = global_position


func _state_patrol(delta: float) -> void:
	if not _has_route():
		_drop_route()
		return
	var seen := _sees_player()
	if _update_suspicion(delta):
		_alert()
		return
	if _suspicion >= 0.5 and not seen:
		_enter_suspicious()  # saw something, lost it: go and look
		return
	var target := patrol_route.global_point(patrol_index)
	var flat := target - global_position
	flat.y = 0.0
	if flat.length() <= ARRIVE_DISTANCE or _arrived:
		velocity.x = 0.0
		velocity.z = 0.0
		if not _arrived:
			_arrived = true
			_wait_left = patrol_route.wait_seconds
		_wait_left -= delta
		if _wait_left <= 0.0:
			_arrived = false
			_stuck_time = 0.0
			var next := patrol_route.advance(patrol_index, _patrol_step)
			patrol_index = next[0]
			_patrol_step = next[1]
		return
	_walk_to(target, move_speed * PATROL_SPEED_FACTOR, delta)
	if _stuck_time >= STUCK_SECONDS:
		# Blocked on the way: skip this waypoint instead of pushing against the obstacle forever.
		_stuck_time = 0.0
		var skip := patrol_route.advance(patrol_index, _patrol_step)
		patrol_index = skip[0]
		_patrol_step = skip[1]


func _state_suspicious(delta: float) -> void:
	if not _has_route():
		_drop_route()
		return
	_state_time += delta
	if _update_suspicion(delta):
		_alert()
		return
	var dist := _walk_to(_last_known, move_speed * PATROL_SPEED_FACTOR * 1.3, delta)
	if dist <= ARRIVE_DISTANCE + 0.4 or _state_time >= SUSPICIOUS_TIMEOUT or _stuck_time >= STUCK_SECONDS:
		state = State.SEARCH
		_search_left = search_seconds
		velocity.x = 0.0
		velocity.z = 0.0


func _state_search(delta: float) -> void:
	if not _has_route():
		_drop_route()
		return
	velocity.x = 0.0
	velocity.z = 0.0
	if _update_suspicion(delta):
		_alert()
		return
	_visual_root.rotation.y += delta * 1.4 * (1.0 if int(_search_left * 0.5) % 2 == 0 else -1.0)  # look around
	_search_left -= delta
	if _search_left <= 0.0:
		_begin_return()


func _state_return(delta: float) -> void:
	if not _has_route():
		_drop_route()
		return
	_state_time += delta
	if _update_suspicion(delta):
		_alert()
		return
	var target := patrol_route.global_point(patrol_index)
	var dist := _walk_to(target, move_speed * PATROL_SPEED_FACTOR, delta)
	if dist <= ARRIVE_DISTANCE or _state_time >= RETURN_TIMEOUT or _stuck_time >= STUCK_SECONDS:
		_begin_patrol()
		_arrived = true  # at the marker: wait there as usual, then move on
		_wait_left = 0.2


func _raise_alarm() -> void:
	if not coordinate_alarm:
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var other := node as Enemy
		if other == null or other == self or other.is_dead():
			continue
		if other.global_position.distance_to(global_position) > ALLY_ALERT_RADIUS:
			continue
		if other.state == State.IDLE or other.state == State.PATROL or other.state == State.SUSPICIOUS \
				or other.state == State.SEARCH or other.state == State.RETURN:
			other.receive_ally_alert()


## An ally noticed the player: join the chase (does not alarm further allies).
func receive_ally_alert() -> void:
	_suspicion = 1.0
	_cooldown = minf(_cooldown, 0.6)
	state = State.CHASE
