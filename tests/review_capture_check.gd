extends SceneTree
## Headless check for the review capture lists (tools/review/capture_ui.gd and capture_fx.gd). It takes NO
## screenshots: it checks that the lists are complete, unique, file-safe and buildable.
##   godot --headless --path . -s tests/review_capture_check.gd
## Exits non-zero on failure.

const CAPTURE_UI: String = "res://tools/review/capture_ui.gd"
const CAPTURE_FX: String = "res://tools/review/capture_fx.gd"
const ID_PATTERN: String = "^[a-z0-9_]+$"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			out.append(dir_path + "/" + file_name)
	out.sort()
	return out


func _run() -> void:
	var ui_script := load(CAPTURE_UI) as GDScript
	var fx_script := load(CAPTURE_FX) as GDScript
	_check(ui_script != null, "capture_ui.gd loads")
	_check(fx_script != null, "capture_fx.gd loads")
	if ui_script == null or fx_script == null:
		print("\n%d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	var ui_consts := ui_script.get_script_constant_map()
	var fx_consts := fx_script.get_script_constant_map()

	_test_ui(ui_consts)
	_test_fx(fx_consts)

	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_ui(consts: Dictionary) -> void:
	print("UI screens (capture_ui.gd)")
	var screens: Array = consts["SCREENS"]
	var excluded: Dictionary = consts["EXCLUDED"]
	_check(screens.size() >= 30, "at least 30 screens are listed (%d)" % screens.size())

	var seen: Dictionary = {}
	var regex := RegEx.new()
	regex.compile(ID_PATTERN)
	var script_paths: Dictionary = {}
	for entry: Dictionary in screens:
		var id: String = entry["id"]
		_check(not seen.has(id), "ui id is unique: %s" % id)
		_check(regex.search(id) != null, "ui id is file-safe: %s" % id)
		_check(String(entry.get("name", "")) != "", "ui %s has a name" % id)
		seen[id] = true
		var path: String = entry["script"]
		_check(FileAccess.file_exists(path), "ui %s: script exists (%s)" % [id, path])
		script_paths[path] = true

	# Every screen script must build headless when it is a Node (a CanvasLayer or Control screen).
	for path: String in script_paths.keys():
		var script := load(path) as GDScript
		if script == null:
			_check(false, "ui script loads: %s" % path)
			continue
		var base := script.get_instance_base_type()
		if not ClassDB.is_parent_class(base, "Node") and base != &"Node":
			continue
		var instance = script.new()
		_check(instance is Node, "ui script builds headless: %s" % path.get_file())
		if instance is Node:
			(instance as Node).free()

	# Completeness: every script in scripts/ui and scripts/story is a screen here or excluded with a reason.
	for folder in ["res://scripts/ui", "res://scripts/story"]:
		for file_path in _gd_files(folder):
			var covered := script_paths.has(file_path) or excluded.has(file_path)
			_check(covered, "ui coverage: %s is a screen or excluded with a reason" % file_path.get_file())
	for path: String in excluded.keys():
		_check(FileAccess.file_exists(path), "excluded file exists: %s" % path.get_file())
		_check(String(excluded[path]).length() > 10, "excluded %s has a reason" % path.get_file())
		_check(not script_paths.has(path), "excluded %s is not also a screen" % path.get_file())


func _test_fx(consts: Dictionary) -> void:
	print("Effects (capture_fx.gd)")
	var effects: Array = consts["EFFECTS"]
	var skipped: Array = consts["SKIPPED"]
	var frame_times: Array = consts["FRAME_TIMES"]
	_check(effects.size() >= 15, "at least 15 effects are listed (%d)" % effects.size())
	_check(frame_times.size() == 4, "four frames per effect")
	var ascending := true
	for i in range(1, frame_times.size()):
		ascending = ascending and float(frame_times[i]) > float(frame_times[i - 1])
	_check(ascending and float(frame_times[0]) == 0.0, "frame times start at 0 and rise")

	var seen: Dictionary = {}
	var regex := RegEx.new()
	regex.compile(ID_PATTERN)
	var sources: Dictionary = {}
	for group in [effects, skipped]:
		for entry: Dictionary in group:
			var id: String = entry["id"]
			_check(not seen.has(id), "fx id is unique: %s" % id)
			_check(regex.search(id) != null, "fx id is file-safe: %s" % id)
			_check(String(entry.get("name", "")) != "", "fx %s has a name" % id)
			var source: String = entry["source"]
			_check(FileAccess.file_exists(source), "fx %s: source exists (%s)" % [id, source.get_file()])
			seen[id] = true
			sources[source] = true
	for skip: Dictionary in skipped:
		_check(String(skip["reason"]).length() > 10, "skipped fx %s has a reason" % skip["id"])

	# Completeness: every effect script in scripts/fx is captured or skipped with a reason.
	for file_path in _gd_files("res://scripts/fx"):
		_check(sources.has(file_path), "fx coverage: %s is captured or skipped" % file_path.get_file())
