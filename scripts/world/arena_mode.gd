class_name ArenaMode
extends RefCounted
## Arena Mode: the five-wave arena as a replayable challenge from the main menu. It is isolated from the campaign:
## while it is active nothing is written to any save file (SaveManager.write_data refuses), the world and progression
## start from a fresh run, and no reward is paid (WaveManager skips the completion reward). The only thing it keeps
## is a small record file of its own: best clear time, furthest wave and run count.

const SECTION: String = "arena"

static var active: bool = false
static var record_path: String = "user://arena_records.cfg"


static func begin() -> void:
	active = true


static func end() -> void:
	active = false


static func best_time() -> float:
	return float(_read("best_time", 0.0))


static func best_wave() -> int:
	return int(_read("best_wave", 0))


static func run_count() -> int:
	return int(_read("runs", 0))


## Stores one finished run. `waves_cleared` is how many waves were beaten (the total on a clear). Returns
## {"new_best_time": bool, "new_best_wave": bool, "best_time": float, "best_wave": int}.
static func record_run(waves_cleared: int, seconds: float, completed: bool) -> Dictionary:
	var config := ConfigFile.new()
	config.load(record_path)
	var out := {"new_best_time": false, "new_best_wave": false}
	var previous_time := float(config.get_value(SECTION, "best_time", 0.0))
	var previous_wave := int(config.get_value(SECTION, "best_wave", 0))
	var waves := maxi(waves_cleared, 0)
	if waves > previous_wave:
		config.set_value(SECTION, "best_wave", waves)
		out["new_best_wave"] = true
	if completed and is_finite(seconds) and seconds > 0.0 and (previous_time <= 0.0 or seconds < previous_time):
		config.set_value(SECTION, "best_time", seconds)
		out["new_best_time"] = true
	config.set_value(SECTION, "runs", int(config.get_value(SECTION, "runs", 0)) + 1)
	config.save(record_path)
	out["best_time"] = float(config.get_value(SECTION, "best_time", 0.0))
	out["best_wave"] = int(config.get_value(SECTION, "best_wave", 0))
	return out


static func format_time(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	return "%d:%02d" % [total / 60, total % 60]


static func _read(key: String, fallback: Variant) -> Variant:
	var config := ConfigFile.new()
	if config.load(record_path) != OK:
		return fallback
	return config.get_value(SECTION, key, fallback)
