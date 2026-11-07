class_name DeadCoastContent
extends RefCounted
## Interactables, story documents, caches, the gate and the patrol groups of the Dead Coast.
## Every persistent thing has an id starting with "dead_coast_" (underscores only: WorldState drops saved flags with other characters or over 48) so its world flag carries the region name
## (crate -> "<id>_taken", document -> "doc_<id>_found", patrol -> "patrol_<id>_cleared").

const ENEMY_SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const ENEMY_ELITE: String = "res://scenes/enemies/HunterElite.tscn"
const ENEMY_HEAVY: String = "res://scenes/enemies/HeavySoldier.tscn"

var root: Node3D
var props: DeadCoastProps
## id -> node (documents, terminals, crates, doors) and PatrolGroup id -> group
var nodes: Dictionary = {}
var patrols: Dictionary = {}
var crate_ids: Array[String] = []
var document_ids: Array[String] = []


func _init(parent: Node3D, props_builder: DeadCoastProps) -> void:
	root = parent
	props = props_builder


func _ground(d: float, z: float, lift: float = 0.0) -> Vector3:
	return DeadCoastTerrain.ground(d, z, lift)


func _register(item: Node3D, id: String, pos: Vector3, why: String, radius: float = 2.5) -> void:
	item.position = pos
	root.add_child(item)
	nodes[id] = item
	props.placed.append({"kind": "interactable", "name": id, "pos": pos, "radius": radius, "why": why, "solid": false})


func doc(id: String, title: String, text: String, d: float, z: float, why: String, lift: float = 0.8) -> LoreDocument:
	var item := LoreDocument.new()
	item.name = id.replace(".", "_")
	item.title = title
	item.body_text = text
	item.interaction_id = StringName(id)
	_register(item, id, _ground(d, z, lift), why)
	document_ids.append(id)
	return item


func terminal(id: String, title: String, pages: Array, d: float, z: float, why: String, finish_flag: String = "", requires: String = "", locked_text: String = "") -> Terminal:
	var item := Terminal.new()
	item.name = id.replace(".", "_")
	item.terminal_title = title
	item.pages = PackedStringArray(pages)
	item.finish_flag = StringName(finish_flag)
	item.requires_flag = StringName(requires)
	item.locked_text = locked_text
	item.interaction_id = StringName(id)
	_register(item, id, _ground(d, z, 0.6), why)
	return item


func crate(id: String, loot: Array, d: float, z: float, why: String, table: String = "res://resources/loot/dead_coast_cache.tres") -> SupplyCrate:
	var item := SupplyCrate.new()
	item.name = id.replace(".", "_")
	item.crate_id = StringName(id)
	var paths := PackedStringArray()
	for entry in loot:
		paths.append("res://resources/items/%s.tres" % entry)
	item.loot_paths = paths
	item.bonus_table_path = table
	_register(item, id, _ground(d, z), why, 2.0)
	props.collider(id.replace(".", "_") + "_body", _ground(d, z, 0.4), Vector3(1.1, 0.8, 0.85))
	crate_ids.append(id)
	return item


func checkpoint(id: String, d: float, z: float) -> Checkpoint:
	var item := Checkpoint.new()
	item.name = id
	item.interaction_id = StringName(id)
	_register(item, id, _ground(d, z, 0.8), "rest point with a save: %s" % id)
	props.collider(id + "_post", _ground(d, z, 0.8), Vector3(0.5, 1.6, 0.5))
	return item


func gate(id: String, d: float, z: float, width: float, flag: String, reason: String) -> Door:
	var door := Door.new()
	door.name = "Door_" + id
	door.door_id = StringName(id)
	door.width = width
	door.locked_by_flag = StringName(flag)
	door.lock_reason = reason
	door.position = _ground(d, z)
	root.add_child(door)
	nodes[id] = door
	props.placed.append({"kind": "gate", "name": id, "pos": door.position, "radius": width * 0.5, "why": "the checkpoint barrier spans the whole corridor", "solid": true})
	return door


func patrol(id: String, area: String, scenes: Array, route: Array, loop: bool = true) -> PatrolGroup:
	var group := PatrolGroup.new()
	group.name = "Patrol_" + id.replace(".", "_")
	group.group_id = StringName(id)
	group.area_id = StringName(area)
	group.scene_paths = PackedStringArray(scenes)
	var points := PackedVector3Array()
	for p in route:
		points.append(_ground((p as Vector2).x, (p as Vector2).y, 0.1))
	group.route_points = points
	group.loop = loop
	root.add_child(group)
	patrols[id] = group
	return group


# --- the whole content set ----------------------------------------------------

