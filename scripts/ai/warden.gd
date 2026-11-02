class_name Warden
extends Enemy
## Boss: heavy overhead slams with a periodic ground shockwave (jump or dodge it), and a charge
## that ends in a long wall stun (Milestone 4). At 40% health he roars (invulnerable 2.5 s), enrages,
## chains a flurry after each slam, adds fire lines after the shockwave and a leap slam, strafes
## between attacks, and calls two soldiers once. Only heavy hits interrupt him.
##
## Attack choice (weights, documented in docs/BOSS_DESIGN_WARDEN.md): phase 1 slam 3 : charge 1;
## phase 2 slam 4 : leap 2 : charge 1. A special never repeats back to back, and after three slams in a
## row a special is forced, so the order is learnable but not a metronome.

const SLAM_PATH: String = "res://resources/attacks/warden_slam.tres"
const FLURRY_PATH: String = "res://resources/attacks/warden_flurry.tres"
const SHOCK_PATH: String = "res://resources/attacks/warden_shockwave.tres"
const CHARGE_PATH: String = "res://resources/attacks/warden_charge.tres"
const LEAP_PATH: String = "res://resources/attacks/warden_leap.tres"
const FIRE_PATH: String = "res://resources/attacks/warden_fire.tres"
const SOLDIER_PATH: String = "res://scenes/enemies/PatrolSoldier.tscn"

const EXTRA_DROP_PATH: String = "res://resources/items/health_potion.tres"
## Phase 2 starts at 40% health (Milestone 4 decision; the Milestone 3 baseline was 50%).
const PHASE2_THRESHOLD: float = 0.4
const ROAR_TIME: float = 2.5

const CHARGE_SPEED: float = 17.0
const CHARGE_MAX: float = 14.0
const CHARGE_MIN_DIST: float = 5.0
const CHARGE_HIT_RADIUS: float = 1.7
const CHARGE_WALL_STUN: float = 1.5
const CHARGE_SHORT_STUN: float = 0.8
const LEAP_AIR_TIME: float = 0.5
const LEAP_RADIUS: float = 3.5
const LEAP_HEIGHT: float = 3.0
const LEAP_MIN_DIST: float = 3.5
const FIRE_LENGTH: float = 11.0
const FIRE_WIDTH: float = 1.2
const FIRE_SWEEP: float = 0.5
const FIRE_BURN: float = 1.5
const FIRE_TICK: float = 0.5
const STRAFE_FLIP_SECONDS: float = 2.5
const STRAFE_RANGE: float = 11.0
const STRAFE_PREFERRED: float = 5.5
const SLOWMO_SECONDS: float = 0.5
const SHOCK_RADIUS: float = 5.5
const SHOCK_TIME: float = 0.5
const SHOCK_BAND: float = 0.9
const PHASE2_COLOR: Color = Color(0.75, 0.12, 0.1)
const PHASE2_SPEED_BONUS: float = 1.35
const PHASE2_COOLDOWN_SCALE: float = 0.6
const ARENA_LIMIT: float = 26.0
## Only attacks with at least this much stagger (the heavy finisher) interrupt the boss.
const INTERRUPT_STAGGER: float = 0.5

var phase2: bool = false

var _slam: AttackData
var _flurry: AttackData
var _shock: AttackData
var _charge: AttackData
var _leap: AttackData
var _fire: AttackData
var _slam_count: int = 0
var _shock_pending: bool = false
## Tests set this to force the next attack (&"slam", &"charge" or &"leap").
var forced_attack: StringName = &""
var _planned: StringName = &""
var _special: StringName = &""
var _sp_phase: int = 0  # 0 telegraph, 1 rush / flight, 2 recovery or stun
var _sp_timer: float = 0.0
var _slams_in_row: int = 0
var _last_was_special: bool = false
var _rush_dir: Vector3 = Vector3.FORWARD
var _rush_start: Vector3 = Vector3.ZERO
var _rush_cap: float = 0.0
var _rush_wall: bool = false
var _special_hit_done: bool = false
var _leap_from: Vector3 = Vector3.ZERO
var _leap_to: Vector3 = Vector3.ZERO
var _leap_t: float = 0.0
var _strafe_dir: float = 1.0
var _strafe_time: float = 0.0
var _summons: Array[Node] = []
var _fire_lines: Array[Dictionary] = []
var _marker: MeshInstance3D
var _arrows: Node3D
var _embers: CPUParticles3D
## Counters the tests read (what actually happened, not what the data says).
var stats: Dictionary = {"charges": 0, "wall_stuns": 0, "leaps": 0, "fire_ticks": 0, "phase_changes": 0}
var _chain_flurry: bool = false
var _roaring: bool = false
var _roar_time: float = 0.0
var _roar_shake: float = 0.0
var _shockwaves: Array[Dictionary] = []


