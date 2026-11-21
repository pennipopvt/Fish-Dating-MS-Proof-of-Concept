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
	var initial: Vector2 = hunter.position
	kuda.step(0.20)
	_check(hunter.position != initial and kuda.phase == SeaKudaEncounter.Phase.CHASING,
		"Kuda visibly pursues prey within an editor-configured area")
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
	sea.call("_on_fish_hit", hunter)
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
	_check(sea.get_node_or_null("NPCs/PartyFish_barracuda") != null,
		"Kuda immediately follows Penni in fish form for the swim to shore")
	var still_registered: bool = false
	for wild in sea.get("_wild_fish"):
		if is_instance_valid(wild) and wild == hunter:
			still_registered = true
	_check(kuda.phase == SeaKudaEncounter.Phase.RECRUITED and not still_registered,
		"Recruited Kuda is removed from wild catches, not added to inventory")
	kuda.end_dive()
	_check(not kuda.activate(),
		"Kuda never respawns as prey after being recruited")
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
