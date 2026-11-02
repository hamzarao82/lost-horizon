extends SceneTree
## Headless checks for RunStats and the M4 screens (main menu, death, results, equipment):
##   godot --headless --path . -s tests/screens_check.gd
## Exits non-zero on failure. Layout checks use fixed control sizes (headless text metrics are unreliable).

const BOOT_SCENE: String = "res://scenes/boot/Boot.tscn"
const STUB: String = "res://tests/_warmup_stub.gd"
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720)]

var _failures: int = 0
var _checks: int = 0
var _stats: Node
var _saves: Node


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


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	_stats = root.get_node_or_null("/root/RunStats")
	_saves = root.get_node_or_null("/root/SaveManager")
	_check(_stats != null, "RunStats autoload is registered")
	if _stats == null or _saves == null:
		quit(1)
		return
	_saves.reset_runtime_state()
	_saves.delete_save()
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(4)
	var player := get_first_node_in_group("player") as Player

	await _test_run_stats(main, player)
	await _test_persistence(player)
	await _test_death_screen(main, player)
	await _test_results_screen(main, player)
	await _test_equipment_screen(main, player)
	await _test_menu_states()
	await _test_layouts()

	main.queue_free()
	await _frames(4)
	await _test_boot_menu()

	_saves.reset_runtime_state()
	_saves.delete_save()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_run_stats(main: Node, player: Player) -> void:
	print("RunStats")
	_check(main.get_node_or_null("DeathScreen") != null and main.get_node_or_null("ResultsScreen") != null,
			"the death and results screens are installed with the world")
	_stats.reset()
	var enemy := (load("res://scenes/enemies/PatrolSoldier.tscn") as PackedScene).instantiate() as Enemy
	enemy.position = Vector3(0, 0, 60)
	main.add_child(enemy)
	await _frames(2)
	enemy.defeated.emit()
	_check(_stats.enemies_defeated == 1, "a defeated enemy is counted")

	var before: int = _stats.pickups
	player.inventory.add_item(load("res://resources/items/health_potion.tres"))
	_check(_stats.pickups == before + 1, "a kept pickup is counted")
	player.inventory.add_item(load("res://resources/items/improvised_blade.tres"))
	_check(_stats.pickups == before + 1, "a rejected pickup (no better than the equipped weapon) is not counted")

	var world := root.get_node("/root/WorldState")
	var secrets_before: int = _stats.secrets_found()
	world.set_flag(&"doc_screens_test_found")
	world.set_flag(&"screens_test_crate_taken")
	world.set_flag(&"unrelated_flag")
	_check(_stats.secrets_found() == secrets_before + 2, "documents and taken crates count as secrets, other flags do not")
	_check(_stats.documents_found() >= 1, "documents are counted separately")
	_check(_stats.secrets_total() >= _stats.secrets_found(), "the secret total is never below the found count")

	var seconds: float = _stats.seconds_played
	_stats._process(1.5)
	_check(is_equal_approx(_stats.seconds_played, seconds + 1.5), "time advances while the player is alive")
	var alive_state := player.state
	player.state = Player.State.DEAD
	_stats._process(5.0)
	_check(is_equal_approx(_stats.seconds_played, seconds + 1.5), "time stops once the player is dead")
	player.state = alive_state
	_check(ResultsScreen.format_time(3725.0) == "1:02:05", "time formats as h:mm:ss")

	var clean: Dictionary = _stats.sanitize({"seconds": -5, "kills": 99999999999, "pickups": "x", "extra": 1})
	_check(clean["seconds"] == 0.0 and clean["kills"] == 100000 and clean["pickups"] == 0 and not clean.has("extra"),
			"hostile stats are clamped and unknown keys dropped")
	_check(_stats.sanitize("nope").is_empty(), "a non-dictionary stats value is ignored")

	# Nearest living enemy within range is named as the cause; nobody close means no name.
	_stats.last_attacker_name = ""
	enemy.display_name = "Test Brute"
	enemy.global_position = player.global_position + Vector3(2, 0, 0)
	player.health.take_damage(1.0)
	_check(_stats.last_attacker_name == "Test Brute", "the nearest enemy is recorded as the attacker")
	_stats.last_attacker_name = ""
	enemy.global_position = player.global_position + Vector3(40, 0, 0)
	player.health.take_damage(1.0)
	_check(_stats.last_attacker_name == "", "a far-away enemy is not blamed")
	enemy.queue_free()
	player.health.health = player.health.max_health


