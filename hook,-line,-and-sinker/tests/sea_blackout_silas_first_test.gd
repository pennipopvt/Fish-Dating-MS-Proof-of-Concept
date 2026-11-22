extends Node

# Oxygen loss on the FIRST Silas dive: he isn't in DivingParty yet, but
# still rescues Penni, wakes up human, and gets his usual townhouse room.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
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
	var flags: Dictionary = NPCManager.get_npc_state(SILAS.npc_id)["flags"]
	flags[&"silas_freed"] = true
	flags[&"silas_following"] = true
	story.get("_events")[&"first_companion_catch"] = true
	_check(not party.has_companion(SILAS.npc_id)
		and not story.has_silas_flag(&"silas_surface_transformed")
		and story.can_begin_silas_surface_reveal(),
		"Before the first shore visit Silas is following but isn't on roster")
	GameManager.begin_dive_period()
	transition.underwater = true
	player.set_swimming(true, sea._sea_bounds())
	oxygen.begin_dive(true)
	oxygen.step(oxygen.capacity_seconds)
	for i in range(65):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	_check(DialogueManager.is_active
		and DialogueManager.current_npc.npc_id == &"oxygen_blackout_story",
		"Silas rescues Penni even though DivingParty was empty")
	var actor: Node2D = world.get_node_or_null("SurfaceGuest_test_npc") as Node2D
	_check(is_instance_valid(actor) and actor.visible
		and actor.get_node_or_null("Sprite") is AnimatedSprite2D,
		"Silas is ALREADY in human form at the dock when Penni wakes")
	var cast: Dictionary = DialogueManager.get("_active_cast") as Dictionary
	_check(cast.has(SILAS.npc_id) and not cast.has(&"barracuda"),
		"The first-dive rescue only features companions actually with Penni")
	var heard_silas_first := false
	var heard_kuda := false
	for i in range(40):
		if not DialogueManager.is_active or DialogueManager.current_npc.npc_id != &"oxygen_blackout_story":
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null:
			heard_silas_first = heard_silas_first or (
				line.speaker_id == SILAS.npc_id and line.text.contains(
					"I didn't even notice"))
			heard_kuda = heard_kuda or line.speaker_id == &"barracuda"
		DialogueManager.advance()
	_check(heard_silas_first and not heard_kuda,
		"Silas explains he noticed the transformation but prioritized the rescue")
	for i in range(55):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	var house_spot: Marker2D = world.get_node("TownhouseArrival/PlayerSpot") as Marker2D
	_check(DialogueManager.is_active and DialogueManager.current_npc == SILAS
		and player.global_position.distance_to(house_spot.global_position) < 1.0,
		"First-time Silas goes directly from the rescue to the townhouse dialogue")
	_check(story.has_silas_flag(&"silas_surface_transformed")
		and party.has_companion(SILAS.npc_id),
		"First rescue sets normal transformation milestone and recruits Silas")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	for i in range(65):
		if not transition.transitioning:
			break
		await get_tree().create_timer(0.05).timeout
	_check(RecruitmentHandler.is_resident(SILAS.npc_id)
		and story.has_silas_flag(&"silas_has_home"),
		"Silas's existing townhouse arrival still assigns his room")
	_check(not transition.transitioning and not player.busy
		and not story.can_begin_silas_surface_reveal(),
		"No replay of first land transformation after recovery")
	_check(world.get_node_or_null("SurfaceGuest_test_npc") == null,
		"Shared return cleans up Silas's temporary dock actor")
	main.queue_free()
	await get_tree().process_frame
	print("sea_blackout_silas_first_test: PASS" if failures == 0 else
		"sea_blackout_silas_first_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1
