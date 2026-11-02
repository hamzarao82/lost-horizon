extends SceneTree
## Layout checks for the HUD:
##   godot --headless --path . -s tests/ui_layout_check.gd
## Headless text metrics are unreliable, so overlap checks use Hud.plan_layout (the same rectangles
## the HUD positions its widgets from) and the real touch-button circles. Windowed screenshots are
## taken separately (docs/UI_LAYOUT.md).

const SIZES: Array[Vector2] = [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 2844)]
const BUTTON_RADIUS: float = 44.0

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
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
		await physics_frame


func _run() -> void:
	_test_plan_overlaps()
	_test_touch_buttons()
	_test_captions()
	await _test_banners_and_cuts()
	await _test_labels()
	await _test_widgets()
	_test_icons_and_theme()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _circle_hits_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var nearest := Vector2(clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y))
	return nearest.distance_to(center) < radius


func _test_plan_overlaps() -> void:
	print("Layout plan: no widget overlaps another")
	for viewport in SIZES:
		for touch in [false, true]:
			var plan: Dictionary = Hud.plan_layout(viewport, touch)
			var names: Array = plan.keys()
			var clashes: Array[String] = []
			for i in names.size():
				for j in range(i + 1, names.size()):
					var a: Rect2 = plan[names[i]]
					var b: Rect2 = plan[names[j]]
					if a.intersects(b):
						clashes.append("%s x %s" % [names[i], names[j]])
			_check(clashes.is_empty(), "%dx%d touch=%s: %d widgets, no overlaps %s" % [
				viewport.x, viewport.y, touch, names.size(), "" if clashes.is_empty() else str(clashes)])
			var inside := true
			for key in names:
				var rect: Rect2 = plan[key]
				if rect.position.x < 0.0 or rect.position.y < 0.0 or rect.end.x > viewport.x or rect.end.y > viewport.y:
					inside = false
			_check(inside, "%dx%d touch=%s: every widget is on screen" % [viewport.x, viewport.y, touch])


func _test_touch_buttons() -> void:
	print("Layout plan: HUD clears the touch buttons")
	for viewport in SIZES:
		var centers: Array[Vector2] = []
		for button in TouchControls.BUTTONS:
			centers.append(viewport + (button["offset"] as Vector2))
		var all_inside := true
		for center in centers:
			if center.x - BUTTON_RADIUS < 0.0 or center.y - BUTTON_RADIUS < 0.0 \
					or center.x + BUTTON_RADIUS > viewport.x or center.y + BUTTON_RADIUS > viewport.y:
				all_inside = false
		_check(all_inside, "%dx%d: all %d touch buttons are on screen" % [viewport.x, viewport.y, centers.size()])
		var apart := true
		for i in centers.size():
			for j in range(i + 1, centers.size()):
				if centers[i].distance_to(centers[j]) < BUTTON_RADIUS * 2.0:
					apart = false
		_check(apart, "%dx%d: touch buttons do not overlap each other" % [viewport.x, viewport.y])
		var plan: Dictionary = Hud.plan_layout(viewport, true)
		var clashes: Array[String] = []
		for key in plan.keys():
			for center in centers:
				if _circle_hits_rect(center, BUTTON_RADIUS, plan[key]):
					clashes.append(str(key))
		_check(clashes.is_empty(), "%dx%d: no HUD widget sits under a touch button %s" % [
			viewport.x, viewport.y, "" if clashes.is_empty() else str(clashes)])


func _test_captions() -> void:
	print("Captions")
	var long_text := "Find the generator switches and bring the outpost back online. I will guide you from here, " \
			+ "but you must hurry, because the patrols will find you soon and the whole island is watching."
	var pieces := Hud.split_caption(long_text)
	var all_short := true
	for piece in pieces:
		if piece.length() > Hud.CAPTION_MAX_CHARS:
			all_short = false
	_check(pieces.size() >= 2 and all_short, "long text splits into pieces that fit two lines (%d pieces)" % pieces.size())
	_check(" ".join(pieces).replace("  ", " ") == long_text, "splitting loses no text")
	_check(Hud.split_caption("Short.").size() == 1, "short text stays one piece")
	_check(is_equal_approx(Hud.caption_seconds_for("Hi"), Hud.CAPTION_MIN_SECONDS), "tiny captions stay at least 3 s")
	_check(is_equal_approx(Hud.caption_seconds_for(long_text), Hud.CAPTION_MAX_SECONDS), "long captions are capped at 6 s")
	_check(Hud.caption_seconds_for("A medium length radio line to read.") > Hud.caption_seconds_for("Short."),
			"reading time grows with text length")


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	var wm := main.get_node_or_null("WaveManager")
	if wm:
		wm.autostart = false
	root.add_child(main)
	await _frames(3)
	return main


func _spawn_enemy(main: Node, path: String, pos: Vector3) -> Enemy:
	var enemy := (load(path) as PackedScene).instantiate() as Enemy
	enemy.position = pos
	main.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


