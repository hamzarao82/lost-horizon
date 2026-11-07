class_name EliteExperimentalSubject
extends Enemy
## Research Complex mini-boss (Milestone 8): three telegraphed attacks, one hit per use, and a punish
## window after each. It extends Enemy the way the Warden does and does not touch enemy.gd.
##
##   claw   : crouch (marker on the ground where it will land), leap, landing hit in a small radius.
##   ring   : crouch, then a shockwave ring that is only dangerous on the ground (jump or dodge it).
##   charge : two ground strips show the line, rush, one hit, long stun when it hits a wall.
##
## Fairness numbers live in resources/attacks/experimental_*.tres and are asserted by
## tests/experimental_enemies_check.gd: telegraph >= 0.6 s (charge >= 0.8 s), punish >= 0.5 s.
## The red tell is the shared Enemy windup colour for the whole telegraph.

const CLAW_PATH: String = "res://resources/attacks/experimental_claw.tres"
const RING_PATH: String = "res://resources/attacks/experimental_ring.tres"
const CHARGE_PATH: String = "res://resources/attacks/experimental_charge.tres"
const REGION: StringName = &"research_complex"
const REWARD_PATH: String = "res://resources/items/containment_sigil.tres"

const CLAW_AIR_TIME: float = 0.45
const CLAW_RADIUS: float = 2.6
const CLAW_MIN_DIST: float = 3.0
const CLAW_MAX_DIST: float = 10.0
const CLAW_HEIGHT: float = 2.5
const RING_RADIUS: float = 4.5
const RING_TIME: float = 0.5
const RING_BAND: float = 0.9
const RING_TRIGGER: float = 5.0
const CHARGE_SPEED: float = 15.0
const CHARGE_MAX: float = 12.0
const CHARGE_MIN_DIST: float = 5.0
const CHARGE_HIT_RADIUS: float = 1.6
const CHARGE_WALL_STUN: float = 1.5
const CHARGE_SHORT_STUN: float = 0.8
## Only attacks with at least this much stagger (the heavy finisher) interrupt it.
const INTERRUPT_STAGGER: float = 0.5

## Tests set this to force the next attack (&"claw", &"ring" or &"charge").
var forced_attack: StringName = &""
## What actually happened, for tests.
var stats: Dictionary = {"claws": 0, "rings": 0, "charges": 0, "wall_stuns": 0, "hits": 0, "last_claw_error": -1.0}

var _claw: AttackData
var _ring: AttackData
var _charge: AttackData
var _special: StringName = &""
var _sp_phase: int = 0  # 0 telegraph, 1 action, 2 recovery or stun
var _sp_timer: float = 0.0
var _hit_done: bool = false
var _last_kind: StringName = &""
var _repeat_count: int = 0
var _leap_to: Vector3 = Vector3.ZERO
var _leap_t: float = 0.0
var _rush_dir: Vector3 = Vector3.FORWARD
var _rush_start: Vector3 = Vector3.ZERO
var _rush_cap: float = 0.0
var _rush_wall: bool = false
var _marker: MeshInstance3D
var _rings: Array[Dictionary] = []

static var _flat_mesh: BoxMesh
static var _ring_mesh: CylinderMesh
static var _tele_material: StandardMaterial3D


func _ready() -> void:
	patrol_route = null  # a containment subject never patrols
	super()
	add_to_group("miniboss")
	_uncount()  # must not shrink the soldiers' attack-token limit
	_claw = load(CLAW_PATH) as AttackData
	_ring = load(RING_PATH) as AttackData
	_charge = load(CHARGE_PATH) as AttackData


func is_boss() -> bool:
	return false


func _physics_process(delta: float) -> void:
	_update_rings(delta)
	super(delta)


# --- chase and attack choice ---------------------------------------------------

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
	if _cooldown <= 0.0:
		_start_attack()
		return
	if dist > attack_range + 1.5:
		_move_horizontal(dir, move_speed)
	else:
		_move_horizontal(Vector3.ZERO, 0.0)


