class_name Region
extends Node3D
## Base for a region scene. RegionManager instantiates one at a time, calls restore_state() before
## enter(), and calls capture_state() when the player leaves or the game is saved.
## Outpost 17 is the exception: it lives in Main and RegionManager detaches its nodes instead.

signal exit_requested(exit_id: StringName)

var region_id: StringName = &""


## The player has just been placed at `entry_id`. Start region-specific behaviour here.
func enter(_entry_id: StringName) -> void:
	pass


## Region-specific state worth saving. Must be JSON-safe (numbers, strings, bools, arrays, dictionaries).
func capture_state() -> Dictionary:
	return {}


func restore_state(_state: Dictionary) -> void:
	pass