func build() -> void:
	_beach()
	_trail_and_camp()
	_checkpoint_area()
	_cove()
	_watchpoint()
	_depot()
	_exit()


func _beach() -> void:
	props.freighter(3.0, -30.0)
	props.kit("boat_wreck", _ground(5.0, -8.0), 0.9, 1.0, true, "lifeboat torn off the freighter: its locker was left shut")
	props.kit("crate", _ground(8.0, -5.0), 0.4, 1.0, true, "crates the crew dragged ashore")
	props.kit("barrel", _ground(10.5, -3.5), 0.0, 1.0, true, "fuel drum")
	props.kit("sandbag_stack", _ground(23.0, 15.0), 3.14, 1.0, true, "the first sandbag nest: someone expected a landing here")
	checkpoint("checkpoint_dead_coast_1", 20.0, 4.0)
	doc("dead_coast_wreck_hull", "Freighter hull",
		"The name on the stern is half gone: CALLOWAY. Salt has eaten the paint but not the stencils on the crates in the hold: 'SEALED - NOT FOR INSPECTION - BS'.",
		8.5, -28.0, "the breach in the hull: where the investigation begins")
	terminal("dead_coast_radio_wreck", "Ship radio",
		["Static, then a looping voice: 'Calloway, Calloway, cargo sealed, do not board, repeat do not board.'",
		"A second voice cuts in, flat and tired: 'Relay Seventeen acknowledges. Proceed on schedule.'"],
		3.0, -24.0, "the ship's radio: the survivor's last transmission and the first mention of the relay")
	doc("dead_coast_log_wreck_manifest", "Cargo manifest",
		"Consignment 4 of 9. Forty sealed containers, 'medical stores', consigned to the island garrison. Weight does not match the declared contents. Receiving officer: Outpost 17.",
		9.0, -6.0, "the manifest: evidence of a military shipment", 1.4)
	doc("dead_coast_data_device", "Data device",
		"A ruggedised drive taped under a bunk. Most of it is encrypted. The header is readable: SHIPPING LEDGER, BLACKWOOD ROUTE, SIGNED R. HALE.",
		1.0, -37.5, "the data device in the stern: the mission's hard objective")
	crate("dead_coast_cache_wreck", ["bandage", "credits_small"], 4.0, -10.5, "lifeboat locker: optional supplies")
	patrol("dead_coast_beach", "dc_wreckage_beach", [ENEMY_SOLDIER, ENEMY_SOLDIER],
		[Vector2(16.0, -12.0), Vector2(16.0, -26.0), Vector2(16.0, -44.0)], false)
	props.crane(2.0, -84.0)  # a dock crane stands at the trail's midpoint: the first sign that this was a loading coast


func _trail_and_camp() -> void:
	props.kit("truck_wreck", _ground(7.0, -62.0), 0.7, 1.0, true, "the cargo truck the patrol left on the road, doors open")
	props.kit("barricade_concrete", _ground(19.0, -52.0), 1.57, 1.0, true, "road block: cover for the first firefight")
	props.kit("barricade_concrete", _ground(8.0, -75.0), 1.57, 1.0, true, "second road block, facing north")
	# Raider camp: optional, off the trail on a flat shelf.
	props.kit("tent", _ground(30.0, -66.0), 0.4, 1.0, true, "the raiders' tent: they moved into the abandoned patrol point")
	props.kit("hut_small", _ground(30.0, -78.0), 3.14, 1.0, true, "a lean-to the raiders built from the truck's cargo boards")
	props.decor_box(_ground(30.0, -72.0, 0.15), Vector3(1.0, 0.3, 1.0), Color(0.25, 0.1, 0.05))
	props.decor_box(_ground(30.0, -72.0, 0.6), Vector3(0.45, 0.5, 0.45), Color(0.95, 0.5, 0.15))  # the fire
	var camp_trigger := AreaTrigger.new()
	camp_trigger.name = "Trigger_dc_camp"
	camp_trigger.area_id = &"dc_camp"
	camp_trigger.size = Vector3(22.0, 10.0, 22.0)
	camp_trigger.position = _ground(28.0, -72.0, 3.0)
	root.add_child(camp_trigger)
	nodes["trigger_dc_camp"] = camp_trigger
	crate("dead_coast_cache_camp", ["coastal_alloy", "sharpening_oil"], 33.0, -71.0, "the raiders' stash: optional camp reward")
	patrol("dead_coast_camp", "dc_camp", [ENEMY_SOLDIER, ENEMY_SOLDIER],
		[Vector2(27.0, -68.0), Vector2(33.0, -76.0)], true)
	checkpoint("checkpoint_dead_coast_2", 20.0, -96.0)


