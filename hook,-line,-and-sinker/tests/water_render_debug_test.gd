extends Node

# Exercises every Backslash diagnostic mode without changing production render state.
# Run: godot --headless --path . res://tests/water_render_debug_test.tscn
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	var debug: WaterRenderDebug = main.get_node("WaterDebugLayer") as WaterRenderDebug
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var water: ColorRect = world.get_node("Water") as ColorRect
	var solids: TileMapLayer = world.get_node_or_null("Sea/Solids") as TileMapLayer
	var sea: Node2D = world.get_node("Sea") as Node2D
	var ground: TileMapLayer = world.get_node("Ground") as TileMapLayer
	var ground_front: TileMapLayer = world.get_node("GroundFront") as TileMapLayer
	_check(water.z_index > ground_front.z_index
		and (solids == null or water.z_index > solids.z_index),
		"Runtime World/Water draws above ground and any legacy Solids tiles")
	var normal_water: Material = water.material
	var normal_clip: Material = solids.material if solids != null else null
	var normal_color: Color = water.color
	_check(not debug.visible, "Backslash debug starts hidden")
	_check(debug.handle_input(_key(KEY_BACKSLASH)) and debug.visible,
		"Backslash opens separate diagnostics without modifying the water")
	_check(debug.mode == 0 and water.material == normal_water
		and (solids == null or solids.material == normal_clip),
		"Mode 1 is unmodified gameplay")
	debug.handle_input(_key(KEY_2))
	_check(not sea.visible and water.visible, "Mode 2 hides only the sea visuals")
	debug.handle_input(_key(KEY_3))
	_check(sea.visible and not ground.visible and not ground_front.visible,
		"Mode 3 isolates land tiles; previous mode is restored")
	debug.handle_input(_key(KEY_4))
	_check(not water.visible and ground.visible and ground_front.visible,
		"Mode 4 hides only the water overlay")
	debug.handle_input(_key(KEY_5))
	_check(water.visible and water.material == null and water.color == Color(1, 0, 1, 1),
		"Mode 5 makes water coverage unambiguously magenta")
	debug.handle_input(_key(KEY_6))
	_check((solids == null or solids.material == null) and water.material == normal_water,
		"Mode 6 preserves the normal water shader without requiring removed tiles")
	debug.handle_input(_key(KEY_BACKSLASH))
	_check(not debug.visible and sea.visible and water.visible
		and ground.visible and ground_front.visible
		and water.material == normal_water
		and (solids == null or solids.material == normal_clip)
		and water.color == normal_color, "Backslash restores every visual material and visibility")
	main.queue_free()
	await get_tree().process_frame
	print("FAILED %d" % failures if failures > 0 else "Backslash water render diagnostics passed")
	get_tree().quit(1 if failures > 0 else 0)


func _key(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _check(ok: bool, description: String) -> void:
	print(("PASS " if ok else "FAIL ") + description)
	if not ok:
		failures += 1
