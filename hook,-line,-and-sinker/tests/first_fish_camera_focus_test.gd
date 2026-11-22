extends Node

# Run: godot --headless --path . res://tests/first_fish_camera_focus_test.tscn
# The pre-existing one-time fish reveal is responsible for the control lock,
# while the shared WorldCameraController animates the view in and back.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	await get_tree().process_frame
	var opening: FishCoOpeningSequence = main.get_node("IntroLayer") as FishCoOpeningSequence
	_check(opening.debug_skip_to_dive(), "Intro skip prepares the ordinary dock and underwater story")
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var player: Player = world.get_node("Player") as Player
	var camera: WorldCameraController = world.get_node("CameraController") as WorldCameraController
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var encounter: SeaEncounterSequence = sea.get_node("EncounterSequence") as SeaEncounterSequence
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var fish: DivingWildFish = encounter.tutorial_fish
	if not is_instance_valid(fish):
		_check(false, "First fish exists")
		_finish(main)
		return

	# Use the already-authored story gate, not a special test camera mode.
	player.set_swimming(true, sea._sea_bounds())
	player.global_position = fish.global_position + Vector2(75.0, 0.0)
	camera.set_underwater_mode(true)
	camera.snap_to_player()
	encounter.on_dive_entered()
	encounter.set("_tutorial_swim_origin", player.global_position + Vector2(0.0, 60.0))
	encounter.fish_focus_pan_seconds = 0.16
	encounter.fish_focus_hold_seconds = 0.24
	encounter.fish_focus_return_seconds = 0.16
	encounter.call("_check_first_fish_focus", 0.0)
	_check(story.has_event(&"fish_focus_seen") and player.busy
		and not bool(camera.get("_following")),
		"One-time first-fish reveal locks Penni and starts the shared camera pan")
	await get_tree().create_timer(0.22).timeout
	_check(camera.camera.get_screen_center_position().distance_to(fish.global_position) < 8.0,
		"Pan centers on the real first fish without replacing the world")
	_check(player.busy, "Player stays locked during the short fish hold")
	await get_tree().create_timer(0.55).timeout
	_check(not player.busy and not bool(encounter.get("_fish_focus_locked"))
		and bool(camera.get("_following")),
		"Camera finishes its return to Penni before controls unlock")
	_check(story.has_event(&"fish_focus_seen"),
		"Focus completion preserves the original story flag for one-time playback")
	encounter.call("_check_first_fish_focus", 0.0)
	_check(not player.busy and bool(camera.get("_following")),
		"Discovering the same fish again never repeats the pan")

	# An interrupted scene must not leave the camera stuck on the fish.
	encounter.set("_fish_focus_locked", true)
	player.busy = true
	camera.pan_to(fish.global_position, 1.0)
	encounter.leave_sea()
	_check(not player.busy and bool(camera.get("_following")),
		"Leaving the sea cancels an interrupted focus and restores normal follow")

	_finish(main)


func _finish(main: Node) -> void:
	main.queue_free()
	await get_tree().process_frame
	print("first_fish_camera_focus_test: PASS" if failures == 0 else
		"first_fish_camera_focus_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
