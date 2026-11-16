class_name OpeningApproach
extends Node3D
## Opening Milestones 3 to 5 in Area A (the beach, z 30..80). Trail clues in the sand, an earth berm that screens
## the compound from the spawn (two gaps: the direct path and a bushy bypass), a rise with a ramp to look over the
## wall, a perimeter fence with a cranked gate and a hidden cut, two patrols, a work yard seen from afar, a supply
## crate and a checkpoint. All scenery is one merged vertex-coloured mesh; colliders are plain boxes.
## Flags: settlement_seen, perimeter_crank_turned (Terminal.finish_flag), door_perimeter_open (Door).
## Area ids reported to quests: opening_trail_gap, opening_viewpoint, opening_fence_reached, opening_perimeter_in.

const BEACH_X: float = 42.0
const BERM_Z0: float = 50.5
const BERM_Z1: float = 53.5
const BERM_H: float = 5.8
const DECK_H: float = 4.4
const GAP_DIRECT: Vector2 = Vector2(-3.0, 3.0)
const GAP_BYPASS: Vector2 = Vector2(24.0, 28.0)
const DECK_X: Vector2 = Vector2(11.0, 17.0)
const FENCE_Z: float = 44.5
const FENCE_H: float = 2.2
const CUT_X: Vector2 = Vector2(17.5, 20.5)
const GATE_WIDTH: float = 5.0
const START_AREA: StringName = &"opening_trail_start"
const QUEST_TRAIL: StringName = &"opening_trail"
const START_FLAG: StringName = &"opening_event_seen"
const VIEW_CAPTION: String = "Three people and a bag, I could follow. A place with fences and guards is another matter."
const FENCE_CAPTION: String = "The front gate is the stupid way in. There has to be another."

const EARTH: Color = Color(0.22, 0.17, 0.12)
const EARTH_TOP: Color = Color(0.2, 0.22, 0.14)
const GRASS: Color = Color(0.2, 0.3, 0.15)
const PRINT: Color = Color(0.12, 0.1, 0.08)
const FLAT: Color = Color(0.26, 0.32, 0.17)

var triggers: Dictionary = {}
var gate: Door
var control: Terminal
var crate: SupplyCrate
var checkpoint: Checkpoint
var patrol_trail: PatrolGroup
var patrol_gate: PatrolGroup
var walkers: Array[WorkerWalker] = []

var _b: ArenaDecor.Builder
var _smooth: Array = []  # ArrayMesh pieces of the berm and rise
var _clock: float = 0.0
var _started: bool = false


static func build(outpost: Node3D) -> OpeningApproach:
	var approach := OpeningApproach.new()
	approach.name = "OpeningApproach"
	outpost.add_child(approach)
	return approach


func _ready() -> void:
	_b = ArenaDecor.Builder.new()
	_build_berm()
	_build_ramp_and_deck()
	_build_clues()
	_build_fence()
	_build_yard()
	_build_props()
	_finish_mesh()
	_build_bushes()
	_build_gate()
	_build_interactables()
	_build_triggers()
	_build_patrols()
	_build_walkers()
	_build_smoke()
	var state := get_node_or_null("/root/WorldState")
	if state != null:
		state.area_entered.connect(_on_area_entered)
	OpeningSoundscape.attach(self)


func _process(delta: float) -> void:
	if _started:
		set_process(false)
		return
	_clock += delta
	if _clock < 0.5:
		return
	_clock = 0.0
	try_start_quest()


## Starts "The Trail" once the opening has handed control to the player (the beach sets opening_event_seen).
func try_start_quest() -> bool:
	var state := get_node_or_null("/root/WorldState")
	var quests := get_node_or_null("/root/QuestManager")
	if state == null or quests == null or not state.has_flag(START_FLAG):
		return false
	_started = true
	if quests.is_active(QUEST_TRAIL) or quests.is_completed(QUEST_TRAIL) or quests.is_active(&"opening_perimeter") or quests.is_completed(&"opening_perimeter"):
		return false
	return quests.start_quest(QUEST_TRAIL, true)


# --- geometry helpers --------------------------------------------------------

