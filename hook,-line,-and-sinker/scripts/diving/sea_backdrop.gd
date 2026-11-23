extends Node2D

# Underwater backdrop that follows the camera: a vertical gradient across the
# screen, lighter at the top of the view and darker at the bottom. It moves
# with the view, so the colors stay the same at every depth. It never draws
# above the sea surface, so the sky still shows when the surface is on
# screen. It sits behind everything in the sea (z_index -4 in the scene, behind
# the shadow fish at -3 and the Background Terrain at -2).

## Color at the top of the screen.
@export var top_color: Color = Color(0.22, 0.47, 0.62, 1.0)
## Color at the bottom of the screen.
@export var bottom_color: Color = Color(0.05, 0.14, 0.28, 1.0)
## Above 1, the screen stays light longer and darkens near the bottom.
## Below 1, it darkens quickly from the top.
@export_range(0.3, 3.0) var curve: float = 1.0
## 0 = smooth. Otherwise the number of flat color bands (pixel-art look).
@export_range(0, 32) var bands: int = 0
## Sea surface y in the parent's space (DivingWorld.SEA_TOP). Nothing is
## drawn above it.
@export var surface_y: float = 154.0

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
	var surface: float = to_local(get_parent().to_global(Vector2(0.0, surface_y))).y \
			if get_parent() is Node2D else surface_y
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
