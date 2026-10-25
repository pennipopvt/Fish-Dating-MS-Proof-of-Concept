
extends Node

var current_npc: NPCData = null
var current_dialogue: DialogueData = null
var line_index: int = 0
var is_active: bool = false


# Start a conversation with an NPC.
func start_conversation(npc: NPCData) -> void:
	if is_active or npc == null:
		return

	var dialogue: DialogueData = NPCManager.get_dialogue(npc)

	if dialogue == null:
		return

	current_npc = npc
	current_dialogue = dialogue
	line_index = 0
	is_active = true

	_check_for_end()


# Get the current line for the UI to display.
func get_current_line() -> DialogueLineData:
	if not is_active or current_dialogue == null:
		return null

	if line_index >= current_dialogue.lines.size():
		return null

	return current_dialogue.lines[line_index]


# Check if the player needs to select a choice.
func is_awaiting_choice() -> bool:
	if not is_active or current_dialogue == null:
		return false

	return (
		line_index >= current_dialogue.lines.size()
		and not current_dialogue.choices.is_empty()
	)


# Get the available choices for the UI.
func get_choices() -> Array[DialogueChoiceData]:
	if is_awaiting_choice():
		return current_dialogue.choices

	return []


# Advance to the next line.
func advance() -> void:
	if not is_active or is_awaiting_choice():
		return

	line_index += 1
	_check_for_end()


# Select a choice by its index.
func select_choice(index: int) -> void:
	if not is_awaiting_choice():
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


# End the conversation if there is nothing left.
func _check_for_end() -> void:
	if current_dialogue == null:
		end_conversation()
		return

	if (
		line_index >= current_dialogue.lines.size()
		and current_dialogue.choices.is_empty()
	):
		end_conversation()


# Reset conversation state.
func end_conversation() -> void:
	current_npc = null
	current_dialogue = null
	line_index = 0
	is_active = false
