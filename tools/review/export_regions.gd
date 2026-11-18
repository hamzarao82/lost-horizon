extends Node
## Runner for RegionExport: visits every region through the Inspector's world and writes one GLB per region plus a
## regions.json (file, size, triangle count, bounds, what was left out, and every labelled object) into LH_REGION_DIR.
## Headless works (nothing is rendered). The hub's update-holo.ps1 runs it.
##   LH_REGION_DIR=<folder> godot --headless --path <game> res://tools/review/export_regions.tscn

signal finished

## Tests turn this off so they can read the results; the hub run leaves it on and the process exits.
var quit_when_done: bool = true
var out_dir: String = ""
var regions: Array[Dictionary] = []


func _ready() -> void:
	out_dir = OS.get_environment("LH_REGION_DIR").replace("\\", "/").rstrip("/")
	if out_dir == "":
		push_error("LH_REGION_DIR is not set")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var insp := (load("res://tools/review/inspector.tscn") as PackedScene).instantiate()
	add_child(insp)
	var waited := 0
	while insp.camera == null and waited < 1200:
		await get_tree().process_frame
		waited += 1
	await get_tree().process_frame
	for rid: StringName in insp.REGION_IDS:
		await insp.travel_to(rid)
		for i in 8:
			await get_tree().process_frame
		var built := RegionExport.build(insp.main_node)
		var root := built["root"] as Node3D
		var file := "%s.glb" % rid
		var err := RegionExport.write(root, "%s/%s" % [out_dir, file])
		root.free()
		var bytes := 0
		if err == OK:
			bytes = FileAccess.get_file_as_bytes("%s/%s" % [out_dir, file]).size()
		regions.append({"id": String(rid), "file": file, "ok": err == OK, "error": error_string(err) if err != OK else "", "bytes": bytes,
				"bounds": built["bounds"], "report": built["report"], "objects": insp.collect_objects()})
		print("REGION %s: %s, %d KB, %d tris, %d meshes" % [rid, "ok" if err == OK else error_string(err), bytes / 1024, int(built["report"]["tris"]), int(built["report"]["meshes"])])
	var f := FileAccess.open("%s/regions.json" % out_dir, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"regions": regions}, "\t"))
		f.close()
	finished.emit()
	if quit_when_done:
		get_tree().quit(0)
