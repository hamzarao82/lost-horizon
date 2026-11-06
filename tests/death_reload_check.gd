extends SceneTree
## Dying through the real Player._die path and its 2 s reload timer: progression and the inventory
## survive the real scene reload and checkpoint respawn.
## godot --headless --path . -s tests/death_reload_check.gd   (uses SaveManager's per-process test file)

var _failures: int = 0
var _checks: int = 0
var _sm: Node
var _prog: Node


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
		await physics_frame


func _clean() -> void:
	_sm.reset_runtime_state()
	_sm.delete_save()
	for suffix in [".bak", ".tmp"]:
		var path: String = _sm.save_path() + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_sm.defeated_bosses.clear()


func _run() -> void:
	_sm = root.get_node_or_null("SaveManager")
	_prog = root.get_node_or_null("Progression")
	_check(_sm != null and _prog != null, "SaveManager and Progression autoloads exist")
	_clean()
	_prog.reset()
	await create_timer(2.6).timeout  # drain any pending reload timers from earlier work
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(3)
	current_scene = main  # Player._die reloads the current scene
	var player := main.get_node("Player") as Player
	player.global_position = Vector3(6.0, 0.1, -41.0)

	# Build a character: level, spent points, skills, items, currency.
	_prog.progress.xp = 2500
	var level_before: int = _prog.level()
	_prog.progress.attributes[&"strength"] = 2
	_prog.progress.skills[&"sharpened_edge"] = 2
	_prog.progress.skills[&"combo_extension"] = 1
	var knife := load("res://resources/items/combat_knife.tres") as ItemData
	var scrap := load("res://resources/items/cloth_scrap.tres") as ItemData
	player.inventory.collect(scrap, 3)
	player.inventory.add_item(knife)
	player.inventory.add_currency(120)
	var scrap_at_checkpoint: int = player.inventory.count_of("cloth_scrap")
	var money_at_checkpoint: int = player.inventory.currency
	await _frames(2)
	_sm.activate_checkpoint("checkpoint_progress")  # also saves
	var xp_at_checkpoint: int = _prog.progress.xp

	# After the checkpoint: earn more XP, find another item, then walk away and die outside the arena.
	_prog.award_xp(40, "test")
	var xp_before_death: int = _prog.progress.xp
	player.inventory.collect(scrap, 5)
	player.inventory.add_currency(75)
	player.global_position = Vector3(0.0, 0.1, 5.0)
	player.health.take_damage(100000.0)
	_check(player.is_dead(), "the player dies through the real death path")
	var guard := 0
	while (current_scene == main or not is_instance_valid(current_scene)) and guard < 600:
		await physics_frame
		guard += 1
	_check(current_scene != null and current_scene != main, "the real 2 s timer reloads the scene")
	await _frames(20)
	var reloaded := current_scene
	var new_player := reloaded.get_node("Player") as Player if reloaded else null
	_check(new_player != null and not new_player.is_dead(), "a fresh player is alive")
	if new_player != null:
		_check(new_player.global_position.distance_to(Vector3(6.0, 0.1, -41.0)) < 0.6, "it respawns at the checkpoint")
	_check(_prog.level() == level_before and _prog.level() > 1, "the level survives death (%d)" % _prog.level())
	_check(_prog.progress.xp == xp_before_death, "XP earned after the checkpoint is kept (%d, was %d at the checkpoint)" % [_prog.progress.xp, xp_at_checkpoint])
	_check(int(_prog.progress.attributes.get(&"strength", 0)) == 2, "attribute points survive")
	_check(int(_prog.progress.skills.get(&"sharpened_edge", 0)) == 2 and int(_prog.progress.skills.get(&"combo_extension", 0)) == 1, "skill ranks survive")
	if new_player != null:
		var inv = new_player.inventory
		_check(inv.count_of("cloth_scrap") == scrap_at_checkpoint, "items come back as at the checkpoint (%d scrap, had %d then)" % [inv.count_of("cloth_scrap"), scrap_at_checkpoint])
		_check(inv.currency == money_at_checkpoint, "currency comes back as at the checkpoint (%d)" % inv.currency)
		_check(_prog.currency() == inv.currency, "Progression and the inventory still agree on currency")
		var scale: float = new_player.call("_progression_scale", load("res://resources/attacks/light_1.tres"))
		_check(scale > 1.0, "the respawned player still has its skill and attribute damage bonus (x%.3f)" % scale)
		# The combo skill is live on the new player: light 3 continues into an extension hit.
		new_player.set("_attack_idx", Player.IDX_LIGHT_3)
		_check(new_player.call("_next_attack", false) == Player.IDX_LIGHT_1, "Combo Extension still works after the reload")
	if reloaded:
		reloaded.queue_free()
	await _frames(3)
	_clean()
	_prog.reset()
	print("death_reload_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
