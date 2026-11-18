extends Node
## Review capture: every UI screen of the game as a 1280x720 PNG, plus ui.json. WINDOWED ONLY (headless
## runs cannot take screenshots). Screens are built the way the game builds them: MainMenu, the real Main world
## (Hud, PauseMenu, RPG screens, DeathScreen, ResultsScreen) with real items, quest and stats content, and the
## story overlays. Only test save files are touched (SaveManager.test_mode), and they are removed at the end.
##   LH_CAPTURE_DIR=<folder> godot --path <game> --resolution 1280x720 res://tools/review/capture_ui.tscn
## Output: <folder>/ui/<id>.png and <folder>/ui.json = [{"id","name","file","script"}]. A screen that could not be
## built is listed in the same array with "skipped": "<reason>" and no "file".
## tests/review_capture_check.gd reads SCREENS and EXCLUDED and checks that every script in scripts/ui and
## scripts/story is either a screen here or excluded with a reason.

signal finished

const WIDTH: int = 1280
const HEIGHT: int = 720
const SETTLE_FRAMES: int = 12
const ITEMS: String = "res://resources/items/"
const MAIN_SCENE: String = "res://scenes/main/Main.tscn"
const WARDEN_SCENE: String = "res://scenes/enemies/Warden.tscn"
const MERCHANT: String = "res://resources/merchants/outpost_quartermaster.tres"

## Quit when done. A test that wants to read the results turns this off and waits for `finished`.
var quit_when_done: bool = true
var out_dir: String = ""

var _entries: Array[Dictionary] = []

## Every screen the capture produces, in capture order: id (file-safe), name, the script it comes from.
const SCREENS: Array[Dictionary] = [
	{"id": "main_menu", "name": "Main menu", "script": "res://scripts/ui/main_menu.gd"},
	{"id": "main_menu_settings", "name": "Main menu: settings", "script": "res://scripts/ui/settings_page.gd"},
	{"id": "key_bindings", "name": "Key bindings (from the main menu)", "script": "res://scripts/ui/rebind_panel.gd"},
	{"id": "credits", "name": "Credits", "script": "res://scripts/ui/main_menu.gd"},
	{"id": "load_screen", "name": "Load game", "script": "res://scripts/ui/load_screen.gd"},
	{"id": "hud_normal", "name": "HUD: normal play", "script": "res://scripts/ui/hud.gd"},
	{"id": "hud_location", "name": "HUD: area name banner", "script": "res://scripts/ui/hud.gd"},
	{"id": "hud_message_toast", "name": "HUD: pickup toast", "script": "res://scripts/ui/hud.gd"},
	{"id": "rpg_toast", "name": "Loot and credit toasts", "script": "res://scripts/ui/rpg_notifications.gd"},
	{"id": "rpg_level_banner", "name": "Level-up banner", "script": "res://scripts/ui/rpg_notifications.gd"},
	{"id": "hud_low_health", "name": "HUD: low health", "script": "res://scripts/ui/hud.gd"},
	{"id": "hud_damage_direction", "name": "HUD: damage direction wedge", "script": "res://scripts/ui/hud.gd"},
	{"id": "hud_wave_counter", "name": "HUD: wave counter and wave banner", "script": "res://scripts/ui/hud.gd"},
	{"id": "hud_boss_telegraph", "name": "HUD: boss bar with attack telegraph", "script": "res://scripts/ui/hud.gd"},
	{"id": "touch_controls", "name": "Touch controls (forced on for the capture)", "script": "res://scripts/ui/touch_controls.gd"},
	{"id": "perf_overlay", "name": "FPS / performance readout", "script": "res://scripts/ui/perf_overlay.gd"},
	{"id": "pause_menu", "name": "Pause menu", "script": "res://scripts/ui/pause_menu.gd"},
	{"id": "pause_settings", "name": "Pause menu: settings", "script": "res://scripts/ui/settings_page.gd"},
	{"id": "pause_key_bindings", "name": "Pause menu: key bindings", "script": "res://scripts/ui/rebind_panel.gd"},
	{"id": "inventory_screen", "name": "Inventory", "script": "res://scripts/ui/inventory_screen.gd"},
	{"id": "character_screen", "name": "Character and skills", "script": "res://scripts/ui/character_screen.gd"},
	{"id": "crafting_screen", "name": "Crafting", "script": "res://scripts/ui/crafting_screen.gd"},
	{"id": "merchant_screen", "name": "Merchant (buy and sell)", "script": "res://scripts/ui/merchant_screen.gd"},
	{"id": "equipment_screen", "name": "Gear overview", "script": "res://scripts/ui/equipment_screen.gd"},
	{"id": "journal_screen", "name": "Journal", "script": "res://scripts/ui/journal_screen.gd"},
	{"id": "map_screen", "name": "Map: overview", "script": "res://scripts/ui/map_screen.gd"},
	{"id": "map_detail", "name": "Map: area detail", "script": "res://scripts/ui/map_screen.gd"},
	{"id": "results_screen", "name": "Mission results", "script": "res://scripts/ui/results_screen.gd"},
	{"id": "death_screen", "name": "Death screen", "script": "res://scripts/ui/death_screen.gd"},
	{"id": "arena_result", "name": "Arena result", "script": "res://scripts/ui/arena_result.gd"},
	{"id": "story_intro", "name": "Opening title sequence (captions)", "script": "res://scripts/story/intro.gd"},
	{"id": "opening_cinematic", "name": "Opening cinematic (first frame)", "script": "res://scripts/story/opening_cinematic.gd"},
	{"id": "opening_beach", "name": "Opening: beach recovery", "script": "res://scripts/story/opening_beach.gd"},
	{"id": "opening_ending", "name": "Opening: lockdown breaker ending", "script": "res://scripts/story/opening_ending.gd"},
	{"id": "campaign_ending", "name": "Campaign ending: closing captions", "script": "res://scripts/story/campaign_ending.gd"},
	{"id": "campaign_ending_choice", "name": "Campaign ending: choice", "script": "res://scripts/story/campaign_ending.gd"},
	{"id": "story_ending", "name": "Thanks for playing", "script": "res://scripts/story/ending.gd"},
]

