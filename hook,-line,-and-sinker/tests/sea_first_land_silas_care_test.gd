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
		if line != null and line.text.contains("I'll get you there"):
			heard_offer = true
		DialogueManager.advance()
	_check(heard_offer and transition.transitioning,
		"Penni promises to carry Silas and the rescue triggers automatically")

	for i in range(100):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	_check(DialogueManager.is_active and DialogueManager.current_npc != null
		and DialogueManager.current_npc.npc_id == &"first_land_care_test_npc",
		"Silas sees his own first human form in Penni's care scene")
	_check(not transition.underwater
		and not party.has_companion(SILAS.npc_id),
		"His roster welcome waits for the normal first-land milestone")
	var heard_care := false
	for i in range(30):
		if not DialogueManager.is_active:
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null and line.text.contains("carried me"):
			heard_care = true
		DialogueManager.advance()
	_check(heard_care, "Silas thanks Penni for carrying him out of the sea")
	for i in range(90):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	_check(DialogueManager.is_active and DialogueManager.current_npc == SILAS
		and story.has_silas_flag(&"silas_surface_transformed")
		and party.has_companion(SILAS.npc_id),
		"Silas transforms and joins the same roster before townhouse talk")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	for i in range(90):
		if not transition.transitioning:
			break
		await get_tree().create_timer(0.05).timeout
	_check(RecruitmentHandler.is_resident(SILAS.npc_id)
		and story.has_silas_flag(&"silas_has_home")
		and not transition.transitioning,
		"Silas gets his room with no repeated rescue or lost recruitment")
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
