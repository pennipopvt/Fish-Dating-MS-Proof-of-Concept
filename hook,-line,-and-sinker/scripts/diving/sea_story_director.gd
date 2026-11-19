extends Node
class_name SeaStoryDirector

# Only one-time events live here. The fishing, NPC and dialogue systems
# continue to own their normal behavior and persistent NPC state.
signal silas_following_started

@export var silas_data: NPCData = preload("res://resources/npcs/silas.tres")

var _events: Dictionary = {}
var _dialogue_stage: StringName = &""
var _missing_bubble_warned: bool = false
var _help_trigger_logged: bool = false
var _speech_bubble: SeaSpeechBubble
var _help_ui_pending: bool = false
var _help_retry_time: float = 0.0


func bind_speech_bubble(bubble: SeaSpeechBubble) -> void:
	# Main owns the UI. Inject its exact scene instance once Main is ready.
	_speech_bubble = bubble
	if _speech_bubble == null:
		push_warning("Main has no SeaSpeechBubble to bind to the story.")



func _ready() -> void:
	DialogueManager.conversation_finished.connect(_on_conversation_finished)


func _process(delta: float) -> void:
	if not _help_ui_pending:
		return
	_help_retry_time -= delta
	if _help_retry_time > 0.0:
		return
	_help_retry_time = 0.6
	var ui: SeaSpeechBubble = _bubble()
	if ui != null and ui.is_call_active():
		# Waiting between repeated cries is deliberate, not a missing UI.
		return
	if _show_silas_bubble("Help me!"):
		print("[SEA STORY] Pending help bubble restored")
	else:
		print("[SEA STORY] Help triggered; bubble still unavailable")


func _bubble() -> SeaSpeechBubble:
	# Do not walk across viewports here. Main injects the real UI node.
	# The group fallback keeps standalone sea tests/dev scenes safe.
	if is_instance_valid(_speech_bubble):
		return _speech_bubble
	return get_tree().get_first_node_in_group("sea_speech_bubble") as SeaSpeechBubble


func _show_silas_bubble(message: String, seconds: float = 0.0) -> bool:
	var ui: SeaSpeechBubble = _bubble()
	if ui == null or not ui.is_node_ready():
		# The story beat must not be consumed when the presentation is
		# missing. DivingWorld will retry the trigger on a later frame.
		if not _missing_bubble_warned:
			push_warning("SeaSpeechBubble was not bound from Main; Silas call will retry.")
			_missing_bubble_warned = true
		return false
	_missing_bubble_warned = false
	var speaker: Node2D = get_parent().get_node_or_null("NPCs/Silas") as Node2D
	if speaker != null:
		ui.show_attached_call(message, speaker, seconds)
	else:
		ui.show_call(message, false, seconds)
	if not ui.is_call_shown():
		push_warning("Silas speech bubble did not become visible; will retry the story beat.")
		return false
	return true


func _cue() -> SeaTutorialCue:
	# Direct node lookup in the SAME SubViewport as the Player and camera.
	# No dependency on Main's CanvasLayer or cross-viewport group ordering.
	return get_parent().get_parent().get_node_or_null(
		"Player/Camera2D/SeaTutorialCue"
	) as SeaTutorialCue


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
	if not has_event(&"line_broken") and not has_event(&"help_called"):
		var cue: SeaTutorialCue = _cue()
		if cue == null:
			push_warning("SeaTutorialCue is missing from the Player camera.")
			return
		if has_event(&"tutorial_hooked"):
			cue.show_action(&"reel")
		elif has_event(&"fish_focus_seen") and not has_event(&"first_cast"):
			cue.show_action(&"cast")
		elif not has_event(&"first_cast"):
			cue.show_action(&"move")
		return

# The camera/player pause is deliberately a one-time moment. Core player
# controls are unchanged; the sea controller releases its own movement lock.
func wants_first_fish_focus() -> bool:
	return not has_event(&"fish_focus_seen") and not has_event(&"first_cast") \
		and not has_event(&"line_broken") and not has_event(&"help_called")


func on_first_fish_seen() -> bool:
	if not wants_first_fish_focus():
		return false
	var cue: SeaTutorialCue = _cue()
	# Never take control unless the in-world camera cue is visible.
	if cue == null or not cue.show_action(&"cast"):
		return false
	_events[&"fish_focus_seen"] = true
	return true


func on_first_cast() -> void:
	if has_event(&"first_cast"):
		return
	_events[&"first_cast"] = true
	var cue: SeaTutorialCue = _cue()
	if cue != null:
		cue.hide_action()


func wants_scripted_hook(fish: DivingWildFish, tutorial_fish: DivingWildFish) -> bool:
	return not has_event(&"line_broken") and not has_event(&"help_called") \
		and fish != null and fish == tutorial_fish