func _test_persistence(player: Player) -> void:
	print("RunStats persistence")
	_stats.seconds_played = 123.4
	_stats.enemies_defeated = 7
	_stats.pickups = 3
	_check(_saves.save_game("manual"), "the game saves")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_saves.save_path()))
	_check(parsed is Dictionary and (parsed as Dictionary).has("stats"), "the save file has an optional stats section")
	_check(parsed is Dictionary and int((parsed as Dictionary)["version"]) == 2, "the save version stays 2")
	_stats.reset()
	_check(_stats.enemies_defeated == 0, "reset clears the counters")
	_check(_saves.load_game(), "the save loads")
	_check(is_equal_approx(_stats.seconds_played, 123.4) and _stats.enemies_defeated == 7 and _stats.pickups == 3,
			"stats come back from the save")
	_saves.reset_runtime_state()
	_check(_stats.seconds_played == 0.0 and _stats.enemies_defeated == 0 and _stats.pickups == 0,
			"a new run (reset_runtime_state) clears the stats")

	_stats.enemies_defeated = 5
	var legacy := {"version": 2, "saved_at": 1, "next_wave": 1, "completed": false,
			"inventory": {"weapon": "improvised_blade", "armor": "", "potions": 0},
			"player": {"health": 80, "max_health": 100}, "defeated_bosses": [],
			"world": {"checkpoint_id": "", "position": null}}
	_saves.write_data(legacy)
	_check(_saves.load_game(), "a version 2 save without stats still loads")
	_check(_stats.enemies_defeated == 0, "and starts the counters from zero")
	_saves.reset_runtime_state()
	_stats.seconds_played = 2535.0
	player.health.health = player.health.max_health
	_saves.save_game("manual")


func _test_death_screen(main: Node, _player: Player) -> void:
	print("Death screen")
	var death := main.get_node("DeathScreen") as DeathScreen
	death.show_death("Hunter Elite", "checkpoint_b", null, 0)
	await _frames(2)
	_check(death.is_showing(), "the overlay shows")
	_check(death.cause_text() == "Killed by: Hunter Elite", "cause names the killer")
	_check(death.respawn_text() == "Respawn: Military Compound checkpoint", "a known checkpoint gets a friendly name")
	_check(death.hint_text().begins_with("Tip: ") and death.hint_text().length() > 10, "a hint line is shown")
	death.show_death("", "", null, 1)
	_check(death.cause_text() == "Killed by: Unknown", "an unknown killer reads Unknown")
	_check(death.respawn_text() == "Respawn: start of the island", "no checkpoint means the start")
	_check(DeathScreen.respawn_line("checkpoint_x", [0.0, 1.0, -75.0]) == "Respawn: Command Center",
			"an unnamed checkpoint falls back to the area that contains it")
	_check(DeathScreen.respawn_line("checkpoint_x", null) == "Respawn: last checkpoint", "no place at all falls back to a generic line")
	_check(DeathScreen.respawn_line(DeathScreen.WAVE_RESPAWN) == "Respawn: the current wave", "arena deaths name the wave")
	_check(get_first_node_in_group("death_screen") == death, "the HUD can tell a death screen exists (no doubled YOU DIED)")
	death.hide_death()
	_check(not death.is_showing(), "the overlay hides again")

	_stats.last_attacker_name = "Warden"
	_saves.checkpoint_id = ""
	death._on_player_died()
	_check(death.cause_text() == "Killed by: Warden", "the real death path reads RunStats")
	death.hide_death()
	_stats.last_attacker_name = ""


