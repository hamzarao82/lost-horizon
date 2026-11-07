class_name DialogueSequence
extends Resource
## An ordered conversation. `once` sequences play a single time per save (flag `dlg_<id>`).

@export var id: StringName
@export var lines: Array[DialogueLine] = []
@export var once: bool = true
