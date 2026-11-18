class_name BalanceTable
extends RefCounted
## Milestone 11 balance table: per region, the enemies of its wave encounter and its bosses, read from the
## REAL resources (scenes, EnemyConfig, FacilityEnemyConfig, attack data, the level scaling config), plus a
## headless time-to-kill for every weapon. Everything here is formula output, never a human playtest.
##
## Assumptions (all visible, all tested): the player has no attribute or skill investment (damage part 1.0),
## every weapon is at upgrade level 0, the player lands every swing of the five-hit light chain with its full
## recovery (no animation cancelling), and the expected player level per region is EXPECTED_LEVEL.

const ARENA_DIR: String = "res://resources/arena/"
const ATTACK_DIR: String = "res://resources/attacks/"
const PLAYER_HEALTH: float = 100.0
const LIGHT_CHAIN: Array[String] = ["light_1", "light_2", "light_3", "light_4", "light_5"]

## id, display name, expected player level, wave table file, boss resources.
const REGIONS: Array[Dictionary] = [
	{"id": &"outpost_17", "name": "Outpost 17", "level": 1, "waves": "waves.tres",
			"bosses": ["res://scenes/enemies/Warden.tscn"]},
	{"id": &"dead_coast", "name": "Dead Coast", "level": 3, "waves": "stage_dead_coast.tres",
			"bosses": ["res://resources/enemies/dc_harbor_commander.tres", "res://resources/enemies/dc_cove_boss.tres"]},
	{"id": &"blackwood", "name": "Blackwood", "level": 5, "waves": "stage_blackwood.tres",
			"bosses": ["res://resources/enemies/bw_patrol_chief.tres", "res://resources/enemies/bw_site_overseer.tres"]},
	{"id": &"research_complex", "name": "Research Complex", "level": 7, "waves": "stage_research_complex.tres",
			"bosses": ["res://resources/enemies/facility_elite_subject.tres", "res://resources/enemies/rc_facility_commander_boss.tres"]},
	{"id": &"iron_fortress", "name": "Iron Fortress", "level": 9, "waves": "stage_iron_fortress.tres",
			"bosses": ["res://resources/enemies/fortress_captain.tres", "res://resources/enemies/director.tres"]},
]
const WEAPON_IDS: Array[String] = [
	"wooden_stick", "improvised_blade", "combat_knife", "iron_sword", "military_machete",
	"katana", "tactical_sword", "claymore", "warden_blade",
]


## Bosses fight with their own attack sets (scripts), not the config's single swing: their damage per
## second is the mean over these attacks, each as damage / (its frames + the boss's cooldown).
const STAGE_BOSS_ATTACKS: Array[String] = ["experimental_claw", "experimental_ring", "experimental_charge"]
const BOSS_ATTACKS: Dictionary = {
	"res://scenes/enemies/Warden.tscn": ["warden_slam", "warden_charge", "warden_leap", "warden_fire"],
	"res://resources/enemies/facility_elite_subject.tres": STAGE_BOSS_ATTACKS,
	"res://resources/enemies/dc_harbor_commander.tres": STAGE_BOSS_ATTACKS,
	"res://resources/enemies/dc_cove_boss.tres": STAGE_BOSS_ATTACKS,
	"res://resources/enemies/bw_patrol_chief.tres": STAGE_BOSS_ATTACKS,
	"res://resources/enemies/bw_site_overseer.tres": STAGE_BOSS_ATTACKS,
	"res://resources/enemies/fortress_captain.tres": ["fortress_captain_slam", "fortress_captain_charge", "fortress_captain_volley"],
	"res://resources/enemies/director.tres": ["director_sweep", "director_volley", "director_barrage", "director_dash", "director_ring", "director_counter"],
}


static func region_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for r in REGIONS:
		out.append(r["id"])
	return out


static func region(id: StringName) -> Dictionary:
	for r in REGIONS:
		if r["id"] == id:
			return r
	return {}


static func _attack(path: String) -> AttackData:
	return load(path) as AttackData