## Files in scripts/ui and scripts/story that are not a screen of their own, with the reason. They are either
## parts of a screen (drawn inside it), helpers, or captured as effects in capture_fx.gd.
const EXCLUDED: Dictionary = {
	"res://scripts/ui/damage_direction.gd": "drawn in the HUD; captured as the damage direction effect in capture_fx.gd",
	"res://scripts/ui/elite_bar.gd": "a 3D bar over an enemy; captured as the elite bar effect in capture_fx.gd",
	"res://scripts/ui/telegraph_indicator.gd": "the strip under the boss bar; in hud_boss_telegraph and the telegraph effect",
	"res://scripts/ui/objective_pointer.gd": "compass arrow owned by the HUD; shows only while an objective is off screen",
	"res://scripts/ui/hud_bar.gd": "widget inside the HUD (health, armor, stamina bars)",
	"res://scripts/ui/hud_icons.gd": "icon drawing helper used by the HUD",
	"res://scripts/ui/hud_teleport.gd": "teleport charge widget inside the HUD",
	"res://scripts/ui/hud_theme.gd": "theme and colour constants, no visuals of its own",
	"res://scripts/ui/hud_widgets.gd": "equipment panel inside the HUD (top right of hud_normal)",
	"res://scripts/ui/item_details_panel.gd": "details panel inside the inventory screen",
	"res://scripts/ui/map_canvas.gd": "the drawing surface inside the map screen",
	"res://scripts/ui/menu_embers.gd": "animated background of the main menu",
	"res://scripts/ui/menu_hero.gd": "character figure on the main menu",
	"res://scripts/ui/menu_storm.gd": "storm background of the main menu",
	"res://scripts/ui/region_label.gd": "text helper (area names), no visuals of its own",
	"res://scripts/ui/rpg_screen.gd": "base class of the RPG screens (their frame is in every RPG capture)",
	"res://scripts/ui/rpg_ui.gd": "shared styling helper for the RPG screens",
	"res://scripts/story/dialogue_line.gd": "data for one line of dialogue; the line is drawn as a caption in the HUD",
	"res://scripts/story/dialogue_player.gd": "plays dialogue through the HUD caption path (hud_normal)",
	"res://scripts/story/dialogue_sequence.gd": "data for a conversation; no visuals of its own",
	"res://scripts/story/document_data.gd": "data for a journal document; shown by journal_screen",
	"res://scripts/story/document_index.gd": "catalogue of documents; shown by journal_screen",
	"res://scripts/story/opening_art.gd": "procedural 3D art for the opening, shown in opening_cinematic and opening_beach",
	"res://scripts/story/opening_timeline.gd": "timing data for the opening cinematic",
	"res://scripts/story/payment_bag.gd": "3D prop of the payment bag, seen in the cinematic and in the world",
	"res://scripts/story/payment_recovery.gd": "scripted world moment (camera and a line in the world), not a screen",
}


