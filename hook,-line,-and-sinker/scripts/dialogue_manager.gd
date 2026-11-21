extends Node

signal dialogue_requested(npc: NPCData)
signal conversation_started(npc: NPCData)
signal conversation_finished(npc: NPCData)
# Animation cues from JSON nodes and special-scene requests after a conversation ends.
signal dialogue_cue(npc: NPCData, cue: String)
signal scene_requested(npc: NPCData, scene_id: String)
# Only DateManager consumes date_style choices; normal dialogue is unaffected.
signal choice_resolved(npc: NPCData, choice: Dictionary)

# Underwater conversations use the same DialogueManager / DialogueUI pipeline
# as the island, but supply short in-memory JSON-style graphs for contextual
# fish conversations. They never spend extra world actions during a dive.
var _requested_inline_graph: Dictionary = {}
var _requested_inline_alias: String = ""
var _current_speaker_alias: String = ""

func request_inline_conversation(
	npc: NPCData, lines: Array[String],
	speaker_alias: String = "", choices: Array[Dictionary] = []
) -> void:
	if npc == null or is_active or lines.is_empty():
		return
	var nodes: Dictionary = {"start": {"lines": lines.duplicate()}}
	if not choices.is_empty():
		var choice_defs: Array[Dictionary] = []
		for i in range(choices.size()):
			var incoming: Dictionary = choices[i]
			var choice: Dictionary = incoming.duplicate(true)
			var target: String = "response_%d" % i
			nodes[target] = {"lines": [str(choice.get("response", ""))]}
			choice.erase("response")
			choice["next"] = target
			choice["spends_action"] = false
			choice_defs.append(choice)
		nodes["start"]["choices"] = choice_defs
	_requested_inline_graph = {
		"entry": "start", "free_greeting": true, "nodes": nodes
	}
	_requested_inline_alias = speaker_alias
	dialogue_requested.emit(npc)
	_requested_inline_graph = {}
	_requested_inline_alias = ""


# Player-only reaction using the existing DialogueUI and its Penni portrait.
# Use a transient NPCData context so Silas's flags/conversation callbacks
# cannot be mistaken for Penni's monologue.
func request_player_monologue(lines: Array[String]) -> void:
	if lines.is_empty() or is_active:
		return
	var context: NPCData = NPCData.new()
	context.npc_id = &"penni_monologue"
	context.display_name = "Penni"
	var entries: Array[Dictionary] = []
	for message in lines:
		entries.append({"speaker": "player", "text": message})
	_requested_inline_graph = {
		"entry": "start",
		"free_greeting": true,
		"nodes": {"start": {"lines": entries}}
	}
	_requested_inline_alias = ""
	dialogue_requested.emit(context)
	_requested_inline_graph = {}
	_requested_inline_alias = ""


func get_current_speaker_name() -> String:
	if not _current_speaker_alias.is_empty():
		return _current_speaker_alias
	return current_npc.display_name if current_npc != null else ""


func request_conversation(npc: NPCData, json_override: String = "", gift_player: Player = null) -> void:
	if npc != null and not is_active:
		_requested_json_path = json_override
		_gift_player = gift_player
		_expected_gift_item_id = gift_player.held_item.item_id if gift_player != null and gift_player.held_item != null else &""
		dialogue_requested.emit(npc)
		_requested_json_path = ""

# API kept compatible with DialogueUI. JSON graphs are instantiated at runtime.
var current_npc: NPCData = null
var current_dialogue: DialogueData = null
var line_index: int = 0
var is_active: bool = false

var _graph: Dictionary = {}
var _node_id: String = ""
var _lines: Array[DialogueLineData] = []
var _choices: Array[DialogueChoiceData] = []
var _choice_defs: Array = []
var _pending_choice: Dictionary = {}
var _requested_json_path: String = ""
var _node_effects_applied: bool = false
var _gift_player: Player = null
var _expected_gift_item_id: StringName = &""
var _scene_after_conversation: String = ""
# JSON file of the running conversation and, per shown choice, whether it is
# greyed (picked before). Used by AffectionManager / DialogueUI.
var _current_path: String = ""
var _choice_greyed: Array[bool] = []
# A router's selected topic stays consistent if revisited in one conversation.
var _conversation_rotations: Dictionary = {}
# Compatibility field. Ordinary conversations are free in the world clock.
# Dates use their own time cost through DateManager.
var last_conversation_cost: int = 0
var _conversation_costs_action: bool = true