func _ready() -> void:
	super()
	add_to_group("boss")
	_uncount()  # the boss must not shrink the soldiers' attack-token limit
	_slam = load(SLAM_PATH) as AttackData
	_flurry = load(FLURRY_PATH) as AttackData
	_shock = load(SHOCK_PATH) as AttackData
	_charge = load(CHARGE_PATH) as AttackData
	_leap = load(LEAP_PATH) as AttackData
	_fire = load(FIRE_PATH) as AttackData
	# Bigger body: collision and name tag follow the visual scale.
	var collider := $CollisionShape3D as CollisionShape3D
	var capsule := (collider.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.radius = 0.4 * body_scale * 0.8
	capsule.height = 1.8 * body_scale
	collider.shape = capsule
	collider.position.y = capsule.height * 0.5
	_label.position.y = capsule.height + 0.6


func is_boss() -> bool:
	return true


func _physics_process(delta: float) -> void:
	_update_shockwaves(delta)
	_update_fire_lines(delta)
	if _roaring:
		_update_roar(delta)
	super(delta)


# --- chase / attack --------------------------------------------------------

func _state_chase(delta: float) -> void:
	var player := _target()
	if player == null:
		state = State.IDLE
		return
	var to := _flat_to(player)
	var dist := to.length()
	var dir := to.normalized()
	_face(dir, delta)
	if _cooldown <= 0.0:
		if _planned == &"":
			_planned = _pick_attack(dist)
		if _planned != &"slam":
			_start_attack()
		elif dist <= attack_range:
			_start_attack()
		else:
			_move_horizontal(dir, move_speed)
	elif phase2 and dist < STRAFE_RANGE:
		_strafe(dir, dist, delta)
	elif dist > attack_range * 0.85:
		_move_horizontal(dir, move_speed)
	else:
		_move_horizontal(Vector3.ZERO, 0.0)


## Phase 2 movement: circle the player at range instead of walking straight in.
func _strafe(dir: Vector3, dist: float, delta: float) -> void:
	_strafe_time -= delta
	if _strafe_time <= 0.0:
		_strafe_time = STRAFE_FLIP_SECONDS
		_strafe_dir = -_strafe_dir
	var side := Vector3(-dir.z, 0.0, dir.x) * _strafe_dir
	var radial := clampf((dist - STRAFE_PREFERRED) * 0.5, -1.0, 1.0)
	var move := side * 0.9 + dir * radial
	_move_horizontal(move.normalized(), move_speed * 0.85)


## Weighted choice with two learnability rules (see the class comment). Distance gates keep every
## special fair: the charge needs room to run, the leap needs a gap to cross.
func _pick_attack(dist: float) -> StringName:
	if forced_attack != &"":
		return forced_attack
	var options: Array[StringName] = [&"slam"]
	var weights: Array[float] = [4.0 if phase2 else 3.0]
	if not _last_was_special:
		if dist >= CHARGE_MIN_DIST:
			options.append(&"charge")
			weights.append(1.0)
		if phase2 and dist >= LEAP_MIN_DIST:
			options.append(&"leap")
			weights.append(2.0)
		if _slams_in_row >= 3 and options.size() > 1:
			options.remove_at(0)
			weights.remove_at(0)
	var total := 0.0
	for w in weights:
		total += w
	var roll := randf() * total
	for i in options.size():
		roll -= weights[i]
		if roll <= 0.0:
			return options[i]
	return options[0]


func _start_attack() -> void:
	var kind := _planned if _planned != &"" else _pick_attack(_dist_to_player())
	_planned = &""
	_special = &""
	_special_hit_done = false
	_sp_phase = 0
	_note_choice(kind)
	if kind == &"charge":
		_special = kind
		_swing = _charge
		_shock_pending = false
		_chain_flurry = false
		_audio(&"boss_charge")
		super()
		return
	if kind == &"leap":
		_special = kind
		_swing = _leap
		_shock_pending = false
		_chain_flurry = false
		_audio(&"boss_leap")
		super()
		return
	_slam_count += 1
	_swing = _slam
	_shock_pending = _slam_count % (2 if phase2 else 3) == 0
	_chain_flurry = phase2
	super()


func _note_choice(kind: StringName) -> void:
	_last_was_special = kind != &"slam"
	_slams_in_row = _slams_in_row + 1 if kind == &"slam" else 0


func _dist_to_player() -> float:
	var player := _target()
	return _flat_to(player).length() if player else 0.0


func _state_attack(delta: float) -> void:
	if _special == &"charge":
		_state_charge(delta)
		return
	if _special == &"leap":
		_state_leap(delta)
		return
	var before := _attack_frames
	super(delta)
	# The shockwave leaves the boss the moment the slam connects with the ground.
	if _shock_pending and _swing == _slam and before < _slam.startup_frames \
			and _attack_frames >= _slam.startup_frames:
		_shock_pending = false
		_spawn_shockwave()
		_audio(&"boss_slam")
		if phase2:
			_spawn_fire_lines()


func _finish_attack(cooldown: float) -> void:
	if _special != &"":
		_end_special()
	if _chain_flurry and _swing == _slam and state == State.ATTACK:
		_chain_flurry = false
		_swing = _flurry
		_attack_frames = 0.0
		_hitbox.deactivate()
		swing_started.emit()
		return
	super(cooldown)


# --- super armor / phases --------------------------------------------------

func receive_hit(attack: AttackData, from_position: Vector3, damage_scale: float = 1.0) -> bool:
	if _roaring:
		return false  # invulnerable while roaring
	return super(attack, from_position, damage_scale)


func _hit_interrupts(attack: AttackData) -> bool:
	return attack.stagger_time >= INTERRUPT_STAGGER


func _state_stagger(delta: float) -> void:
	if _roaring:
		_stagger_time = maxf(_stagger_time, _roar_time)  # a hit landing on the roar must not cut it short
	super(delta)


func _on_damaged() -> void:
	if not phase2 and _health.health <= _health.max_health * PHASE2_THRESHOLD:
		_begin_phase2()


func _begin_phase2() -> void:
	phase2 = true
	stats["phase_changes"] += 1
	_roaring = true
	_roar_time = ROAR_TIME
	_roar_shake = 0.0
	_hitbox.deactivate()
	_weapon_pivot.visible = false
	_release_token()
	_chain_flurry = false
	_shock_pending = false
	_end_special()
	_planned = &""
	_spawn_shockwave(false)
	_audio(&"boss_roar")
	Outpost17.say(self, "The Warden is enraged!", 3.5)
	_start_embers()
	state = State.STAGGER
	_stagger_time = ROAR_TIME
	body_color = PHASE2_COLOR
	move_speed *= PHASE2_SPEED_BONUS
	cooldown_min *= PHASE2_COOLDOWN_SCALE
	cooldown_max *= PHASE2_COOLDOWN_SCALE
	_cooldown = 0.5
	_shake_camera(0.8)
	_summon_soldiers.call_deferred()


func _update_roar(delta: float) -> void:
	var before := _roar_time
	_roar_time -= delta
	if before > ROAR_TIME * 0.5 and _roar_time <= ROAR_TIME * 0.5:
		_spawn_shockwave(false)  # a second harmless pulse mid-roar
	var t := ROAR_TIME - _roar_time
	_visual_root.scale = Vector3.ONE * body_scale * (1.0 + 0.14 * absf(sin(t * 14.0)))
	_roar_shake -= delta
	if _roar_shake <= 0.0:
		_roar_shake = 0.3
		_shake_camera(0.4)
	if _roar_time <= 0.0:
		_roaring = false
		_visual_root.scale = Vector3.ONE * body_scale * 1.1


func _summon_soldiers() -> void:
	var parent := get_parent()
	var scene := load(SOLDIER_PATH) as PackedScene
	if scene == null or not is_instance_valid(parent) or state == State.DEAD:
		return
	for side in [-1.0, 1.0]:
		var soldier := scene.instantiate() as Node3D
		# Position before add_child so it never overlaps the player at the origin.
		var spot := global_position + Vector3(side * 5.0, 0.0, 0.0)
		soldier.position = Vector3(clampf(spot.x, -ARENA_LIMIT, ARENA_LIMIT), 0.1,
				clampf(spot.z, -ARENA_LIMIT, ARENA_LIMIT))
		parent.add_child(soldier)
		_summons.append(soldier)
		if soldier.has_method("aggro"):
			soldier.call("aggro")


func _shake_camera(amount: float) -> void:
	var cam := get_tree().get_first_node_in_group("camera_controller") as CameraController
	if cam:
		cam.add_trauma(amount)


# --- reward ----------------------------------------------------------------

## Guaranteed: every entry of the loot table (cleaver, plate, medkit) plus one extra medkit.
func _drop_loot() -> void:
	var table := load(loot_table_path) as LootTable
	if table == null:
		return
	var paths: Array[String] = []
	for path in table.item_paths:
		paths.append(path)
	paths.append(EXTRA_DROP_PATH)
	for i in paths.size():
		var item := load(paths[i]) as ItemData
		var angle := TAU * i / paths.size()
		var spot := Vector3(
				clampf(global_position.x + cos(angle) * 2.2, -ARENA_LIMIT, ARENA_LIMIT), 0.0,
				clampf(global_position.z + sin(angle) * 2.2, -ARENA_LIMIT, ARENA_LIMIT))
		Pickup.spawn.call_deferred(get_parent(), item, spot)


# --- shockwave -------------------------------------------------------------

static var _ring_mesh: CylinderMesh
static var _ring_material: StandardMaterial3D


## Shared by every shockwave (and by the warm-up), so a slam never builds a mesh or a material.
static func ring_resources() -> Array:
	if _ring_mesh == null:
		_ring_mesh = CylinderMesh.new()
		_ring_mesh.top_radius = 1.0
		_ring_mesh.bottom_radius = 1.0
		_ring_mesh.height = 0.15
		_ring_material = StandardMaterial3D.new()
		_ring_material.albedo_color = Color(1.0, 0.25, 0.1, 0.45)
		_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return [_ring_mesh, _ring_material]


func _spawn_shockwave(harmful: bool = true) -> void:
	var ring := MeshInstance3D.new()
	var resources := Warden.ring_resources()
	ring.mesh = resources[0]
	ring.material_override = resources[1]
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.top_level = true  # stay where the slam landed instead of following the boss
	add_child(ring)
	ring.global_position = Vector3(global_position.x, 0.1, global_position.z)
	ring.scale = Vector3(0.01, 1.0, 0.01)
	_shockwaves.append({"node": ring, "age": 0.0, "hit": not harmful, "origin": ring.global_position})
	_shake_camera(0.5 if harmful else 0.2)


func _update_shockwaves(delta: float) -> void:
	for i in range(_shockwaves.size() - 1, -1, -1):
		var wave := _shockwaves[i]
		var ring := wave["node"] as MeshInstance3D
		wave["age"] = (wave["age"] as float) + delta
		var age := wave["age"] as float
		var radius := SHOCK_RADIUS * clampf(age / SHOCK_TIME, 0.0, 1.0)
		if age >= SHOCK_TIME + 0.1:
			ring.queue_free()
			_shockwaves.remove_at(i)
			continue
		ring.scale = Vector3(maxf(radius, 0.01), 1.0, maxf(radius, 0.01))
		if wave["hit"] or age > SHOCK_TIME:
			continue
		var player := _target()
		if player == null or not player.is_on_floor():
			continue  # jumping over the ring is the intended counter
		var origin := wave["origin"] as Vector3
		var flat := Vector2(player.global_position.x - origin.x, player.global_position.z - origin.z)
		if absf(flat.length() - radius) <= SHOCK_BAND:
			wave["hit"] = player.receive_hit(_shock, origin)


# --- charge (Milestone 4) ---------------------------------------------------

func _state_charge(delta: float) -> void:
	_attack_frames += delta * FPS
	var player := _target()
	match _sp_phase:
		0:
			_move_horizontal(Vector3.ZERO, 0.0)
			if _attack_frames < _charge.startup_frames * 0.6 and player:
				_face(_flat_to(player).normalized(), delta)  # aim during the first part, then commit
			_rush_dir = _facing_flat()
			_show_arrows(_rush_dir)
			if _attack_frames >= _charge.startup_frames:
				_begin_rush(player)
		1:
			_rush(player)
		2:
			_move_horizontal(Vector3.ZERO, 0.0)
			_sp_timer -= delta
			if _sp_timer <= 0.0:
				_finish_attack(randf_range(cooldown_min, cooldown_max))


func _facing_flat() -> Vector3:
	var f := -_visual_root.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.001 else Vector3.FORWARD


func _begin_rush(player: Player) -> void:
	_sp_phase = 1
	_rush_start = global_position
	_hide_arrows()
	stats["charges"] += 1
	# Cap the run at the first wall or container (a ray), so he never leaves the arena or tunnels.
	var wall_dist := _wall_distance(_rush_dir, CHARGE_MAX + 1.0)
	_rush_wall = wall_dist < CHARGE_MAX + 1.0
	_rush_cap = minf(CHARGE_MAX, maxf(wall_dist - capsule_radius() - 0.05, 0.0))
	if player:
		add_collision_exception_with(player)  # run through the player's body; damage is a radius check


func capsule_radius() -> float:
	return 0.4 * body_scale * 0.8


## Distance along dir to the first static collider (characters are skipped); max_dist when clear.
func _wall_distance(dir: Vector3, max_dist: float) -> float:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, 0.8, 0.0)
	var exclude: Array[RID] = [get_rid()]
	for i in 6:
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return max_dist
		var collider: Object = hit["collider"]
		if collider is CharacterBody3D:
			exclude.append((collider as CollisionObject3D).get_rid())
			continue
		return from.distance_to(hit["position"] as Vector3)
	return max_dist


