class_name KeyBindings
extends RefCounted
## Player-rebindable keyboard/mouse bindings. Only the keyboard and mouse events of an action are touched;
## joypad events (GamepadBindings) and touch controls are left alone. Pause (Escape) is not rebindable:
## Escape is also the "cancel capture" key.

const RESERVED_KEYCODE: int = KEY_ESCAPE
const CONFIG_SECTION: String = "bindings"

## [action, label] in the order the panel lists them.
const ACTIONS: Array = [
	[&"move_forward", "Move forward"], [&"move_backward", "Move backward"],
	[&"move_left", "Move left"], [&"move_right", "Move right"],
	[&"jump", "Jump"], [&"sprint", "Sprint"], [&"dodge", "Dodge"], [&"interact", "Interact"],
	[&"attack_light", "Light attack"], [&"attack_heavy", "Heavy attack"], [&"special", "Special attack"],
	[&"lock_on", "Lock on"], [&"target_next", "Next target"], [&"target_prev", "Previous target"],
	[&"use_item", "Use medkit"], [&"teleport", "Teleport"], [&"equipment", "Equipment screen"],
]

static var _defaults: Dictionary = {}  # action -> Array[InputEvent] (keyboard/mouse only)


static func rebindable_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry: Array in ACTIONS:
		if InputMap.has_action(entry[0]):
			out.append(entry[0])
	return out


## Remember the project's original keyboard/mouse events. Safe to call repeatedly; only the first call records.
static func capture_defaults() -> void:
	if not _defaults.is_empty():
		return
	for action in rebindable_actions():
		_defaults[action] = _kb_events(action)


static func is_bindable(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return _code(key) != 0 and _code(key) != RESERVED_KEYCODE
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).button_index > 0
	return false


static func describe(event: InputEvent) -> String:
	if event == null:
		return "Unbound"
	if event is InputEventKey:
		return (event as InputEventKey).as_text_physical_keycode()
	if event is InputEventMouseButton:
		return "Mouse %d" % (event as InputEventMouseButton).button_index
	return event.as_text()


## The first keyboard/mouse event of an action (its "primary" binding), or null.
static func primary(action: StringName) -> InputEvent:
	var events := _kb_events(action)
	return null if events.is_empty() else events[0]


## Rebind `action`'s primary to `event`. Any other rebindable action already using that input swaps:
## it takes this action's old primary. Returns {"ok": bool, "swapped": StringName (or &"")}.
static func rebind(action: StringName, event: InputEvent) -> Dictionary:
	capture_defaults()
	if not rebindable_actions().has(action) or not is_bindable(event):
		return {"ok": false, "swapped": &""}
	var old := primary(action)
	var swapped: StringName = &""
	for other in rebindable_actions():
		if other == action:
			continue
		var events := _kb_events(other)
		for i in events.size():
			if _same(events[i], event):
				if old == null:
					events.remove_at(i)
				else:
					events[i] = old
				_write(other, events)
				swapped = other
				break
	var mine := _kb_events(action)
	var kept: Array[InputEvent] = []
	for e in mine.slice(1):
		if not _same(e, event):
			kept.append(e)
	var fresh: InputEvent = event.duplicate()
	_clear_state(fresh)
	_write(action, _prepend(fresh, kept))
	return {"ok": true, "swapped": swapped}


static func reset_all() -> void:
	capture_defaults()
	for action in rebindable_actions():
		_write(action, _defaults[action])


static func is_default() -> bool:
	return to_config().is_empty()


## action -> "k65,m1" for every action whose keyboard/mouse events differ from the project defaults.
static func to_config() -> Dictionary:
	capture_defaults()
	var out := {}
	for action in rebindable_actions():
		var now := _encode(_kb_events(action))
		if now != _encode(_defaults[action]):
			out[String(action)] = now
	return out


## Apply a saved config. Anything malformed, reserved, unknown, or leaving two actions on the same
## input rejects the WHOLE config and the defaults stay in force. Returns true when applied.
static func apply_config(data: Variant) -> bool:
	capture_defaults()
	if not (data is Dictionary):
		return false
	var parsed := {}
	for key in (data as Dictionary):
		if not (key is String) or not rebindable_actions().has(StringName(key)):
			return false
		var events := _decode((data as Dictionary)[key])
		if events.is_empty():
			return false
		parsed[StringName(key)] = events
	var plan := {}
	for action in rebindable_actions():
		plan[action] = parsed.get(action, _defaults[action])
	var actions: Array = plan.keys()
	for i in actions.size():
		for j in range(i + 1, actions.size()):
			if not (parsed.has(actions[i]) or parsed.has(actions[j])):
				continue
			for a: InputEvent in plan[actions[i]]:
				for b: InputEvent in plan[actions[j]]:
					if _same(a, b) and not (_default_has(actions[i], a) and _default_has(actions[j], b)):
						return false
	for action in plan:
		_write(action, plan[action])
	return true


static func _default_has(action: StringName, event: InputEvent) -> bool:
	for e: InputEvent in _defaults.get(action, []):
		if _same(e, event):
			return true
	return false


static func _prepend(first: InputEvent, rest: Array[InputEvent]) -> Array[InputEvent]:
	var out: Array[InputEvent] = [first]
	out.append_array(rest)
	return out


static func _kb_events(action: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			out.append(e)
	return out


## Replace only the keyboard/mouse events, keeping the joypad events in place.
static func _write(action: StringName, kb_events: Array) -> void:
	var others: Array[InputEvent] = []
	for e in InputMap.action_get_events(action):
		if not (e is InputEventKey or e is InputEventMouseButton):
			others.append(e)
	InputMap.action_erase_events(action)
	for e: InputEvent in kb_events:
		InputMap.action_add_event(action, e)
	for e in others:
		InputMap.action_add_event(action, e)


static func _code(key: InputEventKey) -> int:
	return key.physical_keycode if key.physical_keycode != 0 else key.keycode


static func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		return _code(ka) == _code(kb) and ka.ctrl_pressed == kb.ctrl_pressed \
				and ka.shift_pressed == kb.shift_pressed and ka.alt_pressed == kb.alt_pressed
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


static func _clear_state(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		key.pressed = false
		key.echo = false
		if key.physical_keycode == 0:
			key.physical_keycode = key.keycode
		key.keycode = 0
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		mouse.pressed = false
		mouse.double_click = false


static func _encode(events: Array) -> String:
	var parts: PackedStringArray = []
	for e: InputEvent in events:
		if e is InputEventKey:
			parts.append("k%d" % _code(e as InputEventKey))
		elif e is InputEventMouseButton:
			parts.append("m%d" % (e as InputEventMouseButton).button_index)
	return ",".join(parts)


static func _decode(value: Variant) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not (value is String):
		return out
	for token in (value as String).split(","):
		if token.length() < 2 or not token.substr(1).is_valid_int():
			return [] as Array[InputEvent]
		var number := token.substr(1).to_int()
		var event: InputEvent
		if token[0] == "k":
			var key := InputEventKey.new()
			key.physical_keycode = number as Key
			event = key
		elif token[0] == "m":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = number as MouseButton
			event = mouse
		else:
			return [] as Array[InputEvent]
		if not is_bindable(event):
			return [] as Array[InputEvent]
		out.append(event)
	return out
