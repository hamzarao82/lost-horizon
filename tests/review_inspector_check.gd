extends SceneTree
## The review inspector (tools/review/inspector.gd, a development tool): loads the real world, visits every region,
## labels what matters, shows collision, saves pins as JSON, never touches the real save, and is excluded from
## release builds. godot --headless --path . -s tests/review_inspector_check.gd

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _real_save_fingerprint() -> String:
	var path := OS.get_environment("APPDATA").replace("\\", "/") + "/Godot/app_userdata/Lost Horizon/save_slot_1.json"
	if not FileAccess.file_exists(path):
		return "none"
	return "%d:%d" % [FileAccess.get_file_as_bytes(path).size(), FileAccess.get_modified_time(path)]


func _total_markers(insp: Node) -> int:
	var total := 0
	for cat in insp.marker_counts:
		total += int(insp.marker_counts[cat])
	return total


func _run() -> void:
	var save_before := _real_save_fingerprint()
	var temp_dir := OS.get_user_data_dir() + "/review_test_%d" % OS.get_process_id()
	OS.set_environment("LH_REVIEW_DATA", temp_dir)

	var insp := (load("res://tools/review/inspector.tscn") as PackedScene).instantiate()
	root.add_child(insp)
	var waited := 0
	while insp.camera == null and waited < 600:
		await physics_frame
		waited += 1
	await _frames(15)
	_check(insp.camera != null and is_instance_valid(insp.main_node), "the inspector loads the real world (%d frames)" % waited)
	_check(root.get_node("SaveManager").test_mode and root.get_node("SaveManager").save_path().contains("save_test_"),
			"it forces save test mode: writes go to a throwaway file")
	_check(insp.review_data_dir == temp_dir.replace("\\", "/"), "the pin folder comes from LH_REVIEW_DATA")

	# Outpost 17 has things worth labelling.
	_check(insp.region_id == &"outpost_17", "it starts in Outpost 17")
	# Outpost 17 spawns its enemies when the player approaches (patrol groups, the arena, the boss), so at load the
	# labelled encounters are the patrol groups; the other regions place their enemies up front.
	_check(int(insp.marker_counts.get("patrols", 0)) > 0, "Outpost 17: patrol groups (the future encounters) are labelled (%d)" % int(insp.marker_counts.get("patrols", 0)))
	_check(int(insp.marker_counts.get("interactables", 0)) + int(insp.marker_counts.get("doors", 0)) > 0, "Outpost 17: interactables and doors are labelled")
	_check(_total_markers(insp) > 10, "Outpost 17: a useful number of labels (%d)" % _total_markers(insp))
	_check(insp._spots.size() >= 8, "the area list has the four areas and the named spots (%d)" % insp._spots.size())
	for enemy in get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			_check(not (enemy as Node).is_physics_processing(), "enemies are frozen by default")
			break

	# Every other region can be visited and gets labels.
	for rid: StringName in [&"dead_coast", &"blackwood", &"research_complex", &"iron_fortress"]:
		await insp.travel_to(rid)
		await _frames(4)
		_check(insp.region_id == rid, "%s can be visited" % rid)
		_check(_total_markers(insp) > 0, "%s has labels (%d)" % [rid, _total_markers(insp)])
		_check(insp._spots.size() >= 1, "%s has jump spots (%d)" % [rid, insp._spots.size()])

	# Collision overlay on and off.
	await insp.travel_to(&"outpost_17")
	await _frames(4)
	insp._set_collision_visible(true)
	_check(insp._collision_meshes.size() > 20, "the collision overlay draws shapes (%d)" % insp._collision_meshes.size())
	insp._set_collision_visible(false)
	_check(insp._collision_meshes.is_empty(), "and turns off again")

	# Selection and pins.
	var enemies := get_nodes_in_group("enemies")
	var target: Node = null
	for e in enemies:
		if is_instance_valid(e) and (e as Node).is_inside_tree():
			target = e
			break
	_check(target != null, "there is an enemy to select")
	if target != null:
		insp.select_node(target)
		_check(String(insp.selected.get("class", "")) != "" and String(insp.selected.get("object_id", "")) != "", "selecting records its class and id")
	var pin_id: String = await insp.save_pin("change", "high", "Test note: this looks repetitive.\nSecond line.")
	_check(pin_id.begins_with("PIN-"), "a pin gets an id (%s)" % pin_id)
	var pin_path := temp_dir + "/pins/" + pin_id + ".json"
	_check(FileAccess.file_exists(pin_path), "the pin JSON is written to the review-data folder")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pin_path)) if FileAccess.file_exists(pin_path) else null
	_check(parsed is Dictionary, "the pin file is valid JSON")
	if parsed is Dictionary:
		var pin: Dictionary = parsed
		_check(pin.get("decision") == "change" and pin.get("priority") == "high" and pin.get("status") == "open", "decision, priority and status are saved")
		_check(String(pin.get("observation", "")).begins_with("Test note"), "the note is saved")
		_check(String(pin.get("title", "")) == "Test note: this looks repetitive.", "the title is the first line of the note")
		_check((pin.get("target") as Dictionary).get("region") == "outpost_17", "the target region is saved")
		_check(String(pin.get("game_build", "")).begins_with("build"), "the game build stamp is saved (%s)" % pin.get("game_build"))
		_check(pin.get("camera") is Dictionary and (pin["camera"] as Dictionary).has("position"), "the camera position is saved")

	# Safety: the real save is untouched, and tools/ never ships.
	_check(_real_save_fingerprint() == save_before, "the real save file is untouched")
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	var excludes := 0
	var all_exclude_tools := true
	for line in presets.split("\n"):
		if line.begins_with("exclude_filter="):
			excludes += 1
			if not line.contains("tools/*"):
				all_exclude_tools = false
	_check(excludes >= 1 and all_exclude_tools, "every export preset excludes tools/* (%d presets)" % excludes)

	# Clean up the throwaway pins.
	for sub in ["pins", "shots"]:
		var d := DirAccess.open(temp_dir + "/" + sub)
		if d != null:
			for f in d.get_files():
				d.remove(f)
			DirAccess.remove_absolute(temp_dir + "/" + sub)
	DirAccess.remove_absolute(temp_dir)

	print("review_inspector_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