func _box(solid_name: String, center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = solid_name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	body.basis = basis
	add_child(body)
	return body


func _solid(solid_name: String, center: Vector3, size: Vector3, color: Color) -> void:
	_b.box(center, size, color)
	_box(solid_name, center, size)


func _place(item: Interactable, id: StringName, pos: Vector3) -> void:
	item.name = String(id).capitalize().replace(" ", "")
	item.interaction_id = id
	item.position = pos
	add_child(item)


func _finish_mesh() -> void:
	var node := MeshInstance3D.new()
	node.name = "ApproachMesh"
	node.mesh = _b.finish()
	node.material_override = PbrMaterials.concrete()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	# Berm and rise: one vertex-coloured mesh (sand, scrub, rock) over the same footprints as their colliders.
	var terrain := MeshInstance3D.new()
	terrain.name = "ApproachTerrain"
	terrain.mesh = OpeningArt.merge(_smooth)
	terrain.material_override = OpeningArt.material(true, 0.95, 0.0)
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(terrain)


# --- the berm: screens the compound, two gaps ---------------------------------

func _berm_segment(seg_name: String, x0: float, x1: float, height: float) -> void:
	# The visible mound is a smooth mesh over exactly the collision footprint (see _finish_mesh).
	_smooth.append(OpeningArt.berm_mesh(x0, x1, BERM_Z0, BERM_Z1, height, seg_name.hash()))
	var cx := (x0 + x1) * 0.5
	var cz := (BERM_Z0 + BERM_Z1) * 0.5
	var width := x1 - x0
	_box(seg_name, Vector3(cx, height * 0.5, cz), Vector3(width, height, BERM_Z1 - BERM_Z0))


func _build_berm() -> void:
	_berm_segment("BermWest", -BEACH_X, GAP_DIRECT.x, BERM_H)
	_berm_segment("BermMidA", GAP_DIRECT.y, DECK_X.x, BERM_H)
	_berm_segment("BermMidB", DECK_X.y, GAP_BYPASS.x, BERM_H)
	_berm_segment("BermEast", GAP_BYPASS.y, BEACH_X, BERM_H)


func _build_ramp_and_deck() -> void:
	var cz := (BERM_Z0 + BERM_Z1) * 0.5
	var cx := (DECK_X.x + DECK_X.y) * 0.5
	var width := DECK_X.y - DECK_X.x
	_smooth.append(OpeningArt.berm_mesh(DECK_X.x, DECK_X.y, BERM_Z0, BERM_Z1, DECK_H, 3, false))  # flat-topped rise under the planks
	_b.box(Vector3(cx, DECK_H + 0.07, cz), Vector3(width, 0.14, BERM_Z1 - BERM_Z0), ArenaDecor.WOOD)
	_box("ViewDeck", Vector3(cx, DECK_H * 0.5, cz), Vector3(width, DECK_H, BERM_Z1 - BERM_Z0))
	# A low rail along the north edge so a stumble does not drop the player off the rise.
	_b.box(Vector3(cx, DECK_H + 0.55, BERM_Z0 + 0.1), Vector3(width, 0.12, 0.12), ArenaDecor.WOOD_DARK)
	for px in [DECK_X.x + 0.2, cx, DECK_X.y - 0.2]:
		_b.box(Vector3(px, DECK_H + 0.4, BERM_Z0 + 0.1), Vector3(0.14, 0.8, 0.14), ArenaDecor.WOOD_DARK)
	_box("ViewRail", Vector3(cx, DECK_H + 0.5, BERM_Z0 + 0.1), Vector3(width, 1.0, 0.2))
	# Ramp: from the sand at z = 61 up to the deck's south edge (z = 53.5).
	var run := 61.0 - BERM_Z1
	var length := sqrt(run * run + DECK_H * DECK_H)
	var theta := atan2(DECK_H, run)
	var basis := Basis(Vector3.RIGHT, theta)
	var mid := Vector3(cx, DECK_H * 0.5 - 0.2 * cos(theta), (61.0 + BERM_Z1) * 0.5 - 0.2 * sin(theta))
	_b.box(mid, Vector3(width - 1.0, 0.4, length), ArenaDecor.WOOD, basis)
	_box("ViewRamp", mid, Vector3(width - 1.0, 0.4, length), basis)


# --- trail clues -------------------------------------------------------------

func _build_clues() -> void:
	# Footprints from the beach up to the direct gap and beyond: two per stride, a little off the line.
	var z := 61.0
	var i := 0
	while z > 47.0:
		var x := -1.4 + sin(float(i) * 1.3) * 0.5
		var yaw := sin(float(i) * 0.9) * 0.15
		var basis := Basis(Vector3.UP, yaw)
		_b.box(Vector3(x - 0.17, 0.015, z), Vector3(0.2, 0.02, 0.42), PRINT, basis)
		_b.box(Vector3(x + 0.17, 0.015, z - 0.45), Vector3(0.2, 0.02, 0.42), PRINT, basis)
		z -= 0.9
		i += 1
	# Two drag lines where the bag's weight pulled along (a bag carried by two people).
	_b.box(Vector3(-0.85, 0.014, 56.5), Vector3(0.1, 0.02, 6.4), PRINT.lightened(0.05), Basis(Vector3.UP, 0.04))
	_b.box(Vector3(-0.6, 0.014, 55.8), Vector3(0.09, 0.02, 5.2), PRINT.lightened(0.05), Basis(Vector3.UP, 0.02))
	# Flattened grass where the group pushed through, and a dropped rag.
	for patch: Array in [[Vector3(-1.8, 0.012, 58.0), 0.3], [Vector3(0.6, 0.012, 55.0), -0.2], [Vector3(-0.4, 0.012, 49.2), 0.1]]:
		_b.box(patch[0], Vector3(1.8, 0.02, 1.2), FLAT, Basis(Vector3.UP, float(patch[1])))
	_b.box(Vector3(2.3, 0.03, 54.6), Vector3(0.4, 0.03, 0.28), Color(0.56, 0.58, 0.62), Basis(Vector3.UP, 0.45))
	# Cut stumps near the way in: someone has been felling trees for fuel.
	for stump: Vector3 in [Vector3(-6.0, 0.0, 58.5), Vector3(5.5, 0.0, 56.0), Vector3(8.0, 0.0, 49.0), Vector3(-9.0, 0.0, 50.0), Vector3(22.0, 0.0, 56.5), Vector3(30.0, 0.0, 57.5)]:
		_b.box(stump + Vector3(0.0, 0.17, 0.0), Vector3(0.5, 0.34, 0.5), ArenaDecor.WOOD_DARK)
		_b.box(stump + Vector3(0.0, 0.35, 0.0), Vector3(0.4, 0.04, 0.4), ArenaDecor.WOOD.lightened(0.1))
	# The bypass is fouled by a fallen log you jump or walk round.
	_b.box(Vector3(24.0, 0.4, 47.4), Vector3(12.0, 0.8, 0.9), ArenaDecor.WOOD_DARK)
	_box("FallenLog", Vector3(24.0, 0.4, 47.4), Vector3(12.0, 0.8, 0.9))


# --- fence, gate, yard ---------------------------------------------------------

func _fence_run(fence_name: String, x0: float, x1: float) -> void:
	var width := x1 - x0
	var cx := (x0 + x1) * 0.5
	var posts := int(ceil(width / 3.0)) + 1
	for p in posts:
		var px := x0 + minf(float(p) * 3.0, width)
		_b.box(Vector3(px, FENCE_H * 0.5, FENCE_Z), Vector3(0.16, FENCE_H, 0.16), ArenaDecor.WOOD_DARK)
	for ry in [0.7, 1.5, 2.1]:
		_b.box(Vector3(cx, float(ry), FENCE_Z), Vector3(width, 0.06, 0.05), Color(0.33, 0.33, 0.31))
	_box(fence_name, Vector3(cx, FENCE_H * 0.5, FENCE_Z), Vector3(width, FENCE_H, 0.3))


func _build_fence() -> void:
	var half := GATE_WIDTH * 0.5
	_fence_run("FenceWest", -BEACH_X, -half)
	_fence_run("FenceMid", half, CUT_X.x)
	_fence_run("FenceEast", CUT_X.y, BEACH_X)
	# The cut: bent rails hanging where someone has already been through.
	_b.box(Vector3(CUT_X.x + 0.15, 1.0, FENCE_Z + 0.05), Vector3(0.05, 1.8, 0.05), Color(0.33, 0.33, 0.31), Basis(Vector3.BACK, 0.35))
	_b.box(Vector3(CUT_X.y - 0.15, 1.0, FENCE_Z + 0.05), Vector3(0.05, 1.8, 0.05), Color(0.33, 0.33, 0.31), Basis(Vector3.BACK, -0.3))


func _build_gate() -> void:
	gate = Door.new()
	gate.name = "PerimeterGate"
	gate.door_id = &"perimeter"
	gate.width = GATE_WIDTH
	gate.height = FENCE_H
	gate.locked_by_flag = &"perimeter_crank_turned"
	gate.lock_reason = "The gate is jammed. There is a crank box by the post."
	gate.position = Vector3(0.0, 0.0, FENCE_Z)
	add_child(gate)


func _build_yard() -> void:
	# A fenced work yard with crates, in view from the rise: x 27..40, z 33..41. Closed north and east.
	_b.box(Vector3(33.5, 1.0, 33.0), Vector3(13.0, 2.0, 0.2), Color(0.3, 0.3, 0.28))
	_box("YardNorth", Vector3(33.5, 1.0, 33.0), Vector3(13.0, 2.0, 0.3))
	_b.box(Vector3(40.0, 1.0, 37.0), Vector3(0.2, 2.0, 8.0), Color(0.3, 0.3, 0.28))
	_box("YardEast", Vector3(40.0, 1.0, 37.0), Vector3(0.3, 2.0, 8.0))
	for crate_pos: Vector3 in [Vector3(30.0, 0.0, 37.5), Vector3(31.2, 0.0, 37.5), Vector3(30.6, 0.0, 37.5), Vector3(37.5, 0.0, 35.0), Vector3(37.5, 0.0, 36.1)]:
		_b.box(crate_pos + Vector3(0.0, 0.4, 0.0), Vector3(1.0, 0.8, 1.0), ArenaDecor.WOOD)
	_b.box(Vector3(30.6, 1.2, 37.5), Vector3(1.0, 0.8, 1.0), ArenaDecor.WOOD_DARK)
	_box("YardCrates", Vector3(30.6, 0.8, 37.5), Vector3(2.4, 1.6, 1.2))
	_box("YardCratesE", Vector3(37.5, 0.4, 35.55), Vector3(1.0, 0.8, 2.2))


func _build_walkers() -> void:
	var specs: Array[Dictionary] = [
		{"path": [Vector3(29.0, 0.0, 35.5), Vector3(38.0, 0.0, 35.5)], "speed": 0.8, "guard": false, "carry": true},
		{"path": [Vector3(30.0, 0.0, 39.5), Vector3(38.5, 0.0, 39.5)], "speed": 0.7, "guard": false, "carry": true},
		{"path": [Vector3(34.0, 0.0, 34.2), Vector3(34.0, 0.0, 40.0)], "speed": 0.75, "guard": false, "carry": false},
		{"path": [Vector3(28.0, 0.0, 41.5), Vector3(39.0, 0.0, 41.5)], "speed": 0.45, "guard": true, "carry": false},
	]
	for spec: Dictionary in specs:
		var walker := WorkerWalker.new()
		walker.name = "Guard" if spec["guard"] else "Worker"
		walker.path = PackedVector3Array(spec["path"])
		walker.speed = spec["speed"]
		walker.guard = spec["guard"]
		walker.carrying = spec["carry"]
		add_child(walker)
		walkers.append(walker)


# --- props: poles, cables, a watch shed ------------------------------------------

func _build_props() -> void:
	var poles: Array[Vector3] = [Vector3(-30.0, 0.0, 57.0), Vector3(-16.0, 0.0, 61.0), Vector3(21.0, 0.0, 58.0), Vector3(34.0, 0.0, 57.0)]
	for pole in poles:
		_b.box(pole + Vector3(0.0, 2.3, 0.0), Vector3(0.18, 4.6, 0.18), ArenaDecor.WOOD_DARK)
		_b.box(pole + Vector3(0.0, 4.35, 0.0), Vector3(1.2, 0.08, 0.08), ArenaDecor.WOOD_DARK)
	for i in poles.size() - 1:
		var a: Vector3 = poles[i] + Vector3(0.0, 4.3, 0.0)
		var c: Vector3 = poles[i + 1] + Vector3(0.0, 4.3, 0.0)
		var span := c - a
		var mid := (a + c) * 0.5 + Vector3(0.0, -0.25, 0.0)
		var yaw := atan2(span.x, span.z)
		_b.box(mid, Vector3(0.04, 0.04, Vector2(span.x, span.z).length()), Color(0.1, 0.1, 0.1), Basis(Vector3.UP, yaw))
	# A guard shed west of the direct gap: a solid box with a roof and a lamp.
	_solid("GuardShed", Vector3(-33.0, 1.2, 47.8), Vector3(2.6, 2.4, 2.6), ArenaDecor.WOOD_DARK)
	_b.box(Vector3(-33.0, 2.55, 47.8), Vector3(3.2, 0.2, 3.2), ArenaDecor.RUST)
	_b.box(Vector3(-33.0, 1.6, 46.45), Vector3(0.6, 0.5, 0.06), Color(0.9, 0.8, 0.45))


func _build_bushes() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sphere := SphereMesh.new()
	sphere.radius = 0.8
	sphere.height = 1.4
	sphere.radial_segments = 6
	sphere.rings = 3
	mm.mesh = sphere
	var spots: Array[Vector3] = []
	for x in [22.2, 22.9, 23.6, 28.4, 29.1, 29.8, 30.5]:
		spots.append(Vector3(x, 0.6, 51.0 + fmod(x * 3.7, 2.2)))
	for x in [16.2, 16.9, 21.1, 21.9, 22.7]:
		spots.append(Vector3(x, 0.6, FENCE_Z + 1.3))
	for x in [-35.0, -28.0, -20.0, -12.0, 7.5, 9.5, 36.5, 39.0]:
		spots.append(Vector3(x, 0.55, 54.4))
	mm.instance_count = spots.size()
	for i in spots.size():
		var s := 0.8 + fmod(float(i) * 0.37, 0.7)
		var t := Transform3D(Basis.IDENTITY.scaled(Vector3(s * 1.2, s, s * 1.2)), spots[i])
		mm.set_instance_transform(i, t)
	var node := MultiMeshInstance3D.new()
	node.name = "Bushes"
	node.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.27, 0.13)
	mat.roughness = 1.0
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _build_smoke() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var settings := get_node_or_null("/root/Settings")
	var amount := 16
	if settings != null:
		match int(settings.quality):
			0:  # Settings.Quality.LOW
				return
			1:  # Settings.Quality.MEDIUM
				amount = 8
	var smoke := CPUParticles3D.new()
	smoke.name = "DistantSmoke"
	smoke.amount = amount
	smoke.lifetime = 6.0
	smoke.direction = Vector3.UP
	smoke.spread = 8.0
	smoke.initial_velocity_min = 1.4
	smoke.initial_velocity_max = 2.0
	smoke.gravity = Vector3(0.4, 0.0, 0.0)
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 1.8
	smoke.color = Color(0.3, 0.3, 0.3, 0.45)
	var puff := SphereMesh.new()
	puff.radius = 0.6
	puff.height = 1.2
	puff.radial_segments = 6
	puff.rings = 3
	smoke.mesh = puff
	smoke.position = Vector3(27.0, 1.0, 18.0)
	add_child(smoke)


