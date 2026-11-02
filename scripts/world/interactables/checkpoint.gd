class_name Checkpoint
extends Interactable
## A checkpoint post. Using it records the flag `checkpoint_<id>` and asks SaveManager (if present)
## to autosave. Respawn-at-checkpoint is wired by the save step, not here.


func _ready() -> void:
	super._ready()
	prompt_text = "Activate checkpoint"
	interact_radius = maxf(interact_radius, 2.4)


func flag_id() -> StringName:
	var id := String(interaction_id)
	return StringName(id if id.begins_with("checkpoint_") else "checkpoint_" + id)


func _on_interact(_player: Node3D) -> void:
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(flag_id(), true)
	var saves := get_node_or_null("/root/SaveManager")
	var written := false
	if saves and saves.has_method("activate_checkpoint"):
		written = saves.activate_checkpoint(String(interaction_id))
	elif saves and saves.has_method("autosave"):
		written = saves.autosave("checkpoint")
	Outpost17.say(self, "Checkpoint saved." if written else "Checkpoint reached.", 2.5)
