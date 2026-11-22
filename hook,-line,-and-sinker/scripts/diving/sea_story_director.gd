extends Node
class_name SeaStoryDirector

# Only one-time events live here. The fishing, NPC and dialogue systems
# continue to own their normal behavior and persistent NPC state.
signal first_companion_catch_completed
signal silas_following_started
signal silas_surface_warning_finished
signal silas_surface_reveal_finished
signal silas_townhouse_dialogue_finished
signal silas_townhouse_arrival_finished
signal dialogue_mode_requested(underwater_portraits: bool)
signal kuda_hook_dialogue_finished
signal kuda_recruited
signal kuda_surface_reveal_finished
signal kuda_townhouse_dialogue_finished
signal kuda_townhouse_arrival_finished

@export var silas_data: NPCData = preload("res://resources/npcs/silas.tres")
@export var kuda_data: NPCData = preload("res://resources/npcs/kuda.tres")
@export_file("*.json") var oxygen_recovery_dialogue: String = "res://dialogue/oxygen_blackout_recovery.json"
@export_file("*.json") var first_land_rescue_dialogue: String = "res://dialogue/oxygen_first_land_rescue.json"

var _events: Dictionary = {}
var _dialogue_stage: StringName = &""
var _kuda_dialogue_stage: StringName = &""
var _kuda_bubble_speaker: Node2D
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


func has_kuda_flag(id: StringName) -> bool:
	return bool(NPCManager.get_npc_state(kuda_data.npc_id)["flags"].get(id, false))


func show_kuda_chase_bubble(speaker: Node2D, message: String) -> bool:
	var ui: SeaSpeechBubble = _bubble()
	if ui == null or not ui.is_node_ready() or ui.is_call_active():
		return false
	ui.show_attached_call(message, speaker, 2.8)
	_kuda_bubble_speaker = speaker
	return ui.is_call_shown()


func hide_kuda_chase_bubble() -> void:
	var ui: SeaSpeechBubble = _bubble()
	if ui != null and is_instance_valid(_kuda_bubble_speaker) \
			and ui._speaker == _kuda_bubble_speaker:
		ui.hide_call()
	_kuda_bubble_speaker = null


func on_silas_refuses_kuda_hunt() -> void:
	if DialogueManager.is_active:
		return
	if not has_event(&"silas_kuda_refusal"):
		hide_kuda_chase_bubble()
		DialogueManager.request_conversation(silas_data,
			"res://dialogue/silas_refuses_kuda.json")
		if DialogueManager.is_active:
			_events[&"silas_kuda_refusal"] = true
	else:
		_show_silas_bubble("No way! I'm staying out of that.", 2.5)


func start_kuda_hook_dialogue() -> bool:
	if DialogueManager.is_active or has_event(&"kuda_first_net_dialogue"):
		return false
	hide_kuda_chase_bubble()
	_kuda_dialogue_stage = &"hook"
	DialogueManager.request_conversation(kuda_data, "res://dialogue/kuda_net_hook.json")
	if DialogueManager.is_active:
		_events[&"kuda_first_net_dialogue"] = true
		return true
	_kuda_dialogue_stage = &""
	return false


func start_kuda_caught_dialogue() -> bool:
	if DialogueManager.is_active:
		return false
	_kuda_dialogue_stage = &"caught"
	DialogueManager.request_conversation(kuda_data,
		"res://dialogue/kuda_underwater_caught.json")
	if DialogueManager.is_active:
		return true
	_kuda_dialogue_stage = &""
	return false


func can_begin_kuda_surface_reveal() -> bool:
	return has_kuda_flag(&"Recruited") \
		and not has_kuda_flag(&"kuda_surface_introduced") \
		and not DialogueManager.is_active


