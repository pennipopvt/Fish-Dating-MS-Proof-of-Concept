@tool
extends Node2D
class_name SeaEditorGuide

# Single source of truth for sea dimensions, with an editor-only footprint
# and paint grid. Camera and gameplay bounds read this node at runtime.
@export var map_size: Vector2 = Vector2(920.0, 530.0):
	set(value):
		map_size = Vector2(maxf(320.0, value.x), maxf(180.0, value.y))
		queue_redraw()
@export_range(8, 64, 8) var grid_size: int = 16:
	set(value):
		grid_size = value
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_rect(Rect2(Vector2.ZERO, map_size), Color(0.06, 0.22, 0.32, 0.55))
	var line_color := Color(0.54, 0.77, 0.83, 0.10)
	for x in range(0, int(map_size.x) + 1, maxi(grid_size, 1)):
		draw_line(Vector2(x, 0), Vector2(x, map_size.y), line_color, 1.0)
	for y in range(0, int(map_size.y) + 1, maxi(grid_size, 1)):
		draw_line(Vector2(0, y), Vector2(map_size.x, y), line_color, 1.0)
	draw_rect(Rect2(Vector2.ZERO, map_size), Color(0.58, 0.91, 0.89, 0.75), false, 2.0)
