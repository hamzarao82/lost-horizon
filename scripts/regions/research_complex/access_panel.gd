class_name AccessPanel
extends Interactable
## A swipe panel that grants a credential level (flag `credential_<level>`), once. It can need a flag first
## (for example a keycard found elsewhere). The grant is remembered through WorldState and PersistentIds.

@export var grants: StringName = &"admin"
@export var requires_flag: StringName = &""
@export var show_model: bool = true


func _ready() -> void:
	super._ready()
	if show_model:
		FacilityProps.add_console(self, Color(0.95, 0.7, 0.2))
	one_shot = true
	prompt_text = "Swipe for %s access" % String(grants)
	locked_text = "Panel dead: needs a keycard"
	interact_radius = maxf(interact_radius, 2.4)
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.flag_changed.connect(_on_flag_changed)
		if state.has_flag(FacilityIds.credential_flag(grants)):
			mark_used()
	_refresh_lock()


func claim_id() -> StringName:
	return StringName("panel_%s" % String(interaction_id))


func _refresh_lock() -> void:
	locked = requires_flag != &"" and not FacilityIds.has_flag(requires_flag)


func _on_flag_changed(id: StringName, _value: bool) -> void:
	if id == &"*" or id == requires_flag:
		_refresh_lock()


func _on_interact(_player: Node3D) -> void:
	FacilityIds.set_flag(FacilityIds.credential_flag(grants))
	PersistentIds.claim(FacilityIds.REGION, claim_id())
	Outpost17.say(self, "%s credential granted." % String(grants).capitalize(), 3.0)
