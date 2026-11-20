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
	# Isolate the surfacing test from the deferred Fish Co phone introduction.
	# Suppressing its first call here avoids triggering the unrelated iris.
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
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
	_check(player.position.distance_to(exit.position) <= DivingWorld.SURFACE_REACH,
		"Surface marker is within reachable swim range")
	var flags: Dictionary = NPCManager.get_npc_state(story.silas_data.npc_id)["flags"]
	flags[&"silas_met"] = true
	flags[&"silas_freed"] = true
	flags[&"silas_following"] = true
	actor.following = true
	_check(not story.can_surface(), "First shore return is gated by catching a fish with Silas")
	story.get("_events")[&"first_companion_catch"] = true
	_check(story.can_surface(), "An assisted catch unlocks surfacing")

	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	_check(sea.handle_input(key), "Interact key consumes the shore exit")
	await create_timer(1.05).timeout
	_check(not player.swimming and not transition.underwater,
		"Penni gets back onto the same shore")
	var rod: FishingRod = player.get_node("FishingRod") as FishingRod
	_check(rod != null and not rod.visible,
		"Penni's fishing rod stays put away after returning from the sea")
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
	if land != null:
		var marker: Marker2D = sea.get_node("Points/SilasDockWait") as Marker2D
		var art: AnimatedSprite2D = land.get_node("Sprite") as AnimatedSprite2D
		var frame: Texture2D = art.sprite_frames.get_frame_texture(art.animation, art.frame)
		var feet_y: float = land.global_position.y + art.position.y
		if art.centered:
			feet_y += frame.get_height() * 0.5 * art.scale.y
		_check(absf(feet_y - marker.global_position.y) < 1.0,
			"Silas's human sprite feet align with the dock marker")
	_check(not actor.visible and not actor.following,
		"Underwater Silas is replaced by his land representation")
	_check(DialogueManager.is_active and not bool(main.get_node("CanvasLayer/DialogueUI").get("_underwater_mode")),
		"Post-transform dialogue uses Silas's human portrait")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	await process_frame
	await create_timer(0.7).timeout
	_check(story.has_silas_flag(&"silas_surface_transformed")
		and story.has_silas_flag(&"silas_waiting_at_dock") and not player.busy,
		"Silas is added to the school and control resumes after the exit fade")
	_check(world.get_node_or_null("SilasDockActor") == null,
		"The one-time Silas dock actor is freed after the cutscene")
	_check((transition.get_node("DivingParty") as DivingParty).has_companion(story.silas_data.npc_id),
		"First reveal automatically selects Silas for future dives")
	_check(not bool(flags.get(&"Recruited", false)),
		"Dock waiting does not silently recruit him into housing")
	_check(not story.can_begin_silas_surface_reveal(),
		"One-time reveal cannot replay on subsequent shore returns")
	var shop_menu: ShopMenu = main.get_node("CanvasLayer/ShopMenu") as ShopMenu
	var world_terminal: ShopInteractable = world.get_node("Shop") as ShopInteractable
	_check(shop_menu.is_page_unlocked(ShopMenu.Page.STORAGE)
		and not shop_menu.is_page_unlocked(ShopMenu.Page.SHOP),
		"Finishing Silas's shore reveal unlocks Storage but not Upgrades")
	_check(world_terminal.get_node("UnclaimedAchievementNotice").visible
		and bool(world_terminal.get("_progression_notice")),
		"Storage unlock reuses the existing terminal exclamation notice")

	main.queue_free()
	await process_frame
	print("FAILED: %d" % failures if failures > 0 else "Sea shore and Silas reveal passed")
	quit(1 if failures > 0 else 0)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
