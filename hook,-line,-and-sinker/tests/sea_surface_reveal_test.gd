extends SceneTree

# First return with rescued Silas: ocean -> dock -> warning -> poof -> wait.
# Run with project autoloads enabled.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Control = MAIN.instantiate() as Control
	get_root().add_child(main)
	await process_frame
	var sea: DivingWorld = main.get_node("SubViewportContainer/SubViewport/World/Sea") as DivingWorld
	var player: Player = sea.get_parent().get_node("Player") as Player
	var transition: SeaDiveTransition = main.get_node("TransitionLayer") as SeaDiveTransition
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var actor: SeaNPC = sea.get_node("NPCs/Silas") as SeaNPC
	var exit: Marker2D = sea.get_node("Points/SurfaceExit") as Marker2D
	var prompt: InteractPrompt = exit.get_node("InteractPrompt") as InteractPrompt
	var world: Node2D = sea.get_parent() as Node2D

	# Surface exit is reachable from the player swim bounds, even though
	# the top of those bounds lies BELOW the actual surface marker.
	player.set_swimming(true, sea.call("_sea_bounds"))
	player.global_position = exit.global_position + Vector2(0, 25)
	transition.underwater = true
	GameManager.diving_session_active = true
	sea._process(0.0)
	_check(prompt.visible, "Near the dock waterline the exit prompt appears")
	_check(player.position.distance_to(exit.position) <= sea.SURFACE_REACH,
		"Surface marker is within reachable swim range")
	var flags: Dictionary = NPCManager.get_npc_state(story.silas_data.npc_id)["flags"]
	flags[&"silas_met"] = true
	flags[&"silas_freed"] = true
	flags[&"silas_following"] = true
	actor.following = true

	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	_check(sea.handle_input(key), "Interact key consumes the shore exit")
	await create_timer(1.05).timeout
	_check(not player.swimming and not transition.underwater,
		"Penni gets back onto the same shore")
	_check(bool(story.get("_events").get(&"silas_surface_scene_started", false)),
		"Only recruited-and-following Silas starts the reveal")

	await create_timer(1.2).timeout
	_check(DialogueManager.is_active and DialogueManager.current_npc == story.silas_data,
		"Silas follows onto the dock and the warning conversation opens")
	_check(bool(main.get_node("CanvasLayer/DialogueUI").get("_underwater_mode")),
		"Silas shows his fish portrait before transforming")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	await create_timer(0.72).timeout
	var land: NPCInteractable = world.get_node_or_null("SilasDockActor") as NPCInteractable
	_check(land != null and land.visible and not land.monitoring,
		"Existing land Silas appears at the dock but cannot start the old romance route")
	_check(not actor.visible and not actor.following,
		"Underwater Silas is replaced by his land representation")
	_check(DialogueManager.is_active and not bool(main.get_node("CanvasLayer/DialogueUI").get("_underwater_mode")),
		"Post-transform dialogue uses Silas's human portrait")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	await process_frame
	_check(story.has_silas_flag(&"silas_surface_transformed")
		and story.has_silas_flag(&"silas_waiting_at_dock") and not player.busy,
		"Silas waits at the dock; player control resumes after reveal")
	_check(not bool(flags.get(&"Recruited", false)),
		"Dock waiting does not silently recruit him into housing")
	_check(not story.can_begin_silas_surface_reveal(),
		"One-time reveal cannot replay on subsequent shore returns")

	main.queue_free()
	await process_frame
	print("FAILED: %d" % failures if failures > 0 else "Sea shore and Silas reveal passed")
	quit(1 if failures > 0 else 0)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
