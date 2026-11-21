extends Node

const PREVIEW: PackedScene = preload("res://scenes/sea_terrain_preview.tscn")
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var preview: Control = PREVIEW.instantiate() as Control
	add_child(preview)
	await get_tree().process_frame
	var terrain: SeaTerrain = preview.get_node(
		"SubViewportContainer/SubViewport/World/Terrain") as SeaTerrain
	var fill: Polygon2D = terrain.get_node("Fill") as Polygon2D
	var edge: Line2D = terrain.get_node("Edge") as Line2D
	var collider: CollisionPolygon2D = terrain.get_node(
		"StaticBody2D/CollisionPolygon2D") as CollisionPolygon2D
	_check(terrain.curve != null and terrain.curve.point_count >= 3,
		"Editable Bezier curve exists in the preview scene")
	_check(terrain.curve.get_point_position(0).is_equal_approx(
		terrain.curve.get_point_position(terrain.curve.point_count - 1)),
		"Editable Path2D has a real closing control point and visible closed curve")
	_check(fill.polygon.size() > terrain.curve.point_count
		and edge.points.size() >= 3 and edge.closed,
		"Smooth filled polygon and truly closed native Line2D strip are generated")
	_check(collider.polygon == fill.polygon and fill.uv == fill.polygon,
		"Exact same baked outline drives both UV-mapped art and collisions")
	_check(edge.texture != null and edge.texture.get_width() == 16
		and edge.texture.get_height() == 16
		and fill.texture != null and fill.texture.get_width() == 16,
		"Uploaded 16px sand assets are referenced by the terrain")
	_check(edge.texture_mode == Line2D.LINE_TEXTURE_TILE
		and edge.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED
		and fill.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED,
		"Textures repeat along the curve and across the fill")
	_check((collider.get_parent() as StaticBody2D).collision_layer == 2,
		"Collision uses the same layer as the existing solid sea tiles")
	# Godot appends new points after its closing duplicate. The terrain
	# component must move the new point before that duplicate and add handles.
	var before_append: int = terrain.curve.point_count
	var first_anchor: Vector2 = terrain.curve.get_point_position(0)
	terrain.curve.add_point(Vector2(40, -25))
	await get_tree().process_frame
	var last_index: int = terrain.curve.point_count - 1
	_check(terrain.curve.point_count == before_append + 1
		and terrain.curve.get_point_position(last_index).is_equal_approx(first_anchor)
		and terrain.curve.get_point_position(last_index - 1) == Vector2(40, -25),
		"Adding a control point keeps the actual Path2D loop closed")
	_check(not terrain.curve.get_point_in(last_index - 1).is_zero_approx()
		and not terrain.curve.get_point_out(last_index - 1).is_zero_approx(),
		"Newly placed control points automatically receive both Bezier handles")
	var inserted_at: int = 2
	var old_count: int = terrain.curve.point_count
	terrain.curve.add_point(Vector2(-92, -33), Vector2.ZERO, Vector2.ZERO, inserted_at)
	await get_tree().process_frame
	_check(terrain.curve.point_count == old_count + 1
		and not terrain.curve.get_point_in(inserted_at).is_zero_approx()
		and not terrain.curve.get_point_out(inserted_at).is_zero_approx(),
		"Inserting a point along an existing segment also defaults to smooth handles")
	var shifted_first: Vector2 = terrain.curve.get_point_position(0) + Vector2(-8, 6)
	terrain.curve.set_point_position(0, shifted_first)
	await get_tree().process_frame
	_check(terrain.curve.get_point_position(terrain.curve.point_count - 1)
		.is_equal_approx(shifted_first),
		"Dragging the first seam point keeps the editor curve closed")
	_check(collider.polygon == fill.polygon,
		"Collision and fill stay synchronized after adding/moving control points")
	_check(terrain._signed_area(edge.points) > 0.0,
		"Edge always winds with its darker texture side facing outside")
	var inside_edges: bool = true
	for point in edge.points:
		if not Geometry2D.is_point_in_polygon(point, fill.polygon):
			inside_edges = false
	_check(inside_edges,
		"Rounded polygon inset keeps edge vertices inside the solid at corners")
	# A right-angled concave notch used to create a huge offset-line spike.
	var shape := Curve2D.new()
	shape.add_point(Vector2(-90, 70))
	shape.add_point(Vector2(-90, -10))
	shape.add_point(Vector2(-10, -10))
	shape.add_point(Vector2(-10, 25))
	shape.add_point(Vector2(10, 25))
	shape.add_point(Vector2(10, -10))
	shape.add_point(Vector2(90, -10))
	shape.add_point(Vector2(90, 70))
	terrain.curve = shape
	await get_tree().process_frame
	inside_edges = not edge.points.is_empty()
	for point in edge.points:
		if not Geometry2D.is_point_in_polygon(point, fill.polygon):
			inside_edges = false
	_check(edge.closed and inside_edges
		and collider.polygon == fill.polygon,
		"Sharp concave corners retain an inset edge and identical fill/collision")
	var old_polygon: PackedVector2Array = fill.polygon.duplicate()
	var original: Vector2 = terrain.curve.get_point_position(1)
	terrain.curve.set_point_position(1, original + Vector2(0.0, -18.0))
	await get_tree().process_frame
	_check(old_polygon != fill.polygon and collider.polygon == fill.polygon,
		"Changing a Bezier control point updates art and collision together")
	# Physics must remain precise in the running game even though editor
	# drags intentionally omit collision-generation work.
	for i in range(12):
		terrain.curve.set_point_position(1, original + Vector2(i, -18.0 - i))
	_check(collider.polygon == fill.polygon and collider.polygon.size() > 3,
		"Runtime curve changes still update collider on every edit")
	preview.queue_free()
	await get_tree().process_frame
	print("sea_terrain_test: PASS" if failures == 0 else
		"sea_terrain_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