# Kuda is already in the party. His first human-form surprise happens only
# after the shared surface poof, and uses the normal dialogue UI/JSON.
func start_kuda_surface_reveal(present_cast: Array[NPCData] = []) -> bool:
	if not can_begin_kuda_surface_reveal():
		return false
	_kuda_dialogue_stage = &"surface_reveal"
	dialogue_mode_requested.emit(false)
	# DialogueManager chooses per-line speakers from this actual returning
	# party, while Kuda remains the owner of the entire introduction.
	DialogueManager.request_conversation(kuda_data,
		"res://dialogue/kuda_surface_reveal.json", null, present_cast)
	if not DialogueManager.is_active:
		DialogueManager.request_inline_conversation(kuda_data,
			["Wait, I have LEGS?!", "What just happened to me?!"], "Kuda")
	if not DialogueManager.is_active:
		_kuda_dialogue_stage = &""
		return false
	return true


# Same existing dialogue UI and JSON authoring, with optional first-land
# lines inserted into the ONE recovery conversation. Silas/Kuda each speak
# only if they genuinely transformed for the first time on this blackout.
# A transient context prevents affection or relationship-story side effects.
func play_oxygen_blackout_recovery(present_cast: Array[NPCData],
		first_land_ids: Array[StringName] = []) -> void:
	if present_cast.is_empty():
		return
	if DialogueManager.is_active:
		await DialogueManager.conversation_finished
	var context := NPCData.new()
	context.npc_id = &"oxygen_blackout_story"
	context.display_name = "Penni's companions"
	context.portrait = present_cast[0].portrait
	var base_graph: Dictionary = DialogueJsonLoader.read_graph(oxygen_recovery_dialogue)
	var base_node: Dictionary = base_graph.get("nodes", {}).get("shore", {})
	var authored: Array = base_node.get("lines", [])
	var lines: Array[Dictionary] = []
	for entry in authored:
		if entry is Dictionary:
			lines.append(entry)
		elif entry is String:
			lines.append({"text": entry})
		# Put the surprise directly after Penni wakes and her friends react.
		if lines.size() == 3 and not first_land_ids.is_empty():
			var first_graph: Dictionary = DialogueJsonLoader.read_graph(first_land_rescue_dialogue)
			var nodes: Dictionary = first_graph.get("nodes", {})
			for npc_id in first_land_ids:
				var special_node: Dictionary = nodes.get(
					"silas_first" if npc_id == silas_data.npc_id else
					"kuda_first" if npc_id == kuda_data.npc_id else "", {})
				for special_line in special_node.get("lines", []):
					if special_line is Dictionary:
						lines.append(special_line)
	dialogue_mode_requested.emit(false)
	DialogueManager.request_group_lines(context, lines, present_cast)
	if DialogueManager.is_active and DialogueManager.current_npc == context:
		await DialogueManager.conversation_finished


func mark_kuda_surface_rescued() -> void:
	# The human transformation was already seen at wake-up; the room scene
	# is still separate and will assign residence after dialogue.
	NPCManager.get_npc_state(kuda_data.npc_id)["flags"][&"kuda_surface_introduced"] = true
	kuda_surface_reveal_finished.emit()


func mark_silas_surface_rescued() -> void:
	# Skip Silas's fish-jump warning/reveal, not his welcome or his room.
	_events[&"silas_surface_scene_started"] = true
	_set_silas_flag(&"silas_surface_transformed")
	_set_silas_flag(&"silas_waiting_at_dock")
	_npc_flags()[&"silas_following"] = false
	silas_surface_reveal_finished.emit()


# Penni returns with an injured fish who has never reached land. The
# normal shore actor and townhouse hooks handle their first transformation
# and housing; only the words describing WHO rescued whom are different.
func play_first_land_care_dialogue(npc: NPCData,
		present_cast: Array[NPCData]) -> void:
	if npc == null or npc.sea_first_land_after_knockout_json.is_empty():
		return
	if DialogueManager.is_active:
		await DialogueManager.conversation_finished
	var context := NPCData.new()
	context.npc_id = StringName("first_land_care_%s" % String(npc.npc_id))
	context.display_name = npc.display_name
	context.portrait = npc.portrait
	dialogue_mode_requested.emit(false)
	DialogueManager.request_conversation(context,
		npc.sea_first_land_after_knockout_json, null, present_cast)
	if DialogueManager.is_active and DialogueManager.current_npc == context:
		await DialogueManager.conversation_finished


