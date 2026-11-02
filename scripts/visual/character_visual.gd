class_name CharacterVisual
extends Node3D
## Base class of everything that draws a character. Gameplay never calls into a visual: the visual
## polls the body (state, velocity, attack frames) and only ever changes how things LOOK.
## Implementations: ProceduralVisual (today's code-built rig, always available as fallback) and
## SkinnedVisual (an imported GLB with a skeleton and clips).

## The CharacterBody3D (Player or Enemy) being drawn.
var body: CharacterBody3D


func bind(new_body: CharacterBody3D) -> void:
	body = new_body


## Per-frame refresh. Implementations poll the body here.
func update(_delta: float) -> void:
	pass


## Tint the whole character (hit flash, telegraph, death). `strength` 0 removes the tint.
func set_flash_color(_color: Color, _strength: float) -> void:
	pass


## Show the weapon with this item id in the character's hand (&"" = whatever is equipped).
func set_weapon(_item_id: StringName) -> void:
	pass


func has_clip(_clip_name: String) -> bool:
	return false


func is_skinned() -> bool:
	return false


## Whether this visual is the one currently shown.
func set_active(_active: bool) -> void:
	pass