func _ready() -> void:
	out_dir = OS.get_environment("LH_CAPTURE_DIR").replace("\\", "/").rstrip("/")
	if out_dir == "":
		push_error("LH_CAPTURE_DIR is not set")
		get_tree().quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("capture_ui needs a window: headless runs cannot take screenshots")
		get_tree().quit(2)
		return
	_run.call_deferred()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout


## One screenshot of the window, after the screen has settled. Records the entry for ui.json.
func _shot(id: String, script_path: String) -> void:
	await _frames(SETTLE_FRAMES)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_skip(id, script_path, "the viewport gave no image")
		return
	if image.get_size() != Vector2i(WIDTH, HEIGHT):
		image.resize(WIDTH, HEIGHT)
	var file := "ui/%s.png" % id
	if image.save_png("%s/%s" % [out_dir, file]) != OK:
		_skip(id, script_path, "the PNG could not be written")
		return
	_entries.append({"id": id, "name": _name_of(id), "file": file, "script": script_path})
	print("CAPTURE ui %s" % id)


func _skip(id: String, script_path: String, reason: String) -> void:
	_entries.append({"id": id, "name": _name_of(id), "file": "", "script": script_path, "skipped": reason})
	print("SKIP ui %s: %s" % [id, reason])


func _name_of(id: String) -> String:
	for screen in SCREENS:
		if screen["id"] == id:
			return screen["name"]
	return id


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir + "/ui")
	HitStop.enabled = false
	Player.require_mouse_capture = false
	var saves: Node = get_node("/root/SaveManager")
	var qm: Node = get_node("/root/QuestManager")
	var stats: Node = get_node("/root/RunStats")
	# Test files only: the real save slots are never read or written by this tool.
	saves.test_mode = true
	saves.slot = 1
	qm.intro_done = true
	saves.delete_save()
	saves.reset_runtime_state()
	stats.reset()

	saves.write_data(_save_data())
	await _menu_screens()
	saves.delete_save()
	saves.reset_runtime_state()

	await _world_screens()
	await _story_screens()

	saves.delete_save()
	saves.reset_runtime_state()
	stats.reset()
	_write_json()
	print("CAPTURE ui done: %d entries -> %s" % [_entries.size(), out_dir])
	finished.emit()
	if quit_when_done:
		get_tree().quit(0)


func _save_data() -> Dictionary:
	return {"version": 4, "saved_at": int(Time.get_unix_time_from_system()) - 2530, "next_wave": 1,
			"completed": false, "inventory": {"weapon": "improvised_blade", "armor": "", "potions": 2},
			"player": {"health": 80.0, "max_health": 100.0}, "defeated_bosses": [],
			"world": {"checkpoint_id": "checkpoint_b", "position": [-22.0, 0.8, 24.0]},
			"regions": {"current": "dead_coast"}, "stats": {"seconds": 2530.0, "kills": 12, "pickups": 3}}


# --- main menu and its pages ---------------------------------------------------------------------------

func _menu_screens() -> void:
	var menu := MainMenu.new()
	get_tree().root.add_child(menu)
	await _frames(3)
	menu.skip_intro()
	await _frames(30)
	menu.refresh()
	await _shot("main_menu", "res://scripts/ui/main_menu.gd")

	menu.button("settings").pressed.emit()
	await _shot("main_menu_settings", "res://scripts/ui/settings_page.gd")
	var page: Node = menu.get("_settings_page")
	page._open_bindings()
	await _shot("key_bindings", "res://scripts/ui/rebind_panel.gd")
	page._close_bindings()
	menu._show_page(menu.get("_main_page"))

	menu.button("credits").pressed.emit()
	await _shot("credits", "res://scripts/ui/main_menu.gd")
	menu._show_page(menu.get("_main_page"))

	var load_screen := menu.open_load_screen()
	if load_screen == null:
		_skip("load_screen", "res://scripts/ui/load_screen.gd", "the main menu did not open the load list")
	else:
		await _shot("load_screen", "res://scripts/ui/load_screen.gd")
		load_screen.queue_free()
	menu._show_page(menu.get("_main_page"))
	menu.queue_free()
	await _frames(4)


# --- the real world: HUD, pause menu, RPG screens, death and results ------------------------------------

