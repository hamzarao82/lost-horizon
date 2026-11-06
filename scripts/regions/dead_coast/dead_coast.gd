class_name DeadCoast
extends Node3D
## Dead Coast: the first region beyond Outpost 17. A self-contained content builder: call build()
## (done automatically on _ready), then the region framework reads `entry_points`, `exit_points`,
## `capture_state()` / `restore_state()` and the metadata below. It starts its own quest chain.

const REGION_ID: StringName = &"dead_coast"
const FIRST_QUEST: StringName = &"dc_wreckage"
const LAST_QUEST: StringName = &"dc_lost_cargo"
const COMPLETE_FLAG: StringName = &"dead_coast.cargo_complete"
const ROUTE_FLAG: StringName = &"dead_coast.route_pass"
const RETRY_SECONDS: float = 2.5
const ENEMY_TABLE_REGULAR: String = "res://resources/loot/dead_coast_regular.tres"
const ENEMY_TABLE_ELITE: String = "res://resources/loot/dead_coast_elite.tres"

## Display areas: id, name, z centre, z length, d centre (inland), d width, trigger height and centre y.
const AREAS: Array[Dictionary] = [
	{"id": &"dc_wreckage_beach", "name": "Wreckage Beach", "z": -12.0, "len": 66.0, "d": 20.0, "w": 60.0, "y": 4.0},
	{"id": &"dc_coastal_trail", "name": "Coastal Trail", "z": -72.0, "len": 56.0, "d": 20.0, "w": 60.0, "y": 4.0},
	{"id": &"dc_checkpoint", "name": "Abandoned Checkpoint", "z": -121.0, "len": 44.0, "d": 18.0, "w": 52.0, "y": 4.0},
	{"id": &"dc_cove", "name": "Smuggler's Cove", "z": -168.0, "len": 52.0, "d": 14.0, "w": 30.0, "y": 4.0},
	{"id": &"dc_watchpoint", "name": "Cliffside Watchpoint", "z": -152.0, "len": 38.0, "d": 54.0, "w": 30.0, "y": 12.0},
	{"id": &"dc_depot", "name": "Hidden Supply Depot", "z": -189.0, "len": 26.0, "d": 48.0, "w": 26.0, "y": 4.0},
	{"id": &"dc_exit", "name": "Exit toward Blackwood", "z": -212.0, "len": 24.0, "d": 18.0, "w": 52.0, "y": 4.0},
]

## Set before add_child to build a sun and haze of its own (screenshots, tests). The framework normally provides them.
var owns_lighting: bool = false
## Vegetation density multiplier (1.0 desktop high; the framework lowers it for web and mobile).
var vegetation_density: float = 1.0

var entry_points: Dictionary = {}
var exit_points: Dictionary = {}
var triggers: Dictionary = {}
var props: DeadCoastProps
var content: DeadCoastContent

var _built: bool = false
var _retry: Timer


func _ready() -> void:
	set_meta(&"region_id", REGION_ID)
	set_meta(&"ambience_name", "dead_coast")
	set_meta(&"environment_preset", "dead_coast")
	if not _built:
		build()


func region_id() -> StringName:
	return REGION_ID


## The walkable main route, dense enough (5 m) that the chord never leaves the shore-following strip.
static func main_path() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var z := 14.0
	while z >= -224.0:
		var gate := exp(-pow((z + 118.0) / 9.0, 2.0))
		var d := lerpf(14.0, 3.0, gate)
		pts.append(DeadCoastTerrain.ground(d, z))
		z -= 5.0
	return pts


static func branch_paths() -> Dictionary:
	var ramp: Array[Vector3] = []
	var depot: Array[Vector3] = []
	for i in 9:
		var t := i / 8.0
		ramp.append(DeadCoastTerrain.ground(lerpf(16.0, 52.0, t), lerpf(-124.0, -152.0, t)))
	depot.append(DeadCoastTerrain.ground(14.0, -187.0))
	for dd in [20.0, 26.0, 32.0, 38.0, 44.0, 50.0]:
		depot.append(DeadCoastTerrain.ground(dd, -187.5))
	return {"watchpoint": ramp, "depot": depot}


