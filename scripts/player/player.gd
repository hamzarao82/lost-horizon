class_name Player
extends CharacterBody3D
## Camera-relative movement, dodge with i-frames, light/heavy combo attacks.

signal stamina_changed(current: float, maximum: float)

enum State { FREE, DODGE, ATTACK, HIT, DEAD }

const FPS: float = 60.0
const CHAIN_PATHS: Array[String] = [
	"res://resources/attacks/light_1.tres",
	"res://resources/attacks/light_2.tres",
	"res://resources/attacks/light_3.tres",
	"res://resources/attacks/heavy_1.tres",
	"res://resources/attacks/sprint_attack.tres",
	"res://resources/attacks/air_attack.tres",
	"res://resources/attacks/spin_special.tres",
]
## Indices into CHAIN_PATHS. Light combo is 0 -> 1 -> 2; heavy finishes from any of them.
const IDX_LIGHT_1: int = 0
const IDX_LIGHT_2: int = 1
const IDX_LIGHT_3: int = 2
const HEAVY_INDEX: int = 3
const IDX_SPRINT: int = 4
const IDX_AIR: int = 5
const IDX_SPIN: int = 6
const AIM_ASSIST_RANGE: float = 4.0
const HEAL_BUFFER: float = 0.8  # long enough to outlast a heavy attack
const QUEUE_SIZE: int = 3
const AIR_DIVE_SPEED: float = 14.0
const LAND_AOE_SCALE: float = 0.8
## Every action the player reacts to as a discrete press. The order matters only for touch/polled
## presses that land on the same tick: jump goes before the attacks so jump + attack is an air attack.
const WATCHED_ACTIONS: Array[StringName] = [
	&"dodge", &"jump", &"special", &"attack_heavy", &"attack_light", &"use_item", &"lock_on"]

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
@export var special_cooldown: float = 6.0

var inventory: Inventory
## Seconds until the spin special is ready again (0 = ready). HUDs read this and `special_cooldown`.
var special_cooldown_left: float = 0.0

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
## FIFO of buffered presses: [{"action": StringName, "time": float seconds left}], at most QUEUE_SIZE.
var _queue: Array[Dictionary] = []
## Actions whose press was already queued from a real InputEvent this tick (so polling skips them).
var _event_seen: Dictionary = {}
## Actions that were held down on the previous tick (for edge detection of polled/touch presses).
var _was_down: Dictionary = {}
var _last_press_tick: Dictionary = {}
var _heal_time: float = 0.0
var _invuln_time: float = 0.0
var _swing_hits: Array[Node3D] = []
var _attack_connected: bool = false
var _landed: bool = false
var _pulsed: bool = false
var _dodge_time: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _attack_idx: int = -1
var _attack_frames: float = 0.0
var _hit_time: float = 0.0
var _targeting: Targeting = Targeting.new()
var _lock_marker: MeshInstance3D


func _ready() -> void:
	add_to_group("player")
	HitStop.reset()
	inventory = Inventory.new()
	add_child(inventory)
	for path in CHAIN_PATHS:
		_chain.append(load(path) as AttackData)
	stamina = max_stamina
	health.died.connect(_die)
	_hitbox.hit.connect(_on_hit_landed)


func _exit_tree() -> void:
	# The marker is parented to the target while locked, and is orphaned otherwise.
	if is_instance_valid(_lock_marker) and _lock_marker.get_parent() == null:
		_lock_marker.free()


func is_invulnerable() -> bool:
	return _invuln_time > 0.0 or (state == State.DODGE and _dodge_time < dodge_iframes)


## Extra i-frames from outside the dodge (teleport, etc.). Never shortens an existing window.
func grant_invulnerability(seconds: float) -> void:
	_invuln_time = maxf(_invuln_time, seconds)


func is_dead() -> bool:
	return state == State.DEAD


func is_sprinting() -> bool:
	return state == State.FREE and Input.is_action_pressed("sprint") \
			and Vector2(velocity.x, velocity.z).length() > walk_speed + 0.5


func lock_target() -> Node3D:
	return _targeting.target


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_lock(delta)
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

