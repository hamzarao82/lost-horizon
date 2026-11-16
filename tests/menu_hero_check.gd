extends SceneTree
## The real player model in the title menu: it must cost nothing on a headless run, never crash the menu, keep
## every existing button, and the storm's flash must be readable by the hero's light when it is built.
## godot --headless --path . -s tests/menu_hero_check.gd

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _model_has_strike_clip() -> bool:
	var scene := load(MenuHero.MODEL_PATH) as PackedScene
	if scene == null:
		return false
	var instance := scene.instantiate()
	var found := false
	for node in instance.find_children("*", "AnimationPlayer", true, false):
		for clip in MenuHero.STRIKE_CLIPS:
			if (node as AnimationPlayer).has_animation(clip):
				found = true
	instance.free()
	return found


func _run() -> void:
	_check(not MenuHero.wanted(), "headless: the hero is not wanted (no 3D viewport on CI or tests)")
	_check(ResourceLoader.exists(MenuHero.MODEL_PATH), "the real player model file exists: %s" % MenuHero.MODEL_PATH)

	var storm := MenuStorm.new(3)
	root.add_child(storm)
	var hero := MenuHero.new(storm)
	root.add_child(hero)
	for i in 3:
		await process_frame
	_check(not hero.active and hero.get_child_count() == 0, "headless: builds nothing (no SubViewport, no lights)")
	hero.queue_free()

	var menu := MainMenu.new()
	root.add_child(menu)
	for i in 3:
		await process_frame
	_check(menu.hero != null and menu.hero.is_inside_tree(), "the real MainMenu holds a MenuHero")
	_check(not menu.hero.active, "and it stays inactive headless")
	for key in ["new_game", "continue", "load_game", "replay_ending", "arena", "settings", "credits"]:
		_check(menu.button(key) != null, "button still present: %s" % key)

	# The hero reads the storm's flash: when active, a stronger flash must raise the key light.
	var fake := MenuHero.new(storm)
	fake.key_light = DirectionalLight3D.new()
	fake.active = true
	root.add_child(fake)
	root.add_child(fake.key_light)
	fake._process(0.0)
	var calm: float = fake.key_light.light_energy
	storm._flash = 1.0
	fake._process(0.0)
	_check(fake.key_light.light_energy > calm + 1.0, "a lightning flash raises the key light (%.2f -> %.2f)" % [calm, fake.key_light.light_energy])
	_check(is_equal_approx(calm, MenuHero.KEY_ENERGY_BASE), "and it rests at the base energy when calm")

	# --- combat imagery: a lightning strike plays an attack clip every 10 to 16 seconds, then idle (stepped clock) ---
	_check(_model_has_strike_clip(), "the real player model has a light_1 or heavy clip to strike with")
	var striker := MenuHero.new(storm)
	root.add_child(striker)
	striker.active = true
	var anim := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	var idle_clip := Animation.new()
	idle_clip.length = 1.0
	lib.add_animation("idle", idle_clip)
	var strike_clip := Animation.new()
	strike_clip.length = 0.8
	lib.add_animation("light_1", strike_clip)
	anim.add_animation_library("", lib)
	striker.add_child(anim)
	striker._anim = anim
	anim.play("idle")

	var step := 0.1
	var clock := 0.0
	var strike_times: Array[float] = []
	var returns := 0
	var prev_clip := "idle"
	for i in 700:  # 70 seconds; a flash every other step is a rising edge every 0.2 s
		clock += step
		storm._flash = 1.0 if i % 2 == 0 else 0.0
		striker.tick(step)
		var now := String(anim.current_animation)
		if now == "light_1" and prev_clip != "light_1":
			strike_times.append(clock)
		if now == "idle" and prev_clip == "light_1":
			returns += 1
		prev_clip = now
	_check(strike_times.size() >= 4, "over 70 s the striker strikes several times (%d)" % strike_times.size())
	_check(striker.strikes == strike_times.size(), "every strike is counted once (%d)" % striker.strikes)
	var first_ok := strike_times.size() > 0 and strike_times[0] >= 10.0 and strike_times[0] <= 16.2
	_check(first_ok, "the first strike comes 10 to 16 seconds in (%.1f s)" % (strike_times[0] if strike_times.size() > 0 else -1.0))
	var gaps_ok := true
	for i in range(1, strike_times.size()):
		var gap := strike_times[i] - strike_times[i - 1]
		if gap < 10.0 or gap > 16.2:
			gaps_ok = false
	_check(gaps_ok, "every gap between strikes is 10 to 16 seconds")
	_check(returns >= strike_times.size() - 1, "each strike returns to idle afterwards (%d returns)" % returns)
	_check(striker._attack_until < 0.0 or striker._clock < striker._attack_until + 1.0, "no attack clip is left stuck playing")

	var dormant := MenuHero.new(storm)  # not built: must never strike
	root.add_child(dormant)
	for i in 700:
		storm._flash = 1.0 if i % 2 == 0 else 0.0
		dormant.tick(step)
	_check(dormant.strikes == 0 and dormant._anim == null, "an unbuilt striker (headless, low quality, web) never strikes")

	print("menu_hero_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