func _world_screens() -> void:
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	get_tree().root.add_child(main)
	await _frames(20)
	var player := get_tree().get_first_node_in_group("player") as Player
	var inv := player.inventory
	var qm: Node = get_node("/root/QuestManager")
	var stats: Node = get_node("/root/RunStats")
	var progression: Node = get_node("/root/Progression")

	# Real content: equipped gear, a bag, currency, a quest in progress and some run stats.
	inv.add_item(load(ITEMS + "katana.tres"))
	inv.add_item(load(ITEMS + "light_tactical_armor.tres"))
	inv.collect(load(ITEMS + "claymore.tres"))
	inv.collect(load(ITEMS + "bandage.tres"), 3)
	inv.collect(load(ITEMS + "health_potion.tres"), 2)
	inv.collect(load(ITEMS + "cloth_scrap.tres"), 5)
	inv.collect(load(ITEMS + "intel_drive.tres"))
	inv.add_currency(350)
	qm.add_quest_item(&"access_card")
	qm.start_quest(&"first_signal")
	progression.award_xp(900, "capture_ui")
	stats.enemies_defeated = 12
	stats.seconds_played = 754.0
	await _frames(20)

	var hud := main.get_node("Hud") as Hud
	var pause := main.get_node("PauseMenu") as PauseMenu
	var notes: Node = pause.get("_notifications")
	var waves := main.get_node("WaveManager") as WaveManager

	await _shot("hud_normal", "res://scripts/ui/hud.gd")

	hud.show_location("Outpost 17")
	await _frames(4)
	await _shot("hud_location", "res://scripts/ui/hud.gd")

	hud._show_toast("Medkit added to the bag (2 left)", Color(0.5, 0.85, 1.0))
	await _frames(2)
	await _shot("hud_message_toast", "res://scripts/ui/hud.gd")

	if notes != null:
		notes.notify_loot(load(ITEMS + "claymore.tres"))
		inv.add_currency(37)
		await _frames(2)
		await _shot("rpg_toast", "res://scripts/ui/rpg_notifications.gd")
		notes.notify_level(7)
		await _frames(2)
		await _shot("rpg_level_banner", "res://scripts/ui/rpg_notifications.gd")
	else:
		_skip("rpg_toast", "res://scripts/ui/rpg_notifications.gd", "the pause menu has no notifications node")
		_skip("rpg_level_banner", "res://scripts/ui/rpg_notifications.gd", "the pause menu has no notifications node")

	player.health.health = player.health.max_health * 0.2
	await _frames(20)
	await _shot("hud_low_health", "res://scripts/ui/hud.gd")
	player.health.health = player.health.max_health

	hud._damage_dir.on_hit(player.global_position, player.global_position + Vector3(-8.0, 0.0, 0.0))
	await _frames(3)
	await _shot("hud_damage_direction", "res://scripts/ui/hud.gd")

	waves.start_wave_at(1)
	await _seconds(2.5)
	await _shot("hud_wave_counter", "res://scripts/ui/hud.gd")
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await _frames(4)

	await _boss_telegraph_shot(main, player)

	# The game shows these only on touch devices; force_visible is the node's own switch for that.
	var touch := main.get_node("TouchLayer/TouchControls") as TouchControls
	touch.force_visible = true
	touch.visible = true
	await _frames(20)
	await _shot("touch_controls", "res://scripts/ui/touch_controls.gd")
	touch.force_visible = false
	touch.visible = false

	var perf := main.get_node("PerfOverlay") as CanvasLayer
	perf.visible = true
	await _frames(20)
	await _shot("perf_overlay", "res://scripts/ui/perf_overlay.gd")
	perf.visible = false

	pause.open()
	await _shot("pause_menu", "res://scripts/ui/pause_menu.gd")
	var settings: Node = pause.get("_settings_page")
	pause._show_page(settings)
	await _shot("pause_settings", "res://scripts/ui/settings_page.gd")
	settings._open_bindings()
	await _shot("pause_key_bindings", "res://scripts/ui/rebind_panel.gd")
	settings._close_bindings()
	pause._show_page(pause.get("_main_page"))

	await _rpg_screen(pause.get("_inventory_screen"), "inventory_screen", pause.show_inventory)
	await _rpg_screen(pause.get("_character_screen"), "character_screen", pause.show_character)
	await _rpg_screen(pause.get("_crafting_screen"), "crafting_screen", pause.show_crafting)
	var merchant_data := load(MERCHANT) as MerchantData
	await _rpg_screen(pause.get("_merchant_screen"), "merchant_screen", func() -> void: pause.show_merchant(merchant_data))
	var equipment: Node = pause.get("_equipment")
	pause.show_equipment()
	await _shot("equipment_screen", "res://scripts/ui/equipment_screen.gd")
	equipment.close()
	await _rpg_screen(pause.get("_journal_screen"), "journal_screen", pause.show_journal)
	var map_node: Node = pause.get("_map_screen")
	pause.show_map()
	await _shot("map_screen", "res://scripts/ui/map_screen.gd")
	map_node.show_detail()
	await _shot("map_detail", "res://scripts/ui/map_screen.gd")
	map_node.close()
	await _frames(2)
	pause.close()
	await _frames(4)

	var results: Node = main.get_node("ResultsScreen")
	results.show_results(&"first_signal")
	await _shot("results_screen", "res://scripts/ui/results_screen.gd")
	results.close()

	var death: Node = main.get_node("DeathScreen")
	death.show_death("Hunter Elite", "checkpoint_b", null, 0)
	await _shot("death_screen", "res://scripts/ui/death_screen.gd")
	death.hide_death()

	get_tree().paused = false
	main.queue_free()
	await _frames(6)


