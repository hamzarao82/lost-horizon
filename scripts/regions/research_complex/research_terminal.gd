class_name ResearchTerminal
extends Terminal
## A Terminal for the facility: optionally needs power (`requires_flag`, from Terminal) and a credential
## level, and shows its pages. The first read sets `doc_<id>_found`, which Progression already pays a
## discovery bonus for exactly once (no separate XP here, so the economy has a single source), and
## marks the read in the region state.

@export var credential: StringName = &""
@export var show_model: bool = true


func _ready() -> void:
	super._ready()
	if show_model:
		FacilityProps.add_console(self, Color(0.25, 0.8, 0.55))


func read_claim_id() -> StringName:
	return StringName("terminal_%s_read" % String(interaction_id))


func found_flag() -> StringName:
	return StringName("doc_%s_found" % String(interaction_id))


func _refresh_lock() -> void:
	var state := get_node_or_null("/root/WorldState")
	var powered: bool = requires_flag == &"" or (state != null and state.has_flag(requires_flag))
	var cleared: bool = credential == &"" or (state != null and state.has_flag(FacilityIds.credential_flag(credential)))
	locked = not (powered and cleared)
	if not powered:
		locked_text = "%s: no power" % terminal_title
	elif not cleared:
		locked_text = "%s: %s credential required" % [terminal_title, String(credential)]


func _on_flag_changed(id: StringName, _value: bool) -> void:
	if id == &"*" or id == requires_flag or (credential != &"" and id == FacilityIds.credential_flag(credential)):
		_refresh_lock()


func _on_interact(player: Node3D) -> void:
	super(player)
	FacilityIds.set_flag(found_flag())
	PersistentIds.claim(FacilityIds.REGION, read_claim_id())
