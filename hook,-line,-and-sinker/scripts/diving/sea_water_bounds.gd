@tool
extends ColorRect
class_name SeaWaterBounds

# Same Water shader/material and waterline; only its rectangular coverage
# is derived from the sea editor guide. Works at runtime and when editing
# prefabs/world.tscn. Designers now change just Sea/EditorGuide.
@export var guide_path: NodePath = ^"../Sea/EditorGuide"
@export_range(0.0, 1024.0, 1.0) var left_overdraw: float = 260.0
@export_range(0.0, 1024.0, 1.0) var bottom_overdraw: float = 40.0
# Preserve the original water coverage below the land and distant beach.
@export var shoreline_right_x: float = 2800.0
@export var surface_y: float = 140.0

var _guide: SeaEditorGuide


func _ready() -> void:
	_guide = get_node_or_null(guide_path) as SeaEditorGuide
	if _guide == null:
		push_warning("Water requires its sibling Sea/EditorGuide.")
		return
	if not _guide.bounds_changed.is_connected(_update_bounds):
		_guide.bounds_changed.connect(_update_bounds)
	_update_bounds()


func _update_bounds() -> void:
	if not is_instance_valid(_guide):
		return
	# Convert the sea guide's corners into this Water node's parent space.
	# This also handles moving the entire Sea instance in the world later.
	var parent_2d: Node2D = get_parent() as Node2D
	if parent_2d == null:
		return
	var a: Vector2 = parent_2d.to_local(_guide.to_global(_guide.map_origin))
	var b: Vector2 = parent_2d.to_local(
		_guide.to_global(_guide.map_origin + _guide.map_size))
	var left: float = minf(a.x, b.x) - left_overdraw
	var right: float = maxf(maxf(a.x, b.x), shoreline_right_x)
	var bottom: float = maxf(a.y, b.y) + bottom_overdraw
	position = Vector2(left, surface_y)
	size = Vector2(maxf(320.0, right - left),
		maxf(180.0, bottom - surface_y))