func start_conversation(npc: NPCData, json_override: String = "") -> void:
	if is_active or npc == null:
		return
	_conversation_rotations.clear()
	if not _requested_inline_graph.is_empty():
		current_npc = npc
		current_dialogue = null
		_graph = _requested_inline_graph.duplicate(true)
		_current_speaker_alias = _requested_inline_alias
		_current_path = "res://dialogue/diving_inline.json"
		_conversation_costs_action = false
		is_active = true
		conversation_started.emit(npc)
		_enter_node(str(_graph["entry"]))
		return
	_current_speaker_alias = ""
	var path: String = json_override if not json_override.is_empty() else _requested_json_path
	if path.is_empty() and not npc.encounter_rules.is_empty():
		path = NPCManager.get_encounter_json_path(npc)
		if path.is_empty():
			return
	elif path.is_empty():
		path = npc.dialogue_json_path
	if not path.is_empty():
		var graph := DialogueJsonLoader.read_graph(path)
		if graph.is_empty():
			return
		current_npc = npc
		_graph = graph
		_conversation_costs_action = not bool(graph.get("free_greeting", false))
		_current_path = path
		is_active = true
		conversation_started.emit(npc)
		_enter_node(str(graph["entry"]))
		return
	var dialogue: DialogueData = NPCManager.get_dialogue(npc)
	if dialogue == null:
		return
	current_npc = npc
	_conversation_costs_action = true
	current_dialogue = dialogue
	line_index = 0
	is_active = true
	conversation_started.emit(npc)
	_check_for_end()

func get_current_line() -> DialogueLineData:
	if not is_active:
		return null
	if not _graph.is_empty():
		if line_index >= _lines.size():
			return null
		return _lines[line_index]
	if current_dialogue == null or line_index >= current_dialogue.lines.size():
		return null
	return current_dialogue.lines[line_index]

func is_awaiting_choice() -> bool:
	if not is_active:
		return false
	if not _graph.is_empty():
		return line_index >= _lines.size() and not _choices.is_empty()
	return current_dialogue != null and line_index >= current_dialogue.lines.size() and not current_dialogue.choices.is_empty()

# Picked in an earlier visit: DialogueUI shows it grey (still pickable).
func is_choice_greyed(index: int) -> bool:
	return is_awaiting_choice() and index >= 0 and index < _choice_greyed.size() and _choice_greyed[index]

func get_choices() -> Array[DialogueChoiceData]:
	if not is_awaiting_choice():
		return []
	if not _graph.is_empty():
		return _choices
	return current_dialogue.choices

func advance() -> void:
	if not is_active or is_awaiting_choice():
		return
	line_index += 1
	if not _graph.is_empty() and not _pending_choice.is_empty() and line_index >= _lines.size():
		_complete_pending_choice()
	else:
		_check_for_end()

func select_choice(index: int) -> void:
	if not is_awaiting_choice():
		return
	if not _graph.is_empty():
		if index < 0 or index >= _choice_defs.size():
			return
		var choice: Dictionary = _choice_defs[index]
		_show_player_choice(choice)
		return
	if index < 0 or index >= current_dialogue.choices.size():
		return
	var choice: DialogueChoiceData = current_dialogue.choices[index]
	if choice == null:
		return
	NPCManager.apply_choice(current_npc, choice)
	if choice.next_dialogue == null:
		end_conversation()
	else:
		current_dialogue = choice.next_dialogue
		line_index = 0
		_check_for_end()

# Display the selected response as Penni's own line before entering its target node.
# Effects are applied only after that line is advanced, so the player can read it.
func _show_player_choice(choice: Dictionary) -> void:
	_pending_choice = choice.duplicate(true)
	_lines.clear()
	_choices.clear()
	_choice_defs.clear()
	line_index = 0
	var line := DialogueLineData.new()
	line.speaker = DialogueLineData.Speaker.PLAYER
	line.text = str(choice.get("spoken_text", choice.get("text", "")))
	line.expression = StringName(str(choice.get("expression", "neutral")))
	_lines.append(line)

func _complete_pending_choice() -> void:
	var choice := _pending_choice
	_pending_choice = {}
	# Preserve the jealousy tier from when Penni chose her answer. DateManager
	# may change jealousy in choice_resolved, before the response node appears.
	var reaction_tier := -1
	if choice.has("date_style") and current_npc != null:
		reaction_tier = AffectionManager.get_jealousy_tier(current_npc.npc_id)
	if bool(choice.get("spends_action", true)):
		_conversation_costs_action = true
	# Affection goes through AffectionManager (tone or exact number, first pick only).
	if not choice.has("date_style"):
		AffectionManager.on_choice_picked(current_npc, str(choice.get("_key", "")), choice)
	_apply_json_effects(choice.get("effects", {}), false)
	choice_resolved.emit(current_npc, choice)
	_enter_node(str(choice["next"]), reaction_tier)