# Presses reach the player two ways, and both feed the same handler:
#  - real InputEvents (keyboard, mouse, gamepad) arrive in _input, so a press that starts and ends
#    between two physics ticks (low FPS on web/Android) is never lost;
#  - touch buttons call Input.action_press(), which creates no InputEvent, so they are picked up by
#    polling is_action_just_pressed() each physics tick (TouchControls keeps the action pressed
#    for one tick on release).
# _event_seen stops a press that arrived as an event from being queued a second time by the poll.
# Every watched action is handled independently: there is no if/elif chain to drop a simultaneous press.

func _input(event: InputEvent) -> void:
	if state == State.DEAD or event is InputEventMouseMotion:
		return
	for action in WATCHED_ACTIONS:
		if event.is_action_pressed(action):  # echoes are ignored (allow_echo = false)
			_event_seen[action] = true
			_last_press_tick[action] = Engine.get_physics_frames()
			_register_press(action)


func _poll_input(delta: float) -> void:
	_invuln_time = maxf(_invuln_time - delta, 0.0)
	special_cooldown_left = maxf(special_cooldown_left - delta, 0.0)
	_tick_queue(delta)
	# A polled press is "fresh" when the action went from up to down, or Input says it was just
	# pressed (a release + re-press with no tick in between). is_action_just_pressed() alone can
	# report one press on two consecutive ticks, so a repeat within one tick of the last
	# registration of that action is ignored (no human double-taps faster than that).
	var tick := Engine.get_physics_frames()
	for action in WATCHED_ACTIONS:
		var down := Input.is_action_pressed(action)
		var fresh := down and (not _was_down.has(action) or Input.is_action_just_pressed(action))
		if fresh and tick - int(_last_press_tick.get(action, -10)) > 1:
			if not _event_seen.has(action) and state != State.DEAD:
				_register_press(action)
			_last_press_tick[action] = tick
		if down:
			_was_down[action] = true
		else:
			_was_down.erase(action)
	_event_seen.clear()
	_heal_time -= delta
	if _heal_time > 0.0 and (state == State.FREE or state == State.HIT) and inventory.use_potion(health):
		_heal_time = 0.0
		_sfx(&"heal")


## The click that (re)captures the mouse must not also swing the weapon.
func _attacks_allowed() -> bool:
	return not require_mouse_capture or TouchControls.touch_active \
			or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _register_press(action: StringName) -> void:
	match action:
		&"lock_on":
			if _attacks_allowed():
				toggle_lock()
		&"use_item":
			_heal_time = HEAL_BUFFER
		&"dodge", &"jump":
			_enqueue(action)
		_:
			if _attacks_allowed():
				_enqueue(action)


func _enqueue(action: StringName) -> void:
	if _queue.size() >= QUEUE_SIZE:
		_queue.pop_front()  # drop the oldest; the newest press is what the player means now
	_queue.append({"action": action, "time": input_buffer})


func _tick_queue(delta: float) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		_queue[i]["time"] -= delta
		if _queue[i]["time"] <= 0.0:
			_queue.remove_at(i)


## Number of buffered presses of `action` (for tests and HUD debugging).
func queued_count(action: StringName) -> int:
	var count := 0
	for entry in _queue:
		if entry["action"] == action:
			count += 1
	return count


func _drop_queued(entry: Dictionary) -> void:
	_queue.erase(entry)


## Runs the buffered presses in FIFO order. `handler` is called with (action) and returns:
## CONSUMED (remove, keep going), CHANGED_STATE (remove, stop), KEEP (leave it for later) or
## DROP (remove it, it can never succeed, e.g. no stamina or end of a chain).
enum Result { KEEP, DROP, CONSUMED, CHANGED_STATE }


func _process_queue(handler: Callable) -> void:
	for entry in _queue.duplicate():
		if not _queue.has(entry):
			continue
		var result: int = handler.call(entry["action"])
		match result:
			Result.DROP, Result.CONSUMED:
				_drop_queued(entry)
			Result.CHANGED_STATE:
				_drop_queued(entry)
				return


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
	var lock_dir := _lock_direction()
	if lock_dir.length_squared() > 0.001 and not Input.is_action_pressed("sprint"):
		_turn_toward(lock_dir, delta)  # strafe: keep facing the locked enemy
	elif direction.length_squared() > 0.001:
		_turn_toward(direction, delta)
	_process_queue(_handle_free_action)


