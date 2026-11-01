extends Node
## Autoload "Teleport": gives every Player a TeleportAbility child, so no scene or player.gd edit
## is needed. The ability's state lives in a file, so a scene reload never refunds charges.


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().get_nodes_in_group("player"):
		_attach(node)


func _on_node_added(node: Node) -> void:
	if node is Player:
		_attach.call_deferred(node)


func _attach(node: Node) -> void:
	var player := node as Player
	if player == null or not is_instance_valid(player) or player.get_node_or_null("TeleportAbility"):
		return
	var ability := TeleportAbility.new()
	ability.name = "TeleportAbility"
	player.add_child(ability)


func _exit_tree() -> void:
	# Headless runs (tests) use a throw-away per-process file; never leave it behind.
	if DisplayServer.get_name() == "headless":
		var path := TeleportAbility.default_save_path()
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
