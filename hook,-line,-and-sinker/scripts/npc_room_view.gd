class_name NPCRoomView
extends Control

# A first-person room overlay, not a replacement world or dialogue system.
# The existing DialogueUI remains the only conversation renderer.
@onready var _background: TextureRect = $Background
var _dialogue: DialogueUI
var _transition: SeaDiveTransition
var _player: Player
var _resident: NPCData
var _inside: bool = false
var _closing: bool = false
var _dialogue_exit_requested: bool = false


func configure(dialogue: DialogueUI, transition: SeaDiveTransition, player: Player) -> void:
	_dialogue = dialogue
	_transition = transition
	_player = player
	DialogueManager.conversation_finished.connect(_on_conversation_finished)
	DialogueManager.scene_requested.connect(_on_scene_requested)


func open_room(npc: NPCData) -> void:
	if npc == null or _inside or _closing or _transition.transitioning or DialogueManager.is_active:
		return
	_resident = npc
	_inside = true
	_player.busy = true
	await _transition.iris_swap(_show_room)
	_start_conversation()


func _show_room() -> void:
	_background.texture = _resident.room_background
	_dialogue.set_room_mode(true)
	show()


func _start_conversation() -> void:
	if not _inside or _closing or DialogueManager.is_active:
		return
	# Mirror NPCInteractable's existing gift branch without spawning an actor.
	if _player.held_item != null:
		var gift_path: String = NPCManager.get_gift_encounter_path(_resident, _player.held_item)
		if not gift_path.is_empty():
			DialogueManager.request_conversation(_resident, gift_path, _player)
			return
	DialogueManager.request_conversation(_resident)
	if not DialogueManager.is_active:
		# No eligible JSON yet: still allow leaving without trapping Penni.
		DialogueManager.request_inline_conversation(_resident, ["Oh, hi, Penni!"], "",
			[{"text": "Bye!", "response": "See you later!", "spends_action": false,
				"effects": {"request_scene": "room_exit"}}])


func _on_conversation_finished(npc: NPCData) -> void:
	if not _inside or _closing or npc != _resident:
		return
	# A dialogue effect may request a cutscene/exit in scene_requested; allow
	# that signal to fire before deciding whether to show the next menu.
	call_deferred("_resume_or_exit")


func _on_scene_requested(npc: NPCData, scene_id: String) -> void:
	if _inside and npc == _resident and not scene_id.is_empty():
		_dialogue_exit_requested = true


func _resume_or_exit() -> void:
	if not _inside or _closing:
		return
	if _dialogue_exit_requested:
		close_room()
	else:
		_start_conversation()


func close_room() -> void:
	if not _inside or _closing:
		return
	_closing = true
	await _transition.iris_swap(_hide_room)
	_player.busy = false
	_inside = false
	_closing = false
	_dialogue_exit_requested = false
	_resident = null


func _hide_room() -> void:
	hide()
	_dialogue.set_room_mode(false)
	_background.texture = null
