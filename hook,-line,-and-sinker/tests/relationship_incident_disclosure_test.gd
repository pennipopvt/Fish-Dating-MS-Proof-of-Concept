extends Node

# Run: godot --headless --path . res://tests/relationship_incident_disclosure_test.tscn
# Shared incident cooldowns, contextual disclosure and no hidden numeric scores.
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	NPCManager.npc_states.clear()
	GameManager.reset_clock()

	# Silas has been romanced. Kuda has invited Penni, but she hasn't stayed.
	_prime_completed_romance(SILAS)
	_accept_invitation(KUDA)
	_check(NPCManager.get_disclosure_subject(SILAS) == KUDA,
		"Silas's greeting recognizes Kuda's actual accepted invitation")
	_check(_disclose_through_greeting(SILAS, "Kuda"),
		"Silas's menu uses the agreed disclosure option and says Kuda's name")
	_check(NPCManager.was_invitation_disclosed(SILAS.npc_id, KUDA.npc_id),
		"Finishing the conversation records this one invitation")
	AffectionManager.on_romance_completed(KUDA.npc_id)
	_check(not NPCManager.has_active_relationship_event(SILAS, &"other_romance"),
		"An honest advance disclosure prevents the overnight incident")

	# The same greeting and name binding work in the opposite romance order.
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	_prime_completed_romance(KUDA)
	_accept_invitation(SILAS)
	_check(NPCManager.get_disclosure_subject(KUDA) == SILAS,
		"Kuda's greeting recognizes Silas's accepted invitation")
	_check(_disclose_through_greeting(KUDA, "Silas"),
		"Kuda's menu uses the same option but says Silas's name")
	AffectionManager.on_romance_completed(SILAS.npc_id)
	_check(not NPCManager.has_active_relationship_event(KUDA, &"other_romance"),
		"Kuda also respects advance disclosure")

	# Unannounced sleep starts an incident; ordinary dates do not.
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	_prime_completed_romance(SILAS)
	_accept_invitation(KUDA)
	AffectionManager.call("_on_date_finished", DateManager.get_date(&"kuda_ship"))
	_check(not NPCManager.has_active_relationship_event(SILAS, &"other_romance"),
		"Dating another NPC is not a betrayal event")
	AffectionManager.on_romance_completed(KUDA.npc_id)
	_check(NPCManager.has_active_relationship_event(SILAS, &"other_romance")
		and NPCManager.has_blocking_relationship_event(SILAS, &"dive"),
		"Undisclosed overnight starts Silas's boundary and stops diving")
	var first: Dictionary = NPCManager.get_relationship_event_state(SILAS, &"other_romance")
	_check(int(first.get("incident_count", -1)) == 1
		and not NPCManager.is_room_awaiting_reconciliation(SILAS),
		"First incident is discussable on the next visit")

	# Wrong response defers the conversation, but does not count as another offense.
	DialogueManager.start_conversation(SILAS, "res://dialogue/silas_other_romance.json")
	_advance_to_choices()
	var dismiss: int = _find_choice("You're making a big deal out of nothing.")
	if dismiss >= 0:
		DialogueManager.select_choice(dismiss)
		_advance_to_end()
	_check(NPCManager.is_room_awaiting_reconciliation(SILAS)
		and int(first.get("incident_count", -1)) == 1,
		"Dismissal closes the door for a day without inflating offense count")
	GameManager.rest_until(GameManager.Times.MORNING)
	_check(not NPCManager.is_room_awaiting_reconciliation(SILAS)
		and NPCManager.has_blocking_relationship_event(SILAS, &"dive"),
		"The door reopens next morning; diving still needs reconciliation")

	_check(NPCManager.resolve_relationship_event(SILAS, &"other_romance"),
		"An apology can resolve the first incident")
	NPCManager.start_relationship_event(SILAS, &"other_romance")
	var repeat: Dictionary = NPCManager.get_relationship_event_state(SILAS, &"other_romance")
	_check(int(repeat.get("incident_count", -1)) == 2
		and int(repeat.get("ready_day", -1)) == GameManager.get_day() + 1,
		"Second offense adds one full waiting day")
	NPCManager.resolve_relationship_event(SILAS, &"other_romance")
	NPCManager.start_relationship_event(SILAS, &"other_romance")
	var third: Dictionary = NPCManager.get_relationship_event_state(SILAS, &"other_romance")
	_check(int(third.get("incident_count", -1)) == 3
		and int(third.get("ready_day", -1)) == GameManager.get_day() + 2,
		"Third offense adds two waiting days")

	# There are no affection or jealousy values to accumulate in NPC state.
	var state: Dictionary = NPCManager.get_npc_state(SILAS.npc_id)
	_check(not state.has("affection") and not state.has("jealousy"),
		"Numeric affection and jealousy are no longer stored")
	_check(SILAS.sea_first_land_after_knockout_json.is_empty(),
		"Silas uses his original transformation after first-land injury")

	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	print("relationship_incident_disclosure_test: PASS" if failures == 0 else
		"relationship_incident_disclosure_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _prime_completed_romance(npc: NPCData) -> void:
	var flags: Dictionary = NPCManager.get_npc_state(npc.npc_id)["flags"]
	flags[&"Recruited"] = true
	flags[npc.romance_complete_flag] = true
	AffectionManager.on_romance_completed(npc.npc_id)


func _accept_invitation(npc: NPCData) -> void:
	var flags: Dictionary = NPCManager.get_npc_state(npc.npc_id)["flags"]
	flags[&"Recruited"] = true
	flags[npc.invitation_accepted_flag] = true
	NPCManager.register_invitation_accepted(npc)


func _disclose_through_greeting(recipient: NPCData, expected_name: String) -> bool:
	var path: String = "res://dialogue/silas_casual.json" if recipient == SILAS else "res://dialogue/kuda_casual.json"
	DialogueManager.start_conversation(recipient, path)
	_advance_to_choices()
	var option: int = _find_choice("I'm seeing another person...")
	if option < 0:
		DialogueManager.end_conversation()
		return false
	DialogueManager.select_choice(option)
	var heard_name: bool = false
	for i in range(40):
		if not DialogueManager.is_active:
			break
		var line: DialogueLineData = DialogueManager.get_current_line()
		if line != null and line.text.contains(expected_name + " invited me"):
			heard_name = true
		DialogueManager.advance()
	return heard_name and not DialogueManager.is_active


func _advance_to_choices() -> void:
	for i in range(40):
		if not DialogueManager.is_active or DialogueManager.is_awaiting_choice():
			return
		DialogueManager.advance()


func _advance_to_end() -> void:
	for i in range(40):
		if not DialogueManager.is_active:
			return
		DialogueManager.advance()


func _find_choice(text: String) -> int:
	var choices: Array[DialogueChoiceData] = DialogueManager.get_choices()
	for i in range(choices.size()):
		if choices[i].text == text:
			return i
	return -1


func _check(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		failures += 1
