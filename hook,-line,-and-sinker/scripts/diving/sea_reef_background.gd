extends Node2D

# Reef strip that follows the camera: always sits along the bottom of the
# screen, repeats sideways, and scrolls sideways slower than the play layer
# (parallax) so it reads as far away. Anything above the water surface is cut
# off, so it never shows over the sky or the land. Darken or tint it with this
# node's `modulate`. Sits behind the terrain (z_index -3 in the scene).

@export var texture: Texture2D = preload("res://sprites/environment/oceanJerry/OceanBackground/background.png")
## How much the reef moves sideways compared to the play layer:
## 1 = moves with the rocks, 0 = stuck to the screen. Lower reads as farther.
@export_range(0.0, 1.0) var parallax: float = 0.5
## Pixels to raise the strip above the screen bottom (negative lowers it).
@export var raise: float = 0.0
## Visible water surface y in the parent's space, used only when the World's
## `Water` node isn't found (same rule as the backdrop and bubbles).
@export var surface_y: float = 140.0


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
	# Whole pixels, so the strip doesn't shimmer while the camera moves.
	var top: float = roundf(view_pos.y + view_size.y - h - raise)
	var visible_top: float = maxf(top, ceilf(_surface_local_y()))
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
