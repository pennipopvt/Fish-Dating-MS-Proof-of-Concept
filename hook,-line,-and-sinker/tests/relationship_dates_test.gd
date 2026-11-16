extends Node

# godot --headless --path . res://tests/relationship_dates_test.tscn
# Shared 4-step date templates, 4 jealousy tiers, scores, decay and Kuda route.

const SILAS = preload("res://resources/npcs/silas.tres")
const KUDA = preload("res://resources/npcs/kuda.tres")
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
		_expect(dates.size() == 1, "%s has exactly one date resource" % npc.display_name)
		if dates.size() == 1:
			var expected_id := &"silas_beach" if npc == SILAS else &"kuda_ship"
			_expect(dates[0].date_id == expected_id, "%s keeps only their distinct venue" % npc.display_name)
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
				_expect(styles == ["bold", "playful", "reassure"],
					"Every step uses the same three choice styles")
				for choice in choices:
					_expect(not choice.has("required_flags") and not choice.has("forbidden_flags"),
						"All three date choices remain available at any jealousy tier")

	# The same date_style choice means different things to different NPCs.
	for tier in range(4):
		_expect(DateManager.score_for_choice("reassure", tier, SILAS) >= 1,
			"Silas reassurance is score-safe at tier %d" % tier)
		_expect(DateManager.score_for_choice("reassure", tier, KUDA) >= 1,
			"Kuda reassurance is score-safe at tier %d" % tier)
	for tier in [0, 1]:
		var silas_playful := DateManager.score_for_choice("playful", tier, SILAS)
		var silas_reassure := DateManager.score_for_choice("reassure", tier, SILAS)
		var silas_bold := DateManager.score_for_choice("bold", tier, SILAS)
		_expect(silas_playful > silas_reassure and silas_reassure > silas_bold,
			"Silas prefers playful, then reassurance, then bold at low jealousy")
		var kuda_bold := DateManager.score_for_choice("bold", tier, KUDA)
		var kuda_playful := DateManager.score_for_choice("playful", tier, KUDA)
		var kuda_reassure := DateManager.score_for_choice("reassure", tier, KUDA)
		_expect(kuda_bold > kuda_playful and kuda_playful > kuda_reassure,
			"Kuda prefers bold, then playful, then reassurance at low jealousy")
		_expect(DateManager.jealousy_for_choice("playful", tier) < 0,
			"Playful choices reduce jealousy at low tiers")
		_expect(DateManager.jealousy_for_choice("reassure", tier) < DateManager.jealousy_for_choice("playful", tier),
			"Reassurance reduces jealousy even more")
	for tier in [2, 3]:
		_expect(DateManager.score_for_choice("reassure", tier, SILAS) >
			DateManager.score_for_choice("playful", tier, SILAS),
			"Reassurance is Silas's favorite response when jealousy is high")
		_expect(DateManager.score_for_choice("bold", tier, SILAS) < 0,
			"Bold responses backfire on jealous Silas")
	_expect(DateManager.score_for_choice("bold", 0, KUDA) > 0, "Bold choices work on Kuda at low jealousy")
	_expect(DateManager.score_for_choice("bold", 3, KUDA) < 0, "Bold choices backfire on Kuda at high jealousy")
	_expect(DateManager.score_for_choice("invalid", 0, SILAS) == 0, "Unknown date style gives no score")
	_expect(SILAS.date_score_for_style("playful", 0) != KUDA.date_score_for_style("playful", 0),
		"Character score preferences differ in NPCData")

	# Silas's finished beach draft converges after each of its three responses.
	var beach_graph := DialogueJsonLoader.read_graph("res://dialogue/silas_date_beach.json")
	_expect(not beach_graph.is_empty(), "Silas beach draft parses")
	if not beach_graph.is_empty():
		var beach_nodes: Dictionary = beach_graph["nodes"]
		_expect(not str(beach_nodes["start"]["lines"][0]).begins_with("[Placeholder"),
			"Silas beach date no longer opens with placeholder text")
		for phase in range(1, 5):
			var destination := "choice_%d" % (phase + 1) if phase < 4 else "ending"
			for choice in beach_nodes["choice_%d" % phase]["choices"]:
				var reaction: Dictionary = beach_nodes[str(choice["next"])]
				_expect(str(reaction.get("next", "")) == destination,
					"Every choice at step %d rejoins the shared date" % phase)
				_expect(not str(reaction["lines"][0]).contains("{{date_reaction}}"),
					"Silas beach date has authored reactions rather than generic placeholders")
		var closing_lines: Array = beach_nodes["ending"]["lines"]
		var last_line: Variant = closing_lines.back()
		_expect(last_line is Dictionary and last_line.get("speaker", "") == "player",
			"Silas beach date ends with Penni's reply")

	# Kuda's boat date is fully written and keeps the same non-branching flow.
	var boat_graph := DialogueJsonLoader.read_graph("res://dialogue/kuda_date_ship.json")
	_expect(not boat_graph.is_empty(), "Kuda boat draft parses")
	if not boat_graph.is_empty():
		var boat_nodes: Dictionary = boat_graph["nodes"]
		_expect(not str(boat_nodes["start"]["lines"][0]).begins_with("[Placeholder"),
			"Kuda boat date opens with authored lines")
		for phase in range(1, 5):
			var destination := "choice_%d" % (phase + 1) if phase < 4 else "ending"
			for choice in boat_nodes["choice_%d" % phase]["choices"]:
				var reaction: Dictionary = boat_nodes[str(choice["next"])]
				_expect(str(reaction.get("next", "")) == destination,
					"Kuda choices at step %d converge on the next shared beat" % phase)
				_expect(not str(reaction["lines"][0]).contains("{{date_reaction}}"),
					"Kuda choice reactions are authored")
		for node in boat_nodes.values():
			for line in node.get("lines", []):
				var line_text := str(line.get("text", "")) if line is Dictionary else str(line)
				_expect(not line_text.to_lower().contains("heh"),
					"Kuda dialogue avoids smug chuckling")
		var last_line: Variant = boat_nodes["ending"]["lines"].back()
		_expect(last_line is Dictionary and last_line.get("speaker", "") == "player",
			"Kuda boat date ends with Penni's reply")

	_expect(DateManager.outcome_for_score(-1) == "bad", "Negative total yields a bad date")
	_expect(DateManager.outcome_for_score(2) == "okay", "Low total yields an okay date")
	_expect(DateManager.outcome_for_score(8) == "good", "Middle total yields a good date")
	_expect(DateManager.outcome_for_score(13) == "great", "High total yields a great date")

	silas_state["flags"][&"Recruited"] = true
	kuda_state["flags"][&"Recruited"] = true
	silas_state["flags"][&"silas_route_complete"] = true
	AffectionManager.on_romance_completed(SILAS.npc_id)
	kuda_state["flags"][&"barracuda_route_complete"] = true
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
	_expect(int(DateManager.get("_date_score")) == 5,
		"Jealousy tier two uses Silas\u0027s reassuring score")
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
	AffectionManager.call("_on_date_missed", DateManager.get_date(&"kuda_ship"))
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
