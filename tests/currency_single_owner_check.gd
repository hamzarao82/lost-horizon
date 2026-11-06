extends SceneTree
## One currency balance: Progression forwards to the player's Inventory.
## godot --headless --path . -s tests/currency_single_owner_check.gd

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
	var player := load("res://scenes/player/Player.tscn").instantiate() as Player
	root.add_child(player)
	for i in 4:
		await physics_frame
	var inv = player.inventory
	var before: int = inv.currency
	var got: int = progression.add_currency(100, false)
	_check(got == 100, "add_currency returns the amount (%d)" % got)
	_check(inv.currency == before + 100, "inventory balance rose by 100 (%d)" % inv.currency)
	_check(progression.currency() == inv.currency, "Progression.currency() reads the inventory balance")
	_check(progression.spend_currency(40), "spend through Progression succeeds")
	_check(inv.currency == before + 60, "inventory balance fell by 40 (%d)" % inv.currency)
	_check(not progression.spend_currency(before + 10000), "overspend refused")
	_check(inv.currency == before + 60, "refused spend changes nothing")
	inv.add_currency(25)
	_check(progression.currency() == before + 85, "inventory-side gains show in Progression")
	var saved: Dictionary = progression.to_dict()
	_check(int(saved.get("currency", -1)) == before + 85, "saved progression currency matches the inventory (%s)" % str(saved.get("currency")))
	print("currency_single_owner_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
