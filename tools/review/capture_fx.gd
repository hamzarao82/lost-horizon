extends Node
## Review capture: every visual effect as a filmstrip. Each effect is triggered in a small plain arena (ground
## plane, sky colour, camera framing 1280x720) and captured at FRAME_TIMES seconds after the trigger; the frames are
## composited left to right into one PNG with Image.blit_rect. WINDOWED ONLY (headless runs cannot take screenshots).
## Effects use the game's own code paths where it is practical (Fx signals on a real enemy, the real barrel, the
## real TelegraphIndicator, DamageDirection, TeleportFx, the opening's smoke and rain).
##   LH_CAPTURE_DIR=<folder> godot --path <game> --resolution 1280x720 res://tools/review/capture_fx.tscn
## Output: <folder>/fx/<id>.png and <folder>/fx.json = [{"id","name","file","frames":[seconds...],"source"}].
## Effects that cannot be shown are listed in the same array with "skipped": "<reason>" and no "file".
## tests/review_capture_check.gd reads EFFECTS and SKIPPED and checks every source file exists.

signal finished

## Quit when done. A test that wants to read the results turns this off and waits for `finished`.
var quit_when_done: bool = true
var out_dir: String = ""

const WIDTH: int = 1280
const HEIGHT: int = 720
const FRAME_TIMES: Array[float] = [0.0, 0.1, 0.25, 0.5]
const SOLDIER_SCENE: String = "res://scenes/enemies/PatrolSoldier.tscn"
const WARDEN_SCENE: String = "res://scenes/enemies/Warden.tscn"
const SKY_DAY: Color = Color(0.55, 0.7, 0.85)
const SKY_DUSK: Color = Color(0.42, 0.36, 0.34)
const GROUND: Color = Color(0.42, 0.44, 0.4)
const DODGE_DUST: Color = Color(0.5, 0.75, 1.0, 0.8)  # the colour Fx.DODGE_DUST_COLOR uses

## Every effect that is captured: id (file-safe), name, source script (the code that makes it).
const EFFECTS: Array[Dictionary] = [
	{"id": "hit_sparks_light", "name": "Hit sparks: light", "source": "res://scripts/fx/fx_manager.gd"},
	{"id": "hit_sparks_heavy", "name": "Hit sparks: heavy", "source": "res://scripts/fx/fx_manager.gd"},
	{"id": "enemy_hit_light", "name": "Enemy hit: light (flash, number, sparks)", "source": "res://scripts/fx/fx_manager.gd"},
	{"id": "enemy_hit_heavy", "name": "Enemy hit: heavy (ring, dust, sparks, number)", "source": "res://scripts/fx/fx_manager.gd"},
	{"id": "enemy_defeated", "name": "Enemy defeated: death burst", "source": "res://scripts/fx/fx_manager.gd"},
	{"id": "dust_puff", "name": "Dust puff", "source": "res://scripts/fx/fx_manager.gd"},
	{"id": "dodge_dust", "name": "Dodge dust (blue)", "source": "res://scripts/fx/fx_manager.gd"},
	{"id": "shimmer", "name": "Shimmer (pickup and ambient glint)", "source": "res://scripts/fx/fx_manager.gd"},
	{"id": "damage_numbers", "name": "Damage numbers: normal, heavy, kill, heal", "source": "res://scripts/fx/fx_manager.gd"},
	{"id": "enemy_windup_ring", "name": "Enemy windup ring", "source": "res://scripts/fx/fx_manager.gd"},
	{"id": "boss_ground_decal", "name": "Boss ground telegraph decal", "source": "res://scripts/fx/fx_manager.gd"},
	{"id": "boss_telegraph", "name": "Boss attack telegraph strip", "source": "res://scripts/ui/telegraph_indicator.gd"},
	{"id": "elite_bar", "name": "Elite health bar (damaged)", "source": "res://scripts/ui/elite_bar.gd"},
	{"id": "damage_direction", "name": "Damage direction wedge", "source": "res://scripts/ui/damage_direction.gd"},
	{"id": "explosive_barrel_fuse", "name": "Explosive barrel: fuse lit", "source": "res://scripts/world/explosive_barrel.gd"},
	{"id": "explosive_barrel_blast", "name": "Explosive barrel: blast", "source": "res://scripts/world/explosive_barrel.gd"},
	{"id": "teleport_departure", "name": "Teleport departure column and flash", "source": "res://scripts/fx/teleport_fx.gd"},
	{"id": "opening_smoke", "name": "Opening: distant smoke plume", "source": "res://scripts/world/opening_approach.gd"},
	{"id": "opening_rain", "name": "Opening: storm rain (storm scene)", "source": "res://scripts/story/opening_cinematic.gd"},
]