func _rush(player: Player) -> void:
	var travelled := Vector2(global_position.x - _rush_start.x, global_position.z - _rush_start.z).length()
	_move_horizontal(_rush_dir, CHARGE_SPEED)
	if player and not _special_hit_done and _flat_to(player).length() <= CHARGE_HIT_RADIUS:
		_special_hit_done = true  # one hit per charge
		player.receive_hit(_charge, global_position)
	var blocked := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if not (c.get_collider() is CharacterBody3D) and c.get_normal().dot(_rush_dir) < -0.5:
			blocked = true
	if travelled >= _rush_cap - 0.05 or blocked:
		_end_rush(player, _rush_wall or blocked)


func _end_rush(player: Player, on_wall: bool) -> void:
	_move_horizontal(Vector3.ZERO, 0.0)
	if player and is_instance_valid(player):
		remove_collision_exception_with(player)
	_sp_phase = 2
	_sp_timer = CHARGE_WALL_STUN if on_wall else CHARGE_SHORT_STUN
	if on_wall:
		stats["wall_stuns"] += 1
		_shake_camera(0.7)
		_fx_ring(global_position, 4.0)
		_audio(&"boss_slam")


# --- leap slam (Milestone 4) -------------------------------------------------

func _state_leap(delta: float) -> void:
	_attack_frames += delta * FPS
	var player := _target()
	match _sp_phase:
		0:
			_move_horizontal(Vector3.ZERO, 0.0)
			if _attack_frames < _leap.startup_frames * 0.5 and player:
				_leap_to = Vector3(player.global_position.x, 0.0, player.global_position.z)  # the marker tracks, then locks
				_face(_flat_to(player).normalized(), delta)
			_show_marker(_leap_to)
			_visual_root.position.y = -0.25 * minf(_attack_frames / _leap.startup_frames, 1.0)  # crouch
			if _attack_frames >= _leap.startup_frames:
				_sp_phase = 1
				_leap_from = global_position
				_leap_t = 0.0
				stats["leaps"] += 1
				_visual_root.position.y = 0.0
				if player:
					add_collision_exception_with(player)
		1:
			_leap_t += delta / LEAP_AIR_TIME
			var remaining := maxf(LEAP_AIR_TIME * (1.0 - _leap_t), delta)
			var to := _leap_to - global_position
			to.y = 0.0
			var v := to / remaining
			_move_horizontal(v.normalized(), minf(v.length(), 40.0))
			_visual_root.position.y = sin(clampf(_leap_t, 0.0, 1.0) * PI) * LEAP_HEIGHT
			if _leap_t >= 1.0:
				_land(player)
		2:
			_move_horizontal(Vector3.ZERO, 0.0)
			_sp_timer -= delta
			if _sp_timer <= 0.0:
				_finish_attack(randf_range(cooldown_min, cooldown_max))


