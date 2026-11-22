extends Node

# Kuda is injured before his first landfall. Penni automatically brings him
# to shore using the blackout fade, then the normal housing event follows.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
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
	var commands: SeaPartyCommands = sea.get_node("PartyCommands") as SeaPartyCommands
	var queue: SeaWorldDialogueQueue = sea.get_node("WorldDialogueQueue") as SeaWorldDialogueQueue
	var oxygen: SeaOxygen = sea.get_node("SeaOxygen") as SeaOxygen
	var bag: SeaDiveInventory = sea.get_node("SeaDiveInventory") as SeaDiveInventory
	NPCManager.get_npc_state(SILAS.npc_id)["flags"][&"silas_surface_transformed"] = true
	NPCManager.get_npc_state(KUDA.npc_id)["flags"][&"Recruited"] = true
	_check(party.invite(KUDA) and not RecruitmentHandler.is_resident(KUDA.npc_id),
		"Kuda is recruited underwater but has never reached land")
	story.get("_events")[&"first_companion_catch"] = true
	_check(GameManager.begin_dive_period(), "A care rescue uses a real dive period")
	transition.underwater = true
	player.set_swimming(true, sea._sea_bounds())
	oxygen.begin_dive(true)
	bag.record_fish(MULLET)
	sea.activate_diving_party(party.members())
	var battle: DivingCompanionBattle = commands.battle_for(KUDA.npc_id)
	var fish: DivingWildFish = sea.call("_spawn_wild_fish", MULLET,
		player.position + Vector2(75, -15), 1991, 0.0, 0.0, 0.0) as DivingWildFish
	_check(battle != null and battle.start(fish, MULLET), "Kuda fights before first landfall")
	battle.health = 1.0
	battle.set("_companion_timer", 100.0)
	battle.set("_fish_timer", 0.0)
	battle.step(0.1, true)
	_check(party.has_companion(KUDA.npc_id)
		and not NPCManager.has_active_relationship_event(KUDA, &"companion_knockout"),
		"Injury doesn't erase recruitment or invent an inaccessible conflict")
	_check(queue.pending_count() == 1 and oxygen.get("_paused")
		and not transition.transitioning,
		"Knockout pauses oxygen and queues a Penni rescue before the fade")
	queue._process(0.0)
	_check(DialogueManager.is_active and DialogueManager.current_npc != null
		and DialogueManager.current_npc.npc_id == &"companion_ko_barracuda",
		"Underwater dialogue starts before Penni carries Kuda out")
	var heard_penni_help := false
	for i in range(30):
		if not DialogueManager.is_active:
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null and line.text.contains("I'll take care of you"):
			heard_penni_help = true
		DialogueManager.advance()
	_check(heard_penni_help and transition.transitioning and player.busy,
		"Penni promises care; the emergency return starts AUTOMATICALLY")

	for i in range(95):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	_check(DialogueManager.is_active and DialogueManager.current_npc != null
		and DialogueManager.current_npc.npc_id == &"first_land_care_barracuda",
		"On shore, Kuda gets a first-time care conversation, not a blackout rescue")
	_check(not transition.underwater and bag.count_carried() == 0
		and GameManager.get_period() == GameManager.Times.AFTERNOON
		and player.animator.animation == &"idle_r",
		"Emergency care shares blackout fade, catch loss, time and inland facing")
	_check(not story.has_kuda_flag(&"kuda_surface_introduced"),
		"Care conversation occurs before Kuda's first-land milestone is set")
	var heard_kuda_carried := false
	for i in range(30):
		if not DialogueManager.is_active:
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null and line.text.contains("carried me"):
			heard_kuda_carried = true
		DialogueManager.advance()
	_check(heard_kuda_carried, "Kuda acknowledges Penni carried him to safety")
	for i in range(90):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	_check(DialogueManager.is_active and DialogueManager.current_npc == KUDA
		and story.has_kuda_flag(&"kuda_surface_introduced"),
		"Kuda proceeds directly to his regular townhouse introduction")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	for i in range(95):
		if not transition.transitioning:
			break
		await get_tree().create_timer(0.05).timeout
	_check(RecruitmentHandler.is_resident(KUDA.npc_id)
		and party.has_companion(KUDA.npc_id)
		and story.has_kuda_flag(&"kuda_has_home")
		and not transition.transitioning,
		"Penni's rescue ends with Kuda safely housed and still recruited")
	main.queue_free()
	await get_tree().process_frame
	NPCManager.npc_states.clear()
	print("sea_first_land_knockout_test: PASS" if failures == 0 else
		"sea_first_land_knockout_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1
