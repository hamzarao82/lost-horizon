extends SceneTree
## The Skip buttons of the opening cinematic, the beach scene and the old title intro must sit fully inside the
## viewport, 16 px from the bottom-right corner (a web screenshot showed one clipped at the right edge).
##   godot --headless --path . -s tests/skip_button_check.gd

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	HitStop.enabled = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _button_of(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == "Skip":
			return child as Button
	return null


func _run() -> void:
	var view := Vector2(root.get_visible_rect().size)
	_check(view.x >= 800.0 and view.y >= 360.0, "the test viewport is a sane size (%s)" % str(view))
	var makers := {
		"OpeningCinematic": func() -> Node: return OpeningCinematic.new(),
		"OpeningBeach": func() -> Node: return OpeningBeach.new(),
		"StoryIntro": func() -> Node: return StoryIntro.new(),
	}
	for label in makers:
		var node: Node = (makers[label] as Callable).call()
		root.add_child(node)
		await _frames(4)
		var button := _button_of(node)
		_check(button != null, "%s has a Skip button" % label)
		if button != null:
			var rect := button.get_global_rect()
			_check(rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= view.x + 0.5 and rect.end.y <= view.y + 0.5,
					"%s: the Skip button is fully on screen (%s in %s)" % [label, str(rect), str(view)])
			_check(absf((view.x - rect.end.x) - 16.0) < 1.5 and absf((view.y - rect.end.y) - 16.0) < 1.5,
					"%s: it sits 16 px from the bottom-right corner" % label)
		node.queue_free()
		await _frames(2)
		paused = false
	print("skip_button_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
