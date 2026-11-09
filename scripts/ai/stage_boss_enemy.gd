class_name StageBossEnemy
extends EliteExperimentalSubject
## A boss for the Dead Coast and the Blackwood: the Research Complex mini-boss's three telegraphed melee
## attacks (leaping claw, shockwave ring, charging rush: one hit per use, a punish window after each,
## numbers in resources/attacks/experimental_*.tres and asserted by tests) with the mix chosen per boss.
## The mix is data: weight 0 switches an attack off, so a commander that leaps and charges and a boss that
## holds the ground with rings are the same class with different configs.
##
## It does not drop the Research Complex's own reward; the unique reward and the defeat flag belong to
## StageBoss (scripts/regions/stage_boss.gd), which also puts a never-picked-up reward back after a reload.

## Relative chance of each attack when it is possible at the current distance. 0 = never used.
@export var claw_weight: float = 3.0
@export var ring_weight: float = 2.0
@export var charge_weight: float = 1.0


func _pick_attack(dist: float) -> StringName:
	if forced_attack != &"":
		return forced_attack
	var options: Array[StringName] = []
	var weights: Array[float] = []
	if claw_weight > 0.0 and dist >= CLAW_MIN_DIST and dist <= CLAW_MAX_DIST:
		options.append(&"claw")
		weights.append(claw_weight)
	if ring_weight > 0.0 and dist <= RING_TRIGGER:
		options.append(&"ring")
		weights.append(ring_weight)
	if charge_weight > 0.0 and dist >= CHARGE_MIN_DIST:
		options.append(&"charge")
		weights.append(charge_weight)
	if options.is_empty():
		# Out of every attack's band (or the mix excludes what fits): the nearest enabled one is next.
		if ring_weight > 0.0:
			options.append(&"ring")
		elif claw_weight > 0.0:
			options.append(&"claw")
		else:
			options.append(&"charge")
		weights.append(1.0)
	if _repeat_count >= 2 and options.size() > 1 and options.has(_last_kind):
		var idx := options.find(_last_kind)
		options.remove_at(idx)
		weights.remove_at(idx)
	var total := 0.0
	for w in weights:
		total += w
	var roll := randf() * total
	for i in options.size():
		roll -= weights[i]
		if roll <= 0.0:
			return options[i]
	return options[0]


## The normal loot table only. The Research Complex's containment sigil is not this boss's reward.
func _drop_loot() -> void:
	if loot_table_path == "":
		return
	var table := load(loot_table_path) as LootTable
	var item := table.roll() if table != null else null
	if item != null:
		Pickup.spawn.call_deferred(get_parent(), item, Vector3(global_position.x, 0.0, global_position.z))
