extends Node
## Review Inspector: a development tool for LOOKING at the game (it is never shipped: export_presets.cfg excludes
## tools/*). Free-fly camera over the real, running world, a region and area selector, labels for the things that
## matter (enemies, pickups, interactables, doors, barrels, triggers, patrols), a collision overlay, click to
## select, screenshots, and Pins: a decision (keep / change / cut), a note and a screenshot saved as JSON into the
## Review Hub's review-data folder, for the next working session.
##
##   godot --path <game> res://tools/review/inspector.tscn      (the hub's "Open Inspector.bat" does this)
##
## Safety: SaveManager is forced into test mode first, so nothing here can touch the real save.

const REGION_IDS: Array[StringName] = [&"outpost_17", &"dead_coast", &"blackwood", &"research_complex", &"iron_fortress"]
const DEFAULT_REVIEW_DATA: String = "C:/Users/SCS/OneDrive/Documents/GitHub/lost-horizon-review-hub/review-data"
const MAX_MARKERS_PER_CATEGORY: int = 400
const LABEL_RANGE: float = 85.0
const CATEGORIES: Dictionary = {
	"enemies": {"label": "Enemies", "color": Color(1.0, 0.38, 0.32)},
	"pickups": {"label": "Pickups", "color": Color(0.45, 0.95, 0.5)},
	"interactables": {"label": "Interactables", "color": Color(0.4, 0.85, 1.0)},
	"doors": {"label": "Doors", "color": Color(1.0, 0.75, 0.3)},
	"barrels": {"label": "Barrels", "color": Color(1.0, 0.55, 0.2)},
	"triggers": {"label": "Triggers", "color": Color(0.9, 0.5, 1.0)},
	"patrols": {"label": "Patrol groups", "color": Color(0.95, 0.95, 0.5)},
}
const DECISIONS: Array[String] = ["change", "keep", "cut"]
const PRIORITIES: Array[String] = ["normal", "high", "low"]
## Named spots in Outpost 17 beyond the four area centres (x, z).
const OUTPOST_SPOTS: Dictionary = {
	"Compound entrance (sign)": Vector2(-6.0, 36.0),
	"Perimeter gate (crank)": Vector2(4.6, 46.0),
	"Door C to D (boss door)": Vector2(0.0, -62.0),
	"Payment store (hidden room)": Vector2(-18.5, -87.0),
}

var main_node: Node3D
var camera: Camera3D
var region_id: StringName = &"outpost_17"
var markers_root: Node3D
var marker_counts: Dictionary = {}
var selected: Dictionary = {}
var review_data_dir: String = ""

var _fly_speed: float = 14.0
var _yaw: float = 0.0
var _pitch: float = -0.6
var _toggles: Dictionary = {}
var _fog_before: Dictionary = {}
var _marker_nodes: Dictionary = {}  # category -> Array[{label, node}]
var _collision_meshes: Array[MeshInstance3D] = []
var _collision_on: bool = false
var _freeze_enemies: bool = true
var _busy: bool = false
var _ui: CanvasLayer
var _panel: PanelContainer
var _region_pick: OptionButton
var _area_pick: OptionButton
var _info: Label
var _counts: Label
var _status: Label
var _note: TextEdit
var _decision_pick: OptionButton
var _priority_pick: OptionButton
var _help_visible: bool = true
var _spots: Array[Dictionary] = []


func _ready() -> void:
	Player.require_mouse_capture = false
	HitStop.enabled = false
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null:
		save_manager.test_mode = true  # first of all: nothing below may touch the real save file
	var quests := get_node_or_null("/root/QuestManager")
	if quests != null:
		quests.intro_done = true  # no opening cutscene over the inspection
	_resolve_review_dir()
	_build_ui()
	_boot_world.call_deferred()


func _resolve_review_dir() -> void:
	var from_env := OS.get_environment("LH_REVIEW_DATA")
	review_data_dir = from_env if from_env != "" else DEFAULT_REVIEW_DATA
	review_data_dir = review_data_dir.replace("\\", "/").rstrip("/")


func _boot_world() -> void:
	main_node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate() as Node3D
	var waves := main_node.get_node_or_null("WaveManager")
	if waves != null:
		waves.autostart = false
	add_child(main_node)
	for i in 12:
		await get_tree().physics_frame
	camera = Camera3D.new()
	camera.name = "InspectorCamera"
	camera.far = 1800.0
	camera.fov = 70.0
	camera.near = 0.1
	add_child(camera)
	camera.make_current()
	var player := get_tree().get_first_node_in_group("player") as Player
	if player != null:
		player.set_physics_process(false)  # the player stays as a scale reference, but nothing moves it
		player.set_process(false)
		player.set_process_input(false)
		player.set_process_unhandled_input(false)
	_set_game_hud_visible(false)
	await _after_region_change(true)
	_set_status("Ready. Right mouse + WASD to fly, left click to select.")


