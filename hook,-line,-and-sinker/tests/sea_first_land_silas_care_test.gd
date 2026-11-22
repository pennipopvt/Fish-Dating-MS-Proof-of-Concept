extends Node

# Silas is not yet in DivingParty on the tutorial dive. When knocked out,
# Penni still carries him ashore and the original townhouse onboarding runs.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const MULLET: FishData = preload("res://resources/fish/mullet.tres")
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var player: Player = world.get_node("Player") as Player
	var transition: SeaDiveTransition = main.get_node("TransitionLayer") as SeaDiveTransition
	var party: DivingParty = transition.get_node("DivingParty") as DivingParty
	var queue: SeaWorldDialogueQueue = sea.get_node("WorldDialogueQueue") as SeaWorldDialogueQueue
	var oxygen: SeaOxygen = sea.get_node("SeaOxygen") as SeaOxygen
	var flags: Dictionary = NPCManager.get_npc_state(SILAS.npc_id)["flags"]
	flags[&"silas_freed"] = true
	flags[&"silas_following"] = true
	story.get("_events")[&"first_companion_catch"] = true
	_check(not party.has_companion(SILAS.npc_id) and story.can_begin_silas_surface_reveal(),
		"Silas can be a first-land companion before his roster is created")
	GameManager.begin_dive_period()
	transition.underwater = true
	player.set_swimming(true, sea._sea_bounds())
	oxygen.begin_dive(true)
	sea.call("_on_silas_following_started")
	var commands: SeaPartyCommands = sea.get_node("PartyCommands") as SeaPartyCommands
	var battle: DivingCompanionBattle = commands.battle_for(SILAS.npc_id)
	var fish: DivingWildFish = sea.call("_spawn_wild_fish", MULLET,
		player.position + Vector2(90, -10), 2010, 0.0, 0.0, 0.0) as DivingWildFish
	_check(battle != null and battle.start(fish, MULLET),
		"Silas joins combat via existing tutorial companion actor")
	battle.health = 1.0
	battle.set("_companion_timer", 100.0)
	battle.set("_fish_timer", 0.0)
	battle.step(0.1, true)
	_check(queue.pending_count() == 1 and oxygen.get("_paused")
		and not RecruitmentHandler.is_resident(SILAS.npc_id),
		"Silas first-land knockout pauses oxygen for emergency care")
	queue._process(0.0)
	_check(DialogueManager.is_active and DialogueManager.current_npc != null
		and DialogueManager.current_npc.npc_id == &"companion_ko_test_npc",
		"Silas gets his underwater injury conversation")
	var heard_offer := false
	for i in range(30):
		if not DialogueManager.is_active:
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null and line.text.contains("Stay here. I'll try to find something to help"):
			heard_offer = true
		DialogueManager.advance()
	_check(heard_offer and transition.transitioning,
		"Penni tells Silas to stay put while she looks for help")

	# Emergency return brings Penni ashore but preserves Silas in fish form.
	# The normal first-return scene then drives the SAME jump, poof and
	# townhouse onboarding used after a successful introductory dive.
	for i in range(140):
		if DialogueManager.is_active and DialogueManager.current_npc == SILAS:
			break
		await get_tree().create_timer(0.05).timeout
	var silas_fish: SeaNPC = sea.get_node("NPCs/Silas") as SeaNPC
	var dock_actor: NPCInteractable = world.get_node_or_null("SilasDockActor") as NPCInteractable
	_check(DialogueManager.is_active and DialogueManager.current_npc == SILAS
		and story.get("_dialogue_stage") == &"surface_warning"
		and bool(story.get("_events").get(&"silas_surface_scene_started", false)),
		"The rescue uses Silas's actual first-land jump and warning dialogue")
	_check(not transition.underwater and not player.swimming
		and player.animator.animation == &"idle_r"
		and dock_actor != null and not dock_actor.visible
		and silas_fish.visible and not silas_fish.following,
		"Penni is on shore but Silas remains a fish until his dock poof")
	var heard_silas_followed := false
	var heard_surprise := false
	for i in range(30):
		if not DialogueManager.is_active or story.get("_dialogue_stage") != &"surface_warning":
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null:
			heard_silas_followed = heard_silas_followed or line.text.contains(
				"I told you to stay in the water")
			heard_surprise = heard_surprise or line.text.contains(
				"W-what?! What's happening")
		DialogueManager.advance()
	_check(heard_silas_followed and heard_surprise,
		"Silas followed Penni against instructions and reacts in surprise")
	for i in range(80):
		if DialogueManager.is_active and story.get("_dialogue_stage") == &"surface_reveal":
			break
		await get_tree().create_timer(0.05).timeout
	_check(DialogueManager.is_active and DialogueManager.current_npc == SILAS
		and story.get("_dialogue_stage") == &"surface_reveal"
		and dock_actor != null and dock_actor.visible and not silas_fish.visible,
		"Shared poof transforms Silas and starts his ORIGINAL reveal dialogue")
	var heard_original_reveal := false
	for i in range(40):
		if not DialogueManager.is_active or story.get("_dialogue_stage") != &"surface_reveal":
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null and line.text.contains("what am I supposed to do now"):
			heard_original_reveal = true
		DialogueManager.advance()
	_check(heard_original_reveal,
		"The rest of Silas's normal recruitment dialogue plays unchanged")
	for i in range(90):
		if DialogueManager.is_active and story.get("_dialogue_stage") == &"townhouse_arrival":
			break
		await get_tree().create_timer(0.05).timeout
	_check(DialogueManager.is_active and DialogueManager.current_npc == SILAS
		and story.get("_dialogue_stage") == &"townhouse_arrival"
		and story.has_silas_flag(&"silas_surface_transformed")
		and party.has_companion(SILAS.npc_id),
		"Silas reaches his original townhouse dialogue and joins the roster")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	for i in range(90):
		if not transition.transitioning:
			break
		await get_tree().create_timer(0.05).timeout
	_check(RecruitmentHandler.is_resident(SILAS.npc_id)
		and story.has_silas_flag(&"silas_has_home")
		and not transition.transitioning
		and world.get_node_or_null("SilasDockActor") == null,
		"First-land knockout finishes the standard housing and actor cleanup")
	main.queue_free()
	await get_tree().process_frame
	NPCManager.npc_states.clear()
	print("sea_first_land_silas_care_test: PASS" if failures == 0 else
		"sea_first_land_silas_care_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1
