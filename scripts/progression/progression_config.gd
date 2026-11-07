class_name ProgressionConfig
extends Resource
## All progression tuning in one resource: the XP curve, point grants, XP rewards and balance caps.
## Level 1 values must keep today's gameplay numbers (every bonus starts at zero).

## xp_to_next[i] is the XP needed to go from level i+1 to level i+2. max_level = size + 1.
@export var xp_to_next: PackedInt32Array = PackedInt32Array([100, 150, 220, 300, 400, 520, 660, 820, 1000, 1200, 1450])
@export var attribute_points_per_level: int = 1
@export var skill_points_per_level: int = 1

## Base XP per enemy tier, before the anti-grind factors. Quests and discoveries pay more than kills.
@export var kill_xp: Dictionary = {&"grunt": 8, &"elite": 14, &"heavy": 20, &"boss": 150}
## Level at which a tier stops being a fair challenge. Kill XP drops by `overlevel_falloff` per level above it.
@export var recommended_level: Dictionary = {&"grunt": 1, &"elite": 3, &"heavy": 4, &"boss": 6}
@export var overlevel_falloff: float = 0.2
@export var min_kill_factor: float = 0.1
## Repeat kills of the same enemy name shrink by 1 / (1 + kills / farm_halving), never below farm_floor.
@export var farm_halving: float = 40.0
@export var farm_floor: float = 0.3

@export var quest_xp: Dictionary = {&"first_signal": 400, &"leave_outpost": 60}
@export var default_quest_xp: int = 200
@export var discovery_xp: int = 25

## Balance caps.
@export var damage_mult_cap: float = 1.6
@export var max_damage_reduction: float = 0.6
@export var min_recharge_mult: float = 0.5
@export var min_dodge_cost_mult: float = 0.5
@export var max_move_speed_bonus: float = 0.15

## Enemy scaling is data only (0 = off); nothing applies it unless a region sets it.
@export var enemy_health_per_level_over: float = 0.0
@export var enemy_damage_per_level_over: float = 0.0


func max_level() -> int:
	return xp_to_next.size() + 1


## Total XP at which `level` is reached (level 1 = 0).
func xp_for_level(level: int) -> int:
	var total := 0
	for i in clampi(level - 1, 0, xp_to_next.size()):
		total += xp_to_next[i]
	return total


func level_for_xp(xp: int) -> int:
	var level := 1
	while level < max_level() and xp >= xp_for_level(level + 1):
		level += 1
	return level


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for i in xp_to_next.size():
		if xp_to_next[i] <= 0:
			errors.append("xp_to_next[%d] must be > 0" % i)
		elif i > 0 and xp_to_next[i] < xp_to_next[i - 1]:
			errors.append("xp curve must not decrease at index %d" % i)
	if damage_mult_cap < 1.0 or max_damage_reduction >= 1.0:
		errors.append("balance caps out of range")
	return errors