func _set_game_hud_visible(on: bool) -> void:
	for node in main_node.find_children("*", "CanvasLayer", true, false):
		(node as CanvasLayer).visible = on


# --- region and area -------------------------------------------------------------

func travel_to(id: StringName) -> void:
	if _busy:
		return
	_busy = true
	var rm := get_node_or_null("/root/RegionManager")
	if rm != null:
		for rid in REGION_IDS:
			if not rm.unlocked.has(String(rid)):
				rm.unlocked.append(String(rid))
		if id != rm.current_region_id:
			await rm.travel(id, &"", null, true)
	_busy = false
	await _after_region_change(false)


func _after_region_change(first: bool) -> void:
	for i in 10:
		await get_tree().physics_frame
	var rm := get_node_or_null("/root/RegionManager")
	region_id = rm.current_region_id if rm != null else &"outpost_17"
	if is_instance_valid(_region_pick) and REGION_IDS.has(region_id):
		_region_pick.select(REGION_IDS.find(region_id))
	if is_instance_valid(camera):
		camera.make_current()
	_apply_enemy_freeze()
	_set_game_hud_visible(false)
	_collect_markers()
	if _collision_on:
		_set_collision_visible(true)
	_fill_area_list()
	var player := get_tree().get_first_node_in_group("player") as Player
	if player != null:
		_place_camera(player.global_position + Vector3(0.0, 16.0, 22.0), player.global_position)
	if is_instance_valid(_region_pick) and not first:
		_set_status("Region: %s" % region_id)


func _fill_area_list() -> void:
	_spots.clear()
	_area_pick.clear()
	_area_pick.add_item("Jump to...")
	if region_id == &"outpost_17":
		var areas: Dictionary = Outpost17.AREAS
		for id in areas:
			var rect: Rect2 = areas[id]["rect"]
			_spots.append({"name": String(areas[id]["name"]), "pos": Vector3(rect.get_center().x, 0.0, rect.get_center().y)})
		for spot in OUTPOST_SPOTS:
			var v: Vector2 = OUTPOST_SPOTS[spot]
			_spots.append({"name": spot, "pos": Vector3(v.x, 0.0, v.y)})
	else:
		var data := RegionStore.load_data(region_id)
		if data != null:
			for entry in data.entry_points:
				var xf: Transform3D = data.entry_points[entry]
				_spots.append({"name": "Entry: %s" % entry, "pos": xf.origin})
	for spot in _spots:
		_area_pick.add_item(spot["name"])


func _place_camera(from: Vector3, look_at_pos: Vector3) -> void:
	camera.global_position = from
	var dir := (look_at_pos - from).normalized()
	_yaw = atan2(-dir.x, -dir.z)
	_pitch = asin(clampf(dir.y, -1.0, 1.0))
	_apply_camera_rotation()


func _apply_camera_rotation() -> void:
	camera.rotation = Vector3(_pitch, _yaw, 0.0)


func _apply_enemy_freeze() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.set_physics_process(not _freeze_enemies)


# --- markers ---------------------------------------------------------------------

func _category_of(node: Node) -> String:
	if node is Enemy:
		return "enemies"
	if node is Pickup:
		return "pickups"
	if node is Door:
		return "doors"
	if node is Interactable:
		return "interactables"
	if node is ExplosiveBarrel:
		return "barrels"
	if node is AreaTrigger or node is OutpostSign:
		return "triggers"
	if node is PatrolGroup:
		return "patrols"
	return ""


func script_name_of(node: Node) -> String:
	var script := node.get_script() as Script
	if script != null and script.get_global_name() != &"":
		return String(script.get_global_name())
	return node.get_class()


func object_id_of(node: Node) -> String:
	for prop in ["interaction_id", "door_id", "barrel_id", "group_id", "area_id"]:
		var v: Variant = node.get(prop)
		if v != null and String(v) != "":
			return String(v)
	if node is Pickup and (node as Pickup).item != null:
		return "pickup." + String((node as Pickup).item.item_id)
	return String(node.name)


func _label_text(node: Node, category: String) -> String:
	match category:
		"enemies":
			var enemy := node as Enemy
			return "%s%s" % [enemy.display_name, "  [BOSS]" if enemy.is_in_group("boss") else ""]
		"pickups":
			var pickup := node as Pickup
			return pickup.item.display_name if pickup.item != null else "pickup"
	return "%s: %s" % [script_name_of(node), object_id_of(node)]