func _land(player: Player) -> void:
	_visual_root.position.y = 0.0
	_move_horizontal(Vector3.ZERO, 0.0)
	_hide_marker()
	if player and is_instance_valid(player):
		remove_collision_exception_with(player)
		var flat := Vector2(player.global_position.x - _leap_to.x, player.global_position.z - _leap_to.z)
		if not _special_hit_done and flat.length() <= LEAP_RADIUS and player.global_position.y < 1.2:
			_special_hit_done = true
			player.receive_hit(_leap, _leap_to)
	_special_hit_done = true
	_sp_phase = 2
	_sp_timer = _leap.recovery_frames / FPS
	_shake_camera(0.8)
	_fx_ring(_leap_to, LEAP_RADIUS)
	_audio(&"boss_leap")


func _end_special() -> void:
	if _special == &"charge" or _special == &"leap":
		var player := _player
		if player != null and is_instance_valid(player):
			remove_collision_exception_with(player)
	_special = &""
	_sp_phase = 0
	_hide_arrows()
	_hide_marker()
	if _visual_root:
		_visual_root.position.y = 0.0


# --- telegraph visuals (cheap: shared mesh and material, created on first use) -------

static var _tele_material: StandardMaterial3D
static var _fire_material: StandardMaterial3D
static var _flat_mesh: BoxMesh