## The HUD boss bar and the telegraph strip, with a real Warden in its attack windup (AI paused, state set).
func _boss_telegraph_shot(main: Node, player: Player) -> void:
	var warden := (load(WARDEN_SCENE) as PackedScene).instantiate() as Enemy
	warden.position = player.global_position + Vector3(0.0, 0.0, -7.0)
	main.add_child(warden)
	await _frames(4)
	warden.set_physics_process(false)
	var swing: AttackData = warden.get("_swing")
	warden.state = Enemy.State.ATTACK
	warden.set("_attack_frames", swing.startup_frames * 0.55)
	await _seconds(0.6)
	await _shot("hud_boss_telegraph", "res://scripts/ui/hud.gd")
	warden.queue_free()
	await _frames(4)


## One RPG panel: opened through the pause menu (as the game does), shot, then closed.
func _rpg_screen(screen: Node, id: String, opener: Callable) -> void:
	if screen == null:
		_skip(id, "", "the pause menu has no such screen")
		return
	opener.call()
	await _shot(id, _script_of(screen))
	screen.close()
	await _frames(2)


func _script_of(node: Object) -> String:
	var script: Script = node.get_script()
	return script.resource_path if script != null else ""


# --- story overlays -------------------------------------------------------------------------------------

func _story_screens() -> void:
	var intro := StoryIntro.new()
	get_tree().root.add_child(intro)
	await _seconds(4.0)
	await _shot("story_intro", "res://scripts/story/intro.gd")
	intro.queue_free()
	await _frames(4)

	var cinematic := OpeningCinematic.new()
	get_tree().root.add_child(cinematic)
	await _frames(8)
	await _shot("opening_cinematic", "res://scripts/story/opening_cinematic.gd")
	cinematic.queue_free()
	await _frames(4)

	var beach := OpeningBeach.new()
	get_tree().root.add_child(beach)
	await _seconds(2.5)
	await _shot("opening_beach", "res://scripts/story/opening_beach.gd")
	beach.queue_free()
	await _frames(4)

	var ending := OpeningEnding.new()
	get_tree().root.add_child(ending)
	await _seconds(3.0)
	await _shot("opening_ending", "res://scripts/story/opening_ending.gd")
	ending.queue_free()
	await _frames(4)

	var campaign := CampaignEnding.new()
	get_tree().root.add_child(campaign)
	await _seconds(4.0)
	await _shot("campaign_ending", "res://scripts/story/campaign_ending.gd")
	campaign.call("_show_choice")
	await _frames(2)
	await _shot("campaign_ending_choice", "res://scripts/story/campaign_ending.gd")
	campaign.queue_free()
	await _frames(4)

	var story_end := StoryEnding.new()
	get_tree().root.add_child(story_end)
	await _seconds(1.0)
	await _shot("story_ending", "res://scripts/story/ending.gd")
	story_end.queue_free()
	await _frames(4)

	var arena := ArenaResult.new()
	get_tree().root.add_child(arena)
	arena.show_result(true, 5, 5, 312.0, {})
	await _shot("arena_result", "res://scripts/ui/arena_result.gd")
	arena.close()
	arena.queue_free()
	get_tree().paused = false
	await _frames(4)


func _write_json() -> void:
	var f := FileAccess.open("%s/ui.json" % out_dir, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_entries, "\t"))
		f.close()