func _handle_free_action(action: StringName) -> int:
	match action:
		&"dodge":
			return Result.CHANGED_STATE if _try_dodge() else Result.DROP
		&"jump":
			return Result.CONSUMED if _try_jump() else Result.KEEP
		&"attack_light":
			return Result.CHANGED_STATE if _start_attack(_context_attack(false)) else Result.DROP
		&"attack_heavy":
			return Result.CHANGED_STATE if _start_attack(_context_attack(true)) else Result.DROP
		&"special":
			return Result.CHANGED_STATE if _try_special() else Result.DROP
	return Result.DROP


func _try_jump() -> bool:
	if not is_on_floor():
		return false
	velocity.y = jump_velocity
	return true


## Which attack an attack press means right now: air > heavy > sprint > first light.
func _context_attack(heavy: bool) -> int:
	if _is_airborne():
		return IDX_AIR
	if heavy:
		return HEAVY_INDEX
	if is_sprinting():
		return IDX_SPRINT
	return IDX_LIGHT_1


func _is_airborne() -> bool:
	if velocity.y > 1.0:
		return true  # just jumped (jump + attack in the same tick is an air attack)
	if is_on_floor():
		return false
	var query := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * 0.6, 1)
	return _physics_space().intersect_ray(query).is_empty()


func _state_dodge(delta: float) -> void:
	_dodge_time += delta
	var speed := dodge_speed * lerpf(1.0, 0.35, clampf(_dodge_time / dodge_duration, 0.0, 1.0))
	velocity.x = _dodge_dir.x * speed
	velocity.z = _dodge_dir.z * speed
	if _dodge_time >= dodge_duration:
		state = State.FREE


func _state_attack(delta: float) -> void:
	var data := _chain[_attack_idx]
	_attack_frames += delta * FPS * _attack_speed()
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
	var pulse_only := data.aoe_radius > 0.0 and not data.aoe_on_land  # spin: ring, no weapon hitbox
	if pulse_only:
		if in_active and not _pulsed:
			_pulsed = true
			_aoe_strike(data, 1.0)
	elif in_active and not _hitbox.is_active():
		_hitbox.activate(data, self, inventory.damage_multiplier())
	elif not in_active and _hitbox.is_active():
		_hitbox.deactivate()

	if _attack_idx == IDX_AIR and _attack_frames >= active_start and not _landed:
		if is_on_floor():
			_landed = true
			_aoe_strike(data, LAND_AOE_SCALE)
		else:
			velocity.y = -AIR_DIVE_SPEED  # dive onto the target

	_update_weapon_visual(data, active_end)

	_process_queue(_handle_attack_action)
	if state == State.ATTACK and _attack_frames >= total and (_attack_idx != IDX_AIR or _landed):
		_end_attack()


## Buffered presses during an attack. Dodge may cancel from the end of the active window once the
## swing has connected, or any time in recovery; chains, jumps and the special wait for recovery.
func _handle_attack_action(action: StringName) -> int:
	var data := _chain[_attack_idx]
	var active_start := float(data.startup_frames)
	var active_end := active_start + data.active_frames
	var can_chain := _attack_frames >= active_end
	var can_cancel := can_chain or (_attack_connected and _attack_frames >= active_start)
	match action:
		&"dodge":
			if not can_cancel:
				return Result.KEEP
			return Result.CHANGED_STATE if _try_dodge() else Result.DROP
		&"jump":
			if not can_chain or not is_on_floor():
				return Result.KEEP
			_end_attack()
			velocity.y = jump_velocity
			return Result.CHANGED_STATE
		&"attack_light", &"attack_heavy":
			if not can_chain:
				return Result.KEEP
			var next := _next_attack(action == &"attack_heavy")
			if next < 0:
				return Result.DROP  # end of chain: don't carry the press into a fresh attack
			return Result.CHANGED_STATE if _start_attack(next) else Result.DROP
		&"special":
			if not can_chain:
				return Result.KEEP
			return Result.CHANGED_STATE if _try_special() else Result.DROP
	return Result.DROP


