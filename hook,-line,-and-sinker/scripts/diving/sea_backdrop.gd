extends Node2D

# Underwater backdrop that follows the camera: a vertical gradient across the
# screen, lighter at the top of the view and darker at the bottom. It moves
# with the view, so the colors stay the same at every depth. It never draws
# above the sea surface, so the sky still shows when the surface is on
# screen. It sits behind everything in the sea (z_index -4 in the scene, behind
# the shadow fish at -3 and the Background Terrain at -2).

## Colors are calibrated against the rendered screen at daytime (afternoon
## clock), after the water and underwater tints draw over this node: on
## screen, color = gain * backdrop + offset per channel, gain (0.569, 0.588,
## 0.608), offset (0.063, 0.176, 0.255). Targets (Penni's request: a bright
## blue near the top): top (80,150,195), bottom (45,105,140), so mid-screen is
## about the original sea color with no backdrop (58,130,171). (#40779a at
## mid-screen would be top (0.41,0.637,0.753), bottom (0.251,0.351,0.395).)
## To pick a new on-screen color S, use backdrop = (S - offset) / gain.
## Color at the top of the screen.
@export var top_color: Color = Color(0.441, 0.701, 0.838, 1.0)
## Color at the bottom of the screen.
@export var bottom_color: Color = Color(0.199, 0.401, 0.484, 1.0)
## Above 1, the screen stays light longer and darkens near the bottom.
## Below 1, it darkens quickly from the top. Keep 1.0 so mid-screen stays halfway.
@export_range(0.3, 3.0) var curve: float = 1.0
## 0 = smooth. Otherwise the number of flat color bands (pixel-art look).
@export_range(0, 32) var bands: int = 0
## Visible water surface y in the parent's space, used only when the World's
## `Water` node isn't found. Nothing is drawn above it. (Not SEA_TOP 154:
## that's how high Penni can swim; the water's drawn top is 140.)
@export var surface_y: float = 140.0

const STRIPS: int = 45


func _process(_delta: float) -> void:
	# The view moves every frame, so redraw every frame (one cheap gradient).
	queue_redraw()


func _draw() -> void:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return
	var view_size: Vector2 = get_viewport_rect().size / camera.zoom.abs()
	var view_top_left: Vector2 = camera.get_screen_center_position() - view_size * 0.5
	# Draw in this node's local space; pad a few pixels so edges never show.
	var top_left: Vector2 = to_local(view_top_left) - Vector2(4.0, 4.0)
	var size: Vector2 = view_size + Vector2(8.0, 8.0)
	var surface: float = _surface_local_y()
	var steps: int = bands if bands > 0 else STRIPS
	for i in steps:
		var y0: float = top_left.y + size.y * float(i) / steps
		var y1: float = top_left.y + size.y * float(i + 1) / steps
		if y1 <= surface:
			continue
		y0 = maxf(y0, surface)
		# Smooth: color at the strip's middle. Bands: evenly from top to bottom.
		var t: float = (float(i) + 0.5) / steps if bands == 0 \
				else float(i) / maxf(float(steps - 1), 1.0)
		var color: Color = top_color.lerp(bottom_color, pow(t, curve))
		draw_rect(Rect2(top_left.x, y0, size.x, y1 - y0 + 0.5), color)


# Start exactly at the water's drawn top (World/Water), so no strip of the
# old background shows between the surface and the backdrop.
func _surface_local_y() -> float:
	var sea: Node = get_parent()
	var world: Node = sea.get_parent() if sea != null else null
	var water: CanvasItem = world.get_node_or_null("Water") as CanvasItem if world != null else null
	if water != null:
		return to_local(water.get_global_transform().origin).y
	if sea is Node2D:
		return to_local((sea as Node2D).to_global(Vector2(0.0, surface_y))).y
	return surface_y
