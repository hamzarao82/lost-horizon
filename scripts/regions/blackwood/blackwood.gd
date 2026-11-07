class_name Blackwood
extends Node3D
## Region content: Blackwood, a dense, dark jungle with a hidden military research site at its end.
## Self-contained: build() creates the ground, trail, vegetation, structures, interactables, encounters
## and registers the three quests. The region framework only needs entry_points / exit_points,
## capture_state / restore_state and the metadata below. See docs/BLACKWOOD.md.
##
## Local frame: the player arrives near (0, 0, 12) and the route runs towards -Z for about 270 m.
## Flag ids use `blackwood_<id>` (WorldState only keeps a-z, 0-9 and _ up to 48 characters).

signal built

const REGION_ID: StringName = &"blackwood"
const AMBIENCE_NAME: String = "blackwood"
const ACCESS_FLAG: StringName = &"blackwood_research_complex_access"
const LAYER_WORLD: int = 1

## id, trigger area id, centre (x, z), size (x, z), label.
const AREAS: Array[Dictionary] = [
	{"id": "jungle_entrance", "area": &"blackwood_jungle_entrance", "c": Vector2(0.0, 0.0), "size": Vector2(36.0, 30.0), "label": "Jungle Entrance"},
	{"id": "trail", "area": &"blackwood_trail", "c": Vector2(-4.0, -42.0), "size": Vector2(24.0, 36.0), "label": "Overgrown Military Trail"},
	{"id": "patrol_camp", "area": &"blackwood_patrol_camp", "c": Vector2(-30.0, -100.0), "size": Vector2(34.0, 30.0), "label": "Abandoned Patrol Camp"},
	{"id": "research_perimeter", "area": &"blackwood_research_perimeter", "c": Vector2(-10.0, -165.0), "size": Vector2(44.0, 36.0), "label": "Research Perimeter"},
	{"id": "comms_station", "area": &"blackwood_comms_station", "c": Vector2(32.0, -138.0), "size": Vector2(24.0, 22.0), "label": "Hidden Communications Station"},
	{"id": "testing_site", "area": &"blackwood_testing_site", "c": Vector2(-10.0, -215.0), "size": Vector2(52.0, 44.0), "label": "Experimental Testing Site"},
	{"id": "facility_entrance", "area": &"blackwood_facility_entrance", "c": Vector2(-10.0, -258.0), "size": Vector2(30.0, 20.0), "label": "Research Facility Entrance"},
]

## Trails as polylines (x, z). The branch to the comms station is deliberately narrower and unmarked.
const TRAIL_MAIN: Array[Vector2] = [
	Vector2(0.0, 14.0), Vector2(0.0, -30.0), Vector2(-12.0, -55.0), Vector2(-24.0, -80.0), Vector2(-30.0, -100.0),
	Vector2(-24.0, -122.0), Vector2(-14.0, -145.0), Vector2(-10.0, -165.0), Vector2(-10.0, -185.0),
	Vector2(-10.0, -215.0), Vector2(-10.0, -250.0),
]
const TRAIL_BRANCH: Array[Vector2] = [Vector2(-22.0, -124.0), Vector2(6.0, -132.0), Vector2(30.0, -138.0)]
const BOUNDS: Rect2 = Rect2(-70.0, -280.0, 140.0, 320.0)
const GATE_Z: float = -185.0
const GATE_X: float = -10.0

## Route waypoints the connectivity test walks (the gate must be open for the last leg).
const ROUTE: Array[Vector2] = [
	Vector2(0.0, 12.0), Vector2(0.0, -30.0), Vector2(-12.0, -55.0), Vector2(-24.0, -80.0), Vector2(-30.0, -100.0),
	Vector2(-24.0, -122.0), Vector2(-14.0, -145.0), Vector2(-10.0, -165.0), Vector2(-10.0, -184.0),
	Vector2(-10.0, -190.0), Vector2(-10.0, -215.0), Vector2(-10.0, -250.0),
]
const BRANCH_ROUTE: Array[Vector2] = [Vector2(-22.0, -124.0), Vector2(6.0, -132.0), Vector2(30.0, -138.0)]

const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const HUNTER: String = "res://scenes/enemies/HunterElite.tscn"
const HEAVY: String = "res://scenes/enemies/HeavySoldier.tscn"

## The region's mood for the framework (applied by apply_environment). Fog stays light so the trail reads.
const ENVIRONMENT: Dictionary = {
	"fog_color": Color(0.1, 0.17, 0.13), "fog_density": 0.012, "ambient_color": Color(0.35, 0.46, 0.4),
	"ambient_energy": 0.85, "tonemap_exposure": 1.05,
}
const MIN_TRAIL_LUMINANCE: float = 0.07

var region_id: StringName = REGION_ID
var ambience_name: String = AMBIENCE_NAME
## Where the player appears: arriving from Dead Coast, or coming back up the hatch.
var entry_points: Dictionary = {
	&"from_dead_coast": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, 12.0)),
	&"from_underground": Transform3D(Basis.IDENTITY, Vector3(14.0, 0.1, -222.0)),
}
## Exit id -> {"position": Vector3, "to": region id, "requires_flag": StringName}.
var exit_points: Dictionary = {
	&"to_dead_coast": {"position": Vector3(0.0, 0.0, 18.0), "to": &"dead_coast", "requires_flag": &""},
	&"to_research_complex": {"position": Vector3(-10.0, 0.0, -266.0), "to": &"research_complex", "requires_flag": ACCESS_FLAG},
}