## Effects that cannot be filmed here, with the reason. The source is still a real file (checked by the test).
const SKIPPED: Array[Dictionary] = [
	{"id": "hit_stop", "name": "Hit stop (time freeze)", "source": "res://scripts/fx/hit_stop.gd",
		"reason": "a time freeze with no picture of its own; it is felt in play, not seen in a still arena"},
	{"id": "weapon_trail", "name": "Weapon trail (swing arc)", "source": "res://scripts/fx/weapon_trail.gd",
		"reason": "drawn only while a real character swings a weapon with an active hitbox; needs a running fight"},
]

var _tag: Label
var _fx: Node
var _arena_node: Node3D


func _ready() -> void:
	out_dir = OS.get_environment("LH_CAPTURE_DIR").replace("\\", "/").rstrip("/")
	if out_dir == "":
		push_error("LH_CAPTURE_DIR is not set")
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("capture_fx needs a window: headless runs cannot take screenshots")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir + "/fx")
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_fx = get_node("/root/Fx")
	var saves: Node = get_node("/root/SaveManager")
	saves.test_mode = true
	get_node("/root/QuestManager").intro_done = true

	var results: Array[Dictionary] = []
	for effect in EFFECTS:
		var id: String = effect["id"]
		var frames: Array[Image] = await _capture(id)
		if frames.size() != FRAME_TIMES.size():
			results.append({"id": id, "name": effect["name"], "file": "", "frames": [],
					"source": effect["source"], "skipped": "fewer than %d frames could be grabbed" % FRAME_TIMES.size()})
			print("SKIP fx %s: frames missing" % id)
		else:
			var file := "fx/%s.png" % id
			_filmstrip(frames).save_png("%s/%s" % [out_dir, file])
			results.append({"id": id, "name": effect["name"], "file": file, "frames": FRAME_TIMES.duplicate(),
					"source": effect["source"]})
			print("CAPTURE fx %s" % id)
		await _clear()
	for effect in SKIPPED:
		results.append({"id": effect["id"], "name": effect["name"], "file": "", "frames": [],
				"source": effect["source"], "skipped": effect["reason"]})
		print("SKIP fx %s: %s" % [effect["id"], effect["reason"]])

	var f := FileAccess.open("%s/fx.json" % out_dir, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(results, "\t"))
		f.close()
	print("CAPTURE fx done: %d effects -> %s" % [EFFECTS.size(), out_dir])
	finished.emit()
	if quit_when_done:
		get_tree().quit(0)


# --- arena and filming -----------------------------------------------------------------------------------

## A plain arena in the main world: sky colour, sun, a ground plane, the camera framing the action, and a tag
## with the time of each frame. `_clear` frees it after the effect.
func _arena(sky: Color, cam_pos: Vector3, cam_target: Vector3) -> Node3D:
	var arena := Node3D.new()
	arena.name = "Arena"
	add_child(arena)
	_arena_node = arena
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.85, 0.85)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	arena.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	arena.add_child(sun)
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = GROUND
	plane.material = ground_mat
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	arena.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 50.0
	arena.add_child(cam)
	cam.current = true
	cam.global_position = cam_pos
	cam.look_at(cam_target)
	var layer := CanvasLayer.new()
	layer.layer = 100
	arena.add_child(layer)
	_tag = Label.new()
	_tag.position = Vector2(16.0, HEIGHT - 44.0)
	_tag.add_theme_font_size_override("font_size", 26)
	_tag.add_theme_color_override("font_color", Color.WHITE)
	_tag.add_theme_color_override("font_outline_color", Color.BLACK)
	_tag.add_theme_constant_override("outline_size", 6)
	layer.add_child(_tag)
	return arena


func _clear() -> void:
	if _arena_node != null and is_instance_valid(_arena_node):
		_arena_node.queue_free()
	_arena_node = null
	_tag = null
	await _frames(2)
	await get_tree().create_timer(1.2).timeout  # let the pooled effects finish before the next one


