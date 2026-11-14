extends SceneTree
## One shared fairness table for every boss (Milestone 11): the Warden, Subject Zero, the Facility
## Commander, the Fortress Captain and the Director. Reads the REAL attack .tres files and script constants.
##   godot --headless --path . -s tests/boss_fairness_check.gd
##
## Rules: telegraph (startup) >= 36 frames = 0.6 s, punish window (recovery) >= 30 frames = 0.5 s, a rush
## or dash telegraph >= 48 frames = 0.8 s, one hit per use per target, no attack deals more than a quarter
## of the player's 100 health. Anything that breaks a rule must be listed in KNOWN_EXCEPTIONS with the
## reason; the test fails if an unlisted attack breaks a rule or a listed exception stops being one.

const ATTACKS: String = "res://resources/attacks/"
const MIN_TELEGRAPH: int = 36
const MIN_PUNISH: int = 30
const MIN_RUSH_TELEGRAPH: int = 48
const MAX_HIT: float = 25.0

## boss -> attack ids. "rush" attacks (charge, dash) need the longer telegraph.
const BOSSES: Dictionary = {
	"Warden": ["warden_slam", "warden_charge", "warden_leap", "warden_fire", "warden_flurry"],
	"Subject Zero": ["experimental_claw", "experimental_ring", "experimental_charge"],
	"Facility Commander": ["ranged_shot", "ranged_shove"],
	"Fortress Captain": ["fortress_captain_slam", "fortress_captain_charge", "fortress_captain_volley"],
	"The Director": ["director_sweep", "director_volley", "director_barrage", "director_dash", "director_ring", "director_counter"],
}
const RUSH_ATTACKS: Array[String] = ["warden_charge", "experimental_charge", "fortress_captain_charge", "director_dash"]
## attack id -> why it may break the telegraph/punish rule. Empty: every boss attack complies.
const KNOWN_EXCEPTIONS: Dictionary = {}
## Damage effects spawned by an already-telegraphed attack, never selected as attacks of their own, so the rule does
## not apply: the slam that spawns the warden_shockwave carries a 36-frame telegraph and 40-frame recovery, and the
## ring expands visibly over Warden.SHOCK_TIME. Damage and validity are still checked.
const SPAWNED_EFFECTS: Array[String] = ["warden_shockwave"]

var _failures: int = 0
var _checks: int = 0
var _hits: int = 0


func _initialize() -> void:
	HitStop.enabled = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures += 1


func _attack(id: String) -> AttackData:
	return load(ATTACKS + id + ".tres") as AttackData


func _run() -> void:
	_test_table()
	_test_phases()
	await _test_single_hit()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_table() -> void:
	print("Telegraph, punish window and damage per attack")
	var seen_exceptions: Array[String] = []
	var total := 0
	for boss: String in BOSSES:
		for id: String in BOSSES[boss]:
			var a := _attack(id)
			total += 1
			if a == null:
				_check(false, "%s: %s loads" % [boss, id])
				continue
			var need_tel := MIN_RUSH_TELEGRAPH if id in RUSH_ATTACKS else MIN_TELEGRAPH
			var tel_ok := a.startup_frames >= need_tel
			var pun_ok := a.recovery_frames >= MIN_PUNISH
			var line := "%s %s: telegraph %d f (%.2f s), punish %d f (%.2f s), %.0f dmg" % [boss, id, a.startup_frames, a.startup_frames / 60.0, a.recovery_frames, a.recovery_frames / 60.0, a.damage]
			if KNOWN_EXCEPTIONS.has(id):
				seen_exceptions.append(id)
				_check(not (tel_ok and pun_ok), "KNOWN EXCEPTION still breaks the rule (%s)" % line)
			else:
				_check(tel_ok, "%s >= %d f telegraph" % [line, need_tel])
				_check(pun_ok, "%s >= %d f punish" % [id, MIN_PUNISH])
			_check(a.damage > 0.0 and a.damage <= MAX_HIT, "%s: one hit deals %.0f (never above %.0f, so never a quarter of the player's health)" % [id, a.damage, MAX_HIT])
			_check(a.validate().is_empty(), "%s validates" % id)
	_check(seen_exceptions.size() == KNOWN_EXCEPTIONS.size(), "every listed exception is still in the table (%d of %d attacks are exceptions)" % [seen_exceptions.size(), total])
	for id in SPAWNED_EFFECTS:
		var fx := _attack(id)
		_check(fx != null and fx.damage > 0.0 and fx.damage <= MAX_HIT and fx.validate().is_empty(), "spawned effect %s is valid and deals <= %.0f" % [id, MAX_HIT])
		_check(_attack("warden_slam").startup_frames >= MIN_TELEGRAPH and Warden.SHOCK_TIME >= 0.5, "%s is telegraphed by the slam and expands over %.1f s" % [id, Warden.SHOCK_TIME])
	for id in ["warden_slam", "warden_charge", "warden_leap"]:
		_check(_attack(id).recovery_frames >= MIN_PUNISH, "%s punish window protects the flurry chain too" % id)


