extends SceneTree
## Runner for HoloExport (the hub's update-holo.ps1 calls it headless):
##   LH_HOLO_DIR=<folder> godot --headless --path <game> -s tools/review/export_holo_data.gd
## Writes items.json, attacks.json and characters.json into the folder.

func _initialize() -> void:
	var dir := OS.get_environment("LH_HOLO_DIR").replace("\\", "/").rstrip("/")
	if dir == "":
		push_error("LH_HOLO_DIR is not set")
		quit(2)
		return
	var counts := HoloExport.export_all(dir)
	print("HOLO data written: ", counts, " -> ", dir)
	quit(0)