## Builds the effect's arena, triggers it at t = 0 and grabs one image per FRAME_TIMES entry.
func _capture(id: String) -> Array[Image]:
	var chest := Vector3(0.0, 1.1, 0.0)
	match id:
		"hit_sparks_light":
			_arena(SKY_DAY, Vector3(0, 1.8, 6), chest)
			return await _film(func() -> void: _fx.spark(chest, 5.0))
		"hit_sparks_heavy":
			_arena(SKY_DAY, Vector3(0, 1.8, 6), chest)
			return await _film(func() -> void: _fx.spark(chest, 25.0))
		"enemy_hit_light":
			_arena(SKY_DAY, Vector3(0, 2.0, 6), Vector3(0, 1.0, 0))
			var light_target = _soldier(Vector3.ZERO)
			return await _film(func() -> void: light_target.damaged.emit(5.0, chest, false))
		"enemy_hit_heavy":
			_arena(SKY_DAY, Vector3(0, 2.0, 6), Vector3(0, 1.0, 0))
			var heavy_target = _soldier(Vector3.ZERO)
			return await _film(func() -> void: heavy_target.damaged.emit(25.0, chest, false))
		"enemy_defeated":
			_arena(SKY_DAY, Vector3(0, 2.0, 6), Vector3(0, 1.0, 0))
			var dead_target = _soldier(Vector3.ZERO)
			return await _film(func() -> void: dead_target.defeated.emit())
		"dust_puff":
			_arena(SKY_DAY, Vector3(0, 1.4, 6), Vector3(0, 0.6, 0))
			return await _film(func() -> void: _fx.dust(Vector3(0, 0.1, 0)))
		"dodge_dust":
			_arena(SKY_DAY, Vector3(0, 1.4, 6), Vector3(0, 0.6, 0))
			return await _film(func() -> void: _fx.dust(Vector3(0, 0.1, 0), DODGE_DUST))
		"shimmer":
			_arena(SKY_DUSK, Vector3(0, 1.8, 6), Vector3(0, 1.0, 0))
			return await _film(func() -> void: _fx.shimmer(Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.4)))
		"damage_numbers":
			_arena(SKY_DAY, Vector3(0, 1.8, 6), Vector3(0, 1.2, 0))
			return await _film(func() -> void:
				_fx.damage_number(Vector3(-2.2, 1.0, 0), 12.0)
				_fx.damage_number(Vector3(0, 1.0, 0), 30.0)
				_fx.damage_number(Vector3(2.2, 1.0, 0), 45.0, true)
				_fx.number(Vector3(0, 2.2, 0), "+25", Color(0.35, 1.0, 0.45)))
		"enemy_windup_ring":
			_arena(SKY_DAY, Vector3(0, 3.0, 7), Vector3(0, 0.5, 0))
			var windup_target = _soldier(Vector3.ZERO)
			return await _film(func() -> void: windup_target.swing_started.emit())
		"boss_ground_decal":
			_arena(SKY_DAY, Vector3(0, 6.0, 12), Vector3(0, 0.5, 0))
			var decal_boss = _warden(Vector3.ZERO)
			return await _film(func() -> void: decal_boss.swing_started.emit())
		"boss_telegraph":
			return await _telegraph_film()
		"elite_bar":
			_arena(SKY_DAY, Vector3(0, 2.4, 7), Vector3(0, 1.4, 0))
			var elite = _soldier(Vector3.ZERO, 200.0)
			EliteBar.attach(elite)
			return await _film(func() -> void: (elite.get_node("HealthComponent") as HealthComponent).take_damage(60.0))
		"damage_direction":
			_arena(SKY_DAY, Vector3(0, 1.8, 6), Vector3(0, 1.0, 0))
			var layer := CanvasLayer.new()
			_arena_node.add_child(layer)
			var direction := DamageDirection.new()
			layer.add_child(direction)
			return await _film(func() -> void: direction.on_hit(Vector3.ZERO, Vector3(-6.0, 0.0, 0.0)))
		"explosive_barrel_fuse":
			_arena(SKY_DAY, Vector3(0, 2.6, 7), Vector3(0, 0.8, 0))
			var fuse_barrel := _barrel()
			return await _film(func() -> void: fuse_barrel.light())
		"explosive_barrel_blast":
			_arena(SKY_DAY, Vector3(0, 2.6, 7), Vector3(0, 0.8, 0))
			var blast_barrel := _barrel()
			return await _film(func() -> void: blast_barrel.explode())
		"teleport_departure":
			_arena(SKY_DAY, Vector3(0, 2.2, 7), Vector3(0, 1.2, 0))
			var teleport := TeleportFx.new()
			_arena_node.add_child(teleport)
			return await _film(func() -> void:
				teleport.play_at(0, Vector3.ZERO)
				teleport.flash(0.4))
		"opening_smoke":
			return await _smoke_film()
		"opening_rain":
			return await _rain_film()
	push_error("no capture for effect %s" % id)
	return []


