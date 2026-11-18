extends SceneTree
## The review snapshot tool (tools/review/snapshot.gd): visits every region and writes the object list and the
## per-category counts that the hub's snapshots, comparison and stale-pin check rely on. Headless runs cannot take
## screenshots, so shots.json is empty here; the windowed run (update-hub.ps1) fills the images.
## godot --headless --path . -s tests/review_snapshot_check.gd

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


func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _run() -> void:
	var dir := OS.get_user_data_dir() + "/review_snapshot_test_%d" % OS.get_process_id()
	OS.set_environment("LH_SNAPSHOT_DIR", dir)
	var snap := (load("res://tools/review/snapshot.tscn") as PackedScene).instantiate()
	snap.quit_when_done = false
	root.add_child(snap)
	await snap.finished
	await physics_frame
	var objects: Variant = _read(dir + "/objects.json")
	var stats: Variant = _read(dir + "/stats.json")
	var shots: Variant = _read(dir + "/shots.json")
	_check(objects is Dictionary and (objects as Dictionary).size() == 5, "objects.json covers the five regions")
	_check(stats is Dictionary and (stats as Dictionary).size() == 5, "stats.json covers the five regions")
	_check(shots is Array, "shots.json is written (empty when headless: %d)" % (shots as Array).size() if shots is Array else 0)
	if objects is Dictionary:
		for region in objects:
			var list: Array = objects[region]
			_check(list.size() > 5, "%s lists its objects (%d)" % [region, list.size()])
			var first: Dictionary = list[0]
			_check(first.has("id") and first.has("class") and first.has("category") and first.has("position"), "%s objects carry id, class, category and position" % region)
		var outpost: Array = objects.get("outpost_17", [])
		var ids := {}
		for o in outpost:
			ids[String((o as Dictionary)["id"])] = true
		_check(ids.has("perimeter_crank") and ids.has("checkpoint_b"), "Outpost 17 includes known objects (the crank, checkpoint B)")
		_check(not (objects as Dictionary).has("") and (objects as Dictionary).has("iron_fortress"), "the last region, the Iron Fortress, was reached")
	if stats is Dictionary:
		var total := 0
		for region in stats:
			for cat in stats[region]:
				total += int(stats[region][cat])
		_check(total > 100, "the counts add up to a real world (%d labelled objects)" % total)
	# Ids must be stable between runs: Godot's auto-generated names ("@CharacterBody3D@37") change every time and
	# would show up as phantom added/removed objects when two snapshots are compared.
	var unstable := 0
	if objects is Dictionary:
		for region in objects:
			for o in objects[region]:
				if String((o as Dictionary)["id"]).contains("@"):
					unstable += 1
	_check(unstable == 0, "no object id carries an auto-generated '@' node name (%d found)" % unstable)
	# Clean up.
	for sub in ["shots"]:
		var d := DirAccess.open(dir + "/" + sub)
		if d != null:
			for f in d.get_files():
				d.remove(f)
			DirAccess.remove_absolute(dir + "/" + sub)
	for f in ["shots.json", "objects.json", "stats.json"]:
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
	print("review_snapshot_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
