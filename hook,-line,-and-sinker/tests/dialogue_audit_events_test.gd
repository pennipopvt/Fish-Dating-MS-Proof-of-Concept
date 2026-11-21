extends Node

# Audit regression: remembered promises and boundaries are relationship events,
# while existing gift flags still drive optional small-talk callbacks.
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	var silas_state: Dictionary = NPCManager.get_npc_state(SILAS.npc_id)
	var kuda_state: Dictionary = NPCManager.get_npc_state(KUDA.npc_id)
	silas_state["flags"][&"Recruited"] = true
	kuda_state["flags"][&"Recruited"] = true

	_check(NPCManager.get_relationship_event_definition(SILAS, &"explore_together") != null
		and NPCManager.get_relationship_event_definition(SILAS, &"fish_hurt_pressure") != null,
		"Silas's promises and boundaries use editable NPC event definitions")
	_check(NPCManager.get_relationship_event_definition(KUDA, &"fish_hurt_pressure") == null,
		"Character-specific incidents are not automatically inflicted on other NPCs")

	# A warm, tentative offer to explore together is remembered as a positive
	# open thread, not immediately marked as an outing that already happened.
	DialogueManager.start_conversation(SILAS, "res://dialogue/silas_casual.json")
	_advance_to_choices()
	_select_choice("Have you gone exploring at all?")
	_advance_to_choices()
	_select_choice("Well, maybe one day we can go exploring together!")
	_advance_to_choices()
	_check(NPCManager.has_active_relationship_event(SILAS, &"explore_together")
		and not NPCManager.has_resolved_relationship_event(SILAS, &"explore_together"),
		"Silas remembers Penni's future exploration offer without pretending it happened")
	_check(not NPCManager.has_active_relationship_event(KUDA, &"explore_together")
		and not NPCManager.has_blocking_relationship_event(SILAS, &"overnight"),
		"A positive plan has neither cross-NPC effects nor a romance penalty")
	DialogueManager.end_conversation()

	DialogueManager.start_conversation(SILAS, "res://dialogue/silas_casual.json")
	_advance_to_choices()
	_check(_choice_index("You said we could explore together someday...") >= 0,
		"Silas's casual talk now includes the remembered promise")
	DialogueManager.end_conversation()

	silas_state["flags"][&"silas_route_complete"] = true
	DialogueManager.start_conversation(SILAS, "res://dialogue/silas_post_romance.json")
	_advance_to_choices()
	_check(_choice_index("Do you still want to explore together someday?") >= 0,
		"The remembered offer remains available after Silas's romance route")
	DialogueManager.end_conversation()

	# A nonconsensual push to hurt a wounded fish should be treated differently
	# from respecting his refusal. Use the existing sea dialogue, unchanged.
	var originally: int = AffectionManager.get_morale(SILAS.npc_id)
	_check(not NPCManager.has_active_relationship_event(SILAS, &"fish_hurt_pressure"),
		"Silas starts without an invented combat disagreement")
	DialogueManager.start_conversation(SILAS, "res://dialogue/silas_refuses_attack.json")
	_advance_to_choices()
	_select_choice("Just one more hit?")
	_advance_until_finished()
	_check(NPCManager.has_active_relationship_event(SILAS, &"fish_hurt_pressure")
		and AffectionManager.get_morale(SILAS.npc_id) == originally - 10,
		"Pressuring Silas triggers the incident and a modest hidden morale loss")
	_check(NPCManager.get_relationship_followup_json(SILAS)
		== "res://dialogue/silas_fish_boundary_followup.json",
		"His specific unresolved problem takes precedence over ordinary room chat")
	_check(not NPCManager.has_blocking_relationship_event(SILAS, &"dive"),
		"A disagreement does not eject Silas from the existing diving party")

	DialogueManager.start_conversation(SILAS)
	_check(DialogueManager.is_active and
		DialogueManager.get_current_line().text == "Oh, Penni.",
		"An ordinary visit starts the authored follow-up instead of generic small talk")
	_advance_to_choices()
	_select_choice("We were just trying to catch it.")
	_advance_until_finished()
	_check(NPCManager.has_active_relationship_event(SILAS, &"fish_hurt_pressure"),
		"Dismissing his concern does not magically resolve the disagreement")

	DialogueManager.start_conversation(SILAS)
	_advance_to_choices()
	_select_choice("You're right. I shouldn't have pushed you.")
	_advance_until_finished()
	_check(NPCManager.has_resolved_relationship_event(SILAS, &"fish_hurt_pressure")
		and AffectionManager.get_morale(SILAS.npc_id) == originally - 2,
		"An apology records reconciliation and partially repairs morale")
	_check(NPCManager.get_relationship_followup_json(SILAS).is_empty()
		and NPCManager.get_encounter_json_path(SILAS) == "res://dialogue/silas_post_romance.json",
		"Silas's regular conversation resumes after the actual issue is resolved")

	# Gifts are already tracked by progress flags, not duplicate events.
	silas_state["flags"][&"spyglass_complete"] = true
	DialogueManager.start_conversation(SILAS, "res://dialogue/silas_post_romance.json")
	_advance_to_choices()
	_check(_choice_index("How's the spyglass?") >= 0,
		"Silas can reminisce about an existing spyglass gift")
	DialogueManager.end_conversation()
	kuda_state["flags"][&"barracuda_route_complete"] = true
	kuda_state["flags"][&"barracuda_scarf_complete"] = true
	DialogueManager.start_conversation(KUDA, "res://dialogue/kuda_post_romance.json")
	_advance_to_choices()
	_check(_choice_index("How's that scarf holding up?") >= 0,
		"Kuda can acknowledge his existing scarf without another event")
	DialogueManager.end_conversation()
	_check(kuda_state.get("relationship_events", {}).is_empty(),
		"Gift callbacks don't create irrelevant relationship incidents")

	for path in ["res://dialogue/silas_casual.json",
		"res://dialogue/silas_post_romance.json",
		"res://dialogue/kuda_casual.json",
		"res://dialogue/kuda_post_romance.json",
		"res://dialogue/silas_refuses_attack.json",
		"res://dialogue/silas_fish_boundary_followup.json"]:
		_check(not DialogueJsonLoader.read_graph(path).is_empty(),
			"Edited JSON dialogue validates: " + path.get_file())
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	print("dialogue_audit_events_test: PASS" if failures == 0 else
		"dialogue_audit_events_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _choice_index(title: String) -> int:
	var choices: Array[DialogueChoiceData] = DialogueManager.get_choices()
	for i in range(choices.size()):
		if choices[i].text == title:
			return i
	return -1


func _select_choice(title: String) -> void:
	var index: int = _choice_index(title)
	_check(index >= 0, "Dialogue offers choice: " + title)
	if index >= 0:
		DialogueManager.select_choice(index)


func _advance_to_choices() -> void:
	for i in range(100):
		if not DialogueManager.is_active or DialogueManager.is_awaiting_choice():
			return
		DialogueManager.advance()


func _advance_until_finished() -> void:
	for i in range(100):
		if not DialogueManager.is_active or DialogueManager.is_awaiting_choice():
			return
		DialogueManager.advance()


func _check(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		failures += 1
