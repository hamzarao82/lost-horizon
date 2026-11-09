extends SceneTree
## The main menu says which build is running.
## godot --headless --path . -s tests/build_label_check.gd

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _run() -> void:
	_check(BuildInfo.LABEL != "", "BuildInfo has a label (%s)" % BuildInfo.LABEL)
	var menu := MainMenu.new()
	root.add_child(menu)
	for i in 4:
		await physics_frame
	var label := menu.find_child("BuildLabel", true, false) as Label
	_check(label != null, "the main menu has a build label")
	if label != null:
		_check(label.text == BuildInfo.LABEL, "it shows the build info text")
		_check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "it never blocks a click")
		_check(label.get_global_rect().position.x < 40.0, "it sits at the left edge")
	print("build_label_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
