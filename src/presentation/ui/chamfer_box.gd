class_name ChamferBox
extends StyleBox
## Flat box with two opposite chamfered corners (top-right and bottom-left), the plate of the main
## menu items (docs/design/operational_map/main_menu.html, variant A): a fill, a 1 px outline that
## follows the chamfers and an optional accent bar on the left edge (hover). Drawn through the
## RenderingServer, so it works as a Button style.

var fill := UiPalette.PANEL
var border := Color(UiPalette.AMBER, 0.34)
var border_width := 1.0
var cut := 12.0
var accent := Color(0, 0, 0, 0)  # left bar colour; transparent = none
var accent_width := 4.0


## The plate's outline for a box of `size`: the two chamfered corners cut by `cut`.
static func outline(size: Vector2, cut_size: float) -> PackedVector2Array:
	return PackedVector2Array(
		[
			Vector2(0, 0),
			Vector2(size.x - cut_size, 0),
			Vector2(size.x, cut_size),
			Vector2(size.x, size.y),
			Vector2(cut_size, size.y),
			Vector2(0, size.y - cut_size),
		]
	)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var points := outline(rect.size, cut)
	for i in points.size():
		points[i] += rect.position
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, PackedColorArray([fill]))
	if accent.a > 0.0:
		# The bar stays clear of the bottom-left chamfer.
		var bar := Rect2(rect.position, Vector2(accent_width, rect.size.y - cut))
		var corners := PackedVector2Array(
			[
				bar.position,
				bar.position + Vector2(bar.size.x, 0),
				bar.position + bar.size,
				bar.position + Vector2(0, bar.size.y),
			]
		)
		RenderingServer.canvas_item_add_polygon(to_canvas_item, corners, PackedColorArray([accent]))
	var closed := points.duplicate()
	closed.append(points[0])
	RenderingServer.canvas_item_add_polyline(
		to_canvas_item, closed, PackedColorArray([border]), border_width, true
	)