func _soldier(at: Vector3, hit_points: float = 0.0) -> Enemy:
	var enemy := (load(SOLDIER_SCENE) as PackedScene).instantiate() as Enemy
	if hit_points > 0.0:
		enemy.hit_points = hit_points
	enemy.position = at
	_arena_node.add_child(enemy)
	enemy.set_physics_process(false)  # held still: nothing in the arena to chase
	return enemy


func _warden(at: Vector3) -> Enemy:
	var boss := (load(WARDEN_SCENE) as PackedScene).instantiate() as Enemy
	boss.position = at
	_arena_node.add_child(boss)
	boss.set_physics_process(false)
	return boss


func _barrel() -> ExplosiveBarrel:
	var barrel := ExplosiveBarrel.new()
	barrel.position = Vector3.ZERO
	_arena_node.add_child(barrel)
	return barrel


## Grabs the frames. `trigger` runs once at t = 0; `update` (if given) runs with each frame's elapsed time first.
func _film(trigger: Callable, update: Callable = Callable()) -> Array[Image]:
	var frames: Array[Image] = []
	trigger.call()
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	for target in FRAME_TIMES:
		while (Time.get_ticks_msec() - t0) / 1000.0 < target:
			await get_tree().process_frame
		var now := (Time.get_ticks_msec() - t0) / 1000.0
		if _tag != null:
			_tag.text = "t = %.2f s" % target
		if update.is_valid():
			update.call(now)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			return []
		if image.get_size() != Vector2i(WIDTH, HEIGHT):
			image.resize(WIDTH, HEIGHT)
		frames.append(image)
	return frames


## The boss telegraph: a real Warden in its attack windup (AI paused; the windup is set by hand each frame) and
## the real TelegraphIndicator strip, which reads the boss through its telegraph_progress.
func _telegraph_film() -> Array[Image]:
	_arena(SKY_DAY, Vector3(0, 4.0, 11), Vector3(0, 1.5, 0))
	var boss := _warden(Vector3.ZERO)
	var layer := CanvasLayer.new()
	_arena_node.add_child(layer)
	var strip := TelegraphIndicator.new()
	layer.add_child(strip)
	var rect := Rect2(340.0, 640.0, 600.0, 14.0)
	var swing: AttackData = boss.get("_swing")
	boss.state = Enemy.State.ATTACK
	var windup := func(now: float) -> void:
		boss.set("_attack_frames", swing.startup_frames * clampf(now / 0.6, 0.0, 1.0))
		strip.update_for(boss, rect, 0.016)
	windup.call(0.0)
	return await _film(func() -> void: pass, windup)


## The opening's distant smoke: the approach scene's own smoke emitter, pre-run for 4 s so a plume is visible.
func _smoke_film() -> Array[Image]:
	var approach := OpeningApproach.new()
	get_tree().root.add_child(approach)
	approach._build_smoke()
	var smoke := approach.get_node_or_null("DistantSmoke") as CPUParticles3D
	if smoke == null:
		approach.queue_free()
		return []
	approach.remove_child(smoke)
	approach.queue_free()
	smoke.emitting = false
	smoke.preprocess = 4.0
	smoke.position = Vector3.ZERO
	_arena(SKY_DUSK, Vector3(0, 3.0, 16), Vector3(0, 3.5, 0))
	_arena_node.add_child(smoke)
	return await _film(func() -> void: smoke.emitting = true)


## The opening's storm rain: the cinematic's own scene run on to the storm (t = 24 s on its clock), then filmed.
func _rain_film() -> Array[Image]:
	var cinematic := OpeningCinematic.new()
	get_tree().root.add_child(cinematic)
	var t := 0.0
	while t < 24.0:
		cinematic.advance(0.1)
		t += 0.1
	var frames := await _film(func() -> void: pass)
	cinematic.queue_free()
	await _frames(4)
	return frames


## Left to right, one frame each, into one strip (Image.blit_rect).
func _filmstrip(frames: Array[Image]) -> Image:
	var strip := Image.create(WIDTH * frames.size(), HEIGHT, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var frame := frames[i]
		if frame.get_format() != Image.FORMAT_RGBA8:
			frame.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(frame, Rect2i(Vector2i.ZERO, Vector2i(WIDTH, HEIGHT)), Vector2i(i * WIDTH, 0))
	return strip