func _test_results_screen(main: Node, _player: Player) -> void:
	print("Results screen")
	var results := main.get_node("ResultsScreen") as ResultsScreen
	_stats.seconds_played = 754.0
	_stats.enemies_defeated = 12
	var qm := root.get_node("/root/QuestManager")
	results.show_results(&"first_signal")
	_check(results.is_open() and paused, "the results screen opens and pauses the game")
	_check(results.label_text("quest") == "The First Signal", "shows the quest title")
	_check(results.label_text("time") == "Time played: 0:12:34", "shows the time played")
	_check(results.label_text("kills") == "Enemies defeated: 12", "shows enemies defeated")
	_check(results.label_text("secrets").begins_with("Secrets found: "), "shows secrets found / total")
	var reward_id: String = qm.get_quest(&"first_signal").rewards[0]
	var reward := load("res://resources/items/%s.tres" % reward_id) as ItemData
	_check(results.label_text("reward") == "Reward: " + reward.display_name and results.label_color("reward").is_equal_approx(reward.color()),
			"shows the reward in its rarity colour")
	_check(results.label_text("saved") == "Progress saved", "reports the save (and the save succeeded)")
	results.close()
	_check(not results.is_open() and not paused, "Continue closes it and resumes the world")

	if qm.has_signal("mission_completed"):
		var wired := false
		for connection in qm.mission_completed.get_connections():
			wired = wired or (connection["callable"] as Callable).get_object() == results
		_check(wired, "the results screen listens to QuestManager.mission_completed")
		qm.mission_completed.emit(&"first_signal")
		_check(not results.is_open(), "headless runs do not pop the screen up by themselves (like the intro and ending)")
	else:
		print("  note QuestManager has no mission_completed signal yet: signal wiring not exercised")
	paused = false


func _test_equipment_screen(main: Node, player: Player) -> void:
	print("Equipment screen")
	var inventory := player.inventory
	var blade := load("res://resources/items/improvised_blade.tres") as ItemData
	var katana := load("res://resources/items/katana.tres") as ItemData
	inventory.weapon = blade
	inventory.previous_weapon = null
	inventory.add_item(katana)
	_check(inventory.weapon == katana and inventory.previous_weapon == blade, "equipping better gear remembers the replaced weapon")
	inventory.add_item(load("res://resources/items/light_tactical_armor.tres"))
	inventory.potions = 2
	var qm := root.get_node("/root/QuestManager")
	qm.add_quest_item(&"access_card")

	var screen := EquipmentScreen.new()
	root.add_child(screen)
	screen.open()
	_check(screen.is_open(), "the screen opens")
	_check(screen.label_text("weapon_name") == katana.display_name and screen.label_color("weapon_name").is_equal_approx(katana.color()),
			"weapon name in its rarity colour")
	var percent := roundi((katana.power() / blade.power() - 1.0) * 100.0)
	_check(screen.label_text("weapon_compare") == "+%d%% vs %s" % [percent, blade.display_name],
			"comparison with the earlier weapon: " + screen.label_text("weapon_compare"))
	_check(screen.label_text("weapon_stats").contains("Damage x%.2f" % katana.damage_multiplier), "damage multiplier is listed")
	_check(screen.label_text("armor_points") == "Armor %d / %d" % [roundi(player.health.armor), roundi(player.health.max_armor)]
			and player.health.max_armor > 0.0, "armor shows current / max points")
	_check(screen.label_text("medkits") == "Medkits: 2", "medkit count")
	_check(screen.label_text("teleport").begins_with("Teleport: ") and screen.label_text("teleport").contains("/ 2 charges"),
			"teleport charges: " + screen.label_text("teleport"))
	_check(screen.label_text("quest_items").contains("Security Access Card"), "quest items are listed by name")
	_check(screen.label_text("documents") == "Documents found: %d" % _stats.documents_found(), "documents found")
	_check(EquipmentScreen.compare_text(blade, katana).begins_with("-"), "a weaker item compares with a minus sign")
	_check(EquipmentScreen.compare_text(blade, null) == "", "no earlier item means no comparison")
	screen.close()
	_check(not screen.is_open(), "the screen closes")

	var pause := main.get_node("PauseMenu") as PauseMenu
	pause.show_equipment()
	_check(paused and pause.is_open(), "the pause menu opens the equipment screen (game paused)")
	pause.toggle()
	paused = false
	screen.queue_free()
	await _frames(1)


