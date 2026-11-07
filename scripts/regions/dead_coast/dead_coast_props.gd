class_name DeadCoastProps
extends RefCounted
## Static dressing for the Dead Coast: terrain, water, landmarks, kit pieces, cover and vegetation.
## Visuals are merged into a few meshes (vertex colours + one kit batch + MultiMesh vegetation);
## colliders are plain boxes. Every placement is recorded with the reason it exists.

const RUST: Color = Color(0.5, 0.26, 0.17)
const RUST_DARK: Color = Color(0.33, 0.19, 0.14)
const HULL_BLUE: Color = Color(0.2, 0.3, 0.34)
const BONE: Color = Color(0.74, 0.7, 0.6)
const STEEL: Color = Color(0.3, 0.33, 0.33)
const WOOD: Color = Color(0.4, 0.29, 0.19)
const WOOD_GREY: Color = Color(0.5, 0.46, 0.4)
const CONCRETE: Color = Color(0.45, 0.44, 0.4)

var root: Node3D
var b: ArenaDecor.Builder = ArenaDecor.Builder.new()
var batch: OutpostKit.Batch = OutpostKit.Batch.new()
## One record per placed thing: {kind, name, pos, radius, why, solid}
var placed: Array[Dictionary] = []
var _vegetation_density: float = 1.0


func _init(parent: Node3D, vegetation_density: float = 1.0) -> void:
	root = parent
	_vegetation_density = vegetation_density


# --- primitives ---------------------------------------------------------------

