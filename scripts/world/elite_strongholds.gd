class_name EliteStrongholds
extends Node3D
## One optional guarded stronghold per region. It wakes when the player comes near, spawns a small elite squad
## on a free patch of ground away from the main route, and when the squad is dead drops a guaranteed item. The
## drop is claimed through PersistentIds when the player actually picks it up, so a reload before that simply
## brings the squad back and a reload after never repeats it. Regions add one with `EliteStrongholds.add_to`.

const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const HEAVY: String = "res://scenes/enemies/HeavySoldier.tscn"
const HUNTER: String = "res://scenes/enemies/HunterElite.tscn"

## Preferred centre (x, z in the region's own space, off the main route), guards and the guaranteed drop.
const CONFIG: Dictionary = {
	&"outpost_17": {"id": &"elite_stronghold", "center": Vector2(-16.0, -52.0),
		"guards": [HUNTER, SOLDIER, SOLDIER], "drop": "res://resources/items/katana.tres"},
	&"dead_coast": {"id": &"elite_stronghold", "center": Vector2(30.0, -60.0),
		"guards": [HEAVY, HUNTER, SOLDIER], "drop": "res://resources/items/heavy_combat_armor.tres"},
	&"blackwood": {"id": &"elite_stronghold", "center": Vector2(12.0, -78.0),
		"guards": [HEAVY, HUNTER, HUNTER], "drop": "res://resources/items/claymore.tres"},
	&"research_complex": {"id": &"elite_stronghold", "center": Vector2(-20.0, -65.0),
		"guards": [HUNTER, HUNTER, HEAVY], "drop": "res://resources/items/tactical_sword.tres"},
	&"iron_fortress": {"id": &"elite_stronghold", "center": Vector2(-22.0, -67.0),
		"guards": [HEAVY, HEAVY, HUNTER, HUNTER], "drop": "res://resources/items/reinforced_armor.tres"},
}

## Dead Coast is laid out along a shore line: its x is an inland distance from the shore at that z.
const DEAD_COAST_INLAND: float = 42.0
## Small on purpose: Outpost 17's stronghold sits just north of the arena courtyard and must never wake during an arena fight.
const PROXIMITY: float = 20.0
const POLL_SECONDS: float = 0.5
const SEARCH_RADII: Array[float] = [0.0, 4.0, 8.0, 12.0, 16.0, 22.0]
const SEARCH_ANGLES: int = 8
const CLEAR_RADIUS: float = 1.6
const ROUTE_CLEARANCE: float = 10.0
const RING_RADIUS: float = 3.0
const MARKER_HEIGHT: float = 7.0

var region_id: StringName = &""
var stronghold_id: StringName = &""
var center: Vector2 = Vector2.ZERO
var guard_paths: Array = []
var drop_path: String = ""
var route: Array[Vector3] = []

var spawned: bool = false
var enemies: Array[Node] = []
var spot: Vector3 = Vector3.ZERO
var drop_item: ItemData
var pickup: Pickup
var retired: bool = false

var _clock: float = 0.0


static func region_ids() -> Array:
	return CONFIG.keys()


static func has_config(id: StringName) -> bool:
	return CONFIG.has(id)


## Adds the stronghold to a region node (the guards and the drop live in that node's space).
static func add_to(region: Node3D, id: StringName) -> EliteStrongholds:
	if region == null or not CONFIG.has(id):
		return null
	var node := EliteStrongholds.new()
	node.name = "EliteStronghold"
	node.region_id = id
	node.stronghold_id = CONFIG[id]["id"]
	node.center = CONFIG[id]["center"]
	node.guard_paths = CONFIG[id]["guards"]
	node.drop_path = CONFIG[id]["drop"]
	region.add_child(node)
	return node


func _ready() -> void:
	add_to_group("elite_strongholds")
	route = _route_for(region_id)
	if region_id == &"dead_coast":
		center.x = DeadCoastTerrain.shore_x(center.y) + DEAD_COAST_INLAND


func _process(delta: float) -> void:
	if retired:
		return
	_clock += delta
	if _clock < POLL_SECONDS:
		return
	_clock = 0.0
	step()


## One poll: retire if already claimed, wake the squad when the player is near, drop the reward when it is dead.
func step() -> void:
	if retired or not is_inside_tree():
		return
	if PersistentIds.is_claimed(region_id, stronghold_id):
		_retire()
		return
	if not spawned:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player != null and _flat_distance(player.global_position, _center_global()) <= PROXIMITY:
			spawn()
		return
	if pickup != null and is_instance_valid(pickup):
		return
	if _all_dead():
		_drop()


func _center_global() -> Vector3:
	return to_global(Vector3(center.x, 0.0, center.y))


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _all_dead() -> bool:
	for enemy in enemies:
		if is_instance_valid(enemy) and not (enemy.has_method("is_dead") and enemy.is_dead()):
			return false
	return true


## Finds a free spot near the preferred centre and spawns the squad around it. Returns the squad size
## (0 when no free ground exists, in which case the stronghold quietly stays off rather than blocking anything).
func spawn() -> int:
	if spawned or retired:
		return 0
	var found: Variant = find_spot()
	if found == null:
		retired = true
		return 0
	spawned = true
	spot = found
	_build_marker()
	var parent := get_parent()
	for i in guard_paths.size():
		var scene := load(guard_paths[i]) as PackedScene
		if scene == null:
			continue
		var angle := TAU * float(i) / float(maxi(guard_paths.size(), 1))
		var local := spot + Vector3(cos(angle), 0.0, sin(angle)) * RING_RADIUS
		var enemy := scene.instantiate() as Node3D
		enemy.position = to_local_in(parent, local)
		parent.add_child(enemy)
		enemies.append(enemy)
	return enemies.size()


