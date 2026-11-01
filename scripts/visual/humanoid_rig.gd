class_name HumanoidRig
extends Node3D
## Low-poly humanoid built in code, animated procedurally from the owning body's state.
##
## Placement: a child of VisualRoot, which is a child of the CharacterBody3D (Player or Enemy).
## The sibling "MeshInstance3D" under VisualRoot is the torso and the material source: whatever
## material it carries (override or surface override) is shared by every body part, so existing
## hit-flash tinting keeps working. Feet are at y = 0, height about 1.8 m; scale via VisualRoot.
##
## Animation contract (polling only, no signals): body.velocity, body.is_on_floor(), body.state
## (Player.State / Enemy.State), and, while attacking, the private _attack_frames plus the
## AttackData in Player._chain[_attack_idx] or Enemy._swing. Missing pieces fall back to defaults.

@export var accent_color: Color = Color(0.08, 0.09, 0.12)
## Tint the visor from the body material (darkened) instead of using accent_color.
@export var derive_accent: bool = false
@export var fallback_body_color: Color = Color(0.55, 0.55, 0.6)

const HIPS_Y: float = 0.88
const LEG_LEN: float = 0.86
const TORSO_CENTER: float = 0.275
const SPINE_Y: float = 0.09

enum J {
	SPINE_X, SPINE_Y, HEAD_X, LEG_L, LEG_R, ARM_L, ARM_R, ARM_L_OUT, ARM_R_OUT,
	FORE_L, FORE_R, BOB, RIG_X, RIG_Y, COUNT,
}
enum Mode { NORMAL, ATTACK, DODGE, HIT, DEAD }

static var _mesh_cache: Dictionary = {}

var _visual_root: Node3D
var _body: CharacterBody3D
var _player: Player
var _enemy: Enemy
var _torso: MeshInstance3D
var _weapon_pivot: Node3D

var _hips: Node3D
var _spine: Node3D
var _head: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _fore_l: Node3D
var _fore_r: Node3D

var _body_parts: Array[MeshInstance3D] = []
var _body_material: Material
var _accent_material: StandardMaterial3D
var _torso_offset: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, TORSO_CENTER, 0.0))

var _target: PackedFloat32Array = PackedFloat32Array()
var _current: PackedFloat32Array = PackedFloat32Array()
var _time: float = 0.0
var _phase: float = 0.0
var _fallback_frames: float = 0.0
var _rate: float = 16.0


func _ready() -> void:
	_visual_root = get_parent() as Node3D
	if _visual_root:
		_body = _visual_root.get_parent() as CharacterBody3D
		_torso = _visual_root.get_node_or_null("MeshInstance3D") as MeshInstance3D
		_weapon_pivot = _visual_root.get_node_or_null("WeaponPivot") as Node3D
	_player = _body as Player
	_enemy = _body as Enemy
	_target.resize(J.COUNT)
	_current.resize(J.COUNT)
	_build()


static func _box(size: Vector3) -> BoxMesh:
	if not _mesh_cache.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		_mesh_cache[size] = mesh
	return _mesh_cache[size] as BoxMesh


