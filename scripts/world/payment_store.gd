class_name PaymentStore
extends Node3D
## Outpost 17, Area D: the back store behind the hidden north-west room where the protagonist's payment bag
## is shelved (decision 1 in docs/OPENING_DECISIONS.md). It adds a partition wall with a sealed store door
## (locked until `warden_d_defeated`), a shelf holding the bag, a salvage ledger outside, and the opening's
## last beats: after the bag is recovered an alarm lockdown shuts the two region exits until a breaker is
## thrown, then the short `OpeningEnding` plays once and the road quest takes over.
##
## It owns no mission logic beyond starting `opening_getaway`; every step is a world flag the quest listens to:
##   door_payment_store_open -> payment_recovered -> lockdown_lifted (and `opening_arc_complete` after the ending).

const QUEST_ID: StringName = &"opening_getaway"
const ROAD_QUEST: StringName = &"leave_outpost"
const FLAG_BOSS: StringName = &"warden_d_defeated"
const FLAG_RECOVERED: StringName = &"payment_recovered"
const FLAG_LOCKDOWN: StringName = &"getaway_lockdown"
const FLAG_LIFTED: StringName = &"lockdown_lifted"
const STORE_DOOR_ID: StringName = &"payment_store"

# The hidden room spans x -22.2..-15.3 and z -91.4..-82.7. The partition splits a 2.5 m store off its west end.
const PARTITION_X: float = -19.4
const STORE_DOOR_Z: float = -87.0
const DOOR_GAP: float = 2.2
const ROOM_Z_MIN: float = -91.4
const ROOM_Z_MAX: float = -82.7
const WALL_H: float = 4.0
const SHELF_POS: Vector3 = Vector3(-21.4, 0.0, -87.0)

const NORTH_SHUTTER: Vector3 = Vector3(3.75, 0.0, -89.2)
const NORTH_SHUTTER_WIDTH: float = 37.0
const SOUTH_SHUTTER: Vector3 = Vector3(0.0, 0.0, 75.2)
const SOUTH_SHUTTER_WIDTH: float = 86.0
const BREAKER_POS: Vector3 = Vector3(7.5, 0.0, -86.5)
const GUARD_SCENES: PackedStringArray = [
	"res://scenes/enemies/PatrolSoldier.tscn",
	"res://scenes/enemies/PatrolSoldier.tscn",
	"res://scenes/enemies/HunterElite.tscn",
]
const GUARD_POSITIONS: Array[Vector3] = [Vector3(4.0, 0.1, -84.0), Vector3(11.0, 0.1, -86.0), Vector3(17.0, 0.1, -83.5)]

var door: Door
var recovery: PaymentRecovery
var ledger: LoreDocument
var breaker: LockdownBreaker
var shutters: Array[Door] = []
var guards: Array[Node] = []

var _world: Node
var _quests: Node
var _started: bool = false
var _material: StandardMaterial3D


## The lockdown breaker: usable only while the lockdown is on, and it lifts it.
class LockdownBreaker extends Interactable:
	func _ready() -> void:
		super._ready()
		interaction_id = &"lockdown_breaker"
		prompt_text = "Reset the breaker"
		locked_text = "Breaker idle"
		one_shot = true
		var state := get_node_or_null("/root/WorldState")
		if state != null:
			state.flag_changed.connect(_on_flag)
		_refresh()

	func _on_flag(_id: StringName, _value: bool) -> void:
		_refresh()

	func _refresh() -> void:
		var state := get_node_or_null("/root/WorldState")
		locked = state == null or not state.has_flag(PaymentStore.FLAG_LOCKDOWN) or state.has_flag(PaymentStore.FLAG_LIFTED)

	func _on_interact(_player: Node3D) -> void:
		var state := get_node_or_null("/root/WorldState")
		if state != null:
			state.set_flag(PaymentStore.FLAG_LIFTED, true)


static func build(outpost: Node) -> PaymentStore:
	var store := PaymentStore.new()
	store.name = "PaymentStore"
	outpost.add_child(store)
	return store


func _ready() -> void:
	_world = get_node_or_null("/root/WorldState")
	_quests = get_node_or_null("/root/QuestManager")
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.36, 0.38, 0.37)
	_material.roughness = 0.85
	_build_store()
	if _world != null:
		_world.flag_changed.connect(_on_flag_changed)
		if _world.has_flag(FLAG_BOSS):
			_start_quest()
		if _world.has_flag(FLAG_RECOVERED) and not _world.has_flag(FLAG_LIFTED):
			start_lockdown()


# --- the store ----------------------------------------------------------------

