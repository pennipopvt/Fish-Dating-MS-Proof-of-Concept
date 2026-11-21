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
	_check(not terrain.curve.get_point_position(0).is_equal_approx(
		terrain.curve.get_point_position(terrain.curve.point_count - 1)),
		"Closed terrain has no duplicate first/last control point to split when dragging")
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
	preview.queue_free()
	await get_tree().process_frame
	print("sea_terrain_test: PASS" if failures == 0 else
		"sea_terrain_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
