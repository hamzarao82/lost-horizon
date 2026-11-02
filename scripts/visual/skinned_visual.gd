class_name SkinnedVisual
extends CharacterVisual
## Draws a Player or Enemy with an imported, skinned GLB (skeleton + clips) instead of the code-built rig.
##
## Placement: a child of VisualRoot, beside HumanoidRig. It READS the body every frame (state,
## velocity, is_on_floor(), and for attacks the private _attack_idx / _attack_frames / _chain on Player
## or _swing / _attack_frames on Enemy, the same contract HumanoidRig uses) and never calls gameplay
## code. Combat stays authoritative: attack clips are scrubbed to the combat frame counter, so damage,
## hitboxes, hit-stop and attack speed are untouched.
##
## If the model is missing or broken, nothing here activates and the procedural rig stays visible.
## Model contract: see docs/ANIMATION.md (bones, clip names, vertex colours, 1.8 m, faces -Z).

## Global switch: true keeps the procedural rig everywhere (low-end devices, A/B performance runs).
static var disabled: bool = false

const MODEL_DIR: String = "res://assets/characters/"
const ARMOR_DIR: String = "res://assets/armor/"
const WEAPON_DIR: String = "res://assets/weapons/"
const ITEM_DIR: String = "res://resources/items/"
const ENEMY_MODELS: Dictionary = {"Soldier": "soldier", "Heavy": "heavy", "Hunter": "elite"}
## Cosmetic weapons for enemies (the player's follows the Inventory).
const ENEMY_WEAPONS: Dictionary = {
	"soldier": &"military_machete", "heavy": &"claymore", "elite": &"katana", "warden": &"warden_blade",
}
const ATTACK_CLIPS: Dictionary = {
	&"light_1": "light_1", &"light_2": "light_2", &"light_3": "light_3", &"heavy_1": "heavy",
	&"sprint_attack": "sprint_attack", &"air_attack": "air_attack", &"spin_special": "spin",
	&"enemy_swing": "light_1", &"heavy_swing": "heavy", &"hunter_slash": "light_2",
	&"warden_slam": "slam", &"warden_flurry": "flurry", &"warden_shockwave": "shockwave_cast",
	&"warden_charge": "heavy", &"warden_leap": "shockwave_cast", &"warden_fire": "shockwave_cast",
}
const VISUAL_HEIGHT: float = 1.8  # the figure the old capsule rig, the colliders and the hitboxes are built around
const FLASH_STRENGTH: float = 0.55
## Saturated tints (red windup, blue dodge) are scaled down so a telegraph glows without hiding the model.
const TELEGRAPH_SCALE: float = 0.6
const ENRAGE_STRENGTH: float = 0.2
const ROAR_TIME: float = 2.5  # matches Warden.ROAR_TIME

## Overrides the automatic choice (player.glb, soldier.glb, heavy.glb, elite.glb, warden.glb).
@export var model_path: String = ""
## Enemy cosmetic weapon id; empty = automatic (player: equipped weapon).
@export var weapon_id: StringName = &""
## Turn the model if it was exported facing +Z instead of -Z.
@export var yaw_offset_deg: float = 0.0
@export var weapon_position: Vector3 = Vector3(0.0, 0.05, 0.0)  # grip sits in the palm, a little along the hand bone
@export var weapon_rotation_deg: Vector3 = Vector3(90.0, 0.0, 0.0)  # hand bone +Y -> blade forward, flat side up
@export var plate_position: Vector3 = Vector3.ZERO
## Align the strike of every attack clip with the start of the combat system's active window.
@export var align_strike: bool = true
## Scale the model so it is as tall as the figure gameplay is built around (1.8 m x body_scale: enemy hitboxes
## and reach are scaled the same way). Off = the model keeps its authored size.
@export var fit_to_gameplay_height: bool = true

var loaded: bool = false
## Height of the model in its own units (feet at y = 0), measured when it loads.
var authored_height: float = 1.8
var driver: AnimationDriver
var model: Node3D
var hand_socket: WeaponSocket
var chest_socket: WeaponSocket
var meshes: Array[MeshInstance3D] = []

var _visual_root: Node3D
var _torso: MeshInstance3D
var _rig: HumanoidRig
var _old_weapon: Node3D
var _procedural: ProceduralVisual
var _overlay: StandardMaterial3D        # the overlay currently on the meshes (null = none)
var _overlay_add: StandardMaterial3D    # bright tints (hit flash, windup, dodge): adds light, keeps the model's own colours
var _overlay_mix: StandardMaterial3D    # dark tints (death): blends toward the colour
var _overlay_on: bool = false
var _inventory: Inventory
var _is_player: bool = false
var _has_death: bool = false
var _base_body_color: Color = Color(-1.0, 0.0, 0.0)
var _air_time: float = 0.0
var _land_timer: float = 0.0
var _own_dodge_time: float = 0.0
var _weapon_scene_checked: bool = false
var _weapon_scene_hook: bool = false


