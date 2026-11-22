extends Node

# End-to-end second NPC test without replaying the tutorial's narration.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var player: Player = world.get_node("Player") as Player
	var transition: SeaDiveTransition = main.get_node("TransitionLayer") as SeaDiveTransition
	var party: DivingParty = transition.get_node("DivingParty") as DivingParty
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var kuda: SeaKudaEncounter = sea.get_node("KudaEncounter") as SeaKudaEncounter
	var battle: DivingCompanionBattle = sea.get_node("NPCs/Silas/CompanionBattle") as DivingCompanionBattle
	var combat: DivingCombat = sea.get_node("Combat") as DivingCombat
	var flags: Dictionary = NPCManager.get_npc_state(SILAS.npc_id)["flags"]

	_check(kuda.phase == SeaKudaEncounter.Phase.DORMANT,
		"Kuda cannot interrupt the first Silas tutorial dive")
	_check(not kuda.activate(), "Kuda cannot start before Silas is welcomed")
	flags[&"silas_surface_transformed"] = true
	flags[&"silas_following"] = true
	story.silas_surface_reveal_finished.emit()
	_check(party.has_companion(SILAS.npc_id) and party.members().size() == 1,
		"Silas is the first member of the actual dive roster")
	transition.underwater = true
	player.set_swimming(true, sea.call("_sea_bounds"))
	# The confirmed second dive explicitly activates the party before
	# interpreting right-click commands. Mirror that production lifecycle.
	sea.activate_diving_party(party.members())
	var frames: SpriteFrames = player.animator.sprite_frames
	_check(frames.has_animation(&"swim_l") and frames.has_animation(&"swim_r")
		and frames.get_frame_count(&"swim_l") > 0
		and frames.get_frame_count(&"swim_r") > 0,
		"Penni's new directional swim sheets use her existing AnimatedSprite2D")
	player.last_direction = -1.0
	Input.action_press(&"Move Left")
	player.call("_swim_physics", 0.016)
	_check(player.animator.animation == &"swim_l",
		"Actual left input selects swim_l instead of floating")
	Input.action_release(&"Move Left")
	player.call("_swim_physics", 0.016)
	_check(player.animator.animation == &"swim_idle_l",
		"Without input Penni returns to her masked left idle-swim")
	Input.action_press(&"Move Right")
	player.call("_swim_physics", 0.016)
	_check(player.animator.animation == &"swim_r",
		"Actual right input selects swim_r instead of floating")
	Input.action_release(&"Move Right")
	player.call("_swim_physics", 0.016)
	_check(player.animator.animation == &"swim_idle_r",
		"Without input Penni returns to her masked right idle-swim")
	_check(kuda.activate(), "After Silas's first return, Kuda encounter activates")
	_check(is_instance_valid(kuda.kuda) and is_instance_valid(kuda.prey)
		and kuda.controls_fish(kuda.kuda) and kuda.controls_fish(kuda.prey),
		"One authored hunting area owns Kuda and a real registered prey fish")
	if not is_instance_valid(kuda.kuda) or not is_instance_valid(kuda.prey):
		_finish(main)
		return
	var hunter: DivingWildFish = kuda.kuda
	var prey: DivingWildFish = kuda.prey
	_check(is_equal_approx(hunter.health_ratio(), 0.5)
		and hunter.health < hunter.max_health,
		"Kuda starts the encounter already weakened to half health")
	var kuda_art: Sprite2D = hunter.get_node("FishSprite") as Sprite2D
	var prey_art: Sprite2D = prey.get_node("FishSprite") as Sprite2D
	_check(kuda_art != null and prey_art != null and
		is_equal_approx(kuda_art.scale.x * float(kuda_art.texture.get_width()),
			kuda.kuda_sprite_width) and
		is_equal_approx(prey_art.scale.x * float(prey_art.texture.get_width()),
			kuda.prey_sprite_width) and hunter.capture_radius > 13.0,
		"Kuda and prey use independent Inspector sprite sizes with aligned net hitboxes")

	_check(kuda.protects_from_silas(hunter) and kuda.protects_from_silas(prey),
		"Silas refuses both Kuda and the fish he is hunting")
	_check(KUDA.sea_visuals != null
		and is_equal_approx(KUDA.sea_visuals.follower_width, 44.0)
		and KUDA.sea_visuals.portrait_scale > 1.0,
		"Kuda has one shared editor-editable fish-form presentation resource")
	var initial: Vector2 = hunter.position
	kuda.step(0.20)
	_check(hunter.position != initial and kuda.phase == SeaKudaEncounter.Phase.CHASING,
		"Kuda visibly pursues prey within an editor-configured area")
	# Drive Kuda through a close-quarters pass with prey held in place.
	# The old direct-target steering reversed every frame on overlap.
	var old_kuda_pos: Vector2 = hunter.position
	var old_prey_pos: Vector2 = prey.position
	var old_hunter_open: Callable = hunter.is_open
	var old_prey_open: Callable = prey.is_open
	hunter.is_open = func(_point: Vector2) -> bool: return true
	prey.is_open = func(_point: Vector2) -> bool: return true
	hunter.position = kuda.position + Vector2(100.0, 70.0)
	prey.position = hunter.position + Vector2(5.0, 0.0)
	var old_prey_speed: float = kuda.prey_speed
	var old_bite_damage: float = kuda.bite_damage
	kuda.prey_speed = 0.0
	kuda.bite_damage = 0.0
	kuda._hunter_heading = Vector2.RIGHT
	kuda._prey_heading = Vector2.RIGHT
	kuda._attack_pass_remaining = 0.0
	var reverse_steps: int = 0
	for i in range(12):
		var previous_x: float = hunter.position.x
		kuda.step(0.016)
		if hunter.position.x < previous_x - 0.01:
			reverse_steps += 1
	_check(reverse_steps == 0 and hunter.position.x > kuda.position.x + 100.0 + 10.0,
		"Overlapping prey triggers a forward attack pass, not rapid facing reversals")
	kuda.prey_speed = old_prey_speed
	kuda.bite_damage = old_bite_damage
	hunter.position = old_kuda_pos
	prey.position = old_prey_pos
	hunter.is_open = old_hunter_open
	prey.is_open = old_prey_open
	kuda._reset_chase()
	# Make Kuda actually kill the first prey, then advance the WORLD update.
	# The old World skipped kuda.step() when both combat.target and prey
	# were null, permanently freezing him with no replacement prey.
	kuda.bite_range = 40.0
	kuda.prey_speed = 0.0
	kuda.kuda_speed = 0.0
	kuda.burst_speed = 0.0
	kuda._bite_timer = 0.0
	prey.position = hunter.position + Vector2(3.0, 0.0)
	prey.health = 1.0
	kuda.step(0.02)
	_check(kuda.prey == null and kuda.phase == SeaKudaEncounter.Phase.CHASING,
		"Kuda can kill his prey during the chase without ending the encounter")
	sea.call("_process", 1.4)
	_check(is_instance_valid(kuda.prey) and kuda.prey != prey
		and kuda.prey.health > 0.0,
		"World continues ticking a prey-less encounter and respawns replacement prey")
	prey = kuda.prey
	if not is_instance_valid(prey):
		_finish(main)
		return
	kuda.bite_range = 12.0
	kuda.prey_speed = 90.0
	kuda.kuda_speed = 126.0
	kuda.burst_speed = 185.0
	player.position = prey.position + Vector2(18.0, 0.0)
	sea.call("_try_companion_target", prey.position)
	_check(DialogueManager.is_active and DialogueManager.current_npc == SILAS
		and not battle.is_active(), "Targeting Kuda's prey plays Silas's one-time refusal")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	player.position = hunter.position + Vector2(18.0, 0.0)
	sea.call("_try_companion_target", hunter.position)
	_check(not battle.is_active() and story.has_event(&"silas_kuda_refusal"),
		"Silas also refuses Kuda and doesn't repeat the full conversation")
	var dialogue_ui: DialogueUI = main.get_node("CanvasLayer/DialogueUI") as DialogueUI
	dialogue_ui.set_underwater_mode(true)
	sea.call("_on_fish_hit", hunter)
	var portrait: TextureRect = dialogue_ui.get_node("NPCPortrait") as TextureRect
	_check(is_equal_approx(portrait.scale.x, KUDA.sea_visuals.portrait_scale)
		and is_equal_approx(portrait.rotation_degrees,
			KUDA.sea_visuals.portrait_angle_degrees),
		"Kuda's underwater portrait applies his authored scale and angle")
	_check(kuda.phase == SeaKudaEncounter.Phase.HOOK_DIALOGUE
		and DialogueManager.current_npc == KUDA and not combat.is_active(),
		"First net hit pauses Kuda for his confrontation before combat")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	_check(combat.is_active() and combat.target == hunter
		and kuda.phase == SeaKudaEncounter.Phase.REELING,
		"First hook dialogue hands off to the existing reeling and parry combat")
	_check(not combat.record_lost_fish,
		"An escaped NPC isn't recorded as an ordinary lost inventory fish")
	combat.release()
	_check(kuda.phase == SeaKudaEncounter.Phase.CHASING and not hunter.trapped,
		"If Kuda escapes he resumes hunting")
	_check(hunter.catch_cooldown > 0.0, "Escaped Kuda briefly cannot be recaught")
	sea.call("_process", 1.4)
	_check(hunter.catch_cooldown <= 0.0,
		"Kuda's special chase ticks the cooldown so the net can catch him again")
	var net: DivingNetProjectile = sea.get_node("NetProjectile") as DivingNetProjectile
	var candidates: Array[DivingWildFish] = [hunter]
	_check(net.cast_net(player, hunter.position, candidates) and
		net.call("_first_fish_on_segment", hunter.position + Vector2(-30, 0),
			hunter.position + Vector2(30, 0)) == hunter,
		"An ordinary net cast recognizes Kuda again after escape")
	net.reset_net()
	sea.call("_on_fish_hit", hunter)
	_check(combat.is_active() and not DialogueManager.is_active,
		"Second net hit skips the introduction and starts combat immediately")
	combat.call("_finish", true)
	_check(kuda.phase == SeaKudaEncounter.Phase.CAUGHT_DIALOGUE
		and DialogueManager.current_npc == KUDA,
		"Winning plays the separate underwater recruitment dialogue")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	await get_tree().process_frame
	_check(story.has_kuda_flag(&"Recruited") and party.has_companion(KUDA.npc_id)
		and party.members().size() == 2,
		"After underwater dialogue Kuda joins the real two-fish roster")
	var kuda_follower: SeaPartyFollower = sea.get_node_or_null(
		"NPCs/PartyFish_barracuda") as SeaPartyFollower
	_check(kuda_follower != null,
		"Kuda immediately follows Penni in fish form for the swim to shore")
	if kuda_follower != null:
		var art: Sprite2D = kuda_follower.get_node("FishSprite") as Sprite2D
		_check(is_equal_approx(
			float(art.texture.get_width()) * art.scale.x,
			KUDA.sea_visuals.follower_width),
			"Recruited Kuda keeps the same large 44px fish-form size")

	var still_registered: bool = false
	for wild in sea.get("_wild_fish"):
		if is_instance_valid(wild) and wild == hunter:
			still_registered = true
	_check(kuda.phase == SeaKudaEncounter.Phase.RECRUITED and not still_registered,
		"Recruited Kuda is removed from wild catches, not added to inventory")
	kuda.end_dive()
	_check(not kuda.activate(),
		"Kuda never respawns as prey after being recruited")
	# KudaEncounter owns the first surface sequence; World just dispatches
	# presented human actors. Do not trigger a story for an absent companion.
	_check(story.can_begin_kuda_surface_reveal(),
		"Newly recruited Kuda is eligible for exactly one shore reveal")
	var entrance: SeaPartyEntrance = transition.get_node("PartyEntrance") as SeaPartyEntrance
	var silas_actor: Node2D = entrance.stage_surface_actor(SILAS, Vector2(65.0, 112.0))
	silas_actor.show()
	var only_silas: Array[Node2D] = [silas_actor]
	sea.on_party_surfaced(only_silas)
	_check(not DialogueManager.is_active and not RecruitmentHandler.is_resident(KUDA.npc_id),
		"No Kuda scene or room assignment when only Silas appears on shore")
	var kuda_actor: Node2D = entrance.stage_surface_actor(KUDA, Vector2(92.0, 112.0))
	kuda_actor.show()
	var transformed_party: Array[Node2D] = [silas_actor, kuda_actor]
	sea.on_party_surfaced(transformed_party)
	_check(DialogueManager.is_active and DialogueManager.current_npc == KUDA,
		"KudaEncounter opens the shared dialogue after Kuda transforms")
	# Use the real returning actors, not the roster. Silas gets his own lines
	# and human portrait while Kuda still owns the story introduction.
	var cast: Dictionary = DialogueManager.get("_active_cast") as Dictionary
	_check(cast.has(SILAS.npc_id) and cast.has(KUDA.npc_id),
		"Silas and Kuda are both in the actual shore conversation cast")
	var saw_silas_line := false
	var saw_kuda_line := false
	var dock_ui: DialogueUI = main.get_node("CanvasLayer/DialogueUI") as DialogueUI
	for i in range(50):
		if not DialogueManager.is_active:
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null and line.speaker_id == SILAS.npc_id:
			saw_silas_line = true
			dock_ui.call("_refresh")
			_check(dock_ui.get_node("%NameLabel").text == SILAS.display_name
				and (dock_ui.get_node("%NPCPortrait") as TextureRect).texture == SILAS.portrait,
				"Silas speaks with his own name and human portrait")
		elif line != null and line.speaker == DialogueLineData.Speaker.NPC:
			saw_kuda_line = true
		DialogueManager.advance()
	_check(saw_silas_line and saw_kuda_line,
		"First Kuda return includes both characters speaking")
	_check(not DialogueManager.is_active,
		"The full multi-character dock introduction can finish normally")
	await get_tree().process_frame
	_check(story.has_kuda_flag(&"kuda_surface_introduced")
		and not story.can_begin_kuda_surface_reveal(),
		"Finishing the shore dialogue prevents it repeating on later dives")
	# The dock reveal now leads into a separate townhouse conversation.
	# Housing must NOT be assigned until Penni has shown Kuda his room.
	_check(not RecruitmentHandler.is_resident(KUDA.npc_id),
		"Kuda does not get a room before the townhouse conversation")
	for i in range(50):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	var kuda_house_spot: Marker2D = world.get_node("TownhouseArrival/KudaSpot") as Marker2D
	_check(DialogueManager.is_active and DialogueManager.current_npc == KUDA
		and player.global_position.distance_to(
			(world.get_node("TownhouseArrival/PlayerSpot") as Marker2D).global_position) < 1.0,
		"After the dock, Penni introduces Kuda to his townhouse room")
	_check(kuda_actor.global_position.distance_to(kuda_house_spot.global_position) < 35.0,
		"Kuda is visibly standing at the townhouse")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	for i in range(50):
		if RecruitmentHandler.is_resident(KUDA.npc_id):
			break
		await get_tree().create_timer(0.05).timeout
	_check(RecruitmentHandler.is_resident(KUDA.npc_id)
		and story.has_kuda_flag(&"kuda_has_home"),
		"Kuda gets a room only after finishing the townhouse scene")
	var kuda_only: Array[Node2D] = [kuda_actor]
	sea.on_party_surfaced(kuda_only)
	_check(not DialogueManager.is_active,
		"Later surfaces do not replay Kuda's introduction")
	silas_actor.queue_free()
	kuda_actor.queue_free()
	player.set_swimming(false)
	_check(player.animator.animation == &"idle_r",
		"Returning to shore switches back to the existing land animations")
	_finish(main)


func _finish(main: Control) -> void:
	main.queue_free()
	print("kuda_encounter_test: PASS" if failures == 0 else
		"kuda_encounter_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + note)
	if not ok:
		failures += 1
