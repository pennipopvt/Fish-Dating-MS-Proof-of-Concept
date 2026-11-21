@tool
extends Path2D
class_name SeaTerrain

# One Curve2D drives a lightweight editor preview and runtime terrain.
# Expensive collision shapes are generated only when the scene runs.
# This prototype remains separate from DivingWorld and the existing tilemap.
const EDITOR_PREVIEW_INTERVAL_MS: int = 50
const EDITOR_PREVIEW_BAKE_SPACING: float = 4.0
const AUTO_HANDLE_RATIO: float = 0.25
const MIN_AUTO_HANDLE_LENGTH: float = 3.0
# Wait for the native Path2D editor to finish a mouse edit before modifying
# control points, avoiding fights with its active drag/UndoRedo operation.
const EDITOR_CURVE_SETTLE_MS: int = 110
@export_group("Appearance")
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

# Both toggles affect only this SeaTerrain instance. The spline, fill
# texture and author-edited curve stay intact when either is off.
@export var show_edge_texture: bool = true:
	set(value):
		show_edge_texture = value
		if is_node_ready():
			_edge.visible = value


@export_group("Collision")
# Keep a disabled polygon available at runtime so turning collision back
# on does not require rebuilding geometry or recaching fish queries.
@export var collision_enabled: bool = true:
	set(value):
		collision_enabled = value
		if is_node_ready():
			_collider.disabled = not value


@onready var _fill: Polygon2D = $Fill
@onready var _edge: Line2D = $Edge
@onready var _collider: CollisionPolygon2D = $StaticBody2D/CollisionPolygon2D
var _watched_curve: Curve2D
var _preview_dirty: bool = false
var _last_preview_ms: int = -100000
var _last_positions: PackedVector2Array = PackedVector2Array()
var _normalizing: bool = false
var _normalization_pending: bool = false
var _last_curve_edit_ms: int = 0


func _ready() -> void:
	_connect_curve()
	_normalize_closed_curve()
	_configure_art()
	_edge.visible = show_edge_texture
	_collider.disabled = not collision_enabled
	_rebuild()
	# Inspector can replace the entire Curve2D; monitor only its identity.
	set_process(true)


func _process(_delta: float) -> void:
	if curve != _watched_curve:
		_connect_curve()
		_queue_normalization()
		_request_rebuild()
	if Engine.is_editor_hint() and _normalization_pending:
		if Time.get_ticks_msec() - _last_curve_edit_ms >= EDITOR_CURVE_SETTLE_MS:
			_normalization_pending = false
			_normalize_closed_curve()
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
	# A newly assigned Curve2D is its own shape, not an insertion into the
	# previous one. Don't autosmooth all of an artist's existing vertices.
	_last_positions = PackedVector2Array()
	if _watched_curve != null and not _watched_curve.changed.is_connected(_on_curve_changed):
		_watched_curve.changed.connect(_on_curve_changed)


func _on_curve_changed() -> void:
	if _normalizing:
		return
	_queue_normalization()
	_request_rebuild()


func _queue_normalization() -> void:
	if Engine.is_editor_hint():
		_normalization_pending = true
		_last_curve_edit_ms = Time.get_ticks_msec()
	else:
		_normalize_closed_curve()


# Keep the ACTUAL Path2D curve closed, not merely its generated polygon.
# Godot represents a loop with an extra last point at the first position.
# This also gives artists the native closed cyan editor line.
func _normalize_closed_curve() -> void:
	if _normalizing or curve == null or curve.point_count < 3:
		return
	_normalizing = true
	var previous_count: int = _last_positions.size()
	var count: int = curve.point_count
	var inserted_at: int = -1

	if previous_count > 0 and count > previous_count:
		# Adding a point at the end of a closed path places it AFTER Godot's
		# closing duplicate. Move it before the seam to preserve the loop.
		if count == previous_count + 1 and curve.get_point_position(count - 2).is_equal_approx(
				curve.get_point_position(0)):
			var new_position: Vector2 = curve.get_point_position(count - 1)
			var new_in: Vector2 = curve.get_point_in(count - 1)
			var new_out: Vector2 = curve.get_point_out(count - 1)
			curve.remove_point(count - 1)
			curve.add_point(new_position, new_in, new_out, count - 2)
			inserted_at = count - 2
		else:
			# Covers the native Insert Point command on an existing segment.
			for i in range(mini(count - 1, previous_count)):
				if not curve.get_point_position(i).is_equal_approx(_last_positions[i]):
					inserted_at = i
					break

	count = curve.point_count
	var first: Vector2 = curve.get_point_position(0)
	var last: Vector2 = curve.get_point_position(count - 1)
	if not first.is_equal_approx(last):
		if previous_count == count and previous_count > 2:
			var first_was_moved: bool = not first.is_equal_approx(_last_positions[0])
			var last_was_moved: bool = not last.is_equal_approx(_last_positions[previous_count - 1])
			if last_was_moved and not first_was_moved:
				# Dragging the seam's final point moves the first point too.
				curve.set_point_position(0, last)
			else:
				curve.set_point_position(count - 1, first)
		else:
			# New/legacy open curves get a real closing segment. This is
			# a single, native Path2D control point, not a second terrain.
			var seam_in: Vector2 = curve.get_point_in(0)
			if seam_in.is_zero_approx():
				seam_in = -curve.get_point_out(0)
			curve.add_point(first, seam_in)
			count += 1

	# Existing handles are artist-authored; only NEW, handle-less points
	# receive automatic smooth tangents by default.
	if inserted_at >= 0 and inserted_at < count - 1:
		_autosmooth_new_point(inserted_at)
	elif previous_count > 0 and count > previous_count and inserted_at < 0:
		# Appending before the seam can preserve every preceding index.
		_autosmooth_new_point(count - 2)

	_snapshot_curve_positions()
	_normalizing = false


func _autosmooth_new_point(index: int) -> void:
	var count: int = curve.point_count
	if index <= 0 or index >= count - 1:
		return
	if not curve.get_point_in(index).is_zero_approx() or not curve.get_point_out(index).is_zero_approx():
		return
	var point: Vector2 = curve.get_point_position(index)
	var before: Vector2 = curve.get_point_position(index - 1)
	var after: Vector2 = curve.get_point_position(index + 1)
	var forward: Vector2 = (after - before).normalized()
	if forward.is_zero_approx():
		return
	var in_length: float = maxf(MIN_AUTO_HANDLE_LENGTH, before.distance_to(point) * AUTO_HANDLE_RATIO)
	var out_length: float = maxf(MIN_AUTO_HANDLE_LENGTH, point.distance_to(after) * AUTO_HANDLE_RATIO)
	curve.set_point_in(index, -forward * in_length)
	curve.set_point_out(index, forward * out_length)


func _snapshot_curve_positions() -> void:
	_last_positions = PackedVector2Array()
	for i in range(curve.point_count):
		_last_positions.append(curve.get_point_position(i))


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