func _ready() -> void:
	_visual_root = get_parent() as Node3D
	var owner_body: CharacterBody3D = _visual_root.get_parent() as CharacterBody3D if _visual_root else null
	bind(owner_body)
	if _visual_root == null or owner_body == null:
		set_process(false)
		return
	_torso = _visual_root.get_node_or_null("MeshInstance3D") as MeshInstance3D
	_rig = _visual_root.get_node_or_null("HumanoidRig") as HumanoidRig
	_old_weapon = _visual_root.get_node_or_null("WeaponPivot/Weapon") as Node3D
	_is_player = owner_body is Player
	_procedural = ProceduralVisual.new()
	_procedural.name = "ProceduralFallback"
	_procedural.rig = _rig
	add_child(_procedural)
	_procedural.bind(owner_body)
	if _load_model():
		set_active(true)
		_bind_inventory.call_deferred()
	else:
		set_process(false)  # keep the procedural rig; nothing to do


func is_skinned() -> bool:
	return loaded


func has_clip(clip_name: String) -> bool:
	return driver != null and driver.has_clip(clip_name)


# --- loading ---------------------------------------------------------------------

func _resolve_model_path() -> String:
	if model_path != "":
		return model_path
	if body is Warden:
		return MODEL_DIR + "warden.glb"
	if body is Enemy:
		var key := String((body as Enemy).display_name)
		return MODEL_DIR + String(ENEMY_MODELS.get(key, "soldier")) + ".glb"
	if body is Player:
		return MODEL_DIR + "player.glb"
	return ""


func _first_of_type(root: Node, type: String) -> Node:
	var found := root.find_children("*", type, true, false)
	return found[0] if not found.is_empty() else null


func _load_model() -> bool:
	if disabled:
		return false
	var path := _resolve_model_path()
	if path == "" or not ResourceLoader.exists(path):
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("SkinnedVisual: %s did not load as a scene" % path)
		return false
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return false
	var skeleton := _first_of_type(inst, "Skeleton3D") as Skeleton3D
	var anim_player := _first_of_type(inst, "AnimationPlayer") as AnimationPlayer
	var mesh_nodes := inst.find_children("*", "MeshInstance3D", true, false)
	if skeleton == null or anim_player == null or mesh_nodes.is_empty():
		push_warning("SkinnedVisual: %s has no skeleton, animations or mesh; keeping the procedural rig" % path)
		inst.free()
		return false
	inst.name = "Model"
	inst.rotation_degrees.y = yaw_offset_deg
	add_child(inst)
	model = inst
	driver = AnimationDriver.new()
	if not driver.setup(anim_player, anim_player.get_parent()):
		push_warning("SkinnedVisual: %s has no usable animations" % path)
		remove_child(inst)
		inst.free()
		model = null
		driver = null
		return false
	for node in mesh_nodes:
		var mi := node as MeshInstance3D
		meshes.append(mi)
		if mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			var material := mi.get_active_material(surface) as BaseMaterial3D
			if material:
				material.vertex_color_use_as_albedo = true  # the art contract colours with vertices
	hand_socket = WeaponSocket.attach(skeleton, &"Hand_R", "HandSocket")
	if hand_socket:
		hand_socket.position_offset = weapon_position
		hand_socket.rotation_offset_deg = weapon_rotation_deg
	if _is_player:
		chest_socket = WeaponSocket.attach(skeleton, &"Chest", "ChestSocket")
		if chest_socket:
			chest_socket.position_offset = plate_position
	authored_height = _measure_height()
	_has_death = driver.has_exact("death")  # a fallback pose must not cancel the enemy tip-over
	loaded = true
	if not _is_player:
		var key := path.get_file().get_basename()
		set_weapon(weapon_id if weapon_id != &"" else ENEMY_WEAPONS.get(key, &"military_machete"))
	return true


func set_active(active: bool) -> void:
	if not loaded:
		return
	if model:
		model.visible = active
	_procedural.set_active(not active)
	if _old_weapon:
		_old_weapon.visible = not active and _old_weapon.visible
	if active and _torso and _rig == null:
		_torso.visible = false


# --- equipment -------------------------------------------------------------------

func _bind_inventory() -> void:
	if not _is_player or body == null:
		return
	var inv: Variant = body.get("inventory")
	if inv is Inventory:
		_inventory = inv
		if not _inventory.changed.is_connected(_on_inventory_changed):
			_inventory.changed.connect(_on_inventory_changed)
		_on_inventory_changed()


