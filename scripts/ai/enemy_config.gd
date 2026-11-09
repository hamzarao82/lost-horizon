class_name EnemyConfig
extends Resource
## A reusable enemy variant: which scene to build and which Enemy exports to override. New enemy
## variants (Milestone 8 and 9) are one .tres of this type, not a new AI class.

@export var scene_path: String = "res://scenes/enemies/PatrolSoldier.tscn"
@export var display_name: String = "Soldier"
@export var hit_points: float = 60.0
## Armor pool in front of health (0 = none). All incoming damage drains it first.
@export var armor: float = 0.0
@export var body_color: Color = Color(0.55, 0.25, 0.2)
@export var body_scale: float = 1.0
@export_range(0.0, 1.0) var stagger_resist: float = 0.0
@export var swing_path: String = "res://resources/attacks/enemy_swing.tres"
@export var loot_table_path: String = ""
@export var move_speed: float = 3.2
@export var detection_range: float = 14.0
@export var attack_range: float = 1.9
@export var ring_distance: float = 3.4
@export var cooldown_min: float = 1.0
@export var cooldown_max: float = 1.6
## Opt-in ally alert: when this enemy notices the player, nearby idle allies join the fight.
@export var coordinate_alarm: bool = false
@export var ranged: RangedConfig
## A unique item (resource path) dropped once per save: skipped when the player already owns the claim.
@export var unique_drop_path: String = ""
## Extra exports of the enemy class, applied by name when the enemy has the property (for example a stage
## boss's attack weights). Unknown names are ignored, so a config can never break an enemy that lacks them.
@export var extras: Dictionary = {}


## Writes the overrides onto an enemy that is not in the tree yet.
func apply(enemy: Enemy) -> void:
	enemy.display_name = display_name
	enemy.hit_points = hit_points
	enemy.body_color = body_color
	enemy.body_scale = body_scale
	enemy.stagger_resist = stagger_resist
	enemy.swing_path = swing_path
	enemy.loot_table_path = loot_table_path
	enemy.move_speed = move_speed
	enemy.detection_range = detection_range
	enemy.attack_range = attack_range
	enemy.ring_distance = ring_distance
	enemy.cooldown_min = cooldown_min
	enemy.cooldown_max = cooldown_max
	enemy.coordinate_alarm = coordinate_alarm
	enemy.ranged = ranged
	for key: Variant in extras:
		if enemy.get(String(key)) != null:
			enemy.set(String(key), extras[key])


## Builds the enemy at `at` (position is set before it joins the tree so it never overlaps the player
## at the origin), adds it under `parent`, and fits the armor pool and the unique drop.
func spawn(parent: Node, at: Vector3) -> Enemy:
	var enemy := (load(scene_path) as PackedScene).instantiate() as Enemy
	apply(enemy)
	enemy.position = at
	enemy.set_meta(&"enemy_config", self)  # keeps this resource (and its unique-drop callback) alive as long as the enemy
	parent.add_child(enemy)
	if armor > 0.0:
		enemy._health.set_armor(armor)
	if unique_drop_path != "":
		enemy.defeated.connect(_drop_unique.bind(enemy))
	return enemy


func _drop_unique(enemy: Enemy) -> void:
	var tree := enemy.get_tree()
	if tree == null:
		return
	var item := load(unique_drop_path) as ItemData
	var player := tree.get_first_node_in_group("player") as Player
	if item == null or player == null:
		return
	if player.inventory.is_unique_claimed(String(item.item_id)):
		return  # already received on this save: never drops twice
	Pickup.spawn.call_deferred(enemy.get_parent(), item, Vector3(enemy.global_position.x, 0.0, enemy.global_position.z))
