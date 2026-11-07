extends SceneTree
## The Iron Fortress must run on the real combat configs, not the Research Complex fallbacks.
## godot --headless --path . -s tests/fortress_real_configs_check.gd

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _run() -> void:
	_check(FortressEnemies.missing().is_empty(), "no fortress config is on a fallback (%s)" % str(FortressEnemies.missing()))
	for name in ["fortress_infantry", "elite_security_soldier", "heavy_assault_unit", "tactical_commander", "fortress_captain", "director"]:
		_check(not FortressEnemies.is_fallback(name), "%s resolves to its own resource" % name)
	var director_cfg := FortressEnemies.resource("director") as EnemyConfig
	_check(director_cfg != null, "the Director config is an EnemyConfig")
	var scene := load(director_cfg.scene_path) as PackedScene if director_cfg else null
	var node := scene.instantiate() if scene else null
	_check(node is Director, "the Director scene instantiates the Director class")
	if node:
		node.free()
	print("fortress_real_configs_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
