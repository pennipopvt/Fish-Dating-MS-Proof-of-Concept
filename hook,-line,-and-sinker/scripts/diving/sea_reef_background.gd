extends Node2D

# Reef strip that follows the camera: always sits along the bottom of the
# screen, repeats sideways, and scrolls sideways slower than the play layer
# (parallax) so it reads as far away. Its height follows the camera's depth:
# near the surface it sits mostly below the screen edge (only the coral tops
# peek in), and it rises as you go deeper, with a band of its own sand filling
# the space under it. That also gives a gentle vertical parallax while
# swimming up or down. Anything above the water surface is cut off, so it
# never shows over the sky or the land. Darken or tint it with this node's
# `modulate`. Sits behind the terrain (z_index -3 in the scene).

@export var texture: Texture2D = preload("res://sprites/environment/oceanJerry/OceanBackground/background.png")
## How much the reef moves sideways compared to the play layer:
## 1 = moves with the rocks, 0 = stuck to the screen. Lower reads as farther.
@export_range(0.0, 1.0) var parallax: float = 0.5
## Pixels the strip sits below the screen bottom when the view is at the
## surface (the strip is 100px tall; its art starts ~27px down).
@export var sink_at_surface: float = 55.0
## Pixels the strip rises above the screen bottom when the view reaches the
## bottom of the sea. The gap below it is filled with sand.
@export var rise_at_floor: float = 16.0
## Above 1, the reef stays low longer and rises mostly near the bottom.
@export_range(0.3, 3.0) var rise_curve: float = 1.0
## Sand under the strip. Alpha 0 = use the strip's bottom-row color.
@export var sand_color: Color = Color(0, 0, 0, 0)
## Bottom of the sea in the parent's space. 0 = read from the sibling
## EditorGuide (the same bounds the sea camera is limited to).
@export var sea_bottom_y: float = 0.0
## Visible water surface y in the parent's space, used only when the World's
## `Water` node isn't found (same rule as the backdrop and bubbles).
@export var surface_y: float = 140.0


var _sand: Color = Color(1.0, 0.94, 0.75)


func _ready() -> void:
	if sea_bottom_y <= 0.0:
		var guide: Node = get_parent().get_node_or_null("EditorGuide") if get_parent() != null else null
		if guide != null and "map_origin" in guide and "map_size" in guide:
			var origin: Vector2 = guide.get("map_origin")
			var size: Vector2 = guide.get("map_size")
			sea_bottom_y = origin.y + size.y
		else:
			sea_bottom_y = 760.0
	_sand = sand_color
	if _sand.a <= 0.0 and texture != null:
		var image: Image = texture.get_image()
		if image != null:
			_sand = _most_common_color(image, image.get_height() - 1)


func _process(_delta: float) -> void:
	# The view moves every frame.
	queue_redraw()


func _draw() -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null or texture == null:
		return
	var view_size: Vector2 = get_viewport_rect().size / camera.zoom.abs()
	var view_pos: Vector2 = to_local(camera.get_screen_center_position() - view_size * 0.5)
	var w: float = float(texture.get_width())
	var h: float = float(texture.get_height())
	var surface: float = _surface_local_y()
	var view_bottom: float = view_pos.y + view_size.y
	# 0 with the view's top at the surface, 1 with its bottom at the sea floor.
	var travel: float = maxf(sea_bottom_y - surface - view_size.y, 1.0)
	var depth: float = clampf((view_pos.y - surface) / travel, 0.0, 1.0)
	var lift: float = lerpf(-sink_at_surface, rise_at_floor, pow(depth, rise_curve))
	# Whole pixels, so the strip doesn't shimmer while the camera moves.
	var top: float = roundf(view_bottom - h - lift)
	var visible_top: float = maxf(top, ceilf(surface))
	# Sand fills everything between the strip's bottom and the screen bottom.
	var sand_top: float = maxf(top + h, visible_top)
	if sand_top < view_bottom:
		draw_rect(Rect2(view_pos.x - 2.0, sand_top, view_size.x + 4.0,
				view_bottom - sand_top + 2.0), _sand)
	if visible_top >= top + h:
		return
	var cut: float = visible_top - top
	# Screen x where a tile starts, moving at `parallax` of the camera speed.
	var start: float = fposmod(-view_pos.x * parallax, w) - w
	var x: float = start
	while x < view_size.x:
		var at := Vector2(roundf(view_pos.x + x), visible_top)
		draw_texture_rect_region(texture, Rect2(at, Vector2(w, h - cut)),
				Rect2(0.0, cut, w, h - cut))
		x += w


func _surface_local_y() -> float:
	var sea: Node = get_parent()
	var world: Node = sea.get_parent() if sea != null else null
	var water: CanvasItem = world.get_node_or_null("Water") as CanvasItem if world != null else null
	if water != null:
		return to_local(water.get_global_transform().origin).y
	if sea is Node2D:
		return to_local((sea as Node2D).to_global(Vector2(0.0, surface_y))).y
	return surface_y


func _most_common_color(image: Image, row: int) -> Color:
	var counts: Dictionary = {}
	var best: Color = Color(1.0, 0.94, 0.75)
	var best_count: int = 0
	for x in image.get_width():
		var c: Color = image.get_pixel(x, row)
		if c.a < 0.5:
			continue
		var n: int = int(counts.get(c, 0)) + 1
		counts[c] = n
		if n > best_count:
			best_count = n
			best = c
	return best
