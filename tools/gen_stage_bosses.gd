extends SceneTree
## Writes the stage boss configs and their unique rewards (re-runnable; overwrites the same files).
## godot --headless --path . -s tools/gen_stage_bosses.gd
## Then run tools/gen_icons.gd so every new item has its icon.

const ITEMS_DIR: String = "res://resources/items/"
const ENEMIES_DIR: String = "res://resources/enemies/"

## id, name, slot, rarity, stats, value, region, description
const ITEMS: Array = [
	["dc_harbor_cap", "Harbor Commander's Cap", ItemData.Slot.HEAD, ItemData.Rarity.RARE,
		{"damage_reduction": 0.03, "max_health": 6.0}, 90, "dead_coast",
		"A salt-stained officer's cap with a checkpoint pin. Whoever wore it never left the harbor road."],
	["dc_cove_gloves", "Cove Boss's Gloves", ItemData.Slot.GLOVES, ItemData.Rarity.EPIC,
		{"damage_mult": 1.04}, 120, "dead_coast",
		"Scarred hauling gloves with a smuggler's tally stitched inside. They grip a blade as hard as a crate."],
	["bw_chief_boots", "Patrol Chief's Boots", ItemData.Slot.LEGS, ItemData.Rarity.RARE,
		{"move_speed_mult": 1.04, "damage_reduction": 0.02}, 90, "blackwood",
		"Jungle boots worn to the shape of one man's stride. The trail lanterns were set to his pace."],
	["bw_overseer_badge", "Site Overseer's Badge", ItemData.Slot.ACCESSORY, ItemData.Rarity.EPIC,
		{"damage_reduction": 0.04, "max_health": 10.0}, 130, "blackwood",
		"A testing-site access badge with every clearance box ticked. The photograph has been scratched out."],
	["rc_commander_visor", "Facility Commander's Visor", ItemData.Slot.HEAD, ItemData.Rarity.EPIC,
		{"damage_reduction": 0.04, "max_health": 8.0}, 130, "research_complex",
		"A tactical visor tuned to the laboratory's camera network. It still shows the last room it watched."],
]

## id, name, hp, armor, colour, scale, weights {claw, ring, charge}, loot table, reward id
const MELEE_BOSSES: Array = [
	["dc_harbor_commander", "Harbor Commander", 340.0, 40.0, Color(0.2, 0.42, 0.5), 1.35,
		{"claw_weight": 3.0, "ring_weight": 0.0, "charge_weight": 2.0}, "res://resources/loot/dead_coast_elite.tres", "dc_harbor_cap"],
	["dc_cove_boss", "Cove Boss", 430.0, 60.0, Color(0.55, 0.35, 0.15), 1.6,
		{"claw_weight": 1.0, "ring_weight": 3.0, "charge_weight": 0.0}, "res://resources/loot/dead_coast_elite.tres", "dc_cove_gloves"],
	["bw_patrol_chief", "Patrol Chief", 350.0, 30.0, Color(0.25, 0.4, 0.2), 1.3,
		{"claw_weight": 2.0, "ring_weight": 0.0, "charge_weight": 3.0}, "res://resources/loot/enemy_miniboss.tres", "bw_chief_boots"],
	["bw_site_overseer", "Site Overseer", 450.0, 70.0, Color(0.3, 0.35, 0.45), 1.5,
		{"claw_weight": 2.0, "ring_weight": 3.0, "charge_weight": 1.0}, "res://resources/loot/enemy_miniboss.tres", "bw_overseer_badge"],
]


func _initialize() -> void:
	for spec in ITEMS:
		var item := ItemData.new()
		item.item_id = StringName(spec[0])
		item.display_name = String(spec[1])
		item.kind = ItemData.Kind.ARMOR
		item.rarity = spec[3]
		item.description = String(spec[7])
		item.slot = spec[2]
		item.base_stats = spec[4]
		item.value = int(spec[5])
		item.unique = true
		item.region = String(spec[6])
		print("ITEM ", spec[0], " save=", ResourceSaver.save(item, ITEMS_DIR + String(spec[0]) + ".tres"))
	for spec in MELEE_BOSSES:
		var config := EnemyConfig.new()
		config.scene_path = "res://scenes/enemies/StageBoss.tscn"
		config.display_name = String(spec[1])
		config.hit_points = float(spec[2])
		config.armor = float(spec[3])
		config.body_color = spec[4]
		config.body_scale = float(spec[5])
		config.stagger_resist = 0.7
		config.swing_path = "res://resources/attacks/experimental_claw.tres"
		config.loot_table_path = String(spec[7])
		config.move_speed = 3.0
		config.detection_range = 18.0
		config.attack_range = 3.0
		config.cooldown_min = 1.4
		config.cooldown_max = 2.0
		config.extras = spec[6]
		print("CONFIG ", spec[0], " save=", ResourceSaver.save(config, ENEMIES_DIR + String(spec[0]) + ".tres"))
	# The Research Complex's laboratory commander becomes the stage's second boss: same ranged brain as
	# facility_commander.tres, more health and armor, bigger, with the boss bar and a unique reward.
	var commander := (load(ENEMIES_DIR + "facility_commander.tres") as EnemyConfig).duplicate(true) as EnemyConfig
	commander.display_name = "Facility Commander"
	commander.hit_points = 380.0
	commander.armor = 80.0
	commander.body_scale = 1.3
	commander.stagger_resist = 0.5
	commander.unique_drop_path = ""  # the boss helper owns the reward (and restores it after a reload)
	print("CONFIG rc_facility_commander_boss save=", ResourceSaver.save(commander, ENEMIES_DIR + "rc_facility_commander_boss.tres"))
	quit()