@export var auto_build: bool = true
## 1.0 high, 0.7 medium, 0.4 low (mobile/web); scales the vegetation.
@export var density: float = 1.0
@export var view_range: float = 60.0

var puzzle: FrequencyPuzzle
var encounters: Dictionary = {}
var patrol: PatrolGroup
var gate_body: StaticBody3D
var gate_mesh: MeshInstance3D
var is_built: bool = false

var _structures: MeshBuilder
var _glow: MeshBuilder
var _gate_open: bool = false
var _hatch: Interactable


# --- static data helpers (pure, used by tests) -----------------------------

static func area_ids() -> Array[String]:
	var ids: Array[String] = []
	for a in AREAS:
		ids.append(String(a["id"]))
	return ids


static func area_rect(area: Dictionary) -> Rect2:
	var c: Vector2 = area["c"]
	var s: Vector2 = area["size"]
	return Rect2(c - s * 0.5, s)


static func dist_to_polyline(p: Vector2, line: Array[Vector2]) -> float:
	var best := INF
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Where nothing may grow: the trail corridors, the areas and the story props.
static func is_walkable(p: Vector2, margin: float = 0.0) -> bool:
	if dist_to_polyline(p, TRAIL_MAIN) < 4.0 + margin:
		return true
	if dist_to_polyline(p, TRAIL_BRANCH) < 2.6 + margin:
		return true
	for a in AREAS:
		if area_rect(a).grow(margin).has_point(p):
			return true
	return false


static func apply_environment(world_env: WorldEnvironment) -> void:
	if world_env == null or world_env.environment == null:
		return
	var env := world_env.environment
	env.fog_enabled = true
	env.fog_light_color = ENVIRONMENT["fog_color"]
	env.fog_density = ENVIRONMENT["fog_density"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ENVIRONMENT["ambient_color"]
	env.ambient_light_energy = ENVIRONMENT["ambient_energy"]
	env.tonemap_exposure = ENVIRONMENT["tonemap_exposure"]


# --- lifecycle --------------------------------------------------------------

func _ready() -> void:
	name = "Blackwood"
	if auto_build:
		build()


## Builds everything once. Safe to call again only on a fresh node.
func build() -> void:
	if is_built:
		return
	is_built = true
	_structures = MeshBuilder.new()
	_glow = MeshBuilder.new()
	var manager := get_node_or_null("/root/QuestManager")
	BlackwoodQuests.register(manager, get_node_or_null("/root/Progression"))
	_build_ground()
	_build_bounds()
	_build_vegetation()
	_build_landmarks()
	_build_camp()
	_build_comms_station()
	_build_perimeter_and_gate()
	_build_testing_site()
	_build_facility_entrance()
	_build_triggers()
	_build_encounters()
	_finish_meshes()
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.area_entered.connect(_on_area_entered)
		_set_gate(state.has_flag(&"blackwood_gate_open"))
		state.flag_changed.connect(_on_flag_changed)
	built.emit()


func _on_area_entered(id: StringName) -> void:
	if id == &"blackwood_jungle_entrance":
		BlackwoodQuests.start_chain(get_node_or_null("/root/QuestManager"))


func _on_flag_changed(id: StringName, _value: bool) -> void:
	if id == &"blackwood_gate_open" or id == &"*":
		var state := get_node_or_null("/root/WorldState")
		_set_gate(state != null and state.has_flag(&"blackwood_gate_open"))


## Region-level save data (world flags are saved by WorldState; this is what flags cannot hold).
func capture_state() -> Dictionary:
	return {"puzzle": puzzle.capture_state() if puzzle else {}, "gate_open": _gate_open}


func restore_state(data: Variant) -> void:
	if not (data is Dictionary):
		return
	var d := data as Dictionary
	if puzzle:
		puzzle.restore_state(d.get("puzzle"))
	if d.get("gate_open") == true:
		var state := get_node_or_null("/root/WorldState")
		if state:
			state.set_flag(&"blackwood_gate_open", true)
	var state2 := get_node_or_null("/root/WorldState")
	_set_gate(state2 != null and state2.has_flag(&"blackwood_gate_open"))


func exit_locked(exit_id: StringName) -> bool:
	var info: Dictionary = exit_points.get(exit_id, {})
	var flag: StringName = info.get("requires_flag", &"")
	if flag == &"":
		return false
	var state := get_node_or_null("/root/WorldState")
	return not (state != null and state.has_flag(flag))


# --- ground, bounds ----------------------------------------------------------

func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 7.0
	var nx := int(ceil(BOUNDS.size.x / step))
	var nz := int(ceil(BOUNDS.size.y / step))
	for iz in nz:
		for ix in nx:
			var x0 := BOUNDS.position.x + ix * step
			var z0 := BOUNDS.position.y + iz * step
			var p00 := Vector3(x0, 0.0, z0)
			var p10 := Vector3(x0 + step, 0.0, z0)
			var p01 := Vector3(x0, 0.0, z0 + step)
			var p11 := Vector3(x0 + step, 0.0, z0 + step)
			var c00 := _ground_color(Vector2(p00.x, p00.z))
			var c10 := _ground_color(Vector2(p10.x, p10.z))
			var c01 := _ground_color(Vector2(p01.x, p01.z))
			var c11 := _ground_color(Vector2(p11.x, p11.z))
			for tri in [[p00, p10, p11, c00, c10, c11], [p00, p11, p01, c00, c11, c01]]:
				for i in 3:
					st.set_normal(Vector3.UP)
					st.set_color(tri[3 + i])
					st.set_uv(Vector2(tri[i].x, tri[i].z) * 0.25)
					st.add_vertex(tri[i])
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = st.commit()
	ground.material_override = _ground_material()
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BOUNDS.size.x, 2.0, BOUNDS.size.y)
	shape.shape = box
	shape.position = Vector3(BOUNDS.get_center().x, -1.0, BOUNDS.get_center().y)
	body.add_child(shape)
	add_child(body)
	_build_stream()


