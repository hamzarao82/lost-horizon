extends SceneTree
## RPG screens (headless): inventory, character/skills, crafting, merchant, notifications and layout.
## Everything goes through the real Inventory, Progression, UpgradeService, CraftingBook and MerchantService.
## godot --headless --path . -s tests/rpg_screens_check.gd

const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"
const ITEM_DIR: String = "res://resources/items/"
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(800, 360)]

var _failures: int = 0
var _checks: int = 0
var _player: Player
var _inv: Inventory
var _progression: Node


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


func _item(id: String) -> ItemData:
	return load(ITEM_DIR + id + ".tres") as ItemData


func _frames(count: int = 3) -> void:
	for i in count:
		await process_frame


func _all_buttons(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button and (child as Button).is_visible_in_tree():
			out.append(child as Button)
		_all_buttons(child, out)


func _find_button(screen: Node, text: String) -> Button:
	var all: Array[Button] = []
	_all_buttons(screen, all)
	for button in all:
		if button.text == text:
			return button
	return null


func _press(button: Button) -> void:
	if button != null and not button.disabled:
		button.pressed.emit()


func _run() -> void:
	_progression = root.get_node_or_null("Progression")
	_check(_progression != null, "Progression autoload exists")
	_player = load(PLAYER_SCENE).instantiate() as Player
	root.add_child(_player)
	await _frames(4)
	_inv = _player.inventory
	_inv.add_currency(0)

	var notes := RpgNotifications.new()
	root.add_child(notes)
	var inv_screen := InventoryScreen.new()
	root.add_child(inv_screen)
	var char_screen := CharacterScreen.new()
	root.add_child(char_screen)
	var craft_screen := CraftingScreen.new()
	root.add_child(craft_screen)
	var shop := MerchantScreen.new()
	root.add_child(shop)
	await _frames(2)
	notes.hook_inventory(_inv)

	await _test_notifications(notes)
	await _test_inventory(inv_screen)
	await _test_character(char_screen)
	await _test_crafting(craft_screen)
	await _test_merchant(shop)
	await _test_layout([inv_screen, char_screen, craft_screen, shop])

	print("rpg_screens_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- notifications --------------------------------------------------------------------------------

func _test_notifications(notes: RpgNotifications) -> void:
	print("-- notifications")
	var before := notes.shown_texts.size()
	_inv.add_item(_item("scrap_metal"))  # the real world pickup path; collect() does not emit item_collected
	await _frames(2)
	_check(notes.shown_texts.size() == before + 1, "collecting one item shows exactly one toast (%d)" % (notes.shown_texts.size() - before))
	_check(notes.shown_texts.size() > before and String(notes.shown_texts[-1]).to_lower().contains("scrap"), "the toast names the item")
	before = notes.shown_texts.size()
	_inv.add_currency(37)
	await _frames(2)
	_check(notes.shown_texts.size() == before + 1 and notes.shown_texts.size() > 0 and String(notes.shown_texts[-1]).contains("+37"),
			"+37 credits shows one credit toast")
	before = notes.shown_texts.size()
	notes.notify_level(7)
	_check(notes.banner_text() == "LEVEL 7", "level-up banner text")
	_check(notes.shown_texts.size() == before + 1, "level-up adds one banner entry")
	var rare_toast_before := notes.toast_count()
	var epic := ItemData.new()
	epic.item_id = &"test_epic"
	epic.display_name = "Test Epic"
	epic.rarity = ItemData.Rarity.EPIC
	notes.notify_loot(epic)
	_check(String(notes.shown_texts[-1]).begins_with("EPIC"), "epic loot is announced as EPIC")
	_check(notes.toast_count() <= RpgNotifications.MAX_TOASTS, "toast count is capped (%d)" % notes.toast_count())
	_check(rare_toast_before <= RpgNotifications.MAX_TOASTS, "toasts never exceed the cap")
	# a real level-up through Progression raises the banner once
	var levels: Array[int] = [0]
	_progression.level_up.connect(func(_l: int) -> void: levels[0] += 1)
	_progression.award_xp(2000, "rpg_screens_check")
	await _frames(2)
	_check(levels[0] >= 1, "Progression.level_up fired (%d)" % levels[0])
	_check(notes.banner_text().begins_with("LEVEL"), "banner follows the real level-up (%s)" % notes.banner_text())


# --- inventory ------------------------------------------------------------------------------------

func _test_inventory(screen: InventoryScreen) -> void:
	print("-- inventory screen")
	var claymore := _item("claymore")
	_inv.collect(claymore)
	_inv.collect(_item("bandage"), 3)
	_inv.collect(_item("cloth_scrap"), 5)
	_inv.collect(_item("intel_drive"))
	screen.open()
	await _frames(2)
	_check(paused, "opening the inventory pauses the game")
	var focus := root.gui_get_focus_owner()
	_check(focus != null and screen.is_ancestor_of(focus), "opening the inventory puts keyboard/gamepad focus inside it (%s)" % (focus.name if focus else "none"))
	_check(screen.header_text().contains("Credits:"), "header shows credits (%s)" % screen.header_text())
	var ids := screen.row_ids()
	_check(ids.has("claymore") and ids.has("bandage") and ids.has("cloth_scrap"), "rows exist for the bag items")

	screen.set_filter(ItemData.Category.CONSUMABLE)
	await _frames(2)
	_check(screen.row_ids().has("bandage") and not screen.row_ids().has("cloth_scrap") and not screen.row_ids().has("katana"),
			"consumable filter keeps consumables only")
	screen.set_filter(-1)
	await _frames(2)

	var weapon_before := _inv.weapon
	screen.select("claymore")
	await _frames(2)
	var dump := screen.details().text_dump()
	_check(dump.contains("Claymore") or dump.to_lower().contains("claymore"), "details name the selected item")
	_check(dump.contains("Compared with") and dump.contains("Damage") and dump.contains("(+"),
			"details compare against the equipped weapon with a positive damage delta")
	var equip := screen.action_button("Equip")
	_check(equip != null, "an Equip action is offered for the claymore")
	var mult_before := float(_inv.stat_totals()["damage_mult"])
	_press(equip)
	await _frames(2)
	_check(_inv.weapon == claymore, "pressing Equip equips the claymore")
	_check(float(_inv.stat_totals()["damage_mult"]) > mult_before, "equipping raises the damage total (%.2f -> %.2f)" % [mult_before, float(_inv.stat_totals()["damage_mult"])])
	_check(_inv.count_of("claymore") == 0 and weapon_before != null, "the equipped claymore left the bag")
	_check(screen.action_button("Unequip") != null, "an equipped item offers Unequip")

	# protected quest item cannot be dropped
	screen.select("intel_drive")
	await _frames(2)
	var drop := screen.action_button("Drop")
	_check(drop != null and drop.disabled, "Drop is disabled for a quest item")
	_press(drop)
	_check(_inv.count_of("intel_drive") == 1, "the quest item is still in the bag")

	# drop one scrap
	screen.select("cloth_scrap")
	await _frames(2)
	_press(screen.action_button("Drop"))
	await _frames(2)
	_check(_inv.count_of("cloth_scrap") == 4, "Drop removes one from the stack (%d)" % _inv.count_of("cloth_scrap"))

	# use a bandage on the real player
	_player.health.take_damage(30.0)
	var hp_before: float = _player.health.health
	screen.select("bandage")
	await _frames(2)
	_press(screen.action_button("Use"))
	await _frames(2)
	_check(_player.health.health > hp_before, "Use heals the player (%.0f -> %.0f)" % [hp_before, _player.health.health])
	_check(_inv.count_of("bandage") == 2, "Use consumed one bandage (%d)" % _inv.count_of("bandage"))

	# sort changes order only
	var total_before := _inv.stack_count()
	_press(_find_button(screen, "Sort"))
	await _frames(2)
	_check(_inv.stack_count() == total_before, "Sort keeps every stack")

	await _test_upgrade(screen)
	screen.close()
	_check(not paused, "closing the inventory resumes the game")


func _test_upgrade(screen: InventoryScreen) -> void:
	print("-- upgrade confirmation")
	var weapon := _inv.weapon
	screen.select(String(weapon.item_id))
	await _frames(2)
	var plan := UpgradeService.preview(weapon, _inv)
	for id in (plan["materials"] as Dictionary).keys():
		_inv.collect(MerchantService.item_for(String(id)), int(plan["materials"][id]))
	_inv.add_currency(int(plan["currency"]))
	var level_before := _inv.level_of(weapon)
	var credits_before := _inv.currency
	var expected := UpgradeService.preview(weapon, _inv)
	_check(bool(expected["ok"]), "upgrade is affordable after seeding (%s)" % expected["reason"])
	_press(screen.action_button("Upgrade"))
	await _frames(2)
	_check(screen.is_confirming(), "Upgrade opens a confirmation first")
	_check(_inv.level_of(weapon) == level_before and _inv.currency == credits_before, "nothing is spent before confirming")
	screen.cancel_upgrade()
	_check(not screen.is_confirming() and _inv.level_of(weapon) == level_before, "Cancel keeps the level and the resources")
	_press(screen.action_button("Upgrade"))
	await _frames(2)
	var confirm := _find_button(screen, "Confirm")
	_check(confirm != null and not confirm.disabled, "Confirm is enabled when affordable")
	_press(confirm)
	await _frames(2)
	_check(_inv.level_of(weapon) == level_before + 1, "Confirm raises the level by one")
	var after := _inv.item_stats(weapon)
	_check(is_equal_approx(float(after["damage_mult"]), float((expected["after"] as Dictionary)["damage_mult"])),
			"applied damage equals the preview (%.3f)" % float(after["damage_mult"]))
	_check(_inv.currency == credits_before - int(expected["currency"]), "credits dropped by exactly the preview cost")


# --- character ------------------------------------------------------------------------------------

func _test_character(screen: CharacterScreen) -> void:
	print("-- character screen")
	var progress: PlayerProgress = _progression.get("progress")
	progress.attribute_points = 2
	progress.skill_points = 3
	screen.open()
	await _frames(2)
	_check(screen.stats_text().contains("Level"), "stats show the level (%s)" % screen.stats_text().split("\n")[0])
	_check(screen.stats_text().contains("Attribute points: 2"), "stats show the unspent attribute points")
	var vit := screen.attribute_button(&"vitality")
	_check(vit != null and not vit.disabled, "vitality + is enabled with points available")
	var spent_before := int(progress.attributes.get(&"vitality", 0))
	_press(vit)
	await _frames(3)
	_check(int(progress.attributes.get(&"vitality", 0)) == spent_before + 1, "+ spends one attribute point")
	_check(progress.attribute_points == 1, "one attribute point is left (%d)" % progress.attribute_points)
	progress.attribute_points = 0
	screen.refresh()
	await _frames(2)
	_check(screen.attribute_button(&"vitality").disabled, "+ is disabled with no points")

	# skill tree: prerequisites respected
	var tree: SkillTree = _progression.get("tree")
	var hh := tree.get_skill(&"heavy_hitter")
	_check(hh != null and hh.prerequisites.size() > 0, "heavy_hitter has a prerequisite")
	screen.select_skill(&"heavy_hitter")
	await _frames(2)
	var info := screen.skill_info_text()
	_check(info.contains("Requires"), "locked skill explains why (%s)" % info.replace("\n", " | ").left(80))
	var unlock := _find_button(screen, "Unlock")
	_check(unlock != null and unlock.disabled, "Unlock is disabled while locked")
	var points_before := progress.skill_points
	_press(unlock)
	_check(progress.skill_rank(&"heavy_hitter") == 0 and progress.skill_points == points_before, "a locked skill cannot be bought")
	screen.select_skill(&"sharpened_edge")
	await _frames(2)
	unlock = _find_button(screen, "Unlock")
	_check(unlock != null and not unlock.disabled, "an available skill can be unlocked")
	_press(unlock)
	await _frames(3)
	_check(progress.skill_rank(&"sharpened_edge") == 1, "Unlock buys rank 1")
	_check(progress.skill_points < points_before, "skill points were spent (%d -> %d)" % [points_before, progress.skill_points])
	_check(screen.skill_button(&"sharpened_edge") != null and screen.skill_button(&"heavy_hitter") != null, "skill nodes are drawn")
	screen.close()


# --- crafting -------------------------------------------------------------------------------------

func _test_crafting(screen: CraftingScreen) -> void:
	print("-- crafting screen")
	_check(screen.recipe_count() >= 6, "recipes loaded (%d)" % screen.recipe_count())
	screen.open()
	await _frames(2)
	var index := -1
	for i in screen.recipe_count():
		screen.select_recipe(i)
		if screen.selected_recipe().recipe_id == &"bandage":
			index = i
			break
	_check(index >= 0, "the bandage recipe is listed")
	while _inv.count_of("cloth_scrap") > 0:
		_inv.remove("cloth_scrap", _inv.count_of("cloth_scrap"))
	screen.select_recipe(index)
	await _frames(2)
	_check(screen.craft_button().disabled, "Craft is disabled without materials")
	_check(screen.info_text().contains("0 / 2"), "info shows have/need (%s)" % screen.info_text().replace("\n", " | ").left(90))
	_inv.collect(_item("cloth_scrap"), 5)
	screen.select_recipe(index)
	await _frames(2)
	_check(not screen.craft_button().disabled, "Craft is enabled with materials")
	var bandages := _inv.count_of("bandage")
	_press(screen.craft_button())
	await _frames(2)
	_check(_inv.count_of("cloth_scrap") == 3, "crafting consumed exactly 2 scrap (%d left)" % _inv.count_of("cloth_scrap"))
	_check(_inv.count_of("bandage") == bandages + 1, "crafting produced one bandage")
	_check(screen.status_text().contains("Crafted"), "status confirms the craft (%s)" % screen.status_text())
	screen.close()


# --- merchant -------------------------------------------------------------------------------------

func _test_merchant(screen: MerchantScreen) -> void:
	print("-- merchant screen")
	var data := load("res://resources/merchants/outpost_quartermaster.tres") as MerchantData
	_inv.add_currency(500)
	screen.open_for(data)
	await _frames(2)
	_check(screen.is_buying() and screen.row_ids().has("bandage"), "buy tab lists the vendor stock")
	var price := MerchantService.buy_price(data, "bandage")
	var credits := _inv.currency
	var owned := _inv.count_of("bandage")
	screen.select("bandage")
	screen.set_quantity(3)
	await _frames(2)
	_press(screen.action_button())
	await _frames(2)
	_check(_inv.currency == credits - price * 3, "buying 3 cost exactly 3 x %d (%d -> %d)" % [price, credits, _inv.currency])
	_check(_inv.count_of("bandage") == owned + 3, "the bandages arrived in the bag")
	# cannot afford: money and items unchanged
	var poor := _inv.currency
	_inv.spend_currency(poor)
	var items_before := _inv.count_of("bandage")
	screen.select("bandage")
	_press(screen.action_button())
	await _frames(2)
	_check(_inv.count_of("bandage") == items_before and _inv.currency == 0, "a purchase without credits changes nothing")
	_check(screen.status_text() != "", "the refusal explains itself (%s)" % screen.status_text())
	_inv.add_currency(poor)
	# selling
	screen.set_mode(false)
	await _frames(2)
	_check(not screen.is_buying() and screen.row_ids().has("bandage"), "sell tab lists sellable bag items")
	_check(not screen.row_ids().has("intel_drive"), "quest items are not offered for sale")
	screen.select("bandage")
	screen.set_quantity(1)
	var unit := MerchantService.sell_price(data, _item("bandage"))
	credits = _inv.currency
	items_before = _inv.count_of("bandage")
	await _frames(2)
	_press(screen.action_button())
	await _frames(2)
	_check(_inv.currency == credits + unit and _inv.count_of("bandage") == items_before - 1,
			"selling one pays %d and removes one" % unit)
	_check(unit < price, "selling pays less than buying (%d < %d)" % [unit, price])
	screen.close()


# --- layout ---------------------------------------------------------------------------------------

func _test_layout(screens: Array) -> void:
	print("-- layout")
	var data := load("res://resources/merchants/outpost_quartermaster.tres") as MerchantData
	var scale_mode := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED  # literal pixel sizes: stricter than the stretched viewport
	for size in SIZES:
		root.size = size
		await _frames(3)
		for screen in screens:
			var rpg := screen as RpgScreen
			if rpg is MerchantScreen:
				(rpg as MerchantScreen).open_for(data)
			else:
				rpg.open()
			await _frames(3)
			var name := "%s %dx%d" % [rpg.get_script().get_global_name(), size.x, size.y]
			var panel := rpg.root_control().get_child(1).get_child(0) as Control  # margin -> panel
			var view := Rect2(Vector2.ZERO, Vector2(size))
			_check(view.encloses(panel.get_global_rect().grow(-0.5)), "%s: panel fits the screen" % name)
			var buttons: Array[Button] = []
			_all_buttons(rpg.root_control(), buttons)
			var short := 0
			for button in buttons:
				if button.get_global_rect().size.y < RpgUi.TOUCH_HEIGHT - 0.5 and button.size.y > 0.0:
					short += 1
			_check(short == 0, "%s: all buttons are at least 56 px tall (%d short)" % [name, short])
			# siblings never overlap
			var overlaps := 0
			var parents: Dictionary = {}
			for button in buttons:
				parents[button.get_parent()] = true
			for parent in parents.keys():
				if parent is ScrollContainer or (parent as Node).get_parent() is ScrollContainer and false:
					continue
				var kids: Array[Button] = []
				for child in (parent as Node).get_children():
					if child is Button and (child as Button).is_visible_in_tree() and not (parent is Control and (parent as Control).get_class() == "Control"):
						kids.append(child)
				for a in kids.size():
					for b in range(a + 1, kids.size()):
						if kids[a].get_global_rect().grow(-1.0).intersects(kids[b].get_global_rect().grow(-1.0)):
							overlaps += 1
			_check(overlaps == 0, "%s: no overlapping sibling buttons (%d)" % [name, overlaps])
			rpg.close()
			await _frames(2)
	root.size = SIZES[0]
	root.content_scale_mode = scale_mode