func _checkpoint_area() -> void:
	# Sandbag chicane south of the gate, booth and guardhouse beside it.
	for i in 3:
		props.kit("sandbag_stack", _ground(18.0 + i * 5.0, -112.0), 1.57, 1.0, true, "sandbag wall along the inspection lane")
	props.kit("fence_wire", _ground(-1.0, -118.0), 1.57, 1.0, false, "wire along the sea wall so nobody wades round the gate")
	props.kit("hut_olive", _ground(23.0, -108.0), 3.14, 1.0, true, "the guardhouse")
	props.kit("watchtower", _ground(28.0, -118.0), 3.14, 1.0, true, "gate tower: its floodlights point at the empty road")
	props.solid("Booth", _ground(6.0, -108.0, 1.4), Vector3(4.0, 2.8, 3.0), Color(0.46, 0.44, 0.4), 0.0, "inspection booth: the security terminal lives here")
	terminal("dead_coast_checkpoint_terminal", "Checkpoint terminal",
		["GATE 2 LOG. Last entries: 'Order 114: stand down all inspections.' 'Order 115: leave the road open.' 'Order 116: guards to the fence line, do not respond to the coast.'",
		"Barrier control: locked. A guard pass is required."],
		6.0, -105.4, "the checkpoint security terminal")
	props.decor_box(_ground(9.4, -106.0, 0.6), Vector3(0.12, 1.2, 0.12), Color(0.3, 0.21, 0.14))  # the notice post the orders are pinned to
	doc("dead_coast_log_checkpoint_orders", "Posted orders",
		"Taped to the booth glass: TRUCKS WITH BS STENCIL PASS WITHOUT INSPECTION. NO RECORDS. NO QUESTIONS. - Commander's office, Outpost 17.",
		9.4, -106.0, "why the checkpoint was abandoned: it was ordered blind", 1.2)
	terminal("dead_coast_guard_pass", "Guard pass locker",
		["Inside, a laminated pass on a lanyard. You take it. The barrier will open for it."],
		21.5, -105.0, "the guard pass: opens the coastal route", "dead_coast_route_pass")
	crate("dead_coast_cache_guardhouse", ["armor_patch", "bandage"], 25.5, -111.0, "guardhouse locker: optional")
	gate("dc_gate", 3.0, -118.0, 12.0, "dead_coast_route_pass", "Barrier locked: a guard pass is required")
	checkpoint("checkpoint_dead_coast_3", 20.0, -130.0)
	patrol("dead_coast_checkpoint", "dc_checkpoint", [ENEMY_HEAVY, ENEMY_SOLDIER, ENEMY_ELITE],
		[Vector2(8.0, -100.0), Vector2(18.0, -103.0), Vector2(14.0, -112.0)], true)


func _cove() -> void:
	doc("dead_coast_trail_markers", "Drag marks",
		"Parallel runner scars lead north from the gate. Between them, painted on the stones: BS 4 / 9 and an arrow.",
		12.0, -134.0, "the shipment's trail: mission 3 starts here")
	props.kit("boat_wreck", _ground(8.0, -156.0), 2.4, 1.0, true, "smugglers' boat, hauled out and abandoned")
	props.kit("boat_wreck", _ground(2.0, -178.0), 0.3, 1.0, true, "second hull, used as a roof")
	props.kit("hut_small", _ground(24.0, -180.0), 1.57, 1.0, true, "the smugglers' shack: their ledger and the black stencil")
	props.kit("container_red", _ground(26.0, -158.0), 0.2, 1.0, true, "a stripped container on the cove's north shelf")
	props.kit("container_green", _ground(26.5, -166.0), 0.0, 1.0, true, "its twin: empty")
	props.kit("sandbag_corner", _ground(18.0, -150.0), 0.4, 1.0, true, "smugglers' firing position")
	props.crane(-2.0, -170.0)
	props.pier(-3.0, -176.0, 21.0)
	props.pier(-3.0, -163.0, 15.0)
	crate("dead_coast_cargo_a", ["coastal_alloy", "credits_small"], 9.0, -153.0, "hidden container A: behind the boat (cargo objective)")
	crate("dead_coast_cargo_b", ["bandage", "scrap_metal"], 6.0, -172.0, "hidden container B: under the second hull")
	crate("dead_coast_cargo_c", ["coastal_alloy"], 18.0, -163.0, "hidden container C: in the rock shadow")
	doc("dead_coast_cargo_gear", "Sealed equipment case",
		"A watertight case with the stencil BS 4. Inside: coils of fibre optic, two ruggedised relays, a tag reading 'REPLACEMENT PARTS - GHOST NODE'.",
		20.0, -169.0, "the mission-critical equipment", 0.9)
	doc("dead_coast_log_cove_ledger", "Smugglers' ledger",
		"Eleven drops this season. Nobody asked for names, only counts. The uniformed ones pay double to be forgotten.",
		17.0, -150.5, "the cove's trade: the locals were paid to look away")
	doc("dead_coast_log_black_site_link", "Consignment sheet",
		"BS 4 / 9. Contents: LIVE FEED, RESTRAINTS, SEDATIVES. Destination: Outpost 17, then inland. Authorised: The Director. Note in the margin: 'Project Black Site cannot lose another batch.'",
		23.0, -177.0, "the Project Black Site connection: no more than a name and a pattern", 1.0)
	checkpoint("checkpoint_dead_coast_4", 21.0, -146.0)
	patrol("dead_coast_cove", "dc_cove", [ENEMY_SOLDIER, ENEMY_ELITE],
		[Vector2(14.0, -154.0), Vector2(16.0, -168.0), Vector2(14.0, -182.0)], true)


