extends SceneTree
## Hint text follows the player's key bindings (headless):
##   godot --headless --path . -s tests/key_hint_check.gd

const BootScript = preload("res://scripts/core/boot.gd")

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


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


func _run() -> void:
	KeyBindings.capture_defaults()
	KeyBindings.reset_all()

	print("-- helpers")
	_check(KeyBindings.key_name(&"use_item") == "R", "medkit default shows R (%s)" % KeyBindings.key_name(&"use_item"))
	_check(KeyBindings.key_name(&"interact") == "E", "interact default shows E (%s)" % KeyBindings.key_name(&"interact"))
	_check(KeyBindings.key_name(&"lock_on") == "Middle mouse", "lock-on default shows the middle mouse (%s)" % KeyBindings.key_name(&"lock_on"))
	_check(KeyBindings.key_name(&"no_such_action") == "?", "an unknown action shows ? instead of erroring")
	_check(KeyBindings.fill("Press {use_item} now") == "Press R now", "fill replaces a token")
	_check(KeyBindings.fill("no tokens") == "no tokens", "fill leaves plain text alone")

	print("-- texts at the defaults")
	var hud_default := Hud.hint_text()
	_check(hud_default.begins_with("WASD move"), "the HUD strip starts with WASD move (%s)" % hud_default)
	_check(hud_default.contains("R medkit") and hud_default.contains("Left mouse light"), "the HUD strip names the default keys")
	_check(not hud_default.contains("{"), "no unreplaced tokens in the HUD strip")
	for tip in BootScript.TIPS:
		_check(not KeyBindings.fill(tip).contains("{"), "boot tip has no unreplaced token: %s" % tip.left(40))
	for tip in DeathScreen.HINTS:
		_check(not KeyBindings.fill(tip).contains("{"), "death hint has no unreplaced token: %s" % tip.left(40))

	print("-- rebinding changes the shown text")
	KeyBindings.rebind(&"use_item", _key(KEY_H))
	KeyBindings.rebind(&"interact", _key(KEY_G))
	_check(KeyBindings.key_name(&"use_item") == "H", "medkit now shows H")
	_check(Hud.hint_text().contains("H medkit") and not Hud.hint_text().contains("R medkit"), "the HUD strip follows the medkit rebind")
	var medkit_tip := ""
	for tip in BootScript.TIPS:
		if tip.contains("{use_item}"):
			medkit_tip = KeyBindings.fill(tip)
	_check(medkit_tip.contains("Press H"), "the loading tip follows the medkit rebind (%s)" % medkit_tip.left(20))
	var death_tip := ""
	for tip in DeathScreen.HINTS:
		if tip.contains("{use_item}"):
			death_tip = KeyBindings.fill(tip)
	_check(death_tip.contains("Press H"), "the death-screen hint follows the medkit rebind")
	_check(DeathScreen.HINTS.size() > 0 and BootScript.TIPS.size() > 0, "tip lists are not empty")

	KeyBindings.rebind(&"move_forward", _key(KEY_UP))
	_check(Hud.hint_text().contains("Up"), "a rebound movement key shows in the HUD strip (%s)" % Hud.hint_text().left(30))

	print("-- reset restores the defaults text")
	KeyBindings.reset_all()
	_check(Hud.hint_text() == hud_default, "after Reset to defaults the HUD strip is the original")

	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
