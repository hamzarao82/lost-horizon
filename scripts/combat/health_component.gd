class_name HealthComponent
extends Node

signal changed(current: float, maximum: float)
signal damaged(amount: float)
signal died

@export var max_health: float = 100.0

var health: float


func _ready() -> void:
	health = max_health


func take_damage(amount: float) -> void:
	if health <= 0.0 or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	damaged.emit(amount)
	changed.emit(health, max_health)
	if health <= 0.0:
		died.emit()


func is_dead() -> bool:
	return health <= 0.0