func _pivot(parent: Node3D, pivot_name: String, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = pivot_name
	node.position = pos
	parent.add_child(node)
	return node


func _part(parent: Node3D, size: Vector3, pos: Vector3, accent: bool = false, shadow: bool = false) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _box(size)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if accent:
		mi.material_override = _accent_material
	else:
		_body_parts.append(mi)


func _build() -> void:
	_accent_material = StandardMaterial3D.new()
	_accent_material.albedo_color = accent_color
	_accent_material.emission_enabled = true
	_accent_material.emission = accent_color
	_accent_material.emission_energy_multiplier = 0.5

	_hips = _pivot(self, "Hips", Vector3(0.0, HIPS_Y, 0.0))
	_part(_hips, Vector3(0.4, 0.18, 0.24), Vector3.ZERO)

	_leg_l = _pivot(_hips, "LegL", Vector3(-0.11, -0.02, 0.0))
	_part(_leg_l, Vector3(0.16, LEG_LEN, 0.18), Vector3(0.0, -LEG_LEN * 0.5, 0.0), false, true)
	_leg_r = _pivot(_hips, "LegR", Vector3(0.11, -0.02, 0.0))
	_part(_leg_r, Vector3(0.16, LEG_LEN, 0.18), Vector3(0.0, -LEG_LEN * 0.5, 0.0), false, true)

	_spine = _pivot(_hips, "Spine", Vector3(0.0, SPINE_Y, 0.0))
	# The torso mesh is the existing VisualRoot/MeshInstance3D; _process keeps it on the spine.
	if _torso:
		_torso.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	_head = _pivot(_spine, "Head", Vector3(0.0, 0.56, 0.0))
	_part(_head, Vector3(0.24, 0.26, 0.24), Vector3(0.0, 0.13, 0.0))
	_part(_head, Vector3(0.2, 0.07, 0.04), Vector3(0.0, 0.15, -0.125), true)

	_arm_l = _pivot(_spine, "ArmL", Vector3(-0.31, 0.47, 0.0))
	_part(_arm_l, Vector3(0.11, 0.3, 0.11), Vector3(0.0, -0.15, 0.0))
	_fore_l = _pivot(_arm_l, "ForeL", Vector3(0.0, -0.3, 0.0))
	_part(_fore_l, Vector3(0.1, 0.28, 0.1), Vector3(0.0, -0.14, 0.0))

	_arm_r = _pivot(_spine, "ArmR", Vector3(0.31, 0.47, 0.0))
	_part(_arm_r, Vector3(0.11, 0.3, 0.11), Vector3(0.0, -0.15, 0.0))
	_fore_r = _pivot(_arm_r, "ForeR", Vector3(0.0, -0.3, 0.0))
	_part(_fore_r, Vector3(0.1, 0.28, 0.1), Vector3(0.0, -0.14, 0.0))

	_sync_material()


## Share the torso's material with every body part; re-run when the owner swaps it (enemy _ready).
func _sync_material() -> void:
	if _torso == null:
		return
	var source: Material = _torso.material_override
	if source == null:
		source = _torso.get_surface_override_material(0)
	if source == null:
		var created := StandardMaterial3D.new()
		created.albedo_color = fallback_body_color
		_torso.material_override = created
		source = created
	if source == _body_material:
		return
	_body_material = source
	for part in _body_parts:
		part.material_override = source
	if derive_accent and source is StandardMaterial3D:
		var derived := (source as StandardMaterial3D).albedo_color.darkened(0.55)
		_accent_material.albedo_color = derived
		_accent_material.emission = derived


func _process(delta: float) -> void:
	if _torso == null or not is_visible_in_tree():
		return
	_time += delta
	_sync_material()
	_compute_targets(delta)
	_apply(delta)
	_torso.global_transform = _spine.global_transform * _torso_offset


# --- state reading -----------------------------------------------------------

func _read_mode() -> Mode:
	if _player:
		match _player.state:
			Player.State.ATTACK:
				return Mode.ATTACK
			Player.State.DODGE:
				return Mode.DODGE
			Player.State.HIT:
				return Mode.HIT
			Player.State.DEAD:
				return Mode.DEAD
	elif _enemy:
		match _enemy.state:
			Enemy.State.ATTACK:
				return Mode.ATTACK
			Enemy.State.STAGGER:
				return Mode.HIT
			Enemy.State.DEAD:
				return Mode.DEAD
	return Mode.NORMAL


# --- pose targets --------------------------------------------------------------

func _compute_targets(delta: float) -> void:
	for i in J.COUNT:
		_target[i] = 0.0
	if _body == null:
		_apply_rate(16.0)
		return

	var mode := _read_mode()
	var velocity := _body.velocity
	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := clampf(speed / 4.5, 0.0, 1.0)
	var run := clampf((speed - 5.5) / 3.0, 0.0, 1.0)
	_phase += delta * (2.5 + speed * 1.3)
	var cycle := sin(_phase)
	var breath := sin(_time * 2.2)
	var guard := _enemy != null and _enemy.state == Enemy.State.CHASE

	if mode != Mode.ATTACK:
		_fallback_frames = 0.0

	match mode:
		Mode.NORMAL:
			if _body.is_on_floor():
				_pose_locomotion(moving, run, cycle, breath, guard)
			else:
				_pose_air(velocity.y)
		Mode.ATTACK:
			_pose_attack(delta)
		Mode.DODGE:
			_target[J.SPINE_X] = -0.85
			_target[J.HEAD_X] = 0.5
			_target[J.LEG_L] = 1.0
			_target[J.LEG_R] = 1.0
			_target[J.ARM_L] = 0.8
			_target[J.ARM_R] = 0.8
			_target[J.FORE_L] = 1.6
			_target[J.FORE_R] = 1.6
			_target[J.BOB] = -0.1
			_apply_rate(22.0)
		Mode.HIT:
			_target[J.SPINE_X] = 0.4
			_target[J.HEAD_X] = 0.2
			_target[J.ARM_L] = 1.5
			_target[J.ARM_R] = 1.5
			_target[J.FORE_L] = 0.7
			_target[J.FORE_R] = 0.7
			_target[J.ARM_L_OUT] = 0.3
			_target[J.ARM_R_OUT] = 0.3
			_target[J.LEG_L] = 0.2
			_target[J.LEG_R] = -0.3
			_apply_rate(24.0)
		Mode.DEAD:
			_target[J.ARM_L] = 0.25
			_target[J.ARM_R] = 0.25
			_target[J.ARM_L_OUT] = 0.9
			_target[J.ARM_R_OUT] = 0.9
			_target[J.LEG_L] = 0.12
			_target[J.LEG_R] = -0.1
			_target[J.HEAD_X] = 0.2
			if _player:
				# Fall over backwards; enemies already tip their whole VisualRoot.
				_target[J.RIG_X] = 1.45
				_target[J.RIG_Y] = 0.08
				_apply_rate(8.0)
			else:
				_apply_rate(10.0)


func _apply_rate(value: float) -> void:
	_rate = value


func _pose_locomotion(moving: float, run: float, cycle: float, breath: float, guard: bool) -> void:
	var swing := 0.75 * moving * (1.0 + 0.25 * run)
	var guard_arm := 0.35 if guard else 0.08
	var guard_fore := 0.9 if guard else 0.1
	var arm_swing := swing * (0.5 if guard else 0.9)
	_target[J.LEG_L] = cycle * swing
	_target[J.LEG_R] = -cycle * swing
	_target[J.ARM_L] = guard_arm - cycle * arm_swing
	_target[J.ARM_R] = guard_arm + cycle * arm_swing
	var elbow := guard_fore + moving * (0.25 + 0.5 * run)
	_target[J.FORE_L] = elbow
	_target[J.FORE_R] = elbow
	_target[J.ARM_L_OUT] = 0.08 + breath * 0.02
	_target[J.ARM_R_OUT] = 0.08 + breath * 0.02
	_target[J.SPINE_X] = -(0.06 * moving + 0.22 * run) + breath * 0.015
	_target[J.HEAD_X] = -_target[J.SPINE_X] * 0.6
	_target[J.BOB] = -absf(cycle) * 0.045 * moving + breath * 0.006
	_apply_rate(16.0)


func _pose_air(vertical_speed: float) -> void:
	_target[J.LEG_L] = 0.6
	_target[J.LEG_R] = -0.35
	_target[J.SPINE_X] = -0.1
	if vertical_speed > 0.0:
		_target[J.ARM_L] = 1.2
		_target[J.ARM_R] = 1.2
		_target[J.ARM_L_OUT] = 0.5
		_target[J.ARM_R_OUT] = 0.5
	else:
		_target[J.ARM_L] = 0.3
		_target[J.ARM_R] = 0.3
		_target[J.ARM_L_OUT] = 0.9
		_target[J.ARM_R_OUT] = 0.9
	_target[J.FORE_L] = 0.4
	_target[J.FORE_R] = 0.4
	_apply_rate(14.0)


func _pose_attack(delta: float) -> void:
	var frames := 0.0
	var startup := 8.0
	var active := 4.0
	var recovery := 10.0
	var data: AttackData = null
	var raw_frames: Variant = _body.get("_attack_frames")
	if _player:
		var idx: Variant = _body.get("_attack_idx")
		var chain: Variant = _body.get("_chain")
		if idx is int and chain is Array and (idx as int) >= 0 and (idx as int) < (chain as Array).size():
			data = (chain as Array)[idx] as AttackData
	else:
		data = _body.get("_swing") as AttackData
	if data and raw_frames is float:
		frames = raw_frames
		startup = float(data.startup_frames)
		active = float(data.active_frames)
		recovery = float(data.recovery_frames)
	else:
		_fallback_frames += delta * 60.0
		frames = _fallback_frames

	var overhead := startup >= 16.0
	var twist := _weapon_pivot.rotation.y * 0.45 if _weapon_pivot else 0.0

	if frames < startup:
		var w := clampf(frames / startup, 0.0, 1.0)
		w = w * w * (3.0 - 2.0 * w)
		_target[J.SPINE_X] = 0.35 * w
		_target[J.SPINE_Y] = twist
		_target[J.HEAD_X] = -0.15 * w
		_target[J.LEG_L] = -0.3 * w
		_target[J.LEG_R] = 0.3 * w
		if overhead:
			_target[J.ARM_L] = lerpf(0.3, 2.9, w)
			_target[J.ARM_R] = lerpf(0.3, 2.9, w)
			_target[J.FORE_L] = 0.5 * w
			_target[J.FORE_R] = 0.5 * w
		else:
			_target[J.ARM_R] = 1.3 * w
			_target[J.ARM_L] = 0.7 * w
			_target[J.FORE_R] = 1.0 * w
			_target[J.FORE_L] = 0.8 * w
			_target[J.ARM_R_OUT] = 0.5 * w
		_apply_rate(22.0)
	elif frames < startup + active:
		_target[J.SPINE_X] = -0.5
		_target[J.SPINE_Y] = twist
		_target[J.LEG_L] = 0.5
		_target[J.LEG_R] = -0.45
		if overhead:
			var w := clampf((frames - startup) / active, 0.0, 1.0)
			_target[J.ARM_L] = lerpf(2.9, 0.4, w)
			_target[J.ARM_R] = lerpf(2.9, 0.4, w)
			_target[J.FORE_L] = 0.2
			_target[J.FORE_R] = 0.2
		else:
			_target[J.ARM_R] = 1.5
			_target[J.ARM_L] = 0.9
			_target[J.FORE_R] = 0.1
			_target[J.FORE_L] = 0.6
		_apply_rate(30.0)
	else:
		var u := clampf((frames - startup - active) / maxf(recovery, 1.0), 0.0, 1.0)
		var k := 1.0 - u
		_target[J.SPINE_X] = -0.3 * k
		_target[J.SPINE_Y] = twist * k
		_target[J.LEG_L] = 0.3 * k
		_target[J.LEG_R] = -0.25 * k
		var arm := (0.5 if overhead else 1.0) * k
		_target[J.ARM_L] = arm
		_target[J.ARM_R] = arm
		_apply_rate(12.0)


# --- applying -----------------------------------------------------------------

func _apply(delta: float) -> void:
	var k := 1.0 - exp(-_rate * delta)
	for i in J.COUNT:
		_current[i] = lerpf(_current[i], _target[i], k)
	_hips.position.y = HIPS_Y + _current[J.BOB]
	_spine.rotation.x = _current[J.SPINE_X]
	_spine.rotation.y = _current[J.SPINE_Y]
	_head.rotation.x = _current[J.HEAD_X]
	_leg_l.rotation.x = _current[J.LEG_L]
	_leg_r.rotation.x = _current[J.LEG_R]
	_arm_l.rotation.x = _current[J.ARM_L]
	_arm_r.rotation.x = _current[J.ARM_R]
	_arm_l.rotation.z = -_current[J.ARM_L_OUT]
	_arm_r.rotation.z = _current[J.ARM_R_OUT]
	_fore_l.rotation.x = _current[J.FORE_L]
	_fore_r.rotation.x = _current[J.FORE_R]
	rotation.x = _current[J.RIG_X]
	position.y = _current[J.RIG_Y]