## Stats of one enemy entry (a .tscn or a config .tres) as it would spawn at `player_level`.
static func enemy_stats(path: String, player_level: int) -> Dictionary:
	var res: Resource = load(path)
	var armor := 0.0
	var ranged: RangedConfig = null
	var enemy: Enemy = null
	if res is PackedScene:
		enemy = (res as PackedScene).instantiate() as Enemy
	elif res is EnemyConfig:
		var cfg := res as EnemyConfig
		enemy = (load(cfg.scene_path) as PackedScene).instantiate() as Enemy
		cfg.apply(enemy)
		armor = cfg.armor
		ranged = cfg.ranged
	elif res is FacilityEnemyConfig:
		var fcfg := res as FacilityEnemyConfig
		enemy = (load(fcfg.base_scene_path) as PackedScene).instantiate() as Enemy
		fcfg.apply(enemy)
	if enemy == null:
		return {}
	var warden_scaling := enemy is Warden
	var scaling := EnemyScaling.config()
	var hp_mult := scaling.health_mult(player_level, warden_scaling)
	var dmg_mult := scaling.damage_mult(player_level, warden_scaling)
	var swing := _attack(enemy.swing_path)
	var melee_hit := swing.damage * dmg_mult
	var melee_cycle := swing.total_frames() / 60.0 + (enemy.cooldown_min + enemy.cooldown_max) * 0.5
	var dps := melee_hit / melee_cycle
	var hit := melee_hit
	if ranged != null:
		var shot := _attack(ranged.shot_path)
		var burst := shot.damage * dmg_mult * ranged.burst_shots
		var burst_cycle := shot.startup_frames / 60.0 + shot.recovery_frames / 60.0 \
				+ ranged.shot_spacing * maxf(ranged.burst_shots - 1, 0) + (ranged.cooldown_min + ranged.cooldown_max) * 0.5
		dps = maxf(dps, burst / burst_cycle)
		hit = maxf(hit, shot.damage * dmg_mult)
	if BOSS_ATTACKS.has(path):
		var total_dps := 0.0
		var best_hit := 0.0
		var ids: Array = BOSS_ATTACKS[path]
		for aid: String in ids:
			var a := _attack(ATTACK_DIR + aid + ".tres")
			var cycle := a.total_frames() / 60.0 + (enemy.cooldown_min + enemy.cooldown_max) * 0.5
			total_dps += a.damage * dmg_mult / cycle
			best_hit = maxf(best_hit, a.damage * dmg_mult)
		dps = total_dps / ids.size()
		hit = best_hit
	var stats := {
		"name": enemy.display_name if enemy.display_name != "" else path.get_file().get_basename(),
		"path": path,
		"hp": enemy.hit_points * hp_mult,
		"armor": armor,
		"ehp": enemy.hit_points * hp_mult + armor,
		"hit": hit,
		"dps": dps,
		"detection": enemy.detection_range,
		"stagger_resist": enemy.stagger_resist,
		"is_warden": warden_scaling,
	}
	enemy.free()
	return stats


static func _entries(wave_set: ArenaWaveSet) -> Array[String]:
	var out: Array[String] = []
	for i in wave_set.wave_count():
		for entry in wave_set.enemies_of(i):
			out.append(String(entry))
	return out


## Everything the balance report needs about one region.
static func region_report(id: StringName) -> Dictionary:
	var r := region(id)
	var level: int = r["level"]
	var wave_set := load(ARENA_DIR + String(r["waves"])) as ArenaWaveSet
	var boss_paths: Array[String] = []
	for b in r["bosses"]:
		boss_paths.append(String(b))
	var regulars: Array[Dictionary] = []
	for entry in _entries(wave_set):
		if entry in boss_paths:
			continue
		regulars.append(enemy_stats(entry, level))
	var bosses: Array[Dictionary] = []
	for path in boss_paths:
		bosses.append(enemy_stats(path, level))
	var wave_ehp := 0.0
	var wave_dps := 0.0
	for e in regulars:
		wave_ehp += float(e["ehp"])
		wave_dps += float(e["dps"])
	var boss_ehp := 0.0
	var boss_dps := 0.0
	for b in bosses:
		boss_ehp += float(b["ehp"])
		boss_dps += float(b["dps"])
	return {
		"id": id, "name": r["name"], "level": level, "waves": wave_set.wave_count(),
		"regulars": regulars, "bosses": bosses,
		"wave_ehp": wave_ehp, "wave_dps": wave_dps, "boss_ehp": boss_ehp, "boss_dps": boss_dps,
		"threat": (wave_ehp + boss_ehp) * (wave_dps + boss_dps) / 1000.0,
	}


# --- player side -------------------------------------------------------------------------------

## Seconds one full light chain takes with `weapon`, and the damage it deals to a neutral target.
static func light_chain(weapon: ItemData) -> Dictionary:
	var inventory := Inventory.new()
	inventory.weapon = weapon
	var speed := maxf(inventory.attack_speed(), 0.25)
	var mult := inventory.damage_multiplier()
	var seconds := 0.0
	var damage := 0.0
	for id in LIGHT_CHAIN:
		var swing := WeaponProfiles.scaled(_attack(ATTACK_DIR + id + ".tres"), weapon)
		seconds += swing.total_frames() / 60.0 / speed
		damage += swing.damage * mult
	inventory.free()
	return {"seconds": seconds, "damage": damage, "dps": damage / seconds}


## Seconds to remove `ehp` with the light chain of `weapon` (continuous chaining, every swing lands).
static func time_to_kill(weapon: ItemData, ehp: float) -> float:
	var chain := light_chain(weapon)
	return ehp / float(chain["dps"])


## Hits the player survives from one `hit`-damage blow with no armor.
static func hits_to_die(hit: float) -> int:
	return ceili(PLAYER_HEALTH / maxf(hit, 0.01))
