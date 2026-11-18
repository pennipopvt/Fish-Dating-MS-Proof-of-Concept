extends SceneTree

# Run: godot --headless --path . -s res://tests/sea_level_layout_test.gd
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node = MAIN.instantiate()
	get_root().add_child(main)
	await process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var player: Player = world.get_node("Player") as Player
	var guide: SeaEditorGuide = sea.get_node("EditorGuide") as SeaEditorGuide
	var solids: TileMapLayer = sea.get_node("Solids") as TileMapLayer
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	_check(sea.get_parent() == world and not sea.has_node("Player"), "One shared Player")
	_check(sea.has_node("BackgroundSprites") and sea.has_node("Details")
		and sea.has_node("ForegroundSprites"), "Empty sprite containers")
	_check(sea.get_node("BackgroundSprites").get_child_count() == 0
		and sea.get_node("Details").get_child_count() == 0
		and sea.get_node("ForegroundSprites").get_child_count() == 0, "No placeholder art")
	_check(not sea.has_node("Silas") and not sea.has_node("Combat")
		and not sea.has_node("FishSpawns") and not sea.has_node("NetProjectile"),
		"No active fish or combat systems")
	_check(solids.collision_enabled and solids.get_used_cells().is_empty(), "Empty collidable tilemap")
	_check(solids.tile_set != (world.get_node("Ground") as TileMapLayer).tile_set,
		"Independent sea collisions don't modify island tiles")
	_check(solids.tile_set.tile_size == Vector2i(16, 16)
		and solids.tile_set.get_physics_layer_collision_layer(0) == 2, "16px collision layer 2")
	var atlas: TileSetAtlasSource = solids.tile_set.get_source(0) as TileSetAtlasSource
	var tile: TileData = atlas.get_tile_data(Vector2i(0, 0), 0)
	_check(tile != null and tile.get_collision_polygons_count(0) > 0, "Painted wall has polygon")
	_check(sea.get_node("Points/Entry") is Marker2D
		and sea.get_node("Points/SurfaceExit") is Marker2D, "Only entry and exit markers")
	_check(sea.call("_sea_bounds").end == Vector2(904, 514), "Bounds match map size")
	guide.map_size = Vector2(1040, 620)
	sea.call("_set_camera_bounds", true)
	_check(camera.limit_right == 1040 and camera.limit_bottom == 620, "Camera can resize")
	sea.call("_set_camera_bounds", false)
	_check(camera.limit_right >= 10000000, "Land camera limits restored")
	main.queue_free()
	print("FAILED: %d" % failures if failures else "Blank sea layout passed")
	quit(1 if failures else 0)

func _check(ok: bool, description: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + description)
	if not ok:
		failures += 1