static func _telegraph_resources() -> void:
	if _flat_mesh != null:
		return
	_flat_mesh = BoxMesh.new()
	_flat_mesh.size = Vector3(1.0, 0.06, 1.0)
	_tele_material = StandardMaterial3D.new()
	_tele_material.albedo_color = Color(1.0, 0.2, 0.1, 0.45)
	_tele_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tele_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fire_material = StandardMaterial3D.new()
	_fire_material.albedo_color = Color(0.85, 0.08, 0.05, 0.6)
	_fire_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


static func _flat_node(use_fire: bool) -> MeshInstance3D:
	Warden._telegraph_resources()
	var node := MeshInstance3D.new()
	node.mesh = _flat_mesh
	node.material_override = _fire_material if use_fire else _tele_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


func _show_arrows(dir: Vector3) -> void:
	if _arrows == null:
		_arrows = Node3D.new()
		_arrows.top_level = true
		add_child(_arrows)
		for side in [-1.0, 1.0]:
			var arrow := Warden._flat_node(false)
			arrow.scale = Vector3(0.7, 1.0, CHARGE_MAX)
			arrow.position = Vector3(side * 0.9, 0.0, 0.0)
			_arrows.add_child(arrow)
	_arrows.visible = true
	var origin := Vector3(global_position.x, 0.1, global_position.z)
	var center := origin + dir * (CHARGE_MAX * 0.5 + 1.0)
	_arrows.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), center)


