extends Node

# Real battle knockouts use NPCManager's authored incidents, the single
# AffectionManager score, normal party selection and regular dialogue JSON.
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
	var player: Player = world.get_node("Player") as Player
	var transition: SeaDiveTransition = main.get_node("TransitionLayer") as SeaDiveTransition
	var party: DivingParty = transition.get_node("DivingParty") as DivingParty
	var story: SeaStoryDirector = sea.get_node("StoryDirector") as SeaStoryDirector
	var commands: SeaPartyCommands = sea.get_node("PartyCommands") as SeaPartyCommands
	var queue: SeaWorldDialogueQueue = sea.get_node("WorldDialogueQueue") as SeaWorldDialogueQueue
	for npc in [SILAS, KUDA]:
		var state: Dictionary = NPCManager.get_npc_state(npc.npc_id)
		state["room_id"] = &"knockout_test_room"
		state["resident_data"] = npc
		state["flags"][&"Recruited"] = true
	NPCManager.get_npc_state(SILAS.npc_id)["flags"][&"silas_surface_transformed"] = true
	story.silas_surface_reveal_finished.emit()
	_check(party.invite(KUDA) and party.members().size() == 2,
		"Both housed companions can join a dive")
	transition.underwater = true
	player.set_swimming(true, sea._sea_bounds())
	sea.activate_diving_party(party.members())
	var silas_battle: DivingCompanionBattle = commands.battle_for(SILAS.npc_id)
	var kuda_battle: DivingCompanionBattle = commands.battle_for(KUDA.npc_id)
	var kuda_actor: SeaPartyFollower = sea.get_node("NPCs/PartyFish_barracuda") as SeaPartyFollower
	_check(silas_battle != null and kuda_battle != null and kuda_actor != null,
		"Two companion battles use the existing command and actor systems")
	var before_silas: int = AffectionManager.get_affection(SILAS.npc_id)
	var before_kuda: int = AffectionManager.get_affection(KUDA.npc_id)
	var fish1: DivingWildFish = sea.call("_spawn_wild_fish", MULLET,
		player.position + Vector2(60, 15), 1754, 0.0, 0.0, 0.0) as DivingWildFish
	var fish2: DivingWildFish = sea.call("_spawn_wild_fish", MULLET,
		player.position + Vector2(75, -15), 1755, 0.0, 0.0, 0.0) as DivingWildFish
	_knock_out(silas_battle, fish1)
	_check(silas_battle.exhausted and not commands.party_order().has(SILAS.npc_id)
		and commands.battle_for(KUDA.npc_id) == kuda_battle,
		"Silas KO leaves Kuda's independent combat unaffected")
	_check(AffectionManager.get_affection(SILAS.npc_id) ==
		before_silas - sea.knockout_affection_loss
		and NPCManager.has_active_relationship_event(SILAS, &"companion_knockout"),
		"Silas KO lowers affection and starts his authored relationship incident")
	_check(not party.members().has(SILAS) and party.roster_members().has(SILAS)
		and not party.invite(SILAS),
		"KO temporarily blocks dives but never dismisses the resident")
	_check(commands.next_available_id() == KUDA.npc_id,
		"Kuda remains available to receive combat orders")
	_check(queue.pending_count() == 1,
		"Silas's knockout schedules his immediate underwater sendoff dialogue")
	queue._process(0.0)
	_check(DialogueManager.is_active
		and DialogueManager.get_current_line().speaker_id == SILAS.npc_id,
		"Silas speaks with his own fish-form identity in the existing dialogue UI")
	var silas_heading_back := _finish_ko_dialogue()
	_check(silas_heading_back
		and not (sea.get_node("NPCs/Silas") as SeaNPC).following,
		"Silas says he is heading back before retreating from Penni")
	var count_after_ko: int = AffectionManager.get_affection(SILAS.npc_id)
	sea.call("_on_battle_companion_knocked_out")
	_check(AffectionManager.get_affection(SILAS.npc_id) == count_after_ko,
		"Duplicate knockout signal cannot subtract affection twice")

	_knock_out(kuda_battle, fish2)
	_check(kuda_battle.exhausted and commands.party_order().is_empty()
		and not kuda_actor.retreating and queue.pending_count() == 1,
		"Kuda waits to say he is heading back before retreating")
	queue._process(0.0)
	var kuda_heading_back := _finish_ko_dialogue()
	_check(kuda_heading_back and kuda_actor.retreating,
		"Kuda's own knockout sendoff ends before his retreat")
	_check(AffectionManager.get_affection(KUDA.npc_id) ==
		before_kuda - sea.knockout_affection_loss
		and NPCManager.has_active_relationship_event(KUDA, &"companion_knockout"),
		"Kuda has an independent KO incident and affection loss")
	_check(party.members().is_empty() and party.roster_members().size() == 2,
		"Knocked-out residents stay recruited but unavailable for dives")

	var followup: String = NPCManager.get_relationship_followup_json(KUDA)
	_check(followup == "res://dialogue/kuda_companion_knockout_followup.json"
		and NPCManager.has_blocking_relationship_event(KUDA, &"dive")
		and NPCManager.has_blocking_relationship_event(KUDA, &"overnight"),
		"Existing room system prioritizes KO repair and blocks diving/intimacy")
	DialogueManager.request_conversation(KUDA, followup)
	_advance_to_choices()
	_check(DialogueManager.is_active and DialogueManager.is_awaiting_choice(),
		"Knockout followup offers a real player response")
	if DialogueManager.is_awaiting_choice():
		DialogueManager.select_choice(1)
		_finish_conversation()
	_check(NPCManager.has_active_relationship_event(KUDA, &"companion_knockout")
		and not party.members().has(KUDA),
		"Dismissive response does not resolve the incident")
	DialogueManager.request_conversation(KUDA, followup)
	_advance_to_choices()
	if DialogueManager.is_awaiting_choice():
		DialogueManager.select_choice(0)
		_finish_conversation()
	_check(NPCManager.has_resolved_relationship_event(KUDA, &"companion_knockout")
		and not NPCManager.has_active_relationship_event(KUDA, &"companion_knockout")
		and party.members().has(KUDA) and not party.members().has(SILAS),
		"Apology repairs Kuda's incident without silently repairing Silas")

	sea.end_diving_party()
	sea.activate_diving_party(party.members())
	var next_battle: DivingCompanionBattle = commands.battle_for(KUDA.npc_id)
	_check(next_battle != null and next_battle.can_fight()
		and commands.battle_for(SILAS.npc_id) == null,
		"Next dive heals returning Kuda while unresolved Silas stays at home")
	_check(AffectionManager.get_affection(KUDA.npc_id) < before_kuda + 20,
		"Reconciliation helps but does not erase the knockout affection cost")
	# Before his first ever landing, Kuda has no room in which to repair an
	# incident. A KO can exhaust his fight but must not strand his introduction.
	sea.end_diving_party()
	NPCManager.get_npc_state(KUDA.npc_id).erase("room_id")
	AffectionManager.set_affection(KUDA.npc_id, NPCManager.START_AFFECTION)
	sea.activate_diving_party(party.members())
	var first_dive_battle: DivingCompanionBattle = commands.battle_for(KUDA.npc_id)
	_check(first_dive_battle != null and first_dive_battle.can_fight(),
		"An unhoused companion still has the normal first-dive combat actor")
	var fish3: DivingWildFish = sea.call("_spawn_wild_fish", MULLET,
		player.position + Vector2(90, 30), 1756, 0.0, 0.0, 0.0) as DivingWildFish
	if first_dive_battle != null:
		_knock_out(first_dive_battle, fish3)
	_check(not NPCManager.has_active_relationship_event(KUDA, &"companion_knockout")
		and party.members().has(KUDA) and queue.pending_count() == 1
		and not transition.transitioning,
		"First-land KO keeps recruitment and queues care instead of retreating")
	main.queue_free()
	await get_tree().process_frame
	NPCManager.npc_states.clear()
	print("companion_knockout_relationship_test: PASS" if failures == 0 else
		"companion_knockout_relationship_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _knock_out(battle: DivingCompanionBattle, target: DivingWildFish) -> void:
	if not battle.start(target, MULLET):
		_check(false, "Battle can begin before KO test")
		return
	battle.health = 1.0
	battle.set("_companion_timer", 100.0)
	battle.set("_fish_timer", 0.0)
	battle.step(0.1, true)


func _finish_ko_dialogue() -> bool:
	var heard_back := false
	for i in range(30):
		if not DialogueManager.is_active:
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null and line.text.contains("heading home"):
			heard_back = true
		DialogueManager.advance()
	return heard_back


func _advance_to_choices() -> void:
	for i in range(30):
		if not DialogueManager.is_active or DialogueManager.is_awaiting_choice():
			break
		DialogueManager.advance()


func _finish_conversation() -> void:
	for i in range(30):
		if not DialogueManager.is_active or DialogueManager.is_awaiting_choice():
			break
		DialogueManager.advance()


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1
