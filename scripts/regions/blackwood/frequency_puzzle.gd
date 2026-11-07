class_name FrequencyPuzzle
extends Node3D
## Ghost Frequency: three dials and a transmit lever. The technician's log gives the channel
## (CODE). The rule differs from Outpost 17's ordered switches: it is about matching a number, not an
## order. A wrong transmission only resets the dials (the step), never the quest or the region, and the
## answer is always readable in the log, so no save point can soft-lock it. Solving sets
## `blackwood_comms_power` (a WorldState flag, saved with the world).

signal dial_changed(index: int, value: int)
signal solved
signal failed

const CODE: Array[int] = [4, 1, 7]
const SOLVED_FLAG: StringName = &"blackwood_comms_power"
const DIAL_MAX: int = 9

var dials: Array[int] = [0, 0, 0]
var is_solved: bool = false

var _labels: Array[Label3D] = []
var _lever: Interactable


static func code_text() -> String:
	return "%d-%d-%d" % [CODE[0], CODE[1], CODE[2]]


func _ready() -> void:
	var state := get_node_or_null("/root/WorldState")
	is_solved = state != null and state.has_flag(SOLVED_FLAG)
	_build()
	if is_solved:
		for i in dials.size():
			dials[i] = CODE[i]
		_refresh_labels()


func _build() -> void:
	var panel := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.2, 1.4, 0.4)
	panel.mesh = box
	panel.position = Vector3(0.0, 1.1, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.18, 0.17)
	mat.roughness = 0.8
	panel.material_override = mat
	add_child(panel)
	for i in 3:
		var dial := Interactable.new()
		dial.interaction_id = StringName("bw_dial_%d" % (i + 1))
		dial.prompt_text = "Turn dial %d" % (i + 1)
		dial.interact_radius = 1.6
		dial.position = Vector3(-1.0 + i * 1.0, 1.1, 0.5)
		add_child(dial)
		dial.interacted.connect(_on_dial.bind(i))
		var label := Label3D.new()
		label.text = "0"
		label.font_size = 96
		label.pixel_size = 0.006
		label.modulate = Color(0.5, 1.0, 0.7)
		label.position = Vector3(0.0, 0.0, 0.05)
		label.no_depth_test = false
		dial.add_child(label)
		_labels.append(label)
	_lever = Interactable.new()
	_lever.interaction_id = &"bw_transmit_lever"
	_lever.prompt_text = "Transmit"
	_lever.interact_radius = 1.8
	_lever.position = Vector3(1.9, 0.9, 0.5)
	add_child(_lever)
	_lever.interacted.connect(func(_p: Node3D) -> void: transmit())
	_refresh_labels()


func _on_dial(_player: Node3D, index: int) -> void:
	turn(index)


## Advances one dial 0..9 and wraps. No effect once solved.
func turn(index: int) -> int:
	if is_solved or index < 0 or index >= dials.size():
		return -1
	dials[index] = (dials[index] + 1) % (DIAL_MAX + 1)
	_refresh_labels()
	dial_changed.emit(index, dials[index])
	return dials[index]


## Checks the dials. Right: sets the flag. Wrong: resets only the dials. Returns whether it solved.
func transmit() -> bool:
	if is_solved:
		return true
	for i in dials.size():
		if dials[i] != CODE[i]:
			dials = [0, 0, 0]
			_refresh_labels()
			Outpost17.say(self, "Static. That is not the channel.", 2.5)
			failed.emit()
			return false
	is_solved = true
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(SOLVED_FLAG, true)
	Outpost17.say(self, "The station hums. Power is back.", 3.0)
	solved.emit()
	return true


func capture_state() -> Dictionary:
	return {"dials": dials.duplicate(), "solved": is_solved}


## Hostile or malformed data falls back to a fresh puzzle; a solved flag in the world always wins.
func restore_state(data: Variant) -> void:
	var state := get_node_or_null("/root/WorldState")
	var flagged: bool = state != null and state.has_flag(SOLVED_FLAG)
	dials = [0, 0, 0]
	if data is Dictionary:
		var raw: Variant = (data as Dictionary).get("dials")
		if raw is Array and (raw as Array).size() == 3:
			for i in 3:
				var v: Variant = (raw as Array)[i]
				if v is int or v is float:
					dials[i] = clampi(int(v), 0, DIAL_MAX)
	is_solved = flagged
	if is_solved:
		for i in 3:
			dials[i] = CODE[i]
	_refresh_labels()


func _refresh_labels() -> void:
	for i in _labels.size():
		_labels[i].text = str(dials[i])
