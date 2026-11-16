class_name PaymentRecovery
extends Interactable
## The one place the protagonist's payment can be taken back. Not a loot container: a short scripted moment
## (the camera settles on the bag, a line, the flap opens, a second line), then the bag goes into the inventory
## once, a modest sum of credits is added, and `payment_recovered` is set. Nothing is granted before the
## interaction, before the Area D Warden has fallen, or a second time (a PersistentIds claim plus the
## inventory's own unique-item rule).

const ITEM_PATH: String = "res://resources/items/payment_bag.tres"
const CREDITS: int = 1500
const REGION_ID: StringName = &"outpost_17"
const CLAIM_ID: StringName = &"payment_bag"
const FLAG_BOSS: StringName = &"warden_d_defeated"
const FLAG_STORE_OPEN: StringName = &"door_payment_store_open"
const FLAG_RECOVERED: StringName = &"payment_recovered"
const LINE_ONE: String = "There you are."
const LINE_TWO: String = "All of it."
const SETTLE_SECONDS: float = 1.6
const OPEN_HOLD_SECONDS: float = 1.8

signal recovered

## The prop on the shelf; removed when the bag is taken so a reload shows an empty shelf.
var bag: Node3D

var _busy: bool = false


func _ready() -> void:
	super._ready()
	interaction_id = CLAIM_ID
	prompt_text = "Take your bag"
	locked_text = "The store is shut"
	one_shot = true
	interact_radius = maxf(interact_radius, 2.4)
	var state := get_node_or_null("/root/WorldState")
	if state != null:
		state.flag_changed.connect(_on_flag_changed)
		if state.has_flag(FLAG_RECOVERED):
			mark_used(true)
			enabled = false
	_refresh_lock()


func is_recovered() -> bool:
	var state := get_node_or_null("/root/WorldState")
	return state != null and state.has_flag(FLAG_RECOVERED)


func _refresh_lock() -> void:
	var state := get_node_or_null("/root/WorldState")
	locked = state == null or not (state.has_flag(FLAG_BOSS) and state.has_flag(FLAG_STORE_OPEN))


func _on_flag_changed(_id: StringName, _value: bool) -> void:
	_refresh_lock()


func _on_interact(player: Node3D) -> void:
	recover(player)


## The interaction. Headless runs (tests) skip the presentation and grant at once.
func recover(player: Node3D) -> void:
	if _busy or is_recovered():
		return
	_busy = true
	if DisplayServer.get_name() == "headless" or bag == null or not is_instance_valid(bag):
		grant(player)
		_busy = false
		return
	var camera := get_tree().get_first_node_in_group("camera_controller")
	if camera != null and camera.has_method("set_lock_target"):
		camera.call("set_lock_target", bag)
	AnimationDriver.play_on(player, "open_bag", 0.7)  # kneel, spread the flap, lift both hands: about as long as the moment
	Outpost17.say(self, LINE_ONE, SETTLE_SECONDS + 0.6)
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	if not is_inside_tree():
		return
	PaymentBag.open(bag)
	await get_tree().create_timer(OPEN_HOLD_SECONDS * 0.5).timeout
	if not is_inside_tree():
		return
	Outpost17.say(self, LINE_TWO, OPEN_HOLD_SECONDS)
	await get_tree().create_timer(OPEN_HOLD_SECONDS).timeout
	if not is_inside_tree():
		return
	if camera != null and is_instance_valid(camera) and camera.has_method("clear_lock_target"):
		camera.call("clear_lock_target")
	grant(player)
	_busy = false


## Gives the payment. True only the one time it really happened.
func grant(player: Node3D) -> bool:
	var state := get_node_or_null("/root/WorldState")
	if state == null or state.has_flag(FLAG_RECOVERED) or not state.has_flag(FLAG_BOSS):
		return false
	var p := player as Player
	if p == null or p.inventory == null:
		return false
	if not PersistentIds.claim(REGION_ID, CLAIM_ID):
		return false
	var item := load(ITEM_PATH) as ItemData
	if item != null:
		p.inventory.collect(item)
	p.inventory.add_currency(CREDITS)
	state.set_flag(FLAG_RECOVERED, true)
	if is_instance_valid(bag):
		bag.queue_free()
	bag = null
	enabled = false
	recovered.emit()
	return true