func _try_special() -> bool:
	if special_cooldown_left > 0.0:
		return false
	if not _start_attack(IDX_SPIN):
		return false
	special_cooldown_left = special_cooldown
	return true


## Ring attack around the player (spin pulse, air-attack landing). Skips enemies the swing already hit.
func _aoe_strike(data: AttackData, scale: float) -> int:
	var hits := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead() or _swing_hits.has(enemy):
			continue
		var offset := enemy.global_position - global_position
		if Targeting.flat(offset).length() > data.aoe_radius or absf(offset.y) > 2.5:
			continue
		_swing_hits.append(enemy)
		if enemy.receive_hit(data, global_position, inventory.damage_multiplier() * scale):
			hits += 1
			_on_hit_landed(enemy, data)
	return hits


func _attack_speed() -> float:
	return maxf(inventory.attack_speed(), 0.25) if inventory else 1.0


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
	_sfx(&"dodge")
	return true


# --- attacks ---------------------------------------------------------------

## Chain rules: L -> L -> L, heavy finishes any of them; sprint/air attacks flow into the light combo.
func _next_attack(heavy: bool) -> int:
	if heavy:
		return HEAVY_INDEX if _attack_idx != HEAVY_INDEX and _attack_idx != IDX_SPIN else -1
	match _attack_idx:
		IDX_LIGHT_1, IDX_LIGHT_2:
			return _attack_idx + 1
		IDX_SPRINT, IDX_AIR:
			return IDX_LIGHT_1
	return -1


func _start_attack(idx: int) -> bool:
	var data := _chain[idx]
	if stamina < data.stamina_cost:
		return false
	_spend_stamina(data.stamina_cost)
	_face_attack_direction()
	_hitbox.deactivate()
	_attack_idx = idx
	_attack_frames = 0.0
	_swing_hits.clear()
	_attack_connected = false
	_landed = false
	_pulsed = false
	state = State.ATTACK
	# Respond on the very first frame: swing pose and lunge start now, not next tick.
	_update_weapon_visual(data, float(data.startup_frames + data.active_frames))
	var facing := -_visual_root.global_transform.basis.z
	velocity.x = facing.x * data.lunge_speed
	velocity.z = facing.z * data.lunge_speed
	_sfx(&"swing_heavy" if idx == HEAVY_INDEX or idx == IDX_SPIN else &"swing_light")
	return true


func _end_attack() -> void:
	_hitbox.deactivate()
	_attack_idx = -1
	if state == State.ATTACK:
		state = State.FREE


func _face_attack_direction() -> void:
	var locked := _lock_direction()
	if locked.length_squared() > 0.001:
		_visual_root.rotation.y = atan2(-locked.x, -locked.z)
		return
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


# --- lock-on ---------------------------------------------------------------

func _camera_forward() -> Vector3:
	return Basis(Vector3.UP, _camera_pivot.global_rotation.y) * Vector3.FORWARD


func _physics_space() -> PhysicsDirectSpaceState3D:
	return get_world_3d().direct_space_state


## Flat direction to the locked target, or ZERO when not locked.
func _lock_direction() -> Vector3:
	var locked := _targeting.target
	if locked == null or not is_instance_valid(locked):
		return Vector3.ZERO
	return Targeting.flat(locked.global_position - global_position).normalized()


func toggle_lock() -> void:
	if _targeting.target != null:
		# On touch there is no separate cycle control: tapping Lock again hops to the next enemy.
		if TouchControls.touch_active and cycle_lock(1):
			return
		_clear_lock()
		return
	_targeting.acquire(global_position, _camera_forward(),
			get_tree().get_nodes_in_group("enemies"), _physics_space())
	_apply_lock()


