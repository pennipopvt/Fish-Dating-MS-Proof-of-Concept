extends Node

signal dialogue_requested(npc: NPCData)
signal conversation_started(npc: NPCData)
signal conversation_finished(npc: NPCData)
# Animation cues from JSON nodes and special-scene requests after a conversation ends.
signal dialogue_cue(npc: NPCData, cue: String)
signal scene_requested(npc: NPCData, scene_id: String)

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

func start_conversation(npc: NPCData, json_override: String = "") -> void:
	if is_active or npc == null:
		return
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
		_current_path = path
		is_active = true
		conversation_started.emit(npc)
		_enter_node(str(graph["entry"]))
		return
	var dialogue: DialogueData = NPCManager.get_dialogue(npc)
	if dialogue == null:
		return
	current_npc = npc
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
	# Affection goes through AffectionManager (tone or exact number, first pick only).
	AffectionManager.on_choice_picked(current_npc, str(choice.get("_key", "")), choice)
	_apply_json_effects(choice.get("effects", {}), false)
	_enter_node(str(choice["next"]))

func _apply_json_effects(effects: Variant, include_attraction: bool = true) -> void:
	if not effects is Dictionary or current_npc == null:
		return
	if effects.get("give_held_item", false):
		NPCManager.accept_gift(current_npc, _gift_player, _expected_gift_item_id)
	if effects.has("request_scene"):
		_scene_after_conversation = str(effects["request_scene"])
	if include_attraction:
		AffectionManager.change(current_npc.npc_id, int(effects.get("attraction", 0)))
	var state: Dictionary = NPCManager.get_npc_state(current_npc.npc_id)
	var flags: Dictionary = state.get("flags", {})
	state["flags"] = flags
	for flag in effects.get("set_flags", []):
		flags[StringName(str(flag))] = true
	for flag in effects.get("clear_flags", []):
		flags[StringName(str(flag))] = false


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
	return true

func _enter_node(id: String) -> void:
	var nodes: Dictionary = _graph["nodes"]
	if not nodes.has(id):
		push_error("Dialogue JSON missing node: " + id)
		end_conversation()
		return
	_node_id = id
	_node_effects_applied = false
	var node: Dictionary = nodes[id]
	if node.has("cue"):
		dialogue_cue.emit(current_npc, str(node["cue"]))
	_lines.clear()
	_choices.clear()
	_choice_defs.clear()
	_choice_greyed.clear()
	line_index = 0
	for raw_line in node.get("lines", []):
		var line := DialogueLineData.new()
		if raw_line is String:
			line.text = raw_line
		elif raw_line is Dictionary:
			line.text = str(raw_line.get("text", ""))
			line.speaker = DialogueLineData.Speaker.PLAYER if raw_line.get("speaker", "npc") == "player" else DialogueLineData.Speaker.NPC
			line.expression = StringName(str(raw_line.get("expression", "neutral")))
		else:
			continue
		_lines.append(line)
	for raw_choice in node.get("choices", []):
		var choice: Dictionary = raw_choice
		if not _choice_available(choice):
			continue
		var display_choice := DialogueChoiceData.new()
		display_choice.text = str(choice.get("text", ""))
		choice["_key"] = AffectionManager.choice_key(_current_path, id, display_choice.text)
		_choices.append(display_choice)
		_choice_defs.append(choice)
		_choice_greyed.append(AffectionManager.is_greyed(current_npc.npc_id, choice["_key"], choice))
	_check_for_end()

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
	_choice_greyed.clear()
	conversation_finished.emit(finished_npc)
	if not requested_scene.is_empty():
		scene_requested.emit(finished_npc, requested_scene)
