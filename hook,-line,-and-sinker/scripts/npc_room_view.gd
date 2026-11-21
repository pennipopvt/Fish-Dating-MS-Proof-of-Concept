class_name NPCRoomView
extends Control

# One first-person room overlay, keeping the existing DialogueUI and its
# natural conversational chaining. The romance sequence is driven by arriving
# at night after accepting an invitation, NOT by choosing a dialogue option.
# Shared room-background lighting follows GameManager's existing clock; the
# DialogueUI portrait and text live in a different layer and stay unaffected.
@export_group("Room Lighting")
@export var lighting_profile: RoomLightingProfile

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
var _prelude_active: bool = false
var _prelude_approved: bool = false


func _ready() -> void:
	# No second clock: the same signal drives day/night everywhere on the island.
	GameManager.time_changed.connect(_on_time_changed)
	_refresh_room_lighting()


func _on_time_changed(_day: int, _period: GameManager.Times) -> void:
	# Includes resting after an overnight encounter while still inside the room.
	_refresh_room_lighting()


func _refresh_room_lighting() -> void:
	if lighting_profile == null:
		_background.modulate = Color.WHITE
		return
	_background.modulate = lighting_profile.color_for_period(GameManager.get_period())


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
	_dialogue_exit_requested = false
	_prelude_active = false
	_prelude_approved = false
	_overnight_active = false
	_morning_dialogue_active = false
	_gift_offered_this_visit = false
	_inside = true
	_player.busy = true
	await _transition.iris_swap(_show_room)
	if not _try_start_overnight():
		_start_conversation()


func _show_room() -> void:
	_background.texture = _resident.room_background
	# Also refresh on entry so room previews and any future clock loads
	# always show the correct lighting on their very first frame.
	_refresh_room_lighting()
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
	# A failed or postponed prelude can be retried on a later night, not
	# repeatedly by exiting/reentering the same room that evening.
	var state: Dictionary = NPCManager.get_npc_state(_resident.npc_id)
	if not _resident.overnight_prelude_json.is_empty():
		if int(state.get("romance_prelude_attempt_day", -1)) == GameManager.get_day():
			return false
		state["romance_prelude_attempt_day"] = GameManager.get_day()
		_overnight_active = true
		_prelude_active = true
		_prelude_approved = false
		DialogueManager.request_conversation(_resident, _resident.overnight_prelude_json)
		if DialogueManager.is_active:
			return true
		_prelude_active = false
		_overnight_active = false
		return false
	# Other characters may choose to use the existing direct-entry behavior.
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
	if _prelude_active:
		_prelude_active = false
		# DialogueManager emits scene_requested AFTER conversation_finished;
		# let the room interpret the prelude's result before leaving.
		call_deferred("_resolve_prelude")
		return
	if _morning_dialogue_active:
		_morning_dialogue_active = false
		_complete_romance_route(npc)
		_overnight_active = false
		_dialogue_exit_requested = true
		# Let the illustration fade finish before starting the room iris.
		call_deferred("_close_after_morning")
		return
	if _overnight_active:
		# The illustration owns its dialogue until it signals scene_finished.
		return
	# Room conversations do not automatically start another greeting.
	call_deferred("_resume_or_exit")


func _on_scene_requested(npc: NPCData, scene_id: String) -> void:
	if not _inside or npc != _resident:
		return
	if scene_id == "room_exit":
		_dialogue_exit_requested = true
		return
	if scene_id == "room_overnight_ready" and _overnight_active and not _prelude_active:
		if _illustration != null and _illustration.start_scene(npc):
			_prelude_approved = true
		else:
			push_warning("Unable to start invited evening for %s" % npc.display_name)


func _resolve_prelude() -> void:
	if not _inside or _closing or _prelude_approved:
		return
	# Either the player declined, the mood went wrong or the dialogue failed.
	# Preserve the accepted invitation so they can try a later night.
	_overnight_active = false
	_dialogue_exit_requested = true
	_resume_or_exit()


func _close_after_morning() -> void:
	if not _inside or _closing:
		return
	# The morning dialogue usually lasts longer than the scene's fade.
	# This also handles a fast-forward / debug skip at full black.
	while _illustration != null and _illustration._transitioning and is_inside_tree():
		await get_tree().process_frame
	if _inside and not _closing:
		close_room()


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
	AffectionManager.mark_date_completed(npc.npc_id, GameManager.get_day())
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
	# The completed night was recorded before the new day began.
	if npc.romance_reward_id != &"":
		var bobber: BobberData = BobberManager.get_bobber(npc.romance_reward_id)
		if bobber != null and bobber.source_npc_id == npc.npc_id:
			BobberManager.unlock_bobber(npc.romance_reward_id)


func _resume_or_exit() -> void:
	if not _inside or _closing or _overnight_active or DialogueManager.is_active:
		return
	# A fresh visit starts a fresh greeting. Continuing to talk in the SAME
	# visit uses authored "Something else..." / topics nodes instead.
	close_room()


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
	_prelude_active = false
	_prelude_approved = false
	_overnight_active = false


func _hide_room() -> void:
	hide()
	_dialogue.set_room_mode(false)
	_background.texture = null