func _collect_markers() -> void:
	if is_instance_valid(markers_root):
		markers_root.queue_free()
	markers_root = Node3D.new()
	markers_root.name = "InspectorMarkers"
	add_child(markers_root)
	_marker_nodes.clear()
	marker_counts.clear()
	for cat in CATEGORIES:
		_marker_nodes[cat] = []
		marker_counts[cat] = 0
	for node in main_node.find_children("*", "Node3D", true, false):
		var cat := _category_of(node)
		if cat == "":
			continue
		marker_counts[cat] += 1
		if (_marker_nodes[cat] as Array).size() >= MAX_MARKERS_PER_CATEGORY:
			continue
		var label := Label3D.new()
		label.text = _label_text(node, cat)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0009
		label.font_size = 24
		label.outline_size = 8
		label.visibility_range_end = LABEL_RANGE
		label.visibility_range_end_margin = 30.0
		label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		label.modulate = CATEGORIES[cat]["color"]
		label.visible = bool(_toggles.get(cat, true))
		markers_root.add_child(label)
		label.global_position = (node as Node3D).global_position + Vector3(0.0, 2.3, 0.0)
		(_marker_nodes[cat] as Array).append({"label": label, "node": node})
	_update_counts()


## For high overview shots: no fog (it washes a whole region out from above) and labels visible at any distance.
## Ground-level views keep the fog and the distance fade, because that is what the player sees.
func set_overview_mode(on: bool) -> void:
	for cat in _marker_nodes:
		for entry in _marker_nodes[cat]:
			if is_instance_valid(entry["label"]):
				(entry["label"] as Label3D).visibility_range_end = 0.0 if on else LABEL_RANGE
	for node in main_node.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env == null:
			continue
		var key := str(env.get_instance_id())
		if on:
			if not _fog_before.has(key):
				_fog_before[key] = env.fog_enabled
			env.fog_enabled = false
		elif _fog_before.has(key):
			env.fog_enabled = bool(_fog_before[key])
	if not on:
		_fog_before.clear()


## Every labelled object of the current region (not capped like the on-screen labels): the data behind snapshots
## and behind the hub's "this pin's object changed or went missing" check.
func collect_objects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node in main_node.find_children("*", "Node3D", true, false):
		var cat := _category_of(node)
		if cat == "":
			continue
		var p := (node as Node3D).global_position
		out.append({"id": object_id_of(node), "class": script_name_of(node), "category": cat, "name": String(node.name),
				"position": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]})
	return out


func _update_counts() -> void:
	var parts: Array[String] = []
	for cat in CATEGORIES:
		parts.append("%s %d" % [CATEGORIES[cat]["label"], int(marker_counts.get(cat, 0))])
	if is_instance_valid(_counts):
		_counts.text = "%s  |  %s" % [region_id, "  ".join(parts)]


func _set_category_visible(cat: String, on: bool) -> void:
	_toggles[cat] = on
	for entry in _marker_nodes.get(cat, []):
		if is_instance_valid(entry["label"]):
			(entry["label"] as Label3D).visible = on


# --- collision overlay -----------------------------------------------------------

func _set_collision_visible(on: bool) -> void:
	_collision_on = on
	for mesh in _collision_meshes:
		if is_instance_valid(mesh):
			mesh.queue_free()
	_collision_meshes.clear()
	if not on:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.9, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	for node in main_node.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node.shape == null or shape_node.disabled or shape_node.get_parent() is CharacterBody3D:
			continue
		var debug_mesh := shape_node.shape.get_debug_mesh()
		if debug_mesh == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = debug_mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shape_node.add_child(mi)
		_collision_meshes.append(mi)


# --- selection -------------------------------------------------------------------

func _meaningful_owner(node: Node) -> Node:
	var n := node
	while n != null and n != main_node:
		if _category_of(n) != "":
			return n
		n = n.get_parent()
	return node


func select_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		selected = {}
		_info.text = "Nothing selected. Left click an object."
		return
	var pos := Vector3.ZERO
	if node is Node3D:
		pos = (node as Node3D).global_position
	var groups: Array[String] = []
	for g in node.get_groups():
		if not String(g).begins_with("_"):
			groups.append(String(g))
	selected = {
		"name": String(node.name),
		"class": script_name_of(node),
		"object_id": object_id_of(node),
		"path": String(main_node.get_path_to(node)) if main_node.is_ancestor_of(node) else String(node.get_path()),
		"region": String(region_id),
		"position": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
		"groups": groups,
	}
	_info.text = "%s\nclass: %s\nid: %s\nregion: %s   pos: %.1f, %.1f, %.1f\ngroups: %s" % [
			selected["name"], selected["class"], selected["object_id"], selected["region"], pos.x, pos.y, pos.z, ", ".join(groups)]