## Display name of the area containing a world position ("" outside all areas).
func location_at(pos: Vector3) -> String:
	for area in AREAS:
		var rect := _area_rect(area)
		if rect.has_point(Vector2(pos.x, pos.z)):
			return area["name"]
	return ""


func _area_rect(area: Dictionary) -> Rect2:
	var cx := DeadCoastTerrain.shore_x(float(area["z"])) + float(area["d"])
	return Rect2(cx - float(area["w"]) * 0.5, float(area["z"]) - float(area["len"]) * 0.5, float(area["w"]), float(area["len"]))


func build() -> void:
	if _built:
		return
	_built = true
	props = DeadCoastProps.new(self, vegetation_density)
	props.build_terrain()
	content = DeadCoastContent.new(self, props)
	content.build()
	props.scatter(main_path())
	props.finish()
	_build_triggers()
	_build_exits_and_entries()
	if owns_lighting:
		_build_lighting()
	_wire_quests()
	_retry = Timer.new()
	_retry.name = "SpawnRetry"
	_retry.wait_time = RETRY_SECONDS
	_retry.autostart = true
	_retry.timeout.connect(_tick)
	add_child(_retry)


func _build_triggers() -> void:
	for area in AREAS:
		var trigger := AreaTrigger.new()
		trigger.name = "Trigger_" + String(area["id"])
		trigger.area_id = area["id"]
		trigger.size = Vector3(float(area["w"]), 16.0, float(area["len"]))
		var cx := DeadCoastTerrain.shore_x(float(area["z"])) + float(area["d"])
		trigger.position = Vector3(cx, float(area["y"]), float(area["z"]))
		add_child(trigger)
		triggers[area["id"]] = trigger


func _build_exits_and_entries() -> void:
	var arrival := DeadCoastTerrain.ground(14.0, 10.0, 0.1)
	var gate_south := DeadCoastTerrain.ground(16.0, -206.0, 0.1)
	entry_points = {
		"beach_arrival": Transform3D(Basis.IDENTITY, arrival),                       # faces north (-z)
		"from_blackwood": Transform3D(Basis(Vector3.UP, PI), gate_south),             # faces back down the coast
	}
	exit_points = {
		"to_outpost_17": {"position": DeadCoastTerrain.ground(14.0, 24.0), "region": "outpost_17",
			"entry": "from_dead_coast", "locked_flag": "", "locked_text": ""},
		"to_blackwood": {"position": DeadCoastTerrain.ground(18.0, -224.0), "region": "blackwood",
			"entry": "from_dead_coast", "locked_flag": String(COMPLETE_FLAG),
			"locked_text": "The trail north is still sealed: find the lost cargo first."},
	}
	var exits := Node3D.new()
	exits.name = "Exits"
	add_child(exits)
	for id: String in exit_points:
		var marker := Marker3D.new()
		marker.name = id
		marker.position = (exit_points[id] as Dictionary)["position"]
		for key: String in ["region", "entry", "locked_flag", "locked_text"]:
			marker.set_meta(StringName(key), (exit_points[id] as Dictionary)[key])
		exits.add_child(marker)


func _build_lighting() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.55, 0.78)
	sky_material.sky_horizon_color = Color(0.86, 0.78, 0.66)
	sky_material.ground_bottom_color = Color(0.35, 0.3, 0.25)
	sky_material.ground_horizon_color = Color(0.86, 0.78, 0.66)
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.82, 0.76, 0.66)
	env.fog_density = 0.002
	var world_env := WorldEnvironment.new()
	world_env.name = "DeadCoastEnvironment"
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "DeadCoastSun"
	sun.rotation_degrees = Vector3(-38.0, -125.0, 0.0)
	sun.light_color = Color(1.0, 0.9, 0.74)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)


# --- quests and persistence ------------------------------------------------------

func _quest_manager() -> Node:
	return get_node_or_null("/root/QuestManager")


