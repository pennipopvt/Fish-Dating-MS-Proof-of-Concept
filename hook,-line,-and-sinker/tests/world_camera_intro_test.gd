extends Node

# Run: godot --headless --path . res://tests/world_camera_intro_test.tscn
# The intro boat, water, sky, and camera are all in one persistent World.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const BOAT: PackedScene = preload("res://prefabs/intro_boat.tscn")
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# The artist-editable scene is packaged intact, and the opening then
	# places this instance into the same World as the actual Water and Sky.
	var authored_boat: Node2D = BOAT.instantiate() as Node2D
	_check(authored_boat != null and authored_boat.has_node("PlayerSpot")
		and authored_boat.has_node("CameraFocus")
		and authored_boat.has_node("Sprite"),
		"Authored IntroBoat PackedScene includes editable sprite and markers")
	authored_boat.free()
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var player: Player = world.get_node("Player") as Player
	var controller: WorldCameraController = world.get_node("CameraController") as WorldCameraController
	var camera: Camera2D = controller.get_node("Camera2D") as Camera2D
	var boat: Node2D = world.get_node("IntroBoat") as Node2D
	var boat_art: IntroBoatSprite = boat.get_node("Sprite") as IntroBoatSprite
	var water: ColorRect = world.get_node("Water") as ColorRect
	var sky_layer: CanvasLayer = world.get_node("SkyLayer") as CanvasLayer
	var sky: Control = sky_layer.get_node("Sky") as Control
	var opening: FishCoOpeningSequence = main.get_node("IntroLayer") as FishCoOpeningSequence
	var story: IslandStoryDirector = main.get_node("IslandStoryDirector") as IslandStoryDirector
	var focus: Marker2D = boat.get_node("CameraFocus") as Marker2D

	_check(camera.get_parent() == controller and not player.has_node("Camera2D"),
		"Camera belongs to World, never to Penni's rotating sprite")
	_check(world.get_node("CameraController/Camera2D/UnderwaterTint") is ColorRect,
		"Same underwater shader stays attached to the world camera")
	_check(sky_layer.layer < 0 and sky.clip_contents
		and sky.get_parent() == sky_layer
		and sky.position == Vector2.ZERO,
		"Sky, sun, moon and drifting clouds render in fixed viewport-space")
	world.call("_process", 0.0)
	var surface_screen: float = water.get_global_transform_with_canvas().origin.y
	_check(is_equal_approx(sky.size.y, clampf(ceilf(surface_screen), 0.0, 180.0)),
		"Sky only exposes pixels above the real waterline")
	_check(player.global_position.distance_to(
		(boat.get_node("PlayerSpot") as Marker2D).global_position) < 1.0
		and camera.get_screen_center_position().distance_to(focus.global_position) < 4.0,
		"The opening starts at the editable real boat/camera markers")
	_check(not (opening.get_node("FishCoIntro") as FishCoIntro).visible
		and DialogueManager.is_active and player.busy,
		"Original Fish Co phone dialogue runs without an illustrated overlay")
	_check(boat.global_position.x > (world.get_node("Beach") as Node2D).global_position.x
		and water.get_global_rect().has_point(Vector2(boat.global_position.x,
			water.global_position.y + 10.0)),
		"Boat sits right of the playable beach inside the existing Water")
	_check(boat_art.sprite_sheet == load("res://sprites/environment/boat.png")
		and boat_art.sprite_frames != null
		and boat_art.sprite_frames.has_animation(&"sail")
		and boat_art.sprite_frames.get_frame_count(&"sail") > 1,
		"New boat sheet is playing on a real world AnimatedSprite2D")

	_check(opening.debug_skip_to_dive(), "Debug skip keeps normal dock onboarding")
	await get_tree().process_frame
	_check(not player.busy and player.z_index == 0
		and controller.get("_following"),
		"Returning to island restores player draw order and camera follow")
	var old_x: float = controller.global_position.x
	player.global_position.x += 90.0
	await get_tree().create_timer(0.15).timeout
	_check(controller.global_position.x > old_x
		and controller.global_position.x < player.global_position.x,
		"Follow is smoothed rather than teleporting with Penni")
	_check(sky.position == Vector2.ZERO,
		"Camera smoothing cannot shake the sky's viewport position")
	player.animator.rotation = 0.4
	_check(is_zero_approx(camera.rotation),
		"Tilting Penni does not rotate the world camera")
	player.animator.rotation = 0.0

	var marker := Marker2D.new()
	marker.global_position = Vector2(player.global_position.x + 100.0, player.global_position.y)
	world.add_child(marker)
	story.play_camera_pan(marker, 0.12, 0.08, 0.12)
	_check(player.busy and not controller.get("_following"),
		"Story director locks player control while camera pans")
	await get_tree().create_timer(0.19).timeout
	_check(camera.get_screen_center_position().distance_to(marker.global_position) < 6.0,
		"Story pan reaches the requested world marker")
	await get_tree().create_timer(0.3).timeout
	_check(not player.busy and controller.get("_following"),
		"Story returns camera to Penni and releases her controls")
	marker.queue_free()
	main.queue_free()
	await get_tree().process_frame
	print("world_camera_intro_test: PASS" if failures == 0 else
		"world_camera_intro_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1
