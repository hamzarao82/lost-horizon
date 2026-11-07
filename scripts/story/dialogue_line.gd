class_name DialogueLine
extends Resource
## One spoken or radioed line. `cue` is an existing AudioManager sound name played when the line starts.

@export var speaker: String = ""
@export_multiline var text: String = ""
@export var seconds: float = 4.0
@export var cue: StringName = &""