func collider(name: String, center: Vector3, size: Vector3, yaw: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	body.rotation.y = yaw
	root.add_child(body)
	return body


## A visible and solid box (centre y is the box centre). `why` documents the storytelling or gameplay purpose.
func solid(name: String, center: Vector3, size: Vector3, color: Color, yaw: float = 0.0, why: String = "") -> void:
	b.box(center, size, color, Basis(Vector3.UP, yaw))
	collider(name, center, size, yaw)
	placed.append({"kind": "solid", "name": name, "pos": center, "radius": maxf(size.x, size.z) * 0.5, "why": why, "solid": true,
		"center": center, "half": Vector2(size.x, size.z) * 0.5, "yaw": yaw})


func decor_box(center: Vector3, size: Vector3, color: Color, yaw: float = 0.0) -> void:
	b.box(center, size, color, Basis(Vector3.UP, yaw))


## A kit GLB piece merged into the batch, with an AABB collider when `collide` is set.
func kit(piece: String, pos: Vector3, yaw: float = 0.0, scale: float = 1.0, collide: bool = true, why: String = "") -> void:
	var mesh := OutpostKit.mesh_of(piece)
	if mesh == null:
		return
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
	if not batch.add(piece, Transform3D(basis, pos)):
		return
	var aabb := mesh.get_aabb()
	var size := aabb.size * scale
	var radius := maxf(size.x, size.z) * 0.5
	if collide:
		var center := pos + Basis(Vector3.UP, yaw) * (aabb.get_center() * scale)
		collider("Kit_" + piece, center, Vector3(maxf(size.x, 0.3), maxf(size.y, 0.3), maxf(size.z, 0.3)), yaw)
	var fp_center := pos + Basis(Vector3.UP, yaw) * (aabb.get_center() * scale)
	placed.append({"kind": "kit", "name": piece, "pos": pos, "radius": radius, "why": why, "solid": collide,
		"center": fp_center, "half": Vector2(maxf(size.x, 0.3), maxf(size.z, 0.3)) * 0.5, "yaw": yaw})


# --- terrain and water --------------------------------------------------------

func build_terrain() -> void:
	var mesh := DeadCoastTerrain.build_mesh()
	var node := MeshInstance3D.new()
	node.name = "Terrain"
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	root.add_child(body)
	# Water: one teal plane just below the foam line, plus a collision ribbon at the shore.
	var water := MeshInstance3D.new()
	water.name = "Sea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(420.0, 340.0)
	water.mesh = plane
	water.position = Vector3(-190.0, DeadCoastTerrain.SEA_LEVEL, -100.0)
	var sea := StandardMaterial3D.new()
	sea.albedo_color = Color(0.1, 0.52, 0.58)
	sea.roughness = 0.12
	sea.metallic_specular = 0.9
	water.material_override = sea
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(water)
	var wall_index := 0
	for seg: Dictionary in DeadCoastTerrain.shore_wall_positions():
		collider("ShoreWall%d" % wall_index, seg["center"], Vector3(1.0, 6.0, seg["length"]), seg["yaw"])
		wall_index += 1


# --- finishing ---------------------------------------------------------------

func finish() -> void:
	var statics := MeshInstance3D.new()
	statics.name = "Statics"
	statics.mesh = b.finish()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	statics.material_override = material
	statics.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(statics)
	var kit_mesh := batch.finish()
	if kit_mesh != null:
		var kit_node := MeshInstance3D.new()
		kit_node.name = "KitPieces"
		kit_node.mesh = kit_mesh
		kit_node.material_override = OutpostKit.material()
		kit_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(kit_node)


# --- landmarks ----------------------------------------------------------------

## The freighter that broke its back on the beach. Long axis along z; the inland wall has a breach.
func freighter(d: float, z: float) -> void:
	var base := DeadCoastTerrain.ground(d, z)
	var y := base.y
	var c := Vector3(base.x, y, base.z)
	decor_box(c + Vector3(0.0, 0.06, 0.0), Vector3(9.0, 0.12, 30.0), RUST_DARK)  # deck plate only: no step at the breach
	solid("HullPort", c + Vector3(-4.2, 3.0, 0.0), Vector3(0.7, 5.0, 30.0), HULL_BLUE, 0.0, "freighter port side")
	solid("HullStarN", c + Vector3(4.2, 3.0, -9.0), Vector3(0.7, 5.0, 12.0), RUST, 0.0, "starboard wall north of the breach")
	solid("HullStarS", c + Vector3(4.2, 3.0, 9.0), Vector3(0.7, 5.0, 12.0), RUST, 0.0, "starboard wall south of the breach")
	solid("HullBow", c + Vector3(0.0, 3.0, 14.6), Vector3(9.0, 5.0, 0.8), HULL_BLUE, 0.0, "bow bulkhead, the ship's nose points at the sea")
	solid("HullStern", c + Vector3(0.0, 3.0, -14.6), Vector3(9.0, 5.0, 0.8), RUST, 0.0, "stern bulkhead")
	solid("Bridge", c + Vector3(0.0, 6.2, 8.0), Vector3(7.0, 2.6, 7.0), BONE, 0.0, "bridge deckhouse, windows blown out")
	decor_box(c + Vector3(0.0, 4.4, 8.0), Vector3(7.4, 0.3, 7.4), RUST_DARK)
	decor_box(c + Vector3(-1.5, 8.2, 8.0), Vector3(0.5, 3.2, 0.5), STEEL)  # funnel stump
	solid("CargoCrate1", c + Vector3(-2.0, 1.4, -6.0), Vector3(2.0, 1.8, 2.0), WOOD_GREY, 0.2, "sealed crates still in the hold: stencilled, unopened")
	solid("CargoCrate2", c + Vector3(1.8, 1.4, -10.0), Vector3(2.2, 1.8, 2.2), WOOD_GREY, -0.3, "second sealed crate")


func crane(d: float, z: float) -> void:
	var p := DeadCoastTerrain.ground(d, z)
	for sx in [-2.2, 2.2]:
		solid("CraneLeg%d" % int(sx * 10), p + Vector3(float(sx), 6.0, 0.0), Vector3(0.6, 12.0, 0.6), STEEL, 0.0, "dock crane leg")
	decor_box(p + Vector3(0.0, 12.2, 0.0), Vector3(5.4, 0.6, 0.8), RUST)
	decor_box(p + Vector3(-5.5, 12.6, 0.0), Vector3(12.0, 0.5, 0.5), STEEL)  # jib out over the water
	decor_box(p + Vector3(-9.0, 9.0, 0.0), Vector3(0.12, 7.0, 0.12), STEEL)  # hanging cable
	for i in 3:
		decor_box(p + Vector3(0.0, 2.0 + i * 3.4, 0.0), Vector3(4.4, 0.25, 0.25), STEEL, 0.0)
	placed.append({"kind": "landmark", "name": "crane", "pos": p, "radius": 3.0, "why": "dock crane skeleton: the cove was a loading point", "solid": true})


func lighthouse(d: float, z: float) -> void:
	var p := DeadCoastTerrain.ground(d, z)
	b.prism(p, 3.2, 2.2, 9.0, 10, BONE, Basis.IDENTITY, WOOD_GREY)
	b.prism(p + Vector3(0.0, 9.0, 0.0), 2.6, 2.6, 0.5, 10, STEEL)
	collider("LighthouseBody", p + Vector3(0.0, 4.5, 0.0), Vector3(5.2, 9.0, 5.2))
	placed.append({"kind": "landmark", "name": "lighthouse", "pos": p, "radius": 3.2, "why": "lighthouse stub: the watch post that saw the shipment pass", "solid": true})


func pier(d: float, z: float, length: float) -> void:
	var p := DeadCoastTerrain.ground(d, z)
	for i in int(length / 3.0):
		var x := p.x - 1.5 - i * 3.0
		decor_box(Vector3(x, 0.15, p.z), Vector3(2.8, 0.2, 2.4), WOOD)
		for sz in [-1.1, 1.1]:
			decor_box(Vector3(x, -1.2, p.z + float(sz)), Vector3(0.25, 3.0, 0.25), WOOD_GREY)
	placed.append({"kind": "landmark", "name": "pier", "pos": p, "radius": 2.0, "why": "smugglers' pier, planks half rotted", "solid": false})


# --- vegetation ---------------------------------------------------------------

## Palms, bushes and rocks as MultiMeshes in 60 m cells: at most a handful of draw calls.
func scatter(path_points: Array[Vector3], seed_value: int = 20261107) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var species: Dictionary = {"palm_a": [], "palm_b": [], "bush": [], "rocks_a": [], "rocks_b": [], "rocks_c": []}
	var z := DeadCoastTerrain.Z_MAX - 6.0
	while z > DeadCoastTerrain.Z_MIN + 8.0:
		var tries := int(round(5.0 * _vegetation_density))
		for i in tries:
			var kind := rng.randi_range(0, 9)
			var d := rng.randf_range(6.0, 33.0) if kind < 7 else rng.randf_range(24.0, 33.0)
			var zz := z + rng.randf_range(-3.0, 3.0)
			var pos := DeadCoastTerrain.ground(d, zz)
			if not _free_for_scatter(pos, path_points):
				continue
			var yaw := rng.randf() * TAU
			var s := rng.randf_range(0.8, 1.35)
			var transform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos)
			var key := "palm_a"
			if kind < 2:
				key = "palm_a"
			elif kind < 3:
				key = "palm_b"
			elif kind < 6:
				key = "bush"
			else:
				key = ["rocks_a", "rocks_b", "rocks_c"][rng.randi_range(0, 2)]
			(species[key] as Array).append(transform)
		z -= 6.0
	for key: String in species:
		var xforms: Array[Transform3D] = []
		for t in species[key]:
			xforms.append(t)
		var node := OutpostKit.multimesh(key, xforms)
		if node == null:
			continue
		node.name = "Scatter_" + key
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = 90.0
		node.visibility_range_end_margin = 10.0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(node)
		placed.append({"kind": "scatter", "name": key, "pos": Vector3.ZERO, "radius": 0.0, "why": "%d instances" % xforms.size(), "solid": false})
	# Palms get a trunk collider so they cannot be walked through where they stand close to the trail.
	for t in species["palm_a"] + species["palm_b"]:
		var t3: Transform3D = t
		if _min_path_distance(t3.origin, path_points) < 9.0:
			collider("PalmTrunk", t3.origin + Vector3(0.0, 1.5, 0.0), Vector3(0.5, 3.0, 0.5))


func _free_for_scatter(pos: Vector3, path_points: Array[Vector3]) -> bool:
	if _min_path_distance(pos, path_points) < 4.5:
		return false
	if DeadCoastTerrain.inland_distance(pos.x, pos.z) < 5.0:
		return false
	for record in placed:
		if record["kind"] == "scatter":
			continue
		if Vector2(pos.x, pos.z).distance_to(Vector2((record["pos"] as Vector3).x, (record["pos"] as Vector3).z)) < float(record["radius"]) + 2.0:
			return false
	# Not on steep ground (cliff faces get rocks only through the terrain colours).
	return pos.y < 2.5 or DeadCoastTerrain.inland_distance(pos.x, pos.z) < 34.0 and pos.y < 3.0


static func _min_path_distance(pos: Vector3, points: Array[Vector3]) -> float:
	var best := INF
	for p in points:
		best = minf(best, Vector2(pos.x, pos.z).distance_to(Vector2(p.x, p.z)))
	return best
