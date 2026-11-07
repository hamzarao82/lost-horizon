class_name ContainmentOverride
extends MultiStepPuzzle
## Puzzle C (containment sector): three terminals must all be switched on within a window after the first
## one (45 s). If the window runs out, only the unfinished window resets: the terminals switched in it turn
## off again, and nothing already completed is touched. Then a lockdown release lever finishes the puzzle.
## Steps: `terminals` then `release`. The window itself is not saved: after a reload it simply starts fresh.

signal window_changed

const TERMINALS: Array[StringName] = [&"a", &"b", &"c"]

@export var window_seconds: float = 45.0

var active: Dictionary = {}
var window_left: float = 0.0


func _init() -> void:
	puzzle_id = &"containment"
	steps = [&"terminals", &"release"]
	ordered = true


func _ready() -> void:
	super._ready()
	set_process(false)


func input(id: StringName) -> void:
	var s := String(id)
	if s.begins_with("terminal_"):
		activate_terminal(StringName(s.substr(9)))
	elif id == &"lever":
		release()


func activate_terminal(terminal: StringName) -> bool:
	if is_step_done(&"terminals") or not TERMINALS.has(terminal) or active.has(terminal):
		return false
	if active.is_empty():
		window_left = window_seconds
		set_process(true)
	active[terminal] = true
	window_changed.emit()
	if active.size() == TERMINALS.size():
		window_left = 0.0
		set_process(false)
		complete_step(&"terminals")
	return true


func _process(delta: float) -> void:
	advance(delta)


## Runs the window clock (called every frame while a window is open; tests call it directly).
func advance(delta: float) -> void:
	if window_left <= 0.0 or is_step_done(&"terminals"):
		return
	window_left -= delta
	if window_left <= 0.0:
		fail(&"terminals", "window_expired")


func release() -> bool:
	if is_completed():
		return false
	if not is_step_done(&"terminals"):
		step_failed.emit(&"release", "terminals_offline")  # a caption, no punishment
		return false
	return complete_step(&"release")


func _reset_current(step: StringName) -> void:
	if step == &"terminals":
		active.clear()
		window_left = 0.0
		set_process(false)
		window_changed.emit()


func _after_restore() -> void:
	active.clear()
	window_left = 0.0
	if is_step_done(&"terminals"):
		for t in TERMINALS:
			active[t] = true
	window_changed.emit()


## 0 locked and idle, 1 window open, 2 terminals done, 3 released.
func status() -> int:
	if is_completed():
		return 3
	if is_step_done(&"terminals"):
		return 2
	return 1 if window_left > 0.0 else 0
