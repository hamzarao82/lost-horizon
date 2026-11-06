class_name VegetationScatter
extends RefCounted
## Dense tropical ground cover and a few story clusters around Outpost 17.
##
## Placement (generate) is pure and seeded so tests can check it without scenes. Build turns the
## transforms into MultiMeshes split into 50 m cells: one cell is one draw call per species, and
## visibility ranges only mean something per cell, not for one giant mesh.

const SEED: int = 1705
const CELL: float = 50.0
const BOUNDS: Rect2 = Rect2(-95.0, -120.0, 190.0, 220.0)
const WATER_LEVEL: float = -0.85
const EDGE_MARGIN: float = 4.0

## Walkable footprints (x, z, width, depth) widened by EDGE_MARGIN: no plants inside these.
const WALKABLE: Array[Rect2] = [
	Rect2(-42.0, 30.0, 84.0, 50.0),   # area A: beach (its flanks are handled by BEACH_FLANKS)
	Rect2(-30.0, -30.0, 60.0, 60.0),  # area B: courtyard
	Rect2(-22.5, -92.0, 45.0, 62.0),  # areas C and D
]
## Beach flanks the player can see but does not need: plants allowed here between |x| 16 and 46.
const BEACH_FLANKS_X: Vector2 = Vector2(16.0, 46.0)
const BEACH_FLANKS_Z: Vector2 = Vector2(42.0, 78.0)
## Points of interest that stay clear (centre x, z, radius): checkpoint desk, wreck, spawn, boss arena.
const KEEP_CLEAR: Array[Vector3] = [
	Vector3(6.5, 36.0, 12.0), Vector3(-12.0, 38.0, 10.0), Vector3(0.0, 0.0, 6.0), Vector3(0.0, -81.0, 16.0),
]

const SPECIES: Dictionary = {
	"palm_a": {"count": 40, "scale": Vector2(0.8, 1.1)},
	"palm_b": {"count": 40, "scale": Vector2(0.8, 1.1)},
	"bush": {"count": 110, "scale": Vector2(0.9, 1.6)},
	"rocks_a": {"count": 30, "scale": Vector2(0.5, 1.2)},
	"rocks_b": {"count": 30, "scale": Vector2(0.5, 1.2)},
}

const PROPS_DIR: String = "res://assets/environments/props_new/"


static func is_allowed(p: Vector2, height_fn: Callable = Callable()) -> bool:
	if not BOUNDS.has_point(p):
		return false
	for c in KEEP_CLEAR:
		if p.distance_to(Vector2(c.x, c.y)) < c.z:
			return false
	var flank := absf(p.x) >= BEACH_FLANKS_X.x and absf(p.x) <= BEACH_FLANKS_X.y \
			and p.y >= BEACH_FLANKS_Z.x and p.y <= BEACH_FLANKS_Z.y
	if not flank:
		for r in WALKABLE:
			if r.grow(EDGE_MARGIN).has_point(p):
				return false
	if height_fn.is_valid() and float(height_fn.call(p.x, p.y)) < WATER_LEVEL:
		return false
	return true


## species name -> Array[Transform3D]. density scales the counts (1.0 high, 0.7 medium, 0.4 low).
static func generate(density: float, height_fn: Callable = Callable(), seed_value: int = SEED) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Dictionary = {}
	for species: String in SPECIES:
		var info: Dictionary = SPECIES[species]
		var scale_range: Vector2 = info["scale"]
		var wanted := int(round(float(info["count"]) * density))
		var list: Array[Transform3D] = []
		var attempts := 0
		while list.size() < wanted and attempts < wanted * 60:
			attempts += 1
			var p := Vector2(rng.randf_range(BOUNDS.position.x, BOUNDS.end.x), rng.randf_range(BOUNDS.position.y, BOUNDS.end.y))
			if not is_allowed(p, height_fn):
				continue
			var y := float(height_fn.call(p.x, p.y)) if height_fn.is_valid() else 0.0
			var tilt := Basis(Vector3.RIGHT, rng.randf_range(-0.06, 0.06)) * Basis(Vector3.BACK, rng.randf_range(-0.06, 0.06))
			var basis := Basis(Vector3.UP, rng.randf() * TAU) * tilt
			basis = basis.scaled(Vector3.ONE * rng.randf_range(scale_range.x, scale_range.y))
			list.append(Transform3D(basis, Vector3(p.x, y, p.y)))
		result[species] = list
	return result


