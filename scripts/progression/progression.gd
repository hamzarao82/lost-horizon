extends Node
## Autoload "Progression": owns the PlayerProgress state and connects it to gameplay.
## XP arrives through signals only (Enemy.defeated, QuestManager.quest_completed, WorldState flags),
## and results go back out as additive multipliers the player, teleport and economy read.
## See docs/PROGRESSION_SYSTEM.md. Save integration is Progression.to_dict() / from_dict().

signal xp_gained(amount: int, source: String)
signal level_up(level: int)
signal points_changed
signal skill_changed(id: StringName)
signal currency_changed(amount: int)

const CONFIG_PATH: String = "res://resources/progression/progression_config.tres"
const ATTRIBUTE_DIR: String = "res://resources/progression/attributes/"

var config: ProgressionConfig
var attribute_defs: Array = []
var tree: SkillTree
var progress: PlayerProgress

var _player: Player


func _ready() -> void:
	config = load(CONFIG_PATH) as ProgressionConfig
	if config == null:
		config = ProgressionConfig.new()
	for file in DirAccess.get_files_at(ATTRIBUTE_DIR):
		var file_name := file.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			var def := load(ATTRIBUTE_DIR + file_name) as AttributeData
			if def:
				attribute_defs.append(def)
	attribute_defs.sort_custom(func(a: AttributeData, b: AttributeData) -> bool: return String(a.id) < String(b.id))
	tree = SkillTree.load_default()
	progress = PlayerProgress.new(config)
	get_tree().node_added.connect(_on_node_added)
	var quests := get_node_or_null("/root/QuestManager")
	if quests and quests.has_signal("quest_completed"):
		quests.quest_completed.connect(_on_quest_completed)
	var world := get_node_or_null("/root/WorldState")
	if world and world.has_signal("flag_changed"):
		world.flag_changed.connect(_on_flag_changed)


# --- state ------------------------------------------------------------------

func level() -> int:
	return progress.level()


func reset() -> void:
	progress = PlayerProgress.new(config)
	_notify_changed()


func to_dict() -> Dictionary:
	return progress.to_dict()


func from_dict(raw: Variant) -> void:
	progress.from_dict(raw, attribute_defs, tree.skills.values())
	_prune_skills(progress)
	_notify_changed()


## Validated copy of saved progression for the save layer, so unknown or inconsistent data never
## reaches the game state.
func sanitize(raw: Variant) -> Dictionary:
	var temp := PlayerProgress.new(config)
	temp.from_dict(raw, attribute_defs, tree.skills.values())
	_prune_skills(temp)
	return temp.to_dict()


## from_dict only checks point budgets. A hand-edited save could still own a skill whose prerequisite
## or level requirement is missing: drop those ranks and refund their points, until nothing changes.
func _prune_skills(target: PlayerProgress) -> void:
	var changed := true
	while changed:
		changed = false
		for id in target.skills.keys():
			var skill := tree.get_skill(StringName(id))
			var valid := skill != null and target.level() >= skill.min_level
			if valid:
				for pre in skill.prerequisites:
					if target.skill_rank(StringName(pre)) < 1:
						valid = false
			if not valid:
				var refund: int = int(target.skills[id]) * (skill.cost if skill else 0)
				target.skill_points += refund
				target.skills.erase(id)
				changed = true


func attribute_def(id: StringName) -> AttributeData:
	for def: AttributeData in attribute_defs:
		if def.id == id:
			return def
	return null


# --- XP ---------------------------------------------------------------------

func award_xp(amount: int, source: String = "") -> void:
	if amount <= 0:
		return
	var gained := progress.add_xp(amount)
	xp_gained.emit(amount, source)
	if gained > 0:
		level_up.emit(progress.level())
	_notify_changed()


## Kill XP with both anti-grind factors; counts the kill against its enemy name.
func award_kill(enemy: Node) -> int:
	var tier := StatsResolver.tier_of(enemy)
	var key := String(enemy.get("display_name")) if "display_name" in enemy else String(tier)
	var previous := int(progress.kill_counts.get(key, 0))
	progress.kill_counts[key] = mini(previous + 1, 100000)
	var amount := StatsResolver.kill_xp(config, tier, progress.level(), previous)
	award_xp(amount, "kill")
	return amount


func award_discovery(id: String) -> bool:
	if id == "" or progress.discoveries.has(id) or progress.discoveries.size() >= PlayerProgress.MAX_LIST:
		return false
	progress.discoveries.append(id)
	award_xp(config.discovery_xp, "discovery")
	return true


func award_quest(quest_id: StringName) -> bool:
	var key := String(quest_id)
	if progress.rewarded_quests.has(key):
		return false  # reloading or replaying never pays twice
	progress.rewarded_quests.append(key)
	award_xp(int(config.quest_xp.get(quest_id, config.default_quest_xp)), "quest")
	return true


# --- points -----------------------------------------------------------------

func spend_attribute_point(id: StringName) -> bool:
	var def := attribute_def(id)
	if def == null or progress.attribute_points < 1:
		return false
	if progress.attribute_value(id, def) >= def.max_points:
		return false
	progress.attribute_points -= 1
	progress.attributes[id] = int(progress.attributes.get(id, 0)) + 1
	_notify_changed()
	return true


