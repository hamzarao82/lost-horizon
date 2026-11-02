class_name BossIntro
extends Node
## The Warden encounter in Area D (Command Center). Uses the existing Warden scene, so every pattern,
## phase and loot rule is exactly the one from the arena; this only adds the introduction, the sealed
## door and the victory handling. The Warden also stays wave 5 in the courtyard (Arena Mode).
##
## Flags (WorldState): `warden_intro_done` (the full intro ran once), `boss_warden_defeated` (ANY
## Warden died, including the wave-5 one), `warden_d_defeated` (the Area D fight was won).

const WARDEN_SCENE: String = "res://scenes/enemies/Warden.tscn"

@export var area_id: StringName = &"area_d_command"
@export var spawn_position: Vector3 = Vector3(0.0, 0.1, -75.0)  # centre of the command building
## Collider that seals the doorway behind the player (the C-D door sits at z = -62).
@export var seal_position: Vector3 = Vector3(0.0, 0.0, -62.6)
@export var seal_size: Vector3 = Vector3(4.6, 4.0, 0.8)
@export var intro_seconds: float = 3.0
@export var quick_intro_seconds: float = 1.2  # used when the player returns after dying

var warden: Enemy
var seal: StaticBody3D

var _state: Node
var _running: bool = false
var _check_time: float = 0.0


func _ready() -> void:
	_state = get_node_or_null("/root/WorldState")
	get_tree().node_added.connect(_on_node_added)
	if _state:
		_state.area_entered.connect(_on_area_entered)


## Safety net: the player must never stay sealed in. If the Warden is gone or dead, open the door.
func _process(delta: float) -> void:
	if seal == null:
		return
	_check_time += delta
	if _check_time < 0.5:
		return
	_check_time = 0.0
	if warden == null or not is_instance_valid(warden) or warden.is_dead():
		_release_seal()


func _on_node_added(node: Node) -> void:
	var any_warden := node as Warden
	if any_warden != null:
		any_warden.defeated.connect(_on_any_warden_defeated.bind(any_warden))


func _on_area_entered(id: StringName) -> void:
	if id != area_id or _running or _state == null:
		return
	if _state.has_flag(&"boss_warden_defeated"):
		_say_later("The Warden is gone. Only his command room remains.", 3.5)
		return
	if warden != null and is_instance_valid(warden) and not warden.is_dead():
		return  # already fighting him
	_run_encounter()


func _run_encounter() -> void:
	_running = true
	var quick: bool = _state.has_flag(&"warden_intro_done")
	_make_seal()
	if not quick:
		_say_later("The Warden: This is as far as you go.", 3.0)
	var scene := load(WARDEN_SCENE) as PackedScene
	var host := get_parent().get_parent() if get_parent() else null
	if scene == null or host == null:
		_release_seal()
		_running = false
		return
	var boss := scene.instantiate() as Enemy
	boss.position = spawn_position  # set before add_child: never overlaps the player for a frame
	host.add_child(boss)
	boss.set_physics_process(false)  # stands still during the introduction
	warden = boss
	var camera := get_tree().get_first_node_in_group("camera_controller")
	if camera and camera.has_method("set_lock_target"):
		camera.call("set_lock_target", boss)
	await get_tree().create_timer(quick_intro_seconds if quick else intro_seconds).timeout
	if camera and is_instance_valid(camera) and camera.has_method("clear_lock_target"):
		camera.call("clear_lock_target")
	if is_instance_valid(boss) and not boss.is_dead():
		boss.set_physics_process(true)
		boss.aggro()
	_state.set_flag(&"warden_intro_done", true)
	_running = false


func _on_any_warden_defeated(which: Warden) -> void:
	if _state == null:
		return
	_state.set_flag(&"boss_warden_defeated", true)
	if which == warden:
		_state.set_flag(&"warden_d_defeated", true)
		_release_seal()
		Outpost17.say(self, "The Warden falls.", 3.5)


func _make_seal() -> void:
	if seal != null and is_instance_valid(seal):
		return
	seal = StaticBody3D.new()
	seal.name = "BossSeal"
	seal.position = seal_position
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = seal_size
	shape.shape = box
	shape.position = Vector3(0.0, seal_size.y * 0.5, 0.0)
	seal.add_child(shape)
	var leaf := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(seal_size.x - 0.2, seal_size.y - 0.3, 0.25)
	leaf.mesh = mesh
	leaf.position = Vector3(0.0, seal_size.y * 0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.1, 0.08)
	leaf.material_override = material
	leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seal.add_child(leaf)
	add_child(seal)


func _release_seal() -> void:
	if seal != null and is_instance_valid(seal):
		seal.queue_free()
	seal = null


## Captions wait until the "Command Center" location banner has faded, so the two never overlap.
const CAPTION_DELAY: float = 2.7


func _say_later(text: String, seconds: float) -> void:
	get_tree().create_timer(CAPTION_DELAY).timeout.connect(func() -> void:
		if is_inside_tree():
			Outpost17.say(self, text, seconds))