func _apply_json_effects(effects: Variant, include_attraction: bool = true) -> void:
	if not effects is Dictionary or current_npc == null:
		return
	if not effects.is_empty():
		_conversation_costs_action = true
	if effects.get("give_held_item", false):
		NPCManager.accept_gift(current_npc, _gift_player, _expected_gift_item_id)
	if effects.has("request_scene"):
		_scene_after_conversation = str(effects["request_scene"])
	if include_attraction:
		AffectionManager.change(current_npc.npc_id, int(effects.get("affection", effects.get("attraction", 0))))
	var state: Dictionary = NPCManager.get_npc_state(current_npc.npc_id)
	var flags: Dictionary = state.get("flags", {})
	state["flags"] = flags
	for flag in effects.get("set_flags", []):
		flags[StringName(str(flag))] = true
	for flag in effects.get("clear_flags", []):
		flags[StringName(str(flag))] = false
	for event in effects.get("start_relationship_events", []):
		NPCManager.start_relationship_event(current_npc, StringName(str(event)))
	for event in effects.get("resolve_relationship_events", []):
		NPCManager.resolve_relationship_event(current_npc, StringName(str(event)))
	if effects.has("affection_delta"):
		AffectionManager.change_affection(current_npc.npc_id, int(effects["affection_delta"]))


# Conditions are evaluated when the menu becomes visible, using the NPC's current flags.
func _choice_available(choice: Dictionary) -> bool:
	if current_npc == null:
		return false
	var flags: Dictionary = NPCManager.get_npc_state(current_npc.npc_id).get("flags", {})
	for flag in choice.get("required_flags", []):
		if not flags.get(StringName(str(flag)), false):
			return false
	for flag in choice.get("forbidden_flags", []):
		if flags.get(StringName(str(flag)), false):
			return false
	return NPCManager.dialogue_conditions_match(current_npc.npc_id, choice.get("when", {}))


# Router selection and conditional text are presentation decisions only.
# Conversation stages and underlying affection are owned by their managers.
func _select_rotating_target(id: String, routes: Array) -> String:
	var key: String = "%s#%s" % [_current_path, id]
	if _conversation_rotations.has(key):
		return str(_conversation_rotations[key])
	var state: Dictionary = NPCManager.get_npc_state(current_npc.npc_id)
	var cursors: Dictionary = state.get("dialogue_rotation_cursors", {})
	state["dialogue_rotation_cursors"] = cursors
	var cursor: int = int(cursors.get(key, 0))
	for offset in range(routes.size()):
		var index: int = (cursor + offset) % routes.size()
		var route: Variant = routes[index]
		if route is Dictionary and not NPCManager.dialogue_conditions_match(
				current_npc.npc_id, route.get("when", {})):
			continue
		var target: String = str(route.get("next", "")) if route is Dictionary else str(route)
		cursors[key] = (index + 1) % routes.size()
		_conversation_rotations[key] = target
		return target
	return ""


func _select_node_lines(node: Dictionary, reaction_tier: int) -> Array:
	var tier: int = reaction_tier if reaction_tier >= 0 else AffectionManager.get_jealousy_tier(current_npc.npc_id)
	for variant in node.get("line_variants", []):
		if NPCManager.dialogue_conditions_match(current_npc.npc_id, variant.get("when", {}), tier):
			return variant["lines"]
	if node.has("jealousy_lines"):
		return DialogueJsonLoader.lines_for_jealousy_tier(node, tier)
	return node.get("lines", [])