## One MultiMeshInstance3D per species and 40 m cell. Returns nodes for the caller to add and track.
static func build(density: float, height_fn: Callable, view_range: float) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	var placed := generate(density, height_fn)
	for species: String in placed:
		if not OutpostKit.has_piece(species):
			continue
		var cells: Dictionary = {}
		for xf: Transform3D in placed[species]:
			var key := Vector2i(floori(xf.origin.x / CELL), floori(xf.origin.z / CELL))
			if not cells.has(key):
				cells[key] = [] as Array[Transform3D]
			(cells[key] as Array[Transform3D]).append(xf)
		for key: Vector2i in cells:
			var centre := Vector3((key.x + 0.5) * CELL, 0.0, (key.y + 0.5) * CELL)
			var local: Array[Transform3D] = []
			for xf: Transform3D in cells[key]:
				local.append(Transform3D(xf.basis, xf.origin - centre))
			var node := OutpostKit.multimesh(species, local)
			if node == null:
				continue
			node.position = centre  # the engine measures view range from the node, so each cell sits at its centre
			node.name = "%s_%d_%d" % [species, key.x, key.y]
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_end = view_range + CELL * 0.5  # the cell centre is what the engine measures
			node.visibility_range_end_margin = 8.0
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			nodes.append(node)
	return nodes


## Story clusters beside the beach flank. Each entry: scene, position (x, z), yaw, scale, why it is there.
const CLUSTERS: Array[Dictionary] = [
	{"kit": "truck_wreck", "pos": Vector2(-28.0, 56.0), "yaw": 0.4, "s": 1.0,
		"why": "the patrol truck, abandoned on the beach track when the radio went silent"},
	{"kit": "radio_mast", "pos": Vector2(-36.0, 66.0), "yaw": 0.0, "s": 1.0,
		"why": "the dead relay that should have called for help"},
	{"prop": "wooden_crate_01", "pos": Vector2(20.0, 50.0), "yaw": 0.3, "s": 1.0,
		"why": "supply crates left at the gate when the garrison pulled out"},
	{"prop": "wooden_crate_02", "pos": Vector2(21.5, 51.8), "yaw": -0.5, "s": 1.0, "why": "same supply stack"},
	{"prop": "barrel_03", "pos": Vector2(18.5, 52.0), "yaw": 0.0, "s": 1.0, "why": "same supply stack"},
	{"prop": "barrel_01", "pos": Vector2(23.2, 49.4), "yaw": 1.0, "s": 1.0, "why": "same supply stack"},
	{"kit": "barricade_wire", "pos": Vector2(-20.0, 46.0), "yaw": 1.5708, "s": 1.0,
		"why": "the improvised line the soldiers set up facing the water"},
	{"kit": "barricade_wire", "pos": Vector2(-20.0, 51.0), "yaw": 1.5708, "s": 1.0, "why": "same barricade line"},
	{"camera": "security_camera_02", "pos": Vector2(30.0, 44.0), "yaw": 3.6, "s": 2.4,
		"why": "a camera still watching the approach, scaled up so it reads from the gate"},
]


static func cluster_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for c in CLUSTERS:
		out.append(c["pos"])
	return out


static func build_clusters(height_fn: Callable) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	for c in CLUSTERS:
		var pos: Vector2 = c["pos"]
		var y := float(height_fn.call(pos.x, pos.y)) if height_fn.is_valid() else 0.0
		var xf := Transform3D(Basis(Vector3.UP, float(c["yaw"])).scaled(Vector3.ONE * float(c["s"])), Vector3(pos.x, y, pos.y))
		var node: Node3D = null
		if c.has("kit") and OutpostKit.has_piece(String(c["kit"])):
			node = OutpostKit.instance(String(c["kit"]), xf)
		elif c.has("prop") or c.has("camera"):
			var file := String(c.get("prop", c.get("camera", "")))
			var path := PROPS_DIR + file + ".glb"
			if ResourceLoader.exists(path):
				node = (load(path) as PackedScene).instantiate() as Node3D
				node.transform = xf
		if node == null:
			continue
		node.name = "Story_%d_%s" % [nodes.size(), String(c.get("kit", c.get("prop", c.get("camera", "x"))))]
		_cheap(node)
		nodes.append(node)
		if c.has("camera"):  # post for the camera
			var post := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.07
			cyl.bottom_radius = 0.09
			cyl.height = 3.2
			cyl.radial_segments = 8
			post.mesh = cyl
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.22, 0.23, 0.22)
			mat.roughness = 0.8
			post.material_override = mat
			post.position = Vector3(pos.x, y + 1.6, pos.y)
			nodes.append(post)
			node.position.y = y + 3.2
	return nodes


## Story props are small: no shadow pass and a view range keep them to a few draw calls near the player.
static func _cheap(node: Node3D) -> void:
	var list: Array = node.find_children("*", "GeometryInstance3D", true, false)
	if node is GeometryInstance3D:
		list.append(node)
	for g: GeometryInstance3D in list:
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visibility_range_end = 70.0
