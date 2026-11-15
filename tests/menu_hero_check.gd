extends SceneTree
## The real player model in the title menu: it must cost nothing on a headless run, never crash the menu, keep
## every existing button, and the storm's flash must be readable by the hero's light when it is built.
## godot --headless --path . -s tests/menu_hero_check.gd

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
	_check(not MenuHero.wanted(), "headless: the hero is not wanted (no 3D viewport on CI or tests)")
	_check(ResourceLoader.exists(MenuHero.MODEL_PATH), "the real player model file exists: %s" % MenuHero.MODEL_PATH)

	var storm := MenuStorm.new(3)
	root.add_child(storm)
	var hero := MenuHero.new(storm)
	root.add_child(hero)
	for i in 3:
		await process_frame
	_check(not hero.active and hero.get_child_count() == 0, "headless: builds nothing (no SubViewport, no lights)")
	hero.queue_free()

	var menu := MainMenu.new()
	root.add_child(menu)
	for i in 3:
		await process_frame
	_check(menu.hero != null and menu.hero.is_inside_tree(), "the real MainMenu holds a MenuHero")
	_check(not menu.hero.active, "and it stays inactive headless")
	for key in ["new_game", "continue", "load_game", "replay_ending", "arena", "settings", "credits"]:
		_check(menu.button(key) != null, "button still present: %s" % key)

	# The hero reads the storm's flash: when active, a stronger flash must raise the key light.
	var fake := MenuHero.new(storm)
	fake.key_light = DirectionalLight3D.new()
	fake.active = true
	root.add_child(fake)
	root.add_child(fake.key_light)
	fake._process(0.0)
	var calm: float = fake.key_light.light_energy
	storm._flash = 1.0
	fake._process(0.0)
	_check(fake.key_light.light_energy > calm + 1.0, "a lightning flash raises the key light (%.2f -> %.2f)" % [calm, fake.key_light.light_energy])
	_check(is_equal_approx(calm, MenuHero.KEY_ENERGY_BASE), "and it rests at the base energy when calm")

	print("menu_hero_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