# Shared dialogue system and persistent NPC flags; Kuda's physical presentation
# remains in SeaKudaEncounter, just like Silas's in SeaEncounterSequence.
func start_kuda_townhouse_arrival() -> void:
	_kuda_dialogue_stage = &"townhouse_arrival"
	dialogue_mode_requested.emit(false)
	DialogueManager.request_conversation(kuda_data,
		"res://dialogue/kuda_townhouse_arrival.json")
	if not DialogueManager.is_active:
		DialogueManager.request_inline_conversation(kuda_data,
			["This is the townhouse?", "Fine. I'll take a room.", "Thanks, Penni."], "Kuda")


func complete_kuda_townhouse_arrival() -> void:
	var flags: Dictionary = NPCManager.get_npc_state(kuda_data.npc_id)["flags"]
	flags[&"kuda_has_home"] = true
	kuda_townhouse_arrival_finished.emit()


# World discoveries can use a shared queue rather than opening DialogueUI
# over a fight. The event identity and any persistent flags remain story-owned.
func queue_world_conversation(event_id: StringName, context: NPCData,
		dialogue_path: String, cast: Array[NPCData] = [], priority: int = 0) -> bool:
	var sea: DivingWorld = get_parent() as DivingWorld
	return sea.queue_world_dialogue(event_id, context, dialogue_path, cast, priority) \
		if sea != null else false


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
	# Use the existing JSON dialogue system so this introduction can be edited
	# without changing story or encounter scripts. Silas only follows after it ends.
	DialogueManager.request_conversation(silas_data, "res://dialogue/silas_rescue_intro.json")
	if not DialogueManager.is_active:
		# Keep the existing rescue playable if the JSON gets edited incorrectly.
		push_warning("Silas rescue dialogue unavailable; using short fallback.")
		DialogueManager.request_inline_conversation(
			silas_data, ["I'm free!", "Thank you... I thought I'd never get out."], "Silas"
		)
	var ui: SeaSpeechBubble = _bubble()
	if ui != null:
		ui.hide_call()


func _on_conversation_finished(finished_npc: NPCData) -> void:
	if finished_npc == kuda_data:
		var stage: StringName = _kuda_dialogue_stage
		_kuda_dialogue_stage = &""
		if stage == &"hook":
			kuda_hook_dialogue_finished.emit()
		elif stage == &"caught":
			# The JSON also sets Recruited. Finalize the roster only AFTER
			# the player has finished reading the conversation.
			NPCManager.get_npc_state(kuda_data.npc_id)["flags"][&"Recruited"] = true
			kuda_recruited.emit()
		elif stage == &"surface_reveal":
			NPCManager.get_npc_state(kuda_data.npc_id)["flags"][&"kuda_surface_introduced"] = true
			kuda_surface_reveal_finished.emit()
		elif stage == &"townhouse_arrival":
			kuda_townhouse_dialogue_finished.emit()
		return
	if finished_npc != silas_data:
		return
	if _dialogue_stage == &"introduction":
		_set_silas_flag(&"silas_met")
	elif _dialogue_stage == &"rescue":
		_set_silas_flag(&"silas_following")
		silas_following_started.emit()
	elif _dialogue_stage == &"surface_warning":
		_dialogue_stage = &""
		silas_surface_warning_finished.emit()
		return
	elif _dialogue_stage == &"surface_reveal":
		_set_silas_flag(&"silas_surface_transformed")
		_set_silas_flag(&"silas_waiting_at_dock")
		_dialogue_stage = &""
		silas_surface_reveal_finished.emit()
		return
	elif _dialogue_stage == &"townhouse_arrival":
		_dialogue_stage = &""
		silas_townhouse_dialogue_finished.emit()
		return
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



# Silas stops fighting at his nonlethal threshold every time.
# The automatic retreat warning is one-time to avoid interrupting combat.
# An explicit player command to hurt an already-wounded fish is different:
# it always opens his authored dialogue so Penni can respond to his boundary.
func on_silas_spared_fish(_fish: DivingWildFish) -> void:
	if has_event(&"silas_nonlethal_explained") or DialogueManager.is_active:
		return
	if _show_silas_bubble("Penni... I'm scared I'll hurt it more.", 4.5):
		_events[&"silas_nonlethal_explained"] = true