static func to_local_in(parent: Node, global_point: Vector3) -> Vector3:
	return (parent as Node3D).to_local(global_point) if parent is Node3D else global_point


## Searches rings around the preferred centre for ground that is flat, free of solid objects and off the route.
## Returns a global position or null.
func find_spot() -> Variant:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var base_y := player.global_position.y if player != null else 0.0
	var origin := _center_global()
	for radius in SEARCH_RADII:
		var steps := 1 if radius == 0.0 else SEARCH_ANGLES
		for i in steps:
			var angle := TAU * float(i) / float(steps)
			var probe := origin + Vector3(cos(angle), 0.0, sin(angle)) * radius
			var floor_point: Variant = _floor_at(probe, base_y)
			if floor_point == null:
				continue
			var candidate: Vector3 = floor_point
			if _route_distance(candidate) < ROUTE_CLEARANCE:
				continue
			if _is_free(candidate) and _ring_is_free(candidate):
				return candidate
	return null


func _floor_at(point: Vector3, base_y: float) -> Variant:
	var space := get_world_3d().direct_space_state
	for start_height in [2.5, 8.0]:
		var query := PhysicsRayQueryParameters3D.create(
				Vector3(point.x, base_y + start_height, point.z), Vector3(point.x, base_y - 40.0, point.z))
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and (hit["normal"] as Vector3).y > 0.85 and hit["collider"] is StaticBody3D:
			return hit["position"]
	return null


func _is_free(ground: Vector3) -> bool:
	return _sphere_free(ground + Vector3(0.0, CLEAR_RADIUS + 0.4, 0.0), CLEAR_RADIUS)


func _ring_is_free(ground: Vector3) -> bool:
	for i in guard_paths.size():
		var angle := TAU * float(i) / float(maxi(guard_paths.size(), 1))
		var p := ground + Vector3(cos(angle), 0.0, sin(angle)) * RING_RADIUS
		if not _sphere_free(p + Vector3(0.0, CLEAR_RADIUS + 0.9, 0.0), CLEAR_RADIUS):
			return false
	return true


func _sphere_free(at: Vector3, radius: float) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = 1
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 8):
		if hit["collider"] is StaticBody3D:
			return false
	return true


func _route_distance(point: Vector3) -> float:
	var best := INF
	var flat := Vector2(point.x, point.z)
	for p in route:
		var g := (get_parent() as Node3D).to_global(p) if get_parent() is Node3D else p
		best = minf(best, flat.distance_to(Vector2(g.x, g.z)))
	return best


func _drop() -> void:
	if drop_item == null:
		drop_item = load(drop_path) as ItemData
	if drop_item == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player != null and player.inventory != null and not player.inventory.item_collected.is_connected(_on_item_collected):
		player.inventory.item_collected.connect(_on_item_collected)
	var parent := get_parent()
	pickup = Pickup.spawn(parent, drop_item, to_local_in(parent, spot + Vector3(0.0, 0.8, 0.0)))


## The real "got it" signal: the inventory kept the item. A weapon or armor that is no upgrade is not kept and
## stays on the ground, so it does not claim.
func _on_item_collected(item: ItemData, kept: bool) -> void:
	if retired or not kept or item == null or drop_item == null:
		return
	if String(item.item_id) == String(drop_item.item_id):
		PersistentIds.claim(region_id, stronghold_id)
		_retire()


func _retire() -> void:
	retired = true
	if has_node("Marker"):
		get_node("Marker").queue_free()


func _build_marker() -> void:
	var marker := Node3D.new()
	marker.name = "Marker"
	add_child(marker)
	marker.global_position = spot
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.12
	cyl.height = MARKER_HEIGHT
	pillar.mesh = cyl
	pillar.position = Vector3(0.0, MARKER_HEIGHT * 0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.9, 0.2, 0.15)
	material.emission_enabled = true
	material.emission = Color(0.9, 0.2, 0.15)
	material.emission_energy_multiplier = 1.4
	pillar.material_override = material
	marker.add_child(pillar)
	var label := Label3D.new()
	label.text = "ELITE STRONGHOLD"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36
	label.outline_size = 10
	label.modulate = Color(1.0, 0.45, 0.35)
	label.position = Vector3(0.0, MARKER_HEIGHT + 0.7, 0.0)
	marker.add_child(label)


static func _route_for(id: StringName) -> Array[Vector3]:
	var out: Array[Vector3] = []
	match id:
		&"dead_coast":
			out = DeadCoast.main_path()
		&"research_complex":
			out = ResearchComplex.main_path()
		&"iron_fortress":
			out = IronFortress.main_path()
		&"blackwood":
			for p in Blackwood.TRAIL_MAIN:
				out.append(Vector3(p.x, 0.0, p.y))
		&"outpost_17":
			var z := 48.0
			while z >= -92.0:
				out.append(Vector3(0.0, 0.0, z))
				z -= 4.0
	return out
