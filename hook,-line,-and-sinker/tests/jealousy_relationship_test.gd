extends Node

# godot --headless --path . res://tests/jealousy_relationship_test.tscn
# One shared jealousy score, authored incident conversations, no free +12
# greeting reward, repeatable date-triggered reactions, and independent hurt.
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.reset_clock()
	NPCManager.npc_states.clear()
	var silas_state: Dictionary = NPCManager.get_npc_state(SILAS.npc_id)
	var kuda_state: Dictionary = NPCManager.get_npc_state(KUDA.npc_id)
	silas_state["flags"][&"Recruited"] = true
	kuda_state["flags"][&"Recruited"] = true
	AffectionManager.on_recruited(SILAS.npc_id)
	AffectionManager.on_recruited(KUDA.npc_id)
	AffectionManager.set_affection(SILAS.npc_id, 60)

	# A hello should count as a visit, not grant +12 or farm affection.
	DialogueManager.start_conversation(SILAS, "res://dialogue/silas_casual.json")
	_check(DialogueManager.is_active, "Silas can have an ordinary conversation")
	DialogueManager.end_conversation()
	_check(AffectionManager.get_affection(SILAS.npc_id) == 60,
		"An ordinary chat gives no automatic +12 affection")
	_check(int(silas_state.get(AffectionManager.LAST_TALK_KEY, -1)) == GameManager.get_day(),
		"Visiting is still remembered and prevents next-day neglect")
	silas_state["flags"][&"silas_route_complete"] = true
	AffectionManager.call("_on_day_started", GameManager.get_day() + 1)
	_check(AffectionManager.get_affection(SILAS.npc_id) == 60,
		"A recent check-in prevents next-day decay without increasing affection")

	# The first romance creates no jealousy. The second one creates a
	# meaningful, immediate, authored conversation for the existing partner.
	silas_state["flags"][&"silas_route_complete"] = true
	AffectionManager.on_romance_completed(SILAS.npc_id)
	_check(AffectionManager.get_jealousy(SILAS.npc_id) == 0,
		"The first partner does not become jealous for no reason")
	kuda_state["flags"][&"barracuda_route_complete"] = true
	AffectionManager.on_romance_completed(KUDA.npc_id)
	_check(AffectionManager.get_jealousy(SILAS.npc_id) == 45
		and AffectionManager.get_jealousy(KUDA.npc_id) == 0,
		"Romancing Kuda upsets existing partner Silas, not Kuda")
	_check(AffectionManager.get_affection(SILAS.npc_id) == 48,
		"Second romance has a real affection consequence with no +12 to erase it")
	_check(NPCManager.has_active_relationship_event(SILAS, &"other_romance")
		and NPCManager.get_encounter_json_path(SILAS) ==
			"res://dialogue/silas_other_romance.json",
		"Silas has an explicit priority incident conversation at jealousy 45")
	_choose_reply(SILAS, 0)
	_check(AffectionManager.get_jealousy(SILAS.npc_id) == 20
		and not NPCManager.has_active_relationship_event(SILAS, &"other_romance"),
		"Honest reassurance reduces jealousy and resolves Silas's incident")
	_check(AffectionManager.get_affection(SILAS.npc_id) == 48,
		"Reassurance does not secretly award routine talk affection")

	# Completing a date with Kuda brings back the OTHER partner's concerns.
	var kuda_date: DateData = DateManager.get_date(&"kuda_ship")
	var silas_date: DateData = DateManager.get_date(&"silas_beach")
	_check(kuda_date != null and silas_date != null, "Both authored date resources are loaded")
	DateManager.date_finished.emit(kuda_date)
	_check(AffectionManager.get_jealousy(SILAS.npc_id) == 35
		and NPCManager.has_active_relationship_event(SILAS, &"other_romance")
		and AffectionManager.get_jealousy(KUDA.npc_id) == 0,
		"A date with Kuda renews Silas's concerns without upsetting the date partner")
	_choose_reply(SILAS, 0)
	_check(AffectionManager.get_jealousy(SILAS.npc_id) == 10
		and not NPCManager.has_active_relationship_event(SILAS, &"other_romance"),
		"Reassurance can work again for a NEW incident, not only the first time")

	# Both characters use the same architecture but have their own voice.
	DateManager.date_finished.emit(silas_date)
	_check(AffectionManager.get_jealousy(KUDA.npc_id) == 15
		and NPCManager.get_encounter_json_path(KUDA) ==
			"res://dialogue/kuda_other_romance.json",
		"Kuda reacts in his own dialogue after a date with Silas")
	var kuda_affection_before: int = AffectionManager.get_affection(KUDA.npc_id)
	_choose_reply(KUDA, 1)
	_check(AffectionManager.get_jealousy(KUDA.npc_id) == 25
		and AffectionManager.get_affection(KUDA.npc_id) == kuda_affection_before - 4
		and NPCManager.has_active_relationship_event(KUDA, &"other_romance"),
		"Dismissiveness raises jealousy, hurts affection and leaves the issue unresolved")
	_choose_reply(KUDA, 2)
	_check(NPCManager.has_active_relationship_event(KUDA, &"other_romance"),
		"Asking to talk later does not silently resolve the incident")
	_choose_reply(KUDA, 0)
	_check(AffectionManager.get_jealousy(KUDA.npc_id) == 0
		and not NPCManager.has_active_relationship_event(KUDA, &"other_romance"),
		"Coming back and acknowledging the issue repairs Kuda's jealousy")

	# A missed date should be disappointment, not imagined romantic betrayal.
	var before_missed: int = AffectionManager.get_affection(KUDA.npc_id)
	AffectionManager.call("_on_date_missed", kuda_date)
	_check(AffectionManager.get_affection(KUDA.npc_id) ==
			before_missed - AffectionManager.MISSED_DATE_AFFECTION_LOSS
		and AffectionManager.get_jealousy(KUDA.npc_id) == 0,
		"Missing your own appointment hurts affection, not jealousy")
	_check(not DialogueJsonLoader.read_graph(
		"res://dialogue/silas_other_romance.json").is_empty()
		and not DialogueJsonLoader.read_graph(
			"res://dialogue/kuda_other_romance.json").is_empty(),
		"Both character-specific jealousy graphs validate with shared JSON schema")

	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	print("jealousy_relationship_test: PASS" if failures == 0
		else "jealousy_relationship_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _choose_reply(npc: NPCData, choice_index: int) -> void:
	DialogueManager.start_conversation(npc)
	_check(DialogueManager.is_active and DialogueManager.current_npc == npc,
		"Jealousy conversation opens for " + npc.display_name)
	for i in range(20):
		if not DialogueManager.is_active or DialogueManager.is_awaiting_choice():
			break
		DialogueManager.advance()
	_check(DialogueManager.is_awaiting_choice()
		and DialogueManager.get_choices().size() == 3,
		"Jealousy conversation offers acknowledge, dismiss, and defer")
	if DialogueManager.is_awaiting_choice():
		DialogueManager.select_choice(choice_index)
		DialogueManager.advance() # Apply choice effects and enter the response.
	if DialogueManager.is_active:
		DialogueManager.end_conversation()


func _check(ok: bool, message: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + message)
	if not ok:
		failures += 1
