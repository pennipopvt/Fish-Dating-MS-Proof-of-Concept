extends Node

# Kuda's first successful shore return should include the townhouse
# conversation before home assignment, matching Silas's cutscene sequence.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	NPCManager.npc_states.clear()
	var main: Control = MAIN.instantiate() as Control
	add_child(main)
	(main.get_node("IntroLayer") as FishCoOpeningSequence)._contract_call_finished = true
	await get_tree().process_frame
	var world: Node2D = main.get_node("SubViewportContainer/SubViewport/World") as Node2D
	var sea: DivingWorld = world.get_node("Sea") as DivingWorld
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var player: Player = world.get_node("Player") as Player
	var entrance: SeaPartyEntrance = main.get_node("TransitionLayer/PartyEntrance") as SeaPartyEntrance
	var kuda_flags: Dictionary = NPCManager.get_npc_state(KUDA.npc_id)["flags"]
	kuda_flags[&"Recruited"] = true
	_check(not RecruitmentHandler.is_resident(KUDA.npc_id), "Kuda has no room before first shore arrival")
	var spot: Marker2D = world.get_node("TownhouseArrival/KudaSpot") as Marker2D
	var player_spot: Marker2D = world.get_node("TownhouseArrival/PlayerSpot") as Marker2D
	var actor: Node2D = entrance.stage_surface_actor(KUDA,
		Vector2(120.0, 120.0), "KudaFirstArrivalTest")
	actor.show()
	# Invoke the encounter as the normal sea surface pipeline does.
	sea.on_party_surfaced([actor])
	_check(DialogueManager.is_active and DialogueManager.current_npc == KUDA,
		"First Kuda human-form conversation opens at the dock")
	_check(not RecruitmentHandler.is_resident(KUDA.npc_id),
		"Room is not assigned before the human-form dialogue")
	var actual_cast: Dictionary = DialogueManager.get("_active_cast") as Dictionary
	_check(actual_cast.has(KUDA.npc_id) and not actual_cast.has(&"test_npc"),
		"Silas does not join the conversation when absent from the returning party")
	var saw_silas := false
	var saw_kuda := false
	for i in range(50):
		if not DialogueManager.is_active:
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null and line.speaker_id == &"test_npc":
			saw_silas = true
		if line != null and line.speaker == DialogueLineData.Speaker.NPC:
			saw_kuda = true
		DialogueManager.advance()
	_check(not saw_silas and saw_kuda and not DialogueManager.is_active,
		"The Kuda-only introduction skips Silas's entire contribution")
	# Ended dialogue advances the existing Kuda townhouse scene.
	for i in range(50):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	_check(DialogueManager.is_active and DialogueManager.current_npc == KUDA,
		"Townhouse scene opens with Kuda's own dialogue")
	_check(player.global_position.distance_to(player_spot.global_position) < 1.0,
		"Penni is placed in front of the townhouse")
	var art: AnimatedSprite2D = actor.get_node_or_null("Sprite") as AnimatedSprite2D
	_check(art != null and art.global_position.distance_to(spot.global_position) < 35.0,
		"Kuda's real land sprite appears beside Penni")
	_check(not RecruitmentHandler.is_resident(KUDA.npc_id),
		"Room is still unassigned during townhouse dialogue")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	for i in range(50):
		if RecruitmentHandler.is_resident(KUDA.npc_id):
			break
		await get_tree().create_timer(0.05).timeout
	_check(RecruitmentHandler.is_resident(KUDA.npc_id) and
		bool(kuda_flags.get(&"kuda_has_home", false)),
		"Finishing the townhouse scene assigns Kuda's room and remembers it")
	_check(bool(kuda_flags.get(&"kuda_surface_introduced", false)),
		"Human-form introduction is still recorded separately")
	# This directly calls the story owner without the regular shore transition.
	# Kuda must not create its own second fade once the townhouse talk ends.
	await get_tree().process_frame
	var fading_again: bool = false
	for child in get_tree().root.get_children():
		if child is ScreenFade:
			fading_again = true
	_check(not fading_again and is_instance_valid(actor) and actor.visible,
		"Kuda does not fade away separately before shared shore cleanup")
	main.queue_free()
	await get_tree().process_frame
	print("kuda_townhouse_arrival_test: PASS" if failures == 0 else
		"kuda_townhouse_arrival_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		failures += 1
