class_name Warden
extends Enemy
## Boss: heavy overhead slams with a periodic ground shockwave (jump or dodge it).
## Below half health it roars (invulnerable), enrages, chains a flurry after each slam,
## shockwaves more often, and calls two soldiers once. Only heavy hits interrupt it.

const SLAM_PATH: String = "res://resources/attacks/warden_slam.tres"
const FLURRY_PATH: String = "res://resources/attacks/warden_flurry.tres"
const SHOCK_PATH: String = "res://resources/attacks/warden_shockwave.tres"
const SOLDIER_PATH: String = "res://scenes/enemies/PatrolSoldier.tscn"

const EXTRA_DROP_PATH: String = "res://resources/items/health_potion.tres"
const PHASE2_THRESHOLD: float = 0.5
const ROAR_TIME: float = 1.5
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
var _attack_count: int = 0
var _shock_pending: bool = false
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
	if _cooldown <= 0.0 and dist <= attack_range:
		_start_attack()
	elif dist > attack_range * 0.85:
		_move_horizontal(dir, move_speed)
	else:
		_move_horizontal(Vector3.ZERO, 0.0)


func _start_attack() -> void:
	_attack_count += 1
	_swing = _slam
	_shock_pending = _attack_count % (2 if phase2 else 3) == 0
	_chain_flurry = phase2
	super()


func _state_attack(delta: float) -> void:
	var before := _attack_frames
	super(delta)
	# The shockwave leaves the boss the moment the slam connects with the ground.
	if _shock_pending and _swing == _slam and before < _slam.startup_frames \
			and _attack_frames >= _slam.startup_frames:
		_shock_pending = false
		_spawn_shockwave()


func _finish_attack(cooldown: float) -> void:
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
	_roaring = true
	_roar_time = ROAR_TIME
	_roar_shake = 0.0
	_hitbox.deactivate()
	_weapon_pivot.visible = false
	_release_token()
	_chain_flurry = false
	_shock_pending = false
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
	_roar_time -= delta
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


func _spawn_shockwave() -> void:
	var ring := MeshInstance3D.new()
	var resources := Warden.ring_resources()
	ring.mesh = resources[0]
	ring.material_override = resources[1]
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.top_level = true  # stay where the slam landed instead of following the boss
	add_child(ring)
	ring.global_position = Vector3(global_position.x, 0.1, global_position.z)
	ring.scale = Vector3(0.01, 1.0, 0.01)
	_shockwaves.append({"node": ring, "age": 0.0, "hit": false, "origin": ring.global_position})
	_shake_camera(0.5)


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