## Distance gates keep every attack fair (the charge needs room, the claw needs a gap, the ring needs
## the player close); the same attack never runs three times in a row.
func _pick_attack(dist: float) -> StringName:
	if forced_attack != &"":
		return forced_attack
	var options: Array[StringName] = []
	var weights: Array[float] = []
	if dist >= CLAW_MIN_DIST and dist <= CLAW_MAX_DIST:
		options.append(&"claw")
		weights.append(3.0)
	if dist <= RING_TRIGGER:
		options.append(&"ring")
		weights.append(2.0)
	if dist >= CHARGE_MIN_DIST:
		options.append(&"charge")
		weights.append(1.0)
	if options.is_empty():
		options.append(&"ring")
		weights.append(1.0)
	if _repeat_count >= 2 and options.size() > 1 and options.has(_last_kind):
		var idx := options.find(_last_kind)
		options.remove_at(idx)
		weights.remove_at(idx)
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
	var player := _target()
	var dist := _flat_to(player).length() if player else 0.0
	var kind := _pick_attack(dist)
	_repeat_count = _repeat_count + 1 if kind == _last_kind else 1
	_last_kind = kind
	_special = kind
	_sp_phase = 0
	_hit_done = false
	match kind:
		&"claw":
			_swing = _claw
		&"ring":
			_swing = _ring
		_:
			_swing = _charge
	super()


func _state_attack(delta: float) -> void:
	_attack_frames += delta * FPS
	var player := _target()
	match _special:
		&"claw":
			_claw_step(delta, player)
		&"ring":
			_ring_step(delta, player)
		_:
			_charge_step(delta, player)


func _finish_attack(cooldown: float) -> void:
	_end_special()
	super(cooldown)


func _hit_interrupts(attack: AttackData) -> bool:
	return attack.stagger_time >= INTERRUPT_STAGGER


func _end_special() -> void:
	if _special == &"claw" or _special == &"charge":
		var player := _player
		if player != null and is_instance_valid(player):
			remove_collision_exception_with(player)
	_special = &""
	_sp_phase = 0
	_hide_marker()
	if _visual_root:
		_visual_root.position.y = 0.0


# --- claw: leap --------------------------------------------------------------

func _claw_step(delta: float, player: Player) -> void:
	match _sp_phase:
		0:
			_move_horizontal(Vector3.ZERO, 0.0)
			if _attack_frames < _claw.startup_frames * 0.5 and player:
				var spot := Vector3(player.global_position.x, 0.0, player.global_position.z)
				var offset := spot - Vector3(global_position.x, 0.0, global_position.z)
				if offset.length() > CLAW_MAX_DIST:
					spot = Vector3(global_position.x, 0.0, global_position.z) + offset.normalized() * CLAW_MAX_DIST
				_leap_to = spot  # the marker tracks, then locks
				_face(_flat_to(player).normalized(), delta)
			_show_marker(_leap_to)
			_visual_root.position.y = -0.2 * minf(_attack_frames / _claw.startup_frames, 1.0)
			if _attack_frames >= _claw.startup_frames:
				_sp_phase = 1
				_leap_t = 0.0
				stats["claws"] += 1
				_visual_root.position.y = 0.0
				if player:
					add_collision_exception_with(player)
		1:
			_leap_t += delta / CLAW_AIR_TIME
			var remaining := maxf(CLAW_AIR_TIME * (1.0 - _leap_t), delta)
			var to := _leap_to - Vector3(global_position.x, 0.0, global_position.z)
			var v := to / remaining
			_move_horizontal(v.normalized(), minf(v.length(), 40.0))
			_visual_root.position.y = sin(clampf(_leap_t, 0.0, 1.0) * PI) * CLAW_HEIGHT
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
	stats["last_claw_error"] = Vector2(global_position.x - _leap_to.x, global_position.z - _leap_to.z).length()
	if player and is_instance_valid(player):
		remove_collision_exception_with(player)
		var flat := Vector2(player.global_position.x - _leap_to.x, player.global_position.z - _leap_to.z)
		if not _hit_done and flat.length() <= CLAW_RADIUS and player.global_position.y < 1.2:
			_hit_done = true
			if player.receive_hit(_claw, _leap_to):
				stats["hits"] += 1
	_hit_done = true
	_sp_phase = 2
	_sp_timer = _claw.recovery_frames / FPS
	_shake_camera(0.6)


