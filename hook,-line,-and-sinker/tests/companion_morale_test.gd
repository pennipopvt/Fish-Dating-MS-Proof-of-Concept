extends Node

# Run: godot --headless --path . res://tests/companion_morale_test.tscn
# Tests the grace period, non-romantic morale, staged slowdown, refusal,
# recovery through ordinary talking, and an optional date bonus.
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
	var original_attraction: int = AffectionManager.get_affection(SILAS.npc_id)
	_check(int(state.get("recruited_day", 0)) == 1,
		"Recruitment stores the day of joining, independently from romance")
	_check(not AffectionManager.is_morale_active(SILAS.npc_id),
		"No pressure immediately after recruitment")
	_check(AffectionManager.get_morale(SILAS.npc_id) == 100,
		"Companions begin with healthy team morale")
	var party := DivingParty.new()
	add_child(party)
	_check(party.invite(SILAS), "Silas can join the diving party initially")

	# Five whole days after recruitment, the team-morale grace period ends.
	for i in range(12):
		GameManager.rest()
	_check(GameManager.get_day() == 5 and not AffectionManager.is_morale_active(SILAS.npc_id)
		and AffectionManager.get_morale(SILAS.npc_id) == 100,
		"Unromanced companions remain stable through Day 5")
	for i in range(3):
		GameManager.rest()
	_check(GameManager.get_day() == 6 and AffectionManager.is_morale_active(SILAS.npc_id)
		and AffectionManager.get_morale(SILAS.npc_id) == 92,
		"Day 6 begins gradual morale pressure for a Day 1 recruit")
	_check(AffectionManager.get_affection(SILAS.npc_id) == original_attraction,
		"Neglect never silently reduces romantic attraction")
	_check(state.get("room_id") == &"test_room" and bool(state["flags"].get(&"Recruited", false)),
		"Morale decay never evicts an NPC from the townhouse")
	for i in range(9):
		GameManager.rest()
	_check(GameManager.get_day() == 9 and AffectionManager.get_morale_stage(SILAS.npc_id)
		== AffectionManager.MoraleStage.NEGLECTED,
		"After more time, neglect becomes visible as a distinct relationship stage")
	_check(AffectionManager.attack_speed_multiplier(SILAS.npc_id) < 1.0,
		"Neglect reduces combat attack speed")
	AffectionManager.set_morale(SILAS.npc_id, 33)
	_check(AffectionManager.get_morale_stage(SILAS.npc_id) == AffectionManager.MoraleStage.HURT,
		"Hurt is more serious than ordinary neglect")

	# Battle component reads the same central stage multiplier as dialogue and party.
	var battle := DivingCompanionBattle.new()
	battle.stats = KUDA_STATS
	add_child(battle)
	var base_interval: float = battle.attack_interval(KUDA_STATS.speed)
	battle.attack_speed_multiplier = AffectionManager.attack_speed_multiplier(SILAS.npc_id)
	_check(battle.companion_attack_interval() > base_interval,
		"Slower attacks use existing battle timing without mutating shared stats")
	AffectionManager.set_morale(SILAS.npc_id, 10)
	_check(AffectionManager.get_morale_stage(SILAS.npc_id) == AffectionManager.MoraleStage.REFUSING,
		"Severe hurt leads to a refusal stage")
	_check(not AffectionManager.can_join_dive(SILAS.npc_id) and party.members().is_empty()
		and party.roster_members().size() == 1 and party.unwilling_members().size() == 1,
		"Refusing companions remain on the party roster but skip dives")
	_check(state.get("room_id") == &"test_room" and state["flags"].get(&"Recruited", false),
		"Refusal never removes Silas from the island")
	AffectionManager.call("_on_conversation_finished", SILAS)
	_check(AffectionManager.get_morale(SILAS.npc_id) == 22
		and AffectionManager.can_join_dive(SILAS.npc_id),
		"Ordinary quality time can restore a companion's willingness")
	AffectionManager.call("_on_conversation_finished", SILAS)
	_check(AffectionManager.get_morale(SILAS.npc_id) == 22,
		"Repeating conversations the same day cannot farm morale")
	_check(party.members().size() == 1, "A reconciled companion rejoins dives automatically")

	# Romance turns the system on immediately, without needing to wait five days.
	var kuda_state: Dictionary = NPCManager.get_npc_state(KUDA.npc_id)
	kuda_state["flags"][&"Recruited"] = true
	AffectionManager.on_recruited(KUDA.npc_id)
	_check(not AffectionManager.is_morale_active(KUDA.npc_id),
		"Freshly recruited Kuda has the same grace period")
	AffectionManager.on_romance_completed(KUDA.npc_id)
	_check(AffectionManager.is_morale_active(KUDA.npc_id),
		"Romance activates relationship maintenance early")
	AffectionManager.set_morale(KUDA.npc_id, 30)
	var previous_outcome: String = DateManager.last_date_outcome
	DateManager.last_date_outcome = "great"
	AffectionManager.call("_on_date_finished", DateManager.get_date(&"kuda_ship"))
	_check(AffectionManager.get_morale(KUDA.npc_id) == 58,
		"A great date offers a bigger optional repair bonus")
	DateManager.last_date_outcome = previous_outcome

	party.queue_free()
	battle.queue_free()
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	print("companion_morale_test: PASS" if failures == 0 else
		"companion_morale_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		failures += 1
