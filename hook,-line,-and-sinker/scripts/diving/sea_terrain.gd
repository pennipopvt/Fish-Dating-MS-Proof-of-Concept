@tool
extends Path2D
class_name SeaTerrain

# One Curve2D drives a lightweight editor preview and runtime terrain.
# Expensive collision shapes are generated only when the scene runs.
# This prototype remains separate from DivingWorld and the existing tilemap.
const EDITOR_PREVIEW_INTERVAL_MS: int = 50
const EDITOR_PREVIEW_BAKE_SPACING: float = 4.0
@export var fill_texture: Texture2D:
	set(value):
		fill_texture = value
		if is_node_ready():
			_fill.texture = value

@export var edge_texture: Texture2D:
	set(value):
		edge_texture = value
		if is_node_ready():
			_edge.texture = value

@export_range(1.0, 64.0, 1.0) var edge_width: float = 16.0:
	set(value):
		edge_width = value
		if is_node_ready():
			_edge.width = value

# The uploaded texture has a darker outer border. A robust polygon inset
# keeps the 16px textured strip on the solid side of the collision curve.
# This is a distance, NOT a per-vertex offset (which twists at corners).
@export_range(-32.0, 32.0, 0.5) var edge_inset: float = 8.0:
	set(value):
		edge_inset = value
		if is_node_ready():
			_request_rebuild()

@onready var _fill: Polygon2D = $Fill
@onready var _edge: Line2D = $Edge
@onready var _collider: CollisionPolygon2D = $StaticBody2D/CollisionPolygon2D
var _watched_curve: Curve2D
var _preview_dirty: bool = false
var _last_preview_ms: int = -100000


func _ready() -> void:
	_connect_curve()
	_configure_art()
	_rebuild()
	# Inspector can replace the entire Curve2D; monitor only its identity.
	set_process(true)


func _process(_delta: float) -> void:
	if curve != _watched_curve:
		_connect_curve()
		_request_rebuild()
	if Engine.is_editor_hint() and _preview_dirty:
		var now: int = Time.get_ticks_msec()
		if now - _last_preview_ms >= EDITOR_PREVIEW_INTERVAL_MS:
			_preview_dirty = false
			_last_preview_ms = now
			_rebuild()


func _exit_tree() -> void:
	if _watched_curve != null and _watched_curve.changed.is_connected(_on_curve_changed):
		_watched_curve.changed.disconnect(_on_curve_changed)


func _connect_curve() -> void:
	if _watched_curve != null and _watched_curve.changed.is_connected(_on_curve_changed):
		_watched_curve.changed.disconnect(_on_curve_changed)
	_watched_curve = curve
	if _watched_curve != null and not _watched_curve.changed.is_connected(_on_curve_changed):
		_watched_curve.changed.connect(_on_curve_changed)


func _on_curve_changed() -> void:
	_request_rebuild()


func _request_rebuild() -> void:
	if not is_node_ready():
		return
	if Engine.is_editor_hint():
		# Curve2D emits 'changed' on every mouse move. Coalesce all handle
		# edits into one preview update per interval, never a physics update.
		_preview_dirty = true
	else:
		_rebuild()


func _configure_art() -> void:
	# Setting textures/flags on every mouse movement also forces redraws.
	# These only need to be configured once per scene instance.
	_fill.texture = fill_texture
	_fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_edge.texture = edge_texture
	_edge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_edge.texture_mode = Line2D.LINE_TEXTURE_TILE
	_edge.width = edge_width
	_edge.antialiased = false


func _rebuild() -> void:
	if not is_node_ready():
		return
	var points := PackedVector2Array()
	if curve != null and curve.point_count >= 3:
		points = _bake_closed_outline()
	if points.size() < 3:
		_fill.polygon = PackedVector2Array()
		_edge.points = PackedVector2Array()
		if not Engine.is_editor_hint():
			_collider.polygon = PackedVector2Array()
		return

	# The fill and collision share the same curve, but only the *running*
	# scene needs to build physics geometry. Editor drags avoid that work.
	_fill.polygon = points
	_fill.uv = points
	if not Engine.is_editor_hint():
		_collider.polygon = points

	# Geometry2D trims intersections at corners, unlike the original
	# averaged-normal vertex offset which could fold into giant triangles.
	# Line2D knows how to join a *closed* strip without a duplicate seam point.
	var outline: PackedVector2Array = points
	if not is_zero_approx(edge_inset):
		var inset_shapes: Array[PackedVector2Array] = Geometry2D.offset_polygon(
			points, -edge_inset, Geometry2D.JOIN_ROUND
		)
		if not inset_shapes.is_empty():
			var largest_area: float = 0.0
			for candidate in inset_shapes:
				var area: float = absf(_signed_area(candidate))
				if area > largest_area:
					largest_area = area
					outline = candidate
	# Keep the texture's dark TOP edge on the outside, regardless of the
	# direction in which the artist drew their Path2D.
	if _signed_area(outline) < 0.0:
		outline.reverse()
	_edge.points = outline
	_edge.closed = true


# Curve2D is an open Bézier resource, even when used for a solid polygon.
# For drawing, close the last point back to the first with a smooth cubic
# made from the endpoint's existing tangent handles. The editable curve
# needs no extra duplicate first/last control point that can split apart.
func _bake_closed_outline() -> PackedVector2Array:
	var source: Curve2D = curve
	var point_total: int = source.point_count
	# Fewer tessellation vertices while dragging; runtime retains the
	# authored bake interval for accurate geometry and collision.
	var sample_interval: float = source.bake_interval
	if Engine.is_editor_hint():
		sample_interval = maxf(sample_interval, EDITOR_PREVIEW_BAKE_SPACING)
	if source.get_point_position(0).is_equal_approx(
			source.get_point_position(point_total - 1)):
		var sample_source: Curve2D = source
		if sample_interval > source.bake_interval:
			sample_source = source.duplicate() as Curve2D
			sample_source.bake_interval = sample_interval
		var existing: PackedVector2Array = sample_source.get_baked_points()
		if existing.size() > 2 and existing[0].is_equal_approx(existing[existing.size() - 1]):
			existing.remove_at(existing.size() - 1)
		return existing

	var closed := Curve2D.new()
	closed.bake_interval = sample_interval
	for i in range(point_total):
		var incoming: Vector2 = source.get_point_in(i)
		var outgoing: Vector2 = source.get_point_out(i)
		# Godot exposes only the incoming handle at the last point.
		if i == point_total - 1 and outgoing.is_zero_approx():
			outgoing = -incoming
		closed.add_point(source.get_point_position(i), incoming, outgoing)
	var first_in: Vector2 = source.get_point_in(0)
	if first_in.is_zero_approx():
		first_in = -source.get_point_out(0)
	closed.add_point(source.get_point_position(0), first_in)
	var baked: PackedVector2Array = closed.get_baked_points()
	if baked.size() > 2 and baked[0].is_equal_approx(baked[baked.size() - 1]):
		baked.remove_at(baked.size() - 1)
	return baked


func _signed_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	for i in range(points.size()):
		area += points[i].cross(points[(i + 1) % points.size()])
	return area * 0.5
