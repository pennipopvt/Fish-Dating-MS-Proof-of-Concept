extends Node

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

func start_conversation(npc: NPCData) -> void:
	if is_active or npc == null:
		return
	var path := ""
	if not npc.encounter_rules.is_empty():
		path = NPCManager.get_encounter_json_path(npc)
		if path.is_empty():
			return
	else:
		path = npc.dialogue_json_path
	if not path.is_empty():
		var graph := DialogueJsonLoader.read_graph(path)
		if graph.is_empty():
			return
		current_npc = npc
		_graph = graph
		is_active = true
		_enter_node(str(graph["entry"]))
		return
	var dialogue: DialogueData = NPCManager.get_dialogue(npc)
	if dialogue == null:
		return
	current_npc = npc
	current_dialogue = dialogue
	line_index = 0
	is_active = true
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
	_check_for_end()

func select_choice(index: int) -> void:
	if not is_awaiting_choice():
		return
	if not _graph.is_empty():
		if index < 0 or index >= _choice_defs.size():
			return
		var choice: Dictionary = _choice_defs[index]
		_apply_json_effects(choice.get("effects", {}))
		_enter_node(str(choice["next"]))
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

func _apply_json_effects(effects: Variant) -> void:
	if not effects is Dictionary or current_npc == null:
		return
	var state: Dictionary = NPCManager.get_npc_state(current_npc.npc_id)
	state["attraction"] = int(state.get("attraction", 0)) + int(effects.get("attraction", 0))
	var flags: Dictionary = state.get("flags", {})
	state["flags"] = flags
	for flag in effects.get("set_flags", []):
		flags[StringName(str(flag))] = true
	for flag in effects.get("clear_flags", []):
		flags[StringName(str(flag))] = false

func _enter_node(id: String) -> void:
	var nodes: Dictionary = _graph["nodes"]
	if not nodes.has(id):
		push_error("Dialogue JSON missing node: " + id)
		end_conversation()
		return
	_node_id = id
	var node: Dictionary = nodes[id]
	_lines.clear()
	_choices.clear()
	_choice_defs.clear()
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
		var display_choice := DialogueChoiceData.new()
		display_choice.text = str(choice.get("text", ""))
		_choices.append(display_choice)
		_choice_defs.append(choice)
	_check_for_end()

func _check_for_end() -> void:
	if not is_active:
		return
	if not _graph.is_empty():
		if line_index >= _lines.size() and _choices.is_empty():
			var node: Dictionary = _graph["nodes"][_node_id]
			if node.has("next"):
				_enter_node(str(node["next"]))
			else:
				end_conversation()
		return
	if current_dialogue == null or (line_index >= current_dialogue.lines.size() and current_dialogue.choices.is_empty()):
		end_conversation()

func end_conversation() -> void:
	current_npc = null
	current_dialogue = null
	line_index = 0
	is_active = false
	_graph.clear()
	_node_id = ""
	_lines.clear()
	_choices.clear()
	_choice_defs.clear()