func _hide_arrows() -> void:
	if _arrows != null:
		_arrows.visible = false


func _show_marker(at: Vector3) -> void:
	if _marker == null:
		var resources := Warden.ring_resources()
		_marker = MeshInstance3D.new()
		_marker.mesh = resources[0]
		_marker.material_override = resources[1]
		_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_marker.top_level = true
		add_child(_marker)
	_marker.visible = true
	_marker.global_position = Vector3(at.x, 0.08, at.z)
	_marker.scale = Vector3(LEAP_RADIUS, 1.0, LEAP_RADIUS)


func _hide_marker() -> void:
	if _marker != null:
		_marker.visible = false


# --- fire lines (phase 2) ----------------------------------------------------

func _spawn_fire_lines() -> void:
	var player := _target()
	var base := Vector3.FORWARD
	if player:
		base = _flat_to(player).normalized()
	var origin := Vector3(global_position.x, 0.1, global_position.z)
	for i in 3:
		var dir := base.rotated(Vector3.UP, TAU * i / 3.0)
		var node := Warden._flat_node(true)
		node.top_level = true
		add_child(node)
		node.global_position = origin
		_fire_lines.append({"node": node, "age": 0.0, "dir": dir, "origin": origin, "tick": 0.0})
	_audio(&"boss_fire")


