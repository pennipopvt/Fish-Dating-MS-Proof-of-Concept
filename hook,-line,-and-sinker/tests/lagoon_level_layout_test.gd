extends SceneTree

# Godot integration test for the lagoon level-design authoring setup.
# Run through a Godot scene test runner with project autoloads enabled.
# The TileSet ships empty; collision polygons must be painted by the artist.
const LAGOON_SCENE: PackedScene = preload("res://scenes/diving_prototype.tscn")

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host: Control = LAGOON_SCENE.instantiate() as Control
	get_root().add_child(host)
	await process_frame

	var lagoon: DivingWorld = host.get_node(
		"SubViewportContainer/SubViewport/Lagoon"
	) as DivingWorld
	var guide: LagoonEditorGuide = lagoon.get_node("EditorGuide") as LagoonEditorGuide
	var water: TileMapLayer = lagoon.get_node("LevelArt/Water") as TileMapLayer
	var terrain: TileMapLayer = lagoon.get_node("LevelArt/Terrain") as TileMapLayer
	var details: TileMapLayer = lagoon.get_node("LevelArt/Details") as TileMapLayer
	var solids: TileMapLayer = lagoon.get_node("LevelArt/Solids") as TileMapLayer
	var overhangs: TileMapLayer = lagoon.get_node("ForegroundArt/Overhangs") as TileMapLayer
	var wall_cast: ShapeCast2D = lagoon.get_node("Player/WallCast") as ShapeCast2D
	var camera: Camera2D = lagoon.get_node("Camera2D") as Camera2D

	_check(guide != null and guide.grid_size == 16, "Editor guide uses a 16px tile grid")
	_check(guide.map_size == Vector2(920.0, 530.0), "Starting ocean footprint is preserved")
	_check(water != null and terrain != null and details != null
		and solids != null and overhangs != null,
		"Five dedicated water, terrain, details, solids and foreground paint layers exist")
	_check(water.tile_set != null and water.tile_set == terrain.tile_set
		and water.tile_set == details.tile_set
		and water.tile_set == solids.tile_set
		and water.tile_set == overhangs.tile_set,
		"All paint layers share one TileSet resource")
	_check(solids.tile_set.tile_size == Vector2i(16, 16),
		"Atlas grid is set for 16x16 underwater tiles")
	_check(solids.collision_enabled and not water.collision_enabled
		and not terrain.collision_enabled and not details.collision_enabled
		and not overhangs.collision_enabled,
		"Only the solid wall layer creates physical collisions")
	_check(solids.tile_set.get_physics_layers_count() == 1
		and solids.tile_set.get_physics_layer_collision_layer(0) == 2,
		"TileSet physics are isolated on layer 2")
	_check(wall_cast.shape is CircleShape2D and wall_cast.collision_mask == 2,
		"Existing Penni sprite uses the matching circular collision sweep")
	_check(lagoon.get_node("Points/Entry") is Marker2D
		and lagoon.get_node("Points/SurfaceExit") is Marker2D
		and lagoon.get_node("Points/SilasBurrow") is Marker2D
		and lagoon.get_node("Points/TangledNet") is Marker2D
		and lagoon.get_node("Points/ShellGarden") is Marker2D,
		"All story placements remain editor-managed markers")
	_check(lagoon.get_node("FishSpawns").get_child_count() >= 8,
		"Fish spawn placements remain editable without code changes")

	var initial: Rect2 = lagoon.call("_sea_bounds")
	_check(initial.position == Vector2(16.0, 30.0)
		and initial.end == Vector2(904.0, 490.0),
		"Initial playable bounds match the previously authored lagoon")

	guide.map_size = Vector2(1040.0, 620.0)
	lagoon.call("_set_camera_bounds", true)
	var resized: Rect2 = lagoon.call("_sea_bounds")
	_check(resized.end == Vector2(1024.0, 580.0),
		"Map Size simultaneously changes gameplay swimming bounds")
	_check(camera.limit_right == 1040 and camera.limit_bottom == 620,
		"Map Size simultaneously changes camera edges")
	guide.map_size = Vector2(920.0, 530.0)
	lagoon.call("_set_camera_bounds", true)

	host.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Lagoon authoring layout tests passed")
	quit(1 if failures > 0 else 0)


func _check(ok: bool, description: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + description)
	if not ok:
		failures += 1
