@tool
extends Path2D
class_name SeaTerrain

# Editor-only authoring component. One closed Curve2D produces the textured
# sand fill, tiled edge strip, and the exact same static collision shape.
# This prototype is intentionally NOT connected to DivingWorld or its tiles.
@export var fill_texture: Texture2D:
	set(value):
		fill_texture = value
		if is_node_ready():
			_rebuild()

@export var edge_texture: Texture2D:
	set(value):
		edge_texture = value
		if is_node_ready():
			_rebuild()

@export_range(1.0, 64.0, 1.0) var edge_width: float = 16.0:
	set(value):
		edge_width = value
		if is_node_ready():
			_rebuild()

# The uploaded texture has a 4-pixel dark border along its TOP. Inset the
# centered 16px Line2D by half its width so its top meets the collision edge.
@export_range(-32.0, 32.0, 0.5) var edge_inset: float = 8.0:
	set(value):
		edge_inset = value
		if is_node_ready():
			_rebuild()

@onready var _fill: Polygon2D = $Fill
@onready var _edge: Line2D = $Edge
@onready var _collider: CollisionPolygon2D = $StaticBody2D/CollisionPolygon2D
var _watched_curve: Curve2D


func _ready() -> void:
	_connect_curve()
	_rebuild()
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	# Godot allows replacing the entire Curve2D resource in the Inspector.
	if curve != _watched_curve:
		_connect_curve()
		_rebuild()


func _exit_tree() -> void:
	if _watched_curve != null and _watched_curve.changed.is_connected(_rebuild):
		_watched_curve.changed.disconnect(_rebuild)


func _connect_curve() -> void:
	if _watched_curve != null and _watched_curve.changed.is_connected(_rebuild):
		_watched_curve.changed.disconnect(_rebuild)
	_watched_curve = curve
	if _watched_curve != null and not _watched_curve.changed.is_connected(_rebuild):
		_watched_curve.changed.connect(_rebuild)


func _rebuild() -> void:
	if not is_node_ready():
		return
	_fill.texture = fill_texture
	_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_edge.texture = edge_texture
	_edge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_edge.texture_mode = Line2D.LINE_TEXTURE_TILE
	_edge.width = edge_width
	_edge.antialiased = false

	if curve == null or curve.point_count < 3:
		_fill.polygon = PackedVector2Array()
		_edge.points = PackedVector2Array()
		_collider.polygon = PackedVector2Array()
		return

	var points: PackedVector2Array = curve.get_baked_points()
	# Path2D's Close Curve tool makes the final control point coincide with
	# the first. Polygon2D/CollisionPolygon2D want it only once.
	if points.size() > 2 and points[0].is_equal_approx(points[points.size() - 1]):
		points.remove_at(points.size() - 1)
	if points.size() < 3:
		return

	# Fill UVs are world-local coordinates, so the 16px sand tile repeats
	# instead of stretching across the whole polygon.
	_fill.polygon = points
	_fill.uv = points
	_collider.polygon = points

	# Offset the 16px textured strip into the solid, leaving its darker
	# top pixels on the collision contour. Works for either winding.
	var signed_area: float = 0.0
	for i in range(points.size()):
		signed_area += points[i].cross(points[(i + 1) % points.size()])
	var inside_sign: float = 1.0 if signed_area > 0.0 else -1.0
	var edge_points := PackedVector2Array()
	for i in range(points.size()):
		var prev: Vector2 = points[(i - 1 + points.size()) % points.size()]
		var next: Vector2 = points[(i + 1) % points.size()]
		var tangent: Vector2 = (next - prev).normalized()
		var inside: Vector2 = Vector2(-tangent.y, tangent.x) * inside_sign
		edge_points.append(points[i] + inside * edge_inset)
	edge_points.append(edge_points[0])
	_edge.points = edge_points