# --- interactables, triggers, patrols ------------------------------------------

func _build_interactables() -> void:
	control = Terminal.new()
	control.terminal_title = "Gate control"
	control.pages = PackedStringArray(["The motor is dead. There is a hand crank under the panel.", "You wind it. The gate frame groans and starts to give."])
	control.finish_flag = &"perimeter_crank_turned"
	_place(control, &"perimeter_crank", Vector3(4.6, 0.2, 45.9))
	_b = ArenaDecor.Builder.new()
	_b.box(Vector3(4.6, 0.6, 45.9), Vector3(1.2, 1.2, 0.5), Color(0.28, 0.3, 0.3))
	_b.box(Vector3(4.6, 1.3, 45.62), Vector3(0.7, 0.4, 0.06), Color(0.2, 0.55, 0.62))
	_box("CrankBox", Vector3(4.6, 0.6, 45.9), Vector3(1.2, 1.2, 0.5))
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "CrankMesh"
	mesh_node.mesh = _b.finish()
	mesh_node.material_override = PbrMaterials.concrete()
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_node)

	var roster := LoreDocument.new()
	roster.title = "Gate roster"
	roster.body_text = "Two on the south gate, rotating. Anything the storm puts on the sand goes to the yard, not to the officers. Keep the workers off the beach."
	_place(roster, &"gate_roster", Vector3(18.9, 0.7, 45.4))

	crate = SupplyCrate.new()
	crate.crate_id = &"supply_crate_a1"
	crate.loot_paths = PackedStringArray(["res://resources/items/health_potion.tres", "res://resources/items/armor_patch.tres"])
	crate.position = Vector3(25.5, 0.0, 46.4)
	add_child(crate)
	_box("SupplyCrateA1Body", Vector3(25.5, 0.4, 46.4), Vector3(1.1, 0.8, 0.85))

	checkpoint = Checkpoint.new()
	_place(checkpoint, &"checkpoint_trail_end", Vector3(4.5, 0.8, 40.0))
	_box("CheckpointTrailBody", Vector3(4.5, 0.8, 40.4), Vector3(0.6, 1.6, 0.6))


