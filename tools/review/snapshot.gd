extends Node
## Review snapshot: for every region, screenshots (a clean overview, a labelled overview and one per named spot or
## entry point) plus a list of every labelled object, written to the folder in LH_SNAPSHOT_DIR. The hub's
## update-hub.ps1 runs this (windowed: headless runs cannot take screenshots) and wraps the result in a snapshot.
## Development tool: tools/* is excluded from release builds.
##   LH_SNAPSHOT_DIR=<folder> godot --path <game> --resolution 1280x720 res://tools/review/snapshot.tscn
##
## Output: shots/<region>__<name>.png, shots.json, objects.json {region: [object]}, stats.json {region: {category: n}}.

signal finished

const SHOT_FRAMES: int = 8

## Tests turn this off so they can read the results; the hub run leaves it on and the process exits.
var quit_when_done: bool = true
var out_dir: String = ""
var shots: Array[Dictionary] = []
var objects: Dictionary = {}
var stats: Dictionary = {}
var _headless: bool = DisplayServer.get_name() == "headless"


func _ready() -> void:
	out_dir = OS.get_environment("LH_SNAPSHOT_DIR").replace("\\", "/").rstrip("/")
	if out_dir == "":
		push_error("LH_SNAPSHOT_DIR is not set")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _slug(text: String) -> String:
	var s := text.to_lower()
	var out := ""
	for i in s.length():
		var c := s[i]
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_")


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(insp: Node, region: String, label: String, from: Vector3, look_at_pos: Vector3) -> void:
	insp._place_camera(from, look_at_pos)
	await _frames(SHOT_FRAMES)
	if _headless:
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return
	var file := "%s__%s.png" % [region, _slug(label)]
	if image.save_png("%s/shots/%s" % [out_dir, file]) == OK:
		shots.append({"file": file, "region": region, "name": label})


func _set_labels(insp: Node, on: bool) -> void:
	for cat in insp.CATEGORIES:
		insp._set_category_visible(cat, on)


func _overview_pose(region: StringName) -> Array[Vector3]:
	if region == &"outpost_17":
		return [Vector3(0.0, 120.0, 130.0), Vector3(0.0, 0.0, -5.0)]
	var data := RegionStore.load_data(region)
	var ext := Rect2(-50.0, -50.0, 100.0, 100.0)
	if data != null:
		ext = data.map_extents
	var c := ext.get_center()
	var size := maxf(ext.size.x, ext.size.y)
	return [Vector3(c.x, size * 0.55, c.y + size * 0.7), Vector3(c.x, 0.0, c.y)]


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir + "/shots")
	var insp := (load("res://tools/review/inspector.tscn") as PackedScene).instantiate()
	add_child(insp)
	var waited := 0
	while insp.camera == null and waited < 1200:
		await get_tree().process_frame
		waited += 1
	await _frames(20)
	insp._ui.visible = false
	for rid: StringName in insp.REGION_IDS:
		await insp.travel_to(rid)
		await _frames(12)
		var region := String(rid)
		objects[region] = insp.collect_objects()
		stats[region] = insp.marker_counts.duplicate()
		_set_labels(insp, false)
		var pose := _overview_pose(rid)
		insp.set_overview_mode(true)
		await _shot(insp, region, "overview", pose[0], pose[1])
		_set_labels(insp, true)
		await _shot(insp, region, "overview labels", pose[0], pose[1])
		insp.set_overview_mode(false)
		_set_labels(insp, false)
		for spot in insp._spots:
			var pos: Vector3 = spot["pos"]
			await _shot(insp, region, String(spot["name"]), pos + Vector3(0.0, 14.0, 20.0), pos)
		print("SNAPSHOT region %s: %d objects, %d shots so far" % [region, (objects[region] as Array).size(), shots.size()])
	_write_json("shots.json", shots)
	_write_json("objects.json", objects)
	_write_json("stats.json", stats)
	print("SNAPSHOT done: %d shots, %d regions -> %s" % [shots.size(), objects.size(), out_dir])
	finished.emit()
	if quit_when_done:
		get_tree().quit(0)


func _write_json(name: String, data: Variant) -> void:
	var f := FileAccess.open("%s/%s" % [out_dir, name], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
