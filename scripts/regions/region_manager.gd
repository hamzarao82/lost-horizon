extends Node
## Autoload "RegionManager": one region in the tree at a time, travel between them, per-region saved state.
##
## Outpost 17 is built inside Main (assembled in code), so it cannot be freed and rebuilt cheaply. When the
## player leaves it, its nodes are detached from Main (out of the tree: no physics, no rendering, no timers)
## and kept for the return trip; every other region is a scene that is freed when the player leaves.
## Main itself (player, HUD, menus, sky and sun) stays. See docs/REGION_FRAMEWORK.md.

signal region_changed(old_id: StringName, new_id: StringName)
signal travel_refused(region_id: StringName, reason: String)

const OUTPOST_ID: StringName = &"outpost_17"
## Set this meta on a node that must survive leaving Outpost 17 (Main's own services).
const PERSISTENT_META: StringName = &"region_persistent"
const RESTORE_WAIT_FRAMES: int = 4

var current_region_id: StringName = OUTPOST_ID
var unlocked: Array[String] = ["outpost_17"]
## region id -> {"ids": {claimed id: true}, "custom": Dictionary from Region.capture_state()}
var states: Dictionary = {}
## Where a freshly loaded Main must go next: {"current": String, "position": [x, y, z] (optional)}.
var pending_restore: Dictionary = {}
var fade_time: float = 0.25
var busy: bool = false

var _container: Node3D
var _outpost_nodes: Array[Node] = []
var _stub: Region
var _exits: Array[Node] = []
var _layer: CanvasLayer
var _veil: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		fade_time = 0.0
	get_tree().node_added.connect(_on_node_added)
	var flow := CampaignFlow.new()  # unlock chain, road gate, bridge quest and hand-off lines
	flow.name = "CampaignFlow"
	add_child(flow)


# --- container (Main) ------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is Node3D and node.name == &"Main" and node.has_node(^"Outpost17"):
		_register_container(node as Node3D)


func _register_container(main: Node3D) -> void:
	_free_orphans()
	_container = main
	current_region_id = OUTPOST_ID
	_stub = null
	_exits.clear()
	main.tree_exiting.connect(_on_container_exiting.bind(main), CONNECT_ONE_SHOT)
	_after_container_ready.call_deferred()


func _on_container_exiting(main: Node3D) -> void:
	if main != _container:
		return
	_free_orphans()
	_container = null
	_stub = null
	_exits.clear()


func _free_orphans() -> void:
	for node in _outpost_nodes:
		if is_instance_valid(node) and not node.is_inside_tree():
			node.free()
	_outpost_nodes.clear()


func _after_container_ready() -> void:
	if _container == null or not is_instance_valid(_container):
		return
	_spawn_exits(OUTPOST_ID)
	if pending_restore.is_empty():
		return
	var restore := pending_restore
	pending_restore = {}
	var target := StringName(str(restore.get("current", "")))
	if target == OUTPOST_ID or not RegionStore.is_known(target):
		return
	for i in RESTORE_WAIT_FRAMES:
		await get_tree().process_frame  # the player's own setup and checkpoint placement finish first
	var position: Variant = RegionStore._position(restore.get("position", null))
	await travel(target, &"", position, true)


# --- unlocking -------------------------------------------------------------

func is_unlocked(region_id: StringName) -> bool:
	var data := RegionStore.load_data(region_id)
	if data == null:
		return false
	if unlocked.has(String(region_id)):
		return true
	if data.unlock_flag != &"" and _world_has(data.unlock_flag):
		unlocked.append(String(region_id))
		return true
	return false


func unlock(region_id: StringName) -> void:
	if RegionStore.is_known(region_id) and not unlocked.has(String(region_id)):
		unlocked.append(String(region_id))


func refuse(region_id: StringName) -> void:
	travel_refused.emit(region_id, "locked")
	var data := RegionStore.load_data(region_id)
	var name := data.display_name if data else String(region_id)
	var quests := get_node_or_null("/root/QuestManager")
	if quests != null and quests.has_method("say"):
		var custom := CampaignFlow.refusal_text(region_id)
		quests.say(custom if custom != "" else "%s is not reachable yet." % name, 3.0)


func _world_has(flag: StringName) -> bool:
	var world := get_node_or_null("/root/WorldState")
	return world != null and world.has_flag(flag)


# --- travel ----------------------------------------------------------------

## Moves the player to another region. Returns true if the player ended up there.
func travel(region_id: StringName, entry_id: StringName = &"", position_override: Variant = null, instant: bool = false) -> bool:
	if busy or _container == null or not is_instance_valid(_container):
		return false
	var data := RegionStore.load_data(region_id)
	if data == null:
		travel_refused.emit(region_id, "unknown region")
		return false
	if region_id == current_region_id:
		return false
	if not is_unlocked(region_id):
		refuse(region_id)
		return false
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		return false
	var packed: PackedScene = null
	if data.scene_path != "":
		packed = await _load_scene(data.scene_path)
		if packed == null:
			travel_refused.emit(region_id, "scene failed to load")
			return false
	busy = true
	if not instant:
		await _fade(1.0)
	if not is_instance_valid(_container):
		busy = false
		return false
	var old := current_region_id
	_save_current_state()
	_unload_current()
	if region_id == OUTPOST_ID:
		_reattach_outpost()
	else:
		var region := packed.instantiate() as Region
		if region == null:
			busy = false
			return false
		region.region_id = region_id
		region.position = Vector3.ZERO  # set before add_child: nothing overlaps the player at the origin
		_container.add_child(region)
		_stub = region
		region.restore_state((states.get(String(region_id), {}) as Dictionary).get("custom", {}))
		region.enter(entry_id if entry_id != &"" else data.default_entry())
	current_region_id = region_id
	_place_player(player, data, entry_id, position_override)
	_spawn_exits(region_id)
	_apply_presets(data)
	busy = false
	region_changed.emit(old, region_id)
	if not instant:
		await _fade(0.0)
	return true