func _on_inventory_changed() -> void:
	if _inventory == null:
		return
	set_weapon(_inventory.weapon.item_id if _inventory.weapon else &"")
	_update_plate(_inventory.armor.item_id if _inventory.armor else &"")


func _weapon_scene(item_id: StringName) -> PackedScene:
	if item_id == &"":
		return null
	if not _weapon_scene_checked:
		_weapon_scene_checked = true
		var script := WeaponModel as GDScript
		for method in script.get_script_method_list():
			if method["name"] == "scene_for":
				_weapon_scene_hook = true
	if _weapon_scene_hook:
		return (WeaponModel as GDScript).call("scene_for", item_id) as PackedScene
	var path := WEAPON_DIR + String(item_id) + ".glb"
	return load(path) as PackedScene if ResourceLoader.exists(path) else null


func set_weapon(item_id: StringName) -> void:
	if hand_socket == null:
		return
	var scene := _weapon_scene(item_id)
	if scene:
		var inst := scene.instantiate() as Node3D
		if inst:
			hand_socket.hold(inst)
			return
	# No model file for this weapon: the code-built sword (it follows the Inventory itself for the player).
	if _is_player and hand_socket.held() is WeaponModel:
		return  # already holding one, and it updates itself on Inventory.changed
	var fallback := WeaponModel.new()
	fallback.position = Vector3(0.0, 0.0, -WeaponModel.HAND_Z)  # put its grip point at the holder origin
	hand_socket.hold(fallback)
	if not _is_player:
		_show_code_weapon.call_deferred(fallback, item_id)


func _show_code_weapon(weapon: WeaponModel, item_id: StringName) -> void:
	if not is_instance_valid(weapon):
		return
	var path := ITEM_DIR + String(item_id) + ".tres"
	weapon.show_weapon(load(path) as ItemData if ResourceLoader.exists(path) else null)


func _update_plate(armor_id: StringName) -> void:
	if chest_socket == null:
		return
	var path := ARMOR_DIR + String(armor_id) + ".glb"
	if armor_id != &"" and ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		var inst := scene.instantiate() as Node3D if scene else null
		chest_socket.hold(inst)
	else:
		chest_socket.hold(null)


# --- tint ------------------------------------------------------------------------

func set_flash_color(color: Color, strength: float) -> void:
	if strength <= 0.01:
		if _overlay_on:
			for mi in meshes:
				mi.material_overlay = null
			_overlay_on = false
		return
	if _overlay_add == null:
		_overlay_add = _make_overlay(BaseMaterial3D.BLEND_MODE_ADD)
		_overlay_mix = _make_overlay(BaseMaterial3D.BLEND_MODE_MIX)
	# A flat alpha-blended layer over a detailed model reads as one colour (a whole red Warden during a
	# windup). Bright tints are added instead, so the model shows through; saturated telegraphs are gentler.
	var dark := maxf(color.r, maxf(color.g, color.b)) < 0.5  # a death tint; red, blue and white all count as bright
	var wanted := _overlay_mix if dark else _overlay_add
	var effective := strength
	if not dark and (maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b))) > 0.5:
		effective = strength * TELEGRAPH_SCALE
	wanted.albedo_color = Color(color.r, color.g, color.b, effective)
	if not _overlay_on or _overlay != wanted:
		for mi in meshes:
			mi.material_overlay = wanted
		_overlay = wanted
		_overlay_on = true