## Switch to the next target right (+1) or left (-1). Returns true if the target changed.
func cycle_lock(direction: int) -> bool:
	if _targeting.target == null:
		return false
	var previous := _targeting.target
	_targeting.cycle(direction, global_position, _camera_forward(),
			get_tree().get_nodes_in_group("enemies"), _physics_space())
	_apply_lock()
	return _targeting.target != previous


func _clear_lock() -> void:
	_targeting.clear()
	_apply_lock()


func _apply_lock() -> void:
	var cam := get_tree().get_first_node_in_group("camera_controller") as CameraController
	var locked := _targeting.target
	if cam:
		if locked:
			cam.set_lock_target(locked)
		else:
			cam.clear_lock_target()
	_place_marker(locked)


func _update_lock(delta: float) -> void:
	if _targeting.target == null:
		return
	if state == State.DEAD or not _targeting.update(delta, global_position, _physics_space()):
		_clear_lock()
		return
	if is_instance_valid(_lock_marker):
		_lock_marker.rotation.y += delta * 3.0


func _place_marker(locked: Node3D) -> void:
	if not is_instance_valid(_lock_marker):
		_lock_marker = MeshInstance3D.new()
		var cone := CylinderMesh.new()  # wide top, point down: an arrow over the target
		cone.top_radius = 0.22
		cone.bottom_radius = 0.0
		cone.height = 0.4
		cone.radial_segments = 8
		cone.rings = 1
		_lock_marker.mesh = cone
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.85, 0.2)
		_lock_marker.material_override = material
		_lock_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var parent := _lock_marker.get_parent()
	if parent:
		parent.remove_child(_lock_marker)
	if locked == null:
		return
	var visual := locked.get_node_or_null("VisualRoot") as Node3D
	var height := (visual.scale.y if visual else 1.0) * 2.0 + 0.9
	locked.add_child(_lock_marker)
	_lock_marker.position = Vector3(0.0, height, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if state == State.DEAD:
		return
	if event.is_action_pressed("target_next"):
		cycle_lock(1)
	elif event.is_action_pressed("target_prev"):
		cycle_lock(-1)


func _update_weapon_visual(data: AttackData, active_end: float) -> void:
	var p := clampf(_attack_frames / active_end, 0.0, 1.0)
	var arc := deg_to_rad(data.swing_arc) * (-1.0 if data.swing_flip else 1.0)
	_weapon_pivot.rotation.y = lerpf(arc * 0.5, -arc * 0.5, p)


func _on_hit_landed(body: Node3D, attack: AttackData) -> void:
	_attack_connected = true
	if not _swing_hits.has(body):
		_swing_hits.append(body)  # lets a landing ring skip enemies the slash already hit
	_sfx(&"hit_heavy" if attack.id == &"heavy_1" or attack.id == &"spin_special" else &"hit_light")
	HitStop.trigger(attack.hit_stop)
	_add_camera_trauma(attack.shake)


func _add_camera_trauma(amount: float) -> void:
	var cam := get_tree().get_first_node_in_group("camera_controller") as CameraController
	if cam:
		cam.add_trauma(amount)


# --- taking damage ---------------------------------------------------------

func receive_hit(attack: AttackData, from_position: Vector3, damage_scale: float = 1.0) -> bool:
	if state == State.DEAD or is_invulnerable():
		return false
	var away := global_position - from_position
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.001 else Vector3.BACK
	_hitbox.deactivate()
	_attack_idx = -1
	_queue.clear()
	velocity.x = away.x * attack.knockback
	velocity.z = away.z * attack.knockback
	health.take_damage(attack.damage * damage_scale)  # armor is a bar in HealthComponent now
	_sfx(&"hurt")
	if state != State.DEAD:
		state = State.HIT
		_hit_time = attack.stagger_time
	_add_camera_trauma(attack.shake * 1.5)
	return true


## Looked up by path so the player (and the tests) work without the AudioManager autoload.
func _sfx(sfx_name: StringName, volume_db: float = 0.0) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play(sfx_name, volume_db)


func _die() -> void:
	state = State.DEAD
	_clear_lock()
	_hitbox.deactivate()
	get_tree().create_timer(2.0, true, false, true).timeout.connect(get_tree().reload_current_scene)