func _update_fire_lines(delta: float) -> void:
	for i in range(_fire_lines.size() - 1, -1, -1):
		var line := _fire_lines[i]
		var node := line["node"] as MeshInstance3D
		line["age"] = (line["age"] as float) + delta
		var age := line["age"] as float
		if age >= FIRE_SWEEP + FIRE_BURN or not is_instance_valid(node):
			if is_instance_valid(node):
				node.queue_free()
			_fire_lines.remove_at(i)
			continue
		var dir := line["dir"] as Vector3
		var origin := line["origin"] as Vector3
		var length := FIRE_LENGTH * clampf(age / FIRE_SWEEP, 0.02, 1.0)
		node.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP).scaled(Vector3(FIRE_WIDTH, 1.0, length)),
				origin + dir * length * 0.5)
		line["tick"] = (line["tick"] as float) - delta
		var player := _target()
		if player == null or (line["tick"] as float) > 0.0 or player.global_position.y > 0.8:
			continue  # jumping clears the flames
		var rel := Vector2(player.global_position.x - origin.x, player.global_position.z - origin.z)
		var d2 := Vector2(dir.x, dir.z)
		var along := rel.dot(d2)
		var across := absf(rel.cross(d2))
		if along >= 0.0 and along <= length and across <= FIRE_WIDTH * 0.5 + 0.3:
			line["tick"] = FIRE_TICK
			stats["fire_ticks"] += 1
			player.receive_hit(_fire, origin)


func _clear_fire_lines() -> void:
	for line in _fire_lines:
		var node := line["node"] as Node
		if is_instance_valid(node):
			node.queue_free()
	_fire_lines.clear()


# --- aura, audio, defeat -----------------------------------------------------

func _start_embers() -> void:
	if _embers != null:
		return
	var fx := get_node_or_null("/root/Fx")
	var quality := 1.0
	if fx != null and fx.get("quality_scale") != null:
		quality = float(fx.get("quality_scale"))
	if quality <= 0.0:
		return
	_embers = CPUParticles3D.new()
	_embers.amount = maxi(int(round(18.0 * quality)), 3)
	_embers.lifetime = 1.1
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_embers.emission_sphere_radius = 0.9 * body_scale
	_embers.direction = Vector3.UP
	_embers.spread = 20.0
	_embers.gravity = Vector3(0.0, 1.2, 0.0)
	_embers.initial_velocity_min = 0.4
	_embers.initial_velocity_max = 1.2
	_embers.scale_amount_min = 0.05
	_embers.scale_amount_max = 0.1
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 4
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.35, 0.1)
	mesh.material = mat
	_embers.mesh = mesh
	_embers.position.y = 1.2 * body_scale
	add_child(_embers)


func _audio(sound: StringName) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play"):
		audio.call("play", sound)


func _fx_ring(at: Vector3, radius: float) -> void:
	var fx := get_node_or_null("/root/Fx")
	if fx != null and fx.has_method("ring"):
		fx.call("ring", at, radius, Color(1.0, 0.25, 0.1))


func _die() -> void:
	_end_special()
	_planned = &""
	_clear_fire_lines()
	if _embers != null:
		_embers.emitting = false
	for summon in _summons:
		if is_instance_valid(summon) and not (summon is Enemy and (summon as Enemy).is_dead()):
			summon.queue_free()
	_summons.clear()
	super()
	HitStop.trigger(SLOWMO_SECONDS)
