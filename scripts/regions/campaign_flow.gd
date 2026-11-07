class_name CampaignFlow
extends Node
## Connective tissue between regions (Milestone 7): who unlocks whom, the Outpost 17 road gate, the
## bridge quest and the radio hand-off lines. Created by RegionManager (one line); holds no saved state of
## its own: everything it decides is a WorldState flag, so saving and loading cannot desync it.
##
## Flag names (the contract for the region content):
##   mission_first_signal_complete   set by QuestManager when The First Signal ends  -> unlocks Dead Coast
##   dead_coast_mission_3_complete   set by the Dead Coast content (mark_mission_complete)   -> unlocks Blackwood
##   blackwood_mission_3_complete    set by the Blackwood content                             -> unlocks the Research Complex
##   <region>_unlocked               derived here; RegionData.unlock_flag points at it
##   dead_coast_arrived              set on the first arrival; completes the bridge quest
## `<region>_region_complete` is accepted as an alias of `<region>_mission_3_complete`, and so are the content's
## own finish flags: `dead_coast_cargo_complete` (Dead Coast) and `blackwood_research_complex_access` (Blackwood).
## All ids use [a-z0-9_] and stay within 48 characters: WorldState drops anything else when it loads a save.

const OUTPOST: StringName = &"outpost_17"
const BRIDGE_QUEST: StringName = &"leave_outpost"
const MISSION_FLAG: StringName = &"mission_first_signal_complete"
const GATE_NAME: String = "CampaignGate"
const GATE_Z: float = 80.6  # just beyond the Outpost 17 exit trigger (z 77 to 79): the barricade shows why it is shut
const SYNC_DELAYS: Array[int] = [2, 40]  # frames after Main appears: a loaded save restores flags a little later

## region -> {after: flag that earns the unlock, aliases: other flags that count (the content's own finish flags), caption: said once when it unlocks}
const CHAIN: Dictionary = {
	&"dead_coast": {
		"after": &"mission_first_signal_complete",
		"aliases": [],
		"caption": "Radio: The signal repeats from the south, past the beach gate. The Dead Coast. The road is open.",
	},
	&"blackwood": {
		"after": &"dead_coast_mission_3_complete",
		"aliases": [&"dead_coast_region_complete", &"dead_coast_cargo_complete"],
		"caption": "Radio: The shipment's trail runs inland. Blackwood. Stay off the open road.",
	},
	&"research_complex": {
		"after": &"blackwood_mission_3_complete",
		"aliases": [&"blackwood_region_complete", &"blackwood_research_complex_access"],
		"caption": "Radio: Clearance code accepted. Access granted. Something is waiting at the end of the trail.",
	},
}
## Said once, the first time the player arrives.
const ARRIVAL: Dictionary = {
	&"dead_coast": "Radio: Wreckage everywhere. Someone shipped something here and never collected it.",
	&"blackwood": "Radio: Signal is weaker under the canopy. Keep your head down.",
	&"research_complex": "Radio: Whatever this place was, it was built to stay hidden.",
}
const REFUSAL: Dictionary = {
	&"dead_coast": "The road is blocked.",
	&"blackwood": "The trail into the Blackwood is grown shut. Finish what is on the coast first.",
	&"research_complex": "The facility gate is sealed. It needs a clearance code.",
}
const SAID_PREFIX: String = "campaign_said_"

var _world: Node
var _quests: Node
var _manager: Node
var _gate: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_manager = get_parent()
	if _manager != null and _manager.has_signal("region_changed"):
		_manager.region_changed.connect(_on_region_changed)
	get_tree().node_added.connect(_on_node_added)
	_bind.call_deferred()


func _bind() -> void:
	_world = get_node_or_null("/root/WorldState")
	_quests = get_node_or_null("/root/QuestManager")
	if _world != null and not _world.flag_changed.is_connected(_on_flag_changed):
		_world.flag_changed.connect(_on_flag_changed)
	if _quests != null and not _quests.quest_completed.is_connected(_on_quest_completed):
		_quests.quest_completed.connect(_on_quest_completed)
	sync()


# --- public ------------------------------------------------------------------

## Content calls this when a main mission of a region ends. n = 1..3. Returns true the first time.
## Mission 3 earns the next region's unlock (the unlock itself is derived in sync(), from the flag).
static func mark_mission_complete(region_id: StringName, n: int) -> bool:
	var world := _world_node()
	if world == null or n < 1:
		return false
	var flag := mission_flag(region_id, n)
	if world.has_flag(flag):
		return false
	world.set_flag(flag, true)
	return true


static func mission_flag(region_id: StringName, n: int) -> StringName:
	return StringName("%s_mission_%d_complete" % [region_id, n])


static func unlock_flag(region_id: StringName) -> StringName:
	return StringName("%s_unlocked" % region_id)


## Text shown when a locked exit is walked into. RegionManager asks before it falls back to a generic line.
static func refusal_text(region_id: StringName) -> String:
	return REFUSAL.get(region_id, "")


