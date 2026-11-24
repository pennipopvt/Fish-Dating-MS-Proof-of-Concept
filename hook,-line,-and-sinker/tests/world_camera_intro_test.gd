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
	var title: GameTitleScreen = main.get_node("TitleScreen") as GameTitleScreen
	var music: UnderwaterMusicPlayer = main.get_node("AudioStreamPlayer2D") as UnderwaterMusicPlayer
	var ambience: SeaAmbienceController = main.get_node("SeaAmbience") as SeaAmbienceController
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
	_check((sky.get_node("Clouds") as Node2D).modulate.is_equal_approx(
		(world.get_node("DayNightTint") as CanvasModulate).color),
		"Clouds preserve the same day/night coloring as the world")
	world.call("_process", 0.0)
	var surface_screen: float = water.get_global_transform_with_canvas().origin.y
	_check(is_equal_approx(sky.size.y, clampf(ceilf(surface_screen), 0.0, world.get_viewport_rect().size.y))
		and is_equal_approx(sky.size.x, world.get_viewport_rect().size.x),
		"Sky only exposes pixels above the real waterline")
	_check(player.global_position.distance_to(
		(boat.get_node("PlayerSpot") as Marker2D).global_position) < 1.0
		and camera.get_screen_center_position().distance_to(
			focus.global_position + opening.title_camera_offset) < 5.0,
		"The title starts on the actual boat with an editable establishing shot")
	_check(title.visible and not DialogueManager.is_active and player.busy
		and not music.playing,
		"Title locks gameplay, shows the live boat, and plays no music")
	_check((ambience.get_node("Ocean") as AudioStreamPlayer).playing
		and (ambience.get_node("Underwater") as AudioStreamPlayer).playing,
		"Both ambience tracks continuously play on their shared ambience bus")
	var rock: IntroBoatRock = boat as IntroBoatRock
	_check(rock != null and rock.rocking_period_seconds > 0.0
		and is_zero_approx(boat.rotation) and absf(boat.position.y - 132.0) <= 3.0,
		"Intro boat is raised to its authored waterline and bobs without rotation")
	_check(boat_art.z_index < water.z_index
		and player.z_index + player.animator.z_index < water.z_index
		and boat_art.z_index < player.z_index + player.animator.z_index,
		"Boat and Penni are drawn behind the existing water reflection pass")
	_check(opening.title_camera_offset.y < -6.0,
		"Intro camera framing is raised from its previous position")
	var title_camera_center_y: float = camera.get_screen_center_position().y
	opening.title_pan_seconds = 0.05
	title.call("_on_play")
	await get_tree().create_timer(0.12).timeout
	_check(absf(camera.get_screen_center_position().y - title_camera_center_y) < 1.0,
		"Play pans horizontally while keeping exactly the title camera's starting Y")
	_check(absf(camera.get_screen_center_position().x - focus.global_position.x) < 5.0,
		"Intro pan still reaches the authored boat focus X")
	_check(not title.visible and DialogueManager.is_active and player.busy
		and not (opening.get_node("FishCoIntro") as FishCoIntro).visible,
		"Play pans to the boat before starting the original Fish Co dialogue")
	_check(boat.global_position.x > (world.get_node("Beach") as Node2D).global_position.x
		and water.get_global_rect().has_point(Vector2(boat.global_position.x,
			water.global_position.y + 10.0)),
		"Boat sits right of the playable beach inside the existing Water")
	_check(not music.playing, "Music remains silent until the arrival on the island")
	_check(boat_art.sprite_sheet == load("res://sprites/environment/boat.png")
		and boat_art.sprite_frames != null
		and boat_art.sprite_frames.has_animation(&"sail")
		and boat_art.sprite_frames.get_frame_count(&"sail") > 1,
		"New boat sheet is playing on a real world AnimatedSprite2D")

	_check(opening.debug_skip_to_dive(), "Debug skip keeps normal dock onboarding")
	await get_tree().process_frame
	_check(world.get_node_or_null("IntroBoat") == null,
		"Intro boat frees after it is no longer used, including when skipping the opening")
	_check(not player.busy and player.z_index == 0
		and controller.get("_following") and music.playing,
		"Returning to island restores camera follow and starts background music")
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
