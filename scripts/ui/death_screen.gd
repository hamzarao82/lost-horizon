class_name DeathScreen
extends CanvasLayer
## Informational overlay for the two seconds between the player's death and the scene reload
## (player.gd owns that reload). Shows the cause, where the player will wake up and a hint.

const FADE_SECONDS: float = 0.6
const WAVE_RESPAWN: String = "__wave__"  # died in the arena waves: the wave checkpoint applies
const CHECKPOINT_NAMES: Dictionary = {
	"checkpoint_b": "Military Compound checkpoint",
	"checkpoint_c": "Research Access Facility checkpoint",
	"checkpoint_d": "Command Center checkpoint",
}
const HINTS: Array[String] = [
	"Dodge through a heavy attack: the roll protects you for the first 0.18 seconds.",
	"Press R for a medkit. You can tap it mid-swing.",
	"Lock on with Tab or middle mouse to keep a fast enemy in front of you.",
	"Fight at a doorway: enemies can only reach you one at a time.",
	"Better weapons and armor equip themselves when you walk over them.",
	"Activate a checkpoint terminal to set where you return after a defeat.",
	"The Warden's red windup is slow. Step out of it, then strike its back.",
]

var _root: Control
var _cause: Label
var _respawn: Label
var _hint: Label
var _tween: Tween


func _init() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("death_screen")
	_build_ui()


func _ready() -> void:
	_connect_player.call_deferred()


func is_showing() -> bool:
	return _root.visible


func cause_text() -> String:
	return _cause.text


func respawn_text() -> String:
	return _respawn.text


func hint_text() -> String:
	return _hint.text


static func cause_line(killer: String) -> String:
	return "Killed by: %s" % (killer if killer != "" else "Unknown")


## Friendly place name: a known checkpoint, else the area that contains the checkpoint, else the start.
static func respawn_line(checkpoint_id: String, position: Variant = null) -> String:
	if checkpoint_id == WAVE_RESPAWN:
		return "Respawn: the current wave"
	if checkpoint_id == "":
		return "Respawn: start of the island"
	if CHECKPOINT_NAMES.has(checkpoint_id):
		return "Respawn: " + str(CHECKPOINT_NAMES[checkpoint_id])
	if position is Array and (position as Array).size() >= 3:
		var flat := Vector2(float(position[0]), float(position[2]))
		for id: StringName in [&"area_d_command", &"area_c_research", &"area_b_compound", &"area_a_perimeter"]:
			if (Outpost17.AREAS[id]["rect"] as Rect2).has_point(flat):
				return "Respawn: " + str(Outpost17.AREAS[id]["name"])
	return "Respawn: last checkpoint"


## Fills the texts and fades the overlay in. `hint_index` < 0 picks a random hint.
func show_death(killer: String, checkpoint_id: String, position: Variant = null, hint_index: int = -1) -> void:
	_cause.text = cause_line(killer)
	_respawn.text = respawn_line(checkpoint_id, position)
	_hint.text = "Tip: " + HINTS[hint_index if hint_index >= 0 else randi() % HINTS.size()]
	_root.visible = true
	_root.modulate.a = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_SECONDS)


func hide_death() -> void:
	_root.visible = false


func _connect_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and player.health:
		player.health.died.connect(_on_player_died, CONNECT_ONE_SHOT)


func _on_player_died() -> void:
	var stats := get_node_or_null("/root/RunStats")
	var saves := get_node_or_null("/root/SaveManager")
	var killer: String = stats.last_attacker_name if stats else ""
	var checkpoint_id: String = saves.checkpoint_id if saves else ""
	var position: Variant = saves.world_checkpoint.get("position", null) if saves else null
	if saves and not bool(saves.get("_respawn_pending")) and not saves.checkpoint.is_empty():
		checkpoint_id = WAVE_RESPAWN
	show_death(killer, checkpoint_id, position)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = HudTheme.theme()
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.0, 0.0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(620, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "YOU DIED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	box.add_child(title)
	_cause = _line(box, 26, HudTheme.TEXT)
	_respawn = _line(box, 22, HudTheme.GOLD)
	_hint = _line(box, 18, HudTheme.TEXT_DIM)


func _line(parent: Control, size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
