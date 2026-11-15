extends SceneTree
## Windowed menu capture and measurement (not headless):
##   godot --path . --resolution 1280x720 -s tools/menu_shot.gd -- <out.png> [hero|nohero]
## Saves one frame after the model has had time to start, and prints average frame time and draw calls over 3 s.

var _out: String = "user://menu.png"
var _hero: bool = true


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_hero = args[1] != "nohero"
	_run.call_deferred()


func _run() -> void:
	var menu := MainMenu.new()
	root.add_child(menu)
	if not _hero and menu.hero != null:
		menu.hero.free()
		menu.hero = null
	for i in 90:
		await process_frame
	var t0 := Time.get_ticks_usec()
	var frames := 180
	var calls := 0
	for i in frames:
		await process_frame
		calls += int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var avg_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
	print("MENU hero=%s window=%s avg_frame_ms=%.2f avg_draw_calls=%.1f hero_active=%s" % [
		str(_hero), str(root.size), avg_ms, float(calls) / float(frames), str(menu.hero.active if menu.hero else false)])
	var img := root.get_texture().get_image()
	img.save_png(_out)
	print("saved ", _out, " ", img.get_size())
	quit()
