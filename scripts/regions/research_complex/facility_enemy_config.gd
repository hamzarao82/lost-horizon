class_name FacilityEnemyConfig
extends Resource
## Data for one Research Complex enemy: which existing scene to instantiate and which stats to apply.
## No new AI per enemy: the config is copied onto the Enemy's exports before it enters the tree.

@export var id: StringName
@export var display_name: String = "Guard"
## Scene that is instantiated (PatrolSoldier / HeavySoldier, or one of the two subject scenes).
@export var base_scene_path: String = "res://scenes/enemies/PatrolSoldier.tscn"
@export var hit_points: float = 70.0
@export var move_speed: float = 3.2
@export var body_color: Color = Color(0.35, 0.42, 0.5)
@export var body_scale: float = 1.0
@export_range(0.0, 1.0) var stagger_resist: float = 0.0
@export var swing_path: String = "res://resources/attacks/enemy_swing.tres"
@export var cooldown_min: float = 1.0
@export var cooldown_max: float = 1.6
@export_range(0.0, 1.0) var dodge_chance: float = 0.0
@export var attack_range: float = 1.9
@export var detection_range: float = 14.0
@export var loot_table_path: String = ""
## Subjects never patrol; guards may be given a route by their spawn point.
@export var patrols: bool = true
## Unique reward that a cleared enemy owes the player until it is picked up (empty = none).
@export var reward_item_path: String = ""



## Copies the stats onto a freshly instantiated Enemy (call before add_child).
func apply(enemy: Enemy) -> void:
	enemy.display_name = display_name
	enemy.hit_points = hit_points
	enemy.move_speed = move_speed
	enemy.body_color = body_color
	enemy.body_scale = body_scale
	enemy.stagger_resist = stagger_resist
	enemy.swing_path = swing_path
	enemy.cooldown_min = cooldown_min
	enemy.cooldown_max = cooldown_max
	enemy.dodge_chance = dodge_chance
	enemy.attack_range = attack_range
	enemy.detection_range = detection_range
	if loot_table_path != "":
		enemy.loot_table_path = loot_table_path


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("config id is empty")
	if not ResourceLoader.exists(base_scene_path):
		errors.append("%s: base scene missing" % id)
	if not ResourceLoader.exists(swing_path):
		errors.append("%s: swing attack missing" % id)
	if hit_points <= 0.0 or move_speed <= 0.0:
		errors.append("%s: hit points and speed must be positive" % id)
	return errors
