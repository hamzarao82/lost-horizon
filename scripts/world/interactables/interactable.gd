class_name Interactable
extends Area3D
## Something the player can use with the interact key (E / gamepad X / touch "Use").
## Selection is by distance (see Interactor), so the Area3D has no shape and costs no physics.

signal interacted(player: Node3D)

@export var interaction_id: StringName
@export var prompt_text: String = "Use"
## Shown instead of prompt_text while `locked` is true (the object is visible but not usable yet).
@export var locked_text: String = ""
@export var one_shot: bool = false
@export var enabled: bool = true
@export var interact_radius: float = 2.2

var locked: bool = false

var _used: bool = false


func _ready() -> void:
	add_to_group("interactables")
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false


func is_used() -> bool:
	return _used


## Worth showing a prompt for: enabled and not already consumed. Locked objects still show their
## locked text so the player learns why nothing happens.
func is_available() -> bool:
	return enabled and not (one_shot and _used)


func can_interact() -> bool:
	return is_available() and not locked


func current_prompt() -> String:
	if locked and locked_text != "":
		return locked_text
	return prompt_text


## Returns true if the interaction really happened (false for locked, used or disabled objects).
func interact(player: Node3D) -> bool:
	if not is_available():
		return false
	var state := get_node_or_null("/root/WorldState")
	if locked:
		if state:
			state.emit_interacted(StringName(String(interaction_id) + "_locked"))
		return false
	_used = true
	_on_interact(player)
	interacted.emit(player)
	if state:
		state.emit_interacted(interaction_id)
	return true


## Subclasses put their effect here (it runs before the `interacted` signal).
func _on_interact(_player: Node3D) -> void:
	pass


## Restore the consumed state without running the effect (loading a save, scene reload).
func mark_used(value: bool = true) -> void:
	_used = value