static func _ground_color(p: Vector2) -> Color:
	var moss := Color(0.1, 0.17, 0.08)
	var leaf := Color(0.07, 0.12, 0.06)
	var n := fposmod(sin(p.x * 0.37 + p.y * 0.21) * 43758.5453, 1.0)
	var base := moss.lerp(leaf, n)
	var dirt := Color(0.44, 0.34, 0.21)
	var d_main := dist_to_polyline(p, TRAIL_MAIN)
	var d_branch := dist_to_polyline(p, TRAIL_BRANCH)
	var t_main := 1.0 - smoothstep(2.4, 5.0, d_main)
	var t_branch := (1.0 - smoothstep(1.2, 3.0, d_branch)) * 0.6
	var t := maxf(t_main, t_branch)
	for a in AREAS:
		if area_rect(a).grow(1.0).has_point(p):
			t = maxf(t, 0.55)  # trodden clearings read as lighter ground
	return base.lerp(dirt, t)


func _ground_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var path := "res://assets/textures/pbr/Ground111/Ground111_1K-JPG_Color.jpg"
		if ResourceLoader.exists(path):
			m.albedo_texture = load(path) as Texture2D
			m.uv1_scale = Vector3(1.0, 1.0, 1.0)
	return m


func _build_stream() -> void:
	var pts: Array[Vector2] = [Vector2(-70.0, -78.0), Vector2(-50.0, -82.0), Vector2(-22.0, -92.0), Vector2(10.0, -96.0), Vector2(40.0, -92.0), Vector2(70.0, -98.0)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 2.2
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x) * half
		var q := [a + side, a - side, b - side, b + side]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(q[k].x, 0.04, q[k].y))
	var water := MeshInstance3D.new()
	water.name = "Stream"
	water.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.12, 0.3, 0.34, 0.85)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.15
	m.metallic = 0.2
	water.material_override = m
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)  # shallow: walkable, so no collider (the trail crosses it at the patrol camp)


func _build_bounds() -> void:
	var body := StaticBody3D.new()
	body.name = "JungleWall"
	body.collision_layer = LAYER_WORLD
	var walls := [
		[Vector3(BOUNDS.get_center().x, 4.0, BOUNDS.position.y - 1.0), Vector3(BOUNDS.size.x, 10.0, 2.0)],
		[Vector3(BOUNDS.get_center().x, 4.0, BOUNDS.end.y + 1.0), Vector3(BOUNDS.size.x, 10.0, 2.0)],
		[Vector3(BOUNDS.position.x - 1.0, 4.0, BOUNDS.get_center().y), Vector3(2.0, 10.0, BOUNDS.size.y)],
		[Vector3(BOUNDS.end.x + 1.0, 4.0, BOUNDS.get_center().y), Vector3(2.0, 10.0, BOUNDS.size.y)],
	]
	for w in walls:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[1]
		shape.shape = box
		shape.position = w[0]
		body.add_child(shape)
	add_child(body)


# --- vegetation (MultiMesh, seeded) ---------------------------------------------

const SPECIES: Dictionary = {
	"palm_a": {"count": 130, "scale": Vector2(1.5, 2.3)},
	"palm_b": {"count": 130, "scale": Vector2(1.4, 2.2)},
	"bush": {"count": 260, "scale": Vector2(1.3, 2.4)},
	"rocks_a": {"count": 24, "scale": Vector2(1.0, 2.2)},
	"rocks_b": {"count": 24, "scale": Vector2(1.0, 2.2)},
}
const CELL: float = 100.0
const SEED: int = 4107
## Props that must stay clear: puzzle panel, hatch, crates and documents are inside areas anyway.
const KEEP_CLEAR_MARGIN: float = 1.5


static func generate_vegetation(density_scale: float, seed_value: int = SEED) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Dictionary = {}
	for species: String in SPECIES:
		var info: Dictionary = SPECIES[species]
		var scale_range: Vector2 = info["scale"]
		var wanted := int(round(float(info["count"]) * density_scale))
		var list: Array[Transform3D] = []
		var attempts := 0
		while list.size() < wanted and attempts < wanted * 40:
			attempts += 1
			var p := Vector2(rng.randf_range(BOUNDS.position.x + 2.0, BOUNDS.end.x - 2.0), rng.randf_range(BOUNDS.position.y + 2.0, BOUNDS.end.y - 2.0))
			if is_walkable(p, KEEP_CLEAR_MARGIN):
				continue
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(scale_range.x, scale_range.y))
			list.append(Transform3D(basis, Vector3(p.x, 0.0, p.y)))
		result[species] = list
	return result


