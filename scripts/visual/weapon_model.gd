class_name WeaponModel
extends Node3D
## Low-poly sword built in code and swapped whenever the equipped weapon changes.
## Lives at VisualRoot/WeaponPivot/Weapon: the pivot swings it, the pivot's visibility shows it.
## All parts and the two materials are created once and re-configured, so a swap allocates nothing.
##
## The model points down -Z from the hand (z = HAND_Z); the blade lies flat for horizontal slashes.

const HAND_Z: float = -0.25
const GRIP_T: float = 0.05

## Per-weapon proportions. blade_color / trim_color are the metal and the handle/guard accent.
## curve_deg bends the last 40% of the blade sideways (machete, katana).
const SPECS: Dictionary = {
	&"improvised_blade": {"blade": 0.8, "w": 0.09, "t": 0.03, "guard": 0.0, "grip": 0.25, "pommel": 0.0,
			"curve": 9.0, "blade_color": Color(0.5, 0.46, 0.42), "trim_color": Color(0.3, 0.2, 0.12)},
	&"combat_knife": {"blade": 0.5, "w": 0.07, "t": 0.025, "guard": 0.14, "grip": 0.2, "pommel": 0.07,
			"curve": 0.0, "blade_color": Color(0.62, 0.65, 0.68), "trim_color": Color(0.12, 0.12, 0.13)},
	&"iron_sword": {"blade": 1.0, "w": 0.1, "t": 0.03, "guard": 0.3, "grip": 0.26, "pommel": 0.08,
			"curve": 0.0, "blade_color": Color(0.55, 0.57, 0.6), "trim_color": Color(0.25, 0.16, 0.1)},
	&"military_machete": {"blade": 0.95, "w": 0.17, "t": 0.03, "guard": 0.0, "grip": 0.27, "pommel": 0.07,
			"curve": 14.0, "blade_color": Color(0.45, 0.5, 0.4), "trim_color": Color(0.15, 0.2, 0.12)},
	&"katana": {"blade": 1.25, "w": 0.065, "t": 0.025, "guard": 0.14, "grip": 0.38, "pommel": 0.06,
			"curve": 6.0, "blade_color": Color(0.82, 0.86, 0.9), "trim_color": Color(0.08, 0.08, 0.1)},
	&"tactical_sword": {"blade": 1.15, "w": 0.1, "t": 0.03, "guard": 0.4, "grip": 0.28, "pommel": 0.09,
			"curve": 0.0, "blade_color": Color(0.7, 0.74, 0.8), "trim_color": Color(0.15, 0.3, 0.55)},
	&"claymore": {"blade": 1.55, "w": 0.17, "t": 0.045, "guard": 0.62, "grip": 0.36, "pommel": 0.14,
			"curve": 0.0, "blade_color": Color(0.66, 0.68, 0.72), "trim_color": Color(0.35, 0.22, 0.1)},
	&"warden_blade": {"blade": 1.6, "w": 0.28, "t": 0.07, "guard": 0.5, "grip": 0.32, "pommel": 0.16,
			"curve": 0.0, "blade_color": Color(0.28, 0.08, 0.08), "trim_color": Color(0.08, 0.05, 0.05)},
}
const FALLBACK_SPEC: Dictionary = {"blade": 0.9, "w": 0.1, "t": 0.03, "guard": 0.28, "grip": 0.25,
		"pommel": 0.07, "curve": 0.0, "blade_color": Color(0.7, 0.72, 0.75), "trim_color": Color(0.2, 0.15, 0.1)}

const EMISSION_BY_RARITY: Array[float] = [0.0, 0.0, 0.25, 0.45, 0.8]

var _metal: StandardMaterial3D
var _trim: StandardMaterial3D
var _grip: MeshInstance3D
var _pommel: MeshInstance3D
var _guard: MeshInstance3D
var _blade_a: MeshInstance3D
var _bend: Node3D
var _blade_b: MeshInstance3D
var _tip: MeshInstance3D
var _inventory: Inventory
var _shown_id: StringName = &""


