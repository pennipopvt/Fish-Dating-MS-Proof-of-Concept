extends Node

# A fish who has already agreed to join Penni is not re-recruited just
# because the fight forces them back to shore before their first visit.
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
	NPCManager.get_npc_state(SILAS.npc_id)["flags"][&"silas_surface_transformed"] = true
	NPCManager.get_npc_state(KUDA.npc_id)["flags"][&"Recruited"] = true
	_check(party.invite(KUDA) and not RecruitmentHandler.is_resident(KUDA.npc_id),
		"Kuda is recruited underwater but hasn't received a townhouse room")
	story.get("_events")[&"first_companion_catch"] = true
	GameManager.begin_dive_period()
	transition.underwater = true
	player.set_swimming(true, sea._sea_bounds())
	sea.activate_diving_party(party.members())
	var battle: DivingCompanionBattle = commands.battle_for(KUDA.npc_id)
	var fish: DivingWildFish = sea.call("_spawn_wild_fish", MULLET,
		player.position + Vector2(75, -15), 1991, 0.0, 0.0, 0.0) as DivingWildFish
	_check(battle != null and battle.start(fish, MULLET), "Kuda can fight before first landfall")
	battle.health = 1.0
	battle.set("_companion_timer", 100.0)
	battle.set("_fish_timer", 0.0)
	battle.step(0.1, true)
	_check(sea.early_returning_companions().has(KUDA)
		and party.has_companion(KUDA.npc_id)
		and not NPCManager.has_active_relationship_event(KUDA, &"companion_knockout"),
		"Knockout means early departure, not permanent unrecruitment")
	queue._process(0.0)
	var heard_departure := false
	for i in range(30):
		if not DialogueManager.is_active:
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null and line.text.contains("heading back"):
			heard_departure = true
		DialogueManager.advance()
	_check(heard_departure, "Kuda tells Penni he is leaving the dive")
	sea.call("_return_to_surface")
	for i in range(90):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	_check(DialogueManager.is_active
		and DialogueManager.current_npc.npc_id == &"early_shore_barracuda",
		"At shore, already-human Kuda gets an early return introduction")
	_check(not story.has_kuda_flag(&"kuda_surface_introduced"),
		"The normal first-transformation milestone waits until dock reunion")
	var heard_transformed := false
	for i in range(30):
		if not DialogueManager.is_active or DialogueManager.current_npc.npc_id != &"early_shore_barracuda":
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null and line.text.contains("drag myself out"):
			heard_transformed = true
		DialogueManager.advance()
	_check(heard_transformed,
		"Kuda explains he reached shore alone and transformed unexpectedly")
	for i in range(75):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	_check(DialogueManager.is_active and DialogueManager.current_npc == KUDA
		and story.has_kuda_flag(&"kuda_surface_introduced"),
		"Kuda skips his ordinary transformation repeat and moves to townhouse talk")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	for i in range(75):
		if not transition.transitioning:
			break
		await get_tree().create_timer(0.05).timeout
	_check(RecruitmentHandler.is_resident(KUDA.npc_id)
		and party.has_companion(KUDA.npc_id)
		and story.has_kuda_flag(&"kuda_has_home")
		and not transition.transitioning,
		"First KO still culminates in Kuda being housed and recruited")
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
