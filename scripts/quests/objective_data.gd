class_name ObjectiveData
extends Resource
## One step of a quest. Progress comes from gameplay events, never from scene scripts.

enum Type { INTERACT, ENTER_AREA, KILL_COUNT, WAVE_CLEARED, ITEM_COLLECTED, FLAG, BOSS_DEFEATED }

@export var id: StringName
@export var text: String
@export var type: Type = Type.INTERACT
## INTERACT / ENTER_AREA / ITEM_COLLECTED / BOSS_DEFEATED / FLAG: ids that count (each counts once).
## KILL_COUNT: enemy display names that count (empty = any enemy).
@export var targets: PackedStringArray
## Needed amount. 0 means "all targets" for the set types and 1 for KILL_COUNT.
## WAVE_CLEARED: the wave number that has to be cleared (5 = the whole arena).
@export var count: int = 0
## Shown as "<label> n/m" in the tracker when more than one step is needed (e.g. "Switches").
@export var progress_label: String


## How much progress completes this objective.
func required() -> int:
	match type:
		Type.KILL_COUNT:
			return maxi(count, 1)
		Type.WAVE_CLEARED:
			return maxi(count, 1)
		_:
			var wanted := count if count > 0 else targets.size()
			return clampi(wanted, 1, maxi(targets.size(), 1))


func is_set_type() -> bool:
	return type != Type.KILL_COUNT and type != Type.WAVE_CLEARED


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("objective has no id")
	if text.strip_edges().is_empty():
		errors.append("%s: no text" % id)
	if is_set_type() and targets.is_empty():
		errors.append("%s: this type needs at least one target" % id)
	if type == Type.WAVE_CLEARED and count < 1:
		errors.append("%s: WAVE_CLEARED needs count >= 1" % id)
	if type == Type.KILL_COUNT and count < 1:
		errors.append("%s: KILL_COUNT needs count >= 1" % id)
	if is_set_type() and count > targets.size():
		errors.append("%s: count %d is larger than the %d targets" % [id, count, targets.size()])
	return errors