func on_silas_attack_refused(_fish: DivingWildFish) -> void:
	if DialogueManager.is_active:
		return
	# Direct player orders can trigger dialogue every time, even after the
	# one-time automatic warning. Do not spam or overwrite active dialogue.
	var ui: SeaSpeechBubble = _bubble()
	if ui != null:
		ui.hide_call()
	DialogueManager.request_conversation(silas_data, "res://dialogue/silas_refuses_attack.json")
	if DialogueManager.is_active:
		_events[&"silas_nonlethal_explained"] = true


# Surfacing itself is always allowed. Only Silas's FIRST return adds a scene.
# The first departure is part of the companion tutorial, not a free exit.
# The condition is a successful net catch of a fish Silas actually damaged.
func can_surface() -> bool:
	return has_event(&"first_companion_catch") or has_silas_flag(&"silas_surface_transformed")


func on_first_companion_catch(fish: DivingWildFish) -> void:
	if fish == null or not fish.companion_weakened or not has_silas_flag(&"silas_following") \
			or has_event(&"first_companion_catch"):
		return
	_events[&"first_companion_catch"] = true
	first_companion_catch_completed.emit()
	var cue: SeaTutorialCue = _cue()
	if cue != null:
		cue.hide_action()


func on_surface_blocked() -> void:
	if DialogueManager.is_active:
		return
	var message: String = "I should help that fish first." if has_silas_flag(&"silas_met") \
		and not has_silas_flag(&"silas_freed") else (
		"We should try catching a fish together before going back."
		if has_silas_flag(&"silas_following") else
		"I don't think I'm done down here yet."
	)
	DialogueManager.request_player_monologue([message])


func can_begin_silas_surface_reveal() -> bool:
	return has_silas_flag(&"silas_following") \
		and not has_silas_flag(&"silas_surface_transformed") \
		and not has_event(&"silas_surface_scene_started") \
		and not DialogueManager.is_active


func begin_silas_surface_reveal() -> bool:
	if not can_begin_silas_surface_reveal():
		return false
	_events[&"silas_surface_scene_started"] = true
	return true


func start_silas_surface_warning() -> void:
	_dialogue_stage = &"surface_warning"
	# Silas is still a fish for the warning conversation.
	dialogue_mode_requested.emit(true)
	DialogueManager.request_conversation(silas_data, "res://dialogue/silas_surface_warning.json")
	if not DialogueManager.is_active:
		DialogueManager.request_inline_conversation(
			silas_data,
			["Penni! Wait for me!", "I-I thought I could come with you..."],
			"Silas"
		)


# Called by the existing SeaEncounterSequence after the fade to the house.
func start_silas_townhouse_arrival() -> void:
	_dialogue_stage = &"townhouse_arrival"
	dialogue_mode_requested.emit(false)
	DialogueManager.request_conversation(silas_data, "res://dialogue/silas_townhouse_arrival.json")
	if not DialogueManager.is_active:
		DialogueManager.request_inline_conversation(
			silas_data, ["This is where I'll be staying?", "Thank you, Penni!"], "Silas"
		)


func complete_silas_townhouse_arrival() -> void:
	var flags: Dictionary = _npc_flags()
	flags[&"silas_waiting_at_dock"] = false
	flags[&"silas_has_home"] = true
	silas_townhouse_arrival_finished.emit()


func on_silas_surface_transformed() -> void:
	# The dock dialogue is NOT the residence assignment. That happens
	# only after the townhouse conversation and second fade.
	var flags: Dictionary = _npc_flags()
	flags[&"silas_following"] = false
	_dialogue_stage = &"surface_reveal"
	dialogue_mode_requested.emit(false)
	DialogueManager.request_conversation(silas_data, "res://dialogue/silas_surface_reveal.json")
	if not DialogueManager.is_active:
		DialogueManager.request_inline_conversation(
			silas_data, ["AAH! I have legs?!", "I guess I'll wait here for now."], "Silas"
		)
