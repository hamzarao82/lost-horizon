extends SceneTree
## Writes the Dead Coast quests, items and loot tables as resources.
## godot --headless --path . -s tools/gen_dead_coast_data.gd
## Run once after editing the definitions below; the .tres files are committed.

const T := ObjectiveData.Type
const QUEST_DIR := "res://resources/quests/dead_coast/"
const LOOT_DIR := "res://resources/loot/"
const ITEM_DIR := "res://resources/items/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(QUEST_DIR))
	_items()
	_loot()
	_quests()
	quit()


func _obj(id: String, text: String, type: int, targets: Array, count: int = 0, label: String = "", optional: bool = false) -> ObjectiveData:
	var o := ObjectiveData.new()
	o.id = StringName(id)
	o.text = text
	o.type = type as ObjectiveData.Type
	o.targets = PackedStringArray(targets)
	o.count = count
	o.progress_label = label
	o.optional = optional
	return o


func _quest(id: String, title: String, description: String, objectives: Array, rewards: Array, reward_text: String,
		prerequisites: Array, next_quest: String, start: Array, complete: Array, hint: String) -> void:
	var q := QuestData.new()
	q.id = StringName(id)
	q.title = title
	q.description = description
	var typed: Array[ObjectiveData] = []
	for o in objectives:
		typed.append(o)
	q.objectives = typed
	q.rewards = PackedStringArray(rewards)
	q.reward_text = reward_text
	q.prerequisites = PackedStringArray(prerequisites)
	q.next_quest = StringName(next_quest)
	q.start_captions = PackedStringArray(start)
	q.complete_captions = PackedStringArray(complete)
	q.caption_seconds = 4.5
	q.category = QuestData.Category.MAIN
	q.location_hint = hint
	var errors := q.validate()
	if not errors.is_empty():
		push_error("%s invalid: %s" % [id, "; ".join(errors)])
	var path := QUEST_DIR + id + ".tres"
	print("quest ", id, " -> ", error_string(ResourceSaver.save(q, path)))


func _quests() -> void:
	_quest("dc_wreckage", "Wreckage",
		"A freighter broke apart on the Dead Coast. Somebody was moving something the military did not want seen.",
		[
			_obj("enter_dead_coast", "Enter the Dead Coast", T.ENTER_AREA, ["dc_wreckage_beach"]),
			_obj("investigate_wreckage", "Investigate the freighter wreckage", T.INTERACT, ["dead_coast_wreck_hull"]),
			_obj("find_comm_equipment", "Search for surviving communication equipment", T.INTERACT, ["dead_coast_radio_wreck"]),
			_obj("find_shipment_evidence", "Find evidence of a military shipment", T.INTERACT, ["dead_coast_log_wreck_manifest"]),
			_obj("defeat_beach_patrols", "Defeat the hostile patrols", T.FLAG, ["patrol_dead_coast_beach_cleared"]),
			_obj("recover_data_device", "Recover the data device", T.INTERACT, ["dead_coast_data_device"]),
			_obj("find_wreck_cache", "Search the lifeboat for supplies", T.INTERACT, ["dead_coast_cache_wreck"], 0, "", true),
		],
		["upgrade_kit_weapon", "credits_medium"], "Weapon Upgrade Kit and credits", [], "dc_silent_checkpoint",
		["The coast is quiet. Too quiet. The wreck is the only thing out here that is still talking."],
		["Wreckage: complete.", "Someone staged this crash. The data device points up the coast."],
		"Wreckage Beach")
	_quest("dc_silent_checkpoint", "The Silent Checkpoint",
		"A military checkpoint on the coast road stopped answering. Find out why, and open the supply route.",
		[
			_obj("locate_checkpoint", "Locate the abandoned checkpoint", T.ENTER_AREA, ["dc_checkpoint"]),
			_obj("investigate_security", "Investigate the checkpoint's security systems", T.INTERACT, ["dead_coast_checkpoint_terminal"]),
			_obj("discover_reason", "Find out why it was abandoned", T.INTERACT, ["dead_coast_log_checkpoint_orders"]),
			_obj("obtain_route_access", "Obtain access to the coastal supply route", T.FLAG, ["dead_coast_route_pass"]),
			_obj("defeat_defenders", "Defeat the checkpoint's defenders", T.FLAG, ["patrol_dead_coast_checkpoint_cleared"]),
			_obj("search_guardhouse", "Search the guardhouse", T.INTERACT, ["dead_coast_cache_guardhouse"], 0, "", true),
		],
		["armor_patch", "credits_medium"], "Armor patch and credits", ["dc_wreckage"], "dc_lost_cargo",
		["The checkpoint is a dead end for the radio. Somebody ordered it left empty."],
		["The Silent Checkpoint: complete.", "The supply route is open. The cargo went north."],
		"Abandoned Checkpoint")
	_quest("dc_lost_cargo", "Lost Cargo",
		"The shipment never reached Outpost 17. Follow it to Smuggler's Cove.",
		[
			_obj("track_shipment", "Track the missing shipment", T.INTERACT, ["dead_coast_trail_markers"]),
			_obj("explore_cove", "Explore Smuggler's Cove", T.ENTER_AREA, ["dc_cove"]),
			_obj("find_containers", "Locate the hidden supply containers", T.INTERACT,
				["dead_coast_cargo_a", "dead_coast_cargo_b", "dead_coast_cargo_c"], 3, "Containers"),
			_obj("recover_equipment", "Recover the sealed equipment case", T.INTERACT, ["dead_coast_cargo_gear"]),
			_obj("discover_black_site", "Discover the link to Project Black Site", T.INTERACT, ["dead_coast_log_black_site_link"]),
			_obj("reach_watchpoint", "Climb to the cliffside watchpoint", T.ENTER_AREA, ["dc_watchpoint"], 0, "", true),
			_obj("find_depot", "Find the hidden supply depot", T.ENTER_AREA, ["dc_depot"], 0, "", true),
			_obj("clear_raider_camp", "Clear the raider camp", T.FLAG, ["patrol_dead_coast_camp_cleared"], 0, "", true),
		],
		["coastal_weapon_part", "credits_medium"], "Coastal weapon part and credits", ["dc_silent_checkpoint"], "",
		["The cargo left the beach in sealed crates. Find where they were hidden."],
		["Lost Cargo: complete.", "The trail goes on into the Blackwood. The way north is open."],
		"Smuggler's Cove")


