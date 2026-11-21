extends Node

# Run: godot --headless --path . res://tests/dialogue_state_variants_test.tscn
# Regression for reusable state-aware lines, prioritized topics, rotating
# everyday discussions and compatibility with original full-stage dialogue.
const SILAS: NPCData = preload("res://resources/npcs/silas.tres")
const KUDA: NPCData = preload("res://resources/npcs/kuda.tres")
var failures: int = 0


func _ready() -> void:
	await get_tree().process_frame
	GameManager.reset_clock()
	NPCManager.npc_states.clear()
	var silas_state: Dictionary = NPCManager.get_npc_state(SILAS.npc_id)
	silas_state["flags"][&"Recruited"] = true
	silas_state["flags"][&"silas_route_complete"] = true
	var kuda_state: Dictionary = NPCManager.get_npc_state(KUDA.npc_id)
	kuda_state["flags"][&"Recruited"] = true
	kuda_state["flags"][&"barracuda_route_complete"] = true

	for path in ["res://dialogue/silas_post_romance.json",
			"res://dialogue/kuda_post_romance.json",
			"res://dialogue/silas_date_beach.json"]:
		_check(not DialogueJsonLoader.read_graph(path).is_empty(), "Valid dialogue graph: " + path)

	_check(NPCManager.dialogue_conditions_match(SILAS.npc_id,
		{"required_flags": ["silas_route_complete"], "min_affection": 10,
		"max_jealousy": 0}),
		"Shared state predicates recognize flags, affection and jealousy")
	_check(not NPCManager.dialogue_conditions_match(SILAS.npc_id,
		{"forbidden_flags": ["silas_route_complete"]}),
		"Forbidden flags prevent the predicate from matching")
	_check(not NPCManager.dialogue_conditions_match(SILAS.npc_id,
		{"min_days_since_talk": 3}),
		"An NPC with no prior conversation is not incorrectly considered neglected")

	# With an ordinary relationship, post-romance greetings stay warm. The
	# everyday answer cycles without repeating for three consecutive visits.
	var seen: Array[String] = []
	for i in range(4):
		DialogueManager.start_conversation(SILAS)
		_check(DialogueManager.is_active and DialogueManager.get_current_line().text == "Oh! Penni, hi.",
			"Normal relationship uses the usual greeting on visit %d" % (i + 1))
		_open_current_choices()
		var choices: Array[DialogueChoiceData] = DialogueManager.get_choices()
		_check(not choices.is_empty() and choices[0].text == "Want to go on a date?",
			"Original date choice stays first at default priority")
		DialogueManager.call("_enter_node", "check_in")
		var topic: String = DialogueManager.get_current_line().text
		if i < 3:
			_check(not seen.has(topic), "Visit %d selects a fresh everyday topic" % (i + 1))
			seen.append(topic)
		else:
			_check(topic == seen[0], "Fourth visit cycles back after every topic is seen")
		DialogueManager.call("_enter_node", "check_in")
		_check(DialogueManager.get_current_line().text == topic,
			"Re-entering a topic during one conversation does not rotate it again")
		DialogueManager.end_conversation()

	# Choices and text both react to jealousy; authored state-specific dialogue
	# routes first instead of ignoring an urgent relationship problem.
	AffectionManager.set_jealousy(SILAS.npc_id, 60)
	DialogueManager.start_conversation(SILAS)
	_check(DialogueManager.get_current_line().text == "Oh. Hi, Penni.",
		"High jealousy selects the colder greeting without swapping JSON files")
	_open_current_choices()
	var jealous_choices: Array[DialogueChoiceData] = DialogueManager.get_choices()
	_check(not jealous_choices.is_empty() \
		and jealous_choices[0].text == "You seem a little distant. Is something wrong?",
		"High-priority, conditional relationship topic appears first")
	DialogueManager.call("_enter_node", "check_in")
	_check(DialogueManager.get_current_line().text == "I've been trying not to think about it, but...",
		"Jealousy directs an ordinary check-in to its authored serious response")
	DialogueManager.end_conversation()

	# Low affection and time apart are distinct state predicates and messages.
	AffectionManager.set_jealousy(SILAS.npc_id, 0)
	AffectionManager.set_morale(SILAS.npc_id, 3)
	DialogueManager.start_conversation(SILAS)
	DialogueManager.call("_enter_node", "check_in")
	_check(DialogueManager.get_current_line().text == "I know you're busy, Penni.",
		"Low morale has a different response from jealousy")
	DialogueManager.end_conversation()

	AffectionManager.set_morale(SILAS.npc_id, 100)
	silas_state["last_talk_day"] = -4
	DialogueManager.start_conversation(SILAS)
	_check(DialogueManager.get_current_line().text == "Oh! Penni...",
		"Days without conversation influence the greeting")
	DialogueManager.call("_enter_node", "check_in")
	_check(DialogueManager.get_current_line().text == "I've been doing okay on my own.",
		"Time apart selects a softer neglected response")
	DialogueManager.end_conversation()

	# Kuda shares the code path but has his own authored personality and topic
	# rotation. No duplicate NPC-specific dialogue controller is needed.
	kuda_state["last_talk_day"] = GameManager.get_day()
	DialogueManager.start_conversation(KUDA)
	_check(DialogueManager.get_current_line().text == "Hey, Penni.",
		"Kuda retains his existing normal greeting")
	DialogueManager.call("_enter_node", "check_in")
	var first_kuda: String = DialogueManager.get_current_line().text
	DialogueManager.end_conversation()
	DialogueManager.start_conversation(KUDA)
	DialogueManager.call("_enter_node", "check_in")
	_check(DialogueManager.get_current_line().text != first_kuda,
		"Kuda rotates his own everyday conversations")
	DialogueManager.end_conversation()

	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	print("dialogue_state_variants_test: PASS" if failures == 0 else
		"dialogue_state_variants_test: %d FAILED" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _open_current_choices() -> void:
	# get_choices() intentionally stays empty until all greeting text has
	# actually been advanced, matching the player-facing dialogue UI.
	for i in range(20):
		if not DialogueManager.is_active or DialogueManager.is_awaiting_choice():
			break
		DialogueManager.advance()


func _check(ok: bool, note: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + note)
	if not ok:
		failures += 1