## Applies every rule to the flags as they are now. Safe to call at any time (idempotent): it only ever
## sets flags and starts the bridge quest; captions come out when a flag actually changes.
func sync() -> void:
	if _world == null:
		return
	for region in CHAIN:
		var rule: Dictionary = CHAIN[region]
		var earned: bool = _world.has_flag(rule["after"])
		for alias in rule["aliases"]:
			earned = earned or _world.has_flag(alias)
		if earned:
			_unlock(region)
	_update_bridge()
	_update_gate()


# --- reactions ---------------------------------------------------------------

func _on_flag_changed(id: StringName, value: bool) -> void:
	if value:
		sync()


func _on_quest_completed(quest_id: StringName) -> void:
	if quest_id == BRIDGE_QUEST and _quests != null:
		_quests.tracker_first = &""
	_update_bridge()


func _on_region_changed(_old: StringName, new_id: StringName) -> void:
	if new_id == &"dead_coast" and _world != null:
		_world.set_flag(&"dead_coast_arrived", true)  # completes the bridge quest through the normal flag event
	_say_once(new_id, ARRIVAL.get(new_id, ""))
	_update_gate()


func _unlock(region: StringName) -> void:
	var flag := unlock_flag(region)
	if _world.has_flag(flag):
		return
	_world.set_flag(flag, true)
	# A quiet delay keeps the line clear of the results screen, which pauses the game on mission end.
	_say_later(CHAIN[region]["caption"], 6.0 if region == &"dead_coast" else 1.0)


func _say_later(text: String, delay: float) -> void:
	if delay <= 0.0 or not is_inside_tree():
		_say(text)
		return
	get_tree().create_timer(delay, true).timeout.connect(_say.bind(text))


func _say(text: String) -> void:
	if _quests != null and _quests.has_method("say") and not text.is_empty():
		_quests.say(text, 4.5)


func _say_once(key: StringName, text: String) -> void:
	if text.is_empty() or _world == null:
		return
	var flag := StringName(SAID_PREFIX + String(key))
	if _world.has_flag(flag):
		return
	_world.set_flag(flag, true)
	_say(text)


# --- bridge quest ------------------------------------------------------------

func _update_bridge() -> void:
	if _quests == null or _world == null:
		return
	if _world.has_flag(MISSION_FLAG) and _quests.is_completed(&"first_signal"):
		_quests.start_quest(BRIDGE_QUEST)  # refused by the manager if already started or finished
	if _quests.is_active(BRIDGE_QUEST):
		if _quests.tracker_first != BRIDGE_QUEST:
			_quests.tracker_first = BRIDGE_QUEST
			_quests.tracker_changed.emit()
	elif _quests.tracker_first == BRIDGE_QUEST:
		_quests.tracker_first = &""
		_quests.tracker_changed.emit()


# --- the Outpost 17 road gate ------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is Node3D and node.name == &"Main" and node.has_node(^"Outpost17"):
		for frames in SYNC_DELAYS:
			_sync_after.call_deferred(frames)


func _sync_after(frames: int) -> void:
	for i in frames:
		if not is_inside_tree():
			return
		await get_tree().process_frame
	if _world == null:
		_bind()
	else:
		sync()


func _update_gate() -> void:
	var open: bool = _world != null and _world.has_flag(unlock_flag(&"dead_coast"))
	if open:
		if _gate != null and is_instance_valid(_gate):
			_gate.queue_free()
		_gate = null
		return
	# One gate per Main. It travels with the Outpost 17 nodes (detached while the player is away), so an
	# existing gate, attached or not, is never replaced, and none is built while another region is loaded.
	if _gate != null and is_instance_valid(_gate):
		return
	var main := _main()
	if main == null or _manager == null or _manager.get("current_region_id") != OUTPOST:
		return
	_gate = _build_gate()
	main.add_child(_gate)


func _main() -> Node3D:
	var container: Variant = _manager.get("_container") if _manager != null else null
	return container as Node3D if container is Node3D and is_instance_valid(container) else null


## A low barricade and a sign on the south edge of the beach, behind the exit trigger so walking up to it
## still shows the refusal caption. Removed once the road is open.
func _build_gate() -> Node3D:
	var gate := Node3D.new()
	gate.name = GATE_NAME
	gate.position = Vector3(0.0, 0.0, GATE_Z)  # set before add_child
	var body := StaticBody3D.new()
	body.name = "Barricade"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16.0, 1.4, 0.8)
	shape.shape = box
	shape.position = Vector3(0.0, 0.7, 0.0)
	body.add_child(shape)
	gate.add_child(body)
	var mesh := MeshInstance3D.new()
	var visual := BoxMesh.new()
	visual.size = box.size
	mesh.mesh = visual
	mesh.position = shape.position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.36, 0.12)
	material.roughness = 0.9
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.add_child(mesh)
	var sign_label := Label3D.new()
	sign_label.text = "ROAD CLOSED"
	sign_label.font_size = 96
	sign_label.pixel_size = 0.012
	sign_label.modulate = Color(1.0, 0.92, 0.7)
	sign_label.outline_modulate = Color(0.1, 0.05, 0.0)
	sign_label.position = Vector3(0.0, 0.8, -0.45)
	sign_label.rotation = Vector3(0.0, PI, 0.0)  # faces north, towards the player walking south
	gate.add_child(sign_label)
	return gate


static func _world_node() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("WorldState") if loop else null
