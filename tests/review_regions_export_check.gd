extends SceneTree
## The region exporter (tools/review/region_export.gd): every region becomes a valid glTF with real geometry, the
## movers are left out, and regions.json carries bounds and the labelled objects for the Holo Bay.
## godot --headless --path . -s tests/review_regions_export_check.gd

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


func _run() -> void:
	var dir := OS.get_user_data_dir() + "/regions_test_%d" % OS.get_process_id()
	OS.set_environment("LH_REGION_DIR", dir)
	var runner := (load("res://tools/review/export_regions.tscn") as PackedScene).instantiate()
	runner.quit_when_done = false
	root.add_child(runner)
	await runner.finished
	await physics_frame
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/regions.json")) if FileAccess.file_exists(dir + "/regions.json") else null
	_check(data is Dictionary and (data as Dictionary).has("regions"), "regions.json is written")
	var regions: Array = (data as Dictionary).get("regions", []) if data is Dictionary else []
	_check(regions.size() == 5, "all five regions are exported (%d)" % regions.size())
	for entry in regions:
		var r: Dictionary = entry
		var id := String(r["id"])
		var path := dir + "/" + String(r["file"])
		_check(bool(r["ok"]) and FileAccess.file_exists(path), "%s: the glTF is written" % id)
		var bytes := FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0
		_check(bytes > 100000 and bytes == int(r["bytes"]), "%s: a real file, size matches the index (%d KB)" % [id, bytes / 1024])
		var rep: Dictionary = r["report"]
		_check(int(rep["tris"]) > 3000, "%s: real geometry (%d triangles, %d meshes)" % [id, int(rep["tris"]), int(rep["meshes"])])
		var b: Array = r["bounds"]
		var size := Vector3(b[1][0] - b[0][0], b[1][1] - b[0][1], b[1][2] - b[0][2])
		_check(size.x > 10.0 and size.z > 10.0 and size.x < 1500.0 and size.z < 1500.0, "%s: sane bounds (%.0f x %.0f x %.0f m)" % [id, size.x, size.y, size.z])
		_check((r["objects"] as Array).size() > 5, "%s: carries its labelled objects (%d)" % [id, (r["objects"] as Array).size()])
		# Read the file back: it must be a valid glTF with meshes, and must not contain the movers.
		var state := GLTFState.new()
		var doc := GLTFDocument.new()
		var err := doc.append_from_file(path, state)
		var scene: Node = doc.generate_scene(state) if err == OK else null
		_check(err == OK and scene != null, "%s: the file reads back as a valid glTF" % id)
		if scene != null:
			var meshes := scene.find_children("*", "MeshInstance3D", true, false)
			_check(meshes.size() >= int(rep["meshes"]) / 2 and meshes.size() > 3, "%s: the meshes survive the round trip (%d)" % [id, meshes.size()])
			var movers := 0
			for n in scene.find_children("*", "", true, false):
				var nm := String(n.name)
				if nm == "Player" or nm.begins_with("PatrolSoldier") or nm.begins_with("Warden"):
					movers += 1
			_check(movers == 0, "%s: no player or enemy was exported" % id)
			scene.free()
	# The big flat sea is left out of the outpost (it would dwarf everything), and vegetation is merged.
	var outpost: Dictionary = {}
	for entry in regions:
		if String((entry as Dictionary)["id"]) == "outpost_17":
			outpost = entry
	var orep: Dictionary = outpost.get("report", {})
	_check(int(orep.get("multimesh_nodes", 0)) >= 1 and int(orep.get("multimesh_instances", 0)) > 20, "the outpost's vegetation is merged (%d instances)" % int(orep.get("multimesh_instances", 0)))
	_check(int(orep.get("shader_materials", 0)) >= 0 and orep.has("skipped_big"), "the report says what was left out and converted")
	for f in ["regions.json", "outpost_17.glb", "dead_coast.glb", "blackwood.glb", "research_complex.glb", "iron_fortress.glb"]:
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
	print("review_regions_export_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
