extends SceneTree
## Draws a 64x64 icon per item into assets/icons/: a rarity-coloured badge with a glyph for its category
## (sword, shield, cross, hexagon, key, diamond, up-arrow). Deterministic, no external art.
##   godot --headless --path . -s tools/gen_icons.gd

const ITEMS: String = "res://resources/items/"
const OUT: String = "res://assets/icons/"
const SIZE: int = 64
const GLYPH := Color(0.93, 0.93, 0.9)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var count := 0
	for file in DirAccess.get_files_at(ITEMS):
		if not file.ends_with(".tres"):
			continue
		var item := load(ITEMS + file) as ItemData
		if item == null:
			continue
		var image := _make(item)
		image.save_png(ProjectSettings.globalize_path(OUT + String(item.item_id) + ".png"))
		count += 1
	print("icons written: ", count)
	quit()


func _make(item: ItemData) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var accent := RarityTable.color(item.rarity)
	_rounded_rect(image, 2, 2, SIZE - 3, SIZE - 3, 8, accent.darkened(0.25))
	_rounded_rect(image, 5, 5, SIZE - 6, SIZE - 6, 6, Color(0.1, 0.12, 0.15, 1.0).lerp(accent, 0.12))
	match item.category():
		ItemData.Category.WEAPON:
			_line(image, Vector2(18, 46), Vector2(46, 18), 3, GLYPH)
			_line(image, Vector2(16, 36), Vector2(28, 48), 3, accent)
			_line(image, Vector2(14, 50), Vector2(20, 44), 3, accent.darkened(0.2))
		ItemData.Category.ARMOR:
			_polygon(image, [Vector2(32, 14), Vector2(48, 20), Vector2(46, 38), Vector2(32, 52), Vector2(18, 38), Vector2(16, 20)], GLYPH)
			_polygon(image, [Vector2(32, 20), Vector2(41, 24), Vector2(40, 36), Vector2(32, 44), Vector2(24, 36), Vector2(23, 24)], accent.darkened(0.3))
		ItemData.Category.CONSUMABLE:
			_rect(image, 28, 16, 8, 32, GLYPH)
			_rect(image, 16, 28, 32, 8, GLYPH)
		ItemData.Category.MATERIAL:
			_polygon(image, _hexagon(Vector2(32, 32), 17), GLYPH)
			_polygon(image, _hexagon(Vector2(32, 32), 8), accent.darkened(0.4))
		ItemData.Category.QUEST:
			_circle(image, Vector2(24, 32), 9, GLYPH)
			_circle(image, Vector2(24, 32), 4, accent.darkened(0.4))
			_rect(image, 31, 30, 20, 5, GLYPH)
			_rect(image, 44, 35, 4, 7, GLYPH)
		ItemData.Category.COLLECTIBLE:
			_polygon(image, [Vector2(32, 14), Vector2(48, 32), Vector2(32, 50), Vector2(16, 32)], GLYPH)
			_polygon(image, [Vector2(32, 22), Vector2(40, 32), Vector2(32, 42), Vector2(24, 32)], accent.darkened(0.3))
		ItemData.Category.UPGRADE_COMPONENT:
			_polygon(image, [Vector2(32, 14), Vector2(48, 34), Vector2(38, 34), Vector2(38, 50), Vector2(26, 50), Vector2(26, 34), Vector2(16, 34)], GLYPH)
	return image


func _hexagon(center: Vector2, radius: float) -> Array:
	var points: Array = []
	for i in 6:
		var angle := TAU * i / 6.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _rect(image: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for yy in range(maxi(y, 0), mini(y + h, SIZE)):
		for xx in range(maxi(x, 0), mini(x + w, SIZE)):
			image.set_pixel(xx, yy, color)


func _rounded_rect(image: Image, x0: int, y0: int, x1: int, y1: int, radius: int, color: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := maxi(maxi(x0 + radius - x, x - (x1 - radius)), 0)
			var dy := maxi(maxi(y0 + radius - y, y - (y1 - radius)), 0)
			if dx * dx + dy * dy <= radius * radius:
				image.set_pixel(x, y, color)


func _circle(image: Image, center: Vector2, radius: float, color: Color) -> void:
	for y in SIZE:
		for x in SIZE:
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				image.set_pixel(x, y, color)


func _line(image: Image, a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var steps := int(a.distance_to(b)) * 2
	for i in steps + 1:
		var p := a.lerp(b, float(i) / maxf(steps, 1))
		for y in range(int(p.y - width), int(p.y + width) + 1):
			for x in range(int(p.x - width), int(p.x + width) + 1):
				if x >= 0 and y >= 0 and x < SIZE and y < SIZE and Vector2(x, y).distance_to(p) <= width:
					image.set_pixel(x, y, color)


func _polygon(image: Image, points: Array, color: Color) -> void:
	var polygon := PackedVector2Array()
	for point in points:
		polygon.append(point as Vector2)
	for y in SIZE:
		for x in SIZE:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), polygon):
				image.set_pixel(x, y, color)