func _make_overlay(mode: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = mode
	return material


## Mirrors the tint gameplay scripts apply to the torso material (white hit flash, red windup,
## blue dodge, dark death) onto the skinned meshes. A change of body_color (the Warden's enrage)
## shows as a faint steady tint.
func _poll_flash() -> void:
	if _torso == null:
		return
	var material := _torso.material_override as BaseMaterial3D
	if material == null:
		material = _torso.get_surface_override_material(0) as BaseMaterial3D
	if material == null:
		return
	var current := material.albedo_color
	var body_color: Variant = body.get("body_color")
	if not body_color is Color:
		set_flash_color(current, 0.0)  # the player has no body colour: gameplay never tints it, so nothing to mirror
		return
	var expected: Color = body_color
	if _base_body_color.r < 0.0:
		_base_body_color = expected
	if _color_distance(current, expected) > 0.05:
		set_flash_color(current, FLASH_STRENGTH)
	elif _color_distance(expected, _base_body_color) > 0.05:
		set_flash_color(expected, ENRAGE_STRENGTH)
	else:
		set_flash_color(current, 0.0)


static func _color_distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


# --- per-frame -------------------------------------------------------------------

func _process(delta: float) -> void:
	update(delta)


func update(delta: float) -> void:
	if not loaded or body == null or not is_visible_in_tree():
		return
	_sync_transform()
	_poll_flash()
	if _old_weapon and _old_weapon.visible:
		_old_weapon.visible = false  # the held weapon replaces the code-built one on the swing pivot
	if _is_player:
		_drive_player(delta)
	else:
		_drive_enemy(delta)


## VisualRoot is scaled by gameplay (enemy body_scale, the player's dodge squash) and tipped over when an
## enemy dies. The model keeps its authored size and, when it has a death clip, its pose.
func _sync_transform() -> void:
	var s := _visual_root.scale
	var target := 1.0
	if fit_to_gameplay_height and authored_height > 0.1:
		var gameplay_scale: Variant = body.get("body_scale")
		target = VISUAL_HEIGHT / authored_height * (gameplay_scale if gameplay_scale is float else 1.0)
	model.scale = Vector3(target / maxf(s.x, 0.01), target / maxf(s.y, 0.01), target / maxf(s.z, 0.01))
	if not _is_player and _has_death:
		model.rotation.x = -_visual_root.rotation.x


func _drive_player(delta: float) -> void:
	var player := body as Player
	match player.state:
		Player.State.DEAD:
			driver.play_state(&"death")
		Player.State.HIT:
			driver.play_state(&"hit")
		Player.State.DODGE:
			var dodge_time: Variant = body.get("_dodge_time")
			_own_dodge_time = dodge_time if dodge_time is float else _own_dodge_time + delta
			driver.scrub_progress("dodge", _own_dodge_time / maxf(player.dodge_duration, 0.01))
		Player.State.ATTACK:
			_own_dodge_time = 0.0
			var chain: Variant = body.get("_chain")
			var idx: Variant = body.get("_attack_idx")
			var data: AttackData = null
			if chain is Array and idx is int and idx >= 0 and idx < (chain as Array).size():
				data = (chain as Array)[idx] as AttackData
			_drive_attack(data)
		_:
			_own_dodge_time = 0.0
			_drive_free(delta, false)


func _drive_enemy(delta: float) -> void:
	var enemy := body as Enemy
	if enemy.state == Enemy.State.DEAD:
		driver.play_state(&"death")
		return
	if body is Warden and body.get("_roaring") == true:
		var roar_time: Variant = body.get("_roar_time")
		var progress := 1.0 - (float(roar_time) / ROAR_TIME if roar_time is float else 0.0)
		driver.scrub_progress("roar", progress)
		return
	match enemy.state:
		Enemy.State.STAGGER:
			driver.play_state(&"hit")
		Enemy.State.ATTACK:
			_drive_attack(body.get("_swing") as AttackData)
		_:
			_drive_free(delta, enemy.state == Enemy.State.CHASE)


func _drive_free(delta: float, guarding: bool) -> void:
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	if body.is_on_floor():
		if _air_time > 0.15:
			_land_timer = 0.18
		_air_time = 0.0
		if _land_timer > 0.0:
			_land_timer -= delta
			driver.play_state(&"land")
		elif guarding and speed < 0.3:
			driver.play_state(&"guard")
		else:
			driver.set_speed(speed)
			driver.play_state(&"loco")
	else:
		_air_time += delta
		if _air_time < 0.2 and body.velocity.y > 1.0:
			driver.play_state(&"jump_start")
		else:
			driver.play_state(&"fall")


## Scrubs the attack clip to the combat system's frame counter (never plays it on its own).
func _drive_attack(data: AttackData) -> void:
	if data == null:
		_drive_free(0.0, false)
		return
	var frames_raw: Variant = body.get("_attack_frames")
	var frames: float = frames_raw if frames_raw is float else 0.0
	var clip := clip_for(data)
	var length := driver.clip_length(clip)
	var position := AnimationDriver.attack_clip_position(
			frames, float(data.startup_frames), float(data.total_frames()), length, align_strike)
	if not driver.scrub(clip, position):
		_drive_free(0.0, false)


## The canonical clip name for an attack (by AttackData.id; unknown ids use light_1).
static func clip_for(data: AttackData) -> String:
	return String(ATTACK_CLIPS.get(data.id, "light_1"))


## Top of the model's meshes in the model's own space (the art contract puts the feet at y = 0).
func _measure_height() -> float:
	var top := 0.0
	var to_model := model.global_transform.affine_inverse()
	for mi in meshes:
		if mi.mesh == null:
			continue
		var box: AABB = (to_model * mi.global_transform) * mi.get_aabb()
		top = maxf(top, box.position.y + box.size.y)
	return top if top > 0.1 else VISUAL_HEIGHT
