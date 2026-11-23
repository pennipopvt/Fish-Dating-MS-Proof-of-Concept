extends Node

# Day 3 Fish Co reminder uses the island story event queue, not a custom call.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const OPERATOR: NPCData = preload("res://resources/npcs/fish_co_operator.tres")
var failures: int = 0


func _ready() -> void:
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	var previous_gifts: bool = ShopManager.gifts_unlocked
	var previous_quota: bool = QuotaManager.first_quota_completed
	ShopManager.gifts_unlocked = true
	QuotaManager.first_quota_completed = true
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	var opening: FishCoOpeningSequence = main.get_node("IntroLayer") as FishCoOpeningSequence
	opening._contract_call_finished = true
	opening._first_dive_call_started = true
	opening._first_dive_call_finished = true
	var director: IslandStoryDirector = main.get_node("IslandStoryDirector") as IslandStoryDirector
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var player: Player = world.get_node("Player") as Player
	await get_tree().process_frame
	_check(director.events.size() == 2
		and director.events[1].event_id == &"fish_co_morale",
		"Day 3 morale call is an authored island story event")
	player.busy = true
	for i in range(6):
		GameManager.rest()
	await get_tree().process_frame
	_check(GameManager.get_day() == 3 and not director.has_pending(&"fish_co_morale"),
		"The company does not claim to observe companions before one is housed")
	_check(RecruitmentHandler.assign_home(SILAS), "Silas moves into the townhouse")
	await get_tree().process_frame
	_check(director.has_pending(&"fish_co_morale") and not DialogueManager.is_active,
		"The Day 3 call queues until the player is free")
	player.busy = false
	for i in range(20):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.1).timeout
	_check(DialogueManager.is_active and DialogueManager.current_npc == OPERATOR
		and director.get("_active") == director.events[1],
		"Fish Co calls once on Day 3 or later when a companion is housed")
	var graph: Dictionary = DialogueJsonLoader.read_graph("res://dialogue/fish_co_morale.json")
	_check(not graph.is_empty()
		and JSON.stringify(graph).contains("companion morale"),
		"The authored call links team morale with dive efficiency")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	_check(director.has_completed(&"fish_co_morale"),
		"The reminder is recorded as a one-time island story event")
	for i in range(3):
		GameManager.rest()
	await get_tree().create_timer(0.15).timeout
	_check(not DialogueManager.is_active,
		"Morale reminder does not repeat on later days")
	main.queue_free()
	NPCManager.npc_states.clear()
	ShopManager.gifts_unlocked = previous_gifts
	QuotaManager.first_quota_completed = previous_quota
	print("fish_co_morale_call_test: PASS" if failures == 0 else
		"fish_co_morale_call_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		failures += 1