func _test_menu_states() -> void:
	print("Main menu")
	_saves.delete_save()
	var menu := MainMenu.new()
	root.add_child(menu)
	await _frames(2)
	_check(menu.button("continue").disabled, "Continue is disabled without a save")
	_check(not menu.button("new_game").disabled, "New Game is always available")
	_check(menu.has_quit_button(), "Quit is offered on desktop")
	_check(menu.continue_info() == "", "no save info without a save")
	var events: Array[String] = []
	menu.new_game_pressed.connect(func() -> void: events.append("new"))
	menu.button("new_game").pressed.emit()
	_check(events == ["new"], "New Game emits its signal")
	menu.queue_free()

	var save := {"version": 2, "saved_at": 1, "next_wave": 1, "completed": false,
			"inventory": {"weapon": "improvised_blade", "armor": "", "potions": 0},
			"player": {"health": 80, "max_health": 100}, "defeated_bosses": [],
			"world": {"checkpoint_id": "checkpoint_b", "position": [-22.0, 0.8, 24.0]},
			"stats": {"seconds": 2535.0, "kills": 4, "pickups": 1}}
	_saves.write_data(save)
	var menu2 := MainMenu.new()
	root.add_child(menu2)
	await _frames(2)
	_check(not menu2.button("continue").disabled, "Continue is enabled with a save")
	_check(menu2.continue_info() == "Military Compound checkpoint - 0:42:15", "Continue shows the place and time: " + menu2.continue_info())
	menu2.continue_pressed.connect(func() -> void: events.append("continue"))
	menu2.button("continue").pressed.emit()
	_check(events.has("continue"), "Continue emits its signal")
	_check(MainMenu.describe_save({}) == "", "an empty save has no description")
	menu2.queue_free()
	_saves.delete_save()
	await _frames(1)


func _viewport_rects(size: Vector2i, node: Node, after: Callable = Callable()) -> Array[Rect2]:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(node)
	await process_frame
	await process_frame
	if after.is_valid():
		after.call(node)
		await process_frame
		await process_frame
	var rects: Array[Rect2] = []
	for button in _find_buttons(node):
		if button.is_visible_in_tree():
			rects.append(button.get_global_rect())
	viewport.queue_free()
	return rects


func _find_buttons(node: Node) -> Array[Button]:
	var out: Array[Button] = []
	if node is Button:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_buttons(child))
	return out


func _layout_ok(rects: Array[Rect2], size: Vector2i, label: String) -> void:
	var overlap := false
	var inside := true
	var tall := true
	for i in rects.size():
		var r := rects[i]
		tall = tall and r.size.y >= 56.0
		inside = inside and r.position.x >= 0.0 and r.position.y >= 0.0 and r.end.x <= size.x and r.end.y <= size.y
		for j in range(i + 1, rects.size()):
			overlap = overlap or r.intersects(rects[j])
	_check(rects.size() > 0, "%s %dx%d: buttons found (%d)" % [label, size.x, size.y, rects.size()])
	_check(not overlap, "%s %dx%d: buttons do not overlap" % [label, size.x, size.y])
	_check(inside, "%s %dx%d: buttons are on screen" % [label, size.x, size.y])
	_check(tall, "%s %dx%d: buttons are touch-sized (>= 56 px)" % [label, size.x, size.y])


func _test_layouts() -> void:
	print("Layouts")
	for size in SIZES:
		var rects := await _viewport_rects(size, MainMenu.new())
		_layout_ok(rects, size, "main menu")
		rects = await _viewport_rects(size, ResultsScreen.new(),
				func(node: Node) -> void: (node as ResultsScreen).show_results(&"first_signal"))
		paused = false
		_layout_ok(rects, size, "results")
		rects = await _viewport_rects(size, EquipmentScreen.new(),
				func(node: Node) -> void: (node as EquipmentScreen).open())
		_layout_ok(rects, size, "equipment")


