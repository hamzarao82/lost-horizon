extends SceneTree
## The title menu appears at once and the world loads behind it.
## godot --headless --path . -s tests/boot_menu_early_check.gd

const BOOT_SCENE: String = "res://scenes/boot/Boot.tscn"
const STUB: String = "res://tests/_warmup_stub.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	HitStop.enabled = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _new_boot(show_menu: bool) -> Node:
	var boot := (load(BOOT_SCENE) as PackedScene).instantiate()
	boot.warmup_script_path = STUB
	boot.show_menu = show_menu
	return boot


func _run() -> void:
	var saves := root.get_node_or_null("SaveManager")
	if saves:
		saves.delete_save()
		saves.reset_runtime_state()

	print("early menu while loading")
	var boot := _new_boot(true)
	var started: Array = []
	boot.finished.connect(func(_m: Node) -> void: started.append(true))
	root.add_child(boot)
	_check(boot.menu != null and is_instance_valid(boot.menu), "the menu exists right after _ready, before loading finishes")
	_check(boot.phase != boot.Phase.MENU and boot.phase != boot.Phase.DONE, "the boot is still loading at that point")
	var menu: MainMenu = boot.menu
	_check(menu.is_loading(), "the menu is in its loading state")
	_check(menu.button("new_game").disabled and menu.button("continue").disabled, "New Game and Continue are off while loading")
	_check(menu.loading_text().begins_with("Loading world..."), "the label reads 'Loading world...' (%s)" % menu.loading_text())
	_check(not boot._ui.visible, "the boot screen is hidden behind the menu while it loads")
	_check(not menu.button("settings").disabled and not menu.button("credits").disabled, "Settings and Credits are usable immediately")

	print("opening animation and skip")
	_check(menu.is_intro_active(), "the opening fade is playing")
	menu.button("settings").pressed.emit()
	await process_frame
	_check(menu._settings_page.visible, "Settings opens while the world loads")
	menu._settings_page.back_pressed.emit()
	for code in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
		var m2 := MainMenu.new()
		root.add_child(m2)
		await process_frame
		_check(m2.is_intro_active(), "a fresh menu starts with the intro (%s)" % OS.get_keycode_string(code))
		m2._input(_key(code))
		_check(not m2.is_intro_active() and is_equal_approx(m2._main_page.modulate.a, 1.0), "%s skips the intro" % OS.get_keycode_string(code))
		m2.queue_free()
	var m3 := MainMenu.new()
	root.add_child(m3)
	await process_frame
	m3._input(_key(KEY_A))
	_check(m3.is_intro_active(), "another key does not skip the intro")
	m3.queue_free()

	print("monotonic progress, then ready")
	var last := -1
	var monotonic := true
	var frames := 0
	while boot.phase != boot.Phase.MENU and boot.phase != boot.Phase.ERROR and frames < 3000:
		await process_frame
		frames += 1
		var t: String = menu.loading_text()
		if t != "":
			var n := int(t.get_slice("...", 1).strip_edges().trim_suffix("%"))
			if n < last:
				monotonic = false
			last = n
	_check(boot.phase == boot.Phase.MENU, "loading reaches the menu phase (%d frames)" % frames)
	_check(monotonic and last >= 0, "the percentage never went backwards (last %d)" % last)
	_check(not menu.is_loading() and menu.loading_text() == "", "the loading label is gone when ready")
	_check(not menu.button("new_game").disabled, "New Game is enabled when ready")
	_check(menu.button("continue").disabled, "Continue stays off without a save")
	_check(boot.menu == menu, "the same menu instance is kept (no second menu)")

	print("New Game starts at once")
	menu.button("new_game").pressed.emit()
	frames = 0
	while started.size() == 0 and frames < 600:
		await process_frame
		frames += 1
	_check(started.size() == 1, "New Game finishes the boot with no second wait (%d frames)" % frames)
	_check(not is_instance_valid(boot) or boot.menu == null, "the menu is gone after New Game")
	_check(not Input.is_action_pressed(&"ui_accept"), "no input action was left pressed")
	if is_instance_valid(boot):
		boot.queue_free()
	await process_frame

	print("headless and no-menu paths are unchanged")
	var plain := _new_boot(false)
	var plain_done: Array = []
	plain.finished.connect(func(_m: Node) -> void: plain_done.append(true))
	root.add_child(plain)
	_check(plain.menu == null, "with show_menu false no menu is created early")
	frames = 0
	while plain_done.size() == 0 and frames < 3000:
		await process_frame
		frames += 1
	_check(plain_done.size() == 1, "the no-menu boot starts the game directly (%d frames)" % frames)
	if is_instance_valid(plain):
		plain.queue_free()

	print("web percentage follows time")
	var boot_script := load("res://scripts/core/boot.gd")
	_check(is_equal_approx(boot_script.display_progress(0.5, false), 0.5), "desktop shows the real progress as is")
	_check(boot_script.display_progress(0.0, true) == 0.0 and is_equal_approx(boot_script.display_progress(1.0, true), 1.0), "web percentage runs from 0 to 100")
	var reveal_start: float = boot_script.W_LOAD + boot_script.W_WARM + boot_script.W_BUILD
	_check(is_equal_approx(boot_script.display_progress(reveal_start, true), 0.30), "the stages before the reveal fill the first 30% on web")
	var prev := -1.0
	var rising := true
	for i in 101:
		var v: float = boot_script.display_progress(i / 100.0, true)
		if v < prev:
			rising = false
		prev = v
	_check(rising, "the web percentage never goes down as raw progress rises")
	_check(boot_script.display_progress(0.96, true) < 0.9, "the reveal does not jump to 'almost done' early on web")

	print("boot_menu_early_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
