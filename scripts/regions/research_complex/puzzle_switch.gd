class_name PuzzleSwitch
extends Interactable
## A button, lever or terminal face that forwards its id to a puzzle (`input(switch_id)`). Reusable by any
## MultiStepPuzzle; it can be used repeatedly (the puzzle decides what each press means).

@export var puzzle_path: NodePath
@export var switch_id: StringName = &""

var puzzle: Node


func _ready() -> void:
	super._ready()
	if puzzle == null and not puzzle_path.is_empty():
		puzzle = get_node_or_null(puzzle_path)
	interact_radius = maxf(interact_radius, 2.2)


func _on_interact(_player: Node3D) -> void:
	if puzzle != null and is_instance_valid(puzzle) and puzzle.has_method("input"):
		puzzle.call("input", switch_id)
