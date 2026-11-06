class_name EnemyScaling
extends RefCounted
## One place that scales a freshly spawned enemy to the player's level (called from Enemy._ready, so
## waves, patrols and summons are all covered). Applied once per instance; a reload spawns new
## instances, which scale against the level at that moment, never on top of an earlier scaling.

const CONFIG_PATH: String = "res://resources/progression/enemy_scaling.tres"
const META: StringName = &"_level_scaled"

static var _config: ScalingConfig


static func config() -> ScalingConfig:
	if _config == null:
		_config = load(CONFIG_PATH) as ScalingConfig
		if _config == null:
			_config = ScalingConfig.new()
	return _config


## Returns true when the enemy was changed. `cfg` is injectable for tests.
static func apply(enemy: Enemy, player_level: int, cfg: ScalingConfig = null) -> bool:
	if enemy == null or enemy.has_meta(META):
		return false
	enemy.set_meta(META, true)
	if player_level <= 1:
		return false
	var c := cfg if cfg != null else config()
	var boss := enemy is Warden
	var hp := c.health_mult(player_level, boss)
	var dmg := c.damage_mult(player_level, boss)
	enemy.hit_points *= hp
	enemy.damage_mult *= dmg
	return hp != 1.0 or dmg != 1.0