func _watchpoint() -> void:
	props.lighthouse(52.0, -150.0)
	props.kit("sandbag_corner", _ground(46.0, -146.0), 0.8, 1.0, true, "the watch crew's firing step")
	props.kit("radio_mast", _ground(60.0, -160.0), 0.0, 1.0, true, "the watch's mast, its dish pointed inland")
	props.kit("barrel", _ground(44.0, -160.0), 0.0, 1.0, true, "water barrel")
	crate("dead_coast_cache_watch", ["armor_plate", "credits_small"], 56.0, -142.0, "the watch's emergency locker: reward for the climb")
	doc("dead_coast_log_watch_journal", "Watch sergeant's journal",
		"Third night this week: lights in the Blackwood, then a sound I won't write down. Command says it is wind. I am sending the boys home before I tell them what wind sounds like.",
		50.0, -158.0, "the watchpoint journal: foreshadows the Blackwood", 1.0)
	patrol("dead_coast_watch", "dc_watchpoint", [ENEMY_ELITE],
		[Vector2(46.0, -148.0), Vector2(60.0, -156.0)], true)


func _depot() -> void:
	# The cleft is closed by two rocks with a 3 m gap (z -188.5 .. -185.5 stays open).
	props.kit("rocks_a", _ground(26.0, -193.0), 0.3, 2.2, true, "rock fall that hides the cleft from the cove")
	props.kit("rocks_b", _ground(26.0, -181.0), 1.0, 2.0, true, "second rock: the gap between them is the way in")
	props.kit("container_blue", _ground(44.0, -190.0), 0.0, 1.0, true, "depot container: opened and emptied")
	props.kit("container_red", _ground(55.0, -196.0), 1.57, 1.0, true, "depot container: still sealed")
	props.kit("crate", _ground(50.0, -183.0), 0.2, 1.0, true, "depot crates")
	props.kit("generator", _ground(58.0, -182.0), 3.14, 1.0, true, "the depot's generator: why the lights still hum")
	crate("dead_coast_cache_depot_a", ["combat_helmet", "credits_medium"], 47.0, -198.0, "depot cache A", "res://resources/loot/dead_coast_depot.tres")
	crate("dead_coast_cache_depot_b", ["armor_plate"], 59.0, -190.0, "depot cache B", "res://resources/loot/dead_coast_depot.tres")
	crate("dead_coast_depot_vault", ["tide_charm", "upgrade_kit_armor"], 53.0, -190.0, "the vault: the unique exploration reward", "res://resources/loot/dead_coast_depot.tres")
	doc("dead_coast_log_depot_inventory", "Depot inventory",
		"Supplies for fifty for six months, none of it issued. The depot was built by people who expected the coast to be held. Nobody came back to hold it.",
		44.0, -186.5, "the depot's inventory: nobody was meant to find it", 1.0)
	patrol("dead_coast_depot", "dc_depot", [ENEMY_HEAVY, ENEMY_SOLDIER],
		[Vector2(44.0, -184.0), Vector2(54.0, -196.0), Vector2(48.0, -190.0)], true)


func _exit() -> void:
	props.kit("fence_wire", _ground(9.0, -216.0), 1.57, 1.0, false, "the fence the exit trail runs through")
	props.kit("sign_outpost_17", _ground(22.0, -214.0), 3.14, 1.0, true, "trail sign: Blackwood, military access only")
	props.kit("barricade_wire", _ground(30.0, -218.0), 1.57, 1.0, true, "the last barricade, pulled open for the trucks")
	props.kit("sandbag_stack", _ground(8.0, -208.0), 0.0, 1.0, true, "sandbag post at the exit")
	checkpoint("checkpoint_dead_coast_5", 20.0, -204.0)