func _world_state() -> Node:
	return get_node_or_null("/root/WorldState")


func _wire_quests() -> void:
	var quests := _quest_manager()
	if quests != null and quests.has_signal("quest_completed"):
		quests.quest_completed.connect(_on_quest_completed)


func _on_quest_completed(quest_id: StringName) -> void:
	if quest_id != LAST_QUEST:
		return
	var state := _world_state()
	if state != null:
		state.set_flag(COMPLETE_FLAG, true)  # opens the exit to Blackwood; saved with the world flags


## Called by the region framework (or a test) when the player arrives. Starts the chain once.
func enter(entry_id: String = "beach_arrival") -> Transform3D:
	var quests := _quest_manager()
	if quests != null and quests.has_method("start_quest"):
		if not quests.is_active(FIRST_QUEST) and not quests.is_completed(FIRST_QUEST):
			quests.start_quest(FIRST_QUEST)
	return entry_points.get(entry_id, entry_points["beach_arrival"])


## Everything this region has handed out or finished, as ids that were claimed. Idempotent to restore.
func capture_state() -> Dictionary:
	var state := _world_state()
	var claimed: Array = []
	var read: Array = []
	var cleared: Array = []
	var flags: Array = []
	if state != null:
		for id in content.crate_ids:
			if state.has_flag(StringName(id + "_taken")):
				claimed.append(id)
		for id in content.document_ids:
			if state.has_flag(StringName("doc_%s_found" % id)):
				read.append(id)
		for id: String in content.patrols:
			if state.has_flag(StringName("patrol_%s_cleared" % id)):
				cleared.append(id)
		for flag in [ROUTE_FLAG, COMPLETE_FLAG, &"door_dc_gate_open"]:
			if state.has_flag(flag):
				flags.append(String(flag))
	return {"version": 1, "claimed": claimed, "read": read, "cleared": cleared, "flags": flags}


func restore_state(raw: Variant) -> void:
	if not (raw is Dictionary):
		return
	var data: Dictionary = raw
	var state := _world_state()
	if state == null:
		return
	for id in _strings(data.get("claimed")):
		if content.crate_ids.has(id):
			state.set_flag(StringName(id + "_taken"), true)
			var crate := content.nodes.get(id) as SupplyCrate
			if crate != null:
				crate.mark_used(true)
				crate._set_open(true, false)
	for id in _strings(data.get("read")):
		if content.document_ids.has(id):
			state.set_flag(StringName("doc_%s_found" % id), true)
	for id in _strings(data.get("cleared")):
		if content.patrols.has(id):
			state.set_flag(StringName("patrol_%s_cleared" % id), true)
			(content.patrols[id] as PatrolGroup).spawned = true  # stays dead: never spawns again
	for flag in _strings(data.get("flags")):
		if flag == String(ROUTE_FLAG) or flag == String(COMPLETE_FLAG) or flag == "door_dc_gate_open":
			state.set_flag(StringName(flag), true)


static func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for entry in value:
			if entry is String or entry is StringName:
				out.append(String(entry))
	return out


# --- spawn retry and loot tagging --------------------------------------------------

## PatrolGroup refuses to spawn when four patrollers are already out; retry quietly for groups whose area
## has been entered, and give every Dead Coast enemy this region's loot table.
func _tick() -> void:
	var state := _world_state()
	for id: String in content.patrols:
		var group := content.patrols[id] as PatrolGroup
		if state != null and not group.spawned and state.has_flag(StringName("discovered_%s" % group.area_id)):
			group.spawn()
		_tag_loot(group)


func _tag_loot(group: PatrolGroup) -> void:
	for enemy in group.enemies:
		if not is_instance_valid(enemy) or enemy.has_meta(&"dc_loot"):
			continue
		enemy.set_meta(&"dc_loot", true)
		var elite := enemy.scene_file_path.contains("Hunter") or enemy.scene_file_path.contains("Heavy")
		enemy.loot_table_path = ENEMY_TABLE_ELITE if elite else ENEMY_TABLE_REGULAR