# --- ring: ground shockwave ------------------------------------------------------

func _ring_step(delta: float, player: Player) -> void:
	match _sp_phase:
		0:
			_move_horizontal(Vector3.ZERO, 0.0)
			if _attack_frames < _ring.startup_frames * 0.6 and player:
				_face(_flat_to(player).normalized(), delta)
			_visual_root.position.y = -0.25 * minf(_attack_frames / _ring.startup_frames, 1.0)
			_show_marker(global_position)  # the whole danger zone is marked on the ground
			if _attack_frames >= _ring.startup_frames:
				_sp_phase = 1
				stats["rings"] += 1
				_hide_marker()
				_visual_root.position.y = 0.0
				_spawn_ring()
				_sp_timer = (_ring.active_frames + _ring.recovery_frames) / FPS
		_:
			_move_horizontal(Vector3.ZERO, 0.0)
			_sp_timer -= delta
			if _sp_timer <= 0.0:
				_finish_attack(randf_range(cooldown_min, cooldown_max))


func _spawn_ring() -> void:
	_ensure_resources()
	var node := MeshInstance3D.new()
	node.mesh = _ring_mesh
	node.material_override = _tele_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.top_level = true  # stays where it was released instead of following the enemy
	add_child(node)
	node.global_position = Vector3(global_position.x, 0.1, global_position.z)
	node.scale = Vector3(0.01, 1.0, 0.01)
	_rings.append({"node": node, "age": 0.0, "hit": false, "origin": node.global_position})
	_shake_camera(0.4)


func _update_rings(delta: float) -> void:
	for i in range(_rings.size() - 1, -1, -1):
		var ring := _rings[i]
		var node := ring["node"] as MeshInstance3D
		ring["age"] = (ring["age"] as float) + delta
		var age := ring["age"] as float
		var radius := RING_RADIUS * clampf(age / RING_TIME, 0.0, 1.0)
		if age >= RING_TIME + 0.1:
			node.queue_free()
			_rings.remove_at(i)
			continue
		node.scale = Vector3(maxf(radius, 0.01), 1.0, maxf(radius, 0.01))
		if ring["hit"] or age > RING_TIME:
			continue
		var player := _target()
		if player == null or not player.is_on_floor():
			continue  # jumping over the ring is the intended counter
		var origin := ring["origin"] as Vector3
		var flat := Vector2(player.global_position.x - origin.x, player.global_position.z - origin.z)
		if absf(flat.length() - radius) <= RING_BAND:
			ring["hit"] = player.receive_hit(_ring, origin)
			if ring["hit"]:
				stats["hits"] += 1


# --- charge --------------------------------------------------------------------

func _charge_step(delta: float, player: Player) -> void:
	match _sp_phase:
		0:
			_move_horizontal(Vector3.ZERO, 0.0)
			if _attack_frames < _charge.startup_frames * 0.6 and player:
				_face(_flat_to(player).normalized(), delta)  # aim, then commit
			_rush_dir = _facing_flat()
			_show_marker(global_position + _rush_dir * 3.0)
			if _attack_frames >= _charge.startup_frames:
				_begin_rush(player)
		1:
			_rush(player)
		_:
			_move_horizontal(Vector3.ZERO, 0.0)
			_sp_timer -= delta
			if _sp_timer <= 0.0:
				_finish_attack(randf_range(cooldown_min, cooldown_max))


func _facing_flat() -> Vector3:
	var f := -_visual_root.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.001 else Vector3.FORWARD


func capsule_radius() -> float:
	return 0.4 * body_scale * 0.8