func _build_triggers() -> void:
	var specs: Dictionary = {
		START_AREA: [Vector3(0.0, 2.0, 63.0), Vector3(BEACH_X * 2.0, 6.0, 30.0)],
		&"opening_trail_gap": [Vector3(0.0, 2.0, 51.5), Vector3(6.0, 6.0, 5.0)],
		&"opening_viewpoint": [Vector3((DECK_X.x + DECK_X.y) * 0.5, DECK_H + 1.6, 52.0), Vector3(DECK_X.y - DECK_X.x - 0.6, 3.2, 2.6)],
		&"opening_fence_reached": [Vector3(0.0, 2.0, 47.0), Vector3(BEACH_X * 2.0, 6.0, 3.0)],
		&"opening_perimeter_in": [Vector3(0.0, 2.0, 41.5), Vector3(BEACH_X * 2.0, 6.0, 5.0)],
	}
	for id: StringName in specs:
		var trigger := AreaTrigger.new()
		trigger.name = "Trigger_" + String(id)
		trigger.area_id = id
		trigger.size = specs[id][1]
		trigger.position = specs[id][0]
		add_child(trigger)
		triggers[id] = trigger


func _build_patrols() -> void:
	patrol_trail = PatrolGroup.new()
	patrol_trail.name = "PatrolTrail"
	patrol_trail.group_id = &"trail_guards"
	patrol_trail.area_id = START_AREA
	patrol_trail.scene_paths = PackedStringArray(["res://scenes/enemies/PatrolSoldier.tscn", "res://scenes/enemies/PatrolSoldier.tscn"])
	patrol_trail.route_points = PackedVector3Array([Vector3(-16.0, 0.1, 47.0), Vector3(-6.0, 0.1, 47.0)])
	patrol_trail.loop = false
	patrol_trail.wait_seconds = 2.2
	add_child(patrol_trail)
	patrol_gate = PatrolGroup.new()
	patrol_gate.name = "PatrolGate"
	patrol_gate.group_id = &"gate_guard"
	patrol_gate.area_id = START_AREA
	patrol_gate.scene_paths = PackedStringArray(["res://scenes/enemies/PatrolSoldier.tscn"])
	patrol_gate.route_points = PackedVector3Array([Vector3(-9.0, 0.1, 41.0), Vector3(-2.5, 0.1, 41.0)])
	patrol_gate.loop = false
	patrol_gate.wait_seconds = 2.0
	add_child(patrol_gate)


func _on_area_entered(id: StringName) -> void:
	var state := get_node_or_null("/root/WorldState")
	if state == null:
		return
	if id == &"opening_viewpoint" and not state.has_flag(&"settlement_seen"):
		state.set_flag(&"settlement_seen", true)
		Outpost17.say(self, VIEW_CAPTION, 6.0)
	elif id == &"opening_fence_reached" and not state.has_flag(&"fence_seen"):
		state.set_flag(&"fence_seen", true)
		Outpost17.say(self, FENCE_CAPTION, 5.0)
