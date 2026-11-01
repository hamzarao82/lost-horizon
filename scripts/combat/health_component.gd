class_name HealthComponent
extends Node
## Health plus an optional armor pool. Armor is a second bar: all incoming damage drains it first,
## and only the overflow reaches health.

signal changed(current: float, maximum: float)
signal armor_changed(current: float, maximum: float)
signal damaged(amount: float)
signal died

@export var max_health: float = 100.0

var health: float
var armor: float = 0.0
var max_armor: float = 0.0


func _ready() -> void:
	health = max_health


## Resize the armor bar. Pass a negative `current` to fill it completely.
func set_armor(new_max: float, current: float = -1.0) -> void:
	max_armor = maxf(new_max, 0.0)
	armor = max_armor if current < 0.0 else clampf(current, 0.0, max_armor)
	armor_changed.emit(armor, max_armor)


## Returns false (and does nothing) when there is nothing to restore.
func restore_armor(amount: float) -> bool:
	if amount <= 0.0 or max_armor <= 0.0 or armor >= max_armor:
		return false
	armor = minf(armor + amount, max_armor)
	armor_changed.emit(armor, max_armor)
	return true


## `damaged` reports the full incoming amount (used for damage numbers), even if armor absorbed it all.
func take_damage(amount: float) -> void:
	if health <= 0.0 or amount <= 0.0:
		return
	var remaining := amount
	if armor > 0.0:
		var absorbed := minf(armor, remaining)
		armor -= absorbed
		remaining -= absorbed
		armor_changed.emit(armor, max_armor)
	damaged.emit(amount)
	if remaining <= 0.0:
		return
	health = maxf(health - remaining, 0.0)
	changed.emit(health, max_health)
	if health <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	if health <= 0.0 or amount <= 0.0:
		return
	health = minf(health + amount, max_health)
	changed.emit(health, max_health)


func is_dead() -> bool:
	return health <= 0.0