func _build_vegetation() -> void:
	var placed := generate_vegetation(density)
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
			node.position = centre
			node.name = "%s_%d_%d" % [species, key.x, key.y]
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_end = view_range + CELL * 0.5
			node.visibility_range_end_margin = 8.0
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(node)


# --- structures ---------------------------------------------------------------

## Merges boxes (position, size, colour, optional basis) into one mesh = one draw call.
class MeshBuilder:
	var st := SurfaceTool.new()
	var count: int = 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func box(center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
		count += 1
		var h := size * 0.5
		var corners: Array[Vector3] = []
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					corners.append(center + basis * Vector3(h.x * sx, h.y * sy, h.z * sz))
		# faces as corner indices (x-major order: index = x*4 + y*2 + z)
		var faces: Array = [
			[[4, 6, 7, 5], Vector3.RIGHT], [[0, 1, 3, 2], Vector3.LEFT],
			[[2, 3, 7, 6], Vector3.UP], [[0, 4, 5, 1], Vector3.DOWN],
			[[1, 5, 7, 3], Vector3.BACK], [[0, 2, 6, 4], Vector3.FORWARD],
		]
		for f in faces:
			var idx: Array = f[0]
			var normal: Vector3 = basis * (f[1] as Vector3)
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for k in tri:
					st.set_normal(normal)
					st.set_color(color)
					st.add_vertex(corners[idx[k]])

	func commit() -> ArrayMesh:
		return st.commit()


func _solid(center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_WORLD
	body.position = center
	body.basis = basis
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


## A visible and solid box.
func _block(center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
	_structures.box(center, size, color, basis)
	_solid(center, size, basis)


func _kit(piece: String, x: float, z: float, yaw: float, s: float = 1.0, solid_size: Vector3 = Vector3.ZERO) -> void:
	if not OutpostKit.has_piece(piece):
		return
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(x, 0.0, z))
	var node := OutpostKit.instance(piece, xf)
	if node == null:
		return
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 90.0
	add_child(node)
	if solid_size != Vector3.ZERO:
		_solid(Vector3(x, solid_size.y * 0.5, z), solid_size, Basis(Vector3.UP, yaw))


func _build_landmarks() -> void:
	# Entrance: two huge rocks framing the trail head and a sign post.
	_kit("rocks_c", -9.0, 4.0, 0.4, 3.2, Vector3(6.0, 3.0, 5.0))
	_kit("rocks_c", 9.5, 2.0, 2.0, 2.8, Vector3(5.0, 2.8, 4.5))
	_structures.box(Vector3(2.4, 1.2, 8.0), Vector3(0.18, 2.4, 0.18), Color(0.28, 0.2, 0.12))
	_structures.box(Vector3(2.4, 2.3, 8.0), Vector3(1.8, 0.7, 0.12), Color(0.55, 0.14, 0.1))
	# Trail lanterns: amber posts every ~12 m on the main trail (one merged emissive mesh).
	var along := 0.0
	for i in TRAIL_MAIN.size() - 1:
		var a := TRAIL_MAIN[i]
		var b := TRAIL_MAIN[i + 1]
		var seg := a.distance_to(b)
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var d := 6.0
		while d < seg:
			var p := a + dir * d + side * 4.2 * (1.0 if int((along + d) / 12.0) % 2 == 0 else -1.0)
			_glow.box(Vector3(p.x, 1.5, p.y), Vector3(0.16, 0.28, 0.16), Color(1.0, 0.7, 0.28))
			_structures.box(Vector3(p.x, 0.7, p.y), Vector3(0.1, 1.4, 0.1), Color(0.18, 0.14, 0.1))
			d += 12.0
		along += seg
	# Observation platform with a ramp (vertical variation and a view over the trail).
	_block(Vector3(-46.0, 1.1, -68.0), Vector3(9.0, 2.2, 9.0), Color(0.26, 0.2, 0.14))
	var ramp_angle := atan2(2.2, 8.0)
	_block(Vector3(-46.0, 1.1, -59.4), Vector3(3.2, 0.3, 8.4), Color(0.3, 0.23, 0.16), Basis(Vector3.RIGHT, -ramp_angle))
	# Watchtowers at the perimeter.
	_kit("watchtower", 24.0, -170.0, 0.4, 1.0, Vector3(3.4, 7.0, 3.4))
	_kit("watchtower", -36.0, -200.0, -0.3, 1.0, Vector3(3.4, 7.0, 3.4))
	# Big rocks along the trail, outside the corridor.
	_kit("rocks_b", 12.0, -30.0, 1.0, 2.6, Vector3(5.0, 2.4, 4.0))
	_kit("rocks_a", -36.0, -112.0, 0.3, 2.4, Vector3(4.5, 2.2, 4.0))


func _build_camp() -> void:
	var c := Vector2(-30.0, -100.0)
	_kit("tent", c.x - 9.0, c.y - 5.0, 0.3, 1.0, Vector3(4.0, 2.2, 5.0))
	_kit("tent", c.x - 8.0, c.y + 6.0, -0.4, 1.0, Vector3(4.0, 2.2, 5.0))
	_kit("tent", c.x + 9.0, c.y - 6.0, 2.8, 1.0, Vector3(4.0, 2.2, 5.0))
	_kit("sandbag_stack", c.x + 8.0, c.y + 7.0, 0.2, 1.0, Vector3(3.0, 1.0, 1.2))
	_kit("barricade_wire", c.x - 9.0, c.y - 13.0, 1.57, 1.0, Vector3(1.0, 1.4, 5.0))
	_kit("truck_wreck", c.x - 12.0, c.y + 12.0, 0.9, 0.9, Vector3(5.0, 2.2, 8.0))
	# Cold fire pit and a toppled radio table.
	_structures.box(Vector3(c.x, 0.1, c.y), Vector3(1.6, 0.2, 1.6), Color(0.08, 0.07, 0.06))
	_block(Vector3(c.x + 3.0, 0.5, c.y + 2.0), Vector3(1.6, 1.0, 0.8), Color(0.25, 0.22, 0.16))
	var gear := Interactable.new()
	gear.interaction_id = &"bw_patrol_gear"
	gear.prompt_text = "Search abandoned patrol gear"
	gear.position = Vector3(-6.0, 0.6, -46.0)
	add_child(gear)
	_block(Vector3(-6.0, 0.2, -46.0), Vector3(1.0, 0.4, 1.4), Color(0.2, 0.24, 0.16))
	gear.interacted.connect(func(_p: Node3D) -> void:
		Outpost17.say(self, "A rifle with no bolt, a torn pack, a radio with its antenna cut clean through.", 5.0))
	_add_checkpoint(&"blackwood_camp", Vector3(c.x + 4.0, 0.0, c.y - 3.0))
	_add_crate(&"blackwood_crate_camp", Vector3(c.x - 3.0, 0.0, c.y - 8.0), ["bandage", "scrap_metal"], false)
	_add_doc(&"bw_log_patrol_1", "Sergeant's log", Vector3(c.x - 5.0, 0.0, c.y + 1.0),
			"Day 6. Orders unchanged: escort the covered trucks to the perimeter and ask nothing. The drivers will not say what is in them. The radio has been dropping out since the second night.")
	_add_doc(&"bw_log_patrol_2", "Torn page", Vector3(c.x + 6.0, 0.0, c.y + 4.0),
			"Somebody cut our line on purpose. Private Okoro says the animals went quiet before the first shot was fired. We are leaving the camp as it is and going on foot to the perimeter. If you find this, do not take the main gate.")


func _build_comms_station() -> void:
	var c := Vector2(32.0, -138.0)
	_kit("hut_olive", c.x + 6.0, c.y - 5.0, 3.14, 1.0, Vector3(5.0, 3.0, 4.0))
	_kit("radio_mast", c.x - 7.0, c.y + 5.0, 0.0, 1.2, Vector3(1.0, 8.0, 1.0))
	_kit("generator", c.x + 4.0, c.y + 6.0, 0.3, 1.0, Vector3(2.0, 1.4, 1.2))
	_structures.box(Vector3(c.x - 7.0, 4.0, c.y + 5.0), Vector3(0.08, 8.0, 0.08), Color(0.3, 0.3, 0.3))
	# Frequency puzzle panel facing the trail.
	puzzle = FrequencyPuzzle.new()
	puzzle.name = "FrequencyPuzzle"
	puzzle.position = Vector3(c.x - 2.0, 0.0, c.y + 1.0)
	add_child(puzzle)
	_solid(Vector3(c.x - 2.0, 1.1, c.y + 0.9), Vector3(3.2, 2.2, 0.5))
	_add_doc(&"bw_log_frequency", "Technician's frequency log", Vector3(c.x - 5.5, 0.0, c.y + 3.0),
			"Station log. If the board dies, bring it back on channel %s: dial one to four, dial two to one, dial three to seven, then pull the lever. Anything else only scrambles the dials. Do not leave it on the air longer than a minute. They listen." % FrequencyPuzzle.code_text())
	_add_doc(&"bw_log_tech_notes", "Technician's notes", Vector3(c.x + 1.0, 0.0, c.y - 3.0),
			"Every night at the same minute the receiver picks up a count in a flat voice, then a short tone. It is not one of ours. I stopped logging it after I recognised the numbers as grid squares on the research site map.")
	var transmissions := Terminal.new()
	transmissions.interaction_id = &"bw_transmissions"
	transmissions.terminal_title = "Receiver"
	transmissions.requires_flag = FrequencyPuzzle.SOLVED_FLAG
	transmissions.finish_flag = &"blackwood_transmissions_read"
	transmissions.locked_text = "Receiver: no power (tune the station first)"
	transmissions.pages = PackedStringArray([
		"Decoded: 'Shipment received at the perimeter. Subjects stable. The coast route stays closed.'",
		"Decoded: 'Gate panel code is the grid square of the covered truck: B-7. Do not repeat on open channels.'"])
	transmissions.position = Vector3(c.x + 2.0, 0.6, c.y + 2.0)
	add_child(transmissions)
	_block(Vector3(c.x + 2.0, 0.4, c.y + 2.2), Vector3(1.4, 0.8, 0.8), Color(0.22, 0.24, 0.22))
	var recorder := Terminal.new()
	recorder.interaction_id = &"bw_data_recorder"
	recorder.terminal_title = "Data recorder"
	recorder.requires_flag = FrequencyPuzzle.SOLVED_FLAG
	recorder.finish_flag = &"blackwood_black_site_link"
	recorder.locked_text = "Data recorder: no power"
	recorder.pages = PackedStringArray([
		"Recovered file header: PROJECT BLACK SITE, Field Programme, Blackwood annex.",
		"Summary: 'Phase two selection complete. Transfers from the coast hospital arrive by truck. The annex is not on any map.'"])
	recorder.position = Vector3(c.x + 4.2, 0.6, c.y - 2.0)
	add_child(recorder)
	_block(Vector3(c.x + 4.2, 0.4, c.y - 1.8), Vector3(1.0, 0.8, 0.8), Color(0.2, 0.22, 0.25))
	_add_crate(&"blackwood_crate_station", Vector3(c.x + 8.0, 0.0, c.y + 6.0), ["armor_plate"], true)


func _build_perimeter_and_gate() -> void:
	var c := Vector2(-10.0, -165.0)
	# The fence line with the concealed gate at its centre (vine-coloured, no obvious door).
	var fence_color := Color(0.15, 0.2, 0.15)
	_block(Vector3(-41.5, 1.6, GATE_Z), Vector3(57.0, 3.2, 0.3), fence_color)  # x -70 .. -13
	_block(Vector3(31.5, 1.6, GATE_Z), Vector3(77.0, 3.2, 0.3), fence_color)  # x -7 .. 70
	gate_mesh = MeshInstance3D.new()
	var gate_box := BoxMesh.new()
	gate_box.size = Vector3(6.0, 3.2, 0.5)
	gate_mesh.mesh = gate_box
	gate_mesh.position = Vector3(GATE_X, 1.6, GATE_Z)
	var gate_mat := StandardMaterial3D.new()
	gate_mat.albedo_color = Color(0.12, 0.2, 0.12)
	gate_mat.roughness = 1.0
	gate_mesh.material_override = gate_mat
	add_child(gate_mesh)
	gate_body = StaticBody3D.new()
	gate_body.collision_layer = LAYER_WORLD
	gate_body.position = gate_mesh.position
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(6.0, 3.2, 0.5)
	gs.shape = gb
	gate_body.add_child(gs)
	add_child(gate_body)
	# Access panel beside the gate: needs the grid code from the station's transmissions.
	var panel := Terminal.new()
	panel.interaction_id = &"bw_gate_panel"
	panel.terminal_title = "Gate panel"
	panel.requires_flag = &"blackwood_transmissions_read"
	panel.finish_flag = &"blackwood_gate_open"
	panel.locked_text = "Gate panel: needs an access grid (the station's transmissions)"
	panel.pages = PackedStringArray(["Grid B-7 accepted. The vine-covered section of the wall slides open."])
	panel.position = Vector3(GATE_X + 4.5, 1.0, GATE_Z + 1.0)
	add_child(panel)
	_block(Vector3(GATE_X + 4.5, 0.6, GATE_Z + 0.9), Vector3(0.7, 1.2, 0.4), Color(0.18, 0.2, 0.22))
	_add_checkpoint(&"blackwood_perimeter", Vector3(c.x + 8.0, 0.0, c.y + 8.0))
	_add_doc(&"bw_log_director_note", "Unsigned note", Vector3(c.x - 8.0, 0.0, c.y + 6.0),
			"The Director wants the annex quiet until the next shipment clears Outpost 17. Anyone asking about Blackwood is to be told it is a training area. Nobody asks twice.")
	_add_crate(&"blackwood_crate_perimeter", Vector3(c.x - 14.0, 0.0, c.y - 8.0), ["antiseptic", "bandage"], false)
	_kit("barricade_concrete", c.x - 4.0, c.y - 4.0, 0.1, 1.0, Vector3(4.0, 1.2, 1.0))
	_kit("barricade_concrete", c.x + 6.0, c.y - 6.0, -0.2, 1.0, Vector3(4.0, 1.2, 1.0))


func _build_testing_site() -> void:
	var c := Vector2(-10.0, -215.0)
	_kit("warehouse", c.x - 14.0, c.y - 10.0, 0.0, 1.0, Vector3(10.0, 5.0, 8.0))
	_kit("container_red", c.x + 12.0, c.y - 8.0, 0.2, 1.0, Vector3(6.0, 2.6, 2.6))
	_kit("container_blue", c.x + 16.0, c.y + 4.0, 1.3, 1.0, Vector3(6.0, 2.6, 2.6))
	_kit("barricade_concrete", c.x + 9.0, c.y + 12.0, 0.0, 1.0, Vector3(4.0, 1.2, 1.0))
	# Experimental equipment: two consoles with glowing screens, an empty restraint frame.
	for i in 2:
		var pos := Vector3(c.x - 6.0 + i * 8.0, 0.0, c.y + 2.0)
		_block(pos + Vector3(0.0, 0.5, 0.0), Vector3(1.8, 1.0, 1.0), Color(0.2, 0.23, 0.25))
		_glow.box(pos + Vector3(0.0, 1.15, -0.35), Vector3(1.4, 0.7, 0.06), Color(0.3, 1.0, 0.75))
		var eq := Interactable.new()
		eq.interaction_id = StringName("bw_test_equipment_%d" % (i + 1))
		eq.prompt_text = "Examine equipment"
		eq.position = pos + Vector3(0.0, 0.9, 0.6)
		add_child(eq)
		var line := "A console logging heart-rate traces against a dose schedule." if i == 0 else "Leather restraints bolted to a steel frame. The straps are worn through where hands pulled."
		eq.interacted.connect(func(_p: Node3D) -> void: Outpost17.say(self, line, 5.5))
	_structures.box(Vector3(c.x + 4.0, 1.5, c.y + 2.0), Vector3(0.2, 3.0, 2.6), Color(0.35, 0.36, 0.38))
	_add_doc(&"bw_log_experiment_1", "Experiment record, Subject 14", Vector3(c.x - 2.0, 0.0, c.y - 4.0),
			"Subject 14 (transferred from the coast hospital, no next of kin on file). Dose four. Heart rate unstable, speech lost on day nine, strength gain beyond projection. The programme calls this a success. The medical officer has requested to be reassigned.")
	_add_doc(&"bw_log_subject_list", "Subject list", Vector3(c.x + 8.0, 0.0, c.y - 4.0),
			"Fourteen names crossed out, then numbers. Under 14 someone has written: 'Moved down to Sublevel 1.' Under 15: 'Not yet.'")
	_add_doc(&"bw_log_hatch", "Maintenance note", Vector3(c.x + 22.0, 0.0, c.y - 6.0),
			"Service hatch to Sublevel 1 is under the tarp by the east wall. Keep the tarp on. If the lights come on below, do not go down.")
	# Concealed hatch to the underground (found, not required).
	_structures.box(Vector3(14.0, 0.04, -223.0), Vector3(2.4, 0.08, 2.4), Color(0.18, 0.2, 0.2))
	var hatch := Interactable.new()
	hatch.interaction_id = &"bw_hatch"
	hatch.prompt_text = "Lift the tarp"
	hatch.locked_text = "Something is under the tarp, but the defenders are still watching"
	hatch.position = Vector3(14.0, 0.5, -223.0)
	add_child(hatch)
	hatch.locked = true
	_hatch = hatch
	_refresh_hatch(&"*", true)
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.flag_changed.connect(_refresh_hatch)  # a method on this node: the connection ends with the region
	hatch.interacted.connect(func(_p: Node3D) -> void:
		Outpost17.say(self, "A hatch with a fresh padlock cut off. The stairs below are lit.", 5.0))
	# Site terminal: opens the way on once the defenders are down.
	var terminal := Terminal.new()
	terminal.interaction_id = &"bw_site_terminal"
	terminal.terminal_title = "Site terminal"
	terminal.requires_flag = &"blackwood_site_defenders_cleared"
	terminal.finish_flag = ACCESS_FLAG
	terminal.locked_text = "Site terminal: locked while the site is guarded"
	terminal.pages = PackedStringArray(["Lockdown released. Transport route to the research facility entrance is open."])
	terminal.position = Vector3(c.x + 6.0, 0.6, c.y - 8.0)
	add_child(terminal)
	_block(Vector3(c.x + 6.0, 0.4, c.y - 7.8), Vector3(1.0, 0.8, 0.8), Color(0.2, 0.22, 0.25))
	_add_crate(&"blackwood_crate_site", Vector3(c.x - 18.0, 0.0, c.y + 8.0), ["electronics", "armor_patch"], true)


func _build_facility_entrance() -> void:
	var c := Vector2(-10.0, -258.0)
	# A concrete portal in a rock face; the exit marker sits in front of it.
	_block(Vector3(c.x - 8.0, 3.0, c.y - 8.0), Vector3(6.0, 6.0, 3.0), Color(0.3, 0.31, 0.3))
	_block(Vector3(c.x + 8.0, 3.0, c.y - 8.0), Vector3(6.0, 6.0, 3.0), Color(0.3, 0.31, 0.3))
	_structures.box(Vector3(c.x, 5.2, c.y - 8.0), Vector3(10.0, 1.6, 3.0), Color(0.28, 0.29, 0.28))
	_glow.box(Vector3(c.x, 4.2, c.y - 6.4), Vector3(3.0, 0.14, 0.06), Color(1.0, 0.25, 0.2))
	_solid(Vector3(c.x, 3.0, c.y - 10.5), Vector3(10.0, 6.0, 1.0))
	_add_checkpoint(&"blackwood_entrance", Vector3(c.x + 6.0, 0.0, c.y + 4.0))


func _add_checkpoint(id: StringName, pos: Vector3) -> void:
	var cp := Checkpoint.new()
	cp.interaction_id = id
	cp.position = pos + Vector3(0.0, 0.6, 0.0)
	add_child(cp)
	_block(pos + Vector3(0.0, 0.8, 0.0), Vector3(0.18, 1.6, 0.18), Color(0.9, 0.75, 0.25))


func _add_crate(id: StringName, pos: Vector3, items: Array, hidden: bool) -> void:
	var crate := SupplyCrate.new()
	crate.crate_id = id
	var paths := PackedStringArray()
	for item_id in items:
		paths.append("res://resources/items/%s.tres" % item_id)
	crate.loot_paths = paths
	crate.bonus_table_path = "res://resources/loot/crate_hidden.tres" if hidden else "res://resources/loot/crate_common.tres"
	crate.position = pos
	add_child(crate)


func _add_doc(id: StringName, title: String, pos: Vector3, text: String) -> void:
	var doc := LoreDocument.new()
	doc.interaction_id = id
	doc.title = title
	doc.body_text = text
	doc.position = pos + Vector3(0.0, 0.7, 0.0)
	add_child(doc)
	_structures.box(pos + Vector3(0.0, 0.5, 0.0), Vector3(0.7, 0.5, 0.5), Color(0.3, 0.24, 0.16))
	_structures.box(pos + Vector3(0.0, 0.78, 0.0), Vector3(0.45, 0.04, 0.32), Color(0.86, 0.82, 0.7))


func _finish_meshes() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	var node := MeshInstance3D.new()
	node.name = "Structures"
	node.mesh = _structures.commit()
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.vertex_color_use_as_albedo = true
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.8, 0.5)
	glow_mat.emission_energy_multiplier = 1.4
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	glow.mesh = _glow.commit()
	glow.material_override = glow_mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)


