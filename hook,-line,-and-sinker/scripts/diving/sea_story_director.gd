extends Node
class_name SeaStoryDirector

# Only one-time events live here. The fishing, NPC and dialogue systems
# continue to own their normal behavior and persistent NPC state.
signal silas_following_started

@export var silas_data: NPCData = preload("res://resources/npcs/silas.tres")

var _events: Dictionary = {}
var _dialogue_stage: StringName = &""


func _ready() -> void:
	DialogueManager.conversation_finished.connect(_on_conversation_finished)


func _bubble() -> SeaSpeechBubble:
	return get_tree().get_first_node_in_group("sea_speech_bubble") as SeaSpeechBubble


func has_event(id: StringName) -> bool:
	return bool(_events.get(id, false))


func _npc_flags() -> Dictionary:
	return NPCManager.get_npc_state(silas_data.npc_id)["flags"]


func has_silas_flag(id: StringName) -> bool:
	return bool(_npc_flags().get(id, false))


func _set_silas_flag(id: StringName) -> void:
	var flags: Dictionary = _npc_flags()
	flags[id] = true


func on_dive_entered() -> void:
	var ui: SeaSpeechBubble = _bubble()
	if ui == null:
		return
	if not has_event(&"line_broken"):
		ui.show_hint("LEFT CLICK: cast your net at the first fish")
	elif not has_silas_flag(&"silas_met"):
		ui.show_hint("Follow the voice. Press E near the eel.")
	elif not has_silas_flag(&"silas_freed"):
		ui.show_hint("LEFT CLICK: net Silas to pull him free")
	elif has_silas_flag(&"silas_following") and not has_event(&"companion_targeted"):
		ui.show_hint("RIGHT CLICK a fish to send Silas")


func wants_scripted_hook(fish: DivingWildFish, tutorial_fish: DivingWildFish) -> bool:
	return not has_event(&"line_broken") and fish != null and fish == tutorial_fish


func on_scripted_hook() -> void:
	_events[&"tutorial_hooked"] = true
	var ui: SeaSpeechBubble = _bubble()
	if ui != null:
		ui.show_hint("SCROLL DOWN: reel the fish")


func consume_first_reel() -> bool:
	if not has_event(&"tutorial_hooked") or has_event(&"line_broken"):
		return false
	_events.erase(&"tutorial_hooked")
	_events[&"line_broken"] = true
	var ui: SeaSpeechBubble = _bubble()
	if ui != null:
		ui.show_hint("The line broke! Follow the voice to the left.")
		ui.show_call("Help me!", false, 5.0)
	return true


func can_talk_to_silas() -> bool:
	return has_event(&"line_broken") and not has_silas_flag(&"silas_freed")


func can_net_silas() -> bool:
	return has_silas_flag(&"silas_met") and not has_silas_flag(&"silas_freed")


func talk_to_silas() -> void:
	if not can_talk_to_silas() or DialogueManager.is_active:
		return
	if not has_silas_flag(&"silas_met"):
		_dialogue_stage = &"introduction"
		var lines: Array[String] = ["Help me! I'm tangled in this net.", "Can you pull me free?"]
		DialogueManager.request_inline_conversation(silas_data, lines, "???")
	else:
		var reminder: Array[String] = ["I can't move like this... Can you use your net?"]
		DialogueManager.request_inline_conversation(silas_data, reminder, "Silas")


func on_silas_rescued() -> void:
	if has_silas_flag(&"silas_freed"):
		return
	_set_silas_flag(&"silas_freed")
	_dialogue_stage = &"rescue"
	var lines: Array[String] = ["I'm free!", "Thank you... I thought I'd never get out."]
	DialogueManager.request_inline_conversation(silas_data, lines, "Silas")
	var ui: SeaSpeechBubble = _bubble()
	if ui != null:
		ui.hide_call()
		ui.hide_hint()


func _on_conversation_finished(finished_npc: NPCData) -> void:
	if finished_npc != silas_data:
		return
	if _dialogue_stage == &"introduction":
		_set_silas_flag(&"silas_met")
		var ui: SeaSpeechBubble = _bubble()
		if ui != null:
			ui.show_hint("LEFT CLICK: cast your net at Silas")
	elif _dialogue_stage == &"rescue":
		_set_silas_flag(&"silas_following")
		silas_following_started.emit()
		var ui: SeaSpeechBubble = _bubble()
		if ui != null:
			ui.show_hint("Explore with Silas")
	_dialogue_stage = &""


func maybe_offer_companion_help(player_position: Vector2, fish_list: Array[DivingWildFish]) -> void:
	if not has_silas_flag(&"silas_following") or has_event(&"companion_help_offered"):
		return
	for fish in fish_list:
		if is_instance_valid(fish) and not fish.trapped and fish.position.distance_to(player_position) < 130.0:
			_events[&"companion_help_offered"] = true
			var ui: SeaSpeechBubble = _bubble()
			if ui != null:
				ui.show_call("I can help with that fish.", false, 4.5)
				ui.show_hint("RIGHT CLICK a fish to tell Silas to attack")
			return


func on_companion_targeted() -> void:
	_events[&"companion_targeted"] = true
	var ui: SeaSpeechBubble = _bubble()
	if ui != null:
		ui.hide_call()
		ui.show_hint("Silas attacks automatically. Right click again to call him back.")