func _test_banners_and_cuts() -> void:
	print("Banners and caption cuts")
	var main := await _spawn_main()
	var hud := main.get_node("Hud") as Hud
	for i in 6:
		hud.show_caption("Radio line %d of the transmission." % i)
	_check(hud._caption_queue.size() <= Hud.MAX_QUEUED_CAPTIONS, "caption queue never holds more than 3 waiting (%d)" % hud._caption_queue.size())
	hud._caption_queue.clear()
	hud.show_caption("flash", 1.5)
	hud.show_caption("A normal radio line asked for the usual four seconds.", 4.0)
	_check(is_equal_approx(float(hud._caption_queue[0]["seconds"]), 1.5), "an explicit sub-3 s request is honored exactly")
	_check(float(hud._caption_queue[1]["seconds"]) >= Hud.CAPTION_MIN_SECONDS, "a normal request uses the reading time (at least 3 s)")
	hud._caption_queue.clear()
	hud._on_wave_started(2, 5)
	_check(hud._caption_queue.is_empty(), "a wave start drops the queued captions")
	hud._subtitle_time = 5.0
	hud._on_wave_started(3, 5)
	_check(hud._subtitle_time <= 0.9, "a wave start fades the caption on screen")

	hud._banner_queue.clear()
	hud._banner_time = 0.0
	hud._on_wave_started(1, 5)
	hud._queue_banner("QUEST COMPLETE", Color.WHITE)
	_check(hud._banner_queue.size() == 2, "wave and quest banners queue instead of stacking")
	hud._process(0.016)
	_check(hud._banner.text == "WAVE 1" and hud._banner.visible, "the first banner shows alone")
	_check(hud._banner_queue.size() == 1, "the second banner waits for the first")
	hud._process(Hud.BANNER_SECONDS + 0.1)
	hud._process(0.016)
	_check(hud._banner.text == "QUEST COMPLETE", "the queued banner shows after the first ends")
	for i in 6:
		hud._queue_banner("B%d" % i, Color.WHITE)
	_check(hud._banner_queue.size() <= Hud.MAX_QUEUED_BANNERS, "banner queue is capped at 3")
	_check(hud._banner.position.y >= 98.0 and hud._banner.position.y < 160.0, "banner sits in the upper band, below the boss bar")
	main.queue_free()
	await _frames(3)


func _test_labels() -> void:
	print("Enemy and pickup labels")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var hud := main.get_node("Hud") as Hud
	var enemies: Array[Enemy] = []
	for i in 4:
		enemies.append(_spawn_enemy(main, "res://scenes/enemies/PatrolSoldier.tscn", player.global_position + Vector3(3.0 + i, 0, -2.0 - i * 0.5)))
	var far := _spawn_enemy(main, "res://scenes/enemies/PatrolSoldier.tscn", player.global_position + Vector3(0, 0, -22.0))
	await _frames(2)
	hud._update_enemy_labels()
	var shown := 0
	for enemy in enemies:
		if (enemy.get_node("HealthLabel") as Label3D).visible:
			shown += 1
	_check(shown == Hud.MAX_ENEMY_LABELS, "only the %d nearest enemies show a label (%d shown of 4)" % [Hud.MAX_ENEMY_LABELS, shown])
	_check((enemies[0].get_node("HealthLabel") as Label3D).visible, "the nearest enemy shows its label")
	_check(not (far.get_node("HealthLabel") as Label3D).visible, "a far enemy hides its label")
	var label := enemies[0].get_node("HealthLabel") as Label3D
	_check(label.modulate.a > 0.0 and label.modulate.a <= 1.0, "label alpha is a valid fade value")

	var warden := _spawn_enemy(main, "res://scenes/enemies/Warden.tscn", player.global_position + Vector3(0, 0, -4.0))
	await _frames(2)
	hud._update_enemy_labels()
	_check(not (warden.get_node("HealthLabel") as Label3D).visible, "the boss uses the boss bar, not a floating label")

	var kill := load("res://resources/attacks/heavy_1.tres") as AttackData
	for i in 3:
		enemies[0].receive_hit(kill, player.global_position)
	await _frames(2)
	hud._update_enemy_labels()
	_check((enemies[1].get_node("HealthLabel") as Label3D).visible, "when the nearest dies the next nearest takes its label")

	var item := load("res://resources/items/combat_knife.tres") as ItemData
	var pickups: Array[Pickup] = []
	for i in 6:
		pickups.append(Pickup.spawn(main, item, player.global_position + Vector3(1.0 + i * 0.5, 0, 1.0)))
	await _frames(3)
	for pickup in pickups:
		pickup._label_clock = 1.0
		pickup._update_label(0.0)
	var labels_on := 0
	for pickup in pickups:
		if (pickup.get_node("Label3D") as Label3D).visible:
			labels_on += 1
	_check(labels_on <= Pickup.LABEL_MAX_SHOWN, "a pile of drops shows at most %d labels (%d shown)" % [Pickup.LABEL_MAX_SHOWN, labels_on])
	var scale_ok := true
	for pickup in pickups:
		var s := (pickup.get_node("Label3D") as Label3D).scale.x
		if s < Pickup.LABEL_SCALE_MIN - 0.001 or s > Pickup.LABEL_SCALE_MAX + 0.001:
			scale_ok = false
	_check(scale_ok, "pickup label scale stays within %.1f-%.1f" % [Pickup.LABEL_SCALE_MIN, Pickup.LABEL_SCALE_MAX])
	main.queue_free()
	await _frames(3)