# --- triggers, encounters -------------------------------------------------------

func _build_triggers() -> void:
	for a in AREAS:
		var t := AreaTrigger.new()
		t.area_id = a["area"]
		t.name = "Trigger_%s" % a["id"]
		var c: Vector2 = a["c"]
		var s: Vector2 = a["size"]
		t.size = Vector3(s.x, 8.0, s.y)
		t.position = Vector3(c.x, 3.0, c.y)
		add_child(t)
	var ambush := AreaTrigger.new()
	ambush.area_id = &"blackwood_ambush_zone"
	ambush.name = "Trigger_ambush_zone"
	ambush.size = Vector3(14.0, 8.0, 10.0)
	ambush.position = Vector3(-17.0, 3.0, -66.0)
	add_child(ambush)


func _enc(id: StringName, area: StringName, scenes: Array, offsets: Array, at: Vector3, warn_s: float = 0.0, warn_text: String = "") -> BlackwoodEncounter:
	var e := BlackwoodEncounter.new()
	e.name = "Encounter_%s" % id
	e.encounter_id = id
	e.trigger_area = area
	e.scene_paths = PackedStringArray(scenes)
	var offs := PackedVector3Array()
	for o in offsets:
		offs.append(o)
	e.offsets = offs
	e.warning_seconds = warn_s
	e.warning_text = warn_text
	e.aggro_on_spawn = warn_s > 0.0
	e.position = at
	add_child(e)
	encounters[id] = e
	return e


