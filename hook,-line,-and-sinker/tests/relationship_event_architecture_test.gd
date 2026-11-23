extends Node

# Run: godot --headless --path . res://tests/relationship_event_architecture_test.tscn
# Every NPC uses the same event lifecycle, flags, conditional dialogue and
# action blocking. Distinct authored followups may share an event ID.
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
var failures: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	NPCManager.npc_states.clear()
	GameManager.reset_clock()

	_check(SILAS.relationship_events.size() > 0 and KUDA.relationship_events.size() > 0
		and NPCManager.get_relationship_event_definition(SILAS, &"prelude_boundary") != null
		and NPCManager.get_relationship_event_definition(KUDA, &"prelude_boundary") != null,
		"Both NPC resources use the same editable event definition type")
	_check(not NPCManager.has_active_relationship_event(SILAS, &"prelude_boundary"),
		"A newly recruited NPC has no invented incidents")

	# Dialogue effects set the event, not romance-specific GDScript.
	for npc in [KUDA, SILAS]:
		var graph: Dictionary = DialogueJsonLoader.read_graph(npc.overnight_prelude_json)
		_check(not graph.is_empty(), "Valid original night prelude for " + npc.display_name)
		DialogueManager.start_conversation(npc, npc.overnight_prelude_json)
		_advance_to_choices()
		var choices: Array[DialogueChoiceData] = DialogueManager.get_choices()
		_check(choices.size() >= 3, npc.display_name + " offers a pushy choice")
		if choices.size() >= 3:
			DialogueManager.select_choice(2)
		for i in range(40):
			if not DialogueManager.is_active:
				break
			DialogueManager.advance()
		_check(NPCManager.has_active_relationship_event(npc, &"prelude_boundary"),
			"Authored response starts " + npc.display_name + "'s boundary incident")
		_check(NPCManager.has_blocking_relationship_event(npc, &"overnight")
			and not NPCManager.has_blocking_relationship_event(npc, &"dive"),
			"Only configured actions are blocked for " + npc.display_name)
		_check(NPCManager.dialogue_conditions_match(npc.npc_id,
			{"active_events": ["prelude_boundary"]})
			and not NPCManager.dialogue_conditions_match(npc.npc_id,
			{"resolved_events": ["prelude_boundary"]}),
			"Shared dialogue predicates can read the event without custom NPC flags")
		var flags: Dictionary = NPCManager.get_npc_state(npc.npc_id)["flags"]
		_check(bool(flags.get(&"relationship_event_prelude_boundary_active", false))
			and not bool(flags.get(&"relationship_event_prelude_boundary_resolved", false)),
			"Event automatically mirrors standard active/resolved flags")

	var first_start: int = int(NPCManager.get_relationship_event_state(SILAS, &"prelude_boundary").get("started_day", -1))
	GameManager.rest()
	_check(NPCManager.start_relationship_event(SILAS, &"prelude_boundary")
		and int(NPCManager.get_relationship_event_state(SILAS, &"prelude_boundary").get("started_day", -1))
		== first_start,
		"Starting an already-active event is idempotent")
	_check(NPCManager.resolve_relationship_event(SILAS, &"prelude_boundary")
		and NPCManager.has_resolved_relationship_event(SILAS, &"prelude_boundary")
		and not NPCManager.has_blocking_relationship_event(SILAS, &"overnight"),
		"One NPC's apology resolves their event and lifts the blocking")
	_check(NPCManager.has_active_relationship_event(KUDA, &"prelude_boundary"),
		"Resolving Silas's event cannot affect Kuda")
	_check(NPCManager.dialogue_conditions_match(SILAS.npc_id,
		{"resolved_events": ["prelude_boundary"]})
		and not NPCManager.dialogue_conditions_match(SILAS.npc_id,
		{"active_events": ["prelude_boundary"]}),
		"Dialogue can reference a completed event for later callbacks")
	_check(not NPCManager.resolve_relationship_event(SILAS, &"prelude_boundary"),
		"A resolved event cannot be resolved again")
	_check(NPCManager.start_relationship_event(SILAS, &"prelude_boundary")
		and NPCManager.has_active_relationship_event(SILAS, &"prelude_boundary")
		and not NPCManager.has_resolved_relationship_event(SILAS, &"prelude_boundary"),
		"A resolved incident can recur later with fresh active state")

	# Event priorities work without making a new rule in NPCManager.
	var example: NPCData = NPCData.new()
	example.npc_id = &"example_event_npc"
	var low: RelationshipEventData = RelationshipEventData.new()
	low.event_id = &"worry"
	low.priority = 10
	low.followup_dialogue_json = "res://dialogue/silas_casual.json"
	var high: RelationshipEventData = RelationshipEventData.new()
	high.event_id = &"argument"
	high.priority = 60
	high.followup_dialogue_json = "res://dialogue/kuda_casual.json"
	example.relationship_events = [low, high]
	_check(NPCManager.start_relationship_event(example, &"worry")
		and NPCManager.start_relationship_event(example, &"argument"),
		"Arbitrary NPC definitions can activate multiple independent incidents")
	_check(NPCManager.get_relationship_followup_json(example) == high.followup_dialogue_json
		and NPCManager.get_encounter_json_path(example) == high.followup_dialogue_json,
		"Higher priority followup overrides normal NPC encounters")
	_check(NPCManager.resolve_relationship_event(example, &"argument")
		and NPCManager.get_relationship_followup_json(example) == low.followup_dialogue_json,
		"After resolving the top issue, the next active issue takes priority")
	_check(not NPCManager.start_relationship_event(example, &"unknown"),
		"Unknown event IDs are rejected instead of creating invisible flags")

	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	print("relationship_event_architecture_test: PASS" if failures == 0 else
		"relationship_event_architecture_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _advance_to_choices() -> void:
	for i in range(45):
		if not DialogueManager.is_active or DialogueManager.is_awaiting_choice():
			return
		DialogueManager.advance()


func _check(ok: bool, message: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + message)
	if not ok:
		failures += 1
