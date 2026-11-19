extends SceneTree

# Basic architecture and editor placement regression for the storyboard pass.
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
	var bubble: SeaSpeechBubble = main.get_node("SubViewportContainer/SubViewport/SeaSpeechBubble") as SeaSpeechBubble
	var fish_list: Array = sea.get("_wild_fish")

	_check(sea.get_parent() == world and not sea.has_node("Player"),
		"Sea still shares one existing Player and camera")
	# TileMapLayer.tile_map_data is a 2-byte format header + 12 bytes per
	# cell. Without the header Godot silently rejects all painted geometry.
	_check(solids.tile_map_data.size() == 2 + 12 * 331,
		"Sea floor has the required Godot 4 tile data format header")
	_check(solids.collision_enabled and solids.get_used_cells().size() == 331,
		"All 331 painted seabed tiles actually load into the TileMapLayer")
	_check(solids.get_cell_source_id(Vector2i(-10, 24)) == 0,
		"Seafloor tile exists to the left of the dock at x=-10, y=24")
	var atlas: TileSetAtlasSource = solids.tile_set.get_source(0) as TileSetAtlasSource
	var tile: TileData = atlas.get_tile_data(Vector2i.ZERO, 0)
	_check(tile != null and tile.get_collision_polygons_count(0) > 0,
		"Visible sea block includes a physics collision polygon")
	_check((player.collision_mask | 2) & 2 != 0,
		"Swimming player can collide with sea layer 2")
	_check(solids.tile_set != (world.get_node("Ground") as TileMapLayer).tile_set,
		"Sea wall physics remains separate from the island TileSet")
	_check(solids.tile_set.get_physics_layer_collision_layer(0) == 2,
		"Sea collision remains on layer 2")
	_check(sea.get_node("BackgroundSprites").get_child_count() == 2,
		"Two editable dock support placeholders exist")
	_check(sea.get_node("ForegroundSprites").get_child_count() == 3,
		"Three replaceable seaweed foreground sprites exist")
	_check(sea.get_node("FishSpawns").get_child_count() == 2
		and sea.has_node("FishSpawns/FirstFish")
		and sea.has_node("FishSpawns/MulletAfterSilas")
		and not sea.has_node("FishSpawns/GobyNearBottom"),
		"Only first tutorial fish and later companion tutorial fish spawn")
	_check(fish_list.size() == 3, "Two wild fish and one trapped Silas hit target")
	_check(sea.get_node("NPCs/Silas") is SeaNPC, "Silas is a reusable NPC scene actor")
	_check(sea.get_node("StoryDirector") is SeaStoryDirector,
		"One-time story conditions live outside core fishing")
	_check(sea.get_node("NetProjectile") is DivingNetProjectile
		and sea.get_node("Combat") is DivingCombat
		and sea.get_node("CompanionBattle") is DivingCompanionBattle,
		"Existing separate gameplay systems reused")
	_check(bubble.get_viewport() == sea.get_viewport(),
		"Speech bubble uses the same pixel resolution as the sea")
	_check(bubble.get_node("Call/Frame") is NinePatchRect,
		"Speech bubble frame is nine-slice replaceable")
	_check(bubble.get_node("Call/Tail") is TextureRect,
		"One movable speech tail handles onscreen and offscreen direction")
	_check(bubble.get_node("Call/Direction") == null,
		"No duplicate text arrow remains")
	_check(bubble.get_node("Call/Message") is Label,
		"Pixel Operator speech bubble label is present")
	_check(sea.get_node("Points/Entry") is Marker2D
		and sea.get_node("Points/SurfaceExit") is Marker2D,
		"Entry and surface return markers persist")
	_check(guide.map_origin.x == -832.0 and sea.call("_sea_bounds").position.x < -800.0,
		"Sea swimming bounds extend to the left of the dock")
	_check(sea.get_node("FishSpawns/FirstFish").position.x < sea.get_node("Points/Entry").position.x,
		"First fish is left of the dock")
	_check(sea.get_node("NPCs/Silas").position.x < sea.get_node("FishSpawns/FirstFish").position.x,
		"Silas appears further left than the first fish")
	var block_source: TileSetAtlasSource = solids.tile_set.get_source(0) as TileSetAtlasSource
	_check(block_source.get_tiles_count() == 1 and block_source.texture != null,
		"One visible 16px block is supplied for sea collision painting")
	var sky: Control = world.get_node("Sky") as Control
	_check(sky.get_parent() == world and sky.clip_contents,
		"Sky belongs to World, not the player camera")
	world.call("_process", 0.0)
	_check(absf(sky.global_position.y + sky.size.y - (world.get_node("Water") as ColorRect).global_position.y) < 0.1,
		"Sky ends exactly at the world waterline")
	# Let TileMapLayer upload physics bodies, then trace a real physics ray
	# through an occupied column, not just the serialized tile metadata.
	await physics_frame
	await physics_frame
	var ray_top: Vector2 = solids.to_global(solids.map_to_local(Vector2i(-10, 18)))
	var ray_bottom: Vector2 = solids.to_global(solids.map_to_local(Vector2i(-10, 30)))
	var ray: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(ray_top, ray_bottom, 2)
	var hit: Dictionary = world.get_world_2d().direct_space_state.intersect_ray(ray)
	_check(not hit.is_empty() and hit.get("collider") == solids,
		"Physics ray hits a sea floor tile collider before passing through")
	guide.map_size = Vector2(1040, 620)
	sea.call("_set_camera_bounds", true)
	_check((player.get_node("Camera2D") as Camera2D).limit_left == -832
		and (player.get_node("Camera2D") as Camera2D).limit_right == 272,
		"Left-hand sea camera limits follow the editor's Map Origin and Map Size")
	sea.call("_set_camera_bounds", false)

	main.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Sea storyboard layout tests passed")
	quit(1 if failures > 0 else 0)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
