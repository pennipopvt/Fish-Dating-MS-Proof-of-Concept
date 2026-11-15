extends Node

# godot --headless --path . res://tests/relationship_dates_test.tscn
# Shared 4-step date templates, 4 jealousy tiers, scores, decay and Kuda route.

const SILAS: NPCData = preload("res://resources/npcs/test_npc.tres")
const KUDA: NPCData = preload("res://resources/npcs/barracuda.tres")
var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.reset_clock()
	NPCManager.npc_states.clear()

	var silas_state := NPCManager.get_npc_state(SILAS.npc_id)
	var kuda_state := NPCManager.get_npc_state(KUDA.npc_id)
	_expect(SILAS.npc_id != KUDA.npc_id, "The NPCs have distinct relationship states")
	_expect(silas_state["jealousy"] == 0 and kuda_state["jealousy"] == 0,
		"Every NPC starts at zero jealousy")

	for npc_id in [SILAS.npc_id, KUDA.npc_id]:
		for index in range(8):
			var values := [0, 24, 25, 49, 50, 74, 75, 100]
			var tiers := [0, 0, 1, 1, 2, 2, 3, 3]
			AffectionManager.set_jealousy(npc_id, values[index])
			_expect(AffectionManager.get_jealousy_tier(npc_id) == tiers[index],
				"%s jealousy %d falls into tier %d" % [npc_id, values[index], tiers[index]])
	AffectionManager.set_jealousy(SILAS.npc_id, 0)
	AffectionManager.set_jealousy(KUDA.npc_id, 0)

	for npc in [SILAS, KUDA]:
		var dates := DateManager.get_dates_for(npc.npc_id)
		_expect(dates.size() == 2, "%s has beach and boat date resources" % npc.display_name)
		for date in dates:
			var graph := DialogueJsonLoader.read_graph(date.dialogue_json)
			_expect(not graph.is_empty(), "%s date JSON parses" % date.display_name)
			if graph.is_empty():
				continue
			var nodes: Dictionary = graph["nodes"]
			for phase in range(1, 5):
				var choices: Array = nodes["choice_%d" % phase]["choices"]
				_expect(choices.size() == 3, "Date step %d contains exactly three options" % phase)
				var styles: Array[String] = []
				for choice in choices:
					styles.append(str(choice.get("date_style", "")))
				_expect(styles == ["reassure", "neutral", "bold"],
					"Every step uses the same three choice styles")
				for choice in choices:
					_expect(not choice.has("required_flags") and not choice.has("forbidden_flags"),
						"All three date choices remain available at any jealousy tier")

	for tier in range(4):
		_expect(DateManager.score_for_choice("reassure", tier) >= 1,
			"Reassurance is score-safe at jealousy tier %d" % tier)
	_expect(DateManager.score_for_choice("bold", 0) > 0, "Bold choices work at low jealousy")
	_expect(DateManager.score_for_choice("bold", 3) < 0, "Bold choices backfire at high jealousy")
	_expect(DateManager.outcome_for_score(-1) == "bad", "Negative total yields a bad date")
	_expect(DateManager.outcome_for_score(2) == "okay", "Low total yields an okay date")
	_expect(DateManager.outcome_for_score(8) == "good", "Middle total yields a good date")
	_expect(DateManager.outcome_for_score(13) == "great", "High total yields a great date")

	silas_state["flags"][&"Recruited"] = true
	kuda_state["flags"][&"Recruited"] = true
	silas_state["flags"][&"silas_route_complete"] = true
	kuda_state["flags"][&"barracuda_route_complete"] = true
	AffectionManager.on_romance_completed(SILAS.npc_id)
	AffectionManager.on_romance_completed(KUDA.npc_id)
	_expect(AffectionManager.get_jealousy(SILAS.npc_id) == 45,
		"Completing Kuda's first romance spikes existing partner Silas's jealousy")
	_expect(AffectionManager.get_jealousy(KUDA.npc_id) == 0,
		"New partner does not receive a jealousy spike")

	# A date choice lowers jealousy and scores according to the current tier.
	AffectionManager.set_jealousy(SILAS.npc_id, 70)
	DateManager.set("_active", DateManager.get_date(&"silas_beach"))
	DateManager.set("_in_dialogue", true)
	DateManager.set("_date_score", 0)
	DateManager.set("_date_choice_count", 0)
	DateManager.call("_on_date_choice", SILAS, {"date_style": "reassure"})
	_expect(AffectionManager.get_jealousy(SILAS.npc_id) == 64,
		"Reassurance repairs jealousy during a date")
	_expect(int(DateManager.get("_date_score")) == 3,
		"Jealousy tier two applies the appropriate score")
	_expect(DateManager.get_placeholder_reaction().contains("tier 2"),
		"Date response shows the current jealousy tier in its placeholder")
	DateManager.set("_active", null)
	DateManager.set("_in_dialogue", false)

	# A completed date, not just conversation, prevents the next day's decay.
	AffectionManager.set_jealousy(KUDA.npc_id, 75)
	var before := AffectionManager.get_affection(KUDA.npc_id)
	AffectionManager.call("_on_day_started", 2)
	_expect(AffectionManager.get_affection(KUDA.npc_id) == before - 10,
		"Tier three jealousy causes -10 daily decay without a date")
	AffectionManager.mark_date_completed(KUDA.npc_id, 2)
	before = AffectionManager.get_affection(KUDA.npc_id)
	AffectionManager.call("_on_day_started", 3)
	_expect(AffectionManager.get_affection(KUDA.npc_id) == before,
		"A completed date prevents an entire day's affection decay")
	AffectionManager.call("_on_date_missed", DateManager.get_date(&"kuda_beach"))
	_expect(AffectionManager.get_jealousy(KUDA.npc_id) == 90,
		"Missing Kuda's appointment raises jealousy")
	_expect(NPCManager.get_encounter_json_path(KUDA) == "res://dialogue/kuda_post_romance.json",
		"Kuda can arrange future dates through his own post-romance conversation")

	DateManager.set("_active", null)
	NPCManager.npc_states.clear()
	GameManager.reset_clock()
	print("relationship_dates_test: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _expect(ok: bool, message: String) -> void:
	if ok:
		print("  ok   ", message)
	else:
		failures += 1
		push_error("  FAIL " + message)
