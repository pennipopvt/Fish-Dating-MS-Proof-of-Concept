class_name NPCRoomView
extends Control

# One first-person room overlay, keeping the existing DialogueUI and its
# natural conversational chaining. The romance sequence is driven by arriving
# at night after accepting an invitation, NOT by choosing a dialogue option.
@onready var _background: TextureRect = $Background
var _dialogue: DialogueUI
var _transition: SeaDiveTransition
var _illustration: IllustrationSceneController
var _player: Player
var _resident: NPCData
var _inside: bool = false
var _closing: bool = false
var _dialogue_exit_requested: bool = false
var _gift_offered_this_visit: bool = false
var _overnight_active: bool = false
var _morning_dialogue_active: bool = false


func configure(dialogue: DialogueUI, transition: SeaDiveTransition, player: Player,
		illustration: IllustrationSceneController = null) -> void:
	_dialogue = dialogue
	_transition = transition
	_player = player
	_illustration = illustration
	DialogueManager.conversation_finished.connect(_on_conversation_finished)
	DialogueManager.scene_requested.connect(_on_scene_requested)
	if _illustration != null:
		_illustration.scene_finished.connect(_on_illustration_finished)


func open_room(npc: NPCData) -> void:
	if npc == null or _inside or _closing or _transition.transitioning or DialogueManager.is_active:
		return
	_resident = npc
	_gift_offered_this_visit = false
	_inside = true
	_player.busy = true
	await _transition.iris_swap(_show_room)
	if not _try_start_overnight():
		_start_conversation()


func _show_room() -> void:
	_background.texture = _resident.room_background
	_dialogue.set_room_mode(true)
	show()


# Only entering a room at night with a previously accepted invitation starts
# the one-time romance. Existing invitation JSON remains ordinary conversation.
func _try_start_overnight() -> bool:
	if _illustration == null or _resident == null or not GameManager.is_period(GameManager.Times.NIGHT):
		return false
	if _resident.invitation_accepted_flag == &"" or _resident.romance_complete_flag == &"":
		return false
	var flags: Dictionary = NPCManager.get_npc_state(_resident.npc_id).get("flags", {})
	if not flags.get(_resident.invitation_accepted_flag, false) \
			or flags.get(_resident.romance_complete_flag, false):
		return false
	_overnight_active = true
	if _illustration.start_scene(_resident):
		return true
	_overnight_active = false
	return false


func _start_conversation() -> void:
	if not _inside or _closing or _overnight_active or DialogueManager.is_active:
		return
	# Preserve the existing gift-then-casual conversation behavior. Only the
	# timing of invitation eligibility changes in NPCManager's encounter rules.
	if not _gift_offered_this_visit and _player.held_item != null:
		var gift_path: String = NPCManager.get_gift_encounter_path(_resident, _player.held_item)
		if not gift_path.is_empty():
			_gift_offered_this_visit = true
			DialogueManager.request_conversation(_resident, gift_path, _player)
			return
	DialogueManager.request_conversation(_resident)
	if not DialogueManager.is_active:
		DialogueManager.request_inline_conversation(_resident, ["Oh, hi, Penni!"], "",
			[{"text": "Bye!", "response": "See you later!", "spends_action": false,
				"effects": {"request_scene": "room_exit"}}])


func _on_conversation_finished(npc: NPCData) -> void:
	if not _inside or _closing or npc != _resident:
		return
	if _morning_dialogue_active:
		_morning_dialogue_active = false
		_complete_romance_route(npc)
		_overnight_active = false
	elif _overnight_active:
		# The illustration's dialogue ended; its own scene_finished signal will
		# advance the clock. Don't auto-start a casual conversation over the fade.
		return
	# DialogueManager emits scene_requested AFTER conversation_finished.
	call_deferred("_resume_or_exit")


func _on_scene_requested(npc: NPCData, scene_id: String) -> void:
	if _inside and npc == _resident and scene_id == "room_exit":
		_dialogue_exit_requested = true


func _on_illustration_finished(npc: NPCData, scene_id: StringName, completed: bool) -> void:
	if not _inside or not _overnight_active or npc != _resident \
			or scene_id != npc.intimacy_scene_id:
		return
	if not completed:
		_overnight_active = false
		call_deferred("_resume_or_exit")
		return
	# The fade is fully black here. Rest exactly once, then play the existing
	# post-scene JSON over this SAME room and portrait layout in the morning.
	if not GameManager.is_period(GameManager.Times.NIGHT):
		push_warning("Overnight romance finished outside the night period.")
		_overnight_active = false
		call_deferred("_resume_or_exit")
		return
	GameManager.rest()
	_morning_dialogue_active = true
	DialogueManager.request_conversation(npc, npc.morning_after_json)
	if not DialogueManager.is_active:
		# A missing dialogue file must not trap the player inside the room.
		push_warning("Morning-after dialogue missing for %s" % npc.display_name)
		DialogueManager.request_inline_conversation(npc, ["Good morning."], npc.display_name)
	if not DialogueManager.is_active:
		_morning_dialogue_active = false
		_overnight_active = false
		call_deferred("_resume_or_exit")


func _complete_romance_route(npc: NPCData) -> void:
	if npc.romance_complete_flag == &"":
		return
	var flags: Dictionary = NPCManager.get_npc_state(npc.npc_id)["flags"]
	if flags.get(npc.romance_complete_flag, false):
		return
	flags[npc.romance_complete_flag] = true
	# The shared affection system updates jealousy for existing partners.
	AffectionManager.on_romance_completed(npc.npc_id)
	# The night was spent together, so it satisfies yesterday's relationship
	# upkeep without inventing a parallel intimacy/dating score.
	AffectionManager.mark_date_completed(npc.npc_id, GameManager.get_day() - 1)
	if npc.romance_reward_id != &"":
		var bobber: BobberData = BobberManager.get_bobber(npc.romance_reward_id)
		if bobber != null and bobber.source_npc_id == npc.npc_id:
			BobberManager.unlock_bobber(npc.romance_reward_id)


func _resume_or_exit() -> void:
	if not _inside or _closing or _overnight_active:
		return
	if _dialogue_exit_requested:
		close_room()
	else:
		_start_conversation()


func close_room() -> void:
	if not _inside or _closing or _overnight_active:
		return
	_closing = true
	await _transition.iris_swap(_hide_room)
	_player.busy = false
	_inside = false
	_closing = false
	_dialogue_exit_requested = false
	_resident = null
	_gift_offered_this_visit = false
	_morning_dialogue_active = false


func _hide_room() -> void:
	hide()
	_dialogue.set_room_mode(false)
	_background.texture = null