func unlock_skill(id: StringName) -> bool:
	if not tree.buy(progress, id):
		return false
	skill_changed.emit(id)
	_notify_changed()
	return true


# --- currency ---------------------------------------------------------------

## Earned currency gets the Scavenger bonus; pass bonus = false for refunds and sales adjustments.
func add_currency(amount: int, bonus: bool = true) -> int:
	if amount <= 0:
		return 0
	var scaled := roundi(amount * (currency_multiplier() if bonus else 1.0))
	progress.currency = mini(progress.currency + scaled, PlayerProgress.MAX_CURRENCY)
	currency_changed.emit(progress.currency)
	return scaled


func spend_currency(amount: int) -> bool:
	if amount < 0 or progress.currency < amount:
		return false
	progress.currency -= amount
	currency_changed.emit(progress.currency)
	return true


func currency() -> int:
	return progress.currency


# --- multipliers read by gameplay ---------------------------------------------

func attack_multiplier(data: AttackData) -> float:
	return damage_multiplier(StatsResolver.kind_of(data.id))


func damage_multiplier(kind: StringName) -> float:
	return StatsResolver.damage_multiplier(kind, progress, attribute_defs, tree, _equipment_stats())


func incoming_multiplier() -> float:
	return StatsResolver.incoming_multiplier(progress, attribute_defs, tree, _equipment_stats())


func max_health_bonus() -> float:
	return StatsResolver.max_health_bonus(progress, attribute_defs, tree, _equipment_stats())


func heal_multiplier() -> float:
	return StatsResolver.heal_mult(progress, attribute_defs, tree)


func currency_multiplier() -> float:
	return StatsResolver.currency_mult(progress, attribute_defs, tree)


func teleport_recharge_multiplier() -> float:
	return StatsResolver.teleport_recharge_mult(progress, attribute_defs, tree)


func dodge_cost_multiplier() -> float:
	return StatsResolver.dodge_cost_mult(progress, attribute_defs, tree)


## Equipment's contribution (gear bonuses other than the weapon multiplier, which Inventory still
## applies at the call site). Supplied by Inventory.stat_totals() when the equipment system has it.
func _equipment_stats() -> Dictionary:
	if is_instance_valid(_player):
		var inventory: Object = _player.get("inventory")
		if inventory != null and inventory.has_method("stat_totals"):
			var gear := StatsResolver.equipment(inventory.stat_totals())
			gear[&"damage_mult"] = 1.0  # Inventory.damage_multiplier() already carries weapon, worn gear and buffs at the call site
			return gear
	return StatsResolver.DEFAULT_EQUIPMENT


# --- applying to the player ----------------------------------------------------

## Writes derived stats onto the player from the captured base values. Safe to call any time
## (level up, attribute, skill, equipment change); at level 1 with nothing spent it changes nothing.
func refresh_player() -> void:
	if not is_instance_valid(_player) or _player.health == null:
		return
	var player := _player
	if not player.has_meta(&"prog_base"):
		player.set_meta(&"prog_base", {
			"health": player.health.max_health, "stamina": player.max_stamina, "regen": player.stamina_regen,
			"walk": player.walk_speed, "sprint": player.sprint_speed, "dodge": player.dodge_stamina,
		})
	var base: Dictionary = player.get_meta(&"prog_base")
	var new_max: float = maxf(base["health"] + max_health_bonus(), 1.0)
	var delta: float = new_max - player.health.max_health
	player.health.max_health = new_max
	if delta > 0.0 and not player.health.is_dead():
		player.health.health = minf(player.health.health + delta, new_max)  # growth is granted, not just room
	player.health.health = minf(player.health.health, new_max)
	player.health.changed.emit(player.health.health, new_max)
	player.max_stamina = base["stamina"] + StatsResolver.max_stamina_bonus(progress, attribute_defs, tree)
	player.stamina = minf(player.stamina, player.max_stamina)
	player.stamina_regen = base["regen"] * StatsResolver.stamina_regen_mult(progress, attribute_defs, tree)
	var speed := StatsResolver.move_speed_mult(progress, attribute_defs, tree, _equipment_stats())
	player.walk_speed = base["walk"] * speed
	player.sprint_speed = base["sprint"] * speed
	player.dodge_stamina = base["dodge"] * dodge_cost_multiplier()


func _notify_changed() -> void:
	points_changed.emit()
	refresh_player()


# --- event wiring --------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is Enemy:
		if not node.has_meta(&"progression_bound"):
			node.set_meta(&"progression_bound", true)
			(node as Enemy).defeated.connect(_on_enemy_defeated.bind(node))
	elif node is Player:
		_player = node as Player
		refresh_player.call_deferred()  # the player builds its HealthComponent in its own _ready


func _on_enemy_defeated(enemy: Node) -> void:
	award_kill(enemy)


func _on_quest_completed(quest_id: StringName) -> void:
	award_quest(quest_id)


func _on_flag_changed(id: StringName, value: bool) -> void:
	if not value:
		return
	var text := String(id)
	if (text.begins_with("doc_") and text.ends_with("_found")) or text.ends_with("_taken"):
		award_discovery(text)