func _pick_at(screen_pos: Vector2) -> void:
	# Labelled things first (they are not always solid), then whatever the ray hits.
	var best: Node = null
	var best_dist: float = 28.0
	for cat in _marker_nodes:
		for entry in _marker_nodes[cat]:
			var label := entry["label"] as Label3D
			if not is_instance_valid(label) or not label.visible or camera.is_position_behind(label.global_position):
				continue
			var d := camera.unproject_position(label.global_position).distance_to(screen_pos)
			if d < best_dist:
				best_dist = d
				best = entry["node"]
	if best != null:
		select_node(best)
		return
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 600.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	var hit := main_node.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		select_node(null)
		return
	select_node(_meaningful_owner(hit["collider"] as Node))


# --- screenshots and pins --------------------------------------------------------

func _stamp() -> String:
	return Time.get_datetime_string_from_system(false).replace("-", "").replace(":", "").replace("T", "-")


func _capture(path: String) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	_ui.visible = false
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_ui.visible = true
	if image == null or image.is_empty():
		return false
	return image.save_png(path) == OK


func take_screenshot() -> String:
	DirAccess.make_dir_recursive_absolute(review_data_dir + "/shots")
	var name := "SHOT-%s.png" % _stamp()
	var ok: bool = await _capture(review_data_dir + "/shots/" + name)
	_set_status("Screenshot saved: %s" % name if ok else "Screenshot not available here.")
	return name if ok else ""


func save_pin(decision: String, priority: String, note: String) -> String:
	DirAccess.make_dir_recursive_absolute(review_data_dir + "/pins")
	DirAccess.make_dir_recursive_absolute(review_data_dir + "/shots")
	var id := "PIN-%s-%03d" % [_stamp(), randi() % 1000]
	var shot_name := id + ".png"
	var shot_ok: bool = await _capture(review_data_dir + "/shots/" + shot_name)
	var title := note.strip_edges().split("\n")[0]
	if title.length() > 70:
		title = title.substr(0, 70) + "..."
	var target: Dictionary = selected.duplicate(true) if not selected.is_empty() else {"name": "(view)", "region": String(region_id)}
	if not target.has("region"):
		target["region"] = String(region_id)
	var cam_pos := camera.global_position
	var pin := {
		"id": id,
		"title": title if title != "" else String(target.get("name", id)),
		"status": "open",
		"decision": decision,
		"priority": priority,
		"observation": note.strip_edges(),
		"target": target,
		"camera": {"position": [snappedf(cam_pos.x, 0.01), snappedf(cam_pos.y, 0.01), snappedf(cam_pos.z, 0.01)],
				"yaw": snappedf(_yaw, 0.001), "pitch": snappedf(_pitch, 0.001)},
		"screenshot": shot_name if shot_ok else "",
		"game_build": BuildInfo.LABEL,
		"created": Time.get_datetime_string_from_system(false),
		"acceptance_criteria": [],
	}
	var f := FileAccess.open(review_data_dir + "/pins/" + id + ".json", FileAccess.WRITE)
	if f == null:
		_set_status("Could not write the pin (check %s)." % review_data_dir)
		return ""
	f.store_string(JSON.stringify(pin, "\t"))
	f.close()
	_set_status("Pinned %s (%s)." % [id, decision])
	return id


