class_name SequenceData
extends Resource
## Data for an ordered-press puzzle: which ids must be pressed in which order.

@export var id: StringName
## Switch ids in the order they must be pressed.
@export var order: PackedStringArray
## World flag that must be set before presses count (e.g. the damaged panel was inspected).
@export var requires_flag: StringName
## World flag set when the whole sequence has been completed.
@export var solved_flag: StringName
## Progress is stored as flags "<prefix>1".."<prefix>N" so it survives a scene reload and saves.
@export var step_flag_prefix: String = "puzzle_step_"
@export var hint_not_ready: String = "The switches do nothing yet. Something is wrong with the panel."