func _test_phases() -> void:
	print("Phases")
	_check(Warden.PHASE2_THRESHOLD > 0.0 and Warden.PHASE2_THRESHOLD < 1.0, "the Warden's phase 2 starts at %.0f%% health" % (Warden.PHASE2_THRESHOLD * 100.0))
	_check(Director.PHASE3_THRESHOLD > 0.0 and Director.PHASE3_THRESHOLD < Director.PHASE2_THRESHOLD and Director.PHASE2_THRESHOLD < 1.0,
			"the Director's phases are ordered: 100%% > %.0f%% > %.0f%% > 0" % [Director.PHASE2_THRESHOLD * 100.0, Director.PHASE3_THRESHOLD * 100.0])
	_check(Director.TRANSITION_TIME >= 1.0 and Director.GRACE_AFTER_TRANSITION >= 1.0,
			"a Director phase change is a %.1f s invulnerable beat plus %.1f s of grace" % [Director.TRANSITION_TIME, Director.GRACE_AFTER_TRANSITION])
	_check(Director.INTERRUPT_STAGGER >= 0.4 and EliteExperimentalSubject.INTERRUPT_STAGGER >= 0.4,
			"only heavy hits (stagger >= 0.4 s) interrupt the Director and Subject Zero")
	_check(Director.BAND_MIN >= 3.0 and Director.FINAL_BAND_MIN < Director.FINAL_BAND_MAX and Director.RING_RADIUS <= Director.BAND_MAX,
			"the Director keeps a fair distance band (%.1f-%.1f m, final stand %.1f-%.1f m)" % [Director.BAND_MIN, Director.BAND_MAX, Director.FINAL_BAND_MIN, Director.FINAL_BAND_MAX])
	for cfg_path in ["director", "fortress_captain", "facility_elite_subject", "rc_facility_commander_boss"]:
		var cfg: Resource = load("res://resources/enemies/%s.tres" % cfg_path)
		var hp: float = float(cfg.get("hit_points"))
		var resist: float = float(cfg.get("stagger_resist"))
		_check(hp >= 300.0 and hp <= 700.0 and resist <= 0.9, "%s has %.0f health and %.2f stagger resist (killable, not stun-lock immune)" % [cfg_path, hp, resist])
	var warden := load("res://scenes/enemies/Warden.tscn") as PackedScene
	var w := warden.instantiate() as Warden
	_check(w.hit_points >= 300.0 and w.hit_points <= 700.0, "the Warden has %.0f health" % w.hit_points)
	w.free()


## A real Hitbox on a real overlapping body: every melee boss attack's data lands exactly once per activation.
func _test_single_hit() -> void:
	print("One hit per use (real Hitbox)")
	var dummy := StaticBody3D.new()
	var script := GDScript.new()
	script.source_code = "extends StaticBody3D\nvar hits := 0\nfunc receive_hit(_a, _p, _s = 1.0) -> bool:\n\thits += 1\n\treturn true\n"
	script.reload()
	dummy.set_script(script)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE
	shape.shape = box
	dummy.add_child(shape)
	root.add_child(dummy)
	var source := Node3D.new()
	root.add_child(source)
	source.global_position = Vector3(0.0, 0.0, 5.0)
	var hitbox := Hitbox.new()
	var hit_shape := CollisionShape3D.new()
	var hit_box := BoxShape3D.new()
	hit_box.size = Vector3(3.0, 3.0, 3.0)
	hit_shape.shape = hit_box
	hitbox.add_child(hit_shape)
	root.add_child(hitbox)
	for i in 4:
		await physics_frame
	var all_once := true
	var tested := 0
	for boss: String in BOSSES:
		for id: String in BOSSES[boss]:
			var a := _attack(id)
			if a.active_frames <= 1:
				continue
			dummy.hits = 0
			hitbox.activate(a, source, 1.0)
			for i in a.active_frames + 3:
				await physics_frame
			hitbox.deactivate()
			tested += 1
			if dummy.hits != 1:
				all_once = false
				print("    %s landed %d times" % [id, dummy.hits])
	_check(tested >= 8, "%d melee boss attacks were swung through a real hitbox" % tested)
	_check(all_once, "each of them hit the target exactly once for its whole active window")
	hitbox.queue_free()
	dummy.queue_free()
	source.queue_free()
	await physics_frame