func _test_boot_menu() -> void:
	print("Boot hands over to the menu")
	_saves.delete_save()
	_saves.reset_runtime_state()
	var boot := (load(BOOT_SCENE) as PackedScene).instantiate()
	boot.warmup_script_path = STUB
	boot.show_menu = true
	var finished: Array = []
	boot.finished.connect(func(m: Node) -> void: finished.append(m))
	root.add_child(boot)
	var frames := 0
	while boot.phase != boot.Phase.MENU and boot.phase != boot.Phase.ERROR and frames < 3000:
		await process_frame
		frames += 1
	_check(boot.phase == boot.Phase.MENU and boot.menu != null, "boot waits on the menu after loading (%d frames)" % frames)
	_check(finished.is_empty(), "the game has not started behind the menu")
	var first_main: Node = boot.main_node
	_check(first_main != null and first_main.process_mode == Node.PROCESS_MODE_DISABLED, "Main stays disabled behind the menu")
	_check(boot.menu.button("continue").disabled, "no save: Continue is off in the real hand-over")

	# New Game with leftover runtime state clears it, then the game starts.
	_saves.world_checkpoint = {"position": [1.0, 1.0, 1.0]}
	_saves.checkpoint_id = "checkpoint_b"
	_stats.enemies_defeated = 9
	boot.menu.button("new_game").pressed.emit()
	_check(_saves.world_checkpoint.is_empty() and _saves.checkpoint_id == "" and _stats.enemies_defeated == 0,
			"New Game clears leftover checkpoint and stats")
	var waited := 0
	while finished.is_empty() and waited < 600:
		await process_frame
		waited += 1
	_check(finished.size() == 1 and finished[0] == first_main, "New Game starts the already loaded Main")
	_check(first_main.process_mode == Node.PROCESS_MODE_INHERIT, "Main is enabled after New Game")
	waited = 0
	while is_instance_valid(boot) and waited < 200:
		await process_frame
		waited += 1
	_check(not is_instance_valid(boot), "the boot screen removes itself")
	first_main.queue_free()
	await _frames(4)

	# Continue: write a save from a live Main, then boot again and choose Continue.
	var main2 := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main2.get_node("WaveManager").autostart = false
	root.add_child(main2)
	await _frames(4)
	var p := get_first_node_in_group("player") as Player
	p.global_position = Vector3(-22.0, 0.8, 24.0)
	_stats.enemies_defeated = 4
	_saves.activate_checkpoint("checkpoint_b")
	main2.queue_free()
	await _frames(4)
	_saves.reset_runtime_state()

	var boot2 := (load(BOOT_SCENE) as PackedScene).instantiate()
	boot2.warmup_script_path = STUB
	boot2.show_menu = true
	var finished2: Array = []
	boot2.finished.connect(func(m: Node) -> void: finished2.append(m))
	root.add_child(boot2)
	frames = 0
	while boot2.phase != boot2.Phase.MENU and boot2.phase != boot2.Phase.ERROR and frames < 3000:
		await process_frame
		frames += 1
	_check(boot2.phase == boot2.Phase.MENU and not boot2.menu.button("continue").disabled, "with a save, Continue is on")
	var old_main: Node = boot2.main_node
	boot2.menu.button("continue").pressed.emit()
	waited = 0
	while finished2.is_empty() and waited < 3000 and boot2.phase != boot2.Phase.ERROR:
		await process_frame
		waited += 1
	_check(boot2.phase != boot2.Phase.ERROR, "Continue finishes without a boot error (%s)" % boot2.error_text)
	_check(finished2.size() == 1 and finished2[0] != old_main and is_instance_valid(finished2[0]), "Continue hands over a freshly reloaded Main")
	var new_player := get_first_node_in_group("player") as Player
	_check(new_player != null and new_player.global_position.distance_to(Vector3(-22.0, 0.8, 24.0)) < 3.0,
			"the player is restored at the saved checkpoint")
	_check(_stats.enemies_defeated == 4, "stats are restored by Continue")
	_check(finished2.size() == 1 and finished2[0].process_mode == Node.PROCESS_MODE_INHERIT, "the reloaded Main runs")
	waited = 0
	while is_instance_valid(boot2) and waited < 200:
		await process_frame
		waited += 1
	if finished2.size() == 1 and is_instance_valid(finished2[0]):
		finished2[0].queue_free()
	await _frames(4)
