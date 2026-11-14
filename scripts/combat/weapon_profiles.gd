class_name WeaponProfiles
extends RefCounted
## Weapon identity as data: turns a base AttackData plus the equipped weapon's stagger_power,
## recovery_scale and heavy_multiplier into the attack that is actually used. A neutral weapon
## (all 1.0, which includes the starting blade and no weapon at all) returns the very same object.

const NEUTRAL_EPSILON: float = 0.0001

static var _cache: Dictionary = {}


static func is_neutral(weapon: ItemData) -> bool:
	return weapon == null \
			or (absf(weapon.stagger_power - 1.0) < NEUTRAL_EPSILON \
			and absf(weapon.recovery_scale - 1.0) < NEUTRAL_EPSILON \
			and absf(weapon.heavy_multiplier - 1.0) < NEUTRAL_EPSILON)


static func scaled(base: AttackData, weapon: ItemData) -> AttackData:
	if base == null or is_neutral(weapon):
		return base
	var per_weapon: Dictionary = _cache.get(weapon, {})
	if per_weapon.has(base):
		return per_weapon[base] as AttackData
	var copy := base.duplicate() as AttackData
	copy.recovery_frames = maxi(1, roundi(base.recovery_frames * weapon.recovery_scale))
	copy.stagger_time = base.stagger_time * weapon.stagger_power
	copy.knockback = base.knockback * weapon.stagger_power
	if StatsResolver.kind_of(base.id) == &"heavy":
		copy.damage = base.damage * weapon.heavy_multiplier
	per_weapon[base] = copy
	_cache[weapon] = per_weapon
	return copy


static func clear_cache() -> void:
	_cache.clear()
