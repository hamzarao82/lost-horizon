extends SceneTree
## Headless: godot --headless --path . -s tests/hitstop_check.gd
## Pins the hit-stop contract: gentle, clamped, never stacking, always recovering.

var _fail: int = 0
var _n: int = 0


func _check(ok: bool, msg: String) -> void:
	_n += 1
	if not ok:
		_fail += 1
	print("  ", "ok   " if ok else "FAIL ", msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	HitStop.enabled = true
	HitStop.level = HitStop.Level.NORMAL
	HitStop.reset()
	_check(is_equal_approx(HitStop.effective_seconds(0.10), 0.06), "heavy 0.10 -> 0.06 s")
	_check(is_equal_approx(HitStop.effective_seconds(0.05), 0.03), "light 0.05 -> 0.03 s")
	_check(HitStop.effective_seconds(5.0) <= HitStop.MAX_SECONDS + 0.0001, "huge requests are clamped to the max")
	HitStop.level = HitStop.Level.LIGHT
	_check(is_equal_approx(HitStop.effective_seconds(0.10), 0.03), "Light level halves it")
	HitStop.level = HitStop.Level.OFF
	_check(HitStop.effective_seconds(0.10) == 0.0, "Off level disables it")
	HitStop.level = HitStop.Level.NORMAL
	HitStop.enabled = false
	_check(HitStop.effective_seconds(0.10) == 0.0, "enabled = false disables it")
	HitStop.enabled = true

	HitStop.trigger(0.10)
	_check(is_equal_approx(Engine.time_scale, HitStop.SLOW_SCALE), "slow-motion is gentle (%.2f), not a freeze" % Engine.time_scale)
	_check(Engine.time_scale >= 0.25, "never slower than 0.25")
	HitStop.trigger(0.10)  # overlapping request must not stack or deepen it
	_check(is_equal_approx(Engine.time_scale, HitStop.SLOW_SCALE), "overlapping triggers do not stack")
	var start := Time.get_ticks_usec()
	while Engine.time_scale < 1.0 and (Time.get_ticks_usec() - start) < 1000000:
		await process_frame
	var held := (Time.get_ticks_usec() - start) / 1000.0
	_check(is_equal_approx(Engine.time_scale, 1.0), "time_scale recovers to 1.0")
	_check(held < 140.0, "total slow-motion stays short (%.0f ms)" % held)

	HitStop.trigger(0.10)  # inside the cooldown after the previous one: ignored
	_check(is_equal_approx(Engine.time_scale, 1.0), "a hit right after one is ignored (no chained freeze)")
	HitStop.reset()
	_check(is_equal_approx(Engine.time_scale, 1.0), "reset restores time_scale")
	print("\n%d checks, %d failed" % [_n, _fail])
	quit(1 if _fail > 0 else 0)