func _enter_node(id: String, reaction_tier: int = -1, redirects: int = 0) -> void:
	var nodes: Dictionary = _graph["nodes"]
	if not nodes.has(id):
		push_error("Dialogue JSON missing node: " + id)
		end_conversation()
		return
	if redirects >= 12:
		push_error("Dialogue router cycle near: " + id)
		end_conversation()
		return
	var node: Dictionary = nodes[id]
	for route in node.get("conditional_next", []):
		if NPCManager.dialogue_conditions_match(current_npc.npc_id, route.get("when", {}), reaction_tier):
			_enter_node(str(route["next"]), reaction_tier, redirects + 1)
			return
	if node.has("rotating_next"):
		var target: String = _select_rotating_target(id, node["rotating_next"])
		if target.is_empty():
			push_error("Dialogue topic router has no eligible destinations: " + id)
			end_conversation()
			return
		_enter_node(target, reaction_tier, redirects + 1)
		return
	_node_id = id
	_node_effects_applied = false
	if node.has("cue"):
		dialogue_cue.emit(current_npc, str(node["cue"]))
	_lines.clear()
	_choices.clear()
	_choice_defs.clear()
	_choice_greyed.clear()
	line_index = 0
	# Variant responses change only the text, never the choice or graph path.
	# Other dialogue nodes continue to use their ordinary lines unchanged.
	var lines_to_show: Array = _select_node_lines(node, reaction_tier)
	for raw_line in lines_to_show:
		var line := DialogueLineData.new()
		if raw_line is String:
			line.text = _format_date_placeholder(raw_line)
		elif raw_line is Dictionary:
			line.text = _format_date_placeholder(str(raw_line.get("text", "")))
			line.speaker = DialogueLineData.Speaker.PLAYER if raw_line.get("speaker", "npc") == "player" else DialogueLineData.Speaker.NPC
			line.expression = StringName(str(raw_line.get("expression", "neutral")))
		else:
			continue
		_lines.append(line)
	# Higher-priority state-aware topics appear first; equal priorities retain
	# the author's original JSON order (important for existing date choices).
	var available_choices: Array[Dictionary] = []
	var choice_index: int = 0
	for raw_choice in node.get("choices", []):
		var choice: Dictionary = raw_choice
		if _choice_available(choice):
			available_choices.append({"choice": choice, "order": choice_index})
		choice_index += 1
	available_choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left_priority: int = int(a["choice"].get("priority", 0))
		var right_priority: int = int(b["choice"].get("priority", 0))
		return int(a["order"]) < int(b["order"]) if left_priority == right_priority else left_priority > right_priority
	)
	for record in available_choices:
		var choice: Dictionary = record["choice"]
		var display_choice := DialogueChoiceData.new()
		display_choice.text = str(choice.get("text", ""))
		choice["_key"] = AffectionManager.choice_key(_current_path, id, display_choice.text)
		_choices.append(display_choice)
		_choice_defs.append(choice)
		_choice_greyed.append(AffectionManager.is_greyed(current_npc.npc_id, choice["_key"], choice))
	_check_for_end()

# Date reaction and outcome placeholders are resolved at display time.
# Date authors can replace these with real branches later without changing
# the scoring API or the three response styles.
func _format_date_placeholder(raw: String) -> String:
	if raw == "{{date_reaction}}":
		return DateManager.get_placeholder_reaction()
	if raw == "{{date_outcome}}":
		return DateManager.get_placeholder_outcome()
	return raw


func _check_for_end() -> void:
	if not is_active:
		return
	if not _graph.is_empty():
		if line_index >= _lines.size():
			var node: Dictionary = _graph["nodes"][_node_id]
			# Node effects fire only after all its lines have been read, once per visit.
			if not _choices.is_empty():
				if not _node_effects_applied:
					_apply_json_effects(node.get("effects", {}))
					_node_effects_applied = true
				return
			if not _node_effects_applied:
				_apply_json_effects(node.get("effects", {}))
				_node_effects_applied = true
			if node.has("next"):
				_enter_node(str(node["next"]))
			else:
				end_conversation()
		return
	if current_dialogue == null or (line_index >= current_dialogue.lines.size() and current_dialogue.choices.is_empty()):
		end_conversation()

func end_conversation() -> void:
	var finished_npc := current_npc
	var requested_scene := _scene_after_conversation
	# Authored dialogue flags remain compatible but no longer charge time.
	last_conversation_cost = 0
	_conversation_costs_action = true
	current_npc = null
	current_dialogue = null
	line_index = 0
	is_active = false
	_graph.clear()
	_node_id = ""
	_lines.clear()
	_choices.clear()
	_choice_defs.clear()
	_pending_choice.clear()
	_node_effects_applied = false
	_gift_player = null
	_expected_gift_item_id = &""
	_scene_after_conversation = ""
	_current_path = ""
	_current_speaker_alias = ""
	_choice_greyed.clear()
	_conversation_rotations.clear()
	conversation_finished.emit(finished_npc)
	if not requested_scene.is_empty():
		scene_requested.emit(finished_npc, requested_scene)
