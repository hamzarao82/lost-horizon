extends SceneTree
## Combat feedback UI (Milestone 11): boss telegraph strip, elite health bars, damage direction, low-health
## warning, armor-break and heavy-windup sounds. godot --headless --path . -s tests/combat_ui_check.gd
## States are set and read synchronously (no frames in between) so the enemies' own AI cannot move them.

var _checks: int = 0
var _failures: int = 0
var _main: Node


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _swing(startup: int) -> AttackData:
	var data := AttackData.new()
	data.startup_frames = startup
	return data


func _run() -> void:
	_test_layout()
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	await _frames(4)
	_test_telegraph_progress()
	_test_telegraph_widget()
	_test_damage_direction()
	_test_elite_bar()
	_test_audio()
	await _test_hud_wiring()
	print("combat_ui_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_layout() -> void:
	print("Layout: the telegraph strip has its own slot")
	for viewport in [Vector2(1280, 720), Vector2(1920, 1080), Vector2(960, 540)]:
		var plan: Dictionary = Hud.plan_layout(viewport, false)
		var strip: Rect2 = plan["telegraph"]
		var boss_bar: Rect2 = plan["boss_bar"]
		var banner: Rect2 = plan["banner"]
		_check(strip.size.x == boss_bar.size.x and strip.position.y >= boss_bar.end.y and strip.end.y <= banner.position.y,
				"%dx%d: strip sits between the boss bar and the banner" % [viewport.x, viewport.y])
		_check(Hud.plan_layout(viewport, true).has("telegraph"), "%dx%d: also planned with touch controls" % [viewport.x, viewport.y])


func _spawn(scene: String) -> Enemy:
	var enemy := (load(scene) as PackedScene).instantiate() as Enemy
	_main.add_child(enemy)
	enemy.global_position = Vector3(300.0, 5.0, 300.0)
	return enemy


func _test_telegraph_progress() -> void:
	print("Telegraph: progress from real boss state")
	_check(TelegraphIndicator.telegraph_progress(null) == -1.0, "null boss: no telegraph")
	var soldier := _spawn("res://scenes/enemies/PatrolSoldier.tscn")
	soldier.state = Enemy.State.IDLE
	_check(TelegraphIndicator.telegraph_progress(soldier) == -1.0, "idle: no telegraph")
	soldier.state = Enemy.State.ATTACK
	soldier.set("_swing", _swing(20))
	soldier.set("_attack_frames", 10.0)
	_check(is_equal_approx(TelegraphIndicator.telegraph_progress(soldier), 0.5), "melee windup halfway reads 0.5")
	soldier.set("_attack_frames", 20.0)
	_check(TelegraphIndicator.telegraph_progress(soldier) == -1.0, "once the strike starts the warning is over")
	soldier.state = Enemy.State.DEAD
	soldier.set("_attack_frames", 5.0)
	_check(TelegraphIndicator.telegraph_progress(soldier) == -1.0, "a dead enemy never telegraphs")

	var warden := _spawn("res://scenes/enemies/Warden.tscn")
	warden.state = Enemy.State.ATTACK
	warden.set("_special", &"")
	warden.set("_swing", _swing(40))
	warden.set("_attack_frames", 10.0)
	warden.set("_sp_phase", 0)
	_check(is_equal_approx(TelegraphIndicator.telegraph_progress(warden), 0.25),
			"Warden slam uses the base counter, not the special phase")
	warden.set("_special", &"charge")
	_check(TelegraphIndicator.telegraph_progress(warden) == 1.0, "Warden charge telegraph reports winding up")
	warden.set("_sp_phase", 1)
	_check(TelegraphIndicator.telegraph_progress(warden) == -1.0, "Warden mid-charge is no longer a warning")

	var director := _spawn("res://scenes/enemies/Director.tscn")
	director.state = Enemy.State.ATTACK
	director.set("_kind", &"volley")
	director.set("_swing", _swing(60))
	director.set("_sp_phase", 0)
	director.set("_sp_frames", 30.0)
	_check(is_equal_approx(TelegraphIndicator.telegraph_progress(director), 0.5), "Director telegraph progress is exact")
	director.set("_sp_phase", 1)
	_check(TelegraphIndicator.telegraph_progress(director) == -1.0, "Director strike phase: no warning")
	director.set("_kind", &"counter")
	director.set("_sp_phase", 0)
	director.set("_attack_frames", 15.0)
	_check(is_equal_approx(TelegraphIndicator.telegraph_progress(director), 0.25), "Director counter is a plain melee swing")

	var commander := _spawn("res://scenes/enemies/PatrolSoldier.tscn")
	var cfg := load("res://resources/enemies/facility_commander.tres") as EnemyConfig
	var ranged := cfg.spawn(_main, Vector3(310.0, 5.0, 300.0))
	var brain: Variant = ranged.get("_ranged_brain")
	_check(brain != null, "the Facility Commander has a ranged brain")
	if brain != null:
		ranged.state = Enemy.State.RANGED_ATTACK
		brain.phase = RangedBrain.Phase.TELEGRAPH
		_check(TelegraphIndicator.telegraph_progress(ranged) == 1.0, "ranged telegraph shows the warning")
		brain.phase = RangedBrain.Phase.NONE
		_check(TelegraphIndicator.telegraph_progress(ranged) == -1.0, "ranged: no warning outside the telegraph")
	for e in [soldier, warden, director, commander, ranged]:
		if is_instance_valid(e):
			e.queue_free()


func _test_telegraph_widget() -> void:
	print("Telegraph: the strip widget")
	var strip := TelegraphIndicator.new()
	root.add_child(strip)
	var rect := Rect2(400, 87, 440, 10)
	strip.update_for(null, rect)
	_check(not strip.visible, "no boss: hidden")
	var soldier := _spawn("res://scenes/enemies/PatrolSoldier.tscn")
	soldier.state = Enemy.State.ATTACK
	soldier.set("_swing", _swing(30))
	soldier.set("_attack_frames", 15.0)
	strip.update_for(soldier, rect, 0.016)
	_check(strip.visible and is_equal_approx(strip.progress_value, 0.5), "telegraphing boss: strip visible at 0.5")
	_check(strip.position == rect.position and strip.size == rect.size, "strip follows the layout rectangle")
	soldier.set("_attack_frames", 40.0)
	strip.update_for(soldier, rect, 0.016)
	_check(not strip.visible, "strike started: strip hidden again")
	soldier.queue_free()
	strip.queue_free()


func _test_damage_direction() -> void:
	print("Damage direction and low health")
	var basis := Basis.IDENTITY  # a camera looking down -z
	var here := Vector3.ZERO
	_check(absf(DamageDirection.screen_angle(basis, here, Vector3(0, 0, -5))) < 0.01, "attacker ahead: angle 0 (top)")
	_check(absf(DamageDirection.screen_angle(basis, here, Vector3(5, 0, 0)) - PI * 0.5) < 0.01, "attacker to the right: 90 deg")
	_check(absf(DamageDirection.screen_angle(basis, here, Vector3(-5, 0, 0)) + PI * 0.5) < 0.01, "attacker to the left: -90 deg")
	_check(absf(absf(DamageDirection.screen_angle(basis, here, Vector3(0, 0, 5))) - PI) < 0.01, "attacker behind: 180 deg")
	var tilted := Basis(Vector3.RIGHT, deg_to_rad(-40.0))  # third-person camera pitched down must not bend it
	_check(absf(DamageDirection.screen_angle(tilted, here, Vector3(0, 0, -5))) < 0.01, "camera tilt does not bend the angle")
	var turned := Basis(Vector3.UP, PI * 0.5)  # camera turned to look along -x
	_check(absf(DamageDirection.screen_angle(turned, here, Vector3(-5, 0, 0))) < 0.01, "follows the camera heading")
	_check(absf(absf(DamageDirection.screen_angle(basis, here, here)) - PI) < 0.01, "attacker on top of the player: shown behind")

	var overlay := DamageDirection.new()
	root.add_child(overlay)
	overlay.add_wedge(0.0)
	_check(overlay.wedge_count() == 1, "a hit adds a wedge")
	overlay.advance(DamageDirection.WEDGE_SECONDS + 0.1)
	_check(overlay.wedge_count() == 0, "the wedge fades away")
	for i in 9:
		overlay.add_wedge(float(i))
	_check(overlay.wedge_count() == DamageDirection.MAX_WEDGES, "wedges are capped at %d" % DamageDirection.MAX_WEDGES)
	_check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the overlay never blocks input")

	_check(not DamageDirection.is_low_health(100.0, 100.0), "full health: no warning")
	_check(not DamageDirection.is_low_health(30.0, 100.0), "30%: no warning")
	_check(DamageDirection.is_low_health(25.0, 100.0), "25% warns")
	_check(DamageDirection.is_low_health(1.0, 100.0), "1 HP warns")
	_check(not DamageDirection.is_low_health(0.0, 100.0), "dead: no warning (the death screen takes over)")
	overlay.set_health(20.0, 100.0)
	_check(overlay.low_health_active(), "low health turns the frame on")
	overlay.set_health(80.0, 100.0)
	_check(not overlay.low_health_active(), "healing turns it off")

	overlay.on_armor_changed(50.0, 50.0)
	overlay.on_armor_changed(20.0, 50.0)
	_check(overlay.armor_breaks == 0, "armor wearing down is not a break")
	overlay.on_armor_changed(0.0, 50.0)
	_check(overlay.armor_breaks == 1, "armor reaching zero is one break")
	overlay.on_armor_changed(0.0, 50.0)
	_check(overlay.armor_breaks == 1, "staying at zero is not another break")
	overlay.on_armor_changed(50.0, 50.0)
	overlay.on_armor_changed(0.0, 50.0)
	_check(overlay.armor_breaks == 2, "repaired armor can break again")
	overlay.queue_free()


func _test_elite_bar() -> void:
	print("Elite health bars")
	var soldier := _spawn("res://scenes/enemies/PatrolSoldier.tscn")
	var warden := _spawn("res://scenes/enemies/Warden.tscn")
	var heavy := _spawn("res://scenes/enemies/HeavySoldier.tscn")
	_check(not EliteBar.is_elite(soldier), "a patrol soldier (%d HP) gets no bar" % int(soldier.hit_points))
	_check(EliteBar.is_elite(warden), "the Warden is elite")
	_check(EliteBar.attach(soldier) == null and soldier.get_node_or_null("EliteBar") == null, "attach ignores non-elites")
	var bar := EliteBar.attach(warden)
	_check(bar != null and warden.get_node_or_null("EliteBar") == bar, "attach adds one bar to an elite")
	_check(EliteBar.attach(warden) == bar and warden.find_children("EliteBar", "", false, false).size() == 1,
			"attaching twice never duplicates")
	_check(not EliteBar.should_show(1.0, 30.0, false), "full health and far: hidden")
	_check(EliteBar.should_show(1.0, 5.0, false), "full health and near: shown")
	_check(EliteBar.should_show(0.5, 30.0, false), "damaged and in range: shown")
	_check(not EliteBar.should_show(0.5, 60.0, false), "beyond the far limit: hidden even when damaged")
	_check(not EliteBar.should_show(0.5, 5.0, true), "dead: hidden")
	_check(EliteBar.is_elite(heavy) == (heavy.hit_points >= EliteBar.ELITE_MIN_HEALTH), "heavy soldier follows the health rule")
	for e in [soldier, warden, heavy]:
		e.queue_free()


func _test_audio() -> void:
	print("Sounds")
	var audio := root.get_node("AudioManager")
	for sfx in [&"enemy_windup_heavy", &"armor_break"]:
		_check((audio.get("SFX_NAMES") as Array).has(sfx), "%s is a registered sound" % sfx)
		_check(ResourceLoader.exists("res://assets/audio/%s.wav" % sfx), "%s.wav exists" % sfx)
		var stream: Variant = audio.get("_streams").get(sfx)
		_check(stream != null and (stream as AudioStream).get_length() > 0.1, "%s is loaded and not empty" % sfx)
	var soldier := _spawn("res://scenes/enemies/PatrolSoldier.tscn")
	var warden := _spawn("res://scenes/enemies/Warden.tscn")
	var heavy_cfg := load("res://resources/enemies/heavy_assault_unit.tres") as EnemyConfig
	var heavy := heavy_cfg.spawn(_main, Vector3(320.0, 5.0, 300.0))
	_check(audio.windup_sound_for(soldier) == &"enemy_swing_windup", "light enemy keeps the original windup")
	_check(audio.windup_sound_for(heavy) == &"enemy_windup_heavy", "heavy assault unit has the heavy windup")
	_check(audio.windup_sound_for(warden) == &"enemy_swing_windup", "bosses keep the light windup (own boss sounds)")
	_check(audio.windup_sound_for(null) == &"enemy_swing_windup", "no enemy: the original windup")
	audio.call("_on_enemy_swing")  # the old no-argument call still works
	_check(true, "_on_enemy_swing() without an argument does not crash")
	_check(soldier.is_connected(&"swing_started", audio.get("_on_enemy_swing").bind(soldier)),
			"a spawned enemy's swing is wired to the audio manager with itself bound")
	for e in [soldier, warden, heavy]:
		e.queue_free()


func _test_hud_wiring() -> void:
	print("HUD wiring")
	var huds: Array[Node] = _main.find_children("*", "Hud", true, false)
	_check(huds.size() == 1, "Main has one HUD")
	if huds.size() != 1:
		return
	var hud: Hud = huds[0]
	var overlay := hud.get("_damage_dir") as DamageDirection
	var strip := hud.get("_telegraph") as TelegraphIndicator
	_check(overlay != null and strip != null, "the HUD owns the overlay and the strip")
	var player := _main.get_node("Player") as Player
	_check(overlay.get_index() == 0, "the overlay is drawn behind every widget")
	var before := overlay.wedge_count()
	player.hit_from.emit(player.global_position + Vector3(0, 0, -4))
	_check(overlay.wedge_count() == before + 1, "a hit on the player adds a wedge through the HUD")
	var hp := player.health.max_health
	player.health.health = hp * 0.2
	player.health.changed.emit(player.health.health, hp)
	_check(overlay.low_health_active(), "dropping to 20% turns the low-health frame on")
	player.health.health = hp
	player.health.changed.emit(hp, hp)
	_check(not overlay.low_health_active(), "full health turns it off")
	var attack := AttackData.new()
	attack.damage = 1.0
	var emitted := [0]
	player.hit_from.connect(func(_p: Vector3) -> void: emitted[0] += 1)
	player.receive_hit(attack, player.global_position + Vector3(3, 0, 0))
	_check(emitted[0] == 1, "Player.receive_hit emits hit_from exactly once")
	await _frames(2)
	_check(strip.get_parent() != null and not strip.visible, "no boss present: the strip stays hidden")