func _build_encounters() -> void:
	# Trail patrol: two soldiers walk the main trail once the player enters.
	patrol = PatrolGroup.new()
	patrol.name = "TrailPatrol"
	patrol.group_id = &"bw_trail"
	patrol.area_id = &"blackwood_jungle_entrance"
	patrol.scene_paths = PackedStringArray([SOLDIER, SOLDIER])
	patrol.route_points = PackedVector3Array([Vector3(0.0, 0.0, -30.0), Vector3(-12.0, 0.0, -55.0), Vector3(-24.0, 0.0, -80.0), Vector3(-12.0, 0.0, -55.0)])
	patrol.loop = true
	add_child(patrol)
	# Ambush: birds go up first, the enemies close in from both flanks 1.5 s later.
	_enc(&"ambush", &"blackwood_ambush_zone", [SOLDIER, SOLDIER, HUNTER],
			[Vector3(-9.0, 0.0, -6.0), Vector3(8.0, 0.0, -2.0), Vector3(-6.0, 0.0, 8.0)], Vector3(-17.0, 0.0, -66.0),
			1.5, "Birds burst out of the trees. Something is moving in the brush.")
	_enc(&"perimeter_elites", &"blackwood_research_perimeter", [HUNTER, HUNTER, SOLDIER],
			[Vector3(-8.0, 0.0, -14.0), Vector3(6.0, 0.0, -14.0), Vector3(0.0, 0.0, -20.0)], Vector3(-10.0, 0.0, -165.0))
	_enc(&"site_defenders", &"blackwood_testing_site", [HEAVY, HUNTER, SOLDIER, SOLDIER],
			[Vector3(-8.0, 0.0, 6.0), Vector3(6.0, 0.0, 10.0), Vector3(-14.0, 0.0, 12.0), Vector3(10.0, 0.0, 14.0)], Vector3(-10.0, 0.0, -230.0))




func _set_gate(open: bool) -> void:
	_gate_open = open
	if gate_body == null:
		return
	gate_mesh.visible = not open
	for child in gate_body.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", open)


func _refresh_hatch(id: StringName, _value: bool) -> void:
	if _hatch == null or not (id == &"blackwood_site_defenders_cleared" or id == &"*"):
		return
	var state := get_node_or_null("/root/WorldState")
	_hatch.locked = not (state != null and state.has_flag(&"blackwood_site_defenders_cleared"))