func on_scripted_hook() -> void:
	_events[&"tutorial_hooked"] = true
	var cue: SeaTutorialCue = _cue()
	if cue != null:
		cue.show_action(&"reel")


func on_tutorial_hook_cancelled() -> void:
	_events.erase(&"tutorial_hooked")
	var cue: SeaTutorialCue = _cue()
	if cue != null:
		cue.show_action(&"cast")


func on_first_fish_escaped() -> void:
	if has_event(&"penni_fish_reaction") or DialogueManager.is_active:
		return
	DialogueManager.request_player_monologue(["Damn, it got away."])
	# A missing/hidden DialogueUI must not silently consume the reaction.
	# DivingWorld retries this event after the escape until it is received.
	if DialogueManager.is_active:
		_events[&"penni_fish_reaction"] = true
		print("[SEA STORY] Penni reacts to the escaped fish")


func consume_first_reel() -> bool:
	if not has_event(&"tutorial_hooked") or has_event(&"line_broken"):
		return false
	_events.erase(&"tutorial_hooked")
	_events[&"line_broken"] = true
	var cue: SeaTutorialCue = _cue()
	if cue != null:
		cue.hide_action()
	# Fish escape animation and player movement run in DivingWorld.
	# The actual offscreen voice is a separate one-time story beat.
	return true


func on_followed_escape(near_silas: bool = false) -> void:
	if has_event(&"help_called") or (not has_event(&"line_broken") and not near_silas):
		return
	# A story event must not depend on whether the graphics can render.
	_events[&"help_called"] = true
	_help_ui_pending = true
	_help_retry_time = 0.6
	print("[SEA STORY] Help trigger FIRED: near_silas=%s line_broken=%s" % [
		str(near_silas), str(has_event(&"line_broken"))])
	if _show_silas_bubble("Help me!"):
		print("[SEA STORY] Help bubble visible")
	else:
		print("[SEA STORY] Help bubble unavailable; will retry")


func can_talk_to_silas() -> bool:
	return has_event(&"help_called") and not has_silas_flag(&"silas_freed")


func can_net_silas() -> bool:
	return has_silas_flag(&"silas_met") and not has_silas_flag(&"silas_freed")


func talk_to_silas() -> void:
	if not can_talk_to_silas() or DialogueManager.is_active:
		return
	_help_ui_pending = false
	var ui: SeaSpeechBubble = _bubble()
	if ui != null:
		ui.hide_call()
	if not has_silas_flag(&"silas_met"):
		_dialogue_stage = &"introduction"
		var lines: Array[String] = ["Help me! I'm tangled in this net.", "Can you pull me free?"]
		DialogueManager.request_inline_conversation(silas_data, lines, "???")
	else:
		var reminder: Array[String] = ["I can't move like this... Can you use your net?"]
		DialogueManager.request_inline_conversation(silas_data, reminder, "Silas")


func on_silas_rescue_started() -> void:
	var cue: SeaTutorialCue = _cue()
	if cue != null:
		cue.show_action(&"reel")


func on_silas_rescue_cancelled() -> void:
	var cue: SeaTutorialCue = _cue()
	if cue != null:
		cue.hide_action()


func on_silas_rescued() -> void:
	if has_silas_flag(&"silas_freed"):
		return
	on_silas_rescue_cancelled()
	_help_ui_pending = false
	_set_silas_flag(&"silas_freed")
	_dialogue_stage = &"rescue"
	var lines: Array[String] = ["I'm free!", "Thank you... I thought I'd never get out."]
	DialogueManager.request_inline_conversation(silas_data, lines, "Silas")
	var ui: SeaSpeechBubble = _bubble()
	if ui != null:
		ui.hide_call()


func _on_conversation_finished(finished_npc: NPCData) -> void:
	if finished_npc != silas_data:
		return
	if _dialogue_stage == &"introduction":
		_set_silas_flag(&"silas_met")
	elif _dialogue_stage == &"rescue":
		_set_silas_flag(&"silas_following")
		silas_following_started.emit()
	_dialogue_stage = &""


func maybe_offer_companion_help(player_position: Vector2, fish_list: Array[DivingWildFish]) -> void:
	if not has_silas_flag(&"silas_following") or has_event(&"companion_help_offered"):
		return
	for fish in fish_list:
		if is_instance_valid(fish) and not fish.trapped and fish.position.distance_to(player_position) < 130.0:
			_events[&"companion_help_offered"] = true
			_show_silas_bubble("I can help with that fish.", 4.5)
			var cue: SeaTutorialCue = _cue()
			if cue != null:
				cue.show_action(&"command")
			return


func on_companion_targeted() -> void:
	_events[&"companion_targeted"] = true
	var cue: SeaTutorialCue = _cue()
	if cue != null:
		cue.hide_action()
	var ui: SeaSpeechBubble = _bubble()
	if ui != null:
		ui.hide_call()