func _begin_rush(player: Player) -> void:
	_sp_phase = 1
	_rush_start = global_position
	_hide_marker()
	stats["charges"] += 1
	var wall_dist := _wall_distance(_rush_dir, CHARGE_MAX + 1.0)
	_rush_wall = wall_dist < CHARGE_MAX + 1.0
	_rush_cap = minf(CHARGE_MAX, maxf(wall_dist - capsule_radius() - 0.05, 0.0))
	if player:
		add_collision_exception_with(player)  # run through the body; damage is a radius check


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
	if player and not _hit_done and _flat_to(player).length() <= CHARGE_HIT_RADIUS:
		_hit_done = true  # one hit per charge
		if player.receive_hit(_charge, global_position):
			stats["hits"] += 1
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
		_shake_camera(0.6)


# --- tell visuals (cheap: shared meshes and one material) ------------------------

static func _ensure_resources() -> void:
	if _flat_mesh != null:
		return
	_flat_mesh = BoxMesh.new()
	_flat_mesh.size = Vector3(1.0, 0.06, 1.0)
	_ring_mesh = CylinderMesh.new()
	_ring_mesh.top_radius = 1.0
	_ring_mesh.bottom_radius = 1.0
	_ring_mesh.height = 0.15
	_tele_material = StandardMaterial3D.new()
	_tele_material.albedo_color = Color(1.0, 0.2, 0.1, 0.45)
	_tele_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tele_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _show_marker(spot: Vector3) -> void:
	_ensure_resources()
	if _marker == null:
		_marker = MeshInstance3D.new()
		_marker.mesh = _flat_mesh
		_marker.material_override = _tele_material
		_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_marker.top_level = true
		add_child(_marker)
	_marker.visible = true
	_marker.global_position = Vector3(spot.x, 0.1, spot.z)
	var wide := 1.2
	var deep := CHARGE_MAX
	if _special == &"claw":
		wide = CLAW_RADIUS * 2.0
		deep = wide
	elif _special == &"ring":
		wide = RING_RADIUS * 2.0
		deep = wide
	_marker.mesh = _ring_mesh if _special == &"ring" else _flat_mesh  # the ring zone is a disc, not a square
	_marker.scale = Vector3(RING_RADIUS, 1.0, RING_RADIUS) if _special == &"ring" else Vector3(wide, 1.0, deep)
	if _special == &"charge":
		_marker.global_position = Vector3(global_position.x, 0.1, global_position.z) + _rush_dir * (CHARGE_MAX * 0.5 + 1.0)
		_marker.rotation.y = atan2(-_rush_dir.x, -_rush_dir.z)
	else:
		_marker.rotation.y = 0.0


func _hide_marker() -> void:
	if _marker != null:
		_marker.visible = false


func _shake_camera(amount: float) -> void:
	var cam := get_tree().get_first_node_in_group("camera_controller") as CameraController
	if cam:
		cam.add_trauma(amount)


# --- reward and defeat -------------------------------------------------------------

## Defeat removes every live hazard and drops the unique reward at most once per save.
func _die() -> void:
	for ring in _rings:
		var node := ring["node"] as Node
		if is_instance_valid(node):
			node.queue_free()
	_rings.clear()
	_end_special()
	super()

## The unique reward is claimed by the Inventory when it is picked up, so it is dropped unless this save
## already owns it. Dying and reloading before the pickup is covered by FacilityEnemySpawn, which puts the
## pending reward back when it restores a cleared elite.
func _drop_loot() -> void:
	var item := load(REWARD_PATH) as ItemData
	if item != null and not reward_owned(_player, item):
		Pickup.spawn.call_deferred(get_parent(), item, Vector3(global_position.x, 0.0, global_position.z))
	if loot_table_path != "":
		super()


static func reward_owned(player: Node, item: ItemData) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var inventory: Object = player.get("inventory")
	return inventory != null and inventory.has_method("is_unique_claimed") \
			and inventory.is_unique_claimed(String(item.item_id))