# --- input and flying ------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mb.pressed else Input.MOUSE_MODE_VISIBLE
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_pick_at(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_fly_speed = minf(_fly_speed * 1.25, 200.0)
			_set_status("Fly speed %.0f" % _fly_speed)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_fly_speed = maxf(_fly_speed / 1.25, 1.0)
			_set_status("Fly speed %.0f" % _fly_speed)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.003
		_pitch = clampf(_pitch - mm.relative.y * 0.003, -1.5, 1.5)
		_apply_camera_rotation()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_F1:
			_help_visible = not _help_visible
			_panel.visible = _help_visible


func _process(delta: float) -> void:
	if camera == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var move := Vector3.ZERO
	var basis := camera.global_transform.basis
	if Input.is_key_pressed(KEY_W):
		move -= basis.z
	if Input.is_key_pressed(KEY_S):
		move += basis.z
	if Input.is_key_pressed(KEY_A):
		move -= basis.x
	if Input.is_key_pressed(KEY_D):
		move += basis.x
	if Input.is_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		move -= Vector3.UP
	if move.length_squared() > 0.0:
		var speed := _fly_speed * (4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		camera.global_position += move.normalized() * speed * delta


# --- UI --------------------------------------------------------------------------

func _set_status(text: String) -> void:
	if is_instance_valid(_status):
		_status.text = text


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 400
	add_child(_ui)
	_panel = PanelContainer.new()
	_panel.position = Vector2(12.0, 12.0)
	_panel.custom_minimum_size = Vector2(330.0, 0.0)
	var panel_theme := Theme.new()
	panel_theme.default_font_size = 14
	_panel.theme = panel_theme
	_panel.modulate.a = 0.93
	_ui.add_child(_panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var title := Label.new()
	title.text = "REVIEW INSPECTOR   %s" % BuildInfo.LABEL
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 0.95))
	box.add_child(title)

	_region_pick = OptionButton.new()
	for rid in REGION_IDS:
		_region_pick.add_item(String(rid))
	_region_pick.item_selected.connect(func(i: int) -> void: travel_to(REGION_IDS[i]))
	box.add_child(_region_pick)
	_area_pick = OptionButton.new()
	_area_pick.add_item("Jump to...")
	_area_pick.item_selected.connect(_on_area_selected)
	box.add_child(_area_pick)

	var toggles_box := GridContainer.new()
	toggles_box.columns = 2
	box.add_child(toggles_box)
	for cat in CATEGORIES:
		_toggles[cat] = true
		var cb := CheckBox.new()
		cb.text = CATEGORIES[cat]["label"]
		cb.button_pressed = true
		cb.toggled.connect(func(on: bool) -> void: _set_category_visible(cat, on))
		toggles_box.add_child(cb)
	var coll := CheckBox.new()
	coll.text = "Collision"
	coll.toggled.connect(func(on: bool) -> void: _set_collision_visible(on))
	toggles_box.add_child(coll)
	var freeze := CheckBox.new()
	freeze.text = "Freeze enemies"
	freeze.button_pressed = true
	freeze.toggled.connect(func(on: bool) -> void:
		_freeze_enemies = on
		_apply_enemy_freeze())
	toggles_box.add_child(freeze)
	var hud := CheckBox.new()
	hud.text = "Game HUD"
	hud.toggled.connect(func(on: bool) -> void: _set_game_hud_visible(on))
	toggles_box.add_child(hud)

	_counts = Label.new()
	_counts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_counts.custom_minimum_size = Vector2(340.0, 0.0)
	box.add_child(_counts)
	_info = Label.new()
	_info.text = "Nothing selected. Left click an object."
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(340.0, 0.0)
	box.add_child(_info)

	var pin_row := HBoxContainer.new()
	box.add_child(pin_row)
	_decision_pick = OptionButton.new()
	for d in DECISIONS:
		_decision_pick.add_item(d)
	pin_row.add_child(_decision_pick)
	_priority_pick = OptionButton.new()
	for p in PRIORITIES:
		_priority_pick.add_item(p)
	pin_row.add_child(_priority_pick)
	_note = TextEdit.new()
	_note.placeholder_text = "What do you see? What should change?"
	_note.custom_minimum_size = Vector2(340.0, 70.0)
	_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(_note)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var pin_btn := Button.new()
	pin_btn.text = "Pin"
	pin_btn.pressed.connect(_on_pin_pressed)
	buttons.add_child(pin_btn)
	var shot_btn := Button.new()
	shot_btn.text = "Screenshot"
	shot_btn.pressed.connect(func() -> void: take_screenshot())
	buttons.add_child(shot_btn)

	_status = Label.new()
	_status.text = "Loading the world..."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(340.0, 0.0)
	box.add_child(_status)
	var help := Label.new()
	help.text = "RMB + WASD fly  |  Q / E down / up  |  Shift fast  |  wheel speed  |  LMB select  |  F1 hide panel\nOutpost 17 spawns enemies when you get close in the real game: its patrol groups mark where."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(340.0, 0.0)
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	box.add_child(help)


func _on_area_selected(index: int) -> void:
	if index <= 0 or index > _spots.size():
		return
	var pos: Vector3 = _spots[index - 1]["pos"]
	_place_camera(pos + Vector3(0.0, 14.0, 20.0), pos)
	_area_pick.select(0)


func _on_pin_pressed() -> void:
	await save_pin(DECISIONS[_decision_pick.selected], PRIORITIES[_priority_pick.selected], _note.text)
	_note.text = ""
