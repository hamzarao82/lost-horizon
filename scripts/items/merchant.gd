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
	data = load(merchant_path) as MerchantData
	if data:
		interaction_id = StringName("merchant_" + String(data.merchant_id))


func _on_interact(player: Node3D) -> void:
	if data:
		trade_requested.emit(data, player)
		open_requested.emit(data)
