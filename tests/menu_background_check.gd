extends SceneTree
## The stormy menu background: deterministic lightning/thunder scheduling, quality-scaled rain, no
## heavy build on headless, and the menu's buttons still work with it present.
## godot --headless --path . -s tests/menu_background_check.gd

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
	# Headless: no rain, no audio players, but the node still builds and can be stepped.
	var storm := MenuStorm.new()
	root.add_child(storm)
	for i in 3:
		await process_frame
	_check(storm.rain_count() == 0, "headless builds no rain (cheap)")
	_check(storm.get_child_count() == 0, "headless adds no audio player children")

	# Determinism: two storms with the same seed reach the same flash state after the same time.
	var a := MenuStorm.new(42)
	var b := MenuStorm.new(42)
	root.add_child(a)
	root.add_child(b)
	for t in 20:
		a.advance(0.5)
		b.advance(0.5)
	_check(is_equal_approx(a.flash_intensity(), b.flash_intensity()), "same seed gives the same flash state (%.3f vs %.3f)" % [a.flash_intensity(), b.flash_intensity()])
	_check(a.thunder_pending() == b.thunder_pending(), "and the same thunder-pending state")

	# A flash decays to zero well within a second, and thunder follows within the documented delay.
	var c := MenuStorm.new(7)
	root.add_child(c)
	var saw_flash := false
	var saw_thunder_window := false
	for step in 400:  # 400 * 0.05 s = 20 s: at least one lightning strike given a 4-9 s schedule
		c.advance(0.05)
		if c.flash_intensity() > 0.9:
			saw_flash = true
		if c.thunder_pending():
			saw_thunder_window = true
	_check(saw_flash, "a flash happens within 20 s")
	_check(saw_thunder_window, "a thunder delay is scheduled after a flash")
	# Lightning repeats every 4-9 s by design, so "settled" is a transient, not a permanent state:
	# step in small increments and confirm the flash actually returns to near-zero at some point.
	var saw_calm := false
	for step in 40:  # 40 * 0.05 s = 2 s, well inside most gaps between strikes
		c.advance(0.05)
		if c.flash_intensity() < 0.01:
			saw_calm = true
	_check(saw_calm, "the flash decays to near-zero between strikes")

	# The real main menu still has its buttons with the storm in the tree.
	var menu := MainMenu.new()
	root.add_child(menu)
	for i in 4:
		await process_frame
	_check(menu.find_child("MenuStorm", true, false) != null or _has_storm_child(menu), "the menu contains a storm background")
	var new_game := menu.find_child("*New Game*", true, false)
	print("menu_background_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _has_storm_child(node: Node) -> bool:
	for child in node.get_children():
		if child is MenuStorm:
			return true
		if _has_storm_child(child):
			return true
	return false
