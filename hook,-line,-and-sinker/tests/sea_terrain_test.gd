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
		"Editable closed Bezier curve exists in the preview scene")
	_check(fill.polygon.size() > terrain.curve.point_count
		and fill.polygon.size() == edge.points.size() - 1,
		"Curved polygon and continuous tiled edge are generated")
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
