extends SceneTree

# Godot integration test for the lagoon level-design authoring setup.
# Run through a Godot scene test runner with project autoloads enabled.
# Lagoon tiles use the existing island atlas; collision polygons still need testing.
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var host: Control = MAIN_SCENE.instantiate() as Control
	get_root().add_child(host)
	await process_frame

	var world: Node2D = host.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var lagoon: DivingWorld = world.get_node("Lagoon") as DivingWorld
	var guide: LagoonEditorGuide = lagoon.get_node("EditorGuide") as LagoonEditorGuide
	var background_sprites: Node2D = lagoon.get_node("LevelArt/BackgroundSprites") as Node2D
	var details: Node2D = lagoon.get_node("LevelArt/Details") as Node2D
	var solids: TileMapLayer = lagoon.get_node("LevelArt/Solids") as TileMapLayer
	var foreground_sprites: Node2D = lagoon.get_node("ForegroundArt") as Node2D
	var player: Player = world.get_node("Player") as Player
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D

	_check(guide != null and guide.grid_size == 16, "Editor guide uses a 16px tile grid")
	_check(guide.map_size == Vector2(920.0, 530.0), "Starting ocean footprint is preserved")
	_check(background_sprites != null and details != null
		and solids != null and foreground_sprites != null,
		"Background, details, solid walls and foreground groups are present")
	_check(background_sprites.get_class() == "Node2D"
		and details.get_class() == "Node2D"
		and foreground_sprites.get_class() == "Node2D",
		"Non-wall artwork uses regular Node2D containers for standalone PNG sprites")
	_check(lagoon.get_node("LevelArt").get_children().filter(
		func(node: Node) -> bool: return node is TileMapLayer
	).size() == 1 and solids is TileMapLayer,
		"Exactly one paintable TileMapLayer remains for solid walls")
	_check(solids.tile_set != null and solids.tile_set.tile_size == Vector2i(16, 16),
		"Solid wall TileSet uses 16x16 cells")
	_check(solids.collision_enabled,
		"Wall layer creates physical collisions")
	_check(solids.tile_set.get_physics_layers_count() == 1
		and solids.tile_set.get_physics_layer_collision_layer(0) == 2,
		"TileSet physics are isolated on layer 2")
	_check(lagoon.player_sprite == player and lagoon.camera == camera
		and not lagoon.has_node("Player"),
		"One shared Player and camera are used for both island and diving")
	_check(solids.tile_set == (world.get_node("Ground") as TileMapLayer).tile_set,
		"Underwater wall layer reuses the original beach TileSet resource")
	_check(lagoon.get_node("Points/Entry") is Marker2D
		and lagoon.get_node("Points/SurfaceExit") is Marker2D
		and lagoon.get_node("Points/SilasBurrow") is Marker2D
		and lagoon.get_node("Points/TangledNet") is Marker2D
		and lagoon.get_node("Points/ShellGarden") is Marker2D,
		"All story placements remain editor-managed markers")
	_check(lagoon.get_node("FishSpawns").get_child_count() >= 8,
		"Fish spawn placements remain editable without code changes")

	var initial: Rect2 = lagoon.call("_sea_bounds")
	_check(initial.position == Vector2(16.0, 154.0)
		and initial.end == Vector2(904.0, 514.0),
		"Underwater swimming bounds begin below the visible waterline")

	guide.map_size = Vector2(1040.0, 620.0)
	lagoon.call("_set_camera_bounds", true)
	var resized: Rect2 = lagoon.call("_sea_bounds")
	_check(resized.end == Vector2(1024.0, 604.0),
		"Map Size simultaneously changes gameplay swimming bounds")
	_check(camera.limit_right == 1040 and camera.limit_bottom == 620,
		"Map Size simultaneously changes the shared camera limits")
	guide.map_size = Vector2(920.0, 530.0)
	lagoon.call("_set_camera_bounds", false)
	_check(camera.limit_right >= 10000000,
		"Land camera remains free to follow the island after diving")

	host.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Lagoon authoring layout tests passed")
	quit(1 if failures > 0 else 0)


func _check(ok: bool, description: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + description)
	if not ok:
		failures += 1
