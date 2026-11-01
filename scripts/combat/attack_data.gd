class_name AttackData
extends Resource
## Reusable attack definition. Timings are frames at 60 Hz.

@export var id: StringName
@export var damage: float = 10.0
@export var stamina_cost: float = 5.0
@export var startup_frames: int = 6
@export var active_frames: int = 4
@export var recovery_frames: int = 10
@export var knockback: float = 4.0
@export var stagger_time: float = 0.25
@export var lunge_speed: float = 3.0
@export var hit_stop: float = 0.05
@export var shake: float = 0.25
@export var swing_arc: float = 100.0
@export var swing_flip: bool = false


func total_frames() -> int:
	return startup_frames + active_frames + recovery_frames


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("id is empty")
	if damage <= 0.0:
		errors.append("%s: damage must be > 0" % id)
	if startup_frames < 1 or active_frames < 1 or recovery_frames < 1:
		errors.append("%s: every phase needs at least 1 frame" % id)
	if stamina_cost < 0.0 or knockback < 0.0 or stagger_time < 0.0:
		errors.append("%s: negative stamina, knockback or stagger" % id)
	return errors
