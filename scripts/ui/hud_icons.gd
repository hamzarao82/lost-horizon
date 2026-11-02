class_name HudIcons
extends RefCounted
## Tiny vector icons drawn with a CanvasItem's draw calls (no textures, no imports, scale to any size).
## Used next to the HUD bars and rows and inside the touch buttons.

const KINDS: PackedStringArray = [
	"heart", "shield", "bolt", "medkit", "swirl", "sword", "heavy", "armor",
	"chevron", "crosshair", "spin", "dodge", "use",
]


## Draws icon `kind` inside `rect` with `color`. Unknown kinds draw nothing.
static func draw(ci: CanvasItem, kind: StringName, rect: Rect2, color: Color) -> void:
	var w := maxf(1.5, minf(rect.size.x, rect.size.y) * 0.1)
	match kind:
		&"heart":
			ci.draw_circle(_p(rect, 0.3, 0.36), rect.size.x * 0.22, color)
			ci.draw_circle(_p(rect, 0.7, 0.36), rect.size.x * 0.22, color)
			ci.draw_colored_polygon(_poly(rect, [[0.09, 0.44], [0.91, 0.44], [0.5, 0.92]]), color)
		&"shield":
			ci.draw_colored_polygon(_poly(rect, [[0.12, 0.1], [0.88, 0.1], [0.88, 0.5], [0.5, 0.95], [0.12, 0.5]]), color)
			ci.draw_line(_p(rect, 0.5, 0.2), _p(rect, 0.5, 0.78), Color(1, 1, 1, 0.35), w * 0.7)
		&"bolt":
			ci.draw_colored_polygon(_poly(rect, [[0.6, 0.04], [0.2, 0.56], [0.46, 0.56], [0.38, 0.96], [0.8, 0.4], [0.54, 0.4]]), color)
		&"medkit":
			ci.draw_rect(Rect2(_p(rect, 0.1, 0.26), rect.size * Vector2(0.8, 0.6)), color)
			ci.draw_rect(Rect2(_p(rect, 0.33, 0.1), rect.size * Vector2(0.34, 0.2)), color, false, w)
			ci.draw_rect(Rect2(_p(rect, 0.45, 0.38), rect.size * Vector2(0.1, 0.38)), Color.WHITE)
			ci.draw_rect(Rect2(_p(rect, 0.31, 0.52), rect.size * Vector2(0.38, 0.1)), Color.WHITE)
		&"swirl":
			var center := rect.get_center()
			var radius := minf(rect.size.x, rect.size.y) * 0.46
			ci.draw_arc(center, radius, 0.3, 4.4, 20, color, w)
			ci.draw_arc(center, radius * 0.62, 3.4, 7.4, 16, color, w)
			ci.draw_circle(center, radius * 0.14, color)
		&"sword":
			ci.draw_line(_p(rect, 0.22, 0.78), _p(rect, 0.84, 0.16), color, w * 1.3)
			ci.draw_line(_p(rect, 0.3, 0.52), _p(rect, 0.48, 0.7), color, w)
			ci.draw_line(_p(rect, 0.16, 0.84), _p(rect, 0.26, 0.74), color.darkened(0.3), w * 1.6)
		&"heavy":
			ci.draw_line(_p(rect, 0.2, 0.82), _p(rect, 0.62, 0.4), color.darkened(0.2), w * 1.4)
			ci.draw_colored_polygon(_poly(rect, [[0.5, 0.18], [0.86, 0.1], [0.78, 0.5], [0.58, 0.46]]), color)
		&"armor":
			ci.draw_colored_polygon(_poly(rect, [[0.14, 0.14], [0.38, 0.14], [0.5, 0.28], [0.62, 0.14], [0.86, 0.14],
					[0.8, 0.56], [0.5, 0.94], [0.2, 0.56]]), color)
		&"chevron":
			ci.draw_polyline(PackedVector2Array([_p(rect, 0.2, 0.68), _p(rect, 0.5, 0.36), _p(rect, 0.8, 0.68)]), color, w * 1.4)
			ci.draw_polyline(PackedVector2Array([_p(rect, 0.2, 0.9), _p(rect, 0.5, 0.58), _p(rect, 0.8, 0.9)]), Color(color, 0.55), w * 1.4)
		&"crosshair":
			var c := rect.get_center()
			var r := minf(rect.size.x, rect.size.y) * 0.34
			ci.draw_arc(c, r, 0.0, TAU, 20, color, w)
			for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + dir * r * 0.6, c + dir * r * 1.35, color, w)
			ci.draw_circle(c, w * 0.8, color)
		&"spin":
			var c2 := rect.get_center()
			var r2 := minf(rect.size.x, rect.size.y) * 0.36
			ci.draw_arc(c2, r2, -0.6, 4.4, 20, color, w * 1.3)
			var tip := c2 + Vector2.from_angle(-0.6) * r2
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(-0.12, -0.22) * rect.size.x,
					tip + Vector2(0.22, 0.02) * rect.size.x, tip + Vector2(-0.16, 0.14) * rect.size.x]), color)
		&"dodge":
			var c3 := rect.get_center()
			var r3 := minf(rect.size.x, rect.size.y) * 0.34
			ci.draw_arc(c3, r3, 3.6, 8.2, 20, color, w * 1.3)
			var tip2 := c3 + Vector2.from_angle(8.2) * r3
			ci.draw_colored_polygon(PackedVector2Array([tip2 + Vector2(0.2, -0.14) * rect.size.x,
					tip2 + Vector2(-0.04, 0.24) * rect.size.x, tip2 + Vector2(-0.2, -0.08) * rect.size.x]), color)
		&"use":
			var c4 := rect.get_center()
			var r4 := minf(rect.size.x, rect.size.y) * 0.36
			ci.draw_arc(c4, r4, 0.0, TAU, 20, color, w)
			ci.draw_circle(c4, r4 * 0.28, color)


static func _p(rect: Rect2, x: float, y: float) -> Vector2:
	return rect.position + Vector2(x, y) * rect.size


static func _poly(rect: Rect2, coords: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for c in coords:
		points.append(_p(rect, c[0], c[1]))
	return points
