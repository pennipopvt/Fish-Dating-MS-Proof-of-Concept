@tool
extends Node2D
class_name SeaEditorGuide

# Editor-only guide; never draws prototype rocks or a fake seabed.
@export var map_origin: Vector2 = Vector2(-832.0, 0.0):
	set(value):
		map_origin = value
		queue_redraw()

@export var map_size: Vector2 = Vector2(1024.0, 530.0):
	set(value):
		map_size = Vector2(maxf(320.0, value.x), maxf(240.0, value.y))
		queue_redraw()
@export_range(8, 64, 8) var grid_size: int = 16:
	set(value):
		grid_size = value
		queue_redraw()
@export var show_grid: bool = true:
	set(value):
		show_grid = value
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if show_grid:
		var line_color := Color(0.54, 0.77, 0.83, 0.10)
		for x in range(int(map_origin.x), int(map_origin.x + map_size.x) + 1, maxi(grid_size, 1)):
			draw_line(Vector2(x, map_origin.y), Vector2(x, map_origin.y + map_size.y), line_color, 1.0)
		for y in range(int(map_origin.y), int(map_origin.y + map_size.y) + 1, maxi(grid_size, 1)):
			draw_line(Vector2(map_origin.x, y), Vector2(map_origin.x + map_size.x, y), line_color, 1.0)
	draw_rect(Rect2(map_origin, map_size), Color(0.58, 0.91, 0.89, 0.7), false, 1.0)
