@tool
extends Node2D
class_name SeaSpawnRegion

# Draw this habitat right in the sea editor. The region is an area, not an
# exact spawn location; fish use their existing DivingWildFish movement.
@export var region_size: Vector2 = Vector2(220.0, 110.0):
	set(value):
		region_size = Vector2(maxf(24.0, value.x), maxf(24.0, value.y))
		queue_redraw()
@export_range(0, 30, 1) var population_count: int = 4
@export_range(10.0, 60.0, 1.0) var minimum_fish_spacing: float = 28.0
@export var species_options: Array[SeaSpawnOption] = []

@export_group("Free Swimming")
@export_range(0.0, 120.0, 1.0) var preferred_player_distance: float = 48.0
@export_range(0.0, 160.0, 1.0) var alert_distance: float = 74.0
@export_range(0.0, 180.0, 1.0) var flee_speed: float = 105.0


func local_spawn_rect() -> Rect2:
	return Rect2(Vector2.ZERO, region_size)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_rect(local_spawn_rect(), Color(0.22, 0.83, 0.90, 0.12), true)
	draw_rect(local_spawn_rect(), Color(0.22, 0.83, 0.90, 0.85), false, 1.0)
	draw_circle(Vector2.ZERO, 3.0, Color(0.22, 0.83, 0.90, 0.85))
