class_name WeaponTrail
extends Node3D
## Short ribbon behind a weapon blade while its owner's hitbox is active (the swing's active frames).
## One per character, owned and freed by the Fx autoload; gameplay scenes know nothing about it.
##
## Blade points: a `TrailBase` and `TrailTip` Node3D under the character's VisualRoot/WeaponPivot win
## (a hand-attached model can add them); otherwise they are derived from the `Weapon` node
## (hilt = origin, tip = origin - basis.z * blade length), otherwise from the hitbox position.
## Cost: <= MAX_SEGMENTS samples, one shared material, the mesh is only rebuilt while the ribbon is alive.

const MAX_SEGMENTS: int = 12
const FADE_SECONDS: float = 0.15
const MIN_STEP: float = 0.05        # metres the tip must move before another sample is stored
const PEAK_ALPHA: float = 0.9
const HILT_OFFSET: float = 0.3      # base sits this far along the blade from the weapon origin
const TIP_LIFT: float = 0.26        # a horizontal slash lies in one plane and is edge-on to the camera, so the
const BASE_DROP: float = 0.3        # ribbon is sloped: tip edge raised, hilt edge lowered (derived points only)
const DEFAULT_BLADE: float = 1.0
const ENEMY_COLOR: Color = Color(1.0, 0.25, 0.15)

static var _material: StandardMaterial3D

var character: Node3D
var hitbox: Hitbox
var is_player: bool = false
var quality_scale: float = 1.0

var _mesh_instance: MeshInstance3D
var _mesh: ImmediateMesh
var _tips: PackedVector3Array = PackedVector3Array()
var _bases: PackedVector3Array = PackedVector3Array()
var _times: PackedFloat64Array = PackedFloat64Array()
var _head: int = 0            # next write slot
var _count: int = 0
var _clock: float = 0.0
var _was_active: bool = false
var _drawn: bool = false
var _color: Color = Color.WHITE
var _pivot: Node3D
var _weapon: Node3D
var _tip_marker: Node3D
var _base_marker: Node3D


## Shared by every trail (and the warm-up), so starting a swing never builds a material.
static func shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.vertex_color_use_as_albedo = true
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.disable_fog = true
		_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _material


func _ready() -> void:
	_tips.resize(MAX_SEGMENTS)
	_bases.resize(MAX_SEGMENTS)
	_times.resize(MAX_SEGMENTS)
	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.extra_cull_margin = 4.0  # the ribbon spans world positions far from this node's origin
	_mesh_instance.visible = false
	add_child(_mesh_instance)


func samples() -> int:
	return _count


func is_drawn() -> bool:
	return _drawn


## Sampling runs on the physics tick (the hitbox's own clock): at 60 Hz it is one sample per active frame
## even when rendering is slow, so the ribbon is a smooth arc and not a few coarse triangles.
func _physics_process(_delta: float) -> void:
	var active := quality_scale > 0.0 and hitbox != null and is_instance_valid(hitbox) \
			and is_instance_valid(character) and hitbox.is_active()
	if active:
		if not _was_active:
			_begin()
		_push_sample()
	_was_active = active


func _process(delta: float) -> void:
	_clock += delta
	while _count > 0 and _clock - _times[_oldest()] > FADE_SECONDS:
		_count -= 1
	if _count < 2:
		if _drawn:
			_mesh.clear_surfaces()
			_mesh_instance.visible = false
			_drawn = false
		return
	_rebuild()


# --- sampling --------------------------------------------------------------

func _begin() -> void:
	_count = 0
	_head = 0
	_color = _pick_color()
	_pivot = character.get_node_or_null("VisualRoot/WeaponPivot") as Node3D
	_weapon = null
	_tip_marker = null
	_base_marker = null
	if _pivot:
		_weapon = _pivot.get_node_or_null("Weapon") as Node3D
		_tip_marker = _pivot.find_child("TrailTip", true, false) as Node3D
		_base_marker = _pivot.find_child("TrailBase", true, false) as Node3D


func _oldest() -> int:
	return (_head - _count + MAX_SEGMENTS) % MAX_SEGMENTS


func _push_sample() -> void:
	var points := _blade_points()
	if points.is_empty():
		return
	var tip := points[0]
	var base := points[1]
	if _count > 0:
		var last := (_head - 1 + MAX_SEGMENTS) % MAX_SEGMENTS
		if _tips[last].distance_to(tip) < MIN_STEP and _bases[last].distance_to(base) < MIN_STEP:
			_times[last] = _clock  # blade is still: keep the newest sample fresh instead of adding more
			return
	_tips[_head] = tip
	_bases[_head] = base
	_times[_head] = _clock
	_head = (_head + 1) % MAX_SEGMENTS
	_count = mini(_count + 1, MAX_SEGMENTS)


## [tip, base] in world space, or an empty array when nothing usable exists.
func _blade_points() -> PackedVector3Array:
	if _tip_marker != null and _base_marker != null \
			and is_instance_valid(_tip_marker) and is_instance_valid(_base_marker):
		return PackedVector3Array([_tip_marker.global_position, _base_marker.global_position])
	if _weapon != null and is_instance_valid(_weapon):
		var xform := _weapon.global_transform
		var forward := -xform.basis.z  # carries the owner's scale (the Warden's blade is bigger)
		var unit := xform.basis.y.length()
		return PackedVector3Array([
			xform.origin + forward * (HILT_OFFSET + _blade_length()) + Vector3.UP * (TIP_LIFT * unit),
			xform.origin + forward * HILT_OFFSET + Vector3.DOWN * (BASE_DROP * unit)])
	if hitbox != null and is_instance_valid(hitbox):
		var center := hitbox.global_position
		return PackedVector3Array([center + Vector3(0.0, 0.4, 0.0), center + Vector3(0.0, -0.4, 0.0)])
	return PackedVector3Array()


func _blade_length() -> float:
	if not is_player:
		return DEFAULT_BLADE
	var inventory: Variant = character.get("inventory")
	if inventory != null and inventory.get("weapon") != null:
		var item: ItemData = inventory.weapon
		var spec: Dictionary = WeaponModel.SPECS.get(item.item_id, WeaponModel.FALLBACK_SPEC)
		return float(spec["blade"])
	return DEFAULT_BLADE


func _pick_color() -> Color:
	if not is_player:
		return ENEMY_COLOR
	var inventory: Variant = character.get("inventory")
	if inventory != null and inventory.get("weapon") != null:
		return (inventory.weapon as ItemData).color()
	return Color.WHITE


# --- drawing ---------------------------------------------------------------

func _rebuild() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, shared_material())
	var first := _oldest()
	for n in _count:
		var i := (first + n) % MAX_SEGMENTS
		var age := clampf((_clock - _times[i]) / FADE_SECONDS, 0.0, 1.0)
		var alpha := PEAK_ALPHA * (1.0 - age) * (1.0 - age)
		_mesh.surface_set_color(Color(_color, alpha * 0.5))  # base edge is fainter than the tip edge
		_mesh.surface_add_vertex(_bases[i])
		_mesh.surface_set_color(Color(_color, alpha))
		_mesh.surface_add_vertex(_tips[i])
	_mesh.surface_end()
	_mesh_instance.visible = true
	_drawn = true