func _build_store() -> void:
	var gap_lo := STORE_DOOR_Z - DOOR_GAP * 0.5
	var gap_hi := STORE_DOOR_Z + DOOR_GAP * 0.5
	_wall("StorePartitionN", Vector3(PARTITION_X, WALL_H * 0.5, (ROOM_Z_MIN + gap_lo) * 0.5), Vector3(0.6, WALL_H, gap_lo - ROOM_Z_MIN))
	_wall("StorePartitionS", Vector3(PARTITION_X, WALL_H * 0.5, (gap_hi + ROOM_Z_MAX) * 0.5), Vector3(0.6, WALL_H, ROOM_Z_MAX - gap_hi))
	_wall("StoreShelf", SHELF_POS + Vector3(0.0, 0.45, 0.0), Vector3(0.8, 0.9, 2.4))
	_wall("StoreCrateA", Vector3(-21.6, 0.5, -84.2), Vector3(1.0, 1.0, 1.0))
	_wall("StoreCrateB", Vector3(-21.5, 0.4, -90.0), Vector3(1.2, 0.8, 1.0))

	door = Door.new()
	door.name = "PaymentStoreDoor"
	door.door_id = STORE_DOOR_ID
	door.width = DOOR_GAP
	door.height = 3.2
	door.locked_by_flag = FLAG_BOSS
	door.lock_reason = "Store sealed: command override required"
	door.position = Vector3(PARTITION_X, 0.0, STORE_DOOR_Z)
	door.rotation.y = PI * 0.5
	add_child(door)

	var sign_label := Label3D.new()
	sign_label.text = "SALVAGE STORE"
	sign_label.font_size = 64
	sign_label.pixel_size = 0.01
	sign_label.modulate = Color(0.95, 0.85, 0.6)
	sign_label.position = Vector3(PARTITION_X + 0.45, 3.5, STORE_DOOR_Z)
	sign_label.rotation = Vector3(0.0, PI * 0.5, 0.0)
	add_child(sign_label)

	var recovered: bool = _world != null and _world.has_flag(FLAG_RECOVERED)
	recovery = PaymentRecovery.new()
	recovery.name = "PaymentRecovery"
	recovery.position = SHELF_POS + Vector3(0.9, 0.7, 0.0)
	add_child(recovery)
	if not recovered:
		var bag := PaymentBag.build()
		bag.position = SHELF_POS + Vector3(0.0, 1.1, 0.0)
		add_child(bag)
		recovery.bag = bag

	ledger = LoreDocument.new()
	ledger.title = "Salvage ledger"
	ledger.body_text = "North shore, after the storm: one leather bag, sealed, brought in by a gate guard and two workers. Shelved in the back store. Not to be opened without authorization."
	ledger.interaction_id = &"log_salvage_ledger"
	ledger.name = "SalvageLedger"
	ledger.position = Vector3(-17.2, 0.7, -85.4)
	add_child(ledger)

	breaker = LockdownBreaker.new()
	breaker.name = "LockdownBreaker"
	breaker.position = BREAKER_POS + Vector3(0.0, 0.7, 0.0)
	add_child(breaker)
	_wall("LockdownBreakerBox", BREAKER_POS + Vector3(0.0, 0.7, 0.0), Vector3(0.7, 1.4, 0.5))


func _wall(wall_name: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = wall_name
	body.position = center
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var visual := BoxMesh.new()
	visual.size = size
	mesh.mesh = visual
	mesh.material_override = _material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh)
	add_child(body)


# --- flow ---------------------------------------------------------------------

func _on_flag_changed(id: StringName, value: bool) -> void:
	if not value:
		return
	if id == FLAG_BOSS:
		_start_quest()
	elif id == FLAG_RECOVERED:
		start_lockdown()
	elif id == FLAG_LIFTED:
		_lift_lockdown()


func _start_quest() -> void:
	if _quests == null or not _quests.has_method("start_quest"):
		return
	_quests.start_quest(QUEST_ID, true)  # refused if it already started or finished


## The alarm: both region exits are shut by full-width shutters until the breaker is thrown, and three guards
## come for the player in the Area D yard. Safe to call twice.
func start_lockdown() -> void:
	if _started or (_world != null and _world.has_flag(FLAG_LIFTED)):
		return
	_started = true
	if _world != null:
		_world.set_flag(FLAG_LOCKDOWN, true)
	shutters.append(_shutter(&"lockdown_north", NORTH_SHUTTER, NORTH_SHUTTER_WIDTH))
	shutters.append(_shutter(&"lockdown_south", SOUTH_SHUTTER, SOUTH_SHUTTER_WIDTH))
	_spawn_guards()
	Outpost17.say(self, "Alarm. The compound is sealing itself. The breaker by the north gate will bring the shutters back up.", 6.0)


func _shutter(shutter_id: StringName, at: Vector3, width: float) -> Door:
	var shutter := Door.new()
	shutter.name = "Shutter_" + String(shutter_id)
	shutter.door_id = shutter_id
	shutter.width = width
	shutter.height = 4.0
	shutter.locked_by_flag = FLAG_LIFTED
	shutter.lock_reason = "LOCKDOWN: breaker offline"
	shutter.position = at
	add_child(shutter)
	return shutter


func _spawn_guards() -> void:
	for i in GUARD_SCENES.size():
		var scene := load(GUARD_SCENES[i]) as PackedScene
		if scene == null:
			continue
		var guard := scene.instantiate() as Node3D
		guard.position = GUARD_POSITIONS[i]
		add_child(guard)
		guards.append(guard)
		if guard.has_method("aggro"):
			guard.call("aggro")


func _lift_lockdown() -> void:
	for shutter in shutters:
		if is_instance_valid(shutter):
			shutter.open(true)
	if _quests != null and _quests.has_method("start_quest"):
		_quests.start_quest(ROAD_QUEST, true)  # the road quest is also started by CampaignFlow; refused if it already is
	OpeningEnding.trigger(get_tree(), _world)