## Draws every icon kind inside a real _draw() call, so a bad draw call shows up as an engine error here.
class IconProbe extends Control:
	var drawn: bool = false

	func _draw() -> void:
		var x := 0.0
		for kind in HudIcons.KINDS:
			HudIcons.draw(self, StringName(kind), Rect2(x, 0.0, 32.0, 32.0), Color.WHITE)
			x += 36.0
		drawn = true


func _test_widgets() -> void:
	print("HUD bars, equipment and teleport widgets")
	var main := await _spawn_main()
	var hud := main.get_node("Hud") as Hud

	var bar := HudBar.new()
	bar.size = Vector2(240, 18)
	hud.add_child(bar)
	bar.max_value = 60.0
	bar.value = 60.0
	_check(is_equal_approx(bar.displayed_value(), 60.0), "the first value snaps (a bar never animates up from zero at startup)")
	bar.value = 20.0
	_check(is_equal_approx(bar.displayed_value(), 60.0), "a later change does not jump: the fill eases toward it")
	await create_timer(1.2).timeout
	_check(is_equal_approx(bar.displayed_value(), 20.0), "the fill settles on the new value")
	bar.value = 500.0
	_check(is_equal_approx(bar.value, 60.0), "a value above the maximum is clamped")
	bar.queue_free()

	var teleport := HudTeleport.new()
	teleport.size = Vector2(HudTeleport.WIDTH, 28)
	hud.add_child(teleport)
	teleport.set_state(2, 2, 0.0)
	_check(teleport.time_text() == "READY", "two charges read READY")
	teleport.set_state(1, 2, 61.2)
	_check(teleport.time_text() == "01:02", "recharge time is mm:ss rounded up (%s)" % teleport.time_text())
	teleport.set_state(0, 2, 600.0)
	_check(teleport.time_text() == "10:00", "a full ten-minute wait reads 10:00")
	teleport.queue_free()

	var equipment := hud._equipment
	equipment.set_data("Claymore", Color.PURPLE, "x2.10 dmg  0.85x spd", "Warden Plate", "140/140", Color.ORANGE, 3)
	await _frames(2)
	_check(equipment.weapon_name == "Claymore" and equipment.potions == 3 and equipment.armor_points == "140/140",
			"the equipment panel keeps weapon, modifier, armor points and medkits")

	# Text backdrops follow their labels and hide when the label is empty.
	hud._show_toast("Picked up Medkit", Color.WHITE)
	hud._sync_backdrops()
	var toast_panel: Panel = hud._backdrops[1]["panel"]
	_check(toast_panel.visible and toast_panel.size.x > 20.0, "a visible toast gets a backdrop panel")
	hud._toast.visible = false
	hud._sync_backdrops()
	_check(not toast_panel.visible, "the backdrop hides with its label")
	main.queue_free()
	await _frames(3)


func _test_icons_and_theme() -> void:
	print("Icons and theme")
	var probe := IconProbe.new()
	probe.size = Vector2(600, 40)
	root.add_child(probe)
	probe.queue_redraw()
	var frames_waited := 0
	while not probe.drawn and frames_waited < 10:
		await process_frame
		frames_waited += 1
	_check(probe.drawn, "all %d icon kinds draw without errors" % HudIcons.KINDS.size())
	probe.queue_free()
	var missing: Array[String] = []
	for button in TouchControls.BUTTONS:
		var kind: StringName = TouchControls.BUTTON_ICONS.get(button["action"], &"")
		if kind == &"" or not HudIcons.KINDS.has(String(kind)):
			missing.append(String(button["action"]))
	_check(missing.is_empty(), "every touch button has a known icon %s" % ("" if missing.is_empty() else str(missing)))
	var theme := HudTheme.theme()
	_check(theme == HudTheme.theme(), "the shared theme is built once and cached")
	_check(theme.has_stylebox("normal", "Button") and theme.has_stylebox("panel", "PanelContainer"),
			"the theme styles buttons and panels")
	_check(HudTheme.panel_style().corner_radius_top_left == HudTheme.CORNER, "panels are rounded")
	var plan: Dictionary = Hud.plan_layout(Vector2(1280, 720), false)
	var bars: Rect2 = plan["bars"]
	_check(bars.end.y <= 134.0 and bars.size.x == 240.0, "the bars block still fits the layout contract (y %d-%d)" % [bars.position.y, bars.end.y])
