class_name HitStop
extends RefCounted
## Brief slow-motion on impact. It must read as weight, not as a freeze:
##  - gentle (time_scale 0.3, not 0.05), so movement and animation never stop dead
##  - never stacks: overlapping requests extend to the longest, they do not add up
##  - a short cooldown after each one, so a swing that hits four enemies on consecutive frames
##    cannot chain into one long freeze
##  - requested durations are clamped, so data changes in AttackData cannot bring the lag back
## Uses real time (frame ticks), so pausing or time_scale itself cannot stretch it.

enum Level { OFF, LIGHT, NORMAL }

const SLOW_SCALE: float = 0.3
const DURATION_FACTOR: float = 0.6   # AttackData.hit_stop is tuned for the old hard freeze
const MAX_SECONDS: float = 0.07
const COOLDOWN_US: int = 110000
const LEVEL_FACTOR: Array[float] = [0.0, 0.5, 1.0]

static var enabled: bool = true
static var level: Level = Level.NORMAL

static var _running: bool = false
static var _until_us: int = 0
static var _cooldown_until_us: int = 0


static func reset() -> void:
	_running = false
	_until_us = 0
	_cooldown_until_us = 0
	Engine.time_scale = 1.0


## Seconds actually applied for a requested duration (0 when disabled). Exposed for tests.
static func effective_seconds(requested: float) -> float:
	if not enabled or level == Level.OFF or requested <= 0.0:
		return 0.0
	return minf(requested * DURATION_FACTOR, MAX_SECONDS) * LEVEL_FACTOR[level]


static func trigger(seconds: float) -> void:
	var applied := effective_seconds(seconds)
	if applied <= 0.0:
		return
	var now := Time.get_ticks_usec()
	var end_us := now + int(applied * 1.0e6)
	if _running:
		_until_us = maxi(_until_us, end_us)  # longest wins, never additive
		return
	if now < _cooldown_until_us or Engine.time_scale < 1.0:
		return
	_running = true
	_until_us = end_us
	Engine.time_scale = SLOW_SCALE
	var tree := Engine.get_main_loop() as SceneTree
	while _running and Time.get_ticks_usec() < _until_us:
		await tree.process_frame
	if _running:  # reset() during the wait already restored everything
		Engine.time_scale = 1.0
		_running = false
		_cooldown_until_us = Time.get_ticks_usec() + COOLDOWN_US
