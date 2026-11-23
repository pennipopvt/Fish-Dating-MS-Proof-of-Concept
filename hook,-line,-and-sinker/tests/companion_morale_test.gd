extends Node

# Run: godot --headless --path . res://tests/companion_morale_test.tscn
# A single affection score determines personal closeness and diving behavior.
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
const KUDA_STATS: CompanionStats = preload("res://resources/companions/kuda_battle.tres")
var failures: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.reset_clock()
	NPCManager.npc_states.clear()
	var state: Dictionary = NPCManager.get_npc_state(SILAS.npc_id)
	state["flags"][&"Recruited"] = true
	state["room_id"] = &"test_room"
	AffectionManager.on_recruited(SILAS.npc_id)
	_check(state.has("affection") and not state.has("morale") and not state.has("attraction"),
		"NPC state stores only one affection score; no separate morale or attraction")
	_check(AffectionManager.get_affection(SILAS.npc_id) == NPCManager.START_AFFECTION
		and NPCManager.START_AFFECTION > AffectionManager.AFFECTION_NEGLECTED_AT,
		"Recruits start comfortably above the neglected threshold with room to grow")
	_check(int(state.get("recruited_day", 0)) == 1
		and not AffectionManager.is_decay_active(SILAS.npc_id),
		"Recruitment starts a five-day grace period for passive neglect")
	# Legacy resource-backed dialogue also uses affection (not an obsolete attraction property).
	var resource_choice := DialogueChoiceData.new()
	resource_choice.affection_change = 7
	NPCManager.apply_choice(SILAS, resource_choice)
	_check(AffectionManager.get_affection(SILAS.npc_id) == NPCManager.START_AFFECTION + 7,
		"Resource-backed dialogue choices update unified affection")
	_check(AffectionManager.choice_amount({"effects": {"affection": 9}}) == 9,
		"New JSON choice effects read the affection key")
	AffectionManager.set_affection(SILAS.npc_id, NPCManager.START_AFFECTION)
	var party := DivingParty.new()
	add_child(party)
	_check(party.invite(SILAS), "New companion can join dives at normal attack speed")
	_check(AffectionManager.attack_speed_multiplier(SILAS.npc_id) == 1.0,
		"Healthy starting affection does not penalize combat")

	for i in range(12):
		GameManager.rest()
	_check(GameManager.get_day() == 5 and not AffectionManager.is_decay_active(SILAS.npc_id)
		and AffectionManager.get_affection(SILAS.npc_id) == NPCManager.START_AFFECTION,
		"Day 5 still has no automatic affection decay")
	for i in range(3):
		GameManager.rest()
	_check(GameManager.get_day() == 6 and AffectionManager.is_decay_active(SILAS.npc_id)
		and AffectionManager.get_affection(SILAS.npc_id)
		== NPCManager.START_AFFECTION - AffectionManager.DAILY_AFFECTION_DECAY,
		"Day 6 begins passive affection decay for an unromanced companion")
	_check(state.get("room_id") == &"test_room" and state["flags"].get(&"Recruited", false),
		"Decay does not evict companions or erase their relationship")
	for i in range(9):
		GameManager.rest()
	_check(GameManager.get_day() == 9
		and AffectionManager.get_affection_stage(SILAS.npc_id) == AffectionManager.AffectionStage.NEGLECTED,
		"Gradual neglect affects the same affection score used for dialogue")
	_check(AffectionManager.attack_speed_multiplier(SILAS.npc_id) == 0.82,
		"Neglect slows the existing combat timing")

	AffectionManager.set_affection(SILAS.npc_id, 20)
	_check(AffectionManager.get_affection_stage(SILAS.npc_id) == AffectionManager.AffectionStage.HURT,
		"Lower affection triggers the hurt stage")
	var battle := DivingCompanionBattle.new()
	battle.stats = KUDA_STATS
	add_child(battle)
	var base_interval: float = battle.attack_interval(KUDA_STATS.speed)
	battle.attack_speed_multiplier = AffectionManager.attack_speed_multiplier(SILAS.npc_id)
	_check(battle.companion_attack_interval() > base_interval,
		"Shared affection slowdown is applied to the existing companion battle")

	AffectionManager.set_affection(SILAS.npc_id, 8)
	_check(AffectionManager.get_affection_stage(SILAS.npc_id) == AffectionManager.AffectionStage.REFUSING
		and not AffectionManager.can_join_dive(SILAS.npc_id)
		and party.members().is_empty() and party.roster_members().size() == 1,
		"Very low affection causes temporary diving refusal, not dismissal")
	AffectionManager.call("_on_conversation_finished", SILAS)
	_check(AffectionManager.get_affection(SILAS.npc_id) == 20
		and not AffectionManager.can_join_dive(SILAS.npc_id),
		"One friendly check-in cannot instantly repair serious hurt")
	AffectionManager.call("_on_conversation_finished", SILAS)
	_check(AffectionManager.get_affection(SILAS.npc_id) == 20,
		"Repeating conversations on the same day cannot farm affection")

	for i in range(3):
		GameManager.rest()
	AffectionManager.call("_on_conversation_finished", SILAS)
	_check(AffectionManager.get_affection(SILAS.npc_id) == 32
		and not AffectionManager.can_join_dive(SILAS.npc_id),
		"Refusal persists until the rejoin threshold, even above the initial cutoff")
	for i in range(3):
		GameManager.rest()
	AffectionManager.call("_on_conversation_finished", SILAS)
	_check(AffectionManager.get_affection(SILAS.npc_id) == 44
		and AffectionManager.can_join_dive(SILAS.npc_id)
		and party.members().size() == 1,
		"Repairing affection restores companion participation without re-recruiting")

	# Romance starts passive maintenance early, but creates no second value.
	var kuda_state: Dictionary = NPCManager.get_npc_state(KUDA.npc_id)
	kuda_state["flags"][&"Recruited"] = true
	AffectionManager.on_recruited(KUDA.npc_id)
	_check(not AffectionManager.is_decay_active(KUDA.npc_id),
		"Freshly recruited Kuda gets the same grace period")
	AffectionManager.on_romance_completed(KUDA.npc_id)
	_check(AffectionManager.is_decay_active(KUDA.npc_id)
		and kuda_state.has("affection") and not kuda_state.has("morale"),
		"Romance activates affection maintenance, never a parallel morale score")

	# Dates are rewarded once through DateManager, not once per old system.
	AffectionManager.set_affection(KUDA.npc_id, 30)
	_check(int(DateManager.OUTCOME_AFFECTION["great"]) == 28,
		"Date's best outcome awards meaningful affection")
	AffectionManager.change_affection(KUDA.npc_id, int(DateManager.OUTCOME_AFFECTION["great"]))
	DateManager.date_finished.emit(DateManager.get_date(&"kuda_ship"))
	_check(AffectionManager.get_affection(KUDA.npc_id) == 58,
		"Date completion has no second, hidden morale reward")

	# Ordinary conversation can't be used to cancel out a hurtful answer.
	state.erase(AffectionManager.LAST_TALK_KEY)
	var before_pressure: int = AffectionManager.get_affection(SILAS.npc_id)
	DialogueManager.start_conversation(SILAS, "res://dialogue/silas_refuses_attack.json")
	for i in range(40):
		if DialogueManager.is_awaiting_choice():
			break
		DialogueManager.advance()
	var index: int = -1
	for i in range(DialogueManager.get_choices().size()):
		if DialogueManager.get_choices()[i].text == "Just one more hit?":
			index = i
	_check(index >= 0, "Silas's deliberate boundary-pressure choice is available")
	if index >= 0:
		DialogueManager.select_choice(index)
		for i in range(40):
			if not DialogueManager.is_active:
				break
			DialogueManager.advance()
	_check(AffectionManager.get_affection(SILAS.npc_id) == before_pressure - 10,
		"Negative relationship event cannot be offset by automatic talk recovery")

	battle.queue_free()
	party.queue_free()
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	print("companion_morale_test: PASS" if failures == 0 else
		"companion_morale_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		failures += 1