func _load_scene(path: String) -> PackedScene:
	if OS.has_feature("web"):
		return load(path) as PackedScene  # single-threaded export: a plain load, the scene is small
	if ResourceLoader.load_threaded_request(path) != OK:
		return load(path) as PackedScene
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	return ResourceLoader.load_threaded_get(path) as PackedScene


func _place_player(player: Player, data: RegionData, entry_id: StringName, position_override: Variant) -> void:
	var target: Transform3D = data.entry_transform(entry_id)
	if position_override is Vector3:
		target.origin = position_override
	player.global_transform = target
	player.velocity = Vector3.ZERO


func _is_persistent(node: Node) -> bool:
	return node is Player or node is CanvasLayer or node is Control or node is WorldEnvironment \
			or node is DirectionalLight3D or node.has_meta(PERSISTENT_META)


func _unload_current() -> void:
	for exit in _exits:
		if is_instance_valid(exit):
			exit.get_parent().remove_child(exit)
			exit.queue_free()
	_exits.clear()
	if current_region_id == OUTPOST_ID:
		for child in _container.get_children():
			if not _is_persistent(child):
				_container.remove_child(child)
				_outpost_nodes.append(child)
	elif _stub != null and is_instance_valid(_stub):
		_stub.get_parent().remove_child(_stub)
		_stub.queue_free()
	_stub = null


func _reattach_outpost() -> void:
	for node in _outpost_nodes:
		if is_instance_valid(node):
			_container.add_child(node)
	_outpost_nodes.clear()


func _spawn_exits(region_id: StringName) -> void:
	var data := RegionStore.load_data(region_id)
	if data == null or _container == null:
		return
	for exit_id in data.exit_points:
		var spec: Variant = data.exit_points[exit_id]
		if not spec is Dictionary:
			continue
		var exit := RegionExit.new()
		exit.name = "Exit_%s" % String(exit_id)
		exit.exit_id = exit_id
		exit.target_region = StringName(str(spec.get("target_region", "")))
		exit.target_entry = StringName(str(spec.get("target_entry", "")))
		exit.size = spec.get("size", Vector3(8.0, 3.0, 2.0))
		exit.position = spec.get("position", Vector3.ZERO)  # set before add_child
		_container.add_child(exit)
		_exits.append(exit)


func _apply_presets(data: RegionData) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("set_region_ambience"):
		audio.call("set_region_ambience", data.ambience)


func _fade(target_alpha: float) -> void:
	if fade_time <= 0.0:
		return
	if _layer == null:
		_layer = CanvasLayer.new()
		_layer.layer = 90
		_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		_veil = ColorRect.new()
		_veil.color = Color.BLACK
		_veil.modulate.a = 0.0
		_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
		_layer.add_child(_veil)
		add_child(_layer)
	var tween := create_tween()
	tween.tween_property(_veil, "modulate:a", target_alpha, fade_time)
	await tween.finished


# --- per-region state and persistent ids ------------------------------------

func _state_for(region_id: StringName) -> Dictionary:
	var key := String(region_id)
	if not states.has(key) or not states[key] is Dictionary:
		states[key] = {"ids": {}, "custom": {}}
	return states[key]


func _save_current_state() -> void:
	if _stub != null and is_instance_valid(_stub):
		_state_for(current_region_id)["custom"] = _stub.capture_state()


## True the first time `id` is claimed in this region, false ever after (also after save and load).
func claim(region_id: StringName, id: StringName) -> bool:
	if not RegionStore.is_known(region_id) or String(id).is_empty() or String(id).length() > RegionStore.MAX_ID_LENGTH:
		return false
	var ids: Dictionary = _state_for(region_id)["ids"]
	if ids.has(String(id)):
		return false
	ids[String(id)] = true
	return true


func is_claimed(region_id: StringName, id: StringName) -> bool:
	return (_state_for(region_id)["ids"] as Dictionary).has(String(id))


func claimed_count(region_id: StringName) -> int:
	return (_state_for(region_id)["ids"] as Dictionary).size()


# --- saving ----------------------------------------------------------------

func to_dict() -> Dictionary:
	_save_current_state()
	var out := {
		"current": String(current_region_id),
		"states": states.duplicate(true),
		"unlocked": unlocked.duplicate(),
	}
	if current_region_id != OUTPOST_ID:
		var player := get_tree().get_first_node_in_group("player") as Player
		if player != null:
			var p := player.global_position
			out["position"] = [p.x, p.y, p.z]
	return out


## Applies a (sanitised) `regions` section. The region switch itself happens once the next Main is up.
func from_dict(raw: Variant) -> void:
	var clean := RegionStore.sanitize(raw)
	states = clean["states"]
	unlocked.clear()
	for id in clean["unlocked"]:
		unlocked.append(str(id))
	pending_restore = {}
	if clean["current"] != String(OUTPOST_ID):
		pending_restore = {"current": clean["current"]}
		if clean.has("position"):
			pending_restore["position"] = clean["position"]


func reset() -> void:
	current_region_id = OUTPOST_ID
	unlocked = ["outpost_17"]
	states = {}
	pending_restore = {}
