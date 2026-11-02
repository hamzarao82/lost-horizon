extends Node
## Autoload "RunStats": what the player did this run, for the death and results screens.
## Counts only real gameplay events (Enemy.defeated, Inventory.item_collected, WorldState flags);
## time counts while the player is alive in an unpaused world. Saved additively as `stats`.

const MAX_SECONDS: float = 360000.0
const MAX_COUNT: int = 100000
const KILLER_RANGE: float = 9.0

var seconds_played: float = 0.0
var enemies_defeated: int = 0
var pickups: int = 0
var last_attacker_name: String = ""

var _player: Player
var _player_health: HealthComponent


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	if _player != null and is_instance_valid(_player) and not _player.is_dead():
		seconds_played = minf(seconds_played + delta, MAX_SECONDS)


func reset() -> void:
	seconds_played = 0.0
	enemies_defeated = 0
	pickups = 0
	last_attacker_name = ""


func to_dict() -> Dictionary:
	return {"seconds": snappedf(seconds_played, 0.1), "kills": enemies_defeated, "pickups": pickups}


## Hostile or damaged data becomes safe numbers; unknown keys are dropped.
static func sanitize(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var data: Dictionary = raw
	return {
		"seconds": clampf(float(data.get("seconds", 0.0)), 0.0, MAX_SECONDS),
		"kills": clampi(int(data.get("kills", 0)), 0, MAX_COUNT),
		"pickups": clampi(int(data.get("pickups", 0)), 0, MAX_COUNT),
	}


func from_dict(raw: Variant) -> void:
	var data := sanitize(raw)
	if data.is_empty():
		return
	seconds_played = data["seconds"]
	enemies_defeated = data["kills"]
	pickups = data["pickups"]


## Lore documents read (`doc_<id>_found`) plus supply crates taken (`<id>_taken`).
func secrets_found() -> int:
	var world := get_node_or_null("/root/WorldState")
	if world == null:
		return 0
	var count := 0
	for id in world.to_dict().get("flags", []):
		var text := String(id)
		if (text.begins_with("doc_") and text.ends_with("_found")) or text.ends_with("_taken"):
			count += 1
	return count


## Documents and crates that exist in the loaded world (never less than what was found).
func secrets_total() -> int:
	var total := 0
	for node in get_tree().get_nodes_in_group("interactables"):
		if node is LoreDocument or node is SupplyCrate:
			total += 1
	return maxi(total, secrets_found())


func documents_found() -> int:
	var world := get_node_or_null("/root/WorldState")
	if world == null:
		return 0
	var count := 0
	for id in world.to_dict().get("flags", []):
		var text := String(id)
		if text.begins_with("doc_") and text.ends_with("_found"):
			count += 1
	return count



# --- event wiring ---------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is Enemy:
		if not node.has_meta(&"runstats_bound"):
			node.set_meta(&"runstats_bound", true)
			(node as Enemy).defeated.connect(_on_enemy_defeated)
	elif node is Inventory:
		var inventory := node as Inventory
		if not inventory.item_collected.is_connected(_on_item_collected):
			inventory.item_collected.connect(_on_item_collected)
	elif node is Player:
		_bind_player(node as Player)


func _bind_player(player: Player) -> void:
	_player = player
	last_attacker_name = ""
	_player_health = null
	# player.health is created in the Player's own _ready; wait one frame so it exists.
	_connect_player_health.call_deferred(player)


func _connect_player_health(player: Player) -> void:
	if not is_instance_valid(player) or player != _player or player.health == null:
		return
	_player_health = player.health
	_player_health.damaged.connect(_on_player_damaged)
	var host := player.get_parent()
	if host != null and host.get_node_or_null("DeathScreen") == null:
		var death := DeathScreen.new()
		death.name = "DeathScreen"
		host.add_child(death)
		var results := ResultsScreen.new()
		results.name = "ResultsScreen"
		host.add_child(results)


func _on_enemy_defeated() -> void:
	enemies_defeated = mini(enemies_defeated + 1, MAX_COUNT)


func _on_item_collected(_item: ItemData, kept: bool) -> void:
	if kept:
		pickups = mini(pickups + 1, MAX_COUNT)


## The game has no per-hit attacker id, so the cause is the nearest living enemy, preferring
## one that is mid-attack. Good enough for a hint; shown as "Unknown" when nobody is close.
func _on_player_damaged(_amount: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var best: Enemy
	var best_score := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead():
			continue
		var distance := enemy.global_position.distance_to(_player.global_position)
		if distance > KILLER_RANGE:
			continue
		var score := distance - (3.0 if enemy.state == Enemy.State.ATTACK else 0.0)
		if score < best_score:
			best_score = score
			best = enemy
	if best != null:
		last_attacker_name = best.display_name
