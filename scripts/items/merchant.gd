class_name MerchantNpc
extends Interactable
## A reusable vendor you can walk up to and press the interact key on. The trading screen is separate:
## this node only identifies the vendor and announces that the player wants to trade.

signal trade_requested(merchant: MerchantData, player: Node3D)
## The trading screen listens to this one: it carries only the vendor data.
signal open_requested(merchant_data: MerchantData)


@export var merchant_path: String = "res://resources/merchants/outpost_quartermaster.tres"

var data: MerchantData


func _ready() -> void:
	super._ready()
	if prompt_text == "Use":
		prompt_text = "Trade"
	_build_keeper()
	data = load(merchant_path) as MerchantData
	if data:
		interaction_id = StringName("merchant_" + String(data.merchant_id))


func _on_interact(player: Node3D) -> void:
	if data:
		trade_requested.emit(data, player)
		open_requested.emit(data)


## Visual only: the existing soldier rig in an idle stance behind the stall, wearing the helmet model,
## facing the side the player arrives from. Interaction is unchanged.
const KEEPER_MODEL: String = "res://assets/characters/soldier.glb"
const KEEPER_HELMET: String = "res://assets/armor/combat_helmet.glb"
const KEEPER_OFFSET: Vector3 = Vector3(0.0, 0.0, -1.0)

var keeper: Node3D


func _build_keeper() -> void:
	if keeper != null or not ResourceLoader.exists(KEEPER_MODEL):
		return
	var scene := load(KEEPER_MODEL) as PackedScene
	keeper = scene.instantiate() as Node3D if scene else null
	if keeper == null:
		return
	keeper.name = "Quartermaster"
	keeper.position = KEEPER_OFFSET
	keeper.rotation.y = PI  # models face -Z; the player walks in from +Z
	add_child(keeper)
	for node in keeper.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			var material := mi.get_active_material(surface) as BaseMaterial3D
			if material:
				material.vertex_color_use_as_albedo = true  # the art contract colours with vertices (as SkinnedVisual does)
	var players := keeper.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var anim := players[0] as AnimationPlayer
		for clip in anim.get_animation_list():
			if String(clip).to_lower().contains("idle"):
				var animation := anim.get_animation(clip)
				if animation:
					animation.loop_mode = Animation.LOOP_LINEAR
				anim.play(clip)
				break
	var skeletons := keeper.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty() and ResourceLoader.exists(KEEPER_HELMET):
		var socket := WeaponSocket.attach(skeletons[0] as Skeleton3D, &"Head", "KeeperHelmet")
		if socket:
			var helmet := load(KEEPER_HELMET) as PackedScene
			socket.hold(helmet.instantiate() as Node3D if helmet else null)
