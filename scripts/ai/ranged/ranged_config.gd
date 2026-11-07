class_name RangedConfig
extends Resource
## Data for an enemy that fights at range. Every timing a player has to react to lives here (or in the
## shot's AttackData) so tests can assert fairness from data instead of from behaviour.

## The shot's AttackData: startup_frames is the telegraph, recovery_frames the punish window after the
## last shot, damage is per projectile.
@export var shot_path: String = "res://resources/attacks/ranged_shot.tres"
@export var burst_shots: int = 3
## Seconds between shots in one burst.
@export var shot_spacing: float = 0.3
## The enemy tries to stay between these distances from the player.
@export var band_min: float = 7.0
@export var band_max: float = 12.0
@export var retreat_speed_factor: float = 1.0
@export var strafe_speed_factor: float = 0.6
## Cooldown between ranged attacks, in seconds.
@export var cooldown_min: float = 1.6
@export var cooldown_max: float = 2.4
## Random yaw error added to every aim (degrees) and the fraction of the perfect lead that is applied.
@export var aim_error_deg: float = 4.0
@export_range(0.0, 1.0) var lead_factor: float = 0.4
@export var projectile_speed: float = 18.0
## Inside this distance the enemy uses its melee swing (a shove) instead of shooting.
@export var shove_range: float = 2.0
@export var use_cover: bool = true

var _shot: AttackData


func shot() -> AttackData:
	if _shot == null:
		_shot = load(shot_path) as AttackData
	return _shot


## Warning time before the first shot, in seconds.
func telegraph_seconds() -> float:
	return shot().startup_frames / 60.0


## Time after the last shot before the enemy can act again, in seconds.
func recovery_seconds() -> float:
	return shot().recovery_frames / 60.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if shot() == null:
		errors.append("shot_path does not load")
		return errors
	errors.append_array(shot().validate())
	if telegraph_seconds() < 0.6:
		errors.append("telegraph %.2f s is shorter than 0.6 s" % telegraph_seconds())
	if recovery_seconds() < 0.5:
		errors.append("recovery %.2f s is shorter than 0.5 s" % recovery_seconds())
	if shot_spacing < 0.25:
		errors.append("shot spacing %.2f s is shorter than 0.25 s" % shot_spacing)
	if burst_shots < 1 or burst_shots > 6:
		errors.append("burst_shots must be 1 to 6")
	if band_min >= band_max:
		errors.append("band_min must be below band_max")
	return errors
