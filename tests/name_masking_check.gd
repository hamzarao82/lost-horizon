extends SceneTree
## "Outpost 17" is a name the player learns at the compound sign. Until the flag `outpost_name_known` is set,
## the map status, travel labels, save-slot info and the First Signal's text say "The Perimeter" or nothing.
## godot --headless --path . -s tests/name_masking_check.gd

var _checks: int = 0
var _failures: int = 0
var _world: Node
var _regions: Node
var _saves: Node


func _initialize() -> void:
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
	_world = root.get_node("WorldState")
	_regions = root.get_node("RegionManager")
	_saves = root.get_node("SaveManager")
	_world.reset()

	print("-- the pure rule")
	_check(RegionLabel.name_for(&"outpost_17", "Outpost 17", false) == "The Perimeter", "unknown: Outpost 17 is masked")
	_check(RegionLabel.name_for(&"outpost_17", "Outpost 17", true) == "Outpost 17", "known: it shows its name")
	_check(RegionLabel.name_for(&"dead_coast", "Dead Coast", false) == "Dead Coast", "other regions are never masked")
	_check(RegionLabel.MASKED_NAME.find("17") == -1 and "outpost" not in RegionLabel.MASKED_NAME.to_lower(), "the mask itself leaks nothing")
	_check(String(RegionLabel.KNOWN_FLAG).length() <= 48 and String(RegionLabel.KNOWN_FLAG) == String(RegionLabel.KNOWN_FLAG).to_lower(), "the flag id is saveable")

	print("-- live label")
	_check(not RegionLabel.name_known(), "a fresh world does not know the name")
	_check(RegionLabel.visible_name(&"outpost_17", "Outpost 17") == "The Perimeter", "the live helper masks it")
	_world.set_flag(RegionLabel.KNOWN_FLAG, true)
	_check(RegionLabel.visible_name(&"outpost_17", "Outpost 17") == "Outpost 17", "and shows it once the flag is set")
	_world.reset()

	print("-- real map screen")
	_regions.current_region_id = &"outpost_17"
	var screen := MapScreen.new()
	root.add_child(screen)
	await _frames(2)
	screen.open()
	await _frames(3)
	var status: Label = screen.get("_status")
	_check(status != null and status.text.contains("The Perimeter") and not status.text.contains("Outpost 17"),
			"the Outpost status line reads The Perimeter (%s)" % (status.text if status else "?"))
	_regions.current_region_id = &"dead_coast"
	screen.show_detail()
	var exits := screen.detail_exits()
	var labels: Array = []
	for e in exits:
		labels.append(String(e["label"]))
	_check(not labels.is_empty() and not labels.any(func(l: String) -> bool: return l.contains("Outpost 17")),
			"travel labels from the Dead Coast do not name Outpost 17 (%s)" % str(labels))
	_world.set_flag(RegionLabel.KNOWN_FLAG, true)
	exits = screen.detail_exits()
	labels = []
	for e in exits:
		labels.append(String(e["label"]))
	_check(labels.any(func(l: String) -> bool: return l == "To Outpost 17"), "after the flag the label names it (%s)" % str(labels))
	_regions.current_region_id = &"outpost_17"
	screen.show_detail()
	_check(status.text.contains("Outpost 17"), "and so does the status line (%s)" % status.text)
	screen.queue_free()
	_world.reset()

	print("-- save-slot info")
	var path := "user://name_mask_check_%d.json" % OS.get_process_id()
	var base := {"version": 4, "saved_at": 1760000000, "next_wave": 1, "completed": false,
			"inventory": {"weapon": "", "armor": "", "potions": 0}, "player": {"health": 100.0, "max_health": 100.0},
			"defeated_bosses": [], "world": {"checkpoint_id": "", "position": null},
			"regions": {"current": "outpost_17"}, "stats": {"seconds": 10.0, "kills": 0}}
	_write(path, base)
	var info: Dictionary = _saves.inspect_save_file(path, 1)
	_check(info["usable"] and info["region"] == "The Perimeter", "a save without the flag lists The Perimeter (%s)" % info["region"])
	var with_flag := base.duplicate(true)
	with_flag["quests"] = {"world": {"flags": ["outpost_name_known"]}}
	_write(path, with_flag)
	info = _saves.inspect_save_file(path, 1)
	_check(info["region"] == "Outpost 17", "a save with the flag lists Outpost 17 (%s)" % info["region"])
	var coast := base.duplicate(true)
	coast["regions"] = {"current": "dead_coast"}
	_write(path, coast)
	info = _saves.inspect_save_file(path, 1)
	_check(info["region"] == "Dead Coast", "other regions list their own names")
	var row := LoadScreen.describe({"slot": 1, "usable": true, "region": "", "saved_at": 0, "seconds": 0.0, "checkpoint_id": ""})
	_check(not row.contains("Outpost 17"), "a row with no region falls back to the mask, not the name")
	DirAccess.remove_absolute(path)

	print("-- the First Signal's own text")
	var quest := load("res://resources/quests/first_signal.tres") as QuestData
	_check(quest != null and not quest.description.contains("Outpost 17"), "its description does not name the place")
	var first_text := String(quest.objectives[0].text) if quest != null else ""
	_check(not first_text.contains("Outpost 17"), "its first objective does not name the place (%s)" % first_text)
	var ids: Array = []
	for o in quest.objectives:
		ids.append(String(o.id))
	_check(ids.size() == 16 and ids[0] == "reach_perimeter" and ids[1] == "investigate_checkpoint" and ids[15] == "contact_outside",
			"its objective ids and order are unchanged (%d)" % ids.size())
	var search := load("res://resources/quests/campaign/search_outpost.tres") as QuestData
	_check(search != null and search.id == &"search_outpost" and search.objectives.size() == 1, "the contextual quest loads with one objective")

	print("name_masking_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file = null
