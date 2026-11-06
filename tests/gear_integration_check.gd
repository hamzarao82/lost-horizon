extends SceneTree
## Guards the weapon double-count: Inventory.damage_multiplier() already carries weapon, worn gear and
## buffs, so the progression scale must add nothing for equipment at level 1.
## godot --headless --path . -s tests/gear_integration_check.gd

const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"

var _failures: int = 0
var _checks: int = 0


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


func _run() -> void:
	var progression := root.get_node_or_null("Progression")
	_check(progression != null, "Progression autoload exists")
	var player := load(PLAYER_SCENE).instantiate() as Player
	root.add_child(player)
	for i in 4:
		await physics_frame
	var data := load("res://resources/attacks/heavy_1.tres") as AttackData
	var base_scale: float = player.call("_progression_scale", data)
	_check(is_equal_approx(base_scale, 1.0), "level 1 progression scale is exactly 1.0 (got %.4f)" % base_scale)
	var claymore := load("res://resources/items/claymore.tres") as ItemData
	player.inventory.collect(claymore)
	var eq: Dictionary = player.inventory.equip(claymore)
	_check(bool(eq.get("ok", false)), "claymore equips (%s)" % str(eq.get("reason", "ok")))
	var inv_mult: float = player.inventory.damage_multiplier()
	var prog_scale: float = player.call("_progression_scale", data)
	_check(inv_mult > 1.0, "claymore raises the inventory multiplier (%.3f)" % inv_mult)
	_check(is_equal_approx(prog_scale, 1.0), "progression scale does not repeat the weapon (got %.4f)" % prog_scale)
	_check(is_equal_approx(inv_mult * prog_scale, inv_mult), "swing damage multiplier equals the inventory multiplier once")
	print("gear_integration_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