func _ready() -> void:
	_metal = StandardMaterial3D.new()
	_metal.metallic = 0.6
	_metal.roughness = 0.45
	_trim = StandardMaterial3D.new()
	_trim.roughness = 0.9
	_grip = _make_part(BoxMesh.new(), _trim)
	_pommel = _make_part(BoxMesh.new(), _trim)
	_guard = _make_part(BoxMesh.new(), _trim)
	_blade_a = _make_part(BoxMesh.new(), _metal)
	_bend = Node3D.new()
	add_child(_bend)
	_blade_b = _make_part(BoxMesh.new(), _metal, _bend)
	_tip = _make_part(PrismMesh.new(), _metal, _bend)
	_tip.rotation_degrees.x = -90.0  # prism apex (+Y) now points down -Z
	_bind.call_deferred()


func _make_part(mesh: Mesh, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(part)
	return part


## The Player creates its Inventory in its own _ready, after this node is ready: bind one frame later.
func _bind() -> void:
	var node := get_parent()
	while node and not node is Player:
		node = node.get_parent()
	var player := node as Player
	if player and player.inventory:
		_inventory = player.inventory
		_inventory.changed.connect(_on_inventory_changed)
		_on_inventory_changed()
	else:
		show_weapon(null)


func _on_inventory_changed() -> void:
	show_weapon(_inventory.weapon if _inventory else null)


## Re-configures the pooled parts for `item` (null = the fallback blade). Cheap and allocation-free.
func show_weapon(item: ItemData) -> void:
	var id: StringName = item.item_id if item else &""
	if id == _shown_id and id != &"":
		return
	_shown_id = id
	var spec: Dictionary = SPECS.get(id, FALLBACK_SPEC)
	var reach: float = item.reach if item else 1.0
	var blade_len: float = spec["blade"] * reach
	var blade_w: float = spec["w"]
	var blade_t: float = spec["t"]
	var guard_w: float = spec["guard"]
	var grip_len: float = spec["grip"]
	var pommel: float = spec["pommel"]
	var curve: float = spec["curve"]

	_metal.albedo_color = spec["blade_color"]
	_trim.albedo_color = spec["trim_color"]
	var glow := EMISSION_BY_RARITY[item.rarity] if item else 0.0
	_metal.emission_enabled = glow > 0.0
	if glow > 0.0:
		_metal.emission = item.color()
		_metal.emission_energy_multiplier = glow

	# Hand at HAND_Z; pommel behind it, blade ahead of the grip and guard.
	var z := HAND_Z
	_set_box(_grip, Vector3(GRIP_T, GRIP_T, grip_len), z - grip_len * 0.5)
	z -= grip_len
	_pommel.visible = pommel > 0.0
	_set_box(_pommel, Vector3(pommel, pommel, pommel), HAND_Z + pommel * 0.3)
	_guard.visible = guard_w > 0.0
	_set_box(_guard, Vector3(guard_w, 0.05, 0.05), z)

	var main_len := blade_len * (0.6 if curve != 0.0 else 1.0) - 0.1 * blade_len
	main_len = maxf(main_len, 0.05)
	_set_box(_blade_a, Vector3(blade_w, blade_t, main_len), z - main_len * 0.5)
	z -= main_len

	var second_len := blade_len * (0.3 if curve != 0.0 else 0.0)
	_blade_b.visible = second_len > 0.0
	_bend.position = Vector3(0.0, 0.0, z)
	_bend.rotation_degrees.y = curve
	(_blade_b.mesh as BoxMesh).size = Vector3(blade_w, blade_t, maxf(second_len, 0.01))
	_blade_b.position = Vector3(0.0, 0.0, -second_len * 0.5)

	var tip_len := blade_len * 0.1 + 0.05
	var tip_mesh := _tip.mesh as PrismMesh
	tip_mesh.size = Vector3(blade_w, tip_len, blade_t)
	_tip.position = Vector3(0.0, 0.0, -second_len - tip_len * 0.5)


func _set_box(part: MeshInstance3D, size: Vector3, center_z: float) -> void:
	(part.mesh as BoxMesh).size = size
	part.position = Vector3(0.0, 0.0, center_z)