func _item(id: String, name: String, kind: int, rarity: int, description: String, slot: int = 0, stats: Dictionary = {},
		unique: bool = false, max_stack: int = 0, value: int = 0) -> void:
	var item := ItemData.new()
	item.item_id = StringName(id)
	item.display_name = name
	item.kind = kind as ItemData.Kind
	item.rarity = rarity as ItemData.Rarity
	item.description = description
	item.slot = slot as ItemData.Slot
	item.base_stats = stats
	item.unique = unique
	item.max_stack = max_stack
	item.value = value
	item.region = "dead_coast"
	print("item ", id, " -> ", error_string(ResourceSaver.save(item, ITEM_DIR + id + ".tres")))


func _items() -> void:
	_item("tide_charm", "Tide Charm", ItemData.Kind.ARMOR, ItemData.Rarity.RARE,
		"A smuggler's charm of salt-white shell. Whoever carried it always found the quiet route.",
		ItemData.Slot.ACCESSORY, {"damage_reduction": 0.03, "max_health": 8.0, "move_speed_mult": 1.03}, true, 1, 120)
	_item("coastal_weapon_part", "Coastal Weapon Part", ItemData.Kind.UPGRADE_COMPONENT, ItemData.Rarity.EPIC,
		"A hardened guard and fittings cut for a weapon that never arrived. Improves a weapon at the bench.",
		ItemData.Slot.NONE, {}, true, 1, 150)
	_item("coastal_alloy", "Coastal Alloy", ItemData.Kind.MATERIAL, ItemData.Rarity.UNCOMMON,
		"Salt-cured steel scrap from the wrecks. Crafting material.", ItemData.Slot.NONE, {}, false, 99, 18)


func _table(file: String, source: int, chance: float, paths: Array, weights: Array, rolls: int, guaranteed: Array = [], counts: Array = []) -> void:
	var t := LootTable.new()
	t.drop_chance = chance
	t.source = source as LootTable.Source
	t.region = "dead_coast"
	var full := PackedStringArray()
	for p in paths:
		full.append(ITEM_DIR + String(p) + ".tres")
	t.item_paths = full
	t.weights = PackedFloat32Array(weights)
	t.rolls = rolls
	var g := PackedStringArray()
	for p in guaranteed:
		g.append(ITEM_DIR + String(p) + ".tres")
	t.guaranteed_paths = g
	t.max_counts = PackedInt32Array(counts)
	t.rarity_weights = PackedFloat32Array([1.0, 1.0, 1.1, 1.3, 1.3])
	print("loot ", file, " -> ", error_string(ResourceSaver.save(t, LOOT_DIR + file + ".tres")))


func _loot() -> void:
	# Enemy tables replace the Outpost 17 base table for Dead Coast enemies (drop_chance matches today's ~0.45).
	_table("dead_coast_regular", LootTable.Source.REGULAR, 0.45,
		["bandage", "scrap_metal", "credits_small", "cloth_scrap", "coastal_alloy", "health_potion", "armor_patch"],
		[22, 20, 22, 12, 10, 8, 6], 1, [], [1, 2, 1, 1, 1, 1, 1])
	_table("dead_coast_elite", LootTable.Source.ELITE, 0.6,
		["health_potion", "armor_patch", "credits_medium", "coastal_alloy", "sharpening_oil", "electronics", "tactical_gloves"],
		[20, 14, 20, 16, 8, 14, 3], 1, [], [1, 1, 1, 2, 1, 1, 1])
	_table("dead_coast_cache", LootTable.Source.CRATE, 1.0,
		["bandage", "credits_small", "coastal_alloy", "scrap_metal", "cloth_scrap", "antiseptic"],
		[20, 22, 14, 16, 12, 8], 1, [], [2, 1, 2, 2, 2, 1])
	_table("dead_coast_depot", LootTable.Source.HIDDEN, 1.0,
		["credits_medium", "coastal_alloy", "armor_plate", "teleport_cell", "sharpening_oil", "field_boots", "combat_helmet"],
		[18, 18, 14, 6, 8, 3, 3], 2, ["health_potion"], [1, 3, 1, 1, 1, 1, 1])
