extends Node

# No Silas in the actual dive: Kuda is still rescued, but only he speaks.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
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
	var oxygen: SeaOxygen = sea.get_node("SeaOxygen") as SeaOxygen
	NPCManager.get_npc_state(SILAS.npc_id)["flags"][&"silas_surface_transformed"] = true
	NPCManager.get_npc_state(KUDA.npc_id)["flags"][&"Recruited"] = true
	_check(party.invite(KUDA) and not party.has_companion(SILAS.npc_id),
		"Only Kuda belongs to this dive party")
	story.get("_events")[&"first_companion_catch"] = true
	GameManager.begin_dive_period()
	transition.underwater = true
	player.set_swimming(true, sea._sea_bounds())
	sea.activate_diving_party(party.members())
	oxygen.begin_dive(true)
	oxygen.step(oxygen.capacity_seconds)
	for i in range(65):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	_check(DialogueManager.is_active and
		DialogueManager.current_npc.npc_id == &"oxygen_blackout_story",
		"Kuda rescues Penni even when Silas is absent")
	var saw_silas := false
	var saw_kuda := false
	var saw_first_transformation := false
	for i in range(40):
		if not DialogueManager.is_active or DialogueManager.current_npc.npc_id != &"oxygen_blackout_story":
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null:
			saw_silas = saw_silas or line.speaker_id == SILAS.npc_id
			saw_kuda = saw_kuda or line.speaker_id == KUDA.npc_id
			saw_first_transformation = saw_first_transformation or line.text.contains(
				"halfway up")
		DialogueManager.advance()
	_check(saw_kuda and not saw_silas,
		"The recovery scene automatically skips all absent Silas lines")
	_check(saw_first_transformation,
		"Kuda mentions suddenly being human without a separate first reveal")
	for i in range(55):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	var house_spot := world.get_node("TownhouseArrival/PlayerSpot") as Marker2D
	_check(story.has_kuda_flag(&"kuda_surface_introduced")
		and DialogueManager.is_active and DialogueManager.current_npc == KUDA
		and player.global_position.distance_to(house_spot.global_position) < 1.0,
		"Kuda-only blackout skips the ordinary surface reveal and goes to housing")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	for i in range(65):
		if not transition.transitioning:
			break
		await get_tree().create_timer(0.05).timeout
	_check(RecruitmentHandler.is_resident(KUDA.npc_id)
		and not transition.transitioning and not player.busy,
		"Solo Kuda's townhouse introduction and cleanup finish normally")
	main.queue_free()
	await get_tree().process_frame
	print("sea_blackout_solo_test: PASS" if failures == 0 else
		"sea_blackout_solo_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1
