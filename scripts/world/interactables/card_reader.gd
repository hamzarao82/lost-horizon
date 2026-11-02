class_name CardReader
extends Interactable
## Opens a linked Door when the player holds the access card (WorldState flag `has_access_card`).

@export var door_id: StringName
@export var required_flag: StringName = &"has_access_card"


func _ready() -> void:
	super._ready()
	prompt_text = "Swipe access card"
	locked_text = "Access card required"
	interact_radius = maxf(interact_radius, 2.4)
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.flag_changed.connect(_on_flag_changed)
	_refresh_lock()


func _refresh_lock() -> void:
	var state := get_node_or_null("/root/WorldState")
	locked = not (state != null and state.has_flag(required_flag))


func _on_flag_changed(id: StringName, _value: bool) -> void:
	if id == required_flag or id == &"*":
		_refresh_lock()


func _on_interact(_player: Node3D) -> void:
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(StringName("reader_%s_used" % String(interaction_id)), true)
	for node in get_tree().get_nodes_in_group("doors"):
		var door := node as Door
		if door != null and door.door_id == door_id:
			door.open(true)
	Outpost17.say(self, "Access granted.", 2.5)
