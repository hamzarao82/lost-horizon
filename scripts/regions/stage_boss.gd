class_name StageBoss
extends Node3D
## One stage boss, placed with purpose at a fixed spot of a region. The node itself marks the spawn
## (group "stage_boss_spawns", so the objective arrow can lead to it before it exists). It:
##   - spawns the boss from an EnemyConfig once per save: nothing spawns when the defeat is already claimed;
##   - adds the boss to the group "boss" so the HUD shows its health bar;
##   - on defeat sets the saved flag `<region>_boss_<n>_defeated`, claims PersistentIds, says the defeat line
##     and drops the unique reward when this save does not own it yet;
##   - after a reload with the boss down and the reward never picked up, puts the reward back at the spawn.
## All ids use [a-z0-9_] and stay within 48 characters (WorldState drops anything else on load).

const INTRO_RANGE: float = 22.0

var region_id: StringName = &""
var index: int = 1
var config_path: String = ""
var reward_path: String = ""
var intro_line: String = ""
var defeat_line: String = ""
var boss: Enemy

var _intro_said: bool = false
var _reward_given_now: bool = false


static func flag_for(region: StringName, n: int) -> StringName:
	return RegionFlags.key(region, StringName("boss_%d_defeated" % n))


static func claim_for(n: int) -> StringName:
	return StringName("boss_%d" % n)


## Adds one stage boss under `parent` (a region root at the origin) at `pos`.
static func attach(parent: Node3D, region: StringName, n: int, config: String, pos: Vector3, reward: String,
		intro: String, defeat: String) -> StageBoss:
	var stage := StageBoss.new()
	stage.name = "StageBoss%d" % n
	stage.region_id = region
	stage.index = n
	stage.config_path = config
	stage.reward_path = reward
	stage.intro_line = intro
	stage.defeat_line = defeat
	stage.position = pos  # set before add_child
	parent.add_child(stage)
	return stage


func flag() -> StringName:
	return flag_for(region_id, index)


func is_defeated() -> bool:
	var world := get_node_or_null("/root/WorldState")
	return PersistentIds.is_claimed(region_id, claim_for(index)) or (world != null and world.has_flag(flag()))


func _ready() -> void:
	add_to_group("stage_boss_spawns")
	set_physics_process(false)
	if is_defeated():
		_restore_reward.call_deferred()
		return
	_spawn.call_deferred()


## Takes over a boss another part of the region spawns itself (the Research Complex's laboratory commander):
## the health bar, the defeat flag, the claim and the reward work the same way.
func adopt(enemy: Enemy) -> void:
	if enemy == null or boss != null:
		return
	boss = enemy
	boss.defeated.connect(_on_defeated)
	set_physics_process(true)


func _spawn() -> void:
	if config_path == "" or boss != null or not is_inside_tree() or is_defeated():
		return
	var config := load(config_path) as EnemyConfig
	if config == null:
		push_warning("StageBoss: missing config %s" % config_path)
		return
	boss = config.spawn(get_parent(), global_position)
	boss.defeated.connect(_on_defeated)
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _intro_said or boss == null or not is_instance_valid(boss):
		set_physics_process(false)
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and player.global_position.distance_to(boss.global_position) <= INTRO_RANGE:
		_intro_said = true
		# The health bar belongs to a boss the player has come to face, not to one 90 m away that has not
		# noticed anybody: the group (which the HUD reads) is joined here.
		boss.add_to_group("boss")
		if intro_line != "":
			Outpost17.say(self, intro_line, 3.5)
		set_physics_process(false)


func _on_defeated() -> void:
	var at := global_position
	if boss != null and is_instance_valid(boss):
		at = boss.global_position
	PersistentIds.claim(region_id, claim_for(index))
	var world := get_node_or_null("/root/WorldState")
	if world != null:
		world.set_flag(flag(), true)
	if defeat_line != "":
		Outpost17.say(self, defeat_line, 4.0)
	_drop_reward(at)


## Puts the unique reward on the floor unless this save owns it already (the Inventory claims it when picked up).
func _drop_reward(at: Vector3) -> void:
	if reward_path == "" or _reward_given_now:
		return
	var item := load(reward_path) as ItemData
	var player := get_tree().get_first_node_in_group("player")
	if item == null or player == null or EliteExperimentalSubject.reward_owned(player, item) or _reward_on_floor(item):
		return
	_reward_given_now = true
	Pickup.spawn.call_deferred(get_parent(), item, Vector3(at.x, 0.0, at.z))


## A reload after the fight: the boss stays down, and a reward nobody picked up waits where the boss stood.
func _restore_reward() -> void:
	# The player (and the saved inventory claims) may not exist yet while a save is being restored: wait for
	# them, because an owned reward must never be put back.
	for attempt in 40:
		if not is_inside_tree():
			return
		if get_tree().get_first_node_in_group("player") != null:
			break
		await get_tree().create_timer(0.25).timeout
	if not is_inside_tree() or get_tree().get_first_node_in_group("player") == null:
		return
	_drop_reward(global_position)


func _reward_on_floor(item: ItemData) -> bool:
	for node in get_parent().get_children():
		var pickup := node as Pickup
		if pickup != null and pickup.item != null and pickup.item.item_id == item.item_id:
			return true
	return false
