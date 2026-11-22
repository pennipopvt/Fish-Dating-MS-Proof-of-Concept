extends Node

# Blackout uses the same shore story-resolution path as a safe return.
# Kuda's one-time introduction and townhouse room must never be skipped.
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
	var oxygen: SeaOxygen = sea.get_node("SeaOxygen") as SeaOxygen
	var bag: SeaDiveInventory = sea.get_node("SeaDiveInventory") as SeaDiveInventory
	var flags: Dictionary = NPCManager.get_npc_state(SILAS.npc_id)["flags"]
	flags[&"silas_surface_transformed"] = true
	story.silas_surface_reveal_finished.emit()
	_check(party.has_companion(SILAS.npc_id) and party.invite(KUDA),
		"Both returning fish are in the active diving party")
	NPCManager.get_npc_state(KUDA.npc_id)["flags"][&"Recruited"] = true
	story.get("_events")[&"first_companion_catch"] = true
	_check(GameManager.begin_dive_period(), "Blackout dive reserves morning")
	transition.underwater = true
	player.set_swimming(true, sea._sea_bounds())
	sea.activate_diving_party(party.members())
	bag.begin_dive()
	bag.record_fish(MULLET)
	oxygen.begin_dive(true)
	oxygen.step(oxygen.capacity_seconds)
	_check(transition.transitioning, "Running out of oxygen starts rescue")
	for i in range(65):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	_check(DialogueManager.is_active and
		DialogueManager.current_npc.npc_id == &"oxygen_blackout_story",
		"Companions speak to Penni after rescuing her")
	_check(player.busy and not player.swimming and not transition.underwater,
		"Penni is ashore and cannot walk away during recovery")
	var cast: Dictionary = DialogueManager.get("_active_cast") as Dictionary
	_check(cast.has(SILAS.npc_id) and cast.has(KUDA.npc_id),
		"Recovery conversation uses the two returning companions")
	var saw_silas := false
	var saw_kuda := false
	for i in range(40):
		if not DialogueManager.is_active:
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null:
			saw_silas = saw_silas or line.speaker_id == SILAS.npc_id
			saw_kuda = saw_kuda or line.speaker_id == KUDA.npc_id
		DialogueManager.advance()
	_check(saw_silas and saw_kuda, "Both companions speak in the recovery scene")
	for i in range(30):
		if DialogueManager.is_active:
			break
		await get_tree().process_frame
	_check(DialogueManager.is_active and DialogueManager.current_npc == KUDA,
		"Kuda's first shore introduction plays after the recovery scene")
	_check(not RecruitmentHandler.is_resident(KUDA.npc_id),
		"Kuda is not given a room before his introduction")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	for i in range(55):
		if DialogueManager.is_active:
			break
		await get_tree().create_timer(0.05).timeout
	_check(DialogueManager.is_active and DialogueManager.current_npc == KUDA,
		"Penni still takes Kuda in front of the townhouse after blackout")
	if DialogueManager.is_active:
		DialogueManager.end_conversation()
	for i in range(65):
		if not transition.transitioning:
			break
		await get_tree().create_timer(0.05).timeout
	_check(RecruitmentHandler.is_resident(KUDA.npc_id)
		and story.has_kuda_flag(&"kuda_has_home")
		and story.has_kuda_flag(&"kuda_surface_introduced"),
		"Kuda's room, human form, and story flags all resolve after blackout")
	_check(not transition.transitioning and not player.busy and not player.swimming,
		"Shared shore cleanup releases Penni after the complete event sequence")
	_check(world.get_node_or_null("SurfaceGuest_test_npc") == null
		and world.get_node_or_null("SurfaceGuest_barracuda") == null
		and party.has_companion(KUDA.npc_id),
		"Human rescue actors are gone but Kuda remains recruited")
	_check(bag.count_carried() == 0 and
		GameManager.get_period() == GameManager.Times.AFTERNOON,
		"Blackout still loses the carried catch and consumes the time period")
	main.queue_free()
	await get_tree().process_frame
	print("sea_blackout_story_test: PASS" if failures == 0 else
		"sea_blackout_story_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1
