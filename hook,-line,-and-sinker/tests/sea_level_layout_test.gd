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
	var bubble: SeaSpeechBubble = main.get_node("SeaSpeechBubble") as SeaSpeechBubble
	var fish_list: Array = sea.get("_wild_fish")

	_check(sea.get_parent() == world and not sea.has_node("Player"),
		"Sea still shares one existing Player and camera")
	_check(solids.collision_enabled and solids.get_used_cells().size() > 0,
		"Rough solid-block seabed has actual painted collision tiles")
	_check(solids.tile_set != (world.get_node("Ground") as TileMapLayer).tile_set,
		"Sea wall physics remains separate from the island TileSet")
	_check(solids.tile_set.get_physics_layer_collision_layer(0) == 2,
		"Sea collision remains on layer 2")
	_check(sea.get_node("BackgroundSprites").get_child_count() == 2,
		"Two editable dock support placeholders exist")
	_check(sea.get_node("ForegroundSprites").get_child_count() == 3,
		"Three replaceable seaweed foreground sprites exist")
	_check(sea.get_node("FishSpawns").get_child_count() == 3,
		"Three species-defined editor fish spawn markers")
	_check(fish_list.size() == 4, "Three wild fish and one trapped Silas hit target")
	_check(sea.get_node("NPCs/Silas") is SeaNPC, "Silas is a reusable NPC scene actor")
	_check(sea.get_node("StoryDirector") is SeaStoryDirector,
		"One-time story conditions live outside core fishing")
	_check(sea.get_node("NetProjectile") is DivingNetProjectile
		and sea.get_node("Combat") is DivingCombat
		and sea.get_node("CompanionBattle") is DivingCompanionBattle,
		"Existing separate gameplay systems reused")
	_check(bubble.get_node("Call/Frame") is NinePatchRect,
		"Speech bubble frame is nine-slice replaceable")
	_check(bubble.get_node("Call/Message") is Label,
		"Pixel Operator speech bubble label is present")
	_check(sea.get_node("Points/Entry") is Marker2D
		and sea.get_node("Points/SurfaceExit") is Marker2D,
		"Entry and surface return markers persist")
	guide.map_size = Vector2(1040, 620)
	sea.call("_set_camera_bounds", true)
	_check((player.get_node("Camera2D") as Camera2D).limit_right == 1040,
		"Map size remains editor-driven")
	sea.call("_set_camera_bounds", false)

	main.queue_free()
	print("FAILED: %d" % failures if failures > 0 else "Sea storyboard layout tests passed")
	quit(1 if failures > 0 else 0)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
