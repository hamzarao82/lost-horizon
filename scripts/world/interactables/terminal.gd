class_name Terminal
extends Interactable
## A readable computer terminal. Optionally locked until a WorldState flag is set, and optionally
## sets a flag when read (e.g. `next_location_unlocked`). Readable again after the first time.

@export var pages: PackedStringArray
@export var requires_flag: StringName = &""
@export var finish_flag: StringName = &""
@export var terminal_title: String = "Terminal"


func _ready() -> void:
	super._ready()
	prompt_text = "Use %s" % terminal_title.to_lower()
	if locked_text == "":
		locked_text = "%s: no power" % terminal_title
	interact_radius = maxf(interact_radius, 2.4)
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.flag_changed.connect(_on_flag_changed)
	_refresh_lock()


func _refresh_lock() -> void:
	if requires_flag == &"":
		locked = false
		return
	var state := get_node_or_null("/root/WorldState")
	locked = not (state != null and state.has_flag(requires_flag))


func _on_flag_changed(id: StringName, _value: bool) -> void:
	if id == requires_flag or id == &"*":
		_refresh_lock()


func _on_interact(_player: Node3D) -> void:
	for doc_title in DocumentIndex.mark_collected(interaction_id):
		get_tree().call_group("rpg_notifications", "notify_document", doc_title)
	var text := "\n".join(pages)
	Outpost17.say(self, text, clampf(3.0 + text.length() * 0.05, 4.0, 9.0))
	if finish_flag != &"":
		var state := get_node_or_null("/root/WorldState")
		if state:
			state.set_flag(finish_flag, true)
