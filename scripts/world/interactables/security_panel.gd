class_name SecurityPanel
extends Interactable
## The damaged power panel in the control room. Inspecting it sets `panel_inspected` (an objective
## for the power puzzle) and tells the player what to do next.

const TEXT: String = "The panel is damaged. Three breakers feed it, and they only take power in the right sequence. Check the security logs."


func _ready() -> void:
	super._ready()
	if interaction_id == &"":
		interaction_id = &"security_panel"
	prompt_text = "Inspect power panel"
	interact_radius = maxf(interact_radius, 2.4)


func _on_interact(_player: Node3D) -> void:
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(&"panel_inspected", true)
	Outpost17.say(self, TEXT, 6.0)
