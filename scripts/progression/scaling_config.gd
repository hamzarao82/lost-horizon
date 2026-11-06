class_name ScalingConfig
extends Resource
## Enemy strength by player level. Level 1 is always exactly the authored numbers; the curve is small
## and capped so enemies stay a threat without making early gear obsolete. Bosses use their own curve.

@export var health_per_level: float = 0.04
@export var damage_per_level: float = 0.02
@export var max_health_mult: float = 1.8
@export var max_damage_mult: float = 1.4
@export var boss_health_per_level: float = 0.02
@export var boss_max_health_mult: float = 1.4
@export var boss_damage_per_level: float = 0.0


func health_mult(player_level: int, boss: bool) -> float:
	var steps := maxi(player_level - 1, 0)
	if boss:
		return minf(1.0 + boss_health_per_level * steps, boss_max_health_mult)
	return minf(1.0 + health_per_level * steps, max_health_mult)


func damage_mult(player_level: int, boss: bool) -> float:
	var steps := maxi(player_level - 1, 0)
	var rate := boss_damage_per_level if boss else damage_per_level
	return minf(1.0 + rate * steps, max_damage_mult)
